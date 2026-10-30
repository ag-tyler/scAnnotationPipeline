# CNA preview and final-assignment handlers.

register_cna_summary_server <- function(input, output, session, state, context) {
  rv <- state
  cna_export_revision <- reactiveVal(0L)

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

  publish_cna_values <- function(
    sample_name,
    show_progress = TRUE
  ) {
    export_stage <- NULL
    report_export_progress <- function(stage, progress, detail, elapsed_seconds) {
      if (!identical(export_stage, stage)) {
        record_state_event(rv, stage = "cna", event_type = "cna_values_export_stage",
          outcome = "in_progress", sample = sample_name,
          parameters = list(stage = stage, elapsed_seconds = elapsed_seconds, detail = detail))
        message("CNA export | ", sample_name, " | ", stage, " | ", detail)
      }
      export_stage <<- stage
      if (isTRUE(show_progress)) setProgress(value = progress, detail = detail)
    }
    perform_export <- function() {
      export_cna_values_table(
        sample_name = sample_name,
        dataset_dir_path = rv$dataset_dir_path,
        results_dir_path = rv$results_dir_path,
        progress_callback = report_export_progress
      )
    }
    record_state_event(rv, stage = "cna", event_type = "cna_values_export",
      outcome = "started", sample = sample_name)
    result <- tryCatch(
      if (isTRUE(show_progress)) {
        withProgress(
          message = paste("Exporting CNA values:", sample_name),
          value = 0,
          {
            exported <- perform_export()
            setProgress(value = 1, detail = "Compressed table and provenance saved")
            exported
          }
        )
      } else {
        perform_export()
      },
      error = identity,
      interrupt = function(condition) {
        structure(list(message = paste0("CNA export interrupted during ", export_stage, "."), call = NULL),
          class = c("cna_export_interrupted", "error", "condition"))
      }
    )
    cna_export_revision(cna_export_revision() + 1L)
    if (inherits(result, "error")) {
      record_state_event(
        rv,
        stage = "cna",
        event_type = "cna_values_export",
        outcome = if (inherits(result, "cna_export_interrupted")) "interrupted" else "failed",
        sample = sample_name,
        reason = conditionMessage(result)
      )
      showNotification(
        paste(
          "CNA values-table export failed:",
          conditionMessage(result),
          "Use Export/Re-export CNA Values Table to retry."
        ),
        type = "warning",
        duration = 12
      )
      return(invisible(FALSE))
    }
    record_state_event(
      rv,
      stage = "cna",
      event_type = "cna_values_export",
      outcome = "completed",
      sample = sample_name,
      parameters = list(
        path = result$paths$csv,
        row_count = result$row_count,
        checksum = result$csv_checksum,
        elapsed_seconds = result$elapsed_seconds
      )
    )
    invisible(result)
  }

  output$cna_values_export_status <- renderUI({
    cna_export_revision()
    req(input$cna_sample_idx, rv$dataset_dir_path, rv$results_dir_path)
    sample_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    status <- cna_values_export_status(
      sample_name,
      rv$dataset_dir_path,
      rv$results_dir_path
    )
    if (!status$exists) {
      return(tags$small("Optional CNA values table has not been exported.", class = "text-muted"))
    }
    if (status$current) {
      return(tags$small(
        icon("circle-check"),
        paste("Current compressed table:", basename(status$paths$csv)),
        class = "text-success"
      ))
    }
    tags$small(
      icon("triangle-exclamation"),
      paste("Export needs refreshing.", status$reason),
      class = "text-warning"
    )
  })

  observeEvent(input$btn_cna_export_values, {
    req(input$cna_sample_idx)
    sample_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    result <- publish_cna_values(sample_name, show_progress = TRUE)
    if (!identical(result, FALSE)) {
      showNotification(
        paste("CNA values table exported for", sample_name),
        type = "message"
      )
    }
  })

  # --- STEP 5: PREVIEW ASSIGNMENTS & SUMMARY ---
  prepare_cna_preview <- function(notify_reuse = FALSE) {
    req(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]

    readiness <- pipeline_step_readiness(rv$pipeline_state, "cna_assignment", s_name)
    if (!readiness$ready) {
      showNotification(
        paste("Cannot preview final assignments:", paste(readiness$reasons, collapse = "; ")),
        type = "error",
        duration = 10
      )
      return(invisible(FALSE))
    }

    fingerprint <- tryCatch(
      cna_preview_fingerprint(s_name, rv$dataset_dir_path, rv$live_selected_config),
      error = identity
    )
    if (inherits(fingerprint, "error")) {
      record_state_event(
        rv,
        stage = "cna",
        event_type = "cna_preview",
        outcome = "failed",
        sample = s_name,
        reason = conditionMessage(fingerprint)
      )
      showNotification(
        paste("Cannot prepare CNA preview:", conditionMessage(fingerprint)),
        type = "error",
        duration = 10
      )
      return(invisible(FALSE))
    }

    reusable <- !is.null(rv$cna_preview_res) &&
      identical(rv$cna_preview_sample, s_name) &&
      identical(rv$cna_preview_fingerprint, fingerprint)

    if (!reusable) {
      result <- tryCatch(
        withProgress(message = paste("CNA preview:", s_name), value = 0, {
          setProgress(value = 0, detail = "Applying thresholds in memory")
          preview <- preview_cna_summary(
            sample_name = s_name,
            dataset_dir_path = rv$dataset_dir_path,
            selected_config = rv$live_selected_config
          )
          setProgress(value = 1, detail = "Scatter, UMAP, and heatmap previews ready")
          preview
        }),
        error = identity
      )
      if (inherits(result, "error")) {
        record_state_event(
          rv,
          stage = "cna",
          event_type = "cna_preview",
          outcome = "failed",
          sample = s_name,
          reason = conditionMessage(result)
        )
        showNotification(
          paste("CNA preview generation failed:", conditionMessage(result)),
          type = "error",
          duration = 10
        )
        return(invisible(FALSE))
      }
      rv$cna_preview_res <- result
      rv$cna_preview_sample <- s_name
      rv$cna_preview_fingerprint <- fingerprint
    }

    # 1. Render Scatter Plots dynamically (Side-by-side: Original vs New)
    output$cna_preview_scatter_ui <- renderUI({
      ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
      plot_output_list <- lapply(seq_along(rv$cna_preview_res$pre_scatter_plots), function(i) {
        pre_name <- paste0("cna_preview_scatter_pre_", i)
        post_name <- paste0("cna_preview_scatter_post_", i)
        cluster_label <- cna_cluster_labels(ward_refs[[i]]$cluster, ward_refs[[i]]$k)

        fluidRow(
          column(12, h4(paste("Subclone", i, "—", cluster_label), class = "mt-3 text-center fw-bold")),
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

    # 2. Render before/after UMAP plots
    output$cna_preview_umap_pre <- renderPlot({ rv$cna_preview_res$pre_umap_plot })
    output$cna_preview_umap <- renderPlot({ rv$cna_preview_res$umap_plot })

    # 3. Render Summary Heatmap
    output$cna_preview_heatmap <- renderPlot({ rv$cna_preview_res$summary_heatmap })

    # Enable the finalization button
    shinyjs::enable("btn_cna_save_summary")
    nav_select("cna_preview_tabs", "cna_preview_scatter")
    record_state_event(
      rv,
      stage = "cna",
      event_type = "cna_preview",
      outcome = if (reusable) "reused" else "generated",
      sample = s_name,
      parameters = list(fingerprint = fingerprint)
    )
    if (isTRUE(notify_reuse) && reusable) {
      showNotification("The current CNA preview is already up to date.", type = "message")
    }
    invisible(TRUE)
  }

  observeEvent(input$cna_main_views, {
    if (identical(input$cna_main_views, "cna_view_summary")) {
      prepare_cna_preview(notify_reuse = FALSE)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$btn_cna_preview_summary, {
    prepare_cna_preview(notify_reuse = TRUE)
  })


  # --- STEP 6: FINALIZE & SAVE ---
  observeEvent(input$btn_cna_save_summary, {
    req(input$cna_sample_idx, rv$cna_preview_res)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]

    current_fingerprint <- tryCatch(
      cna_preview_fingerprint(s_name, rv$dataset_dir_path, rv$live_selected_config),
      error = identity
    )
    if (
      inherits(current_fingerprint, "error") ||
        !identical(rv$cna_preview_sample, s_name) ||
        !identical(rv$cna_preview_fingerprint, current_fingerprint)
    ) {
      showNotification(
        "The CNA preview is stale. Reopen Assign & Summary to regenerate it before saving.",
        type = "error",
        duration = 10
      )
      shinyjs::disable("btn_cna_save_summary")
      return()
    }

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
    ggplot2::ggsave(file.path(cna_plots_dir_path, paste0('cna_umap_pre_cna_', s_name, '.png')),
                    plot = rv$cna_preview_res$pre_umap_plot, width = 300, height = 400, units = 'mm', bg = "white")
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
          subclone_count = length(unique(stats::na.omit(cells_to_save$subclone))),
          snapshot_annotations = capture_snapshot_annotations(
            cells_to_save, cells_raw_path, rv$live_selected_config$resolutions[[s_name]],
            get_pipeline_step(rv$pipeline_state, "clustering", s_name)
          )
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

    showNotification(
      "CNA Analysis Complete! Assignments and plots saved. CNA values-table export is optional.",
      type = "default"
    )

    # Saving updates the cell-cache checksum included in preview provenance.
    # The displayed preview produced these exact assignments, so rebase its
    # fingerprint without recomputing plots or leaving Assign & Summary.
    rv$cna_preview_fingerprint <- tryCatch(
      cna_preview_fingerprint(s_name, rv$dataset_dir_path, rv$live_selected_config),
      error = function(error) NULL
    )
  })
}
