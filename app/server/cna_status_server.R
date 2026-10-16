# CNA sample status and navigation handlers.

register_cna_status_server <- function(input, output, session, state, context) {
  rv <- state

  preflight_value <- function(value) {
    if (is.null(value) || length(value) == 0L || is.na(value)) "—" else value
  }

  output$cna_eligibility_ui <- renderUI({
    req(
      rv$paths_list,
      input$cna_sample_idx,
      rv$live_selected_config,
      rv$pipeline_state
    )
    idx <- as.numeric(input$cna_sample_idx)
    sample_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    result <- cna_sample_preflight(
      sample_name,
      rv$live_selected_config,
      rv$dataset_dir_path,
      gene_positions = context$resources$gene_positions,
      pipeline_state = rv$pipeline_state,
      validate_expression = FALSE
    )
    status_view <- switch(
      result$status,
      eligible = list(class = "success", label = "Eligible for CNA"),
      incomplete = list(class = "warning", label = "CNA setup incomplete"),
      ineligible = list(class = "secondary", label = "Not eligible for CNA"),
      invalid = list(class = "danger", label = "CNA inputs invalid"),
      omitted = list(class = "info", label = "CNA intentionally omitted")
    )
    reason_items <- if (length(result$reasons) == 0L) {
      tags$p("All preflight checks passed.", class = "mb-2")
    } else {
      tags$ul(
        class = "text-start mb-2",
        lapply(result$reasons, tags$li)
      )
    }
    tags$div(
      class = paste("alert", paste0("alert-", status_view$class), "text-start"),
      tags$strong(status_view$label),
      reason_items,
      tags$div(
        class = "row g-2 text-center",
        tags$div(
          class = "col-4",
          tags$div(class = "border rounded p-2", tags$strong(preflight_value(result$counts$reference)), tags$br(), "Reference")
        ),
        tags$div(
          class = "col-4",
          tags$div(class = "border rounded p-2", tags$strong(preflight_value(result$counts$configured_candidate)), tags$br(), "Potentially malignant")
        ),
        tags$div(
          class = "col-4",
          tags$div(class = "border rounded p-2", tags$strong(preflight_value(result$counts$unassigned)), tags$br(), "Unassigned / NA")
        )
      )
    )
  })

  observe({
    req(rv$paths_list, input$cna_sample_idx, rv$live_selected_config)
    idx <- as.numeric(input$cna_sample_idx)
    sample_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    note <- rv$live_selected_config$sample_notes[[sample_name]]
    updateTextAreaInput(
      session,
      "cna_sample_notes",
      value = if (is.null(note)) "" else note
    )
  })

  observeEvent(input$btn_save_cna_notes, {
    req(rv$paths_list, input$cna_sample_idx, rv$live_selected_config)
    idx <- as.numeric(input$cna_sample_idx)
    sample_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    rv$live_selected_config <- save_sample_note(
      rv$live_selected_config,
      rv$selected_config_path,
      sample_name,
      input$cna_sample_notes
    )
    rv$config$selected <- rv$live_selected_config
    record_state_event(
      rv,
      stage = "notes",
      event_type = "sample_note_saved",
      outcome = "saved",
      sample = sample_name,
      parameters = list(source = "cna")
    )
    showNotification(paste("Notes saved for", sample_name), type = "message")
  })

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

  # Render persisted workflow state and enable only completed prerequisites.
  observe({
    req(
      rv$paths_list,
      input$cna_sample_idx,
      rv$pipeline_state,
      rv$live_selected_config
    )
    idx <- as.numeric(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]

    # 0. Start by disabling steps 2 through 5 and resetting the view
    nav_select("cna_main_views", "cna_view_default")
    shinyjs::disable("btn_cna_compute_heatmaps")
    shinyjs::disable("btn_cna_go_malig_clust")
    shinyjs::disable("btn_cna_compute_sig_cor")
    shinyjs::disable("btn_cna_go_thresholds")
    shinyjs::disable("btn_cna_go_summary")

    shinyjs::disable("btn_cna_save_summary")
    rv$cna_preview_res <- NULL
    output$cna_preview_scatter_ui <- renderUI({ NULL })
    output$cna_preview_umap <- renderPlot({ NULL })
    output$cna_preview_heatmap <- renderPlot({ NULL })

    preflight <- cna_sample_preflight(
      s_name,
      rv$live_selected_config,
      rv$dataset_dir_path,
      gene_positions = context$resources$gene_positions,
      pipeline_state = rv$pipeline_state,
      validate_expression = FALSE
    )
    if (isTRUE(preflight$eligible)) {
      shinyjs::enable("btn_cna_compute_heatmaps")
    }

    step_records <- lapply(
      c(
        "cna_compute",
        "cna_cluster_selection",
        "cna_signal_correlation",
        "cna_thresholds",
        "cna_assignment"
      ),
      function(step) get_pipeline_step(rv$pipeline_state, step, s_name)
    )
    names(step_records) <- c(
      "cna_compute",
      "cna_cluster_selection",
      "cna_signal_correlation",
      "cna_thresholds",
      "cna_assignment"
    )

    status_item <- function(number, label, record) {
      view <- pipeline_status_presentation(record)
      reason <- if (is.null(view$reason)) "" else paste0(
        "<div class='small'>",
        htmltools::htmlEscape(view$reason),
        "</div>"
      )
      paste0(
        "<li class='list-group-item list-group-item-", view$class, "'>",
        number, ". ", label, ": ", view$label, reason, "</li>"
      )
    }

    status_html <- c("<strong>Pipeline Status:</strong><ul class='list-group mt-2 text-start'>")

    step1_done <- identical(step_records$cna_compute$status, "completed")
    if (step1_done) {
      shinyjs::enable("btn_cna_go_malig_clust")
    }
    status_html <- c(status_html, status_item(1, "Base CNA & Heatmaps", step_records$cna_compute))

    ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
    step2_done <- step1_done && identical(
      step_records$cna_cluster_selection$status,
      "completed"
    )

    if (step2_done) {
      shinyjs::enable("btn_cna_compute_sig_cor")

      saved_k <- ward_refs[[1]]$k
      saved_clusters <- sapply(ward_refs, function(x) as.character(x$cluster))

      updateSliderInput(session, "cna_k_clusters", value = saved_k)
      updateSelectizeInput(session, "cna_selected_clusters",
                           choices = as.character(1:saved_k),
                           selected = saved_clusters)

    } else {
      updateSelectizeInput(session, "cna_selected_clusters", selected = character(0))
    }
    status_html <- c(
      status_html,
      status_item(2, "Cluster Selection", step_records$cna_cluster_selection)
    )

    step3_done <- step2_done && identical(
      step_records$cna_signal_correlation$status,
      "completed"
    )

    if (step3_done) {
      shinyjs::enable("btn_cna_go_thresholds")
    }
    status_html <- c(
      status_html,
      status_item(3, "Signal & Correlation", step_records$cna_signal_correlation)
    )

    step4_done <- step3_done && identical(step_records$cna_thresholds$status, "completed")

    if (step4_done) {
      shinyjs::enable("btn_cna_go_summary")
    }
    status_html <- c(
      status_html,
      status_item(4, "Malignant Thresholds", step_records$cna_thresholds),
      status_item(5, "Final Assignment", step_records$cna_assignment)
    )

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
