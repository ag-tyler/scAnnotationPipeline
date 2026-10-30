# Explicit one-time recovery of the F15-R01 YAML precision defect. This is not
# called during normal loading: stale work must never be silently promoted.
recover_dataset_cache_precision <- function(
  dataset_dir_path, paths_list, dataset_config, selected_config,
  dry_run = TRUE, state_filename = "pipeline_state.yaml"
) {
  state_paths <- pipeline_state_paths(dataset_dir_path, state_filename)
  current <- yaml::read_yaml(state_paths$primary)
  previous <- yaml::read_yaml(state_paths$backup)
  validate_pipeline_state(current)
  validate_pipeline_state(previous)
  if (!identical(current$dataset_id, previous$dataset_id) ||
      !setequal(names(current$samples), names(previous$samples)) ||
      previous$revision >= current$revision) {
    stop("State backup does not match the current dataset and revision.", call. = FALSE)
  }
  plan <- .cache_manifest_precision_plan(dataset_dir_path)
  if (any(plan$report$action == "blocked")) {
    stop("Cache precision recovery is blocked; inspect repair_cache_manifest_precision() first.", call. = FALSE)
  }
  proposed <- current
  restored <- character()
  expected_reason <- paste0(
    "Clustering cache is missing, corrupt, or no longer matches its standardized ",
    "inputs and parameters. Rerun clustering."
  )
  validate_artifact <- function(filename, dependencies) {
    record <- plan$manifest$artifacts[[filename]]
    path <- file.path(dataset_dir_path, "cache", filename)
    if (is.null(dependencies) || !.cache_record_matches(record, path, dependencies)) {
      stop("Current scientific inputs do not validate cache: ", filename, ".", call. = FALSE)
    }
    object <- qs2::qs_read(path)
    validate_cache_object(object, record$artifact_type, filename)
    object
  }
  normalize_labels <- function(labels) {
    labels <- as.character(labels)
    labels[!is.na(labels) & labels == ""] <- NA_character_
    labels
  }
  for (index in seq_along(paths_list$sample_dir_paths)) {
    sample_name <- basename(paths_list$sample_dir_paths[[index]])
    clustering <- get_pipeline_step(current, "clustering", sample_name)
    if (!identical(clustering$status, "stale") ||
        !identical(clustering$reason, expected_reason) ||
        !identical(clustering$details$stale_after, "cache_validation")) next
    if (!identical(get_pipeline_step(previous, "clustering", sample_name)$status, "completed")) {
      stop("No completed clustering snapshot exists for ", sample_name, ".", call. = FALSE)
    }
    validate_artifact(paste0("expmat_filt_", sample_name, ".qs2"),
      filter_cache_dependencies(paths_list, index, dataset_config))
    selected_resolution <- selected_config$resolutions[[sample_name]]
    if (is.null(selected_resolution) || length(dataset_config$params$resolutions) == 0L) {
      stop("Missing resolution decisions for ", sample_name, ".", call. = FALSE)
    }
    selected_cells <- NULL
    for (resolution in unique(c(dataset_config$params$resolutions, selected_resolution))) {
      cells <- validate_artifact(
        paste0("cells_filt_clust_res_", resolution, "_", sample_name, ".qs2"),
        clustering_cache_dependencies(paths_list, index, dataset_config, resolution)
      )
      if (identical(as.numeric(resolution), as.numeric(selected_resolution))) selected_cells <- cells
    }
    raw_cells <- data.table::fread(paths_list$cell_file_paths[[index]])
    validate_annotation_cell_alignment(selected_cells, raw_cells)
    saved_labels <- raw_cells$cell_type[match(selected_cells$cell_name, raw_cells$cell_name)]
    if (!identical(normalize_labels(selected_cells$cell_type), normalize_labels(saved_labels))) {
      stop("Saved annotations disagree with the selected cache for ", sample_name, ".", call. = FALSE)
    }
    for (step in c("clustering", "resolution", "differential_expression", "annotation", "cna_configuration")) {
      now <- get_pipeline_step(current, step, sample_name)
      before <- get_pipeline_step(previous, step, sample_name)
      if (!identical(now$status, "stale") || !identical(now$reason, expected_reason)) next
      if (!(before$status %in% c("completed", "skipped")) ||
          !identical(now$attempt, before$attempt) ||
          !identical(now$started_at, before$started_at) ||
          !identical(now$finished_at, before$finished_at)) {
        stop("Prior completion cannot be safely established: ", sample_name, "/", step, ".", call. = FALSE)
      }
      if (step %in% c("resolution", "differential_expression", "annotation") &&
          !is.null(before$details$resolution) &&
          !identical(as.numeric(before$details$resolution), as.numeric(selected_resolution))) {
        stop("Resolution decision changed since the state backup.", call. = FALSE)
      }
      if (step == "cna_configuration") {
        if (before$status == "skipped" && !isTRUE(before$details$omitted_by_user)) {
          stop("Prior CNA omission was not explicit.", call. = FALSE)
        }
        if (before$status == "completed") {
          references <- selected_config$cna_ref_cells[[sample_name]]
          candidates <- selected_config$cna_pot_mal_cells[[sample_name]]
          if (!length(references) || !length(candidates) ||
              !setequal(references, before$details$reference_cell_types) ||
              !setequal(candidates, before$details$potentially_malignant_cell_types)) {
            stop("Saved CNA configuration differs from the prior state snapshot.", call. = FALSE)
          }
        }
      }
      proposed$samples[[sample_name]][[step]] <- before
      restored <- c(restored, paste(sample_name, step, sep = "/"))
    }
  }
  validate_pipeline_state(proposed)
  backup_dir <- NULL
  if (!isTRUE(dry_run) && (length(restored) || any(plan$report$action == "repair"))) {
    # Preserve both state generations before atomic writers rotate their usual
    # backups. A failed state write leaves conservative stale states, not false
    # completion; the original evidence remains available here for retry.
    backup_dir <- tempfile("cache-precision-recovery-", tmpdir = dataset_dir_path)
    dir.create(backup_dir)
    manifest_paths <- cache_manifest_paths(dataset_dir_path)
    originals <- c(state_paths$primary, state_paths$backup, manifest_paths$primary,
      if (file.exists(manifest_paths$backup)) manifest_paths$backup)
    if (!all(file.copy(originals, backup_dir))) stop("Could not preserve recovery evidence.", call. = FALSE)
    repair_cache_manifest_precision(dataset_dir_path, dry_run = FALSE)
    if (length(restored)) save_pipeline_state_at_path(proposed, state_paths$primary)
  }
  list(cache = plan$report, restored_steps = restored, backup_dir = backup_dir, dry_run = dry_run)
}
