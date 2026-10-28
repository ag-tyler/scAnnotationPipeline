# CNA malignant-cluster selection and signal/correlation handlers.

register_cna_cluster_server <- function(input, output, session, state, context) {
  rv <- state
  cluster_ui_context <- reactiveVal(NULL)

  persist_cna_step <- function(
    step,
    sample_name,
    status,
    reason = NULL,
    details = NULL,
    invalidate_downstream = FALSE,
    invalidation_reason = NULL
  ) {
    rv$pipeline_state <- persist_pipeline_step_update(
      rv$pipeline_state,
      rv$pipeline_state_path,
      step = step,
      status = status,
      sample = sample_name,
      reason = reason,
      details = details,
      invalidate_downstream = invalidate_downstream,
      invalidation_reason = invalidation_reason
    )
    invisible(rv$pipeline_state)
  }

  # --- STEP 2: MALIGNANT CLUSTER SELECTION (CUTREE METHOD) ---

  # Debounce the slider so it only triggers 800ms AFTER the user stops dragging.
  k_debounced <- debounce(reactive({ input$cna_k_clusters }), millis = 800)

  # 3. Cache the heavy static plots (Only runs ONCE per sample)
  cna_static_plots <- reactive({
    req(input$cna_sample_idx, rv$paths_list)

    # 1. CRITICAL FIX: Get the correct sample name specifically for the CNA tab!
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]

    # 2. ISOLATE the config to completely prevent reactive invalidation loops
    cfg <- isolate(rv$live_selected_config)
    req(cfg)

    id <- showNotification("Generating main heatmap (this only happens once per sample)...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    hclust_file_name <- paste0('hclust_', s_name, '.qs2')
    cells_file_name <- paste0('cells_filt_clust_res_', cfg$resolutions[[s_name]], '_', s_name, '.qs2')
    clust_hclust <- cache_load_data(hclust_file_name, rv$dataset_dir_path)
    cells_filt <- cache_load_data(cells_file_name, rv$dataset_dir_path)

    # Revert to pre-CNA manual annotations before generating the plot
    if ("cell_type_pre_cna" %in% names(cells_filt)) {
      cells_filt[, cell_type := cell_type_pre_cna]
    }
    cells_filt[is.na(cell_type), cell_type := 'Unassigned']

    expdt <- load_expdt_from_cna_matrix(s_name, rv$dataset_dir_path)

    ref_cells <- cells_filt[cell_type %in% cfg$cna_ref_cells[[s_name]]]

    # Safely merge bypassing data.table NSE
    expdt$cell_type <- cells_filt$cell_type[match(expdt$cell_name, cells_filt$cell_name)]
    expdt <- expdt[!is.na(expdt$cell_type)]

    chr_n <- expdt[, .(n = length(unique(gene))), keyby = chr][n > 20]
    expdt <- expdt[chr %in% chr_n$chr]

    chr_lab <- c('01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12', '14', '16',
                 '17', '18', '19', '20', '22', 'X')
    chr_lab <- unique(expdt[, .(gene, chr)])[,{
      inds <- chr_n[, floor(cumsum(n) - n/2)[chr %in% chr_lab]];
      setNames(gsub('^0', '', chr[inds]), as.character(gene)[inds])
    }]

    hdata <- data.table::copy(expdt[cell_type == 'Unassigned' | cell_type %in% cfg$cna_pot_mal_cells[[s_name]]])
    ordered_cells <- clust_hclust$labels[clust_hclust$order]
    hdata[, cell_num_hclust := as.numeric(factor(cell_name, levels = ordered_cells))]
    hdata[, gene := factor(gene, levels = unique(gene))]

    hdata_hclust_cells <- with(clust_hclust, data.table::data.table(
      cell_name = labels, cell_num = order(order)
    ))

    # Safely merge bypassing data.table NSE
    hdata_hclust_cells$cell_type <- cells_filt$cell_type[match(hdata_hclust_cells$cell_name, cells_filt$cell_name)]

    # GENERATE THE HEAVY PLOTS ONCE
    dend_p <- dendrogram_plot(clust_hclust)
    htmp_p <- cna_heatmap(hdata, ref_cells, chr_n, chr_lab, hdata$cell_num_hclust)
    cell_type_p <- cluster_or_cell_type_bar_plot(hdata_hclust_cells, 'cell_type', 'Cell Type')

    # Extract legends BEFORE removing them
    htmp_leg <- cowplot::get_legend(htmp_p)
    cell_type_leg <- cowplot::get_legend(cell_type_p)

    # Strip themes and convert to static gtables (grobs)
    remove_leg <- ggplot2::theme(legend.position = "none")

    dend_grob <- ggplot2::ggplotGrob(dend_p)
    htmp_grob <- ggplot2::ggplotGrob(htmp_p + remove_leg)
    cell_type_grob <- ggplot2::ggplotGrob(cell_type_p + remove_leg)

    # Return them as a list to be reused
    return(list(
      dend_grob = dend_grob,
      htmp_grob = htmp_grob,
      cell_type_grob = cell_type_grob,
      htmp_leg = htmp_leg,
      cell_type_leg = cell_type_leg,
      hdata_cells = hdata_hclust_cells,
      hc = clust_hclust
    ))
  })

  # One lightweight identity/order mapping feeds the plot bar, navigator, save
  # confirmation, and persisted selection for each debounced sample/k context.
  cna_cluster_identity <- reactive({
    k_val <- k_debounced()
    static <- cna_static_plots()
    req(k_val, static)
    cna_cluster_identity_map(static$hc, k_val)
  })

  cluster_ui_model <- reactive({
    identity <- cna_cluster_identity()
    req(input$cna_sample_idx, rv$paths_list)
    sample_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    previous <- isolate(cluster_ui_context())

    saved_refs <- isolate(rv$live_selected_config$cna_ward_ref_cluster[[sample_name]])
    saved_record <- isolate(get_pipeline_step(
      rv$pipeline_state, "cna_cluster_selection", sample_name
    ))
    reconciled <- reconcile_cna_cluster_selection(
      current_selection = isolate(input$cna_selected_clusters),
      previous_context = previous,
      sample_name = sample_name,
      k = identity$k,
      saved_refs = saved_refs,
      saved_completed = identical(saved_record$status, "completed")
    )
    selected <- reconciled$selected
    selected <- intersect(
      as.character(selected),
      as.character(identity$clusters$cluster_id)
    )

    cluster_ui_context(reconciled$context)
    list(identity = identity, selected = selected)
  })

  output$cna_cluster_navigator_ui <- renderUI({
    model <- cluster_ui_model()
    cna_cluster_navigator_ui(model$identity, model$selected)
  })

  output$cna_cluster_selection_summary <- renderUI({
    identity <- cna_cluster_identity()
    selected <- input$cna_selected_clusters
    if (is.null(selected)) selected <- character()
    cna_cluster_selection_summary_ui(
      identity,
      selected
    )
  })

  # 4. Fast Plot Renderer (Only triggers when the debounced slider updates)
  output$cna_combined_heatmap_plot <- renderPlot({
    identity <- cna_cluster_identity()
    k_val <- identity$k

    # Grab the pre-computed static plots
    static <- cna_static_plots()
    req(static)

    # Reuse the canonical cut rather than recomputing cluster identities.
    cell_clusters <- identity$membership

    # 2. Update the cluster assignments
    # We MUST use copy() here so we don't permanently modify the cached reactive data
    hdata_cells_k <- data.table::copy(static$hdata_cells)
    cluster_levels <- cna_cluster_labels(seq_len(k_val), k_val)
    hdata_cells_k[, k_cluster := factor(
      cna_cluster_labels(cell_clusters[cell_name], k_val),
      levels = cluster_levels
    )]

    # 3. Build only the NEW k-cluster bar (takes < 0.1 seconds)
    k_colors <- viridis::viridis(k_val, option = "turbo")
    names(k_colors) <- cluster_levels

    clust_p <- cluster_or_cell_type_bar_plot(
      hdata_cells_k,
      "k_cluster",
      paste0("Cluster ID (k=", k_val, ")"),
      custom_colors = k_colors
    )

    # The ordered HTML navigator replaces the expensive high-k cluster legend.
    remove_leg <- ggplot2::theme(legend.position = "none")
    clust_grob <- ggplot2::ggplotGrob(clust_p + remove_leg)

    # Stack only the static legends vertically.
    stacked_legends <- cowplot::plot_grid(
      static$cell_type_leg,
      static$htmp_leg,
      ncol = 1, align = "v"
    )

    # 6. Assemble the final plot using the cached grobs!
    cowplot::plot_grid(
      static$dend_grob,
      static$cell_type_grob,
      clust_grob,
      static$htmp_grob,
      stacked_legends,
      nrow = 1, align = 'h', axis = 'tb',
      rel_widths = c(0.20, 0.03, 0.03, 1, 0.15)
    )
  })

  # 5. Save Selection
  observeEvent(input$btn_cna_save_malignant, {
    req(input$cna_k_clusters)
    identity <- isolate(cna_cluster_identity())
    if (!identical(as.integer(input$cna_k_clusters), identity$k)) {
      showNotification(
        "Please wait for the selected cluster count and navigator to finish updating before saving.",
        type = "warning", duration = 5
      )
      return()
    }

    # 1. Provide an explicit, visible warning if no clusters are selected
    if (is.null(input$cna_selected_clusters) || length(input$cna_selected_clusters) == 0) {
      if (!is.null(input$cna_sample_idx) && !is.null(rv$paths_list)) {
        s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
        record_state_event(
          rv,
          stage = "cna",
          event_type = "malignant_clusters_saved",
          outcome = "incomplete",
          sample = s_name,
          reason = "No malignant subclone was selected."
        )
      }
      showNotification("Please select at least one potentially malignant subtree in the navigator before saving.",
                       type = "warning", duration = 5)
      return()
    }

    # 2. Make sure the dataset variables are available
    req(input$cna_sample_idx, input$cna_k_clusters, rv$paths_list, rv$live_selected_config)

    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]

    readiness <- pipeline_step_readiness(
      rv$pipeline_state,
      "cna_cluster_selection",
      s_name
    )
    if (!readiness$ready) {
      showNotification(
        paste("Cannot save malignant clusters:", paste(readiness$reasons, collapse = "; ")),
        type = "error",
        duration = 10
      )
      return()
    }

    # 3. Save as a structured, named list for the backend
    subclones <- lapply(input$cna_selected_clusters, function(cl) {
      cluster_id <- as.numeric(cl)
      list(
        method = 'cutree',
        k = identity$k,
        cluster = cluster_id,
        label = cna_cluster_labels(cluster_id, identity$k)
      )
    })

    previous_subclones <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
    selection_changed <- !identical(previous_subclones, subclones)

    rv$live_selected_config$cna_ward_ref_cluster[[s_name]] <- subclones
    # --- NEW CLEANUP LOGIC ---
    # 1. Clear old thresholds from the active config to prevent UI mismatches
    if (selection_changed) {
      rv$live_selected_config$cna_thresholds[[s_name]] <- NULL
    }

    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)

    state_result <- tryCatch(
      persist_cna_step(
        "cna_cluster_selection",
        s_name,
        "completed",
        details = list(
          k = identity$k,
          clusters = as.numeric(input$cna_selected_clusters),
          cluster_labels = cna_cluster_labels(
            input$cna_selected_clusters,
            identity$k
          ),
          display_positions = identity$clusters$display_position[
            match(as.numeric(input$cna_selected_clusters), identity$clusters$cluster_id)
          ]
        ),
        invalidate_downstream = selection_changed,
        invalidation_reason = if (selection_changed) {
          "The malignant subclone selection changed."
        } else NULL
      ),
      error = identity
    )
    if (inherits(state_result, "error")) {
      record_state_event(
        rv,
        stage = "state",
        event_type = "cna_cluster_selection_state",
        outcome = "failed",
        sample = s_name,
        reason = conditionMessage(state_result)
      )
      showNotification(
        paste("Selection was saved, but workflow state failed:", conditionMessage(state_result)),
        type = "error",
        duration = 10
      )
      return()
    }

    # 2. Delete old subclone plots
    cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
    if (selection_changed && dir.exists(cna_plots_dir_path)) {
      old_plots <- list.files(cna_plots_dir_path,
                              pattern = paste0("subclone_.*_", s_name, "\\.png$"),
                              full.names = TRUE)
      if (length(old_plots) > 0) file.remove(old_plots)
    }

    # 3. Delete old subclone cache files
    cache_dir <- file.path(rv$dataset_dir_path, "cache")
    old_cache <- if (selection_changed) list.files(
      cache_dir,
      pattern = paste0("^cna_sig_cor_", s_name, "_subclone_.*\\.qs2$"),
      full.names = TRUE
    ) else character()
    if (length(old_cache) > 0) {
      cache_invalidate_artifacts(basename(old_cache), rv$dataset_dir_path)
    }
    # -------------------------

    record_state_event(
      rv,
      stage = "cna",
      event_type = "malignant_clusters_saved",
      outcome = "saved",
      sample = s_name,
      parameters = list(
        k = identity$k,
        clusters = as.numeric(input$cna_selected_clusters),
        cluster_labels = cna_cluster_labels(
          input$cna_selected_clusters,
          identity$k
        ),
        display_positions = identity$clusters$display_position[
          match(as.numeric(input$cna_selected_clusters), identity$clusters$cluster_id)
        ]
      )
    )
    if (length(old_cache) > 0L) {
      record_state_event(
        rv,
        stage = "cache",
        event_type = "cna_signal_cache",
        outcome = "invalidated",
        sample = s_name,
        parameters = list(file_count = length(old_cache)),
        reason = "The malignant cluster selection changed."
      )
    }

    id_plot <- showNotification("Saving k-clusters plot to disk...", duration = NULL, type = "message")

    # Define k_val right here so it is always available to cutree()
    k_val <- identity$k

    # Grab the cached static grobs and rebuild the exact plot from the UI
    static <- isolate(cna_static_plots())
    if (!is.null(static)) {
      cell_clusters <- identity$membership
      hdata_cells_k <- data.table::copy(static$hdata_cells)
      cluster_levels <- cna_cluster_labels(seq_len(k_val), k_val)
      hdata_cells_k[, k_cluster := factor(
        cna_cluster_labels(cell_clusters[cell_name], k_val),
        levels = cluster_levels
      )]

      k_colors <- viridis::viridis(k_val, option = "turbo")
      names(k_colors) <- cluster_levels

      clust_p <- cluster_or_cell_type_bar_plot(
        hdata_cells_k,
        "k_cluster",
        paste0("Cluster ID (k=", k_val, ")"),
        custom_colors = k_colors
      )
      clust_leg <- cowplot::get_legend(clust_p)
      remove_leg <- ggplot2::theme(legend.position = "none")
      clust_grob <- ggplot2::ggplotGrob(clust_p + remove_leg)

      stacked_legends <- cowplot::plot_grid(
        static$cell_type_leg,
        clust_leg,
        static$htmp_leg,
        ncol = 1, align = "v"
      )

      final_plot <- cowplot::plot_grid(
        static$dend_grob,
        static$cell_type_grob,
        clust_grob,
        static$htmp_grob,
        stacked_legends,
        nrow = 1, align = 'h', axis = 'tb',
        rel_widths = c(0.20, 0.03, 0.03, 1, 0.15)
      )

      cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
      dir.create(cna_plots_dir_path, showWarnings = FALSE, recursive = TRUE)

      plot_path <- file.path(cna_plots_dir_path, paste0('hclust_k_', k_val, '_clusters_', s_name, '.png'))
      ggplot2::ggsave(plot_path, plot = final_plot, width = 300, height = 400, units = 'mm', bg = "white")
    }
    removeNotification(id_plot)

    showNotification("Malignant clusters saved! Ready to compute signal/correlation.", type = "message")

    # 4. Enable Step 3 computation button (make sure this ID matches your actual UI button for Step 3!)
    shinyjs::enable("btn_cna_compute_sig_cor")
  })

  # --- STEP 3: Compute Signal & Correlation ---
  observeEvent(input$btn_cna_compute_sig_cor, {
    req(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]

    readiness <- pipeline_step_readiness(
      rv$pipeline_state,
      "cna_signal_correlation",
      s_name
    )
    if (!readiness$ready) {
      showNotification(
        paste("Cannot compute signal/correlation:", paste(readiness$reasons, collapse = "; ")),
        type = "error",
        duration = 10
      )
      return()
    }

    state_started <- tryCatch(
      persist_cna_step(
        "cna_signal_correlation",
        s_name,
        "in_progress",
        invalidate_downstream = get_pipeline_step(
          rv$pipeline_state,
          "cna_signal_correlation",
          s_name
        )$status %in% c("completed", "skipped"),
        invalidation_reason = "Signal/correlation is being recomputed."
      ),
      error = identity
    )
    if (inherits(state_started, "error")) {
      showNotification(
        paste("Signal/correlation could not start because workflow state failed:", conditionMessage(state_started)),
        type = "error",
        duration = 10
      )
      return()
    }

    record_state_event(
      rv,
      stage = "cna",
      event_type = "cna_signal_correlation",
      outcome = "started",
      sample = s_name
    )

    tryCatch({
      withProgress(message = paste("Signal/correlation:", s_name), value = 0, {
        setProgress(value = 0, detail = "Loading CNA inputs")
        cells_file <- paste0('cells_filt_clust_res_', rv$live_selected_config$resolutions[[s_name]], '_', s_name, '.qs2')
        cells_filt <- cache_load_data(cells_file, rv$dataset_dir_path)
        cells_filt[is.na(cell_type), cell_type := 'Unassigned']
        ref_cells <- cells_filt[cell_type %in% rv$live_selected_config$cna_ref_cells[[s_name]]]

        ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
        n_subclones <- length(ward_refs)
        for (i in seq_along(ward_refs)) {
          setProgress(
            value = (i - 1) / n_subclones,
            detail = paste("Computing subclone", i, "of", n_subclones)
          )
          compute_signal_cor_cna(s_name, i, ref_cells, rv$live_selected_config, rv$dataset_dir_path)
        }

        persist_cna_step(
          "cna_signal_correlation",
          s_name,
          "completed",
          details = list(subclone_count = n_subclones)
        )

        record_state_event(
          rv,
          stage = "cna",
          event_type = "cna_signal_correlation",
          outcome = "completed",
          sample = s_name,
          parameters = list(subclone_count = n_subclones)
        )
        setProgress(value = 1, detail = paste(n_subclones, "subclone(s) complete"))
        showNotification("Signal and Correlation computed!", type = "default")
        shinyjs::enable("btn_cna_go_thresholds")
        nav_select("cna_main_views", "cna_view_thresholds")
      })
    }, error = function(error) {
      ineligible <- inherits(error, "cna_ineligible_error")
      outcome <- if (ineligible) "skipped" else "failed"
      try(
        persist_cna_step(
          "cna_signal_correlation",
          s_name,
          outcome,
          reason = conditionMessage(error)
        ),
        silent = TRUE
      )
      record_state_event(
        rv,
        stage = "cna",
        event_type = "cna_signal_correlation",
        outcome = outcome,
        sample = s_name,
        reason = conditionMessage(error)
      )
      showNotification(
        paste(
          if (ineligible) "Signal/correlation is not applicable:" else "Signal/correlation computation failed:",
          conditionMessage(error)
        ),
        type = if (ineligible) "warning" else "error",
        duration = 10
      )
    })
  })
}
