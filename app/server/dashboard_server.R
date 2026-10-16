# Dashboard navigation and pipeline trigger handlers.

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
    rv$pipeline_state <- persist_pipeline_step_update(
      rv$pipeline_state,
      rv$pipeline_state_path,
      step = step,
      status = status,
      sample = sample_name,
      reason = reason,
      details = details,
      invalidate_downstream = invalidate,
      invalidation_reason = invalidation_reason
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
  observeEvent(input$btn_back_menu_2, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_copy_info, { updateNavbarPage(session, "main_nav", selected = "clipboard_tab") })
  observeEvent(input$btn_back_menu_3, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_go_cna, { updateNavbarPage(session, "main_nav", selected = "cna_tab") })

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
    showModal(modalDialog(
      title = "Confirm Clustering",
      "Are you sure you want to run the clustering pipeline? This process takes a significant amount of time and will lock the application until finished.",
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_run_clustering", "Yes, Run Clustering", class = "btn-danger")
      )
    ))
  })

  observeEvent(input$confirm_run_clustering, {
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
    tryCatch({
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
        }
      )
      record_state_event(
        rv,
        stage = "clustering",
        event_type = "clustering_run",
        outcome = "completed",
        parameters = list(sample_count = length(rv$paths_list$sample_dir_paths))
      )
      showNotification("Clustering complete!", type = "message")
    }, error = function(error) {
      record_state_event(
        rv,
        stage = "clustering",
        event_type = "clustering_run",
        outcome = "failed",
        reason = conditionMessage(error)
      )
      showNotification(
        paste("Clustering failed:", conditionMessage(error)),
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
      showModal(modalDialog(
        title = "Confirm DE Analysis",
        "Are you sure you want to run the Differential Expression analysis? This process is computationally heavy and will lock the application.",
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton("confirm_run_de", "Yes, Run DE Analysis", class = "btn-danger")
        )
      ))
    }
  })

  observeEvent(input$confirm_run_de, {
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
    tryCatch({
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
        }
      )
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "de_run",
        outcome = "completed",
        parameters = list(sample_count = length(rv$paths_list$sample_dir_paths))
      )
      showNotification("Differential Expression Analysis complete!", type = "message")
    }, error = function(error) {
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "de_run",
        outcome = "failed",
        reason = conditionMessage(error)
      )
      showNotification(
        paste("Differential expression failed:", conditionMessage(error)),
        type = "error",
        duration = 10
      )
    })
  })
}
