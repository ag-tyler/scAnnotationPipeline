# Dashboard navigation and pipeline trigger handlers.

format_batch_progress_detail <- function(
  sample_name,
  sample_index,
  sample_total,
  stage,
  detail,
  outcome = NULL
) {
  stage_label <- gsub("_", " ", stage, fixed = TRUE)
  paste0(
    "Sample ", sample_index, " of ", sample_total, ": ", sample_name,
    " - ", stage_label,
    if (!is.null(detail) && nzchar(detail)) paste0(": ", detail) else "",
    if (!is.null(outcome)) paste0(" [", outcome, "]") else ""
  )
}

make_shiny_batch_progress_callback <- function(progress_context) {
  force(progress_context)
  function(
    operation,
    sample_name,
    sample_index,
    sample_total,
    stage,
    detail = NULL,
    outcome = NULL,
    fraction,
    elapsed_seconds = NULL
  ) {
    progress_context$operation <- operation
    progress_context$sample_name <- sample_name
    progress_context$sample_index <- sample_index
    progress_context$sample_total <- sample_total
    progress_context$stage <- stage
    progress_context$detail <- detail
    progress_context$outcome <- outcome
    progress_context$elapsed_seconds <- elapsed_seconds
    setProgress(
      value = fraction,
      detail = format_batch_progress_detail(
        sample_name,
        sample_index,
        sample_total,
        stage,
        detail,
        outcome
      )
    )
  }
}

format_batch_failure <- function(operation_label, progress_context, error) {
  if (!is.null(progress_context$sample_name)) {
    paste0(
      operation_label, " failed for sample ", progress_context$sample_name,
      " during ", gsub("_", " ", progress_context$stage, fixed = TRUE),
      ": ", conditionMessage(error)
    )
  } else {
    paste0(operation_label, " failed: ", conditionMessage(error))
  }
}

register_dashboard_server <- function(input, output, session, state, context) {
  rv <- state

  persist_sample_step <- function(step, sample_name, status, reason = NULL, details = NULL) {
    current <- get_pipeline_step(rv$pipeline_state, step, sample_name)
    invalidate <- identical(status, "in_progress") &&
      current$status %in% c("completed", "skipped")
    invalidation_reason <- if (invalidate) {
      paste0("The ", step, " step is being rerun for this sample.")
    } else {
      NULL
    }
    downstream_stale_reason <- if (identical(status, "completed")) {
      switch(
        step,
        clustering = "Clustering was rerun; review and save a resolution again.",
        differential_expression = "Differential expression was rerun; review and save annotations again.",
        NULL
      )
    } else if (identical(status, "failed")) {
      paste0(
        tools::toTitleCase(gsub("_", " ", step)),
        " rerun failed",
        if (!is.null(reason)) paste0(": ", reason, ".") else ".",
        " Resolve the error and rerun this step."
      )
    } else {
      NULL
    }
    rv$pipeline_state <- persist_pipeline_step_update(
      rv$pipeline_state,
      rv$pipeline_state_path,
      step = step,
      status = status,
      sample = sample_name,
      reason = reason,
      details = details,
      invalidate_downstream = invalidate,
      invalidation_reason = invalidation_reason,
      downstream_stale_reason = downstream_stale_reason
    )
    record_state_event(
      rv,
      stage = "state",
      event_type = paste0(step, "_state"),
      outcome = status,
      sample = sample_name,
      parameters = list(revision = rv$pipeline_state$revision),
      reason = reason
    )
    invisible(rv$pipeline_state)
  }

  observeEvent(input$btn_go_res, { updateNavbarPage(session, "main_nav", selected = "res_tab") })
  observeEvent(input$btn_go_anno, { updateNavbarPage(session, "main_nav", selected = "anno_tab") })
  observeEvent(input$btn_back_menu_1, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_copy_info, { updateNavbarPage(session, "main_nav", selected = "clipboard_tab") })
  observeEvent(input$btn_back_menu_3, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_go_cna, { updateNavbarPage(session, "main_nav", selected = "cna_tab") })
  observeEvent(input$btn_after_clustering_res, {
    if (!claim_app_confirmation(rv, "after_clustering_navigation")) return()
    removeModal()
    record_state_event(
      rv,
      stage = "navigation",
      event_type = "completion_navigation",
      outcome = "selected",
      parameters = list(source = "clustering_complete", target = "res_tab")
    )
    updateNavbarPage(session, "main_nav", selected = "res_tab")
  })
  observeEvent(input$btn_after_de_anno, {
    if (!claim_app_confirmation(rv, "after_de_navigation")) return()
    removeModal()
    record_state_event(
      rv,
      stage = "navigation",
      event_type = "completion_navigation",
      outcome = "selected",
      parameters = list(source = "de_complete", target = "anno_tab")
    )
    updateNavbarPage(session, "main_nav", selected = "anno_tab")
  })

  observeEvent(input$btn_select_all, {
    runjs("document.getElementById('prompt_text_area').select();")
  })

  observeEvent(input$btn_run_clustering, {
    req(rv$paths_list, rv$pipeline_state)
    standardization <- get_pipeline_step(rv$pipeline_state, "standardization")
    if (!identical(standardization$status, "completed")) {
      showNotification(
        paste0(
          "Cannot run clustering: standardization is ", standardization$status,
          if (!is.null(standardization$reason)) paste0(" (", standardization$reason, ")") else "."
        ),
        type = "error",
        duration = 10
      )
      return()
    }
    arm_app_confirmation(rv, "bulk_clustering")
    showModal(modalDialog(
      title = "Confirm Clustering",
      "Are you sure you want to run the clustering pipeline? This process takes a significant amount of time and will lock the application until finished.",
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton(
          "confirm_run_clustering",
          "Yes, Run Clustering",
          class = "btn-danger",
          onclick = "this.disabled = true;"
        )
      )
    ))
  })

  observeEvent(input$confirm_run_clustering, {
    if (!claim_app_confirmation(rv, "bulk_clustering")) return()
    if (!begin_app_action(rv, "bulk_clustering")) return()
    shinyjs::disable("btn_run_clustering")
    on.exit({
      finish_app_action(rv, "bulk_clustering")
      shinyjs::enable("btn_run_clustering")
    }, add = TRUE)
    removeModal()
    id <- showNotification("Running clustering pipeline. This may take a while. Check R console...",
                           duration = NULL, type = "warning")
    on.exit(removeNotification(id), add = TRUE)
    record_state_event(
      rv,
      stage = "clustering",
      event_type = "clustering_run",
      outcome = "started",
      parameters = list(
        sample_count = length(rv$paths_list$sample_dir_paths),
        resolutions = rv$dataset_config$params$resolutions
      )
    )
    progress_context <- new.env(parent = emptyenv())
    tryCatch({
      withProgress(message = "Bulk clustering", value = 0, {
        cluster_all_samples(
          rv$paths_list,
          rv$dataset_config,
          rv$results_dir_path,
          rv$dataset_dir_path,
          state_callback = function(sample_name, status, reason = NULL, details = NULL) {
            persist_sample_step(
              "clustering",
              sample_name,
              status,
              reason,
              details
            )
          },
          progress_callback = make_shiny_batch_progress_callback(progress_context)
        )
      })
      record_state_event(
        rv,
        stage = "clustering",
        event_type = "clustering_run",
        outcome = "completed",
        parameters = list(sample_count = length(rv$paths_list$sample_dir_paths))
      )
      arm_app_confirmation(rv, "after_clustering_navigation")
      showModal(modalDialog(
        title = "Clustering complete",
        "All samples have been clustered. Review the generated UMAP plots and save one resolution per sample before running differential expression.",
        easyClose = TRUE,
        footer = tagList(
          modalButton("Stay on Start Menu"),
          actionButton(
            "btn_after_clustering_res",
            "Go to Resolution Selection",
            class = "btn-primary",
            onclick = "this.disabled = true;"
          )
        )
      ))
    }, error = function(error) {
      failure_message <- format_batch_failure("Clustering", progress_context, error)
      record_state_event(
        rv,
        stage = "clustering",
        event_type = "clustering_run",
        outcome = "failed",
        reason = failure_message,
        parameters = list(
          sample = progress_context$sample_name,
          failed_stage = progress_context$stage
        )
      )
      showNotification(
        failure_message,
        type = "error",
        duration = 10
      )
    })
  })

  observeEvent(input$btn_run_de, {
    req(rv$paths_list, rv$pipeline_state)
    expected_samples <- basename(rv$paths_list$sample_dir_paths)

    unpicked_samples <- expected_samples[sapply(expected_samples, function(s) {
      res <- rv$live_selected_config$resolutions[[s]]
      is.null(res) || res == 0 || res == 0.0
    })]

    state_blocked_samples <- expected_samples[vapply(expected_samples, function(s) {
      !pipeline_step_readiness(
        rv$pipeline_state,
        "differential_expression",
        s
      )$ready
    }, logical(1))]
    blocked_samples <- unique(c(unpicked_samples, state_blocked_samples))

    if (length(blocked_samples) > 0) {
      msg <- paste(
        "Cannot run DE. Resolution is not complete for:",
        paste(blocked_samples, collapse = ", ")
      )
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "de_run",
        outcome = "incomplete",
        reason = msg,
        parameters = list(samples_missing_resolution = blocked_samples)
      )
      showNotification(msg, type = "error", duration = 10)
    } else {
      arm_app_confirmation(rv, "bulk_de")
      showModal(modalDialog(
        title = "Confirm DE Analysis",
        "Are you sure you want to run the Differential Expression analysis? This process is computationally heavy and will lock the application.",
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton(
            "confirm_run_de",
            "Yes, Run DE Analysis",
            class = "btn-danger",
            onclick = "this.disabled = true;"
          )
        )
      ))
    }
  })

  observeEvent(input$confirm_run_de, {
    if (!claim_app_confirmation(rv, "bulk_de")) return()
    if (!begin_app_action(rv, "bulk_de")) return()
    shinyjs::disable("btn_run_de")
    on.exit({
      finish_app_action(rv, "bulk_de")
      shinyjs::enable("btn_run_de")
    }, add = TRUE)
    removeModal()
    id <- showNotification("Running DE analysis. Check R console...", duration = NULL, type = "warning")
    on.exit(removeNotification(id), add = TRUE)
    record_state_event(
      rv,
      stage = "differential_expression",
      event_type = "de_run",
      outcome = "started",
      parameters = list(sample_count = length(rv$paths_list$sample_dir_paths))
    )
    progress_context <- new.env(parent = emptyenv())
    tryCatch({
      withProgress(message = "Bulk differential expression", value = 0, {
        de_analysis(
          rv$paths_list,
          rv$dataset_config,
          rv$live_selected_config,
          rv$complete_markers,
          rv$results_dir_path,
          rv$dataset_dir_path,
          state_callback = function(sample_name, status, reason = NULL, details = NULL) {
            persist_sample_step(
              "differential_expression",
              sample_name,
              status,
              reason,
              details
            )
          },
          progress_callback = make_shiny_batch_progress_callback(progress_context)
        )
      })
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "de_run",
        outcome = "completed",
        parameters = list(sample_count = length(rv$paths_list$sample_dir_paths))
      )
      arm_app_confirmation(rv, "after_de_navigation")
      showModal(modalDialog(
        title = "Differential expression complete",
        "Marker results are ready for all samples. Continue to Manual Annotation to review clusters and assign cell types.",
        easyClose = TRUE,
        footer = tagList(
          modalButton("Stay on Start Menu"),
          actionButton(
            "btn_after_de_anno",
            "Go to Manual Annotation",
            class = "btn-primary",
            onclick = "this.disabled = true;"
          )
        )
      ))
    }, error = function(error) {
      failure_message <- format_batch_failure(
        "Differential expression",
        progress_context,
        error
      )
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "de_run",
        outcome = "failed",
        reason = failure_message,
        parameters = list(
          sample = progress_context$sample_name,
          failed_stage = progress_context$stage
        )
      )
      showNotification(
        failure_message,
        type = "error",
        duration = 10
      )
    })
  })
}
