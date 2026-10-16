# Manual annotation handlers.

register_annotation_server <- function(input, output, session, state, context) {
  rv <- state

  persist_annotation_step <- function(
    step,
    status,
    reason = NULL,
    details = NULL,
    invalidate_downstream = FALSE,
    invalidation_reason = NULL
  ) {
    current <- get_pipeline_step(rv$pipeline_state, step, rv$sample_name)
    if (
      status == "incomplete" &&
        current$status %in% c("completed", "skipped")
    ) {
      rv$pipeline_state <- persist_pipeline_step_update(
        rv$pipeline_state,
        rv$pipeline_state_path,
        step = step,
        status = "in_progress",
        sample = rv$sample_name,
        invalidate_downstream = invalidate_downstream,
        invalidation_reason = invalidation_reason
      )
      invalidate_downstream <- FALSE
      invalidation_reason <- NULL
    }
    rv$pipeline_state <- persist_pipeline_step_update(
      rv$pipeline_state,
      rv$pipeline_state_path,
      step = step,
      status = status,
      sample = rv$sample_name,
      reason = reason,
      details = details,
      invalidate_downstream = invalidate_downstream,
      invalidation_reason = invalidation_reason
    )
    invisible(rv$pipeline_state)
  }

  status_badge <- function(step, label) {
    view <- pipeline_status_presentation(
      get_pipeline_step(rv$pipeline_state, step, rv$sample_name),
      label
    )
    tags$div(
      class = paste("badge w-100 py-2 mt-1", paste0("bg-", view$class)),
      style = "font-size: 14px; white-space: normal;",
      icon(view$icon),
      paste0(" ", view$label),
      if (!is.null(view$reason)) tags$div(class = "fw-normal mt-1", view$reason)
    )
  }

  observeEvent(input$btn_anno_next, {
    req(rv$paths_list, input$sample_idx)
    idx <- as.numeric(input$sample_idx)
    total_samples <- length(rv$paths_list$sample_dir_paths)
    if (idx < total_samples) {
      updateSelectInput(session, "sample_idx", selected = idx + 1)
    } else {
      showNotification("This is the last sample in the dataset.", type = "message")
    }
  })

  observeEvent(input$btn_cluster_next, {
    req(rv$cells_filt, input$cluster)

    clusters <- unique(as.character(rv$cells_filt$clust))
    clusters <- clusters[order(as.numeric(clusters))]

    curr_idx <- which(clusters == input$cluster)
    if (length(curr_idx) > 0 && curr_idx < length(clusters)) {
      next_cluster <- clusters[curr_idx + 1]
      updateSelectInput(session, "cluster", selected = next_cluster)
    } else {
      showNotification("This is the last cluster for this sample.", type = "message")
    }
  })

  output$anno_status_badge <- renderUI({
    req(rv$sample_name, rv$pipeline_state)
    tagList(
      status_badge("annotation", "Annotation"),
      status_badge("cna_configuration", "CNA configuration")
    )
  })

  output$ref_cell_selector <- renderUI({
    req(rv$cells_filt, rv$sample_name, rv$samples_config)

    current_types <- unique(rv$cells_filt$cell_type)
    current_types <- current_types[!is.na(current_types) & current_types != "NA"]
    current_types <- gsub("\\s*\\(.*\\)", "", current_types)
    current_types <- unique(current_types)

    samples_list <- rv$samples_config$samples
    matching_sample <- Filter(
      function(x) identical(x$sample, rv$sample_name),
      samples_list
    )

    cancer_type <- "Unknown"
    if (length(matching_sample) > 0) {
      cancer_type <- matching_sample[[1]]$cancer_type
    }

    tagList(
      tags$div(
        style = "margin-bottom: 10px; padding: 5px; background-color: #f8f9fa; border-radius: 4px; border: 1px solid #dee2e6;",
        tags$span("Cancer Type: ", style = "font-weight: bold; color: #6c757d;"),
        tags$span(cancer_type, style = "font-weight: bold; color: #2c3e50;")
      ),
      selectizeInput("cna_refs_input", "Select Ref Cell Types:",
                     choices = current_types,
                     selected = rv$live_selected_config$cna_ref_cells[[rv$sample_name]],
                     multiple = TRUE,
                     options = list(placeholder = 'Select annotated types...'))
    )
  })

  output$pot_mal_cell_selector <- renderUI({
    req(rv$cells_filt, rv$sample_name, rv$complete_markers)

    # 1. Grab currently annotated cell types
    current_types <- unique(rv$cells_filt$cell_type)
    current_types <- current_types[!is.na(current_types) & current_types != "NA"]

    # 2. Grab standard marker cell types
    marker_types <- unique(rv$complete_markers$cell_type)

    # 3. Combine and clean
    all_choices <- unique(c(current_types, marker_types))
    all_choices <- gsub("\\s*\\(.*\\)", "", all_choices)
    all_choices <- unique(all_choices)

    selectizeInput("cna_pot_mal_input", "Select Potentially Malig. Types:",
                   choices = all_choices,
                   selected = rv$live_selected_config$cna_pot_mal_cells[[rv$sample_name]],
                   multiple = TRUE,
                   options = list(create = TRUE, placeholder = 'Select or type new...'))
  })

  observeEvent(input$btn_save_refs, {
    req(rv$sample_name)

    readiness <- pipeline_step_readiness(
      rv$pipeline_state,
      "cna_configuration",
      rv$sample_name
    )
    if (!readiness$ready) {
      showNotification(
        paste("Cannot save CNA configuration:", paste(readiness$reasons, collapse = "; ")),
        type = "error",
        duration = 10
      )
      return()
    }

    selected_refs <- input$cna_refs_input
    if (is.null(selected_refs)) selected_refs <- list()

    selected_pot_mal <- input$cna_pot_mal_input
    if (is.null(selected_pot_mal)) selected_pot_mal <- list()

    previous_refs <- rv$live_selected_config$cna_ref_cells[[rv$sample_name]]
    previous_pot_mal <- rv$live_selected_config$cna_pot_mal_cells[[rv$sample_name]]
    configuration_changed <- !identical(
      sort(as.character(previous_refs)),
      sort(as.character(selected_refs))
    ) || !identical(
      sort(as.character(previous_pot_mal)),
      sort(as.character(selected_pot_mal))
    )

    rv$live_selected_config$cna_ref_cells[[rv$sample_name]] <- selected_refs
    rv$live_selected_config$cna_pot_mal_cells[[rv$sample_name]] <- selected_pot_mal

    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)

    config_complete <- length(selected_refs) > 0L && length(selected_pot_mal) > 0L
    state_result <- tryCatch({
      persist_annotation_step(
        "cna_configuration",
        if (config_complete) "completed" else "incomplete",
        reason = if (!config_complete) {
          "Both reference and potentially malignant cell types must be selected."
        } else NULL,
        details = list(
          reference_cell_types = unname(selected_refs),
          potentially_malignant_cell_types = unname(selected_pot_mal)
        ),
        invalidate_downstream = configuration_changed,
        invalidation_reason = if (configuration_changed) {
          "The CNA reference or potentially malignant cell-type configuration changed."
        } else NULL
      )
    }, error = identity)
    if (inherits(state_result, "error")) {
      record_state_event(
        rv,
        stage = "state",
        event_type = "cna_configuration_state",
        outcome = "failed",
        sample = rv$sample_name,
        reason = conditionMessage(state_result)
      )
      showNotification(
        paste("Configuration was saved, but workflow state failed:", conditionMessage(state_result)),
        type = "error",
        duration = 10
      )
      return()
    }

    invalidated_cache <- character()
    if (configuration_changed) {
      invalidated_cache <- cache_invalidate_sample(rv$sample_name, rv$dataset_dir_path)
    }

    record_state_event(
      rv,
      stage = "cna_configuration",
      event_type = "cna_configuration_saved",
      outcome = "saved",
      sample = rv$sample_name,
      parameters = list(
        reference_cell_types = unname(selected_refs),
        potentially_malignant_cell_types = unname(selected_pot_mal),
        invalidated_cache_files = length(invalidated_cache)
      )
    )

    showNotification(paste("CNA Configuration saved for", rv$sample_name), type = "message")
  })

  observeEvent(input$sample_idx, {
    req(rv$paths_list, input$sample_idx)
    idx <- as.numeric(input$sample_idx)

    cells_file <- rv$paths_list$cell_file_paths[idx]
    if (!file.exists(cells_file)) return()

    id <- showNotification("Loading annotation data...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    rv$final_plot <- NULL
    rv$cells_raw <- load_cells(cells_file)
    rv$sample_name <- unique(rv$cells_raw$sample)
    rv$res <- rv$live_selected_config$resolutions[[rv$sample_name]]

    readiness <- pipeline_step_readiness(rv$pipeline_state, "annotation", rv$sample_name)
    if (!readiness$ready) {
      rv$cells_filt <- NULL
      rv$all_matches <- NULL
      return()
    }

    tryCatch({
      results_list <- cell_type_annotation_setup(idx, rv$paths_list, rv$results_dir_path,
                                                 rv$config, rv$dataset_dir_path, rv$complete_markers,
                                                 dataset_config = rv$dataset_config,
                                                 selected_config = rv$live_selected_config)
      rv$cells_filt <- results_list$cells_filt
      rv$all_matches <- results_list$all_matches

      if ("cell_type" %in% names(rv$cells_raw)) {
        rv$cells_filt[rv$cells_raw, on = 'cell_name', cell_type := i.cell_type]
      } else if (!"cell_type" %in% names(rv$cells_filt)) {
        rv$cells_filt[, cell_type := NA_character_]
      }
    }, error = function(e) {
      message("Error loading annotation setup: ", e$message)
      record_state_event(
        rv,
        stage = "annotation",
        event_type = "annotation_load",
        outcome = "failed",
        sample = rv$sample_name,
        reason = conditionMessage(e)
      )
      showNotification("Could not load DE data. Did you run the DE Analysis step?", type = "error")
    })
  })

  output$cluster_selector <- renderUI({
    req(rv$cells_filt)
    clusters <- unique(as.character(rv$cells_filt$clust))
    clusters <- clusters[order(as.numeric(clusters))]
    selectInput("cluster", "2. Select Cluster:", choices = clusters)
  })

  # Render dynamically based on selected dataset marker filters
  output$cell_type_input_ui <- renderUI({
    req(rv$complete_markers)
    selectizeInput("cell_type_input", "Cell Type:",
                   choices = c("NA", unique(rv$complete_markers$cell_type)),
                   options = list(create = TRUE, placeholder = 'Select or type new...'))
  })

  output$current_cluster_annotation <- renderUI({
    req(rv$cells_filt, input$cluster)
    curr_anno <- unique(rv$cells_filt[clust == input$cluster]$cell_type)
    curr_anno <- curr_anno[!is.na(curr_anno) & curr_anno != "NA"]

    if (length(curr_anno) == 0) {
      tags$div(class = "text-muted mt-1 mb-2", style = "font-size: 14px;",
               icon("circle-info"), " Current: ", tags$em("Unassigned"))
    } else {
      tags$div(class = "text-primary fw-bold mt-1 mb-2", style = "font-size: 14px;",
               icon("tag"), paste(" Current:", paste(curr_anno, collapse = ", ")))
    }
  })

  output$umap_ref_plot <- renderImage({
    req(rv$sample_name, rv$res, rv$results_dir_path)
    plot_name <- paste0('clusters_plot_', rv$sample_name, '_res_', rv$res, '.png')
    plot_path <- file.path(rv$results_dir_path, rv$sample_name, '1_cluster_plots', plot_name)
    if(!file.exists(plot_path)) return(list(src=""))
    list(src = plot_path, width = "100%", height = "auto", alt = "Pre-computed UMAP")
  }, deleteFile = FALSE)

  output$cluster_boxplot <- renderImage({
    req(rv$sample_name, input$cluster, rv$results_dir_path)
    plot_path <- file.path(rv$results_dir_path, rv$sample_name, '2_de_plots', paste0(input$cluster, '.png'))
    if(!file.exists(plot_path)) return(list(src=""))
    list(src = plot_path, width = "100%", height = "auto", alt = "Cluster Boxplot")
  }, deleteFile = FALSE)

  output$marker_table <- DT::renderDT({
    req(rv$all_matches, input$cluster)
    dt_subset <- rv$all_matches[clust == input$cluster]

    col_name <- ifelse("symbol" %in% names(dt_subset), "symbol", "gene")
    target_col_idx <- which(names(dt_subset) == col_name) - 1

    DT::datatable(dt_subset,
                  extensions = 'Buttons',
                  class = 'cell-border stripe hover',
                  options = list(
                    pageLength = 50,
                    scrollX = TRUE,
                    dom = 'Bplfrtip',
                    buttons = list(
                      list(
                        extend = 'copy',
                        text = '<i class="fa fa-clipboard"></i> Copy Genes',
                        title = "",
                        header = FALSE,
                        exportOptions = list(
                          modifier = list(page = "all"),
                          columns = target_col_idx
                        )
                      )
                    )
                  ),
                  rownames = FALSE,
                  escape = FALSE)

  }, server = FALSE)

  observeEvent(input$assign_btn, {
    req(rv$cells_filt, input$cluster, input$cell_type_input)
    curr_annotation <- ifelse(input$cell_type_input == "NA", NA_character_, input$cell_type_input)

    tmp <- data.table::copy(rv$cells_filt)
    tmp[clust == input$cluster, cell_type := curr_annotation]
    rv$cells_filt <- tmp

    record_state_event(
      rv,
      stage = "annotation",
      event_type = "annotation_changed",
      outcome = "changed",
      sample = rv$sample_name,
      parameters = list(
        cluster = as.character(input$cluster),
        cell_type = curr_annotation,
        affected_cells = sum(tmp$clust == input$cluster)
      )
    )

    showNotification(paste0("Assigned '", curr_annotation, "' to cluster ", input$cluster), type = "message")

    clusters <- unique(as.character(rv$cells_filt$clust))
    clusters <- clusters[order(as.numeric(clusters))]

    curr_idx <- which(clusters == input$cluster)

    if (length(curr_idx) > 0 && curr_idx < length(clusters)) {
      next_cluster <- clusters[curr_idx + 1]
      updateSelectInput(session, "cluster", selected = next_cluster)
    } else {
      showNotification("All clusters annotated! You can now preview and save.", type = "message", duration = 5)
    }
  })

  observeEvent(input$preview_btn, {
    req(rv$cells_filt, rv$sample_name, rv$res)
    id <- showNotification("Generating preview plot...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    plot_title <- paste0('Cell types of sample: ', rv$sample_name, '; res=', rv$res)
    rv$final_plot <- plot_clusters(rv$cells_filt, plot_title, x_col = umap1, y_col = umap2, cluster_col = cell_type)
    output$final_umap_plot <- renderPlot({ rv$final_plot })
  })

  observeEvent(input$save_btn, {
    req(rv$paths_list, rv$cells_filt, rv$cells_raw, rv$sample_name, rv$res, rv$results_dir_path)
    readiness <- pipeline_step_readiness(rv$pipeline_state, "annotation", rv$sample_name)
    if (!readiness$ready) {
      showNotification(
        paste("Cannot save annotations:", paste(readiness$reasons, collapse = "; ")),
        type = "error",
        duration = 10
      )
      return()
    }
    id <- showNotification("Saving annotations and plot to disk...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    idx <- as.numeric(input$sample_idx)
    de_plots_dir_path <- file.path(rv$results_dir_path, rv$sample_name, '2_de_plots')

    if (!is.null(rv$final_plot)) {
      clust_plot_path <- file.path(de_plots_dir_path, 'cell_types.png')
      ggplot2::ggsave(clust_plot_path, plot = rv$final_plot, width = 8, height = 6)
    }

    # --- NEW FIX: Force memory reallocation with copy() ---
    cells_to_save <- data.table::copy(rv$cells_filt)
    cells_to_save[, cell_type_pre_cna := cell_type]

    old_annotations <- as.character(
      rv$cells_raw$cell_type[match(cells_to_save$cell_name, rv$cells_raw$cell_name)]
    )
    new_annotations <- as.character(cells_to_save$cell_type)
    annotations_changed <- !identical(old_annotations, new_annotations)

    # 1. Save to raw Cells.csv (Using the safe, copied object)
    rv$cells_raw[cells_to_save, on = 'cell_name', cell_type := i.cell_type]
    rv$cells_raw[cells_to_save, on = 'cell_name', cell_type_pre_cna := i.cell_type_pre_cna]
    data.table::fwrite(rv$cells_raw, file = rv$paths_list$cell_file_paths[idx])

    # 2. Sync with the cache
    cells_file <- paste0('cells_filt_clust_res_', rv$res, '_', rv$sample_name, '.qs2')
    cache_save_data(cells_to_save, cells_file, rv$dataset_dir_path)

    # Update the active session memory so it doesn't complain later
    rv$cells_filt <- cells_to_save

    state_result <- tryCatch(
      persist_annotation_step(
        "annotation",
        "completed",
        details = list(
          resolution = rv$res,
          cell_count = nrow(cells_to_save),
          assigned_count = sum(!is.na(cells_to_save$cell_type))
        ),
        invalidate_downstream = annotations_changed,
        invalidation_reason = if (annotations_changed) {
          "Saved cell annotations changed."
        } else NULL
      ),
      error = identity
    )
    if (inherits(state_result, "error")) {
      record_state_event(
        rv,
        stage = "state",
        event_type = "annotation_state",
        outcome = "failed",
        sample = rv$sample_name,
        reason = conditionMessage(state_result)
      )
      showNotification(
        paste("Annotations were saved, but workflow state failed:", conditionMessage(state_result)),
        type = "error",
        duration = 10
      )
      return()
    }

    invalidated_cache <- character()
    if (annotations_changed) {
      invalidated_cache <- cache_invalidate_sample(rv$sample_name, rv$dataset_dir_path)
    }

    record_state_event(
      rv,
      stage = "annotation",
      event_type = "annotations_saved",
      outcome = "saved",
      sample = rv$sample_name,
      parameters = list(
        resolution = rv$res,
        cell_count = nrow(cells_to_save),
        assigned_count = sum(!is.na(cells_to_save$cell_type)),
        invalidated_cache_files = length(invalidated_cache)
      )
    )

    showNotification("Successfully saved annotations to disk!", type = "default")
  })
}
