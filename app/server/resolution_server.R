# Resolution selection handlers.

register_resolution_server <- function(input, output, session, state, context) {
  rv <- state

  output$res_status_badge <- renderUI({
    req(rv$paths_list, input$res_sample_idx)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]

    current_val <- rv$live_selected_config$resolutions[[s_name]]

    if (is.null(current_val) || current_val == 0 || current_val == 0.0) {
      tags$div(class = "badge bg-warning text-dark w-100 py-2 mt-2",
               style = "font-size: 14px; white-space: normal;",
               icon("exclamation-circle"), " Status: Unselected")
    } else {
      tags$div(class = "badge bg-success w-100 py-2 mt-2",
               style = "font-size: 14px; white-space: normal;",
               icon("check-circle"), paste(" Status: Saved (Res:", current_val, ")"))
    }
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

    rv$live_selected_config$resolutions[[s_name]] <- as.numeric(input$selected_res)

    # Update Global copy for utils and save to disk
    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)

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
      showNotification(paste("Cannot run DE! Please save a resolution for", s_name, "first."), type = "error")
    } else {
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
      showNotification(paste("Differential Expression Analysis complete for", s_name, "!"), type = "message")
    }, error = function(e) {
      showNotification(paste("Error running DE:", e$message), type = "error", duration = 10)
    }, finally = {
      removeNotification(id)
    })
  })
}
