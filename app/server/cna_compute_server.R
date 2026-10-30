# CNA computation handlers.

register_cna_compute_server <- function(input, output, session, state, context) {
  rv <- state

  persist_cna_compute <- function(sample_name, status, reason = NULL, details = NULL) {
    current <- get_pipeline_step(rv$pipeline_state, "cna_compute", sample_name)
    invalidate <- identical(status, "in_progress") &&
      current$status %in% c("completed", "skipped")
    if (
      status %in% c("incomplete", "skipped") &&
        current$status %in% c("completed", "skipped") &&
        !(identical(status, "skipped") && identical(current$status, "skipped"))
    ) {
      rv$pipeline_state <- persist_pipeline_step_update(
        rv$pipeline_state,
        rv$pipeline_state_path,
        step = "cna_compute",
        status = "in_progress",
        sample = sample_name,
        invalidate_downstream = TRUE,
        invalidation_reason = "The CNA computation is no longer ready to run."
      )
      invalidate <- FALSE
    }
    rv$pipeline_state <- persist_pipeline_step_update(
      rv$pipeline_state,
      rv$pipeline_state_path,
      step = "cna_compute",
      status = status,
      sample = sample_name,
      reason = reason,
      details = details,
      invalidate_downstream = invalidate,
      invalidation_reason = if (invalidate) "Base CNA computation is being rerun." else NULL
    )
    invisible(rv$pipeline_state)
  }

  # ================================================================================================
  # CNA PIPELINE EXECUTION
  # ================================================================================================

  # --- STEP 1: Compute CNA & Heatmaps ---
  observeEvent(input$btn_cna_compute_heatmaps, {
    req(input$cna_sample_idx, rv$paths_list)
    idx <- as.numeric(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]

    readiness <- pipeline_step_readiness(rv$pipeline_state, "cna_compute", s_name)
    if (!readiness$ready) {
      showNotification(
        paste("Cannot compute CNA:", paste(readiness$reasons, collapse = "; ")),
        type = "error",
        duration = 10
      )
      return()
    }


    preflight <- cna_sample_preflight(
      s_name,
      rv$live_selected_config,
      rv$dataset_dir_path,
      gene_positions = context$resources$gene_positions,
      pipeline_state = rv$pipeline_state,
      validate_expression = TRUE
    )
    if (!isTRUE(preflight$eligible)) {
      state_status <- if (identical(preflight$status, "ineligible")) {
        "skipped"
      } else {
        "incomplete"
      }
      try(
        persist_cna_compute(
          s_name,
          state_status,
          reason = preflight$reason,
          details = list(preflight_status = preflight$status, counts = preflight$counts)
        ),
        silent = TRUE
      )
      record_state_event(
        rv,
        stage = "cna",
        event_type = "cna_preflight",
        outcome = preflight$status,
        sample = s_name,
        parameters = preflight$counts,
        reason = preflight$reason
      )
      showNotification(
        paste("CNA cannot run:", preflight$reason),
        type = if (identical(preflight$status, "invalid")) "error" else "warning",
        duration = 12
      )
      return()
    }

    state_started <- tryCatch(persist_cna_compute(s_name, "in_progress"), error = identity)
    if (inherits(state_started, "error")) {
      showNotification(
        paste("CNA could not start because workflow state failed:", conditionMessage(state_started)),
        type = "error",
        duration = 10
      )
      return()
    }

    record_state_event(
      rv,
      stage = "cna",
      event_type = "cna_compute",
      outcome = "started",
      sample = s_name
    )

    tryCatch({
      withProgress(message = paste("CNA:", s_name), value = 0, {
        setProgress(value = 0, detail = "Stage 1 of 3: preparing validated inputs")
        cells_filt <- preflight$cells
        expmat_filt <- preflight$expmat
        ref_cells <- preflight$ref_cells

        # Compute CNA
        setProgress(value = 1 / 3, detail = "Stage 2 of 3: computing or validating CNA matrix")
        cna_mat_file_name <- paste0('cna_matrix_', s_name, '.qs2')
        cna_dependencies <- cna_matrix_cache_dependencies(
          s_name,
          rv$dataset_dir_path,
          context$resources$gene_positions,
          ref_cells
        )
        if (!cache_check_valid(cna_mat_file_name, rv$dataset_dir_path, cna_dependencies)) {
          cache_invalidate_sample(
            s_name,
            rv$dataset_dir_path,
            artifact_types = c("cna_matrix", "cna_hclust", "cna_signal_correlation")
          )
          compute_cna_and_cache(expmat_filt, context$resources$gene_positions, ref_cells, s_name, rv$dataset_dir_path)
        } else {
          record_state_event(
            rv,
            stage = "cache",
            event_type = "cna_matrix_cache",
            outcome = "reused",
            sample = s_name,
            parameters = list(cache_file = cna_mat_file_name)
          )
        }

        # Compute Heatmaps
        setProgress(value = 2 / 3, detail = "Stage 3 of 3: generating clustering and heatmaps")
        cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
        dir.create(cna_plots_dir_path, showWarnings = FALSE)

        cna_clustering_and_heatmaps(ref_cells, s_name, rv$live_selected_config, cna_plots_dir_path,
                                    rv$dataset_dir_path)

        persist_cna_compute(
          s_name,
          "completed",
          details = list(reference_cell_count = nrow(ref_cells))
        )

        record_state_event(
          rv,
          stage = "cna",
          event_type = "cna_compute",
          outcome = "completed",
          sample = s_name,
          parameters = list(reference_cell_count = nrow(ref_cells))
        )
        setProgress(value = 1, detail = "CNA and heatmaps complete")
        showNotification("CNA and Heatmaps computed successfully!", type = "default")
        shinyjs::enable("btn_cna_go_malig_clust")

        # Trigger UI update by moving to the next tab
        nav_select("cna_main_views", "cna_view_select_malignant")
      })
    }, error = function(error) {
      ineligible <- inherits(error, "cna_ineligible_error")
      outcome <- if (ineligible) "skipped" else "failed"
      try(persist_cna_compute(s_name, outcome, reason = conditionMessage(error)), silent = TRUE)
      record_state_event(
        rv,
        stage = "cna",
        event_type = "cna_compute",
        outcome = outcome,
        sample = s_name,
        reason = conditionMessage(error)
      )
      showNotification(
        paste(
          if (ineligible) "CNA is not applicable:" else "CNA computation failed:",
          conditionMessage(error)
        ),
        type = if (ineligible) "warning" else "error",
        duration = 10
      )
    })
  })

  # --- STEP 1b: Batch Compute CNA & Heatmaps ---
  observeEvent(input$btn_cna_batch_compute, {
    req(rv$paths_list)
    sample_names <- basename(rv$paths_list$sample_dir_paths)
    status_labels <- vapply(sample_names, function(sample_name) {
      get_pipeline_step(rv$pipeline_state, "cna_compute", sample_name)$status
    }, character(1))
    choices <- stats::setNames(
      sample_names,
      paste0(sample_names, " (", status_labels, ")")
    )
    resume_samples <- sample_names[status_labels != "completed"]
    arm_app_confirmation(rv, "cna_batch_compute")
    showModal(modalDialog(
      title = "Confirm Batch CNA Computation",
      p(
        "Select the samples to run. Incomplete, skipped, stale, and failed samples are selected by default; completed samples remain available for an intentional rerun."
      ),
      checkboxGroupInput(
        "cna_batch_samples",
        "Samples:",
        choices = choices,
        selected = resume_samples
      ),
      p(
        "Each sample is preflighted independently. Ineligible samples are skipped and a failure in one sample will not stop the others.",
        class = "text-muted"
      ),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_cna_batch", "Yes, Run Batch", class = "btn-danger")
      )
    ))
  })

  observeEvent(input$confirm_cna_batch, {
    selected_samples <- input$cna_batch_samples
    if (is.null(selected_samples) || length(selected_samples) == 0L) {
      showNotification("Select at least one sample for batch CNA.", type = "warning")
      return()
    }
    if (!claim_app_confirmation(rv, "cna_batch_compute")) return()
    if (!begin_app_action(rv, "cna_batch_compute")) return()
    shinyjs::disable("btn_cna_batch_compute")
    shinyjs::disable("confirm_cna_batch")
    on.exit({
      finish_app_action(rv, "cna_batch_compute")
      shinyjs::enable("btn_cna_batch_compute")
      shinyjs::enable("confirm_cna_batch")
    }, add = TRUE)
    removeModal()
    record_state_event(
      rv,
      stage = "cna",
      event_type = "cna_batch_compute",
      outcome = "started",
      parameters = list(
        sample_count = length(selected_samples),
        samples = unname(selected_samples)
      )
    )

    tryCatch({
      # Run backend logic
      res <- withProgress(
        message = "Batch CNA computation",
        value = 0,
        {
          batch_compute_cna_and_heatmaps(
            paths_list = rv$paths_list,
            dataset_dir_path = rv$dataset_dir_path,
            results_dir_path = rv$results_dir_path,
            selected_config = rv$live_selected_config,
            gene_positions = context$resources$gene_positions,
            sample_names = selected_samples,
            pipeline_state = rv$pipeline_state,
            state_callback = function(sample_name, status, reason = NULL, details = NULL) {
              persist_cna_compute(sample_name, status, reason, details)
            },
            progress_callback = function(
              sample_name,
              sample_index,
              sample_total,
              stage,
              detail = NULL
            ) {
              terminal <- stage %in% c("completed", "skipped", "failed")
              completed_count <- sample_index - if (terminal) 0 else 1
              setProgress(
                value = completed_count / sample_total,
                detail = paste0(
                  "Sample ", sample_index, " of ", sample_total, ": ",
                  sample_name, " — ", if (is.null(detail)) stage else detail
                )
              )
            }
          )
        }
      )

      for (skip_label in res$skipped) {
        skipped_sample <- sub(" \\(Missing Cache\\)$", "", skip_label)
        preflight <- res$preflight[[skipped_sample]]
        record_state_event(
          rv,
          stage = "cna",
          event_type = "cna_compute",
          outcome = if (!is.null(preflight$status)) preflight$status else "incomplete",
          sample = skipped_sample,
          parameters = if (is.null(preflight$counts)) list() else preflight$counts,
          reason = if (is.null(preflight$reason)) {
            "CNA preflight did not pass."
          } else preflight$reason
        )
      }
      for (processed_sample in res$processed) {
        record_state_event(
          rv,
          stage = "cna",
          event_type = "cna_compute",
          outcome = "completed",
          sample = processed_sample,
          parameters = list(batch = TRUE)
        )
      }
      for (failed_sample in names(res$failed)) {
        record_state_event(
          rv,
          stage = "cna",
          event_type = "cna_compute",
          outcome = "failed",
          sample = failed_sample,
          reason = unname(res$failed[[failed_sample]]),
          parameters = list(batch = TRUE)
        )
      }
      record_state_event(
        rv,
        stage = "cna",
        event_type = "cna_batch_compute",
        outcome = if (length(res$failed) > 0L) "completed_with_failures" else "completed",
        parameters = list(
          processed_count = length(res$processed),
          skipped_count = length(res$skipped),
          failed_count = length(res$failed),
          processed_samples = unname(res$processed),
          skipped_samples = unname(res$skipped),
          failed_samples = names(res$failed)
        )
      )

      # Report results to user
      result_line <- function(label, samples) {
        tags$p(
          tags$strong(paste0(label, " (", length(samples), "): ")),
          if (length(samples) == 0L) "None" else paste(samples, collapse = ", ")
        )
      }
      showModal(modalDialog(
        title = "Batch CNA complete",
        result_line("Completed", res$processed),
        result_line("Skipped / incomplete", res$skipped),
        result_line("Failed", names(res$failed)),
        easyClose = TRUE,
        footer = modalButton("Close")
      ))

      # If the currently selected sample in the UI was just processed, unlock Step 2 automatically
      current_s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
      if (current_s_name %in% res$processed) {
        shinyjs::enable("btn_cna_go_malig_clust")
        nav_select("cna_main_views", "cna_view_select_malignant")
      }
    }, error = function(error) {
      record_state_event(
        rv,
        stage = "cna",
        event_type = "cna_batch_compute",
        outcome = "failed",
        reason = conditionMessage(error)
      )
      showNotification(
        paste("Batch CNA computation failed:", conditionMessage(error)),
        type = "error",
        duration = 10
      )
    })
  })
}
