# ==================================================================================================
# Script: 11_utils_storage.R
# Purpose: Safe post-completion cache retirement and dataset archive lifecycle.
# ==================================================================================================


DATASET_STORAGE_SCHEMA_VERSION <- 1L
DATASET_STORAGE_IMPLEMENTATION <- "dataset-storage-v1"
DATASET_STORAGE_STATUSES <- c("active", "cleaning", "archived", "cleanup_failed")


dataset_storage_timestamp <- function(timestamp = Sys.time()) {
  pipeline_state_timestamp(timestamp)
}


new_dataset_storage_state <- function(dataset_id, timestamp = Sys.time()) {
  dataset_id <- trimws(as.character(dataset_id))
  if (length(dataset_id) != 1L || is.na(dataset_id) || !nzchar(dataset_id)) {
    stop("dataset_id must be one non-empty identifier.", call. = FALSE)
  }
  list(
    schema_version = DATASET_STORAGE_SCHEMA_VERSION,
    dataset_id = dataset_id,
    revision = 0L,
    status = "active",
    updated_at = dataset_storage_timestamp(timestamp),
    reason = NULL,
    details = list()
  )
}


validate_dataset_storage_state <- function(state, dataset_id = NULL) {
  required <- c(
    "schema_version", "dataset_id", "revision", "status", "updated_at",
    "reason", "details"
  )
  missing <- setdiff(required, names(state))
  if (length(missing) > 0L) {
    stop("Dataset storage state is missing: ", paste(missing, collapse = ", "), ".", call. = FALSE)
  }
  if (!identical(as.integer(state$schema_version), DATASET_STORAGE_SCHEMA_VERSION)) {
    stop("Unsupported dataset storage-state schema version.", call. = FALSE)
  }
  if (
    length(state$dataset_id) != 1L || is.na(state$dataset_id) ||
      !nzchar(trimws(as.character(state$dataset_id)))
  ) {
    stop("Dataset storage state has an invalid dataset_id.", call. = FALSE)
  }
  if (!is.null(dataset_id) && !identical(as.character(state$dataset_id), as.character(dataset_id))) {
    stop("Dataset storage state belongs to a different dataset.", call. = FALSE)
  }
  if (
    length(state$revision) != 1L || is.na(state$revision) ||
      state$revision < 0L || state$revision != as.integer(state$revision)
  ) {
    stop("Dataset storage state has an invalid revision.", call. = FALSE)
  }
  if (length(state$status) != 1L || !(state$status %in% DATASET_STORAGE_STATUSES)) {
    stop("Dataset storage state has an unsupported status.", call. = FALSE)
  }
  if (length(state$updated_at) != 1L || is.na(state$updated_at) || !nzchar(state$updated_at)) {
    stop("Dataset storage state has an invalid updated_at value.", call. = FALSE)
  }
  if (!is.null(state$reason) && (length(state$reason) != 1L || is.na(state$reason))) {
    stop("Dataset storage-state reason must be NULL or one value.", call. = FALSE)
  }
  if (identical(state$status, "cleanup_failed") && (is.null(state$reason) || !nzchar(state$reason))) {
    stop("A failed cleanup requires an actionable reason.", call. = FALSE)
  }
  if (!is.list(state$details)) {
    stop("Dataset storage-state details must be a list.", call. = FALSE)
  }
  invisible(TRUE)
}


dataset_storage_state_paths <- function(
  dataset_dir_path,
  state_filename = "storage_state.yaml"
) {
  if (!dir.exists(dataset_dir_path)) {
    stop("Dataset directory does not exist: ", dataset_dir_path, call. = FALSE)
  }
  primary <- file.path(dataset_dir_path, state_filename)
  list(
    primary = primary,
    backup = paste0(primary, ".bak"),
    lock = paste0(primary, ".lock"),
    operation_lock = file.path(dataset_dir_path, ".storage-operation.lock")
  )
}


load_dataset_storage_state <- function(
  dataset_dir_path,
  dataset_id = NULL,
  state_filename = "storage_state.yaml",
  recover = TRUE
) {
  paths <- dataset_storage_state_paths(dataset_dir_path, state_filename)
  read_state <- function(path) {
    state <- yaml::read_yaml(path)
    validate_dataset_storage_state(state, dataset_id)
    state
  }
  primary_error <- "primary storage-state file is missing"
  if (file.exists(paths$primary)) {
    state <- tryCatch(read_state(paths$primary), error = identity)
    if (!inherits(state, "error")) return(state)
    primary_error <- conditionMessage(state)
  }
  if (isTRUE(recover) && file.exists(paths$backup)) {
    state <- tryCatch(read_state(paths$backup), error = identity)
    if (!inherits(state, "error")) {
      if (!file.copy(paths$backup, paths$primary, overwrite = TRUE)) {
        stop("Could not restore dataset storage state from backup.", call. = FALSE)
      }
      warning("Recovered dataset storage state because ", primary_error, ".", call. = FALSE)
      return(state)
    }
  }
  stop("Could not load dataset storage state: ", primary_error, ".", call. = FALSE)
}


load_or_initialize_dataset_storage_state <- function(
  dataset_dir_path,
  dataset_id,
  state_filename = "storage_state.yaml",
  timestamp = Sys.time()
) {
  paths <- dataset_storage_state_paths(dataset_dir_path, state_filename)
  if (!file.exists(paths$primary) && !file.exists(paths$backup)) {
    state <- new_dataset_storage_state(dataset_id, timestamp)
    attr(state, "initialized") <- TRUE
    return(state)
  }
  load_dataset_storage_state(dataset_dir_path, dataset_id, state_filename)
}


save_dataset_storage_state_atomic <- function(
  state,
  dataset_dir_path,
  state_filename = "storage_state.yaml",
  timestamp = Sys.time()
) {
  validate_dataset_storage_state(state)
  paths <- dataset_storage_state_paths(dataset_dir_path, state_filename)
  acquire_pipeline_state_lock(paths$lock)
  on.exit(unlink(paths$lock, recursive = TRUE, force = TRUE), add = TRUE)

  if (file.exists(paths$primary)) {
    current <- load_dataset_storage_state(
      dataset_dir_path,
      dataset_id = state$dataset_id,
      state_filename = state_filename
    )
    if (!identical(as.integer(current$revision), as.integer(state$revision))) {
      stop(
        "Dataset storage-state revision conflict: disk is ", current$revision,
        " but the caller has ", state$revision, ".",
        call. = FALSE
      )
    }
  } else if (as.integer(state$revision) != 0L) {
    stop("Cannot create a missing storage state from a non-zero revision.", call. = FALSE)
  }

  saved <- state
  saved$revision <- as.integer(saved$revision) + 1L
  saved$updated_at <- dataset_storage_timestamp(timestamp)
  validate_dataset_storage_state(saved)
  temporary <- tempfile(
    pattern = paste0(".", state_filename, "-"),
    tmpdir = dataset_dir_path,
    fileext = ".tmp"
  )
  on.exit(if (file.exists(temporary)) file.remove(temporary), add = TRUE)
  yaml::write_yaml(saved, temporary)
  validate_dataset_storage_state(yaml::read_yaml(temporary), saved$dataset_id)

  if (file.exists(paths$backup) && !file.remove(paths$backup)) {
    stop("Could not replace the previous dataset storage-state backup.", call. = FALSE)
  }
  had_primary <- file.exists(paths$primary)
  if (had_primary && !file.rename(paths$primary, paths$backup)) {
    stop("Could not back up the current dataset storage state.", call. = FALSE)
  }
  if (!file.rename(temporary, paths$primary)) {
    if (had_primary && file.exists(paths$backup)) file.rename(paths$backup, paths$primary)
    stop("Could not install the new dataset storage state.", call. = FALSE)
  }
  persisted <- yaml::read_yaml(paths$primary)
  validate_dataset_storage_state(persisted, saved$dataset_id)
  persisted
}


transition_dataset_storage_state <- function(
  state,
  status,
  reason = NULL,
  details = NULL,
  timestamp = Sys.time()
) {
  validate_dataset_storage_state(state)
  if (!(status %in% DATASET_STORAGE_STATUSES)) {
    stop("Unsupported dataset storage status: ", status, call. = FALSE)
  }
  updated <- state
  updated$status <- status
  updated$updated_at <- dataset_storage_timestamp(timestamp)
  updated["reason"] <- list(if (is.null(reason)) NULL else trimws(as.character(reason)))
  if (!is.null(details)) {
    if (!is.list(details)) stop("Storage-state details must be a list.", call. = FALSE)
    updated$details <- utils::modifyList(updated$details, details, keep.null = TRUE)
  }
  validate_dataset_storage_state(updated)
  updated
}


dataset_storage_is_archived <- function(state) {
  !is.null(state) && identical(state$status, "archived")
}


dataset_storage_cache_is_retired <- function(state) {
  if (is.null(state)) return(FALSE)
  identical(state$status, "archived") ||
    (state$status %in% c("cleaning", "cleanup_failed") && isTRUE(state$details$cache_retired))
}


dataset_archive_output_audit <- function(storage_state, dataset_dir_path, verify_checksums = FALSE) {
  validate_dataset_storage_state(storage_state)
  retained <- storage_state$details$cleanup$retained_outputs
  if (!dataset_storage_cache_is_retired(storage_state) || is.null(retained)) {
    return(list(applicable = FALSE, intact = TRUE, issues = character(), checked = 0L))
  }
  dataset_root <- normalizePath(dataset_dir_path, winslash = "/", mustWork = TRUE)
  issues <- character()
  for (record in retained) {
    relative_path <- as.character(record$path)
    candidate <- file.path(dataset_root, relative_path)
    normalized_parent <- normalizePath(dirname(candidate), winslash = "/", mustWork = FALSE)
    if (!startsWith(paste0(normalized_parent, "/"), paste0(dataset_root, "/"))) {
      issues <- c(issues, paste0(relative_path, ": recorded path escapes the dataset."))
      next
    }
    if (!file.exists(candidate) || isTRUE(file.info(candidate)$isdir)) {
      issues <- c(issues, paste0(relative_path, ": retained output is missing."))
      next
    }
    if (!identical(as.numeric(file.info(candidate)$size), as.numeric(record$size_bytes))) {
      issues <- c(issues, paste0(relative_path, ": retained output size changed."))
      next
    }
    if (isTRUE(verify_checksums) && !identical(.cache_md5(candidate), as.character(record$checksum))) {
      issues <- c(issues, paste0(relative_path, ": retained output checksum changed."))
    }
  }
  list(
    applicable = TRUE,
    intact = length(issues) == 0L,
    issues = unique(issues),
    checked = length(retained)
  )
}


reconcile_interrupted_dataset_storage <- function(state, dataset_dir_path, timestamp = Sys.time()) {
  validate_dataset_storage_state(state)
  if (!identical(state$status, "cleaning")) return(state)
  cache_exists <- dir.exists(file.path(dataset_dir_path, "cache"))
  retired_path <- state$details$retired_path
  retired_exists <- !is.null(retired_path) && dir.exists(retired_path)
  reason <- if (retired_exists && !cache_exists) {
    "Cleanup was interrupted after cache retirement. Retry deletion to finish archiving."
  } else if (cache_exists) {
    "Cleanup was interrupted before cache retirement. Review and retry cleanup."
  } else {
    "Cleanup was interrupted and neither the active nor retired cache directory is available."
  }
  reconciled <- transition_dataset_storage_state(
    state,
    "cleanup_failed",
    reason = reason,
    details = list(
      cache_retired = retired_exists && !cache_exists,
      deletion_pending = retired_exists && !cache_exists
    ),
    timestamp = timestamp
  )
  attr(reconciled, "storage_reconciled") <- TRUE
  reconciled
}


format_storage_bytes <- function(bytes) {
  bytes <- suppressWarnings(as.numeric(bytes))
  if (length(bytes) != 1L || is.na(bytes) || bytes < 0) return("Unknown")
  units <- c("B", "KB", "MB", "GB", "TB")
  index <- min(length(units), floor(log(max(bytes, 1), 1024)) + 1L)
  value <- bytes / 1024^(index - 1L)
  paste0(format(round(value, if (value >= 10) 1 else 2), trim = TRUE), " ", units[[index]])
}


.storage_relative_paths <- function(paths, root) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  normalized <- normalizePath(paths, winslash = "/", mustWork = TRUE)
  prefix <- paste0(root, "/")
  if (any(!startsWith(normalized, prefix))) {
    stop("Storage inventory escaped its intended root.", call. = FALSE)
  }
  substring(normalized, nchar(prefix) + 1L)
}


dataset_cache_inventory <- function(dataset_dir_path) {
  dataset_root <- normalizePath(dataset_dir_path, winslash = "/", mustWork = TRUE)
  cache_dir <- file.path(dataset_root, "cache")
  if (!dir.exists(cache_dir)) {
    return(list(
      cache_dir = cache_dir,
      files = data.frame(path = character(), relative_path = character(), size_bytes = numeric()),
      directories = character(),
      unknown = character(),
      file_count = 0L,
      size_bytes = 0
    ))
  }
  entries <- list.files(
    cache_dir,
    recursive = TRUE,
    full.names = TRUE,
    all.files = TRUE,
    no.. = TRUE,
    include.dirs = TRUE
  )
  info <- if (length(entries) > 0L) file.info(entries) else data.frame()
  files <- entries[length(entries) > 0L & !info$isdir]
  directories <- entries[length(entries) > 0L & info$isdir]
  relative_files <- if (length(files) > 0L) .storage_relative_paths(files, cache_dir) else character()
  relative_directories <- if (length(directories) > 0L) {
    .storage_relative_paths(directories, cache_dir)
  } else character()
  known_file <- grepl(
    "^(cache_manifest[.]yaml([.]bak)?|[^/\\]+[.]qs2([.]bak)?)$",
    relative_files
  )
  unknown <- c(relative_files[!known_file], relative_directories)
  file_table <- data.frame(
    path = files,
    relative_path = relative_files,
    size_bytes = if (length(files) > 0L) unname(file.info(files)$size) else numeric(),
    stringsAsFactors = FALSE
  )
  list(
    cache_dir = cache_dir,
    files = file_table,
    directories = relative_directories,
    unknown = unknown,
    file_count = nrow(file_table),
    size_bytes = sum(file_table$size_bytes, na.rm = TRUE)
  )
}


.storage_required_file <- function(path, label, sample_name = NULL) {
  valid <- file.exists(path) && !isTRUE(file.info(path)$isdir) && file.info(path)$size > 0
  list(
    valid = isTRUE(valid),
    path = path,
    label = label,
    sample = sample_name,
    reason = if (isTRUE(valid)) NULL else paste0(
      if (!is.null(sample_name)) paste0(sample_name, ": ") else "",
      label, " is missing or empty."
    )
  )
}


dataset_cleanup_readiness <- function(
  pipeline_state,
  paths_list,
  selected_config,
  selected_config_path,
  results_dir_path,
  dataset_dir_path
) {
  validate_pipeline_state(pipeline_state)
  sample_names <- basename(paths_list$sample_dir_paths)
  reasons <- character()
  outputs <- list()
  add_reason <- function(reason) reasons <<- unique(c(reasons, reason))
  add_output <- function(output) {
    outputs[[length(outputs) + 1L]] <<- output
    if (!output$valid) add_reason(output$reason)
  }

  standardization <- get_pipeline_step(pipeline_state, "standardization")
  if (!identical(standardization$status, "completed")) {
    add_reason(paste0("Standardization is ", standardization$status, "."))
  }
  add_output(.storage_required_file(selected_config_path, "Selected configuration"))

  general_steps <- c("clustering", "resolution", "differential_expression", "annotation")
  cna_steps <- c(
    "cna_compute", "cna_cluster_selection", "cna_signal_correlation",
    "cna_thresholds", "cna_assignment"
  )
  for (index in seq_along(sample_names)) {
    sample_name <- sample_names[[index]]
    for (step in general_steps) {
      record <- get_pipeline_step(pipeline_state, step, sample_name)
      if (!identical(record$status, "completed")) {
        add_reason(paste0(sample_name, ": ", step, " is ", record$status, "."))
      }
    }
    add_output(.storage_required_file(
      paths_list$cell_file_paths[[index]], "Final Cells.csv", sample_name
    ))

    resolution <- selected_config$resolutions[[sample_name]]
    cluster_plot <- if (!is.null(resolution)) {
      file.path(
        results_dir_path, sample_name, "1_cluster_plots",
        paste0("clusters_plot_", sample_name, "_res_", resolution, ".png")
      )
    } else ""
    add_output(.storage_required_file(cluster_plot, "Selected-resolution cluster plot", sample_name))
    add_output(.storage_required_file(
      file.path(results_dir_path, sample_name, "2_de_plots", "all_marker_matches.csv"),
      "DE marker table",
      sample_name
    ))
    de_pngs <- list.files(
      file.path(results_dir_path, sample_name, "2_de_plots"),
      pattern = "[.]png$",
      full.names = TRUE
    )
    if (length(de_pngs) == 0L) add_reason(paste0(sample_name, ": DE plots are missing."))

    configuration <- get_pipeline_step(pipeline_state, "cna_configuration", sample_name)
    if (identical(configuration$status, "skipped")) {
      if (!isTRUE(configuration$details$omitted_by_user)) {
        add_reason(paste0(sample_name, ": CNA is skipped without an explicit omission decision."))
      }
      next
    }
    if (!identical(configuration$status, "completed")) {
      add_reason(paste0(sample_name, ": cna_configuration is ", configuration$status, "."))
      next
    }
    for (step in cna_steps) {
      record <- get_pipeline_step(pipeline_state, step, sample_name)
      if (!identical(record$status, "completed")) {
        add_reason(paste0(sample_name, ": ", step, " is ", record$status, "."))
      }
    }
    cna_plot_dir <- file.path(results_dir_path, sample_name, "3_cna_plots")
    add_output(.storage_required_file(
      file.path(cna_plot_dir, paste0("cna_summary_heatmap_", sample_name, ".png")),
      "Final CNA summary heatmap",
      sample_name
    ))
    add_output(.storage_required_file(
      file.path(cna_plot_dir, paste0("cna_umap_assigned_", sample_name, ".png")),
      "Final assigned CNA UMAP",
      sample_name
    ))
    export_status <- cna_values_export_status(sample_name, dataset_dir_path, results_dir_path)
    if (!isTRUE(export_status$current)) {
      add_reason(paste0(sample_name, ": current CNA values export is required (", export_status$reason, ")."))
    } else {
      add_output(.storage_required_file(export_status$paths$csv, "CNA values CSV", sample_name))
      add_output(.storage_required_file(export_status$paths$metadata, "CNA values provenance", sample_name))
    }
  }

  inventory <- dataset_cache_inventory(dataset_dir_path)
  if (inventory$file_count == 0L) add_reason("The dataset cache is already empty.")
  if (length(inventory$unknown) > 0L) {
    add_reason(paste0(
      "The cache contains unrecognized entries: ",
      paste(utils::head(inventory$unknown, 5L), collapse = ", "),
      if (length(inventory$unknown) > 5L) " ..." else "."
    ))
  }
  output_table <- if (length(outputs) > 0L) {
    data.frame(
      path = vapply(outputs, `[[`, character(1), "path"),
      label = vapply(outputs, `[[`, character(1), "label"),
      sample = vapply(outputs, function(output) {
        if (is.null(output$sample)) "" else output$sample
      }, character(1)),
      valid = vapply(outputs, `[[`, logical(1), "valid"),
      stringsAsFactors = FALSE
    )
  } else data.frame(path = character(), label = character(), sample = character(), valid = logical())
  list(
    ready = length(reasons) == 0L,
    reasons = reasons,
    sample_names = sample_names,
    cache = inventory,
    retained_outputs = output_table
  )
}


build_dataset_cleanup_plan <- function(readiness, pipeline_state, timestamp = Sys.time()) {
  if (!isTRUE(readiness$ready)) {
    stop("Dataset cleanup is not ready: ", paste(readiness$reasons, collapse = "; "), call. = FALSE)
  }
  manifest <- load_cache_manifest(dirname(readiness$cache$cache_dir), recover = FALSE)
  retained <- readiness$retained_outputs[readiness$retained_outputs$valid, , drop = FALSE]
  retained$size_bytes <- unname(file.info(retained$path)$size)
  retained$checksum <- vapply(retained$path, .cache_md5, character(1))
  retained$path <- .storage_relative_paths(retained$path, dirname(readiness$cache$cache_dir))
  cleanup_id <- paste0(
    format(as.POSIXct(timestamp, tz = "UTC"), "%Y%m%dT%H%M%S", tz = "UTC"),
    "-", sprintf("%08x", sample.int(.Machine$integer.max, 1L))
  )
  list(
    cleanup_id = cleanup_id,
    created_at = dataset_storage_timestamp(timestamp),
    implementation = DATASET_STORAGE_IMPLEMENTATION,
    pipeline_revision = pipeline_state$revision,
    cache_manifest_revision = manifest$revision,
    cache_file_count = readiness$cache$file_count,
    cache_size_bytes = readiness$cache$size_bytes,
    cache_files = as.list(readiness$cache$files$relative_path),
    retained_outputs = lapply(seq_len(nrow(retained)), function(index) {
      as.list(retained[index, c("path", "label", "sample", "size_bytes", "checksum")])
    })
  )
}


archive_dataset_cache <- function(
  dataset_dir_path,
  pipeline_state,
  storage_state,
  readiness,
  timestamp = Sys.time(),
  state_filename = "storage_state.yaml",
  rename_directory = file.rename,
  delete_directory = function(path) {
    unlink(path, recursive = TRUE, force = TRUE)
    !file.exists(path)
  },
  save_storage = save_dataset_storage_state_atomic
) {
  validate_pipeline_state(pipeline_state)
  validate_dataset_storage_state(storage_state, pipeline_state$dataset_id)
  if (!(storage_state$status %in% c("active", "cleanup_failed"))) {
    stop("Only an active dataset can begin cache cleanup.", call. = FALSE)
  }
  paths <- dataset_storage_state_paths(dataset_dir_path, state_filename)
  acquire_pipeline_state_lock(paths$operation_lock, timeout_seconds = 5)
  on.exit(unlink(paths$operation_lock, recursive = TRUE, force = TRUE), add = TRUE)

  plan <- build_dataset_cleanup_plan(readiness, pipeline_state, timestamp)
  current_inventory <- dataset_cache_inventory(dataset_dir_path)
  inventory_matches <- identical(
    sort(as.character(current_inventory$files$relative_path)),
    sort(as.character(readiness$cache$files$relative_path))
  ) && identical(
    as.numeric(current_inventory$size_bytes),
    as.numeric(readiness$cache$size_bytes)
  ) && length(current_inventory$unknown) == 0L
  if (!inventory_matches) {
    stop("The cache changed after cleanup review. Review the updated cleanup plan before retrying.", call. = FALSE)
  }
  cache_dir <- normalizePath(readiness$cache$cache_dir, winslash = "/", mustWork = TRUE)
  dataset_root <- normalizePath(dataset_dir_path, winslash = "/", mustWork = TRUE)
  expected_cache <- paste0(dataset_root, "/cache")
  if (!identical(cache_dir, expected_cache)) {
    stop("Refusing to retire a cache outside the selected dataset.", call. = FALSE)
  }
  retired_path <- file.path(dataset_root, paste0(".cache-retired-", plan$cleanup_id))
  if (file.exists(retired_path)) stop("Cleanup retirement path already exists.", call. = FALSE)

  cleaning <- transition_dataset_storage_state(
    storage_state,
    "cleaning",
    details = list(
      cleanup = plan,
      cache_retired = FALSE,
      retired_path = retired_path,
      deletion_pending = FALSE
    ),
    timestamp = timestamp
  )
  cleaning <- save_storage(cleaning, dataset_dir_path, state_filename, timestamp)

  if (!isTRUE(rename_directory(cache_dir, retired_path))) {
    failed <- transition_dataset_storage_state(
      cleaning,
      "cleanup_failed",
      reason = "Could not retire the cache directory; files may be locked.",
      details = list(cache_retired = FALSE, deletion_pending = FALSE),
      timestamp = timestamp
    )
    save_storage(failed, dataset_dir_path, state_filename, timestamp)
    stop(failed$reason, call. = FALSE)
  }

  retired <- transition_dataset_storage_state(
    cleaning,
    "cleanup_failed",
    reason = "The cache was safely retired and is waiting for final deletion.",
    details = list(cache_retired = TRUE, deletion_pending = TRUE),
    timestamp = timestamp
  )
  persisted <- tryCatch(
    save_storage(retired, dataset_dir_path, state_filename, timestamp),
    error = identity
  )
  if (inherits(persisted, "error")) {
    rolled_back <- isTRUE(rename_directory(retired_path, cache_dir)) && dir.exists(cache_dir)
    failed <- transition_dataset_storage_state(
      cleaning,
      "cleanup_failed",
      reason = if (rolled_back) {
        paste("Cache retirement was rolled back because storage state failed:", conditionMessage(persisted))
      } else {
        paste(
          "Storage state failed and the retired cache could not be restored. ",
          "Keep the dataset read-only and retry retired cache deletion:",
          conditionMessage(persisted)
        )
      },
      details = list(
        cache_retired = !rolled_back,
        deletion_pending = !rolled_back
      ),
      timestamp = timestamp
    )
    try(save_storage(failed, dataset_dir_path, state_filename, timestamp), silent = TRUE)
    stop(failed$reason, call. = FALSE)
  }

  deleted <- isTRUE(delete_directory(retired_path)) && !file.exists(retired_path)
  if (!deleted) {
    failed <- transition_dataset_storage_state(
      persisted,
      "cleanup_failed",
      reason = "The dataset is archived, but retired cache files could not be deleted. Retry cleanup.",
      details = list(cache_retired = TRUE, deletion_pending = TRUE),
      timestamp = timestamp
    )
    return(save_storage(failed, dataset_dir_path, state_filename, timestamp))
  }
  complete <- transition_dataset_storage_state(
    persisted,
    "archived",
    reason = NULL,
    details = list(
      cache_retired = TRUE,
      deletion_pending = FALSE,
      completed_at = dataset_storage_timestamp(timestamp),
      recovered_bytes = plan$cache_size_bytes
    ),
    timestamp = timestamp
  )
  save_storage(complete, dataset_dir_path, state_filename, timestamp)
}


retry_dataset_cache_deletion <- function(
  dataset_dir_path,
  storage_state,
  timestamp = Sys.time(),
  state_filename = "storage_state.yaml",
  delete_directory = function(path) {
    unlink(path, recursive = TRUE, force = TRUE)
    !file.exists(path)
  }
) {
  validate_dataset_storage_state(storage_state)
  if (
    !identical(storage_state$status, "cleanup_failed") ||
      !isTRUE(storage_state$details$cache_retired) ||
      !isTRUE(storage_state$details$deletion_pending)
  ) {
    stop("There is no retired cache deletion to retry.", call. = FALSE)
  }
  retired_path <- storage_state$details$retired_path
  if (file.exists(retired_path) && !isTRUE(delete_directory(retired_path))) {
    stop("Retired cache files are still locked and could not be deleted.", call. = FALSE)
  }
  completed <- transition_dataset_storage_state(
    storage_state,
    "archived",
    details = list(
      deletion_pending = FALSE,
      completed_at = dataset_storage_timestamp(timestamp),
      recovered_bytes = storage_state$details$cleanup$cache_size_bytes
    ),
    timestamp = timestamp
  )
  save_dataset_storage_state_atomic(completed, dataset_dir_path, state_filename, timestamp)
}


reopen_archived_pipeline_state <- function(pipeline_state, timestamp = Sys.time()) {
  validate_pipeline_state(pipeline_state)
  reason <- "Dataset caches were intentionally removed during archive cleanup; rerun clustering."
  updated <- pipeline_state
  for (sample_name in names(updated$samples)) {
    for (step in PIPELINE_SAMPLE_STEPS) {
      current <- get_pipeline_step(updated, step, sample_name)
      if (current$status %in% c("completed", "skipped")) {
        updated <- transition_pipeline_step(
          updated,
          step,
          "stale",
          sample = sample_name,
          reason = reason,
          details = list(stale_after = "archive_cleanup"),
          timestamp = timestamp,
          force = TRUE
        )
      }
    }
  }
  validate_pipeline_state(updated)
  updated
}


reopen_archived_dataset <- function(
  dataset_dir_path,
  pipeline_state,
  pipeline_state_path,
  storage_state,
  timestamp = Sys.time()
) {
  validate_dataset_storage_state(storage_state, pipeline_state$dataset_id)
  if (!identical(storage_state$status, "archived")) {
    stop("Only an archived dataset can be reopened.", call. = FALSE)
  }
  reopened_pipeline <- reopen_archived_pipeline_state(pipeline_state, timestamp)
  reopened_pipeline <- save_pipeline_state_at_path(
    reopened_pipeline,
    pipeline_state_path,
    timestamp
  )
  reopened_storage <- transition_dataset_storage_state(
    storage_state,
    "active",
    details = list(
      reopened_at = dataset_storage_timestamp(timestamp),
      deletion_pending = FALSE,
      cache_retired = FALSE
    ),
    timestamp = timestamp
  )
  reopened_storage <- save_dataset_storage_state_atomic(
    reopened_storage,
    dataset_dir_path,
    timestamp = timestamp
  )
  setup_cache_dir(dataset_dir_path)
  list(pipeline_state = reopened_pipeline, storage_state = reopened_storage)
}
