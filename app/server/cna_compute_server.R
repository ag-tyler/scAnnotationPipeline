# CNA computation handlers.

register_cna_compute_server <- function(input, output, session, state, context) {
  rv <- state

  persist_cna_compute <- function(sample_name, status, reason = NULL, details = NULL) {
    current <- get_pipeline_step(rv$pipeline_state, "cna_compute", sample_name)
    invalidate <- identical(status, "in_progress") &&
      current$status %in% c("completed", "skipped")
    if (identical(status, "incomplete") && current$status %in% c("completed", "skipped")) {
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

    state_started <- tryCatch(persist_cna_compute(s_name, "in_progress"), error = identity)
    if (inherits(state_started, "error")) {
      showNotification(
        paste("CNA could not start because workflow state failed:", conditionMessage(state_started)),
        type = "error",
        duration = 10
      )
      return()
    }

    id <- showNotification("Computing CNA and Heatmaps. Check R console...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    record_state_event(
      rv,
      stage = "cna",
      event_type = "cna_compute",
      outcome = "started",
      sample = s_name
    )

    tryCatch({
      # Load filtered data from cache
      cells_file <- paste0('cells_filt_clust_res_', rv$live_selected_config$resolutions[[s_name]], '_', s_name, '.qs2')
      expmat_file <- paste0('expmat_filt_', s_name, '.qs2')

      cells_filt <- cache_load_data(cells_file, rv$dataset_dir_path)
      expmat_filt <- cache_load_data(expmat_file, rv$dataset_dir_path)

      # Prepare reference cells
      cells_filt[is.na(cell_type), cell_type := 'Unassigned']
      ref_cells <- cells_filt[cell_type %in% rv$live_selected_config$cna_ref_cells[[s_name]]]

      # Compute CNA
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
      showNotification("CNA and Heatmaps computed successfully!", type = "default")
      shinyjs::enable("btn_cna_go_malig_clust")

      # Trigger UI update by moving to the next tab
      nav_select("cna_main_views", "cna_view_select_malignant")
    }, error = function(error) {
      try(persist_cna_compute(s_name, "failed", reason = conditionMessage(error)), silent = TRUE)
      record_state_event(
        rv,
        stage = "cna",
        event_type = "cna_compute",
        outcome = "failed",
        sample = s_name,
        reason = conditionMessage(error)
      )
      showNotification(
        paste("CNA computation failed:", conditionMessage(error)),
        type = "error",
        duration = 10
      )
    })
  })

  # --- STEP 1b: Batch Compute CNA & Heatmaps ---
  observeEvent(input$btn_cna_batch_compute, {
    req(rv$paths_list)
    showModal(modalDialog(
      title = "Confirm Batch CNA Computation",
      "Are you sure you want to run the CNA and Heatmap pipeline for ALL valid samples? This process takes a significant amount of time and will lock the application.",
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_cna_batch", "Yes, Run Batch", class = "btn-danger")
      )
    ))
  })

  observeEvent(input$confirm_cna_batch, {
    removeModal()
    sample_names <- basename(rv$paths_list$sample_dir_paths)
    blocked_samples <- sample_names[vapply(sample_names, function(sample_name) {
      !pipeline_step_readiness(rv$pipeline_state, "cna_compute", sample_name)$ready
    }, logical(1))]
    if (length(blocked_samples) > 0L) {
      reason <- paste(
        "CNA prerequisites are incomplete for:",
        paste(blocked_samples, collapse = ", ")
      )
      record_state_event(
        rv,
        stage = "cna",
        event_type = "cna_batch_compute",
        outcome = "incomplete",
        reason = reason,
        parameters = list(blocked_samples = blocked_samples)
      )
      showNotification(reason, type = "error", duration = 10)
      return()
    }
    id <- showNotification("Running Batch CNA Computation. Check R console...", duration = NULL, type = "warning")
    on.exit(removeNotification(id), add = TRUE)
    record_state_event(
      rv,
      stage = "cna",
      event_type = "cna_batch_compute",
      outcome = "started",
      parameters = list(sample_count = length(rv$paths_list$sample_dir_paths))
    )

    tryCatch({
      # Run backend logic
      res <- batch_compute_cna_and_heatmaps(
        paths_list = rv$paths_list,
        dataset_dir_path = rv$dataset_dir_path,
        results_dir_path = rv$results_dir_path,
        selected_config = rv$live_selected_config,
        gene_positions = context$resources$gene_positions,
        state_callback = function(sample_name, status, reason = NULL, details = NULL) {
          persist_cna_compute(sample_name, status, reason, details)
        }
      )

      for (skip_label in res$skipped) {
        missing_cache <- grepl(" \\(Missing Cache\\)$", skip_label)
        skipped_sample <- sub(" \\(Missing Cache\\)$", "", skip_label)
        record_state_event(
          rv,
          stage = "cna",
          event_type = "cna_compute",
          outcome = "incomplete",
          sample = skipped_sample,
          reason = if (missing_cache) {
            "Required filtering or clustering caches are missing."
          } else {
            "Reference or potentially malignant cell types are not configured."
          }
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
      record_state_event(
        rv,
        stage = "cna",
        event_type = "cna_batch_compute",
        outcome = "completed",
        parameters = list(
          processed_count = length(res$processed),
          skipped_count = length(res$skipped)
        )
      )

      # Report results to user
      msg <- paste0(
        "Batch Complete!\nProcessed: ", length(res$processed),
        " samples\nIncomplete: ", length(res$skipped), " samples"
      )
      showNotification(msg, type = "message", duration = 15)

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
