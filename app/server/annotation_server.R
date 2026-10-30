# Manual annotation handlers.

register_annotation_server <- function(input, output, session, state, context) {
  rv <- state

  register_single_sample_de_handlers(
    input = input,
    session = session,
    state = rv,
    sample_input_id = "sample_idx",
    trigger_button_id = "btn_rerun_anno_single_de",
    confirm_button_id = "confirm_run_anno_single_de",
    action_key = "annotation_single_sample_de",
    source = "manual_annotation",
    protect_unsaved_annotation = TRUE
  )

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
      status %in% c("incomplete", "skipped") &&
        current$status %in% c("completed", "skipped") &&
        !identical(current$status, status)
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

  show_unsaved_annotation_dialog <- function() {
    arm_app_confirmation(rv, "annotation_navigation")
    showModal(modalDialog(
      title = "Unsaved annotation changes",
      "This sample has cell-type assignments that have not been saved.",
      easyClose = FALSE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton(
          "btn_discard_annotation_navigation",
          "Discard and continue",
          class = "btn-danger",
          onclick = "this.disabled = true;"
        ),
        actionButton(
          "btn_save_annotation_navigation",
          "Save and continue",
          class = "btn-primary",
          onclick = "this.disabled = true;"
        )
      )
    ))
  }

  finish_annotation_navigation <- function() {
    pending <- rv$annotation_pending_navigation
    rv$annotation_pending_navigation <- NULL
    if (is.null(pending)) return(invisible(FALSE))

    record_state_event(
      rv,
      stage = "navigation",
      event_type = "annotation_navigation",
      outcome = "selected",
      sample = rv$sample_name,
      parameters = list(
        type = pending$type,
        target = if (identical(pending$type, "sample")) {
          as.character(pending$index)
        } else if (identical(pending$type, "menu")) {
          "menu_tab"
        } else {
          pending$target
        }
      )
    )

    if (identical(pending$type, "sample")) {
      updateSelectInput(session, "sample_idx", selected = pending$index)
    } else if (identical(pending$type, "menu")) {
      updateNavbarPage(session, "main_nav", selected = "menu_tab")
    } else if (identical(pending$type, "navbar")) {
      updateNavbarPage(session, "main_nav", selected = pending$target)
    }
    invisible(TRUE)
  }

  discard_current_annotation_edits <- function() {
    if (!is.null(rv$cells_filt) && !is.null(rv$cells_raw)) {
      restored <- data.table::copy(rv$cells_filt)
      if ("cell_type" %in% names(rv$cells_raw)) {
        restored[
          rv$cells_raw,
          on = "cell_name",
          cell_type := i.cell_type
        ]
      }
      rv$cells_filt <- restored
    }
    rv$final_plot <- NULL
    rv$annotation_dirty <- FALSE
    invisible(TRUE)
  }

  observe({
    req(rv$sample_name, rv$live_selected_config)
    note <- rv$live_selected_config$sample_notes[[rv$sample_name]]
    updateTextAreaInput(
      session,
      "anno_sample_notes",
      value = if (is.null(note)) "" else note
    )
  })

  observeEvent(input$btn_save_anno_notes, {
    req(rv$sample_name, rv$live_selected_config)
    rv$live_selected_config <- save_sample_note(
      rv$live_selected_config,
      rv$selected_config_path,
      rv$sample_name,
      input$anno_sample_notes
    )
    rv$config$selected <- rv$live_selected_config
    record_state_event(
      rv,
      stage = "notes",
      event_type = "sample_note_saved",
      outcome = "saved",
      sample = rv$sample_name,
      parameters = list(source = "annotation")
    )
    showNotification(paste("Notes saved for", rv$sample_name), type = "message")
  })

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

    clusters <- natural_cluster_order(rv$cells_filt$clust)

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

    if (isTRUE(rv$annotation_dirty)) {
      showNotification(
        "Save the current annotation edits before saving CNA configuration.",
        type = "error",
        duration = 10
      )
      return()
    }

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
          potentially_malignant_cell_types = unname(selected_pot_mal),
          omitted_by_user = FALSE
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

  annotation_load_trigger <- reactive({
    req(rv$paths_list, rv$pipeline_state, input$sample_idx, input$main_nav)
    idx <- as.numeric(input$sample_idx)
    sample_name <- basename(rv$paths_list$sample_dir_paths[[idx]])
    de_record <- get_pipeline_step(
      rv$pipeline_state,
      "differential_expression",
      sample_name
    )
    list(
      index = idx,
      sample = sample_name,
      nav = input$main_nav,
      de_status = de_record$status,
      de_updated_at = de_record$updated_at
    )
  })

  show_annotation_blocked <- function(readiness) {
    showNotification(
      paste(
        "Cannot load annotations yet:",
        paste(readiness$reasons, collapse = "; ")
      ),
      type = "warning",
      duration = 10
    )
  }

  observeEvent(annotation_load_trigger(), {
    trigger <- annotation_load_trigger()
    if (!identical(trigger$nav, "anno_tab")) return()
    idx <- trigger$index
    same_sample <- !is.null(rv$annotation_loaded_index) &&
      identical(idx, as.numeric(rv$annotation_loaded_index))
    readiness <- pipeline_step_readiness(
      rv$pipeline_state,
      "annotation",
      trigger$sample
    )

    if (same_sample && !readiness$ready) {
      rv$cells_filt <- NULL
      rv$all_matches <- NULL
      rv$annotation_loaded_index <- NULL
      rv$annotation_dirty <- FALSE
      show_annotation_blocked(readiness)
      return()
    }
    if (same_sample && !is.null(rv$cells_filt)) return()
    if (
      !same_sample && isTRUE(rv$annotation_dirty) &&
        !is.null(rv$annotation_loaded_index)
    ) {
      rv$annotation_pending_navigation <- list(type = "sample", index = idx)
      updateSelectInput(
        session,
        "sample_idx",
        selected = rv$annotation_loaded_index
      )
      show_unsaved_annotation_dialog()
      return()
    }
    nav_select("annotation_view", "annotation_cluster")

    cells_file <- rv$paths_list$cell_file_paths[idx]
    if (!file.exists(cells_file)) return()

    id <- showNotification("Loading annotation data...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    rv$final_plot <- NULL
    rv$cells_raw <- load_cells(cells_file)
    rv$sample_name <- unique(rv$cells_raw$sample)
    rv$res <- rv$live_selected_config$resolutions[[rv$sample_name]]
    rv$annotation_dirty <- FALSE

    readiness <- pipeline_step_readiness(
      rv$pipeline_state,
      "annotation",
      rv$sample_name
    )
    if (!readiness$ready) {
      rv$cells_filt <- NULL
      rv$all_matches <- NULL
      rv$annotation_loaded_index <- NULL
      show_annotation_blocked(readiness)
      return()
    }

    tryCatch({
      results_list <- cell_type_annotation_setup(idx, rv$paths_list, rv$results_dir_path,
                                                 rv$dataset_dir_path, rv$complete_markers,
                                                 dataset_config = rv$dataset_config,
                                                 selected_config = rv$live_selected_config)
      rv$cells_filt <- results_list$cells_filt
      rv$all_matches <- results_list$all_matches

      if ("cell_type" %in% names(rv$cells_raw)) {
        validate_annotation_cell_alignment(rv$cells_filt, rv$cells_raw)
        rv$cells_filt[rv$cells_raw, on = 'cell_name', cell_type := i.cell_type]
      } else if (!"cell_type" %in% names(rv$cells_filt)) {
        rv$cells_filt[, cell_type := NA_character_]
      }
      rv$annotation_loaded_index <- idx
    }, error = function(e) {
      rv$cells_filt <- NULL
      rv$all_matches <- NULL
      rv$annotation_loaded_index <- NULL
      message("Error loading annotation setup: ", e$message)
      record_state_event(
        rv,
        stage = "annotation",
        event_type = "annotation_load",
        outcome = "failed",
        sample = rv$sample_name,
        reason = conditionMessage(e)
      )
      showNotification(
        paste("Could not load annotation data:", conditionMessage(e)),
        type = "error",
        duration = 10
      )
    })
  })

  output$cluster_selector <- renderUI({
    req(rv$cells_filt)
    clusters <- natural_cluster_order(rv$cells_filt$clust)
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
    cluster_rows <- tmp$clust == input$cluster
    previous_annotation <- as.character(tmp$cell_type[cluster_rows])
    tmp[clust == input$cluster, cell_type := curr_annotation]
    rv$cells_filt <- tmp
    rv$annotation_dirty <- isTRUE(rv$annotation_dirty) || !identical(
      previous_annotation,
      as.character(tmp$cell_type[cluster_rows])
    )

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

    clusters <- natural_cluster_order(rv$cells_filt$clust)

    curr_idx <- which(clusters == input$cluster)

    if (length(curr_idx) > 0 && curr_idx < length(clusters)) {
      next_cluster <- clusters[curr_idx + 1]
      updateSelectInput(session, "cluster", selected = next_cluster)
    } else {
      showNotification("All clusters annotated! You can now preview and save.", type = "message", duration = 5)
    }
  })

  output$final_umap_plot <- renderPlot({
    req(rv$final_plot)
    rv$final_plot
  })

  observeEvent(input$preview_btn, {
    # Do not leave a prior sample/attempt's preview visible after a failed request.
    rv$final_plot <- NULL
    if (
      !is.data.frame(rv$cells_filt) || nrow(rv$cells_filt) == 0L ||
        !("cell_type" %in% names(rv$cells_filt)) ||
        length(rv$sample_name) != 1L || is.na(rv$sample_name) ||
        !nzchar(rv$sample_name) || length(rv$res) != 1L || is.na(rv$res)
    ) {
      showNotification(
        "Annotation data is unavailable. Select a sample with completed clustering, resolution selection and DE first.",
        type = "warning", duration = 10
      )
      return()
    }
    if (all(annotation_plot_labels(rv$cells_filt$cell_type) == "Unassigned")) {
      showNotification(
        "No cell types are assigned yet. Assign at least one cluster before previewing; remaining cells will appear as grey Unassigned points.",
        type = "warning", duration = 10
      )
      return()
    }
    id <- showNotification("Generating preview plot...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    plot_title <- rv$sample_name
    plot_subtitle <- paste("Annotated cell types; clustering resolution", rv$res)
    preview <- tryCatch({
      plot <- plot_clusters(
        rv$cells_filt,
        plot_title,
        x_col = umap1,
        y_col = umap2,
        cluster_col = cell_type,
        subtitle = plot_subtitle
      )
      # ggplot defers some errors until drawing: catch those before navigating.
      ggplot2::ggplot_build(plot)
      plot
    }, error = function(e) {
      showNotification(
        paste("Could not generate annotation preview. Check the sample's annotation and UMAP data, then retry:", conditionMessage(e)),
        type = "warning", duration = 10
      )
      NULL
    })
    if (is.null(preview)) return()
    rv$final_plot <- preview
    nav_select("annotation_view", "annotation_preview")
  })

  observeEvent(input$btn_back_menu_2, {
    if (isTRUE(rv$annotation_dirty)) {
      rv$annotation_pending_navigation <- list(type = "menu")
      show_unsaved_annotation_dialog()
    } else {
      updateNavbarPage(session, "main_nav", selected = "menu_tab")
    }
  })

  observeEvent(input$main_nav, {
    req(input$main_nav)
    if (
      isTRUE(rv$annotation_dirty) &&
        !identical(input$main_nav, "anno_tab")
    ) {
      rv$annotation_pending_navigation <- list(
        type = "navbar",
        target = input$main_nav
      )
      updateNavbarPage(session, "main_nav", selected = "anno_tab")
      show_unsaved_annotation_dialog()
    }
  }, ignoreInit = TRUE)

  save_current_annotations <- function() {
    req(rv$paths_list, rv$cells_filt, rv$cells_raw, rv$sample_name, rv$res, rv$results_dir_path)
    if (!begin_app_action(rv, "annotation_save")) return(FALSE)
    save_button_ids <- c(
      "save_btn", "btn_save_annotation_navigation"
    )
    invisible(lapply(save_button_ids, shinyjs::disable))
    on.exit({
      finish_app_action(rv, "annotation_save")
      invisible(lapply(save_button_ids, shinyjs::enable))
    }, add = TRUE)

    readiness <- pipeline_step_readiness(rv$pipeline_state, "annotation", rv$sample_name)
    if (!readiness$ready) {
      showNotification(
        paste("Cannot save annotations:", paste(readiness$reasons, collapse = "; ")),
        type = "error",
        duration = 10
      )
      return(FALSE)
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
      return(FALSE)
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

    rv$annotation_dirty <- FALSE
    showNotification("Successfully saved annotations to disk!", type = "default")
    TRUE
  }

  request_annotation_save <- function() {
    saved <- save_current_annotations()
    if (isTRUE(saved)) finish_annotation_navigation()
    invisible(saved)
  }

  observeEvent(input$save_btn, {
    request_annotation_save()
  })

  observeEvent(input$btn_omit_cna, {
    req(rv$sample_name, rv$pipeline_state)
    if (isTRUE(rv$annotation_dirty)) {
      showNotification(
        "Save the current annotation edits before omitting CNA.",
        type = "error",
        duration = 10
      )
      return()
    }
    readiness <- pipeline_step_readiness(
      rv$pipeline_state,
      "cna_configuration",
      rv$sample_name
    )
    if (!readiness$ready) {
      showNotification(
        paste(
          "Save annotations before omitting CNA:",
          paste(readiness$reasons, collapse = "; ")
        ),
        type = "error",
        duration = 10
      )
      return()
    }
    arm_app_confirmation(rv, "omit_cna")
    showModal(modalDialog(
      title = "Omit CNA for this sample?",
      paste0(
        "This records that CNA is intentionally omitted for ", rv$sample_name,
        ". You can reverse this later by saving a complete CNA configuration."
      ),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton(
          "btn_confirm_omit_cna",
          "Omit CNA",
          class = "btn-warning",
          onclick = "this.disabled = true;"
        )
      )
    ))
  })

  observeEvent(input$btn_confirm_omit_cna, {
    if (!claim_app_confirmation(rv, "omit_cna")) return()
    removeModal()
    current <- get_pipeline_step(
      rv$pipeline_state,
      "cna_configuration",
      rv$sample_name
    )
    decision_changed <- !identical(current$status, "skipped")
    if (!decision_changed) {
      showNotification(
        paste("CNA is already omitted for", rv$sample_name),
        type = "message"
      )
      return()
    }
    rv$live_selected_config$cna_ref_cells[[rv$sample_name]] <- list()
    rv$live_selected_config$cna_pot_mal_cells[[rv$sample_name]] <- list()
    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)
    persist_annotation_step(
      "cna_configuration",
      "skipped",
      reason = "User explicitly omitted CNA because it is not warranted for this sample.",
      details = list(omitted_by_user = TRUE),
      invalidate_downstream = decision_changed,
      invalidation_reason = if (decision_changed) {
        "The CNA configuration was explicitly omitted."
      } else NULL
    )
    invalidated_cache <- if (decision_changed) {
      cache_invalidate_sample(rv$sample_name, rv$dataset_dir_path)
    } else character()
    record_state_event(
      rv,
      stage = "cna_configuration",
      event_type = "cna_configuration_skipped",
      outcome = "skipped",
      sample = rv$sample_name,
      reason = "User explicitly omitted CNA because it is not warranted for this sample.",
      parameters = list(invalidated_cache_files = length(invalidated_cache))
    )
    showNotification(
      paste("CNA omitted for", rv$sample_name),
      type = "message"
    )
  })

  observeEvent(input$btn_discard_annotation_navigation, {
    if (!claim_app_confirmation(rv, "annotation_navigation")) return()
    removeModal()
    discard_current_annotation_edits()
    finish_annotation_navigation()
  })

  observeEvent(input$btn_save_annotation_navigation, {
    if (!claim_app_confirmation(rv, "annotation_navigation")) return()
    removeModal()
    request_annotation_save()
  })
}
