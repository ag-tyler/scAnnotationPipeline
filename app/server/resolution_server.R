# Resolution selection handlers.

register_resolution_server <- function(input, output, session, state, context) {
  rv <- state

  persist_de_state <- function(sample_name, status, reason = NULL, details = NULL) {
    current <- get_pipeline_step(
      rv$pipeline_state,
      "differential_expression",
      sample_name
    )
    invalidate <- identical(status, "in_progress") &&
      current$status %in% c("completed", "skipped")
    rv$pipeline_state <- persist_pipeline_step_update(
      rv$pipeline_state,
      rv$pipeline_state_path,
      step = "differential_expression",
      status = status,
      sample = sample_name,
      reason = reason,
      details = details,
      invalidate_downstream = invalidate,
      invalidation_reason = if (invalidate) {
        "Differential expression is being rerun for this sample."
      } else NULL
    )
    invisible(rv$pipeline_state)
  }

  output$res_status_badge <- renderUI({
    req(rv$paths_list, input$res_sample_idx, rv$pipeline_state)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    current_val <- rv$live_selected_config$resolutions[[s_name]]
    view <- pipeline_status_presentation(
      get_pipeline_step(rv$pipeline_state, "resolution", s_name),
      "Resolution"
    )
    resolution_text <- if (
      !is.null(current_val) && length(current_val) == 1L &&
        !is.na(current_val) && current_val != 0
    ) paste0(" (", current_val, ")") else ""
    tags$div(
      class = paste("badge w-100 py-2 mt-2", paste0("bg-", view$class)),
      style = "font-size: 14px; white-space: normal;",
      icon(view$icon),
      paste0(" ", view$label, resolution_text),
      if (!is.null(view$reason)) tags$div(class = "fw-normal mt-1", view$reason)
    )
  })

  output$res_header_text <- renderText({
    req(rv$paths_list, input$res_sample_idx)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    paste("Resolution Plots for:", s_name)
  })

  output$res_radio_ui <- renderUI({
    req(rv$paths_list, rv$dataset_config, input$res_sample_idx)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]

    current_val <- rv$live_selected_config$resolutions[[s_name]]
    if (is.null(current_val) || current_val == 0.0) current_val <- rv$dataset_config$params$resolutions[1]

    radioButtons("selected_res", "2. Choose Best Resolution:",
                 choices = rv$dataset_config$params$resolutions,
                 selected = current_val)
  })

  output$res_plots_tabs <- renderUI({
    req(rv$paths_list, rv$dataset_config, input$res_sample_idx)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    resolutions <- rv$dataset_config$params$resolutions

    grid_cols <- lapply(resolutions, function(res) {
      grid_output_id <- paste0("img_grid_", s_name, "_", res)

      local({
        local_res <- res
        local_s_name <- s_name
        output[[grid_output_id]] <- renderImage({
          plot_path <- file.path(rv$results_dir_path, local_s_name, '1_cluster_plots',
                                 paste0('clusters_plot_', local_s_name, '_res_', local_res, '.png'))

          if(!file.exists(plot_path)) return(list(src = "", alt = "Plot not found."))

          list(src = plot_path, width = "100%", style = "max-height: 35vh; object-fit: contain;", alt = paste("Grid Res:", local_res))
        }, deleteFile = FALSE)
      })

      column(6, h5(paste("Resolution:", res), class = "text-center mt-3"), imageOutput(grid_output_id, height = "auto"))
    })

    grid_tab <- nav_panel(
      title = "Grid View (All)",
      fluidRow(tagList(grid_cols))
    )

    individual_tabs <- lapply(resolutions, function(res) {
      tab_output_id <- paste0("img_tab_", s_name, "_", res)

      local({
        local_res <- res
        local_s_name <- s_name
        output[[tab_output_id]] <- renderImage({
          plot_path <- file.path(rv$results_dir_path, local_s_name, '1_cluster_plots',
                                 paste0('clusters_plot_', local_s_name, '_res_', local_res, '.png'))

          if(!file.exists(plot_path)) return(list(src = "", alt = "Plot not found."))

          list(src = plot_path, width = "100%", style = "max-height: 70vh; object-fit: contain;", alt = paste("Tab Res:", local_res))
        }, deleteFile = FALSE)
      })

      nav_panel(
        title = paste("Res:", res),
        div(class = "mt-3 text-center", imageOutput(tab_output_id, height = "auto"))
      )
    })

    all_tabs <- c(list(grid_tab), individual_tabs)
    do.call(navset_card_underline, all_tabs)
  })

  observeEvent(input$btn_save_res, {
    req(rv$paths_list, input$res_sample_idx, input$selected_res)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]

    readiness <- pipeline_step_readiness(rv$pipeline_state, "resolution", s_name)
    if (!readiness$ready) {
      showNotification(
        paste("Cannot save a resolution:", paste(readiness$reasons, collapse = "; ")),
        type = "error",
        duration = 10
      )
      return()
    }

    previous_resolution <- rv$live_selected_config$resolutions[[s_name]]
    selected_resolution <- as.numeric(input$selected_res)

    rv$live_selected_config$resolutions[[s_name]] <- selected_resolution

    # Update Global copy for utils and save to disk
    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)

    resolution_changed <- !is.null(previous_resolution) &&
      length(previous_resolution) == 1L && !is.na(previous_resolution) &&
      previous_resolution != 0 && !isTRUE(all.equal(
        as.numeric(previous_resolution),
        selected_resolution
      ))
    state_result <- tryCatch(
      persist_pipeline_step_update(
        rv$pipeline_state,
        rv$pipeline_state_path,
        step = "resolution",
        status = "completed",
        sample = s_name,
        details = list(resolution = selected_resolution),
        invalidate_downstream = resolution_changed,
        invalidation_reason = if (resolution_changed) {
          paste0(
            "Selected resolution changed from ", previous_resolution,
            " to ", selected_resolution, "."
          )
        } else NULL
      ),
      error = identity
    )
    if (inherits(state_result, "error")) {
      record_state_event(
        rv,
        stage = "state",
        event_type = "resolution_state",
        outcome = "failed",
        sample = s_name,
        reason = conditionMessage(state_result)
      )
      showNotification(
        paste("Resolution was saved, but workflow state failed:", conditionMessage(state_result)),
        type = "error",
        duration = 10
      )
      return()
    }
    rv$pipeline_state <- state_result

    invalidated_cache <- character()
    if (resolution_changed) {
      invalidated_cache <- cache_invalidate_sample(s_name, rv$dataset_dir_path)
    }

    record_state_event(
      rv,
      stage = "resolution",
      event_type = "resolution_saved",
      outcome = "saved",
      sample = s_name,
      parameters = list(
        resolution = selected_resolution,
        previous_resolution = previous_resolution,
        changed = resolution_changed,
        invalidated_cache_files = length(invalidated_cache),
        state_revision = rv$pipeline_state$revision
      )
    )

    showNotification(paste("Resolution", input$selected_res, "saved for", s_name), type = "message")

    total_samples <- length(rv$paths_list$sample_dir_paths)
    if (idx < total_samples) {
      updateSelectInput(session, "res_sample_idx", selected = idx + 1)
    } else {
      showNotification("All samples reviewed! You can now run DE Analysis.", type = "message", duration = 8)
    }
  })

  observeEvent(input$btn_rerun_single_de, {
    req(rv$paths_list, input$res_sample_idx)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]

    current_val <- rv$live_selected_config$resolutions[[s_name]]

    if (is.null(current_val) || current_val == 0 || current_val == 0.0) {
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "single_sample_de",
        outcome = "incomplete",
        sample = s_name,
        reason = "No clustering resolution has been saved for this sample."
      )
      showNotification(paste("Cannot run DE! Please save a resolution for", s_name, "first."), type = "error")
    } else {
      readiness <- pipeline_step_readiness(
        rv$pipeline_state,
        "differential_expression",
        s_name
      )
      if (!readiness$ready) {
        record_state_event(
          rv,
          stage = "differential_expression",
          event_type = "single_sample_de",
          outcome = "incomplete",
          sample = s_name,
          reason = paste(readiness$reasons, collapse = "; ")
        )
        showNotification(
          paste("Cannot run DE:", paste(readiness$reasons, collapse = "; ")),
          type = "error",
          duration = 10
        )
        return()
      }
      showModal(modalDialog(
        title = "Confirm Single Sample DE",
        paste0("Are you sure you want to rerun the Differential Expression analysis for '", s_name, "'? This will lock the application until finished."),
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton("confirm_run_single_de", "Yes, Rerun DE", class = "btn-danger")
        )
      ))
    }
  })

  observeEvent(input$confirm_run_single_de, {
    removeModal()
    req(rv$paths_list, rv$dataset_config, rv$complete_markers)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]

    id <- showNotification(paste("Running DE analysis for", s_name, "- Check R console..."), duration = NULL, type = "warning")

    record_state_event(
      rv,
      stage = "differential_expression",
      event_type = "single_sample_de",
      outcome = "started",
      sample = s_name,
      parameters = list(resolution = rv$live_selected_config$resolutions[[s_name]])
    )

    state_started <- tryCatch(
      persist_de_state(
        s_name,
        "in_progress",
        details = list(resolution = rv$live_selected_config$resolutions[[s_name]])
      ),
      error = identity
    )
    if (inherits(state_started, "error")) {
      record_state_event(
        rv,
        stage = "state",
        event_type = "differential_expression_state",
        outcome = "failed",
        sample = s_name,
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
        sample_idx = idx,
        paths_list = rv$paths_list,
        dataset_config = rv$dataset_config,
        selected_config = rv$live_selected_config,
        complete_markers = rv$complete_markers,
        results_dir_path = rv$results_dir_path,
        dataset_dir_path = rv$dataset_dir_path
      )
      persist_de_state(
        s_name,
        "completed",
        details = list(resolution = rv$live_selected_config$resolutions[[s_name]])
      )
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "single_sample_de",
        outcome = "completed",
        sample = s_name
      )
      showNotification(paste("Differential Expression Analysis complete for", s_name, "!"), type = "message")
    }, error = function(e) {
      try(persist_de_state(s_name, "failed", reason = conditionMessage(e)), silent = TRUE)
      record_state_event(
        rv,
        stage = "differential_expression",
        event_type = "single_sample_de",
        outcome = "failed",
        sample = s_name,
        reason = conditionMessage(e)
      )
      showNotification(paste("Error running DE:", e$message), type = "error", duration = 10)
    }, finally = {
      removeNotification(id)
    })
  })
}
