# Finished-dataset review snapshots. No destination or export registry is persisted.
REVIEW_SNAPSHOT_IMPLEMENTATION <- "review-snapshot-v1"

.snapshot_stop <- function(message) {
  condition <- simpleError(message, call = NULL)
  class(condition) <- c("snapshot_error", class(condition))
  stop(condition)
}
.snapshot_default <- function(value, default) if (is.null(value)) default else value

.snapshot_with_utf8 <- function(code) {
  # Windows UCRT supports UTF-8, but an IDE may start R in the C locale.
  # Native directory enumeration otherwise transliterates some filenames.
  previous <- Sys.getlocale("LC_CTYPE")
  change <- .Platform$OS.type == "windows" && !isTRUE(l10n_info()$`UTF-8`)
  if (change) {
    if (!nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8"))) .snapshot_stop("UTF-8 filename handling is unavailable in this R session.")
    on.exit(Sys.setlocale("LC_CTYPE", previous), add = TRUE)
  }
  force(code)
}

snapshot_options <- function(mode = "folder", include_logs = TRUE, include_cna_values = FALSE) {
  if (length(mode) != 1L || is.na(mode) || !mode %in% c("folder", "archive", "both")) {
    .snapshot_stop("Choose Folder, Compressed archive or Both.")
  }
  for (flag in list(include_logs, include_cna_values)) {
    if (!is.logical(flag) || length(flag) != 1L || is.na(flag)) {
      .snapshot_stop("Snapshot inclusion options must be true or false.")
    }
  }
  list(mode = mode, include_logs = include_logs, include_cna_values = include_cna_values)
}

# These small aggregates are captured only during normal successful pipeline saves.
snapshot_label_counts <- function(cells) {
  labels <- if ("cell_type" %in% names(cells)) as.character(cells$cell_type) else rep(NA_character_, nrow(cells))
  labels[is.na(labels) | !nzchar(trimws(labels)) | labels == "Unassigned"] <- "Unassigned/NA"
  subclones <- if ("subclone" %in% names(cells)) as.character(cells$subclone) else rep(NA_character_, nrow(cells))
  subclones[is.na(subclones) | !nzchar(subclones)] <- "Not assigned"
  counts <- data.table::data.table(annotation = labels, subclone = subclones)[
    , list(cell_count = .N), by = c("annotation", "subclone")
  ]
  counts <- counts[order(annotation, subclone)]
  lapply(seq_len(nrow(counts)), function(i) as.list(counts[i]))
}

capture_snapshot_annotations <- function(cells, cell_path, resolution, clustering_record) {
  list(
    schema_version = 1L, cell_file_checksum = .cache_md5(cell_path),
    resolution = as.character(resolution),
    clustering_attempt = clustering_record$attempt,
    clustering_finished_at = clustering_record$finished_at,
    cell_count = nrow(cells), counts = snapshot_label_counts(cells)
  )
}

# This check intentionally does not read caches, hash payloads, or build inventories.
dataset_snapshot_readiness <- function(
  pipeline_state, storage_state, paths_list, selected_config, selected_config_path,
  results_dir_path, dataset_dir_path, dataset_config, processed_dir_path,
  annotation_dirty = FALSE, active_actions = character()
) {
  validate_dataset_storage_state(storage_state, pipeline_state$dataset_id)
  completed <- dataset_completion_readiness(
    pipeline_state, paths_list, selected_config, selected_config_path,
    results_dir_path, dataset_dir_path, inspect_optional_exports = FALSE
  )
  reasons <- completed$reasons
  if (!storage_state$status %in% c("active", "archived")) {
    reasons <- c(reasons, "Finish or resolve dataset cleanup before creating a snapshot.")
  }
  if (isTRUE(annotation_dirty)) reasons <- c(reasons, "Save or discard unsaved annotation edits first.")
  if (length(active_actions)) reasons <- c(reasons, "Wait for the current application action to finish.")
  samples <- basename(paths_list$sample_dir_paths)
  if (!length(samples) || anyDuplicated(samples) || !setequal(samples, names(pipeline_state$samples))) {
    reasons <- c(reasons, "Sample paths and workflow state do not describe the same nonempty dataset.")
  }
  for (sample in samples) {
    # An omission must not conceal an actually running CNA worker.
    if (any(vapply(PIPELINE_SAMPLE_STEPS, function(step) {
      identical(get_pipeline_step(pipeline_state, step, sample)$status, "in_progress")
    }, logical(1)))) reasons <- c(reasons, paste0(sample, ": a pipeline stage is still running."))
    annotation_plot <- file.path(results_dir_path, sample, "2_de_plots", "cell_types.png")
    if (!isTRUE(.storage_required_file(annotation_plot, "Final annotation plot")$valid)) {
      reasons <- c(reasons, paste0(sample, ": final annotation plot is missing or empty."))
    }
  }
  std <- dataset_config$std_names
  if (!all(c("expmat", "genes", "cells", "samples") %in% names(std)) ||
      !all(vapply(std[c("expmat", "genes", "cells", "samples")], function(value) {
        is.character(value) && length(value) == 1L && !is.na(value) && nzchar(trimws(value))
      }, logical(1)))) {
    reasons <- c(reasons, "Standardized file names are incomplete in dataset configuration.")
  } else {
    required <- c(unlist(lapply(samples, function(sample) {
      file.path(processed_dir_path, sample, unlist(std[c("expmat", "genes", "cells")], use.names = FALSE))
    }), use.names = FALSE), file.path(processed_dir_path, std$samples))
    for (path in required) {
      if (!isTRUE(.storage_required_file(path, "Standardized input")$valid)) {
        reasons <- c(reasons, "A required standardized matrix, gene, cell or Samples file is missing/empty.")
      }
    }
  }
  list(ready = !length(reasons), reasons = unique(reasons))
}

.snapshot_real <- function(path) {
  if (.Platform$OS.type == "windows" && any(nchar(path) >= 260L)) {
    .snapshot_stop("A path exceeds the supported Windows length. Use shorter dataset or destination folder names.")
  }
  as.character(fs::path_real(path))
}
.snapshot_inside <- function(path, root) {
  # Case-insensitive comparison also prevents Windows casing aliases.
  if (.Platform$OS.type == "windows") { path <- tolower(path); root <- tolower(root) }
  identical(path, root) || startsWith(path, paste0(root, "/"))
}

.snapshot_relative <- function(path) {
  if (any(is.na(path) | !nzchar(path) | grepl("(^/|^[A-Za-z]:|\\\\|(^|/)[.][.]?(/|$))", path))) {
    .snapshot_stop("Unsafe relative path in review snapshot.")
  }
  invisible(TRUE)
}

validate_snapshot_destination <- function(destination, dataset_dir_path, datasets_dir_path = dirname(dataset_dir_path)) {
  if (length(destination) != 1L || is.na(destination) || !nzchar(trimws(destination))) {
    .snapshot_stop("Enter an existing destination directory outside the datasets directory.")
  }
  if (!dir.exists(destination)) .snapshot_stop("The destination directory does not exist.")
  resolved <- .snapshot_real(destination)
  source <- .snapshot_real(dataset_dir_path)
  managed <- .snapshot_real(datasets_dir_path)
  if (.snapshot_inside(resolved, source) || .snapshot_inside(source, resolved) ||
      .snapshot_inside(resolved, managed)) {
    .snapshot_stop("Choose a separate export directory outside the source and app-managed datasets directory.")
  }
  resolved
}

validate_snapshot_output_paths <- function(parent, inventory, dataset_id) {
  # R/libuv Windows builds can have MAX_PATH limits even if the OS enables long paths.
  # Never begin copying then silently omit a file that could not be addressed.
  if (.Platform$OS.type == "windows") {
    package_prefix <- nchar(cna_values_export_safe_name(dataset_id)) + 48L
    longest <- max(nchar(c(inventory$files$path, "snapshot_manifest.yaml")))
    if (nchar(parent) + max(package_prefix, 45L) + longest + 3L >= 260L) {
      .snapshot_stop("Snapshot paths would exceed the supported Windows length. Choose a shorter destination or shorten source filenames.")
    }
  }
  invisible(TRUE)
}

.snapshot_excluded <- function(relative) {
  parts <- strsplit(relative, "/", fixed = TRUE)[[1L]]
  # Raw/cache roots are excluded by the fixed input trees, not by guessing
  # from ordinary subdirectory/sample names such as 'data' or 'exports'.
  any(grepl("^([.]cache.*|[.]git|[.]aws|[.]codex)$", parts, ignore.case = TRUE)) ||
    any(grepl("([.](bak|tmp|temp|lock|part)|~)$|^([.]env|[.]Renviron|[.]Rprofile|local_config[.]yaml|cache_manifest[.]yaml)$|_review_[0-9]{8}T[0-9]{6}_.+[.]zip$", parts, ignore.case = TRUE))
}

# Walk one directory at a time; never follow links or recurse into excluded trees.
.snapshot_tree <- function(directory, prefix, dataset_root) {
  result <- data.frame(source = character(), path = character(), stringsAsFactors = FALSE)
  walk <- function(current, relative) {
    for (entry in as.character(fs::dir_ls(current, all = TRUE, recurse = FALSE))) {
      part <- paste0(relative, "/", basename(entry))
      if (.snapshot_excluded(part)) next
      actual <- .snapshot_real(entry)
      # Reject all symlinks/junctions (even internal ones), not just escaping links.
      if (isTRUE(fs::is_link(entry)) || !.snapshot_inside(actual, dataset_root)) {
        .snapshot_stop("A source link or escaping path was found; remove links from snapshot input trees.")
      }
      if (dir.exists(entry)) {
        if (file.exists(file.path(entry, "snapshot_manifest.yaml"))) next
        walk(entry, part)
      } else {
        result[nrow(result) + 1L, ] <<- list(entry, part)
      }
    }
  }
  if (dir.exists(directory)) walk(directory, prefix)
  result
}

.snapshot_cna_pair <- function(sample, dataset_dir_path, results_dir_path, storage_state) {
  paths <- cna_values_export_paths(results_dir_path, sample)
  bad <- function(reason) list(eligible = FALSE, paths = paths, reason = paste0(sample, ": ", reason))
  if (!all(file.exists(c(paths$csv, paths$metadata)))) return(bad("CNA values/provenance pair missing or incomplete."))
  metadata <- tryCatch(yaml::read_yaml(paths$metadata), error = function(e) NULL)
  if (is.null(metadata) || !isTRUE(tryCatch({ validate_cna_values_export_metadata(metadata); TRUE }, error = function(e) FALSE))) {
    return(bad("CNA values provenance cannot be validated."))
  }
  if (!identical(as.character(metadata$sample), sample) ||
      !identical(as.character(metadata$csv_filename), basename(paths$csv)) ||
      !identical(as.numeric(metadata$csv_size_bytes), as.numeric(file.info(paths$csv)$size)) ||
      !identical(as.character(metadata$csv_checksum), .cache_md5(paths$csv))) {
    return(bad("CNA values content does not match its provenance."))
  }
  if (dataset_storage_is_archived(storage_state)) {
    cleanup <- storage_state$details$cleanup
    if (sample %in% unlist(cleanup$optional_export_samples, use.names = FALSE)) {
      return(bad("No current CNA values export was recorded at cache cleanup."))
    }
    retained <- cleanup$retained_outputs
    relative <- .storage_relative_paths(c(paths$csv, paths$metadata), dataset_dir_path)
    verified <- vapply(seq_along(relative), function(i) {
      record <- Filter(function(record) identical(as.character(record$path), relative[[i]]), retained)
      length(record) == 1L && identical(as.character(record[[1L]]$checksum), .cache_md5(c(paths$csv, paths$metadata)[[i]]))
    }, logical(1))
    if (!all(verified)) return(bad("Retained CNA values have no matching verified cleanup evidence."))
  } else if (!isTRUE(cna_values_export_status(sample, dataset_dir_path, results_dir_path)$current)) {
    return(bad("CNA values are outdated or their current cache provenance is unavailable."))
  }
  list(eligible = TRUE, paths = paths, reason = NULL)
}

build_snapshot_inventory <- function(
  dataset_dir_path, processed_dir_path, results_dir_path, logs_dir_path,
  config_paths, pipeline_state, storage_state, options = snapshot_options()
) {
  root <- .snapshot_real(dataset_dir_path)
  if (dataset_storage_is_archived(storage_state)) {
    audit_state <- storage_state
    # Optional values must never become scientific readiness requirements.
    audit_state$details$cleanup$retained_outputs <- Filter(function(record) {
      !grepl("(^|/)3_cna_results/cna_values_[^/]+[.](csv[.]gz|metadata[.]yaml)$", as.character(record$path), ignore.case = TRUE)
    }, storage_state$details$cleanup$retained_outputs)
    audit <- dataset_archive_output_audit(audit_state, dataset_dir_path, verify_checksums = TRUE)
    if (!isTRUE(audit$intact)) .snapshot_stop("Required retained outputs changed after cleanup. Repair the outputs or reopen for review before exporting.")
  }
  trees <- list(processed_data = processed_dir_path, results = results_dir_path)
  if (options$include_logs) trees$logs <- logs_dir_path
  files <- data.frame(source = character(), path = character(), stringsAsFactors = FALSE)
  warnings <- character()
  omissions <- c("Raw inputs, caches, backups, temporary files and previous snapshots are excluded.")
  for (prefix in names(trees)) {
    directory <- trees[[prefix]]
    if (!dir.exists(directory)) {
      if (prefix != "logs") .snapshot_stop("A required snapshot input directory is missing.")
      warnings <- c(warnings, "Logs were requested but the source log directory is unavailable.")
      next
    }
    if (!.snapshot_inside(.snapshot_real(directory), root) || isTRUE(fs::is_link(directory))) {
      .snapshot_stop("Snapshot input directories must be ordinary directories inside this dataset.")
    }
    files <- rbind(files, .snapshot_tree(directory, prefix, root))
  }
  if (!options$include_logs) omissions <- c(omissions, "Logs intentionally excluded.")
  # Recognize only F13 filenames under CNA result directories, including orphan pairs.
  recognized <- grepl("^results/[^/]+/3_cna_results/cna_values_[^/]+[.](csv[.]gz|metadata[.]yaml)$", files$path, ignore.case = TRUE)
  optional <- files[recognized, , drop = FALSE]
  files <- files[!recognized, , drop = FALSE]
  cna_included <- character()
  for (sample in names(pipeline_state$samples)) {
    omitted <- identical(get_pipeline_step(pipeline_state, "cna_configuration", sample)$status, "skipped")
    if (!options$include_cna_values || omitted) next
    pair <- .snapshot_cna_pair(sample, dataset_dir_path, results_dir_path, storage_state)
    if (pair$eligible) {
      chosen <- optional[vapply(optional$source, .snapshot_real, character(1)) %in%
        vapply(c(pair$paths$csv, pair$paths$metadata), .snapshot_real, character(1)), , drop = FALSE]
      if (nrow(chosen) != 2L) .snapshot_stop("Eligible CNA values were not found in the source inventory.")
      files <- rbind(files, chosen)
      cna_included <- c(cna_included, sample)
    } else warnings <- c(warnings, pair$reason)
  }
  # Unrecognized legacy samples' F13 pairs cannot be declared current.
  if (options$include_cna_values && nrow(optional)) {
    extra <- setdiff(unique(vapply(strsplit(optional$path, "/"), `[[`, character(1), 2L)), names(pipeline_state$samples))
    if (length(extra)) warnings <- c(warnings, "CNA values for samples absent from current workflow state were omitted.")
  }
  omissions <- c(omissions, if (options$include_cna_values) {
    "Only existing verified current CNA values/provenance pairs are included; no CNA computation is performed."
  } else "CNA values and their matching export metadata intentionally excluded; CNA plots retained.")
  for (name in names(config_paths)) {
    source <- config_paths[[name]]
    if (!file.exists(source)) {
      if (name %in% c("dataset_config.yaml", "samples_config.yaml", "selected_config.yaml", "pipeline_state.yaml")) {
        .snapshot_stop("A required configuration or historical workflow-state file is missing.")
      }
      warnings <- c(warnings, paste0("Optional preparation provenance unavailable: ", name))
      next
    }
    .snapshot_relative(name)
    if (!.snapshot_inside(.snapshot_real(source), root) || isTRUE(fs::is_link(source))) {
      .snapshot_stop("Provenance input must be an ordinary file inside this dataset.")
    }
    files <- rbind(files, data.frame(source = source, path = paste0("provenance/", name)))
  }
  .snapshot_relative(files$path)
  if (anyDuplicated(tolower(files$path))) .snapshot_stop("Snapshot paths collide on a case-insensitive filesystem.")
  files <- files[order(files$path), , drop = FALSE]
  info <- file.info(files$source)
  if (anyNA(info$size) || any(info$isdir)) .snapshot_stop("Source files changed while inventorying the snapshot.")
  files$size_bytes <- as.numeric(info$size)
  files$mtime <- as.numeric(info$mtime)
  list(files = files, warnings = unique(warnings), omissions = omissions,
       cna_included = cna_included, options = options, size_bytes = sum(files$size_bytes),
       # Conservative upper bound: payload, ZIP (assume no compression), extraction.
       required_space_bytes = sum(files$size_bytes) * if (options$mode == "folder") 1.05 else 3.1)
}

build_snapshot_summaries <- function(pipeline_state, paths_list, selected_config) {
  annotations <- list()
  filtering <- list()
  warnings <- character()
  for (i in seq_along(paths_list$sample_dir_paths)) {
    sample <- basename(paths_list$sample_dir_paths[[i]])
    cells <- data.table::fread(paths_list$cell_file_paths[[i]], na.strings = c("", "NA"))
    if (!all(c("cell_name", "sample", "cell_type") %in% names(cells)) ||
        !nrow(cells) || anyNA(cells$cell_name) || anyDuplicated(cells$cell_name) ||
        anyNA(cells$sample) || !all(cells$sample == sample)) {
      .snapshot_stop("Final cell metadata is empty, malformed or contains inconsistent cell/sample identities.")
    }
    add_counts <- function(counts, scope) {
      for (count in counts) annotations[[length(annotations) + 1L]] <<- data.frame(
        sample = sample, scope = scope, annotation = count$annotation,
        subclone = count$subclone, cell_count = count$cell_count, stringsAsFactors = FALSE
      )
    }
    add_counts(snapshot_label_counts(cells), "all_standardized_cells_not_all_pipeline_reviewed")
    clustering <- get_pipeline_step(pipeline_state, "clustering", sample)
    stats <- clustering$details$snapshot_filtering
    reliable <- identical(clustering$status, "completed") &&
      identical(as.integer(stats$schema_version), 1L) &&
      length(stats$input_cells) == 1L && length(stats$retained_cells) == 1L &&
      is.finite(stats$input_cells) && is.finite(stats$retained_cells) &&
      stats$input_cells == nrow(cells) && stats$retained_cells >= 0 && stats$retained_cells <= nrow(cells)
    retained <- if (reliable) stats$retained_cells else NA_real_
    filtering[[i]] <- data.frame(
      sample = sample, standardized_cells = nrow(cells), retained_for_clustering = retained,
      filtered_out = nrow(cells) - retained,
      filtered_percent = if (nrow(cells)) 100 * (nrow(cells) - retained) / nrow(cells) else NA_real_,
      filter_settings = if (reliable) as.character(jsonlite::toJSON(stats$settings, auto_unbox = TRUE)) else NA_character_,
      availability = if (reliable) "recorded_successful_clustering" else "unavailable_legacy_or_changed_generation",
      stringsAsFactors = FALSE
    )
    step <- if (identical(get_pipeline_step(pipeline_state, "cna_assignment", sample)$status, "completed")) "cna_assignment" else "annotation"
    record <- get_pipeline_step(pipeline_state, step, sample)
    aggregate <- record$details$snapshot_annotations
    valid <- identical(record$status, "completed") && identical(clustering$status, "completed") &&
      identical(as.integer(aggregate$schema_version), 1L) &&
      identical(as.character(aggregate$cell_file_checksum), .cache_md5(paths_list$cell_file_paths[[i]])) &&
      identical(as.character(aggregate$resolution), as.character(selected_config$resolutions[[sample]])) &&
      identical(as.integer(aggregate$clustering_attempt), as.integer(clustering$attempt)) &&
      identical(aggregate$clustering_finished_at, clustering$finished_at)
    if (valid) add_counts(aggregate$counts, "pipeline_analyzed_cells") else {
      annotations[[length(annotations) + 1L]] <- data.frame(sample = sample, scope = "pipeline_analyzed_cells_unavailable",
        annotation = NA_character_, subclone = NA_character_, cell_count = NA_real_)
      warnings <- c(warnings, paste0(sample, ": analyzed-cell annotation aggregates unavailable for this saved generation."))
    }
    if (!reliable) warnings <- c(warnings, paste0(sample, ": preprocessing filter statistics unavailable; no counts inferred from labels."))
  }
  list(annotations = data.table::rbindlist(annotations), filtering = data.table::rbindlist(filtering), warnings = warnings)
}

.snapshot_inventory_matches <- function(files) {
  info <- file.info(files$source)
  !anyNA(info$size) && !any(info$isdir) && identical(as.numeric(info$size), files$size_bytes) &&
    identical(as.numeric(info$mtime), files$mtime)
}

snapshot_readme <- function(dataset_id, dataset_config, inventory, summaries, timestamp) {
  origin <- dataset_config$project_info
  supplied <- function(value) {
    if (is.null(value) || identical(value, "")) return("not provided")
    if (!is.character(value) || length(value) != 1L || is.na(value)) .snapshot_stop("Dataset origin fields must each contain one DOI/link string or be blank.")
    if (!nzchar(trimws(value))) "not provided" else value
  }
  c(
    paste0("# Review snapshot: ", dataset_id), "",
    paste0("Created (UTC): ", pipeline_state_timestamp(timestamp)),
    paste0("Implementation: ", REVIEW_SNAPSHOT_IMPLEMENTATION),
    paste0("Publication DOI: ", supplied(origin$source_doi)),
    paste0("Dataset/repository URL: ", supplied(origin$source_url)), "",
    "This is a review snapshot, NOT a raw-data backup or resumable app workspace.",
    "Included patient/sample metadata is not anonymized by packaging.", "",
    "- [processed_data/](processed_data/): complete standardized data, copied without filtering or rewriting.",
    "  Cells excluded by app preprocessing remain here; earlier standardization losses cannot be recovered.",
    "- [results/](results/): all ordinary results and plots, including alternative resolutions and diagnostics.",
    "  Historical alternatives may remain; use the selected configuration/state to identify final choices.",
    "- [provenance/](provenance/): historical configuration, decisions and workflow state, not live cache evidence.",
    "- [annotation_summary.csv](annotation_summary.csv): annotation/subclone counts by sample and explicit scope.",
    "  All standardized cells may include unreviewed source labels; only the analyzed scope was pipeline-reviewed.",
    "- [filtering_summary.csv](filtering_summary.csv): standardized input versus analyzed cell counts/settings.",
    "  These describe app preprocessing, not filtering before standardization. NA means unavailable, never zero.",
    "- [snapshot_manifest.yaml](snapshot_manifest.yaml): relative payload paths, sizes and MD5 checksums.",
    "  The manifest excludes itself. Checksums detect accidental corruption, not malicious modification.", "",
    paste0("Logs requested: ", inventory$options$include_logs,
      "; included log files: ", sum(startsWith(inventory$files$path, "logs/"))),
    "Included logs were frozen after the export-start event; the final completion event remains in the source logs.",
    paste0("Existing CNA values requested: ", inventory$options$include_cna_values),
    paste0("Samples with verified CNA values included: ", if (length(inventory$cna_included)) paste(inventory$cna_included, collapse = ", ") else "none"),
    "No scientific recomputation was performed. Exact cached UMAP coordinates/cluster membership are not promised.", "",
    "## Omissions and limitations", inventory$omissions,
    unique(c(inventory$warnings, summaries$warnings)), ""
  )
}

# Bounded binary copy; bytes are reported while even a single large matrix is copied.
.snapshot_copy <- function(source, target, callback, block_bytes = 8L * 1024L^2L) {
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  input <- file(source, "rb"); on.exit(close(input), add = TRUE)
  output <- file(target, "wb"); on.exit(close(output), add = TRUE)
  repeat {
    block <- readBin(input, "raw", n = block_bytes)
    if (!length(block)) break
    writeBin(block, output)
    callback(length(block))
  }
  invisible(TRUE)
}

.snapshot_process <- function(kind, archive, payload, files, report) {
  process <- if (kind == "zip") {
    # zip_process prepares its parameters in the parent, before applying wd.
    # Top-level entries with recursion preserve relative paths instead of
    # flattening leaf filenames (zipr/cherry-pick semantics).
    previous <- getwd()
    tryCatch({
      setwd(payload)
      zip::zip_process()$new(zipfile = archive,
        files = list.files(".", all.files = TRUE, no.. = TRUE), recurse = TRUE,
        include_directories = FALSE, wd = payload, stderr = "|", stdout = "|")
    }, finally = setwd(previous))
  } else zip::unzip_process()$new(zipfile = archive, exdir = payload, stderr = "|", stdout = "|")
  on.exit(if (process$is_alive()) { process$kill(); process$wait(timeout = 5000) }, add = TRUE)
  while (process$is_alive()) {
    report()
    process$poll_io(200)
    # Drain pipes; never print raw subprocess errors (may contain the destination).
    process$read_output(); process$read_error()
    Sys.sleep(0.1)
  }
  if (process$get_exit_status() != 0L) .snapshot_stop("Archive compression/extraction failed; check destination permissions and space.")
  invisible(TRUE)
}

.snapshot_verify_payload <- function(root, records, report) {
  actual <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  if (!setequal(actual, records$path)) .snapshot_stop("Snapshot verification found missing or unexpected payload files.")
  for (i in seq_len(nrow(records))) {
    path <- file.path(root, records$path[[i]])
    if (!identical(as.numeric(file.info(path)$size), records$size_bytes[[i]]) ||
        !identical(.cache_md5(path), records$checksum[[i]])) .snapshot_stop("Snapshot payload size/checksum verification failed.")
    report(i, nrow(records))
  }
}

# Rollback is limited to exact new outputs and the unique operation-owned stage.
.snapshot_remove_owned <- function(path, parent, stage = FALSE) {
  if (!file.exists(path)) return(invisible(TRUE))
  parent <- .snapshot_real(parent)
  if (!identical(.snapshot_real(dirname(path)), parent) ||
      isTRUE(fs::is_link(path)) || !.snapshot_inside(.snapshot_real(path), parent) ||
      (stage && !startsWith(basename(path), ".review-snapshot-"))) {
    .snapshot_stop("Refusing cleanup outside the exact snapshot operation-owned paths.")
  }
  # Do not recursively delete a tree into which links appeared after staging.
  check_tree <- function(directory) {
    if (!dir.exists(directory)) return()
    entries <- as.character(fs::dir_ls(directory, all = TRUE, recurse = FALSE))
    for (entry in entries) {
      if (isTRUE(fs::is_link(entry)) || !.snapshot_inside(.snapshot_real(entry), .snapshot_real(path))) {
        .snapshot_stop("Snapshot cleanup found a link; incomplete output was retained for inspection.")
      }
      if (dir.exists(entry)) check_tree(entry)
    }
  }
  check_tree(path)
  unlink(path, recursive = dir.exists(path), force = TRUE)
  if (file.exists(path)) .snapshot_stop("Incomplete snapshot output could not be removed; inspect the destination before retrying.")
  invisible(TRUE)
}

create_review_snapshot <- function(
  destination, dataset_dir_path, pipeline_state, storage_state, paths_list,
  selected_config, selected_config_path, dataset_config, processed_dir_path,
  results_dir_path, logs_dir_path, config_paths,
  options = snapshot_options(), acknowledge_warnings = FALSE,
  annotation_dirty = FALSE, active_actions = character(),
  datasets_dir_path = dirname(dataset_dir_path), timestamp = Sys.time(),
  progress_callback = NULL, event_callback = NULL,
  rename_output = file.rename, available_space = function(path) ps::ps_disk_usage(path)$available[[1L]]
) {
  # Inner scope ensures rollback/on.exit also happens INSIDE the sanitizing boundary.
  operation_started <- proc.time()[["elapsed"]]
  verified_publication <- FALSE
  run <- function() .snapshot_with_utf8(withCallingHandlers({
    options <- do.call(snapshot_options, options)
    readiness <- dataset_snapshot_readiness(pipeline_state, storage_state, paths_list,
      selected_config, selected_config_path, results_dir_path, dataset_dir_path,
      dataset_config, processed_dir_path, annotation_dirty, active_actions)
    if (!readiness$ready) .snapshot_stop(paste("Snapshot is not ready:", paste(readiness$reasons, collapse = "; ")))
    parent <- validate_snapshot_destination(destination, dataset_dir_path, datasets_dir_path)
    operation_lock <- acquire_dataset_storage_operation(dataset_dir_path)
    on.exit(unlink(operation_lock, recursive = TRUE, force = TRUE), add = TRUE)
    # Caller state is not authority if another session changed it before the lock.
    equivalent <- function(a, b) identical(
      yaml::yaml.load(yaml::as.yaml(a, precision = 17)),
      yaml::yaml.load(yaml::as.yaml(b, precision = 17)))
    if (!equivalent(yaml::read_yaml(config_paths[["pipeline_state.yaml"]]), pipeline_state) ||
        !equivalent(yaml::read_yaml(selected_config_path), selected_config) ||
        !equivalent(yaml::read_yaml(config_paths[["dataset_config.yaml"]]), dataset_config) ||
        !equivalent(load_dataset_storage_state(dataset_dir_path, recover = FALSE), storage_state)) {
      .snapshot_stop("Source configuration or workflow state changed; reload and review again.")
    }
    started <- proc.time()[["elapsed"]]
    logging_warnings <- character()
    emit <- function(status, details = list()) {
      # A logging failure after publication must not turn a verified copy into
      # an unexplained failure or leak a raw destination-bearing exception.
      if (is.function(event_callback)) tryCatch(withCallingHandlers(
        event_callback(status, c(options, details,
          list(elapsed_seconds = proc.time()[["elapsed"]] - started))),
        warning = function(w) stop(simpleError("Export logging unavailable"))),
        error = function(e) {
          logging_warnings <<- "Source export-event logging was unavailable; no destination was recorded."
          invisible(NULL)
        })
    }
    report <- function(stage, fraction, detail, bytes = 0) {
      # Keep the shared cleanup lock live even for multi-hour copies/compression.
      Sys.setFileTime(operation_lock, Sys.time())
      if (is.function(progress_callback)) progress_callback(stage = stage, progress = fraction,
        detail = detail, bytes = bytes, elapsed_seconds = proc.time()[["elapsed"]] - started)
    }
    emit("started") # Freeze log content only after this event.
    report("inventory", 0, "Checking inputs and optional CNA provenance")
    inventory <- build_snapshot_inventory(dataset_dir_path, processed_dir_path, results_dir_path,
      logs_dir_path, config_paths, pipeline_state, storage_state, options)
    validate_snapshot_output_paths(parent, inventory, pipeline_state$dataset_id)
    summaries <- build_snapshot_summaries(pipeline_state, paths_list, selected_config)
    warnings <- unique(c(inventory$warnings, summaries$warnings))
    if (length(warnings) && !isTRUE(acknowledge_warnings)) .snapshot_stop("Review and acknowledge snapshot warnings before copying.")
    if (available_space(parent) < inventory$required_space_bytes + 1024^2) .snapshot_stop("Insufficient destination space for staging and final verification.")
    safe_id <- cna_values_export_safe_name(pipeline_state$dataset_id)
    package_name <- paste0(safe_id, "_review_", format(timestamp, "%Y%m%dT%H%M%S", tz = "UTC"), "_",
      substr(gsub("-", "", basename(tempfile())), 1L, 20L))
    folder <- file.path(parent, package_name)
    archive <- paste0(folder, ".zip")
    if (any(file.exists(c(folder, archive)))) .snapshot_stop("A target package already exists; no overwrite is allowed.")
    stage <- tempfile(pattern = ".review-snapshot-", tmpdir = parent)
    if (!dir.create(stage)) .snapshot_stop("Cannot create snapshot staging directory.")
    stage <- .snapshot_real(stage)
    published <- character()
    pending_publication <- NULL
    committed <- FALSE
    on.exit({
      # Handle an interrupt after the native rename succeeded but before R
      # returned to record it. A moved-away source establishes ownership.
      if (!committed && !is.null(pending_publication) &&
          !file.exists(pending_publication[[1L]]) && file.exists(pending_publication[[2L]])) {
        .snapshot_remove_owned(pending_publication[[2L]], parent)
      }
      if (!committed) for (path in published) .snapshot_remove_owned(path, parent)
      .snapshot_remove_owned(stage, parent, stage = TRUE)
    }, add = TRUE, after = FALSE)
    payload <- file.path(stage, "payload"); dir.create(payload)
    copied <- 0
    files <- inventory$files
    files$checksum <- NA_character_
    for (i in seq_len(nrow(files))) {
      if (isTRUE(fs::is_link(files$source[[i]])) ||
          !.snapshot_inside(.snapshot_real(files$source[[i]]), .snapshot_real(dataset_dir_path))) {
        .snapshot_stop("A source path became a link or escaped the dataset during capture.")
      }
      if (!.snapshot_inventory_matches(files[i, , drop = FALSE])) .snapshot_stop("A source file changed after snapshot review; retry with stable inputs.")
      target <- file.path(payload, files$path[[i]])
      .snapshot_copy(files$source[[i]], target, function(bytes) {
        copied <<- copied + bytes
        report("copy", 0.05 + 0.4 * copied / max(1, inventory$size_bytes),
          paste0("File ", i, "/", nrow(files), ": ", files$path[[i]], " - ", format_storage_bytes(copied), " copied"), copied)
      })
      files$checksum[[i]] <- .cache_md5(target)
    }
    # Full source hashes after copying prevent same-size edits from being accepted.
    for (i in seq_len(nrow(files))) {
      if (!identical(.cache_md5(files$source[[i]]), files$checksum[[i]])) .snapshot_stop("Source content changed during capture; no snapshot was published.")
      report("source_verification", 0.45 + 0.08 * i / nrow(files), paste0("Checking source file ", i, "/", nrow(files)))
    }
    if (!.snapshot_inventory_matches(files)) .snapshot_stop("Source metadata changed during capture; no snapshot was published.")
    writeLines(snapshot_readme(pipeline_state$dataset_id, dataset_config, inventory, summaries, timestamp),
      file.path(payload, "README.md"), useBytes = TRUE)
    data.table::fwrite(summaries$annotations, file.path(payload, "annotation_summary.csv"), na = "NA")
    data.table::fwrite(summaries$filtering, file.path(payload, "filtering_summary.csv"), na = "NA")
    records <- files[, c("path", "size_bytes", "checksum")]
    for (name in c("README.md", "annotation_summary.csv", "filtering_summary.csv")) {
      generated <- file.path(payload, name)
      records <- rbind(records, data.frame(path = name, size_bytes = as.numeric(file.info(generated)$size), checksum = .cache_md5(generated)))
    }
    manifest <- list(schema_version = 1L, dataset_id = pipeline_state$dataset_id,
      created_at = pipeline_state_timestamp(timestamp), implementation = REVIEW_SNAPSHOT_IMPLEMENTATION,
      application = list(name = "scAnnotationPipeline", version = "0.0.0.9000"),
      options = options, omissions = as.list(inventory$omissions), warnings = as.list(warnings),
      cna_values_samples = as.list(inventory$cna_included), checksum_algorithm = "MD5",
      files = lapply(seq_len(nrow(records)), function(i) as.list(records[i, ])))
    manifest_path <- file.path(payload, "snapshot_manifest.yaml")
    yaml::write_yaml(manifest, manifest_path, precision = 17)
    # YAML simplifies homogeneous sequences; compare to the intended serialized form.
    expected_manifest <- yaml::yaml.load(yaml::as.yaml(manifest, precision = 17))
    if (!identical(yaml::read_yaml(manifest_path), expected_manifest)) .snapshot_stop("Generated snapshot manifest could not be validated.")
    records <- rbind(records, data.frame(path = "snapshot_manifest.yaml",
      size_bytes = as.numeric(file.info(manifest_path)$size), checksum = .cache_md5(manifest_path)))
    .snapshot_verify_payload(payload, records, function(i, total) report("folder_verification", 0.53 + 0.06 * i / total, paste0("Verified payload file ", i, "/", total)))
    staged_archive <- file.path(stage, "snapshot.zip")
    if (options$mode != "folder") {
      report("compress", 0.6, "Creating ZIP64-capable archive (compression ratio is not estimated)")
      .snapshot_process("zip", staged_archive, payload, records$path, function() {
        size <- if (file.exists(staged_archive)) file.info(staged_archive)$size else 0
        report("compress", 0.65, paste0("Compressing; archive bytes written: ", format_storage_bytes(size)), size)
      })
      listing <- zip::zip_list(staged_archive)
      .snapshot_relative(listing$filename)
      if (anyDuplicated(listing$filename) || !setequal(listing$filename, records$path)) .snapshot_stop("Archive directory does not match the verified payload.")
      if (!identical(as.numeric(listing$uncompressed_size[match(records$path, listing$filename)]), records$size_bytes)) .snapshot_stop("Archive payload sizes differ from the manifest.")
      extracted <- file.path(stage, "verify"); dir.create(extracted)
      .snapshot_process("unzip", staged_archive, extracted, NULL, function() report("archive_readback", 0.75, "Reading back the complete compressed payload"))
      .snapshot_verify_payload(extracted, records, function(i, total) report("archive_verification", 0.8 + 0.14 * i / total, paste0("Verified archive file ", i, "/", total)))
    }
    # Detect changed files and newly added/removed inputs up to publication.
    rechecked <- build_snapshot_inventory(dataset_dir_path, processed_dir_path, results_dir_path,
      logs_dir_path, config_paths, pipeline_state, storage_state, options)
    if (!identical(rechecked$files, inventory$files) || !.snapshot_inventory_matches(files)) .snapshot_stop("Source inventory changed before publication; retry with stable inputs.")
    targets <- if (options$mode == "folder") list(c(payload, folder)) else if (options$mode == "archive") {
      list(c(staged_archive, archive))
    } else list(c(payload, folder), c(staged_archive, archive))
    for (pair in targets) {
      if (file.exists(pair[[2L]])) .snapshot_stop("A target appeared during publication; no overwrite is allowed.")
      pending_publication <- pair
      if (!isTRUE(rename_output(pair[[1L]], pair[[2L]]))) .snapshot_stop("Could not publish every verified output; new outputs were rolled back.")
      published <- c(published, pair[[2L]])
      pending_publication <- NULL
    }
    # Remove all temporary material before claiming success.
    .snapshot_remove_owned(stage, parent, stage = TRUE)
    committed <- TRUE
    verified_publication <<- TRUE
    emit("completed", list(file_count = nrow(records), payload_bytes = sum(records$size_bytes),
      verified = TRUE, cna_values_sample_count = length(inventory$cna_included)))
    report("completed", 1, "All requested outputs verified and published")
    list(outputs = published, file_count = nrow(records), payload_bytes = sum(records$size_bytes), warnings = unique(c(warnings, logging_warnings)))
  }, warning = function(warning) .snapshot_stop("Snapshot I/O reported a warning; check destination permissions, available space and source stability.")))
  outcome <- tryCatch(run(),
  interrupt = function(e) structure(list(message = if (verified_publication) {
    "Snapshot interrupted after verified publication; completed outputs remain in the chosen destination."
  } else "Snapshot interrupted; operation-owned partial outputs were rolled back."), class = c("snapshot_interrupt", "error", "condition")),
  error = identity)
  if (inherits(outcome, "error")) {
    # Only messages emitted by our own path-free validation are safe to expose.
    safe <- if (inherits(outcome, c("snapshot_error", "snapshot_interrupt"))) {
      conditionMessage(outcome)
    } else "Snapshot failed; check source stability, destination permissions and free space, then retry. No scientific files were changed."
    if (is.function(event_callback)) tryCatch(
      event_callback(if (inherits(outcome, "snapshot_interrupt")) "interrupted" else "failed",
        c(options, list(reason = safe, outputs_verified = verified_publication,
          elapsed_seconds = proc.time()[["elapsed"]] - operation_started))),
      error = function(e) NULL, interrupt = function(e) NULL)
    .snapshot_stop(safe)
  }
  outcome
}
