# Dataset storage/archive lifecycle handlers.

register_storage_server <- function(input, output, session, state, context) {
  rv <- state
  reviewed_optional_exports <- reactiveVal(character())
  storage_action_ids <- c(
    "btn_run_clustering", "btn_run_single_clustering", "btn_go_res",
    "btn_run_de", "btn_go_anno", "btn_go_cna"
  )

  storage_read_only <- reactive({
    req(rv$storage_state)
    dataset_storage_cache_is_retired(rv$storage_state)
  })

  cleanup_readiness <- reactive({
    input$main_nav # Refresh optional-export availability when returning to the menu.
    req(
      rv$storage_state,
      rv$pipeline_state,
      rv$paths_list,
      rv$live_selected_config,
      rv$selected_config_path,
      rv$results_dir_path,
      rv$dataset_dir_path
    )
    if (storage_read_only()) return(NULL)
    dataset_cleanup_readiness(
      rv$pipeline_state,
      rv$paths_list,
      rv$live_selected_config,
      rv$selected_config_path,
      rv$results_dir_path,
      rv$dataset_dir_path
    )
  })

  archive_audit <- reactive({
    req(rv$storage_state, rv$dataset_dir_path)
    if (!storage_read_only()) return(NULL)
    dataset_archive_output_audit(rv$storage_state, rv$dataset_dir_path)
  })

  output$dataset_storage_status <- renderUI({
    req(rv$storage_state)
    readiness <- if (is.null(rv$dataset_config) || is.null(context$config)) {
      list(ready = FALSE, reasons = "Load the complete dataset configuration first.")
    } else {
      snapshot_args <- snapshot_server_arguments(rv, context)
      snapshot_args <- snapshot_args[names(snapshot_args) %in% names(formals(dataset_snapshot_readiness))]
      do.call(dataset_snapshot_readiness, snapshot_args)
    }
    dataset_storage_card_ui(rv$storage_state, cleanup_readiness(), archive_audit(), readiness)
  })

  observe({
    req(rv$storage_state)
    read_only <- storage_read_only()
    for (id in storage_action_ids) {
      if (read_only) shinyjs::disable(id) else shinyjs::enable(id)
    }
    if (read_only) {
      nav_hide("main_nav", target = "res_tab")
      nav_hide("main_nav", target = "anno_tab")
      nav_hide("main_nav", target = "cna_tab")
    }
  })

  observeEvent(input$btn_review_dataset_cleanup, {
    req(rv$storage_state, rv$pipeline_state)
    readiness <- dataset_cleanup_readiness(
      rv$pipeline_state, rv$paths_list, rv$live_selected_config,
      rv$selected_config_path, rv$results_dir_path, rv$dataset_dir_path
    )
    if (is.null(readiness) || !isTRUE(readiness$ready)) {
      showNotification(
        paste("Dataset cleanup is not ready:", paste(readiness$reasons, collapse = "; ")),
        type = "warning",
        duration = 12
      )
      return()
    }
    if (length(isolate(rv$active_actions)) > 0L) {
      showNotification("Wait for the current application action to finish before cleanup.", type = "warning")
      return()
    }
    dataset_id <- rv$pipeline_state$dataset_id
    reviewed_optional_exports(readiness$optional_export_samples)
    arm_app_confirmation(rv, "dataset_cleanup")
    showModal(modalDialog(
      title = "Archive Dataset and Remove Reconstructible Caches",
      div(
        class = "alert alert-warning",
        icon("triangle-exclamation"),
        " Annotation and CNA editing will be disabled until the dataset is explicitly reopened and its caches are recomputed."
      ),
      dataset_cleanup_export_warning_ui(readiness),
      tags$dl(
        class = "row",
        tags$dt(class = "col-sm-5", "Cache files"),
        tags$dd(class = "col-sm-7", readiness$cache$file_count),
        tags$dt(class = "col-sm-5", "Estimated space recovered"),
        tags$dd(class = "col-sm-7", format_storage_bytes(readiness$cache$size_bytes)),
        tags$dt(class = "col-sm-5", "Removed"),
        tags$dd(class = "col-sm-7", "Only the validated dataset cache directory and its cache backups"),
        tags$dt(class = "col-sm-5", "Retained"),
        tags$dd(class = "col-sm-7", "Processed data, final Cells.csv files, results, configuration, state, logs, and CNA values exports")
      ),
      textInput(
        "dataset_cleanup_confirmation",
        paste0("Type ", dataset_id, " to confirm:"),
        value = ""
      ),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        shinyjs::disabled(actionButton(
          "btn_confirm_dataset_cleanup",
          "Archive and Remove Caches",
          class = "btn-danger"
        ))
      )
    ))
  })

  observe({
    req(input$dataset_cleanup_confirmation, rv$pipeline_state)
    shinyjs::toggleState(
      "btn_confirm_dataset_cleanup",
      condition = identical(input$dataset_cleanup_confirmation, rv$pipeline_state$dataset_id)
    )
  })

  observeEvent(input$btn_confirm_dataset_cleanup, {
    if (!claim_app_confirmation(rv, "dataset_cleanup")) return()
    req(rv$pipeline_state, rv$storage_state)
    if (!identical(input$dataset_cleanup_confirmation, rv$pipeline_state$dataset_id)) {
      showNotification("The dataset identifier did not match. Cleanup was not started.", type = "error")
      return()
    }
    if (length(isolate(rv$active_actions)) > 0L || !begin_app_action(rv, "dataset_cleanup")) {
      showNotification("Another application action is already running.", type = "warning")
      return()
    }
    on.exit(finish_app_action(rv, "dataset_cleanup"), add = TRUE)
    removeModal()
    reviewed_readiness <- isolate(cleanup_readiness())
    record_state_event(
      rv,
      stage = "storage",
      event_type = "dataset_cleanup",
      outcome = "started",
      parameters = list(
        cache_file_count = reviewed_readiness$cache$file_count,
        estimated_recovered_bytes = reviewed_readiness$cache$size_bytes
      )
    )
    result <- tryCatch(
      withProgress(message = "Archiving dataset caches", value = 0.1, {
        readiness <- dataset_cleanup_readiness(
          rv$pipeline_state,
          rv$paths_list,
          rv$live_selected_config,
          rv$selected_config_path,
          rv$results_dir_path,
          rv$dataset_dir_path
        )
        if (!isTRUE(readiness$ready)) {
          stop("Cleanup requirements changed after review: ", paste(readiness$reasons, collapse = "; "))
        }
        if (length(setdiff(readiness$optional_export_samples, reviewed_optional_exports())) > 0L) {
          stop("CNA export availability changed after review. Review Dataset Cleanup again to see the updated recomputation warning.")
        }
        setProgress(0.25, detail = "Validating final outputs and cache inventory")
        archived <- archive_dataset_cache(
          rv$dataset_dir_path,
          rv$pipeline_state,
          rv$storage_state,
          readiness
        )
        setProgress(1, detail = "Storage lifecycle saved")
        archived
      }),
      error = identity
    )
    if (inherits(result, "error")) {
      rv$storage_state <- tryCatch(
        load_dataset_storage_state(rv$dataset_dir_path, rv$pipeline_state$dataset_id),
        error = function(error) rv$storage_state
      )
      record_state_event(
        rv,
        stage = "storage",
        event_type = "dataset_cleanup",
        outcome = "failed",
        reason = conditionMessage(result)
      )
      showNotification(paste("Dataset cleanup failed:", conditionMessage(result)), type = "error", duration = 12)
      return()
    }
    rv$storage_state <- result
    outcome <- if (identical(result$status, "archived")) "completed" else "deletion_pending"
    record_state_event(
      rv,
      stage = "storage",
      event_type = "dataset_cleanup",
      outcome = outcome,
      parameters = list(
        cache_file_count = result$details$cleanup$cache_file_count,
        recovered_bytes = if (is.null(result$details$recovered_bytes)) 0 else result$details$recovered_bytes,
        cleanup_id = result$details$cleanup$cleanup_id
      ),
      reason = result$reason
    )
    showNotification(
      if (identical(result$status, "archived")) {
        paste("Dataset archived. Recovered", format_storage_bytes(result$details$recovered_bytes), "of cache storage.")
      } else {
        result$reason
      },
      type = if (identical(result$status, "archived")) "message" else "warning",
      duration = 12
    )
  })

  observeEvent(input$btn_retry_dataset_cleanup, {
    req(rv$storage_state)
    if (!begin_app_action(rv, "dataset_cleanup_retry")) return()
    on.exit(finish_app_action(rv, "dataset_cleanup_retry"), add = TRUE)
    result <- tryCatch(
      retry_dataset_cache_deletion(rv$dataset_dir_path, rv$storage_state),
      error = identity
    )
    if (inherits(result, "error")) {
      showNotification(conditionMessage(result), type = "error", duration = 10)
      return()
    }
    rv$storage_state <- result
    record_state_event(
      rv,
      stage = "storage",
      event_type = "dataset_cleanup_retry",
      outcome = "completed",
      parameters = list(
        recovered_bytes = result$details$recovered_bytes,
        cleanup_id = result$details$cleanup$cleanup_id
      )
    )
    showNotification("Retired cache deletion completed.", type = "message")
  })

  observeEvent(input$btn_reopen_dataset, {
    req(rv$storage_state, rv$pipeline_state)
    dataset_id <- rv$pipeline_state$dataset_id
    arm_app_confirmation(rv, "dataset_reopen")
    showModal(modalDialog(
      title = "Reopen Archived Dataset for Editing?",
      div(
        class = "alert alert-warning",
        "Deleted caches cannot be restored. Clustering and all dependent stages will be marked stale and must be recomputed. Existing result files remain for reference."
      ),
      textInput(
        "dataset_reopen_confirmation",
        paste0("Type ", dataset_id, " to confirm:"),
        value = ""
      ),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        shinyjs::disabled(actionButton(
          "btn_confirm_dataset_reopen",
          "Reopen and Require Recalculation",
          class = "btn-warning"
        ))
      )
    ))
  })

  observe({
    req(input$dataset_reopen_confirmation, rv$pipeline_state)
    shinyjs::toggleState(
      "btn_confirm_dataset_reopen",
      condition = identical(input$dataset_reopen_confirmation, rv$pipeline_state$dataset_id)
    )
  })

  observeEvent(input$btn_confirm_dataset_reopen, {
    if (!claim_app_confirmation(rv, "dataset_reopen")) return()
    req(rv$storage_state, rv$pipeline_state)
    if (!identical(input$dataset_reopen_confirmation, rv$pipeline_state$dataset_id)) {
      showNotification("The dataset identifier did not match. Reopen was cancelled.", type = "error")
      return()
    }
    if (!begin_app_action(rv, "dataset_reopen")) return()
    on.exit(finish_app_action(rv, "dataset_reopen"), add = TRUE)
    removeModal()
    result <- tryCatch(
      reopen_archived_dataset(
        rv$dataset_dir_path,
        rv$pipeline_state,
        rv$pipeline_state_path,
        rv$storage_state
      ),
      error = identity
    )
    if (inherits(result, "error")) {
      record_state_event(
        rv,
        stage = "storage",
        event_type = "dataset_reopen",
        outcome = "failed",
        reason = conditionMessage(result)
      )
      showNotification(paste("Dataset reopen failed:", conditionMessage(result)), type = "error", duration = 12)
      return()
    }
    rv$pipeline_state <- result$pipeline_state
    rv$storage_state <- result$storage_state
    nav_show("main_nav", target = "res_tab")
    nav_show("main_nav", target = "anno_tab")
    nav_show("main_nav", target = "cna_tab")
    record_state_event(
      rv,
      stage = "storage",
      event_type = "dataset_reopen",
      outcome = "completed",
      parameters = list(
        storage_revision = result$storage_state$revision,
        cleanup_id = result$storage_state$details$cleanup$cleanup_id
      )
    )
    showNotification("Dataset reopened. Rerun clustering to rebuild its caches.", type = "warning", duration = 10)
  })
}
