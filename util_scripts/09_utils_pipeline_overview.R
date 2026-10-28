# ==================================================================================================
# Script: 09_utils_pipeline_overview.R
# Purpose: Pure, read-only summaries for the Start Menu pipeline status overview.
# ==================================================================================================


PIPELINE_OVERVIEW_STAGES <- list(
  clustering = list(label = "Clustering", step = "clustering"),
  resolution = list(label = "Resolution", step = "resolution"),
  differential_expression = list(
    label = "Differential expression",
    step = "differential_expression"
  ),
  annotation = list(label = "Annotation", step = "annotation"),
  cna_configuration = list(label = "CNA configuration", step = "cna_configuration"),
  cna_analysis = list(label = "CNA analysis", step = NULL)
)


new_pipeline_overview_record <- function(status, reason = NULL) {
  if (
    status %in% c("incomplete", "failed", "skipped", "stale") &&
      (is.null(reason) || !nzchar(reason))
  ) {
    reason <- "See sample details."
  }
  record <- new_pipeline_step_record()
  record$status <- status
  record["reason"] <- list(reason)
  record
}


pipeline_cna_analysis_record <- function(state, sample_name) {
  configuration <- get_pipeline_step(state, "cna_configuration", sample_name)
  if (identical(configuration$status, "skipped")) {
    return(new_pipeline_overview_record("skipped", configuration$reason))
  }

  downstream_steps <- c(
    "cna_compute", "cna_cluster_selection", "cna_signal_correlation",
    "cna_thresholds", "cna_assignment"
  )
  records <- lapply(
    downstream_steps,
    function(step) get_pipeline_step(state, step, sample_name)
  )
  names(records) <- downstream_steps

  # Surface actionable states before deriving progress from completed intermediates.
  for (status in c("failed", "in_progress", "stale", "incomplete")) {
    matching <- which(vapply(
      records,
      function(record) identical(record$status, status),
      logical(1)
    ))
    if (length(matching) > 0L) {
      return(records[[matching[[1]]]])
    }
  }

  assignment <- records$cna_assignment
  if (assignment$status %in% c("completed", "skipped")) {
    return(assignment)
  }

  statuses <- vapply(records, `[[`, character(1), "status")
  if (any(statuses == "completed")) {
    return(new_pipeline_overview_record(
      "incomplete",
      "CNA analysis has completed intermediate stages but is not finalized."
    ))
  }
  if (any(statuses == "skipped")) {
    first_skipped <- which(statuses == "skipped")[[1]]
    return(new_pipeline_overview_record("skipped", records[[first_skipped]]$reason))
  }

  new_pipeline_overview_record("not_started")
}


pipeline_overview_sample_records <- function(state, sample_name) {
  records <- lapply(PIPELINE_OVERVIEW_STAGES, function(definition) {
    if (is.null(definition$step)) {
      pipeline_cna_analysis_record(state, sample_name)
    } else {
      get_pipeline_step(state, definition$step, sample_name)
    }
  })
  names(records) <- names(PIPELINE_OVERVIEW_STAGES)
  records
}


pipeline_overview_next_action <- function(records) {
  action_labels <- c(
    clustering = "Run clustering",
    resolution = "Review and save a resolution",
    differential_expression = "Run differential expression",
    annotation = "Review and save annotations",
    cna_configuration = "Configure or omit CNA",
    cna_analysis = "Continue CNA analysis"
  )

  for (stage in names(records)) {
    record <- records[[stage]]
    if (record$status %in% c("completed", "skipped")) {
      next
    }
    label <- unname(action_labels[[stage]])
    prefix <- switch(
      record$status,
      in_progress = "Wait: ",
      failed = "Retry: ",
      stale = "Review/rerun: ",
      incomplete = "Complete: ",
      ""
    )
    return(list(
      label = paste0(prefix, label),
      stage = stage,
      status = record$status,
      complete = FALSE
    ))
  }

  list(
    label = "Workflow complete (including intentionally skipped steps)",
    stage = NULL,
    status = "completed",
    complete = TRUE
  )
}


summarize_pipeline_overview <- function(state) {
  validate_pipeline_state(state)
  sample_names <- names(state$samples)
  sample_summaries <- lapply(sample_names, function(sample_name) {
    records <- pipeline_overview_sample_records(state, sample_name)
    list(
      name = sample_name,
      records = records,
      next_action = pipeline_overview_next_action(records)
    )
  })
  names(sample_summaries) <- sample_names

  stage_summaries <- lapply(names(PIPELINE_OVERVIEW_STAGES), function(stage) {
    counts <- stats::setNames(integer(length(PIPELINE_STEP_STATUSES)), PIPELINE_STEP_STATUSES)
    if (length(sample_summaries) > 0L) {
      statuses <- vapply(
        sample_summaries,
        function(sample_summary) sample_summary$records[[stage]]$status,
        character(1)
      )
      counts <- counts + table(factor(statuses, levels = PIPELINE_STEP_STATUSES))
    }
    list(
      key = stage,
      label = PIPELINE_OVERVIEW_STAGES[[stage]]$label,
      counts = as.integer(counts) |> stats::setNames(names(counts))
    )
  })
  names(stage_summaries) <- names(PIPELINE_OVERVIEW_STAGES)

  attention <- NULL
  if (length(sample_summaries) > 0L) {
    needs_attention <- which(!vapply(
      sample_summaries,
      function(sample_summary) isTRUE(sample_summary$next_action$complete),
      logical(1)
    ))
    if (length(needs_attention) > 0L) {
      attention <- sample_summaries[[needs_attention[[1]]]]
    }
  }

  list(
    dataset_id = state$dataset_id,
    revision = state$revision,
    updated_at = state$updated_at,
    sample_count = length(sample_names),
    standardization = state$dataset_steps$standardization,
    stages = stage_summaries,
    samples = sample_summaries,
    attention = attention
  )
}
