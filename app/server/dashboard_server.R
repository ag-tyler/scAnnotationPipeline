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
  single_clustering_completed_index <- reactiveVal(NULL)
  de_completion_context <- reactiveVal(NULL)
  clustering_dialog_serial <- reactiveVal(0L)
  clustering_selection_context <- reactiveVal(NULL)
  clustering_completion_context <- reactiveVal(NULL)

  clustering_block_reason <- function() {
    if (is.null(rv$pipeline_state) ||
        !identical(get_pipeline_step(rv$pipeline_state, "standardization")$status, "completed")) {
      return("Cannot run clustering: standardization must be completed first.")
    }
    if (dataset_storage_cache_is_retired(rv$storage_state)) {
      return("This dataset is archived/read-only. Reopen it for editing before clustering.")
    }
    if (length(rv$active_actions)) return("Wait for the current application action to finish before clustering.")
    if (isTRUE(rv$annotation_dirty)) return("Save or discard the current annotation edits before clustering.")
    NULL
  }

  clustering_context_matches <- function(request) {
    !is.null(request) && identical(request$dataset_dir, rv$dataset_dir_path) &&
      identical(request$dataset_id, rv$pipeline_state$dataset_id) &&
      identical(request$samples, basename(rv$paths_list$sample_dir_paths)) &&
      identical(request$resolutions, rv$dataset_config$params$resolutions)
  }

  resolve_clustering_selection <- function() {
    request <- clustering_selection_context()
    if (!clustering_context_matches(request)) {
      stop("The dataset, sample list or resolutions changed. Reopen the clustering dialog.", call. = FALSE)
    }
    reason <- clustering_block_reason()
    if (!is.null(reason)) stop(reason, call. = FALSE)
    indices <- validate_clustering_selection(rv$pipeline_state, input[[request$input_id]], request$samples)
    list(indices = indices, samples = request$samples[indices], context = request)
  }

  clustering_selection_review <- reactive({
    req(clustering_selection_context())
    tryCatch(resolve_clustering_selection(), error = identity)
  })
  output$clustering_selection_summary <- renderUI({
    selection <- clustering_selection_review()
    if (inherits(selection, "error")) {
      return(tags$div(class = "alert alert-warning", conditionMessage(selection)))
    }
    tags$div(
      tags$strong(paste(length(selection$samples), "of", length(selection$context$samples),
        if (length(selection$context$samples) == 1L) "sample selected" else "samples selected")),
      tags$p(style = "max-height: 15vh; overflow-y: auto; overflow-wrap: anywhere;",
             paste(selection$samples, collapse = ", ")),
      tags$p("Only these samples will run. Their saved resolution, DE, annotation and CNA decisions require review again; unselected samples are unchanged.")
    )
  })
  output$clustering_run_control <- renderUI({
    selection <- clustering_selection_review()
    valid <- !inherits(selection, "error")
    count <- if (valid) length(selection$samples) else 0L
    button <- actionButton(
      "confirm_run_clustering", paste("Run clustering for", count, "selected", if (count == 1L) "sample" else "samples"),
      class = "btn-danger", onclick = "this.disabled = true;"
    )
    if (valid) button else shinyjs::disabled(button)
  })
  for (preset in c("all", "stale", "incomplete", "clear")) local({
    current_preset <- preset
    observeEvent(input[[paste0("clustering_select_", current_preset)]], {
      request <- clustering_selection_context()
      if (!clustering_context_matches(request)) return()
      updateCheckboxGroupInput(
        session, request$input_id,
        selected = clustering_selection_preset(rv$pipeline_state, request$samples, current_preset)
      )
    })
  })

  de_review_message <- function(review) {
    paste0(
      length(review$processed_samples),
      if (length(review$processed_samples) == 1L) " sample processed; " else " samples processed; ",
      length(review$pending_samples), " need annotation review. ",
      if (!is.null(review$target_sample)) {
        paste0("Continue at ", review$target_sample, ", the first processed sample ready for review. ")
      } else if (length(review$pending_samples)) {
        "None of those samples are ready yet; check the pipeline overview for unmet prerequisites. Your current selection will be kept. "
      } else {
        "No processed samples currently need annotation review. Your current selection will be kept. "
      },
      "The Start Menu pipeline overview lists the status of every sample."
    )
  }

  block_de_for_unsaved_annotation <- function() {
    if (!isTRUE(rv$annotation_dirty)) return(FALSE)
    showNotification(
      "Save or discard the current annotation edits before running bulk DE. No analysis was started and your edits are unchanged.",
      type = "warning", duration = 15
    )
    TRUE
  }

  pipeline_overview_summary <- reactive({
    req(rv$pipeline_state)
    summarize_pipeline_overview(rv$pipeline_state)
  })

  output$pipeline_status_overview <- renderUI({
    pipeline_status_overview_ui(pipeline_overview_summary())
  })

  persist_sample_step <- function(step, sample_name, status, reason = NULL, details = NULL) {
    current <- get_pipeline_step(rv$pipeline_state, step, sample_name)
    invalidate <- identical(status, "in_progress") &&
      (identical(step, "clustering") || current$status %in% c("completed", "skipped"))
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
    completed <- clustering_completion_context()
    if (is.null(completed) || !identical(completed$dataset_dir, rv$dataset_dir_path) ||
        !identical(completed$dataset_id, rv$pipeline_state$dataset_id)) {
      showNotification("This clustering completion no longer matches the loaded dataset. Use the pipeline overview to choose a sample.", type = "warning")
      return()
    }
    if (isTRUE(rv$annotation_dirty)) {
      showNotification("Save or discard annotation edits before reviewing another sample. Your selection and edits are unchanged.", type = "warning")
      return()
    }
    if (!length(completed$samples)) return()
    index <- match(completed$samples[[1]], basename(rv$paths_list$sample_dir_paths))
    if (is.na(index)) return()
    updateSelectInput(session, "res_sample_idx", selected = index)
    record_state_event(
      rv,
      stage = "navigation",
      event_type = "completion_navigation",
      outcome = "selected",
      parameters = list(source = "clustering_complete", target = "res_tab", sample_index = index, samples = completed$samples)
    )
    updateNavbarPage(session, "main_nav", selected = "res_tab")
  })
  observeEvent(input$btn_after_single_clustering_res, {
    if (!claim_app_confirmation(rv, "after_single_clustering_navigation")) return()
    selected_index <- single_clustering_completed_index()
    removeModal()
    if (!is.null(selected_index)) {
      updateSelectInput(session, "res_sample_idx", selected = selected_index)
    }
    record_state_event(
      rv,
      stage = "navigation",
      event_type = "completion_navigation",
      outcome = "selected",
      parameters = list(
        source = "single_clustering_complete",
        target = "res_tab",
        sample_index = selected_index
      )
    )
    updateNavbarPage(session, "main_nav", selected = "res_tab")
  })
  observeEvent(input$btn_after_de_anno, {
    if (!claim_app_confirmation(rv, "after_de_navigation")) return()
    removeModal()
    completed <- de_completion_context()
    if (is.null(completed) || !identical(completed$dataset_dir, rv$dataset_dir_path) ||
        !identical(completed$dataset_id, rv$pipeline_state$dataset_id)) {
      showNotification(
        "This DE completion no longer matches the loaded dataset. Use its pipeline overview to choose a sample for review.",
        type = "warning", duration = 15
      )
      return()
    }
    # Re-evaluate at click time: a prior target may already have been reviewed
    # or may have become blocked since the completion dialog was shown.
    review <- summarize_de_annotation_review(
      rv$pipeline_state, completed$processed_samples,
      basename(rv$paths_list$sample_dir_paths)
    )
    if (isTRUE(rv$annotation_dirty)) {
      showNotification(
        paste("Save or discard the current annotation edits before switching samples. Your selection and edits are unchanged.", de_review_message(review)),
        type = "warning", duration = 15
      )
      return()
    }
    if (!is.null(review$target_index)) {
      updateSelectInput(session, "sample_idx", selected = review$target_index)
    } else {
      showNotification(
        de_review_message(review),
        type = if (length(review$pending_samples)) "warning" else "message",
        duration = 15
      )
    }
    record_state_event(
      rv,
      stage = "navigation",
      event_type = "completion_navigation",
      outcome = "selected",
      parameters = list(
        source = "de_complete", target = "anno_tab",
        sample_index = review$target_index, sample = review$target_sample,
        processed_samples = review$processed_samples,
        pending_annotation_count = length(review$pending_samples)
      )
    )
    updateNavbarPage(session, "main_nav", selected = "anno_tab")
  })

  observeEvent(input$btn_select_all, {
    runjs("document.getElementById('prompt_text_area').select();")
  })

  observeEvent(input$btn_run_clustering, {
    req(rv$paths_list, rv$pipeline_state)
    reason <- clustering_block_reason()
    if (!is.null(reason)) {
      showNotification(reason, type = "warning", duration = 10)
      return()
    }
    samples <- basename(rv$paths_list$sample_dir_paths)
    serial <- clustering_dialog_serial() + 1L
    clustering_dialog_serial(serial)
    request <- list(
      dataset_dir = rv$dataset_dir_path, dataset_id = rv$pipeline_state$dataset_id,
      samples = samples, resolutions = rv$dataset_config$params$resolutions,
      input_id = paste0("clustering_samples_", serial)
    )
    clustering_selection_context(request)
    statuses <- vapply(samples, function(sample) get_pipeline_step(rv$pipeline_state, "clustering", sample)$status, character(1))
    arm_app_confirmation(rv, "bulk_clustering")
    showModal(modalDialog(
      title = "Select Samples for Clustering",
      p("All samples are checked initially. Narrow the list if only some samples need clustering; downstream stale states alone do not require reclustering."),
      tags$div(class = "d-flex flex-wrap gap-2 mb-3",
        actionButton("clustering_select_all", "Select all"),
        actionButton("clustering_select_stale", "Select stale"),
        actionButton("clustering_select_incomplete", "Select incomplete"),
        actionButton("clustering_select_clear", "Clear")
      ),
      p("Select incomplete includes clustering not started, failed and stale; it excludes active computations.", class = "text-muted small"),
      tags$div(style = "max-height: 35vh; overflow-y: auto;",
        checkboxGroupInput(request$input_id, "Samples and clustering status:",
          choices = stats::setNames(samples, paste0(samples, " (", gsub("_", " ", statuses), ")")), selected = samples)
      ),
      p(paste("Every selected sample runs all configured resolutions:", paste(request$resolutions, collapse = ", "))),
      uiOutput("clustering_selection_summary"),
      p("This synchronous computation locks the app until finished. Review the selected names and downstream impact before running.", class = "text-muted"),
      easyClose = TRUE,
      size = "l",
      footer = tagList(
        modalButton("Cancel"),
        uiOutput("clustering_run_control")
      )
    ))
  })

  observeEvent(input$btn_run_single_clustering, {
    req(rv$paths_list, rv$pipeline_state)
    reason <- clustering_block_reason()
    if (!is.null(reason)) {
      showNotification(reason, type = "warning", duration = 10)
      return()
    }
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

    sample_names <- basename(rv$paths_list$sample_dir_paths)
    sample_choices <- stats::setNames(seq_along(sample_names), sample_names)
    arm_app_confirmation(rv, "single_sample_clustering")
    showModal(modalDialog(
      title = "Run Clustering for One Sample",
      selectInput(
        "single_clustering_sample",
        "Sample:",
        choices = sample_choices,
        selected = sample_choices[[1]]
      ),
      tags$div(
        class = "alert alert-warning mt-3",
        icon("exclamation-triangle"),
        " Rerunning clustering will make this sample's saved resolution, DE, annotation, and CNA work stale. Other samples are not changed."
      ),
      p(
        "All configured clustering resolutions will be recomputed. The application remains locked until this sample finishes.",
        class = "text-muted"
      ),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton(
          "confirm_run_single_clustering",
          "Yes, Cluster This Sample",
          class = "btn-danger",
          onclick = "this.disabled = true;"
        )
      )
    ))
  })

  observeEvent(input$confirm_run_single_clustering, {
    req(rv$paths_list, rv$dataset_config)
    reason <- clustering_block_reason()
    if (!is.null(reason)) {
      showNotification(reason, type = "warning", duration = 10)
      return()
    }
    selected_index <- suppressWarnings(as.integer(input$single_clustering_sample))
    sample_names <- basename(rv$paths_list$sample_dir_paths)
    if (
      length(selected_index) != 1L || is.na(selected_index) ||
        selected_index < 1L || selected_index > length(sample_names)
    ) {
      showNotification("Select a valid sample to cluster.", type = "error")
      return()
    }
    if (identical(get_pipeline_step(rv$pipeline_state, "clustering", sample_names[[selected_index]])$status, "in_progress")) {
      showNotification("Clustering is already in progress for this sample.", type = "warning")
      return()
    }
    if (!claim_app_confirmation(rv, "single_sample_clustering")) return()
    if (!begin_app_action(rv, "single_sample_clustering")) return()

    sample_name <- sample_names[[selected_index]]
    shinyjs::disable("btn_run_single_clustering")
    shinyjs::disable("btn_run_clustering")
    on.exit({
      finish_app_action(rv, "single_sample_clustering")
      shinyjs::enable("btn_run_single_clustering")
      shinyjs::enable("btn_run_clustering")
    }, add = TRUE)
    removeModal()

    id <- showNotification(
      paste("Running clustering for", sample_name, "..."),
      duration = NULL,
      type = "warning"
    )
    on.exit(removeNotification(id), add = TRUE)
    record_state_event(
      rv,
      stage = "clustering",
      event_type = "single_sample_clustering",
      outcome = "started",
      sample = sample_name,
      parameters = list(
        sample_index = selected_index,
        resolutions = rv$dataset_config$params$resolutions
      )
    )

    progress_context <- new.env(parent = emptyenv())
    tryCatch({
      withProgress(message = paste("Clustering", sample_name), value = 0, {
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
          progress_callback = make_shiny_batch_progress_callback(progress_context),
          sample_indices = selected_index
        )
      })
      invalidated_cache <- cache_invalidate_sample(sample_name, rv$dataset_dir_path)
      single_clustering_completed_index(selected_index)
      record_state_event(
        rv,
        stage = "clustering",
        event_type = "single_sample_clustering",
        outcome = "completed",
        sample = sample_name,
        parameters = list(
          sample_index = selected_index,
          invalidated_cache_files = length(invalidated_cache)
        )
      )
      arm_app_confirmation(rv, "after_single_clustering_navigation")
      showModal(modalDialog(
        title = "Sample clustering complete",
        paste0(
          "Clustering is complete for '", sample_name,
          "'. Review every resolution and save the selected resolution again before rerunning DE."
        ),
        easyClose = TRUE,
        footer = tagList(
          modalButton("Stay on Start Menu"),
          actionButton(
            "btn_after_single_clustering_res",
            "Review This Sample's Resolutions",
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
        event_type = "single_sample_clustering",
        outcome = "failed",
        sample = sample_name,
        reason = failure_message,
        parameters = list(
          sample_index = selected_index,
          failed_stage = progress_context$stage
        )
      )
      showNotification(failure_message, type = "error", duration = 10)
    })
  })

  observeEvent(input$confirm_run_clustering, {
    if (!("bulk_clustering" %in% rv$open_confirmations)) return()
    selection <- tryCatch(resolve_clustering_selection(), error = identity)
    if (inherits(selection, "error")) {
      showNotification(conditionMessage(selection), type = "warning", duration = 12)
      return()
    }
    if (!claim_app_confirmation(rv, "bulk_clustering")) return()
    if (!begin_app_action(rv, "bulk_clustering")) return()
    clustering_completion_context(NULL)
    claim_app_confirmation(rv, "after_clustering_navigation")
    completed_samples <- character()
    shinyjs::disable("btn_run_clustering")
    shinyjs::disable("btn_run_single_clustering")
    on.exit({
      finish_app_action(rv, "bulk_clustering")
      shinyjs::enable("btn_run_clustering")
      shinyjs::enable("btn_run_single_clustering")
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
        sample_count = length(selection$samples), selected_samples = selection$samples,
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
            if (identical(status, "completed")) {
              cache_invalidate_sample(sample_name, rv$dataset_dir_path)
            }
            persist_sample_step(
              "clustering",
              sample_name,
              status,
              reason,
              details
            )
            if (identical(status, "completed")) completed_samples <<- c(completed_samples, sample_name)
          },
          progress_callback = make_shiny_batch_progress_callback(progress_context),
          sample_indices = selection$indices
        )
      })
      clustering_completion_context(list(
        dataset_dir = selection$context$dataset_dir, dataset_id = selection$context$dataset_id,
        samples = completed_samples
      ))
      record_state_event(
        rv,
        stage = "clustering",
        event_type = "clustering_run",
        outcome = "completed",
        parameters = list(sample_count = length(completed_samples), selected_samples = selection$samples, completed_samples = completed_samples)
      )
      arm_app_confirmation(rv, "after_clustering_navigation")
      showModal(modalDialog(
        title = "Clustering complete",
        paste0(length(completed_samples), if (length(completed_samples) == 1L) " selected sample clustered: " else " selected samples clustered: ", paste(completed_samples, collapse = ", "),
               ". Unselected samples are unchanged. Review and save a resolution for each processed sample before rerunning DE."),
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
          selected_samples = selection$samples, completed_samples = completed_samples,
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
    if (block_de_for_unsaved_annotation()) return()
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
    if (block_de_for_unsaved_annotation()) {
      removeModal()
      return()
    }
    if (!begin_app_action(rv, "bulk_de")) return()
    # A failed/new run must not leave an earlier completion action armed.
    de_completion_context(NULL)
    claim_app_confirmation(rv, "after_de_navigation")
    run_context <- list(dataset_dir = rv$dataset_dir_path, dataset_id = rv$pipeline_state$dataset_id)
    completed_samples <- character()
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
            if (identical(status, "completed")) {
              completed_samples <<- unique(c(completed_samples, sample_name))
            }
          },
          progress_callback = make_shiny_batch_progress_callback(progress_context)
        )
      })
      run_context$processed_samples <- completed_samples
      de_completion_context(run_context)
      review <- summarize_de_annotation_review(
        rv$pipeline_state, completed_samples, basename(rv$paths_list$sample_dir_paths)
      )
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
        de_review_message(review),
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
