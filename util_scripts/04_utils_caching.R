# ==================================================================================================
# Script: 04_utils_caching.R
# Purpose: Validated, dependency-aware, recoverable cache persistence.
# ==================================================================================================


CACHE_MANIFEST_SCHEMA_VERSION <- 1L
CACHE_MANIFEST_FILENAME <- "cache_manifest.yaml"


cache_timestamp <- function(timestamp = Sys.time()) {
  if (exists("format_pipeline_timestamp", mode = "function")) {
    return(format_pipeline_timestamp(timestamp))
  }
  timestamp <- as.POSIXct(timestamp, tz = "UTC")
  if (length(timestamp) != 1L || is.na(timestamp)) {
    stop("timestamp must be one valid date-time value.", call. = FALSE)
  }
  paste0(format(timestamp, "%Y-%m-%dT%H:%M:%OS3", tz = "UTC"), "Z")
}


setup_cache_dir <- function(dataset_dir_path) {
  if (
    length(dataset_dir_path) != 1L || is.na(dataset_dir_path) ||
      !nzchar(trimws(dataset_dir_path))
  ) {
    stop("dataset_dir_path must be one non-empty path.", call. = FALSE)
  }
  cache_dir_path <- file.path(dataset_dir_path, "cache")
  dir.create(cache_dir_path, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(cache_dir_path)) {
    stop("Could not create cache directory: ", cache_dir_path, call. = FALSE)
  }
  cache_dir_path
}


.validate_cache_filename <- function(data_file_name) {
  if (
    length(data_file_name) != 1L || is.na(data_file_name) ||
      !nzchar(trimws(data_file_name)) ||
      !identical(basename(data_file_name), data_file_name)
  ) {
    stop("Cache filename must be one non-empty basename.", call. = FALSE)
  }
  data_file_name
}


cache_manifest_paths <- function(dataset_dir_path) {
  cache_dir <- setup_cache_dir(dataset_dir_path)
  primary <- file.path(cache_dir, CACHE_MANIFEST_FILENAME)
  list(
    cache_dir = cache_dir,
    primary = primary,
    backup = paste0(primary, ".bak"),
    lock = paste0(primary, ".lock")
  )
}


new_cache_manifest <- function(timestamp = Sys.time()) {
  list(
    schema_version = CACHE_MANIFEST_SCHEMA_VERSION,
    revision = 0L,
    updated_at = cache_timestamp(timestamp),
    artifacts = list()
  )
}


.validate_cache_manifest_record <- function(record, filename) {
  required <- c(
    "artifact_type", "sample", "producer", "created_at", "checksum",
    "size_bytes", "dependency_fingerprint", "dependencies", "validation"
  )
  missing <- setdiff(required, names(record))
  if (length(missing) > 0L) {
    stop(
      "Cache manifest record '", filename, "' is missing: ",
      paste(missing, collapse = ", "), ".",
      call. = FALSE
    )
  }
  for (field in c("artifact_type", "created_at", "checksum")) {
    value <- record[[field]]
    if (length(value) != 1L || is.na(value) || !nzchar(as.character(value))) {
      stop("Cache manifest record '", filename, "' has invalid ", field, ".", call. = FALSE)
    }
  }
  for (field in c("sample", "producer", "dependency_fingerprint")) {
    value <- record[[field]]
    if (!is.null(value) && (length(value) != 1L || is.na(value))) {
      stop("Cache manifest record '", filename, "' has invalid ", field, ".", call. = FALSE)
    }
  }
  if (
    length(record$size_bytes) != 1L || is.na(record$size_bytes) ||
      record$size_bytes < 0
  ) {
    stop("Cache manifest record '", filename, "' has invalid size_bytes.", call. = FALSE)
  }
  if (!is.list(record$dependencies) || !is.list(record$validation)) {
    stop("Cache manifest dependencies and validation must be lists.", call. = FALSE)
  }
  if (!is.null(record$previous)) {
    .validate_cache_manifest_record(record$previous, paste0(filename, " previous"))
  }
  invisible(TRUE)
}


validate_cache_manifest <- function(manifest) {
  required <- c("schema_version", "revision", "updated_at", "artifacts")
  missing <- setdiff(required, names(manifest))
  if (length(missing) > 0L) {
    stop("Cache manifest is missing: ", paste(missing, collapse = ", "), ".", call. = FALSE)
  }
  if (!identical(as.integer(manifest$schema_version), CACHE_MANIFEST_SCHEMA_VERSION)) {
    stop(
      "Unsupported cache-manifest schema version: ", manifest$schema_version,
      ". Expected ", CACHE_MANIFEST_SCHEMA_VERSION, ".",
      call. = FALSE
    )
  }
  if (
    length(manifest$revision) != 1L || is.na(manifest$revision) ||
      manifest$revision < 0 || manifest$revision != as.integer(manifest$revision)
  ) {
    stop("Cache manifest has an invalid revision.", call. = FALSE)
  }
  if (length(manifest$updated_at) != 1L || is.na(manifest$updated_at)) {
    stop("Cache manifest has an invalid updated_at value.", call. = FALSE)
  }
  if (!is.list(manifest$artifacts)) {
    stop("Cache manifest artifacts must be a named list.", call. = FALSE)
  }
  if (
    length(manifest$artifacts) > 0L &&
      (is.null(names(manifest$artifacts)) || any(!nzchar(names(manifest$artifacts))) ||
        anyDuplicated(names(manifest$artifacts)))
  ) {
    stop("Cache manifest artifact names must be non-empty and unique.", call. = FALSE)
  }
  for (filename in names(manifest$artifacts)) {
    .validate_cache_filename(filename)
    .validate_cache_manifest_record(manifest$artifacts[[filename]], filename)
  }
  invisible(TRUE)
}


acquire_cache_manifest_lock <- function(
  lock_path,
  timeout_seconds = 5,
  stale_after_seconds = 300,
  poll_seconds = 0.02
) {
  deadline <- Sys.time() + timeout_seconds
  repeat {
    if (dir.create(lock_path, showWarnings = FALSE)) return(invisible(lock_path))
    lock_info <- file.info(lock_path)
    lock_age <- as.numeric(difftime(Sys.time(), lock_info$mtime, units = "secs"))
    if (is.finite(lock_age) && lock_age > stale_after_seconds) {
      unlink(lock_path, recursive = TRUE, force = TRUE)
      next
    }
    if (Sys.time() >= deadline) {
      stop("Timed out waiting for cache-manifest lock: ", lock_path, call. = FALSE)
    }
    Sys.sleep(poll_seconds)
  }
}


load_cache_manifest <- function(dataset_dir_path, recover = TRUE) {
  paths <- cache_manifest_paths(dataset_dir_path)
  if (!file.exists(paths$primary) && !file.exists(paths$backup)) {
    return(new_cache_manifest())
  }
  read_manifest <- function(path) {
    manifest <- yaml::read_yaml(path)
    validate_cache_manifest(manifest)
    manifest
  }
  primary_error <- "primary cache manifest is missing"
  if (file.exists(paths$primary)) {
    manifest <- tryCatch(read_manifest(paths$primary), error = identity)
    if (!inherits(manifest, "error")) return(manifest)
    primary_error <- conditionMessage(manifest)
  }
  if (isTRUE(recover) && file.exists(paths$backup)) {
    backup <- tryCatch(read_manifest(paths$backup), error = identity)
    if (!inherits(backup, "error")) {
      if (!file.copy(paths$backup, paths$primary, overwrite = TRUE)) {
        stop("Could not restore cache manifest from backup.", call. = FALSE)
      }
      warning(
        "Recovered cache manifest from backup because ", primary_error, ".",
        call. = FALSE
      )
      return(backup)
    }
  }
  stop("Could not load cache manifest: ", primary_error, ".", call. = FALSE)
}


.save_cache_manifest_unlocked <- function(manifest, dataset_dir_path, timestamp = Sys.time()) {
  validate_cache_manifest(manifest)
  paths <- cache_manifest_paths(dataset_dir_path)
  saved <- manifest
  saved$revision <- as.integer(saved$revision) + 1L
  saved$updated_at <- cache_timestamp(timestamp)
  validate_cache_manifest(saved)

  temporary <- tempfile(
    pattern = ".cache-manifest-",
    tmpdir = paths$cache_dir,
    fileext = ".tmp"
  )
  on.exit(if (file.exists(temporary)) file.remove(temporary), add = TRUE)
  yaml::write_yaml(saved, temporary)
  validate_cache_manifest(yaml::read_yaml(temporary))

  if (file.exists(paths$backup) && !file.remove(paths$backup)) {
    stop("Could not replace the cache-manifest backup.", call. = FALSE)
  }
  had_primary <- file.exists(paths$primary)
  if (had_primary && !file.rename(paths$primary, paths$backup)) {
    stop("Could not move the current cache manifest to its backup.", call. = FALSE)
  }
  if (!file.rename(temporary, paths$primary)) {
    if (had_primary && file.exists(paths$backup)) {
      file.rename(paths$backup, paths$primary)
    }
    stop("Could not install the new cache manifest.", call. = FALSE)
  }
  persisted <- yaml::read_yaml(paths$primary)
  validate_cache_manifest(persisted)
  persisted
}


save_cache_manifest_atomic <- function(
  manifest,
  dataset_dir_path,
  timestamp = Sys.time(),
  lock_timeout_seconds = 5,
  stale_lock_seconds = 300
) {
  paths <- cache_manifest_paths(dataset_dir_path)
  acquire_cache_manifest_lock(
    paths$lock,
    timeout_seconds = lock_timeout_seconds,
    stale_after_seconds = stale_lock_seconds
  )
  on.exit(unlink(paths$lock, recursive = TRUE, force = TRUE), add = TRUE)
  current <- load_cache_manifest(dataset_dir_path)
  if (!identical(as.integer(current$revision), as.integer(manifest$revision))) {
    stop(
      "Cache manifest revision conflict: disk is ", current$revision,
      " but the caller has ", manifest$revision, ".",
      call. = FALSE
    )
  }
  .save_cache_manifest_unlocked(manifest, dataset_dir_path, timestamp)
}


.cache_md5 <- function(path) {
  if (!file.exists(path)) return(NULL)
  unname(as.character(tools::md5sum(path)[[1]]))
}


cache_hash_value <- function(value) {
  path <- tempfile(fileext = ".rds")
  on.exit(if (file.exists(path)) file.remove(path), add = TRUE)
  saveRDS(value, path, version = 2)
  .cache_md5(path)
}


cache_dependency_spec <- function(
  files = character(),
  values = list(),
  artifacts = character(),
  dataset_dir_path = NULL
) {
  if (length(files) > 0L && is.null(names(files))) names(files) <- basename(files)
  if (length(values) > 0L && is.null(names(values))) {
    stop("Dependency values must be a named list.", call. = FALSE)
  }
  file_records <- lapply(files, function(path) {
    if (!file.exists(path)) {
      stop("Dependency file does not exist: ", path, call. = FALSE)
    }
    info <- file.info(path)
    list(size_bytes = unname(info$size), checksum = .cache_md5(path))
  })
  value_records <- lapply(values, function(value) list(hash = cache_hash_value(value)))
  artifact_records <- list()
  if (length(artifacts) > 0L) {
    if (is.null(dataset_dir_path)) {
      stop("dataset_dir_path is required for artifact dependencies.", call. = FALSE)
    }
    if (is.null(names(artifacts))) names(artifacts) <- artifacts
    manifest <- load_cache_manifest(dataset_dir_path)
    artifact_records <- lapply(artifacts, function(filename) {
      record <- manifest$artifacts[[filename]]
      if (is.null(record)) {
        stop("Dependency cache is not registered: ", filename, call. = FALSE)
      }
      list(
        filename = filename,
        checksum = record$checksum,
        dependency_fingerprint = record$dependency_fingerprint
      )
    })
  }
  list(files = file_records, values = value_records, artifacts = artifact_records)
}


cache_dependency_fingerprint <- function(dependencies) {
  if (is.null(dependencies)) return(NULL)
  if (!is.list(dependencies)) stop("dependencies must be a list.", call. = FALSE)
  cache_hash_value(dependencies)
}


infer_cache_artifact <- function(data_file_name) {
  patterns <- list(
    filtered_expression = "^expmat_filt_(.+)[.]qs2$",
    clustered_cells = "^cells_filt_clust_res_[^_]+_(.+)[.]qs2$",
    cna_matrix = "^cna_matrix_(.+)[.]qs2$",
    cna_hclust = "^hclust_(.+)[.]qs2$",
    cna_signal_correlation = "^cna_sig_cor_(.+)_subclone_[0-9]+[.]qs2$"
  )
  for (artifact_type in names(patterns)) {
    match <- regexec(patterns[[artifact_type]], data_file_name)
    values <- regmatches(data_file_name, match)[[1]]
    if (length(values) > 0L) {
      return(list(artifact_type = artifact_type, sample = values[[2]]))
    }
  }
  list(artifact_type = "generic", sample = NULL)
}


validate_cache_object <- function(object, artifact_type = "generic", filename = NULL) {
  location <- if (is.null(filename)) "Cache object" else paste0("Cache '", filename, "'")
  summary <- list(class = class(object)[[1]], length = length(object))

  if (identical(artifact_type, "filtered_expression")) {
    matrix_like <- is.matrix(object) || methods::is(object, "Matrix")
    values <- if (methods::is(object, "Matrix")) object@x else as.vector(object)
    if (!matrix_like || !is.numeric(values) || any(dim(object) < 1L)) {
      stop(location, " must be a non-empty numeric matrix.", call. = FALSE)
    }
    if (any(!is.finite(values))) stop(location, " contains non-finite expression values.", call. = FALSE)
    if (is.null(rownames(object)) || is.null(colnames(object))) {
      stop(location, " must have gene and cell names.", call. = FALSE)
    }
    summary <- list(class = class(object)[[1]], rows = nrow(object), columns = ncol(object))
  } else if (identical(artifact_type, "clustered_cells")) {
    # This cache is enriched in place through clustering, annotation and CNA.
    # A cell identifier is the invariant schema; stage-specific columns are
    # validated whenever present.
    required <- "cell_name"
    if (!is.data.frame(object) || !all(required %in% names(object)) || nrow(object) < 1L) {
      stop(location, " is missing required clustered-cell columns or rows.", call. = FALSE)
    }
    if (anyNA(object$cell_name) || anyDuplicated(object$cell_name)) {
      stop(location, " has missing or duplicate cell identifiers.", call. = FALSE)
    }
    coordinate_columns <- intersect(c("umap1", "umap2"), names(object))
    invalid_coordinates <- any(vapply(
      coordinate_columns,
      function(column_name) {
        column <- object[[column_name]]
        !is.numeric(column) || any(!is.finite(column))
      },
      logical(1)
    ))
    if (invalid_coordinates || ("clust" %in% names(object) && anyNA(object$clust))) {
      stop(location, " has invalid UMAP or cluster values.", call. = FALSE)
    }
    summary <- list(class = class(object)[[1]], rows = nrow(object), columns = ncol(object))
  } else if (identical(artifact_type, "cna_matrix")) {
    required <- c("gene", "chr", "start_pos")
    if (!is.data.frame(object) || !all(required %in% names(object)) || nrow(object) < 1L) {
      stop(location, " is not a non-empty CNA matrix table.", call. = FALSE)
    }
    cell_columns <- setdiff(names(object), required)
    if (length(cell_columns) < 1L || anyDuplicated(object$gene)) {
      stop(location, " has no cell columns or has duplicate genes.", call. = FALSE)
    }
    valid_numeric <- vapply(cell_columns, function(column_name) {
      column <- object[[column_name]]
      is.numeric(column) && all(is.finite(column))
    }, logical(1))
    if (!all(valid_numeric)) stop(location, " contains non-numeric or non-finite CNA values.", call. = FALSE)
    summary <- list(class = class(object)[[1]], genes = nrow(object), cells = length(cell_columns))
  } else if (identical(artifact_type, "cna_hclust")) {
    if (!inherits(object, "hclust") || length(object$labels) < 2L || any(!is.finite(object$height))) {
      stop(location, " is not a valid hierarchical clustering result.", call. = FALSE)
    }
    summary <- list(class = "hclust", cells = length(object$labels))
  } else if (identical(artifact_type, "cna_signal_correlation")) {
    required <- c("cell_name", "cna_signal", "cna_cor")
    if (!is.data.frame(object) || !all(required %in% names(object)) || nrow(object) < 1L) {
      stop(location, " is missing required signal/correlation columns or rows.", call. = FALSE)
    }
    if (any(!is.finite(object$cna_signal)) || any(!is.finite(object$cna_cor))) {
      stop(location, " contains non-finite signal/correlation values.", call. = FALSE)
    }
    summary <- list(class = class(object)[[1]], rows = nrow(object), columns = ncol(object))
  }
  summary
}


.cache_artifact_paths <- function(dataset_dir_path, data_file_name) {
  filename <- .validate_cache_filename(data_file_name)
  cache_dir <- setup_cache_dir(dataset_dir_path)
  primary <- file.path(cache_dir, filename)
  list(primary = primary, backup = paste0(primary, ".bak"), cache_dir = cache_dir)
}


.cache_record_matches <- function(record, path, dependencies = NULL) {
  if (is.null(record) || !file.exists(path)) return(FALSE)
  checksum_matches <- identical(.cache_md5(path), as.character(record$checksum))
  size_matches <- identical(as.numeric(file.info(path)$size), as.numeric(record$size_bytes))
  dependency_matches <- is.null(dependencies) || identical(
    cache_dependency_fingerprint(dependencies),
    record$dependency_fingerprint
  )
  checksum_matches && size_matches && dependency_matches
}


cache_save_data <- function(
  data_file,
  data_file_name,
  dataset_dir_path,
  nthreads = 4,
  artifact_type = NULL,
  sample = NULL,
  dependencies = NULL,
  producer = NULL,
  timestamp = Sys.time()
) {
  paths <- .cache_artifact_paths(dataset_dir_path, data_file_name)
  manifest_paths <- cache_manifest_paths(dataset_dir_path)
  inferred <- infer_cache_artifact(data_file_name)
  if (is.null(artifact_type)) artifact_type <- inferred$artifact_type
  if (is.null(sample)) sample <- inferred$sample

  acquire_cache_manifest_lock(manifest_paths$lock)
  on.exit(unlink(manifest_paths$lock, recursive = TRUE, force = TRUE), add = TRUE)
  manifest <- load_cache_manifest(dataset_dir_path)
  old_record <- manifest$artifacts[[data_file_name]]
  if (is.null(dependencies) && !is.null(old_record)) dependencies <- old_record$dependencies
  if (is.null(producer) && !is.null(old_record)) producer <- old_record$producer

  temporary <- tempfile(pattern = paste0(".", data_file_name, "-"), tmpdir = paths$cache_dir, fileext = ".tmp")
  on.exit(if (file.exists(temporary)) file.remove(temporary), add = TRUE)
  qs2::qs_save(data_file, temporary, nthreads = nthreads)
  verified <- qs2::qs_read(temporary, nthreads = nthreads)
  validation <- validate_cache_object(verified, artifact_type, data_file_name)

  if (file.exists(paths$backup) && !file.remove(paths$backup)) {
    stop("Could not replace prior cache backup: ", data_file_name, call. = FALSE)
  }
  had_primary <- file.exists(paths$primary)
  if (had_primary && !file.rename(paths$primary, paths$backup)) {
    stop("Could not move prior cache to backup: ", data_file_name, call. = FALSE)
  }
  if (!file.rename(temporary, paths$primary)) {
    if (had_primary && file.exists(paths$backup)) file.rename(paths$backup, paths$primary)
    stop("Could not install cache artifact: ", data_file_name, call. = FALSE)
  }

  info <- file.info(paths$primary)
  record <- list(
    artifact_type = artifact_type,
    sample = sample,
    producer = producer,
    created_at = cache_timestamp(timestamp),
    checksum = .cache_md5(paths$primary),
    size_bytes = unname(info$size),
    dependency_fingerprint = cache_dependency_fingerprint(dependencies),
    dependencies = if (is.null(dependencies)) list() else dependencies,
    validation = validation
  )
  if (!is.null(old_record)) {
    old_record$previous <- NULL
    record$previous <- old_record
  }
  manifest$artifacts[[data_file_name]] <- record
  manifest_result <- tryCatch(
    .save_cache_manifest_unlocked(manifest, dataset_dir_path, timestamp),
    error = identity
  )
  if (inherits(manifest_result, "error")) {
    file.remove(paths$primary)
    if (had_primary && file.exists(paths$backup)) file.rename(paths$backup, paths$primary)
    stop("Cache artifact was rolled back because its manifest update failed: ", conditionMessage(manifest_result), call. = FALSE)
  }
  invisible(record)
}


.recover_cache_artifact <- function(
  data_file_name,
  dataset_dir_path,
  manifest,
  record,
  dependencies = NULL
) {
  paths <- .cache_artifact_paths(dataset_dir_path, data_file_name)
  previous <- record$previous
  candidate <- if (
    !is.null(previous) &&
      .cache_record_matches(previous, paths$backup, dependencies = dependencies)
  ) previous else if (
    .cache_record_matches(record, paths$backup, dependencies = dependencies)
  ) record else NULL
  if (is.null(candidate)) return(NULL)

  manifest_paths <- cache_manifest_paths(dataset_dir_path)
  acquire_cache_manifest_lock(manifest_paths$lock)
  on.exit(unlink(manifest_paths$lock, recursive = TRUE, force = TRUE), add = TRUE)
  current_manifest <- load_cache_manifest(dataset_dir_path)
  current_record <- current_manifest$artifacts[[data_file_name]]
  if (is.null(current_record) || !identical(current_record$checksum, record$checksum)) {
    stop("Cache manifest changed while attempting artifact recovery.", call. = FALSE)
  }
  if (file.exists(paths$primary) && !file.remove(paths$primary)) {
    stop("Could not remove corrupt cache artifact during recovery.", call. = FALSE)
  }
  if (!file.rename(paths$backup, paths$primary)) {
    stop("Could not restore the previous cache artifact.", call. = FALSE)
  }
  candidate$previous <- NULL
  if (!identical(candidate$checksum, record$checksum)) {
    current_manifest$artifacts[[data_file_name]] <- candidate
    .save_cache_manifest_unlocked(current_manifest, dataset_dir_path)
  }
  warning("Recovered previous valid cache artifact: ", data_file_name, call. = FALSE)
  candidate
}


cache_load_data <- function(
  data_file_name,
  dataset_dir_path,
  nthreads = 4,
  dependencies = NULL,
  recover = TRUE
) {
  paths <- .cache_artifact_paths(dataset_dir_path, data_file_name)
  if (!file.exists(paths$primary)) {
    stop(
      "Expected cached file not found: '", data_file_name, "'. Earlier work may be incomplete or invalidated.",
      call. = FALSE
    )
  }
  manifest <- load_cache_manifest(dataset_dir_path)
  record <- manifest$artifacts[[data_file_name]]
  if (is.null(record)) {
    stop(
      "Cache artifact is untracked and cannot be safely reused: '", data_file_name,
      "'. Rerun its producing pipeline step.",
      call. = FALSE
    )
  }
  if (!.cache_record_matches(record, paths$primary, dependencies)) {
    if (isTRUE(recover)) {
      recovered <- .recover_cache_artifact(
        data_file_name,
        dataset_dir_path,
        manifest,
        record,
        dependencies = dependencies
      )
      if (!is.null(recovered)) record <- recovered else {
        stop("Cache artifact failed checksum, size, or dependency validation: '", data_file_name, "'.", call. = FALSE)
      }
    } else {
      stop("Cache artifact failed checksum, size, or dependency validation: '", data_file_name, "'.", call. = FALSE)
    }
  }
  read_and_validate <- function() {
    object <- qs2::qs_read(paths$primary, nthreads = nthreads)
    validate_cache_object(object, record$artifact_type, data_file_name)
    object
  }
  object <- tryCatch(read_and_validate(), error = identity)
  if (inherits(object, "error") && isTRUE(recover)) {
    recovered <- .recover_cache_artifact(
      data_file_name,
      dataset_dir_path,
      manifest,
      record,
      dependencies = dependencies
    )
    if (!is.null(recovered)) object <- tryCatch(read_and_validate(), error = identity)
  }
  if (inherits(object, "error")) {
    stop(
      "Cache artifact could not be read or failed structural validation: '",
      data_file_name, "': ", conditionMessage(object),
      call. = FALSE
    )
  }
  object
}


cache_check_exists <- function(data_file_name, dataset_dir_path) {
  paths <- .cache_artifact_paths(dataset_dir_path, data_file_name)
  file.exists(paths$primary)
}


cache_check_valid <- function(data_file_name, dataset_dir_path, dependencies = NULL) {
  isTRUE(tryCatch({
    cache_load_data(
      data_file_name,
      dataset_dir_path,
      nthreads = 1,
      dependencies = dependencies,
      recover = FALSE
    )
    TRUE
  }, error = function(error) FALSE))
}


cache_invalidate_artifacts <- function(data_file_names, dataset_dir_path) {
  data_file_names <- unique(vapply(data_file_names, .validate_cache_filename, character(1)))
  manifest_paths <- cache_manifest_paths(dataset_dir_path)
  acquire_cache_manifest_lock(manifest_paths$lock)
  on.exit(unlink(manifest_paths$lock, recursive = TRUE, force = TRUE), add = TRUE)
  manifest <- load_cache_manifest(dataset_dir_path)
  removed <- character()
  for (filename in data_file_names) {
    paths <- .cache_artifact_paths(dataset_dir_path, filename)
    targets <- c(paths$primary, paths$backup)
    existing <- targets[file.exists(targets)]
    if (length(existing) > 0L && all(file.remove(existing))) removed <- c(removed, filename)
    manifest$artifacts[filename] <- NULL
  }
  .save_cache_manifest_unlocked(manifest, dataset_dir_path)
  unique(removed)
}


# Return all cache filenames for one sample and one or more artifact families.
# Registered and untracked legacy files are both included so invalidation does
# not leave a stale file that could later be mistaken for a valid result.
cache_sample_artifacts <- function(
  sample_name,
  dataset_dir_path,
  artifact_types = c("cna_matrix", "cna_hclust", "cna_signal_correlation")
) {
  if (length(sample_name) != 1L || is.na(sample_name) || !nzchar(sample_name)) {
    stop("sample_name must be one non-empty value.", call. = FALSE)
  }
  supported <- c(
    "filtered_expression", "clustered_cells", "cna_matrix",
    "cna_hclust", "cna_signal_correlation"
  )
  unknown <- setdiff(artifact_types, supported)
  if (length(unknown) > 0L) {
    stop("Unknown cache artifact types: ", paste(unknown, collapse = ", "), ".", call. = FALSE)
  }

  cache_dir <- setup_cache_dir(dataset_dir_path)
  manifest <- load_cache_manifest(dataset_dir_path)
  primary_files <- list.files(cache_dir, pattern = "[.]qs2$", full.names = FALSE)
  backup_files <- sub(
    "[.]bak$",
    "",
    list.files(cache_dir, pattern = "[.]qs2[.]bak$", full.names = FALSE)
  )
  filenames <- unique(c(names(manifest$artifacts), primary_files, backup_files))
  matches <- vapply(filenames, function(filename) {
    inferred <- infer_cache_artifact(filename)
    identical(inferred$sample, sample_name) && inferred$artifact_type %in% artifact_types
  }, logical(1))
  filenames[matches]
}


cache_invalidate_sample <- function(
  sample_name,
  dataset_dir_path,
  artifact_types = c("cna_matrix", "cna_hclust", "cna_signal_correlation")
) {
  filenames <- cache_sample_artifacts(
    sample_name,
    dataset_dir_path,
    artifact_types = artifact_types
  )
  if (length(filenames) == 0L) return(character())
  cache_invalidate_artifacts(filenames, dataset_dir_path)
}


clear_cache_dir <- function(dataset_dir_path) {
  cache_dir_path <- setup_cache_dir(dataset_dir_path)
  entries <- list.files(cache_dir_path, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  if (length(entries) > 0L) unlink(entries, recursive = TRUE, force = TRUE)
  invisible(cache_dir_path)
}
