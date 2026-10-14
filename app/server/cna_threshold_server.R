# CNA threshold selection handlers.

register_cna_threshold_server <- function(input, output, session, state, context) {
  rv <- state

  # --- STEP 4: Render Dynamic Threshold UI & Plots ---

  # 1. Dynamically generate the UI (Tabs + Sliders + Plot Output)
  output$cna_dynamic_thresholds_ui <- renderUI({
    req(input$cna_sample_idx, rv$paths_list, rv$live_selected_config)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]

    if (length(ward_refs) == 0) return(h5("No malignant clusters selected yet.", class = "text-danger"))

    # Check if thresholds already exist in config to pre-fill sliders
    existing_thresh <- rv$live_selected_config$cna_thresholds[[s_name]]

    # Generate a UI tab for each subclone
    tabs <- lapply(seq_along(ward_refs), function(i) {

      # Determine default slider values (prefill if saved, otherwise default)
      def_mx <- if(length(existing_thresh) >= i && !is.null(existing_thresh[[i]]$m_x)) existing_thresh[[i]]$m_x else 0.5
      def_my <- if(length(existing_thresh) >= i && !is.null(existing_thresh[[i]]$m_y)) existing_thresh[[i]]$m_y else 0.16
      def_nmx <- if(length(existing_thresh) >= i && !is.null(existing_thresh[[i]]$nm_x)) existing_thresh[[i]]$nm_x else 0.3
      def_nmy <- if(length(existing_thresh) >= i && !is.null(existing_thresh[[i]]$nm_y)) existing_thresh[[i]]$nm_y else 0.15

      nav_panel(
        title = paste("Subclone", i),
        fluidRow(
          column(8, plotOutput(paste0("cna_sig_cor_plot_", i), height = "500px")),
          column(4,
                 card(
                   card_header(paste("Set Thresholds - Subclone", i)),
                   card_body(
                     selectInput(paste0("cna_step_size_", i), "Y-Axis Precision:",
                                 choices = c("0.05" = 0.05, "0.01" = 0.01, "0.005" = 0.005, "0.001" = 0.001), selected = "0.01"),
                     sliderInput(paste0("cna_ymax_", i), "Y-Axis Max Limit:", min = 0.1, max = 3.0, value = def_ymax, step = 0.1),
                     hr(),
                     sliderInput(paste0("cna_thresh_mx_", i), "Malignant X (m_x):", min = -1, max = 1, value = 0.5, step = 0.05),
                     sliderInput(paste0("cna_thresh_my_", i), "Malignant Y (m_y):", min = 0, max = 1, value = def_my, step = 0.01),
                     sliderInput(paste0("cna_thresh_nmx_", i), "Non-Malignant X (nm_x):", min = -1, max = 1, value = def_nmx, step = 0.05),
                     sliderInput(paste0("cna_thresh_nmy_", i), "Non-Malignant Y (nm_y):", min = 0, max = 1, value = def_nmy, step = 0.01)
                   )
                 )
          )
        )
      )
    })

    # Wrap tabs and add the unified save button at the bottom
    tagList(
      do.call(navset_card_underline, tabs),
      br(),
      actionButton("btn_cna_save_thresholds", "Save All Thresholds", class = "btn-success btn-lg w-100")
    )
  })

  # 2. Dynamically render the plots for each subclone
  observe({
    req(input$cna_sample_idx, rv$paths_list, rv$live_selected_config)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]

    if (length(ward_refs) > 0) {
      lapply(seq_along(ward_refs), function(i) {
        output[[paste0("cna_sig_cor_plot_", i)]] <- renderPlot({
          # React to the dynamically generated sliders
          mx <- input[[paste0("cna_thresh_mx_", i)]]
          my <- input[[paste0("cna_thresh_my_", i)]]
          nmx <- input[[paste0("cna_thresh_nmx_", i)]]
          nmy <- input[[paste0("cna_thresh_nmy_", i)]]
          ymax <- input[[paste0("cna_ymax_", i)]] # --- NEW: Capture y_max input ---

          # Only render if sliders have initialized (added ymax check)
          req(!is.null(mx), !is.null(my), !is.null(nmx), !is.null(nmy), !is.null(ymax))

          sig_cor_file <- paste0('cna_sig_cor_', s_name, '_subclone_', i, '.qs2')
          if (!cache_check_exists(sig_cor_file, rv$dataset_dir_path)) return(NULL)

          cna_sig_cor <- cache_load_data(sig_cor_file, rv$dataset_dir_path)

          malig_thresh <- list()
          malig_thresh[[s_name]] <- list(c(m_x = mx, m_y = my, nm_x = nmx, nm_y = nmy))

          # --- NEW: Pass ymax to the plotting function ---
          p <- cna_sig_cor_plot(cna_sig_cor, s_name, malig_thresh, y_max = ymax)

          k_val <- ward_refs[[i]]$k
          c_id <- ward_refs[[i]]$cluster

          p + ggplot2::labs(
            title = paste0(s_name, " - Subclone ", i),
            subtitle = paste0("Source: k-clusters (k=", k_val, "), Cluster ID: ", c_id)
          )
        })
      })
    }
  })

  lapply(1:15, function(i) {

    # Update slider precision when dropdown changes
    observeEvent(input[[paste0("cna_step_size_", i)]], {
      req(input[[paste0("cna_step_size_", i)]])
      step_val <- as.numeric(input[[paste0("cna_step_size_", i)]])
      updateSliderInput(session, paste0("cna_thresh_my_", i), step = step_val)
      updateSliderInput(session, paste0("cna_thresh_nmy_", i), step = step_val)
    })

    # --- X-Axis Thresholds (Step size: 0.05) ---

    # As Non-Malignant X moves, push the floor of Malignant X up
    observeEvent(input[[paste0("cna_thresh_nmx_", i)]], {
      req(input[[paste0("cna_thresh_nmx_", i)]])
      updateSliderInput(session, paste0("cna_thresh_mx_", i),
                        min = input[[paste0("cna_thresh_nmx_", i)]] + 0.05)
    })

    # As Malignant X moves, push the ceiling of Non-Malignant X down
    observeEvent(input[[paste0("cna_thresh_mx_", i)]], {
      req(input[[paste0("cna_thresh_mx_", i)]])
      updateSliderInput(session, paste0("cna_thresh_nmx_", i),
                        max = input[[paste0("cna_thresh_mx_", i)]] - 0.05)
    })

    # --- Y-Axis Thresholds ---

    # As Non-Malignant Y moves, push the floor of Malignant Y up
    observeEvent(input[[paste0("cna_thresh_nmy_", i)]], {
      req(input[[paste0("cna_thresh_nmy_", i)]], input[[paste0("cna_step_size_", i)]])
      step_val <- as.numeric(input[[paste0("cna_step_size_", i)]])
      updateSliderInput(session, paste0("cna_thresh_my_", i),
                        min = input[[paste0("cna_thresh_nmy_", i)]] + step_val)
    })

    # As Malignant Y moves, push the ceiling of Non-Malignant Y down
    observeEvent(input[[paste0("cna_thresh_my_", i)]], {
      req(input[[paste0("cna_thresh_my_", i)]], input[[paste0("cna_step_size_", i)]])
      step_val <- as.numeric(input[[paste0("cna_step_size_", i)]])
      updateSliderInput(session, paste0("cna_thresh_nmy_", i),
                        max = input[[paste0("cna_thresh_my_", i)]] - step_val)
    })
  })

  # 3. Save all dynamic thresholds to config AND save plots
  observeEvent(input$btn_cna_save_thresholds, {
    req(input$cna_sample_idx, rv$paths_list)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
    n_subclones <- length(ward_refs)

    thresh_list <- list()
    has_error <- FALSE

    for (i in seq_len(n_subclones)) {
      m_x <- input[[paste0("cna_thresh_mx_", i)]]
      m_y <- input[[paste0("cna_thresh_my_", i)]]
      nm_x <- input[[paste0("cna_thresh_nmx_", i)]]
      nm_y <- input[[paste0("cna_thresh_nmy_", i)]]

      # Safety Check
      if (is.null(m_x) || m_x < nm_x || m_y < nm_y) {
        showNotification(paste("Error in Subclone", i, ": Malignant thresholds (m_x, m_y) must be >= Non-Malignant thresholds (nm_x, nm_y)."),
                         type = "error", duration = 8)
        has_error <- TRUE
      }

      y_max <- input[[paste0("cna_ymax_", i)]]
      thresh_list[[i]] <- list(m_x = m_x, m_y = m_y, nm_x = nm_x, nm_y = nm_y, y_max = y_max)
    }

    if (has_error) return()

    id <- showNotification("Saving thresholds and plots to disk...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    # --- 1. Save Config ---
    rv$live_selected_config$cna_thresholds[[s_name]] <- thresh_list
    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)

    # --- 2. Save Plots ---
    cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
    dir.create(cna_plots_dir_path, showWarnings = FALSE, recursive = TRUE)

    for (i in seq_len(n_subclones)) {
      sig_cor_file <- paste0('cna_sig_cor_', s_name, '_subclone_', i, '.qs2')
      if (cache_check_exists(sig_cor_file, rv$dataset_dir_path)) {
        cna_sig_cor <- cache_load_data(sig_cor_file, rv$dataset_dir_path)

        malig_thresh <- list()
        malig_thresh[[s_name]] <- list(thresh_list[[i]])

        # Generate the plot exactly as it looks in the UI
        p_unscaled <- cna_sig_cor_plot(cna_sig_cor, s_name, malig_thresh, y_max = NULL)
        p_scaled <- cna_sig_cor_plot(cna_sig_cor, s_name, malig_thresh, y_max = y_max)

        k_val <- ward_refs[[i]]$k
        c_id <- ward_refs[[i]]$cluster

        p_unscaled <- p_unscaled + ggplot2::labs(
          title = paste0(s_name, " - Subclone ", i),
          subtitle = paste0("Source: k-clusters (k=", k_val, "), Cluster ID: ", c_id, " | Threshold Selection | Unscaled")
        )

        p_scaled <- p_scaled + ggplot2::labs(
          title = paste0(s_name, " - Subclone ", i),
          subtitle = paste0("Source: k-clusters (k=", k_val, "), Cluster ID: ", c_id, " | Threshold Selection | Scaled to ", y_max)
        )

        plot_unscaled_title <- paste0('cna_threshold_unscaled_selection_subclone_', i, '_', s_name, '.png')
        plot_unscaled_path <- file.path(cna_plots_dir_path, plot_unscaled_title)
        ggplot2::ggsave(plot_unscaled_path, plot = p_unscaled, width = 7, height = 5, bg = 'white')

        plot_scaled_title <- paste0('cna_threshold_scaled_selection_subclone_', i, '_', s_name, '.png')
        plot_scaled_path <- file.path(cna_plots_dir_path, plot_scaled_title)
        ggplot2::ggsave(plot_scaled_path, plot = p_scaled, width = 7, height = 5, bg = 'white')

      }
    }

    showNotification("All thresholds and plots saved successfully!", type = "message")

    # Enable the final step and switch view
    shinyjs::enable("btn_cna_go_summary")
    nav_select("cna_main_views", "cna_view_summary")
  })
}
