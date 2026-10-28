# Shared targeted differential-expression handlers.

register_single_sample_de_handlers <- function(
  input,
  session,
  state,
  sample_input_id,
  trigger_button_id,
  confirm_button_id,
  action_key,
  source,
  protect_unsaved_annotation = FALSE
) {
  rv <- state

  selected_sample <- function() {
    req(rv$paths_list, input[[sample_input_id]])
    index <- suppressWarnings(as.integer(input[[sample_input_id]]))
    sample_names <- basename(rv$paths_list$sample_dir_paths)
    if (
      length(index) != 1L || is.na(index) ||
        index < 1L || index > length(sample_names)
    ) {
      return(NULL)
    }
    list(index = index, name = sample_names[[index]])
  }

  persist_de_state <- function(sample_name, status, reason = NULL, details = NULL) {
    state_to_update <- rv$pipeline_state
    if (identical(status, "in_progress")) {
      for (downstream_step in PIPELINE_STALE_DEPENDENCIES$differential_expression) {
        downstream_record <- get_pipeline_step(
          state_to_update,
          downstream_step,
          sample_name
        )
        if (identical(downstream_record$status, "stale")) {
          state_to_update <- transition_pipeline_step(
            state_to_update,
            step = downstream_step,
            status = "stale",
            sample = sample_name,
            reason = "Differential expression is being rerun for this sample.",
            details = list(stale_after = "differential_expression")
          )
        }
      }
    }
    current <- get_pipeline_step(
      state_to_update,
      "differential_expression",
      sample_name
    )
    invalidate <- identical(status, "in_progress") &&
      current$status %in% c("completed", "skipped")
    rv$pipeline_state <- persist_pipeline_step_update(
      state_to_update,
      rv$pipeline_state_path,
      step = "differential_expression",
      status = status,
      sample = sample_name,
      reason = reason,
      details = details,
      invalidate_downstream = invalidate,
      invalidation_reason = if (invalidate) {
        "Differential expression is being rerun for this sample."
      } else NULL,
      downstream_stale_reason = if (identical(status, "completed")) {
        "Differential expression was rerun; review and save annotations again."
      } else if (identical(status, "failed")) {
        paste0(
          "Differential expression rerun failed",
          if (!is.null(reason)) paste0(": ", reason, ".") else ".",
          " Resolve the error and rerun this step."
        )
      } else NULL
    )
    invisible(rv$pipeline_state)
  }

  observeEvent(input[[trigger_button_id]], {
    sample <- selected_sample()
    if (is.null(sample)) {
      showNotification("Select a valid sample before rerunning DE.", type = "error")
      return()
    }
    if (isTRUE(protect_unsaved_annotation) && isTRUE(rv$annotation_dirty)) {
      showNotification(
        "Save or discard the current annotation edits before rerunning DE.",
        type = "error",
        duration = 10
      )
      return()
    }

    current_resolution <- rv$live_selected_config$resolutions[[sample$name]]
    if (
      is.null(current_resolution) || length(current_resolution) != 1L ||
        is.na(current_resolution) || current_resolution == 0
    ) {
      reason <- "No clustering resolution has been saved for this sample."
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "single_sample_de",
        outcome = "incomplete",
        sample = sample$name,
        parameters = list(source = source),
        reason = reason
      )
      showNotification(
        paste("Cannot run DE! Please save a resolution for", sample$name, "first."),
        type = "error"
      )
      return()
    }

    readiness <- pipeline_step_readiness(
      rv$pipeline_state,
      "differential_expression",
      sample$name
    )
    if (!readiness$ready) {
      reason <- paste(readiness$reasons, collapse = "; ")
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "single_sample_de",
        outcome = "incomplete",
        sample = sample$name,
        parameters = list(source = source),
        reason = reason
      )
      showNotification(
        paste("Cannot run DE:", reason),
        type = "error",
        duration = 10
      )
      return()
    }

    arm_app_confirmation(rv, action_key)
    showModal(modalDialog(
      title = "Confirm Single Sample DE",
      paste0(
        "Are you sure you want to rerun the Differential Expression analysis for '",
        sample$name,
        "'? Existing annotations for this sample will require review, and the application will be locked until DE finishes."
      ),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton(
          confirm_button_id,
          "Yes, Rerun DE",
          class = "btn-danger",
          onclick = "this.disabled = true;"
        )
      )
    ))
  })

  observeEvent(input[[confirm_button_id]], {
    if (!claim_app_confirmation(rv, action_key)) return()
    if (!begin_app_action(rv, action_key)) return()
    shinyjs::disable(trigger_button_id)
    on.exit({
      finish_app_action(rv, action_key)
      shinyjs::enable(trigger_button_id)
    }, add = TRUE)
    removeModal()
    req(rv$paths_list, rv$dataset_config, rv$complete_markers)

    sample <- selected_sample()
    if (is.null(sample)) {
      showNotification("The selected sample is no longer available.", type = "error")
      return()
    }
    resolution <- rv$live_selected_config$resolutions[[sample$name]]
    id <- showNotification(
      paste("Running DE analysis for", sample$name, "- Check R console..."),
      duration = NULL,
      type = "warning"
    )

    record_state_event(
      rv,
      stage = "differential_expression",
      event_type = "single_sample_de",
      outcome = "started",
      sample = sample$name,
      parameters = list(resolution = resolution, source = source)
    )

    state_started <- tryCatch(
      persist_de_state(
        sample$name,
        "in_progress",
        details = list(resolution = resolution)
      ),
      error = identity
    )
    if (inherits(state_started, "error")) {
      record_state_event(
        rv,
        stage = "state",
        event_type = "differential_expression_state",
        outcome = "failed",
        sample = sample$name,
        reason = conditionMessage(state_started)
      )
      showNotification(
        paste("DE could not start because workflow state failed:", conditionMessage(state_started)),
        type = "error",
        duration = 10
      )
      removeNotification(id)
      return()
    }

    tryCatch({
      single_de_analysis(
        sample_idx = sample$index,
        paths_list = rv$paths_list,
        dataset_config = rv$dataset_config,
        selected_config = rv$live_selected_config,
        complete_markers = rv$complete_markers,
        results_dir_path = rv$results_dir_path,
        dataset_dir_path = rv$dataset_dir_path
      )
      persist_de_state(
        sample$name,
        "completed",
        details = list(resolution = resolution)
      )
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "single_sample_de",
        outcome = "completed",
        sample = sample$name,
        parameters = list(source = source)
      )
      showNotification(
        paste("Differential Expression Analysis complete for", sample$name, "!"),
        type = "message"
      )
    }, error = function(error) {
      try(
        persist_de_state(sample$name, "failed", reason = conditionMessage(error)),
        silent = TRUE
      )
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "single_sample_de",
        outcome = "failed",
        sample = sample$name,
        parameters = list(source = source),
        reason = conditionMessage(error)
      )
      showNotification(
        paste("Error running DE:", conditionMessage(error)),
        type = "error",
        duration = 10
      )
    }, finally = {
      removeNotification(id)
    })
  })
}
