# Prepared-input import: independent binary copying and staged workspace setup.

dataset_workspace_directories <- function(parent_dir) {
  paths <- list.dirs(parent_dir, recursive = FALSE, full.names = TRUE)
  paths[!startsWith(basename(paths), ".prepared-import-")]
}

.import_path_contains <- function(root, path) {
  key <- function(x) {
    x <- sub("/+$", "", x)
    if (.Platform$OS.type == "windows") tolower(x) else x
  }
  root <- key(root)
  path <- key(path)
  identical(root, path) || startsWith(path, paste0(root, "/"))
}

copy_prepared_input_file <- function(source, destination, copied, total, progress) {
  #' Copy One Prepared File With Actual Byte Progress
  #' @return The number of bytes written. No scientific parsing is performed.
  input <- file(source, open = "rb")
  on.exit(close(input), add = TRUE)
  output <- file(destination, open = "wb")
  on.exit(close(output), add = TRUE)
  written <- 0
  repeat {
    bytes <- readBin(input, "raw", n = 8L * 1024L * 1024L)
    if (!length(bytes)) break
    writeBin(bytes, output)
    written <- written + length(bytes)
    progress(copied + written, total, source)
  }
  written
}

import_prepared_dataset <- function(source_dir, parent_dir, dataset_name,
                                    config, template_path,
                                    progress = function(copied, total, path) NULL,
                                    copy_file = copy_prepared_input_file) {
  #' Create an Independent Workspace From Prepared Inputs
  #'
  #' @description Checks source structure, copies bytes into a hidden staging
  #'   workspace, initializes configuration and ready-to-analyze state, checks
  #'   the copied structure, and publishes by sibling-directory rename. Source
  #'   inputs and pre-existing workspaces are never overwritten.
  #' @param source_dir Prepared-data directory containing Samples.csv.
  #' @param parent_dir Existing workspace parent directory.
  #' @param dataset_name New workspace directory name.
  #' @param config General application configuration.
  #' @param template_path Analysis configuration template (not a preparation script).
  #' @param progress Callback receiving copied bytes, total bytes, source path.
  #' @param copy_file Binary copying function; injectable for I/O failure tests.
  #' @return Published workspace path, metadata, filenames and copy byte count.

  dataset_name <- sanitize_dataset_name(dataset_name)
  if (grepl("[.]$", dataset_name) ||
      grepl("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])[.]", dataset_name, ignore.case = TRUE)) {
    stop("Dataset name must not end with a period or use a Windows-reserved device name.", call. = FALSE)
  }
  if (startsWith(dataset_name, ".prepared-import-")) {
    stop("Dataset name uses the reserved import-staging prefix.", call. = FALSE)
  }
  if (!dir.exists(parent_dir)) {
    stop("Select an existing parent directory for the workspace.", call. = FALSE)
  }
  if (!dir.exists(source_dir)) {
    stop("Select an existing prepared-data directory.", call. = FALSE)
  }
  parent <- normalizePath(parent_dir, winslash = "/", mustWork = TRUE)
  source <- normalizePath(source_dir, winslash = "/", mustWork = TRUE)
  destination <- file.path(parent, dataset_name)
  if (file.exists(destination)) {
    stop("A dataset with this name already exists at this location.", call. = FALSE)
  }
  if (.import_path_contains(source, destination) || .import_path_contains(destination, source)) {
    stop("Source and destination must not overlap; select a parent outside the prepared input.", call. = FALSE)
  }
  checked <- check_prepared_data(source)
  if (!checked$valid) stop(checked$message, call. = FALSE)
  if (!file.exists(template_path)) {
    stop("The analysis dataset_config_template.yaml is missing.", call. = FALSE)
  }
  ds_config <- yaml::read_yaml(template_path)

  # Reject links instead of preserving a dependency on the user's source tree.
  entries <- as.character(fs::dir_ls(source, recurse = TRUE, all = TRUE, type = "any"))
  if (any(fs::is_link(entries))) {
    stop("Prepared inputs contain symbolic links; supply ordinary copied files and directories.", call. = FALSE)
  }
  info <- file.info(entries)
  if (anyNA(info$isdir) || anyNA(info$size)) {
    stop("Prepared inputs could not be inventoried; check that they remain readable.", call. = FALSE)
  }
  files <- entries[!info$isdir]
  sizes <- as.numeric(info$size[!info$isdir])
  total <- sum(sizes)

  paths <- c(processed = config$dataset_paths$processed_dir,
             results = config$dataset_paths$results_dir, logs = config$dataset_paths$logs_dir,
             cache = "cache", dataset = config$config_files$dataset,
             selected = config$config_files$selected,
             state = .pipeline_value_or(config$config_files$state, "pipeline_state.yaml"),
             storage = "storage_state.yaml")
  if (length(paths) != 8L || anyNA(paths) || any(!nzchar(paths)) ||
      any(paths %in% c(".", "..")) || any(grepl("[/\\\\]", paths)) ||
      anyDuplicated(tolower(paths))) {
    stop("Workspace directory/configuration names must be distinct single path components.", call. = FALSE)
  }
  staging <- tempfile(pattern = ".prepared-import-", tmpdir = parent)
  if (!dir.create(staging)) stop("Could not create the import staging directory.", call. = FALSE)
  staging <- normalizePath(staging, winslash = "/", mustWork = TRUE)
  on.exit({
    if (dir.exists(staging)) {
      resolved <- normalizePath(staging, winslash = "/", mustWork = TRUE)
      if (identical(dirname(resolved), parent) && startsWith(basename(resolved), ".prepared-import-")) {
        unlink(resolved, recursive = TRUE, force = TRUE)
      }
    }
  }, add = TRUE)
  for (name in paths[c("processed", "results", "logs", "cache")]) {
    if (!dir.create(file.path(staging, name))) stop("Could not create workspace directories.", call. = FALSE)
  }
  processed <- file.path(staging, paths[["processed"]])
  for (directory in entries[info$isdir]) {
    relative <- as.character(fs::path_rel(directory, start = source))
    dir.create(file.path(processed, relative), recursive = TRUE, showWarnings = FALSE)
  }
  copied <- 0
  progress(0, total, source)
  for (i in seq_along(files)) {
    relative <- as.character(fs::path_rel(files[[i]], start = source))
    written <- copy_file(files[[i]], file.path(processed, relative), copied, total, progress)
    if (length(written) != 1L || is.na(written) || written != sizes[[i]] ||
        file.info(file.path(processed, relative))$size != sizes[[i]]) {
      stop("Copy failed or input size changed: ", relative, call. = FALSE)
    }
    copied <- copied + written
  }
  copied_check <- check_prepared_data(processed)
  if (!copied_check$valid) stop(copied_check$message, call. = FALSE)
  if (!identical(copied_check$samples, checked$samples) ||
      !identical(copied_check$std_names, checked$std_names)) {
    stop("Prepared sample metadata or filenames changed during import; retry with stable inputs.", call. = FALSE)
  }

  ds_config$project_info$dataset_id <- dataset_name
  technology <- unique(stats::na.omit(checked$samples$technology))
  ds_config$project_info$technology <- if (length(technology) == 1L) technology[[1]] else ""
  ds_config$std_names <- checked$std_names
  ds_config$raw_files <- NULL
  yaml::write_yaml(ds_config, file.path(staging, paths[["dataset"]]))
  sample_names <- checked$samples$sample
  yaml::write_yaml(setup_selected_config(sample_names), file.path(staging, paths[["selected"]]))
  state <- new_pipeline_state(dataset_name, sample_names)
  state <- transition_pipeline_step(state, "standardization", "in_progress")
  state <- transition_pipeline_step(state, "standardization", "completed", details = list(
    provenance = "prepared_data_import", validation_scope = "structure_only",
    sample_count = length(sample_names), expression_type = checked$expression_type
  ))
  save_pipeline_state_atomic(state, staging, state_filename = paths[["state"]])
  save_dataset_storage_state_atomic(new_dataset_storage_state(dataset_name), staging)
  record_pipeline_event(staging, dataset = dataset_name, stage = "dataset",
    event_type = "workspace_created", outcome = "completed",
    parameters = list(method = "prepared_data_import", validation_scope = "structure_only",
                      sample_count = length(sample_names), copied_bytes = copied))
  record_pipeline_event(staging, dataset = dataset_name, stage = "state",
    event_type = "pipeline_state_initialized", outcome = "completed",
    parameters = list(schema_version = PIPELINE_STATE_SCHEMA_VERSION))

  # The final path is never used for partial copying. Recheck no-overwrite at
  # publication, as another session may have claimed the name during the copy.
  if (file.exists(destination) || !file.rename(staging, destination)) {
    stop("Could not publish the workspace without overwriting an existing destination.", call. = FALSE)
  }
  list(path = normalizePath(destination, winslash = "/", mustWork = TRUE),
       samples = copied_check$samples, std_names = copied_check$std_names, copied_bytes = copied)
}
