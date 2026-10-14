# Dashboard navigation and pipeline trigger handlers.

register_dashboard_server <- function(input, output, session, state, context) {
  rv <- state

  observeEvent(input$btn_go_res, { updateNavbarPage(session, "main_nav", selected = "res_tab") })
  observeEvent(input$btn_go_anno, { updateNavbarPage(session, "main_nav", selected = "anno_tab") })
  observeEvent(input$btn_back_menu_1, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_back_menu_2, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_copy_info, { updateNavbarPage(session, "main_nav", selected = "clipboard_tab") })
  observeEvent(input$btn_back_menu_3, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_go_cna, { updateNavbarPage(session, "main_nav", selected = "cna_tab") })

  observeEvent(input$btn_select_all, {
    runjs("document.getElementById('prompt_text_area').select();")
  })

  observeEvent(input$btn_run_clustering, {
    req(rv$paths_list)
    showModal(modalDialog(
      title = "Confirm Clustering",
      "Are you sure you want to run the clustering pipeline? This process takes a significant amount of time and will lock the application until finished.",
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_run_clustering", "Yes, Run Clustering", class = "btn-danger")
      )
    ))
  })

  observeEvent(input$confirm_run_clustering, {
    removeModal()
    id <- showNotification("Running clustering pipeline. This may take a while. Check R console...",
                           duration = NULL, type = "warning")
    cluster_all_samples(rv$paths_list, rv$dataset_config, rv$results_dir_path, rv$dataset_dir_path)
    removeNotification(id)
    showNotification("Clustering complete!", type = "message")
  })

  observeEvent(input$btn_run_de, {
    req(rv$paths_list)
    expected_samples <- basename(rv$paths_list$sample_dir_paths)

    unpicked_samples <- expected_samples[sapply(expected_samples, function(s) {
      res <- rv$live_selected_config$resolutions[[s]]
      is.null(res) || res == 0 || res == 0.0
    })]

    if (length(unpicked_samples) > 0) {
      msg <- paste("Cannot run DE! Missing resolutions for:", paste(unpicked_samples, collapse = ", "))
      showNotification(msg, type = "error", duration = 10)
    } else {
      showModal(modalDialog(
        title = "Confirm DE Analysis",
        "Are you sure you want to run the Differential Expression analysis? This process is computationally heavy and will lock the application.",
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton("confirm_run_de", "Yes, Run DE Analysis", class = "btn-danger")
        )
      ))
    }
  })

  observeEvent(input$confirm_run_de, {
    removeModal()
    id <- showNotification("Running DE analysis. Check R console...", duration = NULL, type = "warning")
    de_analysis(rv$paths_list, rv$dataset_config, rv$live_selected_config, rv$complete_markers,
                rv$results_dir_path, rv$dataset_dir_path)
    removeNotification(id)
    showNotification("Differential Expression Analysis complete!", type = "message")
  })
}
