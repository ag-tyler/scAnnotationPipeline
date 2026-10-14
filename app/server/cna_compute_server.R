# CNA computation handlers.

register_cna_compute_server <- function(input, output, session, state, context) {
  rv <- state

  # ================================================================================================
  # CNA PIPELINE EXECUTION
  # ================================================================================================

  # --- STEP 1: Compute CNA & Heatmaps ---
  observeEvent(input$btn_cna_compute_heatmaps, {
    req(input$cna_sample_idx, rv$paths_list)
    idx <- as.numeric(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]

    id <- showNotification("Computing CNA and Heatmaps. Check R console...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    # Load filtered data from cache
    cells_file <- paste0('cells_filt_clust_res_', rv$live_selected_config$resolutions[[s_name]], '_', s_name, '.qs2')
    expmat_file <- paste0('expmat_filt_', s_name, '.qs2')

    cells_filt <- cache_load_data(cells_file, rv$dataset_dir_path)
    expmat_filt <- cache_load_data(expmat_file, rv$dataset_dir_path)

    # Prepare reference cells
    cells_filt[is.na(cell_type), cell_type := 'Unassigned']
    ref_cells <- cells_filt[cell_type %in% rv$live_selected_config$cna_ref_cells[[s_name]]]

    # Compute CNA
    cna_mat_file_name <- paste0('cna_matrix_', s_name, '.qs2')
    if (!cache_check_exists(cna_mat_file_name, rv$dataset_dir_path)) {
      compute_cna_and_cache(expmat_filt, context$resources$gene_positions, ref_cells, s_name, rv$dataset_dir_path)
    }

    # Compute Heatmaps
    cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
    dir.create(cna_plots_dir_path, showWarnings = FALSE)

    cna_clustering_and_heatmaps(ref_cells, s_name, rv$live_selected_config, cna_plots_dir_path,
                                rv$dataset_dir_path)

    showNotification("CNA and Heatmaps computed successfully!", type = "default")
    shinyjs::enable("btn_cna_go_malig_clust")

    # Trigger UI update by moving to the next tab
    nav_select("cna_main_views", "cna_view_select_malignant")
  })

  # --- STEP 1b: Batch Compute CNA & Heatmaps ---
  observeEvent(input$btn_cna_batch_compute, {
    req(rv$paths_list)
    showModal(modalDialog(
      title = "Confirm Batch CNA Computation",
      "Are you sure you want to run the CNA and Heatmap pipeline for ALL valid samples? This process takes a significant amount of time and will lock the application.",
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_cna_batch", "Yes, Run Batch", class = "btn-danger")
      )
    ))
  })

  observeEvent(input$confirm_cna_batch, {
    removeModal()
    id <- showNotification("Running Batch CNA Computation. Check R console...", duration = NULL, type = "warning")

    # Run backend logic
    res <- batch_compute_cna_and_heatmaps(
      paths_list = rv$paths_list,
      dataset_dir_path = rv$dataset_dir_path,
      results_dir_path = rv$results_dir_path,
      selected_config = rv$live_selected_config,
      gene_positions = context$resources$gene_positions
    )

    removeNotification(id)

    # Report results to user
    msg <- paste0("Batch Complete!\nProcessed: ", length(res$processed), " samples\nSkipped: ", length(res$skipped), " samples")
    showNotification(msg, type = "message", duration = 15)

    # If the currently selected sample in the UI was just processed, unlock Step 2 automatically
    current_s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    if (current_s_name %in% res$processed) {
      shinyjs::enable("btn_cna_go_malig_clust")
      nav_select("cna_main_views", "cna_view_select_malignant")
    }
  })
}
