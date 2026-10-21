# CNA reset handlers.

register_cna_reset_server <- function(input, output, session, state, context) {
  rv <- state

  # --- STEP 7: RESET SAMPLE CNA ---
  observeEvent(input$btn_cna_reset, {
    req(input$cna_sample_idx, rv$paths_list)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]

    arm_app_confirmation(rv, "cna_reset")
    showModal(modalDialog(
      title = "Confirm CNA Reset",
      paste("Are you sure you want to reset the CNA analysis for '", s_name, "'? This will delete the cached CNA matrix, clustering, and thresholds. It will also revert any assigned malignant cells back to their manual annotations."),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton(
          "confirm_cna_reset",
          "Yes, Reset",
          class = "btn-danger",
          onclick = "this.disabled = true;"
        )
      )
    ))
  })

  observeEvent(input$confirm_cna_reset, {
    if (!claim_app_confirmation(rv, "cna_reset")) return()
    if (!begin_app_action(rv, "cna_reset")) return()
    shinyjs::disable("btn_cna_reset")
    on.exit({
      finish_app_action(rv, "cna_reset")
      shinyjs::enable("btn_cna_reset")
    }, add = TRUE)
    removeModal()
    req(input$cna_sample_idx, rv$paths_list, rv$live_selected_config)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]

    id <- showNotification(paste("Resetting CNA pipeline for", s_name, "..."), duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    # 1. Clear Configuration
    rv$live_selected_config$cna_ward_ref_cluster[[s_name]] <- NULL
    rv$live_selected_config$cna_thresholds[[s_name]] <- NULL

    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)

    # 2. Delete Cached Files
    cache_dir <- setup_cache_dir(rv$dataset_dir_path)

    files_to_delete <- c(
      file.path(cache_dir, paste0('cna_matrix_', s_name, '.qs2')),
      file.path(cache_dir, paste0('hclust_', s_name, '.qs2'))
    )

    # Find all dynamic subclone signal/cor files
    sig_cor_files <- list.files(cache_dir, pattern = paste0('^cna_sig_cor_', s_name, '_subclone_.*\\.qs2$'), full.names = TRUE)
    files_to_delete <- c(files_to_delete, sig_cor_files)

    existing <- files_to_delete[file.exists(files_to_delete)]
    ok <- if (length(existing) > 0L) {
      length(cache_invalidate_artifacts(basename(existing), rv$dataset_dir_path)) == length(existing)
    } else TRUE
    if (!ok) {
      warning('Could not delete: ', paste(existing[!ok], collapse = ', '),
              ' — file may be locked. Close any programs/previews touching the cache folder and retry.')
    }

    # 3. Delete Plots
    cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
    if (dir.exists(cna_plots_dir_path)) {
      unlink(cna_plots_dir_path, recursive = TRUE)
    }

    # 4. Revert Cell Assignments (if Step 5 was saved previously)
    cells_file <- paste0('cells_filt_clust_res_', rv$live_selected_config$resolutions[[s_name]], '_', s_name, '.qs2')
    if (cache_check_valid(cells_file, rv$dataset_dir_path)) {
      cells_filt <- cache_load_data(cells_file, rv$dataset_dir_path)

      # If cell_type_pre_cna exists, restore it so we don't lose manual annotations
      if ("cell_type_pre_cna" %in% names(cells_filt)) {
        cells_filt[, cell_type := cell_type_pre_cna]
        cells_filt[, subclone := NA_integer_]
        cache_save_data(cells_filt, cells_file, rv$dataset_dir_path)
      }
    }

    # Revert the raw CSV as well
    cells_raw_path <- rv$paths_list$cell_file_paths[as.numeric(input$cna_sample_idx)]
    if (file.exists(cells_raw_path)) {
      cells_raw <- data.table::fread(cells_raw_path)
      if ("cell_type_pre_cna" %in% names(cells_raw)) {
        cells_raw[, cell_type := cell_type_pre_cna]
        cells_raw[, subclone := NA_integer_]
        data.table::fwrite(cells_raw, file = cells_raw_path)
      }
    }

    state_result <- tryCatch({
      reset_state <- reset_pipeline_steps(
        rv$pipeline_state,
        steps = c(
          "cna_compute",
          "cna_cluster_selection",
          "cna_signal_correlation",
          "cna_thresholds",
          "cna_assignment"
        ),
        sample = s_name
      )
      save_pipeline_state_at_path(reset_state, rv$pipeline_state_path)
    }, error = identity)
    if (inherits(state_result, "error")) {
      record_state_event(
        rv,
        stage = "state",
        event_type = "cna_reset_state",
        outcome = "failed",
        sample = s_name,
        reason = conditionMessage(state_result)
      )
      showNotification(
        paste("CNA files were reset, but workflow state failed:", conditionMessage(state_result)),
        type = "error",
        duration = 10
      )
      return()
    }
    rv$pipeline_state <- state_result

    record_state_event(
      rv,
      stage = "cache",
      event_type = "cna_cache",
      outcome = "invalidated",
      sample = s_name,
      parameters = list(file_count = length(existing)),
      reason = "The user reset CNA analysis for this sample."
    )
    record_state_event(
      rv,
      stage = "cna",
      event_type = "cna_reset",
      outcome = "completed",
      sample = s_name
    )

    # 5. Refresh UI
    showNotification("Sample CNA reset successfully.", type = "default")

    # Force the main panel back to the default pipeline status view
    nav_select("cna_main_views", "cna_view_default")

    # Force Shiny to re-trigger the sample selection observer (even though the value hasn't changed)
    shinyjs::runjs("Shiny.setInputValue('cna_sample_idx', $('#cna_sample_idx').val(), {priority: 'event'});")
  })
}
