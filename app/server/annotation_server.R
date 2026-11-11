# Manual annotation handlers.

register_annotation_server <- function(input, output, session, state, context) {
  rv <- state

  output$annotation_progress <- renderUI({
    req(rv$pipeline_state, rv$paths_list)
    progress <- annotation_progress_summary(rv$pipeline_state,
      basename(rv$paths_list$sample_dir_paths), rv$sample_name, rv$annotation_dirty)
    div(class = "annotation-progress small text-body-secondary p-2", role = "status", `aria-live` = "polite",
      tags$div(paste0("Saved annotations: ", progress$saved, " of ", progress$total, " samples")),
      tags$progress(value = progress$saved, max = max(1L, progress$total),
        style = "width: 100%; height: 0.5rem;", `aria-label` = "Samples with saved annotations"),
      if (!is.null(progress$unsaved_sample)) tags$div(class = "text-warning-emphasis fw-semibold",
        paste0("Unsaved changes: ", progress$unsaved_sample, ". Pending edits are not included in saved progress.")),
      if (dataset_storage_cache_is_retired(rv$storage_state)) tags$div("Archived dataset: annotations are read-only.")
    )
  })
  observe({
    editable <- !is.null(rv$paths_list) && !dataset_storage_cache_is_retired(rv$storage_state)
    for (id in c("assign_btn", "save_btn", "btn_save_refs", "btn_omit_cna", "btn_save_anno_notes")) {
      shinyjs::toggleState(id, condition = editable)
    }
  })

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
    invalidation_reason = NULL,
    sample = rv$sample_name
  ) {
    current <- get_pipeline_step(rv$pipeline_state, step, sample)
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
        sample = sample,
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
      sample = sample,
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
    req(!dataset_storage_cache_is_retired(rv$storage_state))
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
    idx <- app_sample_index(rv, input$sample_idx)
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
    req(rv$cells_filt, rv$sample_name, rv$sample_metadata)

    current_types <- unique(rv$cells_filt$cell_type)
    current_types <- current_types[!is.na(current_types) & current_types != "NA"]
    current_types <- gsub("\\s*\\(.*\\)", "", current_types)
    current_types <- unique(current_types)

    sample_index <- match(rv$sample_name, rv$sample_metadata$sample)
    cancer_type <- "Unknown"
    if (!is.na(sample_index)) {
      value <- rv$sample_metadata$cancer_type[[sample_index]]
      if (!is.na(value) && nzchar(value)) cancer_type <- value
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
                     options = app_annotation_dropdown_options(placeholder = 'Select annotated types...'))
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
                   options = app_annotation_dropdown_options(create = TRUE, placeholder = 'Select or type new...'))
  })

  observeEvent(input$btn_save_refs, {
    req(!dataset_storage_cache_is_retired(rv$storage_state))
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
    req(identical(input$main_nav, "anno_tab"))
    idx <- app_sample_index(rv, input$sample_idx)
    sample_name <- basename(rv$paths_list$sample_dir_paths[[idx]])
    de_record <- get_pipeline_step(
      rv$pipeline_state,
      "differential_expression",
      sample_name
    )
    list(
      dataset = rv$dataset_dir_path,
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
    if (dataset_storage_cache_is_retired(rv$storage_state)) {
      rv$cells_filt <- NULL; rv$all_matches <- NULL; rv$annotation_loaded_index <- NULL
      return()
    }
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
    selectizeInput("cluster", "2. Select Cluster:", choices = clusters, options = app_annotation_dropdown_options())
  })

  # Render dynamically based on selected dataset marker filters
  output$cell_type_input_ui <- renderUI({
    req(rv$complete_markers)
    selectizeInput("cell_type_input", "Cell Type:",
                   choices = c("NA", unique(rv$complete_markers$cell_type)),
                   options = app_annotation_dropdown_options(create = TRUE, placeholder = 'Select or type new...'))
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
    req(!dataset_storage_cache_is_retired(rv$storage_state))
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
      showNotification(tagList(tags$strong("Sample ready to save: "), rv$sample_name,
        ". Last cluster reached; review the labels, then preview and save. Changes are not saved yet."),
        type = "warning", duration = 10)
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
    req(!dataset_storage_cache_is_retired(rv$storage_state))
    req(rv$paths_list, rv$cells_filt, rv$cells_raw, rv$sample_name, rv$res, rv$results_dir_path)
    idx <- app_sample_index(rv, input$sample_idx)
    req(identical(basename(rv$paths_list$sample_dir_paths[[idx]]), rv$sample_name))
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

    idx <- app_sample_index(rv, input$sample_idx)
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
          assigned_count = sum(!is.na(cells_to_save$cell_type)),
          snapshot_annotations = capture_snapshot_annotations(
            cells_to_save, rv$paths_list$cell_file_paths[idx], rv$res,
            get_pipeline_step(rv$pipeline_state, "clustering", rv$sample_name)
          )
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
    showNotification(tagList(tags$strong("Sample annotation saved: "), rv$sample_name,
      ". Annotations are saved to disk; this sample is included in saved progress."), type = "default", duration = 8)
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

  # Both entry points use the same omission decision and retained-output policy.
  omission_context <- reactiveVal(NULL)
  omission_target <- function(source) {
    req(rv$paths_list, rv$pipeline_state, rv$live_selected_config)
    if (length(rv$active_actions) || dataset_storage_cache_is_retired(rv$storage_state)) {
      showNotification("Omit CNA requires an editable dataset with no operation running.", type = "warning")
      return(NULL)
    }
    if (isTRUE(rv$annotation_dirty)) {
      showNotification("Save or discard the current annotation edits before omitting CNA.", type = "warning")
      return(NULL)
    }
    if (identical(source, "cna")) req(identical(input$main_nav, "cna_tab"))
    idx <- app_sample_index(rv, if (identical(source, "cna")) input$cna_sample_idx else input$sample_idx)
    sample <- basename(rv$paths_list$sample_dir_paths[[idx]])
    if (identical(source, "annotation")) req(identical(rv$sample_name, sample))
    readiness <- pipeline_step_readiness(rv$pipeline_state, "cna_configuration", sample)
    if (!readiness$ready) {
      showNotification(paste("Save annotations before omitting CNA:", paste(readiness$reasons, collapse = "; ")), type = "warning")
      return(NULL)
    }
    sample
  }
  omission_identity <- function(sample, source) list(
    identity = cna_analysis_context(rv, sample, source),
    steps = rv$pipeline_state$samples[[sample]],
    configuration = lapply(rv$live_selected_config[c("resolutions", "cna_ref_cells", "cna_pot_mal_cells",
      "cna_ward_ref_cluster", "cna_thresholds")], function(values) values[[sample]]))
  request_cna_omission <- function(source) {
    sample <- omission_target(source)
    if (is.null(sample)) return()
    if (pipeline_cna_is_omitted(rv$pipeline_state, sample)) {
      showNotification(paste("CNA is already omitted for", sample), type = "message")
      return()
    }
    omission_context(list(source = source, sample = sample, reviewed = omission_identity(sample, source)))
    arm_app_confirmation(rv, "omit_cna")
    showModal(modalDialog(
      title = "Omit CNA for this sample?",
      paste0(
        "This records that CNA is intentionally omitted for ", sample,
        ". Existing CNA decisions will be invalidated and CNA calculation caches removed. ",
        "Saved annotations, cell labels and historical plots/exports are retained. ",
        "You can reverse this later by saving a complete CNA configuration in Manual Annotation."
      ),
      easyClose = FALSE,
      footer = tagList(
        actionButton("btn_cancel_omit_cna", "Cancel", class = "btn-secondary"),
        actionButton(
          "btn_confirm_omit_cna",
          "Omit CNA",
          class = "btn-warning",
          onclick = "this.disabled = true;"
        )
      )
    ))
  }
  observeEvent(input$btn_omit_cna, { request_cna_omission("annotation") })
  observeEvent(input$btn_cna_omit, { request_cna_omission("cna") })
  observeEvent(input$btn_cancel_omit_cna, {
    claim_app_confirmation(rv, "omit_cna")
    omission_context(NULL)
    removeModal()
  })
  observe({
    shinyjs::toggleState("btn_cna_omit", condition = !is.null(rv$paths_list) &&
      !isTRUE(rv$annotation_dirty) && !length(rv$active_actions) &&
      !dataset_storage_cache_is_retired(rv$storage_state))
  })

  observeEvent(input$btn_confirm_omit_cna, {
    if (!claim_app_confirmation(rv, "omit_cna")) return()
    reviewed <- omission_context()
    omission_context(NULL)
    removeModal()
    if (is.null(reviewed)) return()
    sample <- omission_target(reviewed$source)
    if (is.null(sample)) return()
    if (!identical(reviewed$reviewed, omission_identity(sample, reviewed$source))) {
      showNotification("The sample or its CNA inputs changed. Review Omit CNA again before confirming.", type = "warning")
      return()
    }
    if (!begin_app_action(rv, "omit_cna")) return()
    on.exit(finish_app_action(rv, "omit_cna"), add = TRUE)
    rv$live_selected_config$cna_ref_cells[[sample]] <- list()
    rv$live_selected_config$cna_pot_mal_cells[[sample]] <- list()
    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)
    persist_annotation_step(
      "cna_configuration",
      "skipped",
      reason = "User explicitly omitted CNA because it is not warranted for this sample.",
      details = list(omitted_by_user = TRUE),
      invalidate_downstream = TRUE,
      invalidation_reason = "The CNA configuration was explicitly omitted.",
      sample = sample
    )
    invalidated_cache <- cache_invalidate_sample(sample, rv$dataset_dir_path)
    if (identical(reviewed$source, "cna")) {
      rv$cna_view_context <- cna_analysis_context(rv, sample, "cna_view_default")
      nav_select("cna_main_views", "cna_view_default")
    }
    record_state_event(
      rv,
      stage = "cna_configuration",
      event_type = "cna_configuration_skipped",
      outcome = "skipped",
      sample = sample,
      reason = "User explicitly omitted CNA because it is not warranted for this sample.",
      parameters = list(invalidated_cache_files = length(invalidated_cache))
    )
    showNotification(
      paste("CNA omitted for", sample),
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
