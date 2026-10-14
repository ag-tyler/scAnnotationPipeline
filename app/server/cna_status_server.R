# CNA sample status and navigation handlers.

register_cna_status_server <- function(input, output, session, state, context) {
  rv <- state

  # Populate Sample Dropdown when Dataset Loads
  observe({
    req(rv$paths_list)
    s_choices <- setNames(
      seq_along(rv$paths_list$sample_dir_paths),
      basename(rv$paths_list$sample_dir_paths)
    )
    updateSelectInput(session, "cna_sample_idx", choices = s_choices)
  })

  # Basic Navigation between main views
  observeEvent(input$btn_cna_back_menu, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_cna_go_malig_clust, { nav_select("cna_main_views", "cna_view_select_malignant") })
  observeEvent(input$btn_cna_go_thresholds, { nav_select("cna_main_views", "cna_view_thresholds") })
  observeEvent(input$btn_cna_go_summary, { nav_select("cna_main_views", "cna_view_summary") })

  output$cna_header_text <- renderText({
    req(rv$paths_list, input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    paste("CNA Analysis:", s_name)
  })

  # Monitor cache and config to enable/disable pipeline buttons
  observeEvent(input$cna_sample_idx, {
    req(rv$paths_list, input$cna_sample_idx)
    idx <- as.numeric(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]

    # 0. Start by disabling steps 2 through 5 and resetting the view
    nav_select("cna_main_views", "cna_view_default")
    shinyjs::disable("btn_cna_go_malig_clust")
    shinyjs::disable("btn_cna_compute_sig_cor")
    shinyjs::disable("btn_cna_go_thresholds")
    shinyjs::disable("btn_cna_go_summary")

    shinyjs::disable("btn_cna_save_summary")
    rv$cna_preview_res <- NULL
    output$cna_preview_scatter_ui <- renderUI({ NULL })
    output$cna_preview_umap <- renderPlot({ NULL })
    output$cna_preview_heatmap <- renderPlot({ NULL })

    # We will build an HTML status string to show the user what is done
    status_html <- c("<strong>Pipeline Status:</strong><ul class='list-group mt-2 text-start'>")

    # 1. Check if CNA and Heatmaps are computed (Step 1)
    # We look for the hclust cache file as an indicator
    hclust_file <- paste0('hclust_', s_name, '.qs2')
    step1_done <- cache_check_exists(hclust_file, rv$dataset_dir_path)

    if (step1_done) {
      shinyjs::enable("btn_cna_go_malig_clust")
      status_html <- c(status_html, "<li class='list-group-item list-group-item-success'>1. Base CNA & Heatmaps: Complete</li>")
    } else {
      status_html <- c(status_html, "<li class='list-group-item list-group-item-warning'>1. Base CNA & Heatmaps: Pending</li>")
    }

    # 2. Check if Malignant Clusters are selected (Step 2)
    ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
    step2_done <- step1_done && !is.null(ward_refs) && length(ward_refs) > 0

    if (step2_done) {
      shinyjs::enable("btn_cna_compute_sig_cor")

      saved_k <- ward_refs[[1]]$k
      saved_clusters <- sapply(ward_refs, function(x) as.character(x$cluster))

      updateSliderInput(session, "cna_k_clusters", value = saved_k)
      updateSelectizeInput(session, "cna_selected_clusters",
                           choices = as.character(1:saved_k),
                           selected = saved_clusters)

      status_html <- c(status_html, "<li class='list-group-item list-group-item-success'>2. Cluster Selection: Complete</li>")
    } else {
      updateSelectizeInput(session, "cna_selected_clusters", selected = character(0))
      status_html <- c(status_html, "<li class='list-group-item list-group-item-warning'>2. Cluster Selection: Pending</li>")
    }

    # 3. Check if Signal & Cor are computed (Step 3)
    # Check if subclone 1 exists as a baseline
    sig_cor_file <- paste0('cna_sig_cor_', s_name, '_subclone_1.qs2')
    step3_done <- step2_done && cache_check_exists(sig_cor_file, rv$dataset_dir_path)

    if (step3_done) {
      shinyjs::enable("btn_cna_go_thresholds")
      status_html <- c(status_html, "<li class='list-group-item list-group-item-success'>3. Signal & Correlation: Complete</li>")
    } else {
      status_html <- c(status_html, "<li class='list-group-item list-group-item-warning'>3. Signal & Correlation: Pending</li>")
    }

    # 4. Check if Thresholds are saved (Step 4)
    thresholds <- rv$live_selected_config$cna_thresholds[[s_name]]
    step4_done <- step3_done && !is.null(thresholds) && length(thresholds) > 0

    if (step4_done) {
      shinyjs::enable("btn_cna_go_summary")


      status_html <- c(status_html, "<li class='list-group-item list-group-item-success'>4. Malignant Thresholds: Saved</li>")
    } else {
      status_html <- c(status_html, "<li class='list-group-item list-group-item-warning'>4. Malignant Thresholds: Pending</li>")
    }
    # Step 4 (Thresholds) and 5 (Summary) state logic can be expanded here once we define where
    # the thresholds are stored (e.g., config file or another qs2 object).

    status_html <- c(status_html, "</ul>")

    output$cna_status_ui <- renderUI({
      HTML(paste(status_html, collapse = ""))
    })
  })

  # Next Sample Button Logic for CNA
  observeEvent(input$btn_cna_next, {
    req(rv$paths_list, input$cna_sample_idx)
    idx <- as.numeric(input$cna_sample_idx)
    total_samples <- length(rv$paths_list$sample_dir_paths)

    if (idx < total_samples) {
      updateSelectInput(session, "cna_sample_idx", selected = idx + 1)
    } else {
      showNotification("This is the last sample in the dataset.", type = "message")
    }
  })
}
