# ==================================================================================================
# Script: 07_utils_state.R
# Purpose: Persistent current-state tracking for dataset and sample workflow steps.
# ==================================================================================================


PIPELINE_STATE_SCHEMA_VERSION <- 1L

PIPELINE_STEP_STATUSES <- c(
  "not_started",
  "in_progress",
  "incomplete",
  "completed",
  "skipped",
  "failed",
  "stale"
)

PIPELINE_DATASET_STEPS <- "standardization"

PIPELINE_SAMPLE_STEPS <- c(
  "clustering",
  "resolution",
  "differential_expression",
  "annotation",
  "cna_configuration",
  "cna_compute",
  "cna_cluster_selection",
  "cna_signal_correlation",
  "cna_thresholds",
  "cna_assignment"
)

PIPELINE_ATOMIC_DECISION_STEPS <- c(
  "resolution",
  "annotation",
  "cna_configuration",
  "cna_cluster_selection",
  "cna_thresholds",
  "cna_assignment"
)

PIPELINE_TRANSITIONS <- list(
  not_started = c("in_progress", "incomplete", "completed", "skipped"),
  in_progress = c("completed", "incomplete", "failed", "skipped"),
  incomplete = c("in_progress", "completed", "skipped", "stale"),
  completed = c("in_progress", "stale"),
  failed = c("in_progress", "incomplete", "skipped"),
  skipped = c("in_progress", "stale"),
  stale = c("in_progress", "incomplete", "skipped")
)

PIPELINE_STALE_DEPENDENCIES <- list(
  standardization = PIPELINE_SAMPLE_STEPS,
  clustering = c(
    "resolution", "differential_expression", "annotation",
    "cna_configuration", "cna_compute", "cna_cluster_selection",
    "cna_signal_correlation", "cna_thresholds", "cna_assignment"
  ),
  resolution = c(
    "differential_expression", "annotation", "cna_configuration",
    "cna_compute", "cna_cluster_selection", "cna_signal_correlation",
    "cna_thresholds", "cna_assignment"
  ),
  differential_expression = c(
    "annotation", "cna_configuration", "cna_compute",
    "cna_cluster_selection", "cna_signal_correlation", "cna_thresholds",
    "cna_assignment"
  ),
  annotation = c(
    "cna_compute", "cna_cluster_selection", "cna_signal_correlation",
    "cna_thresholds", "cna_assignment"
  ),
  cna_configuration = c(
    "cna_compute", "cna_cluster_selection", "cna_signal_correlation",
    "cna_thresholds", "cna_assignment"
  ),
  cna_compute = c(
    "cna_cluster_selection", "cna_signal_correlation", "cna_thresholds",
    "cna_assignment"
  ),
  cna_cluster_selection = c(
    "cna_signal_correlation", "cna_thresholds", "cna_assignment"
  ),
  cna_signal_correlation = c("cna_thresholds", "cna_assignment"),
  cna_thresholds = "cna_assignment",
  cna_assignment = character()
)

PIPELINE_STEP_PREREQUISITES <- list(
  clustering = "standardization",
  resolution = "clustering",
  differential_expression = "resolution",
  annotation = "differential_expression",
  cna_configuration = "annotation",
  cna_compute = c("annotation", "cna_configuration"),
  cna_cluster_selection = "cna_compute",
  cna_signal_correlation = "cna_cluster_selection",
  cna_thresholds = "cna_signal_correlation",
  cna_assignment = "cna_thresholds"
)


.pipeline_value_or <- function(value, fallback) {
  if (is.null(value) || length(value) == 0L) fallback else value[[1]]
}


pipeline_state_timestamp <- function(timestamp = Sys.time()) {
  if (exists("format_pipeline_timestamp", mode = "function")) {
    return(format_pipeline_timestamp(timestamp))
  }
  if (length(timestamp) != 1L || is.na(timestamp)) {
    stop("timestamp must contain one non-missing value.", call. = FALSE)
  }
  timestamp <- as.POSIXct(timestamp, tz = "UTC")
  if (is.na(timestamp)) {
    stop("timestamp could not be converted to POSIXct.", call. = FALSE)
  }
  paste0(format(timestamp, "%Y-%m-%dT%H:%M:%OS3", tz = "UTC"), "Z")
}


new_pipeline_step_record <- function() {
  list(
    status = "not_started",
    attempt = 0L,
    started_at = NULL,
    finished_at = NULL,
    updated_at = NULL,
    reason = NULL,
    details = list()
  )
}


new_pipeline_state <- function(dataset_id, sample_names, timestamp = Sys.time()) {
  dataset_id <- trimws(as.character(dataset_id))
  sample_names <- trimws(as.character(sample_names))
  if (length(dataset_id) != 1L || is.na(dataset_id) || !nzchar(dataset_id)) {
    stop("dataset_id must be one non-empty identifier.", call. = FALSE)
  }
  if (any(is.na(sample_names) | !nzchar(sample_names))) {
    stop("sample_names must contain only non-empty identifiers.", call. = FALSE)
  }
  if (anyDuplicated(sample_names)) {
    stop("sample_names must be unique.", call. = FALSE)
  }

  dataset_steps <- stats::setNames(
    lapply(PIPELINE_DATASET_STEPS, function(step) new_pipeline_step_record()),
    PIPELINE_DATASET_STEPS
  )
  samples <- stats::setNames(lapply(sample_names, function(sample_name) {
    stats::setNames(
      lapply(PIPELINE_SAMPLE_STEPS, function(step) new_pipeline_step_record()),
      PIPELINE_SAMPLE_STEPS
    )
  }), sample_names)

  list(
    schema_version = PIPELINE_STATE_SCHEMA_VERSION,
    dataset_id = dataset_id,
    revision = 0L,
    updated_at = pipeline_state_timestamp(timestamp),
    dataset_steps = dataset_steps,
    samples = samples
  )
}


.validate_pipeline_step_record <- function(record, location) {
  required_fields <- c(
    "status", "attempt", "started_at", "finished_at", "updated_at",
    "reason", "details"
  )
  missing_fields <- setdiff(required_fields, names(record))
  if (length(missing_fields) > 0L) {
    stop(
      location, " is missing fields: ", paste(missing_fields, collapse = ", "),
      call. = FALSE
    )
  }
  if (
    length(record$status) != 1L || is.na(record$status) ||
      !(record$status %in% PIPELINE_STEP_STATUSES)
  ) {
    stop(location, " has an unsupported status.", call. = FALSE)
  }
  if (
    length(record$attempt) != 1L || is.na(record$attempt) ||
      record$attempt < 0 || record$attempt != as.integer(record$attempt)
  ) {
    stop(location, " has an invalid attempt count.", call. = FALSE)
  }
  for (field in c("started_at", "finished_at", "updated_at", "reason")) {
    value <- record[[field]]
    if (!is.null(value) && (length(value) != 1L || is.na(value))) {
      stop(location, "$", field, " must be NULL or one non-missing value.", call. = FALSE)
    }
  }
  if (!is.list(record$details)) {
    stop(location, "$details must be a list.", call. = FALSE)
  }
  if (
    record$status %in% c("incomplete", "failed", "skipped", "stale") &&
      (is.null(record$reason) || !nzchar(trimws(as.character(record$reason))))
  ) {
    stop(location, " requires an actionable reason for status '", record$status, "'.", call. = FALSE)
  }
  invisible(TRUE)
}


validate_pipeline_state <- function(state, dataset_id = NULL, sample_names = NULL) {
  required_fields <- c(
    "schema_version", "dataset_id", "revision", "updated_at",
    "dataset_steps", "samples"
  )
  missing_fields <- setdiff(required_fields, names(state))
  if (length(missing_fields) > 0L) {
    stop("Pipeline state is missing fields: ", paste(missing_fields, collapse = ", "), call. = FALSE)
  }
  if (!identical(as.integer(state$schema_version), PIPELINE_STATE_SCHEMA_VERSION)) {
    stop(
      "Unsupported pipeline-state schema version: ", state$schema_version,
      ". Expected version ", PIPELINE_STATE_SCHEMA_VERSION, ".",
      call. = FALSE
    )
  }
  if (length(state$dataset_id) != 1L || is.na(state$dataset_id) || !nzchar(trimws(state$dataset_id))) {
    stop("Pipeline state has an invalid dataset_id.", call. = FALSE)
  }
  if (!is.null(dataset_id) && !identical(as.character(state$dataset_id), as.character(dataset_id))) {
    stop(
      "Pipeline state dataset_id '", state$dataset_id,
      "' does not match expected dataset '", dataset_id, "'.",
      call. = FALSE
    )
  }
  if (
    length(state$revision) != 1L || is.na(state$revision) ||
      state$revision < 0 || state$revision != as.integer(state$revision)
  ) {
    stop("Pipeline state has an invalid revision.", call. = FALSE)
  }
  if (length(state$updated_at) != 1L || is.na(state$updated_at) || !nzchar(state$updated_at)) {
    stop("Pipeline state has an invalid updated_at timestamp.", call. = FALSE)
  }
  if (!is.list(state$dataset_steps) || !setequal(names(state$dataset_steps), PIPELINE_DATASET_STEPS)) {
    stop("Pipeline state has invalid dataset step names.", call. = FALSE)
  }
  if (!is.list(state$samples)) {
    stop("Pipeline state samples must be a named list.", call. = FALSE)
  }
  if (
    length(state$samples) > 0L &&
      (is.null(names(state$samples)) || any(!nzchar(names(state$samples))) ||
        anyDuplicated(names(state$samples)))
  ) {
    stop("Pipeline state sample identifiers must be non-empty and unique.", call. = FALSE)
  }
  if (!is.null(sample_names) && !setequal(names(state$samples), as.character(sample_names))) {
    stop("Pipeline state samples do not match configured samples.", call. = FALSE)
  }

  for (step in PIPELINE_DATASET_STEPS) {
    .validate_pipeline_step_record(
      state$dataset_steps[[step]],
      paste0("dataset_steps$", step)
    )
  }
  for (sample_name in names(state$samples)) {
    sample_steps <- state$samples[[sample_name]]
    if (!is.list(sample_steps) || !setequal(names(sample_steps), PIPELINE_SAMPLE_STEPS)) {
      stop("Pipeline state has invalid steps for sample '", sample_name, "'.", call. = FALSE)
    }
    for (step in PIPELINE_SAMPLE_STEPS) {
      .validate_pipeline_step_record(
        sample_steps[[step]],
        paste0("samples$", sample_name, "$", step)
      )
    }
  }
  invisible(TRUE)
}


get_pipeline_step <- function(state, step, sample = NULL) {
  if (step %in% PIPELINE_DATASET_STEPS) {
    if (!is.null(sample)) {
      stop("Dataset step '", step, "' must not specify a sample.", call. = FALSE)
    }
    return(state$dataset_steps[[step]])
  }
  if (!(step %in% PIPELINE_SAMPLE_STEPS)) {
    stop("Unknown pipeline step: ", step, call. = FALSE)
  }
  if (is.null(sample) || !(sample %in% names(state$samples))) {
    stop("Unknown or missing sample for step '", step, "'.", call. = FALSE)
  }
  state$samples[[sample]][[step]]
}


.set_pipeline_step <- function(state, step, sample, record) {
  if (step %in% PIPELINE_DATASET_STEPS) {
    state$dataset_steps[[step]] <- record
  } else {
    state$samples[[sample]][[step]] <- record
  }
  state
}


transition_pipeline_step <- function(
  state,
  step,
  status,
  sample = NULL,
  reason = NULL,
  details = NULL,
  timestamp = Sys.time(),
  force = FALSE
) {
  validate_pipeline_state(state)
  if (length(status) != 1L || !(status %in% PIPELINE_STEP_STATUSES)) {
    stop("Unknown pipeline status: ", paste(status, collapse = ", "), call. = FALSE)
  }
  if (!is.null(details) && !is.list(details)) {
    stop("details must be NULL or a named list.", call. = FALSE)
  }
  if (!is.null(details) && length(details) > 0L && is.null(names(details))) {
    stop("details must be a named list.", call. = FALSE)
  }
  if (
    status %in% c("incomplete", "failed", "skipped", "stale") &&
      (is.null(reason) || length(reason) != 1L || is.na(reason) || !nzchar(trimws(reason)))
  ) {
    stop("Status '", status, "' requires an actionable reason.", call. = FALSE)
  }

  record <- get_pipeline_step(state, step, sample)
  current_status <- record$status
  same_status <- identical(current_status, status)
  atomic_completion <- identical(status, "completed") &&
    step %in% PIPELINE_ATOMIC_DECISION_STEPS
  if (
    !isTRUE(force) && !same_status &&
      !(status %in% PIPELINE_TRANSITIONS[[current_status]]) &&
      !atomic_completion
  ) {
    stop(
      "Invalid pipeline transition for '", step, "': ",
      current_status, " -> ", status, ".",
      call. = FALSE
    )
  }

  transition_time <- pipeline_state_timestamp(timestamp)
  if (identical(status, "in_progress") && !identical(current_status, "in_progress")) {
    record$attempt <- as.integer(record$attempt) + 1L
    record$started_at <- transition_time
    record["finished_at"] <- list(NULL)
  }
  if (status %in% c("completed", "incomplete", "failed", "skipped")) {
    record$finished_at <- transition_time
  }
  record$status <- status
  record$updated_at <- transition_time
  record["reason"] <- list(
    if (is.null(reason)) NULL else trimws(as.character(reason))
  )
  if (!is.null(details)) {
    record$details <- utils::modifyList(record$details, details, keep.null = TRUE)
  }

  state <- .set_pipeline_step(state, step, sample, record)
  validate_pipeline_state(state)
  state
}


mark_pipeline_steps_stale <- function(
  state,
  upstream_step,
  reason,
  sample = NULL,
  timestamp = Sys.time()
) {
  if (!(upstream_step %in% names(PIPELINE_STALE_DEPENDENCIES))) {
    stop("Unknown upstream pipeline step: ", upstream_step, call. = FALSE)
  }
  if (is.null(reason) || !nzchar(trimws(reason))) {
    stop("Staleness propagation requires an actionable reason.", call. = FALSE)
  }

  target_samples <- if (identical(upstream_step, "standardization")) {
    names(state$samples)
  } else {
    if (is.null(sample) || !(sample %in% names(state$samples))) {
      stop("A configured sample is required for sample-step invalidation.", call. = FALSE)
    }
    sample
  }
  downstream_steps <- PIPELINE_STALE_DEPENDENCIES[[upstream_step]]

  for (sample_name in target_samples) {
    for (step in downstream_steps) {
      current <- get_pipeline_step(state, step, sample_name)
      if (current$status %in% c("completed", "skipped")) {
        state <- transition_pipeline_step(
          state,
          step = step,
          status = "stale",
          sample = sample_name,
          reason = reason,
          details = list(stale_after = upstream_step),
          timestamp = timestamp
        )
      }
    }
  }
  state
}


update_downstream_stale_reason <- function(
  state,
  upstream_step,
  sample,
  reason,
  timestamp = Sys.time()
) {
  if (!(upstream_step %in% names(PIPELINE_STALE_DEPENDENCIES))) {
    stop("Unknown upstream pipeline step: ", upstream_step, call. = FALSE)
  }
  if (is.null(sample) || !(sample %in% names(state$samples))) {
    stop("A configured sample is required for stale-reason updates.", call. = FALSE)
  }
  if (is.null(reason) || !nzchar(trimws(reason))) {
    stop("A replacement stale reason is required.", call. = FALSE)
  }
  for (step in PIPELINE_STALE_DEPENDENCIES[[upstream_step]]) {
    current <- get_pipeline_step(state, step, sample)
    stale_after <- current$details$stale_after
    if (
      identical(current$status, "stale") &&
        !is.null(stale_after) && upstream_step %in% stale_after
    ) {
      state <- transition_pipeline_step(
        state,
        step = step,
        status = "stale",
        sample = sample,
        reason = reason,
        timestamp = timestamp
      )
    }
  }
  state
}


reset_pipeline_steps <- function(
  state,
  steps,
  sample,
  reason = NULL,
  timestamp = Sys.time()
) {
  if (is.null(sample) || !(sample %in% names(state$samples))) {
    stop("A configured sample is required when resetting sample steps.", call. = FALSE)
  }
  unknown_steps <- setdiff(steps, PIPELINE_SAMPLE_STEPS)
  if (length(unknown_steps) > 0L) {
    stop("Unknown sample steps: ", paste(unknown_steps, collapse = ", "), call. = FALSE)
  }
  reset_time <- pipeline_state_timestamp(timestamp)
  for (step in steps) {
    old_record <- get_pipeline_step(state, step, sample)
    record <- new_pipeline_step_record()
    record$attempt <- old_record$attempt
    record$updated_at <- reset_time
    record["reason"] <- list(reason)
    state <- .set_pipeline_step(state, step, sample, record)
  }
  validate_pipeline_state(state)
  state
}


reconcile_pipeline_state_samples <- function(state, sample_names) {
  sample_names <- trimws(as.character(sample_names))
  if (any(is.na(sample_names) | !nzchar(sample_names)) || anyDuplicated(sample_names)) {
    stop("Configured sample identifiers must be non-empty and unique.", call. = FALSE)
  }
  existing <- names(state$samples)
  added <- setdiff(sample_names, existing)
  removed <- setdiff(existing, sample_names)

  for (sample_name in added) {
    state$samples[[sample_name]] <- stats::setNames(
      lapply(PIPELINE_SAMPLE_STEPS, function(step) new_pipeline_step_record()),
      PIPELINE_SAMPLE_STEPS
    )
  }
  if (length(removed) > 0L) {
    state$samples[removed] <- NULL
  }
  state$samples <- state$samples[sample_names]
  validate_pipeline_state(state, sample_names = sample_names)
  attr(state, "sample_changes") <- list(added = added, removed = removed)
  state
}


.legacy_state_transition <- function(
  state,
  step,
  status,
  sample = NULL,
  reason = NULL,
  details = list(),
  timestamp = Sys.time()
) {
  transition_pipeline_step(
    state,
    step = step,
    status = status,
    sample = sample,
    reason = reason,
    details = utils::modifyList(
      list(provenance = "legacy_inference"),
      details,
      keep.null = TRUE
    ),
    timestamp = timestamp,
    force = TRUE
  )
}


infer_legacy_pipeline_state <- function(
  dataset_dir_path,
  dataset_id,
  sample_names,
  dataset_config,
  selected_config,
  config,
  timestamp = Sys.time()
) {
  state <- new_pipeline_state(dataset_id, sample_names, timestamp)
  processed_dir <- file.path(
    dataset_dir_path,
    .pipeline_value_or(config$dataset_paths$processed_dir, "processed_data")
  )
  results_dir <- file.path(
    dataset_dir_path,
    .pipeline_value_or(config$dataset_paths$results_dir, "results")
  )
  cache_dir <- file.path(dataset_dir_path, "cache")
  std_names <- dataset_config$std_names
  required_sample_files <- unlist(
    std_names[c("expmat", "genes", "cells")],
    use.names = FALSE
  )
  required_sample_files <- required_sample_files[
    !is.na(required_sample_files) & nzchar(required_sample_files)
  ]

  standard_files <- unlist(lapply(sample_names, function(sample_name) {
    file.path(processed_dir, sample_name, required_sample_files)
  }), use.names = FALSE)
  samples_file <- if (!is.null(std_names$samples) && nzchar(std_names$samples)) {
    file.path(processed_dir, std_names$samples)
  } else {
    character()
  }
  standardization_artifacts <- c(standard_files, samples_file)
  if (
    length(sample_names) > 0L && length(standardization_artifacts) > 0L &&
      all(file.exists(standardization_artifacts))
  ) {
    state <- .legacy_state_transition(
      state,
      "standardization",
      "completed",
      details = list(sample_count = length(sample_names)),
      timestamp = timestamp
    )
  } else if (any(file.exists(standardization_artifacts))) {
    state <- .legacy_state_transition(
      state,
      "standardization",
      "incomplete",
      reason = "Legacy standardized artifacts are present but incomplete.",
      timestamp = timestamp
    )
  }

  resolutions <- dataset_config$params$resolutions
  if (is.null(resolutions)) resolutions <- numeric()
  for (sample_name in sample_names) {
    clustering_files <- c(
      file.path(cache_dir, paste0("expmat_filt_", sample_name, ".qs2")),
      file.path(
        cache_dir,
        paste0("cells_filt_clust_res_", resolutions, "_", sample_name, ".qs2")
      )
    )
    if (length(clustering_files) > 0L && all(file.exists(clustering_files))) {
      state <- .legacy_state_transition(
        state,
        "clustering",
        "completed",
        sample = sample_name,
        details = list(resolutions = resolutions),
        timestamp = timestamp
      )
    } else if (any(file.exists(clustering_files))) {
      state <- .legacy_state_transition(
        state,
        "clustering",
        "incomplete",
        sample = sample_name,
        reason = "Only part of the legacy clustering cache set is present.",
        timestamp = timestamp
      )
    }

    selected_resolution <- selected_config$resolutions[[sample_name]]
    if (
      !is.null(selected_resolution) && length(selected_resolution) == 1L &&
        !is.na(selected_resolution) && selected_resolution != 0
    ) {
      state <- .legacy_state_transition(
        state,
        "resolution",
        "completed",
        sample = sample_name,
        details = list(resolution = selected_resolution),
        timestamp = timestamp
      )
    }

    de_dir <- file.path(results_dir, sample_name, "2_de_plots")
    de_matches <- file.path(de_dir, "all_marker_matches.csv")
    de_summary <- if (dir.exists(de_dir)) {
      list.files(de_dir, pattern = "^top_.*_unannotated_gene_count_plot[.]png$", full.names = TRUE)
    } else {
      character()
    }
    if (file.exists(de_matches) && length(de_summary) > 0L) {
      state <- .legacy_state_transition(
        state,
        "differential_expression",
        "completed",
        sample = sample_name,
        timestamp = timestamp
      )
    } else if (file.exists(de_matches) || length(de_summary) > 0L) {
      state <- .legacy_state_transition(
        state,
        "differential_expression",
        "incomplete",
        sample = sample_name,
        reason = "Legacy differential-expression outputs are incomplete.",
        timestamp = timestamp
      )
    }

    cells_path <- if (!is.null(std_names$cells)) {
      file.path(processed_dir, sample_name, std_names$cells)
    } else {
      ""
    }
    if (nzchar(cells_path) && file.exists(cells_path)) {
      cell_columns <- tryCatch(
        names(data.table::fread(cells_path, nrows = 0L, showProgress = FALSE)),
        error = function(error) character()
      )
      if ("cell_type_pre_cna" %in% cell_columns) {
        state <- .legacy_state_transition(
          state,
          "annotation",
          "completed",
          sample = sample_name,
          timestamp = timestamp
        )
      }
    }

    refs <- selected_config$cna_ref_cells[[sample_name]]
    candidates <- selected_config$cna_pot_mal_cells[[sample_name]]
    refs_set <- !is.null(refs) && length(refs) > 0L
    candidates_set <- !is.null(candidates) && length(candidates) > 0L
    if (refs_set && candidates_set) {
      state <- .legacy_state_transition(
        state,
        "cna_configuration",
        "completed",
        sample = sample_name,
        details = list(
          reference_cell_types = unname(refs),
          potentially_malignant_cell_types = unname(candidates)
        ),
        timestamp = timestamp
      )
    } else if (refs_set || candidates_set) {
      state <- .legacy_state_transition(
        state,
        "cna_configuration",
        "incomplete",
        sample = sample_name,
        reason = "Legacy CNA configuration has only one required cell-type selection.",
        timestamp = timestamp
      )
    }

    cna_files <- file.path(
      cache_dir,
      c(paste0("cna_matrix_", sample_name, ".qs2"), paste0("hclust_", sample_name, ".qs2"))
    )
    if (all(file.exists(cna_files))) {
      state <- .legacy_state_transition(
        state,
        "cna_compute",
        "completed",
        sample = sample_name,
        timestamp = timestamp
      )
    } else if (any(file.exists(cna_files))) {
      state <- .legacy_state_transition(
        state,
        "cna_compute",
        "incomplete",
        sample = sample_name,
        reason = "Legacy base-CNA artifacts are incomplete.",
        timestamp = timestamp
      )
    }

    subclones <- selected_config$cna_ward_ref_cluster[[sample_name]]
    if (!is.null(subclones) && length(subclones) > 0L) {
      state <- .legacy_state_transition(
        state,
        "cna_cluster_selection",
        "completed",
        sample = sample_name,
        details = list(subclone_count = length(subclones)),
        timestamp = timestamp
      )

      signal_files <- file.path(
        cache_dir,
        paste0("cna_sig_cor_", sample_name, "_subclone_", seq_along(subclones), ".qs2")
      )
      if (all(file.exists(signal_files))) {
        state <- .legacy_state_transition(
          state,
          "cna_signal_correlation",
          "completed",
          sample = sample_name,
          details = list(subclone_count = length(subclones)),
          timestamp = timestamp
        )
      } else if (any(file.exists(signal_files))) {
        state <- .legacy_state_transition(
          state,
          "cna_signal_correlation",
          "incomplete",
          sample = sample_name,
          reason = "Legacy signal/correlation artifacts do not cover every selected subclone.",
          timestamp = timestamp
        )
      }
    }

    thresholds <- selected_config$cna_thresholds[[sample_name]]
    if (!is.null(thresholds) && length(thresholds) > 0L) {
      threshold_status <- if (!is.null(subclones) && length(thresholds) == length(subclones)) {
        "completed"
      } else {
        "incomplete"
      }
      state <- .legacy_state_transition(
        state,
        "cna_thresholds",
        threshold_status,
        sample = sample_name,
        reason = if (threshold_status == "incomplete") {
          "Legacy thresholds do not match the selected subclone count."
        } else NULL,
        details = list(subclone_count = length(thresholds)),
        timestamp = timestamp
      )
    }

    cna_results_dir <- file.path(results_dir, sample_name, "3_cna_plots")
    final_outputs <- file.path(
      cna_results_dir,
      c(
        paste0("cna_summary_heatmap_", sample_name, ".png"),
        paste0("cna_umap_assigned_", sample_name, ".png")
      )
    )
    if (all(file.exists(final_outputs))) {
      state <- .legacy_state_transition(
        state,
        "cna_assignment",
        "completed",
        sample = sample_name,
        timestamp = timestamp
      )
    } else if (any(file.exists(final_outputs))) {
      state <- .legacy_state_transition(
        state,
        "cna_assignment",
        "incomplete",
        sample = sample_name,
        reason = "Legacy final CNA outputs are incomplete.",
        timestamp = timestamp
      )
    }
  }

  state <- reconcile_pipeline_state_dependencies(state, timestamp = timestamp)
  validate_pipeline_state(state, dataset_id, sample_names)
  state
}


load_or_initialize_pipeline_state <- function(
  dataset_dir_path,
  dataset_id,
  sample_names,
  dataset_config = list(),
  selected_config = list(),
  config = list(),
  state_filename = "pipeline_state.yaml",
  infer_legacy = TRUE,
  timestamp = Sys.time()
) {
  paths <- pipeline_state_paths(dataset_dir_path, state_filename)
  state_exists <- file.exists(paths$primary) || file.exists(paths$backup)

  if (state_exists) {
    state <- load_pipeline_state(
      dataset_dir_path,
      dataset_id = dataset_id,
      state_filename = state_filename
    )
    state <- reconcile_pipeline_state_samples(state, sample_names)
    changes <- attr(state, "sample_changes")
    attr(state, "sample_changes") <- NULL
    state <- reconcile_pipeline_state_dependencies(state, timestamp = timestamp)
    dependency_changes <- attr(state, "dependency_changes")
    attr(state, "dependency_changes") <- NULL
    if (
      length(changes$added) > 0L || length(changes$removed) > 0L ||
        length(dependency_changes) > 0L
    ) {
      state <- save_pipeline_state_atomic(
        state,
        dataset_dir_path,
        state_filename = state_filename,
        timestamp = timestamp
      )
    }
    attr(state, "initialized") <- FALSE
    attr(state, "sample_changes") <- changes
    attr(state, "dependency_changes") <- dependency_changes
    return(state)
  }

  state <- if (isTRUE(infer_legacy)) {
    infer_legacy_pipeline_state(
      dataset_dir_path = dataset_dir_path,
      dataset_id = dataset_id,
      sample_names = sample_names,
      dataset_config = dataset_config,
      selected_config = selected_config,
      config = config,
      timestamp = timestamp
    )
  } else {
    new_pipeline_state(dataset_id, sample_names, timestamp)
  }
  state <- save_pipeline_state_atomic(
    state,
    dataset_dir_path,
    state_filename = state_filename,
    timestamp = timestamp
  )
  attr(state, "initialized") <- TRUE
  attr(state, "sample_changes") <- list(added = character(), removed = character())
  state
}


pipeline_step_readiness <- function(state, step, sample) {
  if (!(step %in% PIPELINE_SAMPLE_STEPS)) {
    stop("Readiness is defined only for sample steps.", call. = FALSE)
  }
  prerequisites <- PIPELINE_STEP_PREREQUISITES[[step]]
  if (is.null(prerequisites)) {
    return(list(ready = TRUE, unmet = character(), reasons = character()))
  }

  records <- lapply(prerequisites, function(prerequisite) {
    if (prerequisite %in% PIPELINE_DATASET_STEPS) {
      get_pipeline_step(state, prerequisite)
    } else {
      get_pipeline_step(state, prerequisite, sample)
    }
  })
  statuses <- vapply(records, `[[`, character(1), "status")
  unmet <- prerequisites[statuses != "completed"]
  reasons <- vapply(seq_along(unmet), function(index) {
    prerequisite <- unmet[[index]]
    record <- records[[match(prerequisite, prerequisites)]]
    paste0(
      prerequisite, " is ", record$status,
      if (!is.null(record$reason)) paste0(": ", record$reason) else ""
    )
  }, character(1))
  list(ready = length(unmet) == 0L, unmet = unmet, reasons = reasons)
}


clustering_selection_preset <- function(state, sample_names, preset = c("all", "stale", "incomplete", "clear")) {
  preset <- match.arg(preset)
  statuses <- vapply(sample_names, function(sample) get_pipeline_step(state, "clustering", sample)$status, character(1))
  switch(preset,
    all = sample_names,
    stale = sample_names[statuses == "stale"],
    incomplete = sample_names[statuses %in% c("not_started", "failed", "stale")],
    clear = character()
  )
}

validate_clustering_selection <- function(state, selected_samples, sample_names) {
  if (!length(selected_samples)) stop("Select at least one sample for clustering.", call. = FALSE)
  if (anyNA(selected_samples) || anyDuplicated(selected_samples) ||
      !all(selected_samples %in% sample_names) || !all(selected_samples %in% names(state$samples))) {
    stop("The selection contains invalid or duplicate samples. Reopen the clustering dialog.", call. = FALSE)
  }
  indices <- which(sample_names %in% selected_samples)
  active <- sample_names[indices][vapply(sample_names[indices], function(sample) {
    identical(get_pipeline_step(state, "clustering", sample)$status, "in_progress")
  }, logical(1))]
  if (length(active)) {
    stop("Clustering is already in progress for: ", paste(active, collapse = ", "), ". Deselect these samples.", call. = FALSE)
  }
  indices
}

summarize_de_annotation_review <- function(state, processed_samples, sample_names = names(state$samples)) {
  # Read-only completion navigation, in processing order. Never send users to
  # unrelated samples or treat blocked annotation work as ready for review.
  processed <- intersect(as.character(processed_samples), intersect(sample_names, names(state$samples)))
  pending <- processed[vapply(processed, function(sample) {
    !get_pipeline_step(state, "annotation", sample)$status %in% c("completed", "skipped")
  }, logical(1))]
  ready <- pending[vapply(pending, function(sample) {
    pipeline_step_readiness(state, "annotation", sample)$ready
  }, logical(1))]
  target <- if (length(ready)) ready[[1]] else NULL
  list(
    processed_samples = processed,
    pending_samples = pending,
    ready_samples = ready,
    blocked_samples = setdiff(pending, ready),
    target_sample = target,
    target_index = if (is.null(target)) NULL else match(target, sample_names)
  )
}


pipeline_cna_is_omitted <- function(state, sample) {
  configuration <- get_pipeline_step(state, "cna_configuration", sample)
  identical(configuration$status, "skipped") &&
    isTRUE(configuration$details$omitted_by_user) &&
    pipeline_step_readiness(state, "cna_configuration", sample)$ready
}


synchronize_pipeline_cna_omission <- function(state, sample, timestamp = Sys.time()) {
  if (!pipeline_cna_is_omitted(state, sample)) return(state)
  configuration <- get_pipeline_step(state, "cna_configuration", sample)
  computation <- get_pipeline_step(state, "cna_compute", sample)
  reason <- paste0("CNA was explicitly omitted: ", configuration$reason)
  if (identical(computation$status, "in_progress") || (
    identical(computation$status, "skipped") &&
    identical(computation$reason, reason) &&
    identical(computation$details$preflight_status, "omitted") &&
    isTRUE(computation$details$omitted_by_user)
  )) return(state)
  transition_pipeline_step(
    state, "cna_compute", "skipped", sample,
    reason = reason,
    details = list(preflight_status = "omitted", omitted_by_user = TRUE, stale_after = NULL),
    timestamp = timestamp, force = TRUE
  )
}


reconcile_pipeline_state_dependencies <- function(state, timestamp = Sys.time()) {
  validate_pipeline_state(state)
  changed <- character()
  for (sample_name in names(state$samples)) {
    for (step in PIPELINE_SAMPLE_STEPS) {
      if (identical(step, "cna_compute") && pipeline_cna_is_omitted(state, sample_name)) {
        before <- get_pipeline_step(state, step, sample_name)
        state <- synchronize_pipeline_cna_omission(state, sample_name, timestamp)
        if (!identical(before, get_pipeline_step(state, step, sample_name))) {
          changed <- c(changed, paste(sample_name, step, sep = "/"))
        }
        next
      }
      record <- get_pipeline_step(state, step, sample_name)
      if (!(record$status %in% c("completed", "skipped"))) next
      readiness <- pipeline_step_readiness(state, step, sample_name)
      if (readiness$ready) next

      reason <- paste0(
        "Previously recorded work is stale because prerequisites are not complete: ",
        paste(readiness$reasons, collapse = "; "), "."
      )
      state <- transition_pipeline_step(
        state,
        step = step,
        status = "stale",
        sample = sample_name,
        reason = reason,
        details = list(stale_after = readiness$unmet),
        timestamp = timestamp
      )
      changed <- c(changed, paste(sample_name, step, sep = "/"))
    }
  }
  attr(state, "dependency_changes") <- changed
  state
}


reconcile_pipeline_state_cache <- function(
  state,
  paths_list,
  dataset_config,
  selected_config,
  dataset_dir_path,
  gene_positions,
  timestamp = Sys.time()
) {
  validate_pipeline_state(state)
  changes <- character()
  manifest <- tryCatch(
    load_cache_manifest(dataset_dir_path, recover = FALSE),
    error = function(error) NULL
  )

  cache_available <- function(filename) {
    !is.null(manifest) && cache_check_available(
      filename,
      dataset_dir_path,
      manifest = manifest
    )
  }

  mark_cache_stale <- function(current_state, step, sample_name, reason) {
    record <- get_pipeline_step(current_state, step, sample_name)
    if (!(record$status %in% c("completed", "skipped"))) return(current_state)
    current_state <- transition_pipeline_step(
      current_state,
      step = step,
      status = "stale",
      sample = sample_name,
      reason = reason,
      details = list(stale_after = "cache_validation"),
      timestamp = timestamp
    )
    current_state <- mark_pipeline_steps_stale(
      current_state,
      upstream_step = step,
      sample = sample_name,
      reason = reason,
      timestamp = timestamp
    )
    changes <<- c(changes, paste(sample_name, step, sep = "/"))
    current_state
  }

  sample_names <- basename(paths_list$sample_dir_paths)
  for (sample_index in seq_along(sample_names)) {
    sample_name <- sample_names[[sample_index]]

    clustering_record <- get_pipeline_step(state, "clustering", sample_name)
    if (clustering_record$status %in% c("completed", "skipped")) {
      resolutions <- dataset_config$params$resolutions
      expression_valid <- cache_available(
        paste0("expmat_filt_", sample_name, ".qs2")
      )
      cluster_valid <- length(resolutions) > 0L && all(vapply(
        resolutions,
        function(resolution) {
          cache_available(
            paste0(
              "cells_filt_clust_res_", resolution, "_", sample_name, ".qs2"
            )
          )
        },
        logical(1)
      ))
      if (!expression_valid || !cluster_valid) {
        state <- mark_cache_stale(
          state,
          "clustering",
          sample_name,
          "Clustering cache is missing, corrupt, or no longer matches its standardized inputs and parameters. Rerun clustering."
        )
      }
    }

    cna_record <- get_pipeline_step(state, "cna_compute", sample_name)
    if (identical(cna_record$status, "completed")) {
      cna_valid <- cache_available(paste0("cna_matrix_", sample_name, ".qs2")) &&
        cache_available(paste0("hclust_", sample_name, ".qs2"))
      if (!cna_valid) {
        state <- mark_cache_stale(
          state,
          "cna_compute",
          sample_name,
          "Base CNA cache is missing, corrupt, or no longer matches annotation/configuration inputs. Recompute CNA."
        )
      }
    }

    signal_record <- get_pipeline_step(state, "cna_signal_correlation", sample_name)
    if (identical(signal_record$status, "completed")) {
      subclones <- selected_config$cna_ward_ref_cluster[[sample_name]]
      signal_valid <- length(subclones) > 0L && all(vapply(
        seq_along(subclones),
        function(i) cache_available(
          paste0("cna_sig_cor_", sample_name, "_subclone_", i, ".qs2")
        ),
        logical(1)
      ))
      if (!signal_valid) {
        state <- mark_cache_stale(
          state,
          "cna_signal_correlation",
          sample_name,
          "Signal/correlation cache is missing, corrupt, or no longer matches the malignant-cluster selection. Recompute signal/correlation."
        )
      }
    }
  }

  attr(state, "cache_changes") <- unique(changes)
  state
}


pipeline_status_presentation <- function(record, label = NULL) {
  .validate_pipeline_step_record(record, "pipeline status record")
  labels <- c(
    not_started = "Not started",
    in_progress = "In progress",
    incomplete = "Incomplete",
    completed = "Complete",
    skipped = "Skipped",
    failed = "Failed",
    stale = "Stale"
  )
  classes <- c(
    not_started = "secondary",
    in_progress = "info",
    incomplete = "warning",
    completed = "success",
    skipped = "secondary",
    failed = "danger",
    stale = "warning"
  )
  icons <- c(
    not_started = "circle",
    in_progress = "spinner",
    incomplete = "exclamation-circle",
    completed = "check-circle",
    skipped = "forward",
    failed = "circle-xmark",
    stale = "clock-rotate-left"
  )
  status <- record$status
  status_label <- unname(labels[[status]])
  list(
    status = status,
    label = if (is.null(label)) status_label else paste0(label, ": ", status_label),
    class = unname(classes[[status]]),
    icon = unname(icons[[status]]),
    reason = record$reason
  )
}


pipeline_state_paths <- function(dataset_dir_path, state_filename = "pipeline_state.yaml") {
  if (
    length(dataset_dir_path) != 1L || is.na(dataset_dir_path) ||
      !nzchar(trimws(dataset_dir_path))
  ) {
    stop("dataset_dir_path must be one non-empty path.", call. = FALSE)
  }
  if (length(state_filename) != 1L || is.na(state_filename) || !nzchar(state_filename)) {
    stop("state_filename must be one non-empty filename.", call. = FALSE)
  }
  primary <- file.path(dataset_dir_path, state_filename)
  list(
    primary = primary,
    backup = paste0(primary, ".bak"),
    lock = paste0(primary, ".lock")
  )
}


acquire_pipeline_state_lock <- function(
  lock_path,
  timeout_seconds = 2,
  stale_after_seconds = 60,
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
      stop("Timed out waiting for pipeline-state lock: ", lock_path, call. = FALSE)
    }
    Sys.sleep(poll_seconds)
  }
}


load_pipeline_state <- function(
  dataset_dir_path,
  dataset_id = NULL,
  sample_names = NULL,
  state_filename = "pipeline_state.yaml",
  recover = TRUE
) {
  paths <- pipeline_state_paths(dataset_dir_path, state_filename)
  read_and_validate <- function(path) {
    state <- yaml::read_yaml(path)
    validate_pipeline_state(state, dataset_id = dataset_id, sample_names = sample_names)
    state
  }

  primary_error <- NULL
  if (file.exists(paths$primary)) {
    primary <- tryCatch(read_and_validate(paths$primary), error = identity)
    if (!inherits(primary, "error")) return(primary)
    primary_error <- conditionMessage(primary)
  } else {
    primary_error <- "primary state file is missing"
  }

  if (isTRUE(recover) && file.exists(paths$backup)) {
    backup <- tryCatch(read_and_validate(paths$backup), error = identity)
    if (!inherits(backup, "error")) {
      if (!file.copy(paths$backup, paths$primary, overwrite = TRUE)) {
        stop("Could not restore pipeline state from backup.", call. = FALSE)
      }
      warning(
        "Recovered pipeline state from backup because ", primary_error, ".",
        call. = FALSE
      )
      return(backup)
    }
  }

  stop("Could not load pipeline state: ", primary_error, ".", call. = FALSE)
}


save_pipeline_state_atomic <- function(
  state,
  dataset_dir_path,
  state_filename = "pipeline_state.yaml",
  timestamp = Sys.time(),
  lock_timeout_seconds = 2,
  stale_lock_seconds = 60
) {
  if (!dir.exists(dataset_dir_path)) {
    stop("Dataset directory does not exist: ", dataset_dir_path, call. = FALSE)
  }
  validate_pipeline_state(state)
  paths <- pipeline_state_paths(dataset_dir_path, state_filename)
  acquire_pipeline_state_lock(
    paths$lock,
    timeout_seconds = lock_timeout_seconds,
    stale_after_seconds = stale_lock_seconds
  )
  on.exit(unlink(paths$lock, recursive = TRUE, force = TRUE), add = TRUE)

  if (file.exists(paths$primary)) {
    current <- load_pipeline_state(
      dataset_dir_path,
      dataset_id = state$dataset_id,
      state_filename = state_filename
    )
    if (!identical(as.integer(current$revision), as.integer(state$revision))) {
      stop(
        "Pipeline state revision conflict: disk is ", current$revision,
        " but the caller has ", state$revision, ". Reload before saving.",
        call. = FALSE
      )
    }
  } else if (as.integer(state$revision) != 0L) {
    stop("Cannot create a missing state file from a non-zero revision.", call. = FALSE)
  }

  saved_state <- state
  saved_state$revision <- as.integer(saved_state$revision) + 1L
  saved_state$updated_at <- pipeline_state_timestamp(timestamp)
  validate_pipeline_state(saved_state)

  temporary_path <- tempfile(
    pattern = paste0(".", state_filename, "-"),
    tmpdir = dataset_dir_path,
    fileext = ".tmp"
  )
  on.exit(if (file.exists(temporary_path)) file.remove(temporary_path), add = TRUE)
  yaml::write_yaml(saved_state, temporary_path)
  temporary_state <- yaml::read_yaml(temporary_path)
  validate_pipeline_state(temporary_state, dataset_id = saved_state$dataset_id)

  if (file.exists(paths$backup) && !file.remove(paths$backup)) {
    stop("Could not replace the previous pipeline-state backup.", call. = FALSE)
  }
  had_primary <- file.exists(paths$primary)
  if (had_primary && !file.rename(paths$primary, paths$backup)) {
    stop("Could not move the current pipeline state to its backup.", call. = FALSE)
  }
  if (!file.rename(temporary_path, paths$primary)) {
    if (had_primary && file.exists(paths$backup)) {
      file.rename(paths$backup, paths$primary)
    }
    stop("Could not install the new pipeline state; the previous state was restored.", call. = FALSE)
  }

  persisted <- yaml::read_yaml(paths$primary)
  validate_pipeline_state(persisted, dataset_id = saved_state$dataset_id)
  persisted
}


save_pipeline_state_at_path <- function(
  state,
  state_path,
  timestamp = Sys.time()
) {
  if (length(state_path) != 1L || is.na(state_path) || !nzchar(state_path)) {
    stop("state_path must be one non-empty path.", call. = FALSE)
  }
  save_pipeline_state_atomic(
    state,
    dataset_dir_path = dirname(state_path),
    state_filename = basename(state_path),
    timestamp = timestamp
  )
}


persist_pipeline_step_update <- function(
  state,
  state_path,
  step,
  status,
  sample = NULL,
  reason = NULL,
  details = NULL,
  invalidate_downstream = FALSE,
  invalidation_reason = NULL,
  downstream_stale_reason = NULL,
  timestamp = Sys.time(),
  force = FALSE
) {
  updated <- state
  if (isTRUE(invalidate_downstream)) {
    if (is.null(invalidation_reason) || !nzchar(trimws(invalidation_reason))) {
      stop("invalidation_reason is required when invalidating downstream state.", call. = FALSE)
    }
    updated <- mark_pipeline_steps_stale(
      updated,
      upstream_step = step,
      sample = sample,
      reason = invalidation_reason,
      timestamp = timestamp
    )
  }
  updated <- transition_pipeline_step(
    updated,
    step = step,
    status = status,
    sample = sample,
    reason = reason,
    details = details,
    timestamp = timestamp,
    force = force
  )
  if (identical(step, "cna_configuration")) {
    computation <- get_pipeline_step(updated, "cna_compute", sample)
    if (status %in% c("completed", "incomplete") && (
      isTRUE(computation$details$omitted_by_user) ||
      identical(computation$details$preflight_status, "omitted")
    )) {
      updated <- reset_pipeline_steps(
        updated, c("cna_compute", PIPELINE_STALE_DEPENDENCIES$cna_compute),
        sample, timestamp = timestamp
      )
    }
    updated <- synchronize_pipeline_cna_omission(updated, sample, timestamp)
  }
  if (!is.null(downstream_stale_reason)) {
    updated <- update_downstream_stale_reason(
      updated,
      upstream_step = step,
      sample = sample,
      reason = downstream_stale_reason,
      timestamp = timestamp
    )
  }
  save_pipeline_state_at_path(updated, state_path, timestamp)
}
