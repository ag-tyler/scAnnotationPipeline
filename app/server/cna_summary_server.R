# CNA preview and final-assignment handlers.

register_cna_summary_server <- function(input, output, session, state, context) {
  rv <- state

  persist_assignment_state <- function(sample_name, details) {
    rv$pipeline_state <- persist_pipeline_step_update(
      rv$pipeline_state,
      rv$pipeline_state_path,
      step = "cna_assignment",
      status = "completed",
      sample = sample_name,
      details = details
    )
    invisible(rv$pipeline_state)
  }

  # --- STEP 5: PREVIEW ASSIGNMENTS & SUMMARY ---
  observeEvent(input$btn_cna_preview_summary, {
    req(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]

    readiness <- pipeline_step_readiness(rv$pipeline_state, "cna_assignment", s_name)
    if (!readiness$ready) {
      showNotification(
        paste("Cannot preview final assignments:", paste(readiness$reasons, collapse = "; ")),
        type = "error",
        duration = 10
      )
      return()
    }

    id <- showNotification("Generating previews. Please wait...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    # Store preview results in rv so we can save them later without recomputing
    rv$cna_preview_res <- preview_cna_summary(
      sample_name = s_name,
      dataset_dir_path = rv$dataset_dir_path,
      selected_config = rv$live_selected_config
    )

    # 1. Render Scatter Plots dynamically (Side-by-side: Original vs New)
    output$cna_preview_scatter_ui <- renderUI({
      plot_output_list <- lapply(seq_along(rv$cna_preview_res$pre_scatter_plots), function(i) {
        pre_name <- paste0("cna_preview_scatter_pre_", i)
        post_name <- paste0("cna_preview_scatter_post_", i)

        fluidRow(
          column(12, h4(paste("Subclone", i, "Comparisons"), class = "mt-3 text-center fw-bold")),
          column(6, plotOutput(pre_name, height = "450px")),
          column(6, plotOutput(post_name, height = "450px")),
          column(12, hr())
        )
      })
      do.call(tagList, plot_output_list)
    })

    # Wire the specific renderPlot functions for both lists
    lapply(seq_along(rv$cna_preview_res$pre_scatter_plots), function(i) {
      local({
        local_i <- i

        output[[paste0("cna_preview_scatter_pre_", local_i)]] <- renderPlot({
          # Silently halt if this plot index no longer exists in the new data
          req(local_i <= length(rv$cna_preview_res$pre_scatter_plots))
          rv$cna_preview_res$pre_scatter_plots[[local_i]]
        })

        output[[paste0("cna_preview_scatter_post_", local_i)]] <- renderPlot({
          # Silently halt if this plot index no longer exists in the new data
          req(local_i <= length(rv$cna_preview_res$post_scatter_plots))
          rv$cna_preview_res$post_scatter_plots[[local_i]]
        })
      })
    })

    # 2. Render UMAP Plot
    output$cna_preview_umap <- renderPlot({ rv$cna_preview_res$umap_plot })

    # 3. Render Summary Heatmap
    output$cna_preview_heatmap <- renderPlot({ rv$cna_preview_res$summary_heatmap })

    # Enable the finalization button
    shinyjs::enable("btn_cna_save_summary")
  })


  # --- STEP 6: FINALIZE & SAVE ---
  observeEvent(input$btn_cna_save_summary, {
    req(input$cna_sample_idx, rv$cna_preview_res)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]

    readiness <- pipeline_step_readiness(rv$pipeline_state, "cna_assignment", s_name)
    if (!readiness$ready) {
      showNotification(
        paste("Cannot save final assignments:", paste(readiness$reasons, collapse = "; ")),
        type = "error",
        duration = 10
      )
      return()
    }

    id <- showNotification("Saving cell assignments and plots to disk...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    # NEW: Create a copy of the preview data and revert 'Unassigned' back to standard NA
    cells_to_save <- data.table::copy(rv$cna_preview_res$cells_filt)
    cells_to_save[cell_type == 'Unassigned', cell_type := NA_character_]

    # 1. Save updated cell labels to cache
    cells_file <- paste0('cells_filt_clust_res_', rv$live_selected_config$resolutions[[s_name]], '_', s_name, '.qs2')
    cache_save_data(cells_to_save, cells_file, rv$dataset_dir_path)

    # 2. Sync with the raw Cells.csv so Manual Annotation sees these updates
    cells_raw_path <- rv$paths_list$cell_file_paths[as.numeric(input$cna_sample_idx)]
    cells_raw <- load_cells(cells_raw_path)

    # Force the subclone column to integer to prevent logical coercion warnings
    if ("subclone" %in% names(cells_raw)) {
      cells_raw[, subclone := as.integer(subclone)]
    }

    cells_raw[cells_to_save, on = 'cell_name',
              c('cell_type', 'subclone') := .(i.cell_type, i.subclone)]
    fwrite(cells_raw, file = cells_raw_path)

    # 3. Save Plots
    cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')

    # Save Heatmap
    ggplot2::ggsave(file.path(cna_plots_dir_path, paste0('cna_summary_heatmap_', s_name, '.png')),
                    plot = rv$cna_preview_res$summary_heatmap, width = 300, height = 400, units = 'mm',
                    dpi = 300, bg = "white")

    # Save UMAP
    ggplot2::ggsave(file.path(cna_plots_dir_path, paste0('cna_umap_assigned_', s_name, '.png')),
                    plot = rv$cna_preview_res$umap_plot, width = 300, height = 400, units = 'mm', bg = "white")

    # Save Scatter Plots (Pre and Post)
    for (i in seq_along(rv$cna_preview_res$pre_scatter_plots)) {
      ggplot2::ggsave(file.path(cna_plots_dir_path, paste0('cna_assignments_subclone_', i, '_original_', s_name, '.png')),
                      plot = rv$cna_preview_res$pre_scatter_plots[[i]], width = 7, height = 5, bg = "white")

      ggplot2::ggsave(file.path(cna_plots_dir_path, paste0('cna_assignments_subclone_', i, '_final_', s_name, '.png')),
                      plot = rv$cna_preview_res$post_scatter_plots[[i]], width = 7, height = 5, bg = "white")
    }

    state_result <- tryCatch(
      persist_assignment_state(
        s_name,
        details = list(
          cell_count = nrow(cells_to_save),
          malignant_count = sum(cells_to_save$cell_type == "Malignant", na.rm = TRUE),
          subclone_count = length(unique(stats::na.omit(cells_to_save$subclone)))
        )
      ),
      error = identity
    )
    if (inherits(state_result, "error")) {
      record_state_event(
        rv,
        stage = "state",
        event_type = "cna_assignment_state",
        outcome = "failed",
        sample = s_name,
        reason = conditionMessage(state_result)
      )
      showNotification(
        paste("Assignments were saved, but workflow state failed:", conditionMessage(state_result)),
        type = "error",
        duration = 10
      )
      return()
    }

    record_state_event(
      rv,
      stage = "cna",
      event_type = "cna_assignments_saved",
      outcome = "completed",
      sample = s_name,
      parameters = list(
        cell_count = nrow(cells_to_save),
        malignant_count = sum(cells_to_save$cell_type == "Malignant", na.rm = TRUE),
        subclone_count = length(unique(stats::na.omit(cells_to_save$subclone)))
      )
    )

    showNotification("CNA Analysis Complete! Results saved successfully.", type = "default")

    # Force the dropdown observer to re-evaluate and update the status menu
    shinyjs::runjs(paste0("$('#cna_sample_idx').trigger('change');"))
  })
}
