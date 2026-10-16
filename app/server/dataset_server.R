# Dataset workspace loading and creation handlers.

register_dataset_server <- function(input, output, session, state, context) {
  rv <- state
  config <- context$config
  marker_genes <- context$resources$marker_genes
  malignant_markers <- context$resources$malignant_markers
  housekeeping_genes <- context$resources$housekeeping_genes
  mt_genes <- context$resources$mt_genes
  cancer_cell_map <- context$resources$cancer_cell_map
  dataset_base_dir <- context$paths$datasets_dir
  templates_dir <- context$paths$templates_dir
  available_datasets <- context$available_datasets


  observeEvent(input$btn_load_dataset, {
    req(input$dataset_choice)
    dataset_name <- input$dataset_choice

    id <- showNotification(paste("Loading workspace:", dataset_name), duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)

    dataset_dir_path <- file.path(config$paths$datasets_dir, dataset_name)

    # 1. Verify Dataset Files
    dataset_config_path <- file.path(dataset_dir_path, config$config_files$dataset)
    samples_config_path <- file.path(dataset_dir_path, config$config_files$samples)
    selected_config_path <- file.path(dataset_dir_path, config$config_files$selected)

    if (!file.exists(dataset_config_path)) {
      record_pipeline_event(
        dataset_dir_path = dataset_dir_path,
        dataset = dataset_name,
        stage = "dataset",
        event_type = "dataset_load",
        outcome = "failed",
        reason = "dataset_config.yaml is missing."
      )
      showNotification("Configuration file missing for this dataset. Aborting load.", type = "error", duration = 8)
      return()
    }

    # 2. Parse Configs
    dataset_config <- yaml::read_yaml(dataset_config_path)
    samples_config <- tryCatch(
      validate_samples_config(yaml::read_yaml(samples_config_path)),
      error = identity
    )
    if (inherits(samples_config, "error")) {
      record_pipeline_event(
        dataset_dir_path = dataset_dir_path,
        dataset = dataset_name,
        stage = "dataset",
        event_type = "dataset_load",
        outcome = "failed",
        reason = conditionMessage(samples_config)
      )
      showNotification(
        paste("Sample configuration could not be loaded:", conditionMessage(samples_config)),
        type = "error",
        duration = 10
      )
      return()
    }

    if (file.exists(selected_config_path)) {
      selected_config <- yaml::read_yaml(selected_config_path)
    } else {
      # Initialize empty state if it's a new dataset
      selected_config <- list(resolutions = list(), cna_ref_cells = list(), cna_pot_mal_cells = list())
    }

    # 3. Setup Paths specific to dataset
    processed_dir_path <- file.path(dataset_dir_path, config$dataset_paths$processed_dir)

    if (!dir.exists(processed_dir_path)) {
      record_pipeline_event(
        dataset_dir_path = dataset_dir_path,
        dataset = dataset_name,
        stage = "dataset",
        event_type = "dataset_load",
        outcome = "failed",
        reason = "The processed_data directory is missing; run standardization first."
      )
      showNotification(
        paste0("Processed data folder not found: ", processed_dir_path,
               ". Run the standardization pipeline (standardize.R) for this dataset first."),
        type = "error", duration = 10
      )
      return()
    }

    sample_dir_paths <- list.dirs(processed_dir_path, recursive = FALSE)

    if (length(sample_dir_paths) == 0) {
      record_pipeline_event(
        dataset_dir_path = dataset_dir_path,
        dataset = dataset_name,
        stage = "dataset",
        event_type = "dataset_load",
        outcome = "failed",
        reason = "No sample directories exist under processed_data; run standardization first."
      )
      showNotification(
        "No sample folders found in processed_data/. Run standardize.R before loading this dataset.",
        type = "error", duration = 10
      )
      return()
    }

    results_dir_path <- file.path(dataset_dir_path, config$dataset_paths$results_dir)

    dir.create(results_dir_path, showWarnings = FALSE)

    # Gather sample paths
    sample_dir_paths <- list.dirs(processed_dir_path, recursive = FALSE)
    cell_file_paths <- file.path(sample_dir_paths, dataset_config$std_names$cells)
    expmat_file_paths <- file.path(sample_dir_paths, dataset_config$std_names$expmat)
    genes_file_paths <- file.path(sample_dir_paths, dataset_config$std_names$genes)

    paths_list <- list(
      sample_dir_paths = sample_dir_paths,
      cell_file_paths = cell_file_paths,
      expmat_file_paths = expmat_file_paths,
      genes_file_paths = genes_file_paths
    )

    # Load or conservatively initialize persistent workflow state. Existing
    # datasets without a state file are migrated once from decisions/artifacts.
    state_filename <- .pipeline_value_or(
      config$config_files$state,
      "pipeline_state.yaml"
    )
    pipeline_state <- tryCatch(
      load_or_initialize_pipeline_state(
        dataset_dir_path = dataset_dir_path,
        dataset_id = dataset_name,
        sample_names = basename(sample_dir_paths),
        dataset_config = dataset_config,
        selected_config = selected_config,
        config = config,
        state_filename = state_filename,
        infer_legacy = TRUE
      ),
      error = identity
    )
    if (inherits(pipeline_state, "error")) {
      record_pipeline_event(
        dataset_dir_path = dataset_dir_path,
        dataset = dataset_name,
        stage = "state",
        event_type = "pipeline_state_load",
        outcome = "failed",
        reason = conditionMessage(pipeline_state)
      )
      showNotification(
        paste("Pipeline state could not be loaded:", conditionMessage(pipeline_state)),
        type = "error",
        duration = 10
      )
      return()
    }

    selected_config_before_reconcile <- selected_config
    selected_config <- reconcile_selected_config(
      selected_config,
      basename(sample_dir_paths)
    )
    if (!identical(selected_config, selected_config_before_reconcile)) {
      yaml::write_yaml(selected_config, selected_config_path)
    }
    state_initialized <- isTRUE(attr(pipeline_state, "initialized"))
    state_sample_changes <- attr(pipeline_state, "sample_changes")
    state_dependency_changes <- attr(pipeline_state, "dependency_changes")
    pipeline_state <- reconcile_pipeline_state_cache(
      pipeline_state,
      paths_list = paths_list,
      dataset_config = dataset_config,
      selected_config = selected_config,
      dataset_dir_path = dataset_dir_path,
      gene_positions = context$resources$gene_positions
    )
    state_cache_changes <- attr(pipeline_state, "cache_changes")
    attr(pipeline_state, "cache_changes") <- NULL
    if (length(state_cache_changes) > 0L) {
      pipeline_state <- save_pipeline_state_atomic(
        pipeline_state,
        dataset_dir_path,
        state_filename = state_filename
      )
    }

    # 4. Generate Dataset-Specific Marker Filters
    complete_markers <- marker_genes[, {
      n_passing <- sum(combined > dataset_config$marker_filter_params$cell_type$min_score)
      n_keep <- max(dataset_config$marker_filter_params$cell_type$min_genes,
                    min(n_passing, dataset_config$marker_filter_params$cell_type$max_genes))
      head(.SD, n_keep)
    }, by = cell_type]

    complete_markers <- complete_markers[, .(cell_type, symbol)]
    housekeeping_genes_dt <- data.table(cell_type = 'Housekeeping_artifact', symbol = housekeeping_genes)
    mt_genes_dt <- data.table(cell_type = 'Mito_artifact', symbol = mt_genes)
    complete_markers <- rbindlist(list(complete_markers, housekeeping_genes_dt, mt_genes_dt))

    # Attempt to load samples for utilities if present
    samples_path <- file.path(processed_dir_path, dataset_config$std_names$samples)
    samples <- tryCatch(load_samples(samples_path), error = function(e) NULL)

    # Select malignant markers depending on dataset cancer type, skip if markers not available
    if (!is.null(samples) && "cancer_type" %in% names(samples)) {

      cancer_type <- unique(na.omit(samples$cancer_type))

      if (length(cancer_type) == 1 && cancer_type %in% names(cancer_cell_map$cancer_types)) {

        tryCatch({
          cancer_type_acronym <- cancer_cell_map$cancer_types[[cancer_type]]
          cancer_cell_type <- cancer_cell_map$cell_types[[cancer_type_acronym]]

          if (is.null(cancer_cell_type)) {
            stop("cancer_cell_map$cell_types has no entry for acronym: ", cancer_type_acronym)
          }

          filtered_malignant_markers <- malignant_markers[, {
            n_passing <- sum(combined > dataset_config$marker_filter_params$cancer_type$min_score)
            n_keep <- max(dataset_config$marker_filter_params$cancer_type$min_genes,
                          min(n_passing, dataset_config$marker_filter_params$cancer_type$max_genes))
            head(.SD, n_keep)
          }, by = cancer_type]

          if (cancer_type_acronym == 'HNSCC') {
            n_hnscc_genes <- dataset_config$marker_filter_params$cancer_type$min_genes
            cancer_type_markers <- filtered_malignant_markers[
              cancer_type %in% c("HNSCC_HPV-neg", "HNSCC_HPV-pos"),
              head(.SD, n_hnscc_genes),
              by = cancer_type
            ][, cancer_type := "HNSCC"]
          } else {
            cancer_type_markers <- filtered_malignant_markers[cancer_type == cancer_type_acronym, ]
          }

          setnames(cancer_type_markers, old = 'cancer_type', new = 'cell_type')
          cancer_type_markers[, cell_type := cancer_cell_type]
          cancer_type_markers <- cancer_type_markers[, .(cell_type, symbol)]  # match complete_markers' schema

          complete_markers <- rbindlist(list(complete_markers, cancer_type_markers))

        }, error = function(e) {
          warning("Could not add cancer-type-specific malignant markers: ", e$message, call. = FALSE)
        })
      }
    }

    # 5. Populate Reactive State
    rv$paths_list <- paths_list
    rv$dataset_config <- dataset_config
    rv$samples_config <- samples_config
    rv$live_selected_config <- selected_config
    rv$results_dir_path <- results_dir_path
    rv$selected_config_path <- selected_config_path
    rv$pipeline_state <- pipeline_state
    rv$pipeline_state_path <- file.path(dataset_dir_path, state_filename)
    rv$complete_markers <- complete_markers
    rv$dataset_dir_path <- dataset_dir_path
    rv$cells_filt <- NULL
    rv$all_matches <- NULL
    rv$cells_raw <- NULL
    rv$sample_name <- NULL
    rv$res <- NULL
    rv$final_plot <- NULL
    rv$annotation_dirty <- FALSE
    rv$annotation_loaded_index <- NULL
    rv$annotation_pending_navigation <- NULL

    # Update config with the selected configs and store it
    local_config <- config
    local_config$selected <- selected_config
    rv$config <- local_config

    record_state_event(
      rv,
      stage = "dataset",
      event_type = "dataset_load",
      outcome = "completed",
      parameters = list(sample_count = length(sample_dir_paths))
    )
    record_state_event(
      rv,
      stage = "state",
      event_type = "pipeline_state_load",
      outcome = "completed",
      parameters = list(
        initialized = state_initialized,
        revision = pipeline_state$revision,
        samples_added = if (is.null(state_sample_changes$added)) {
          character()
        } else state_sample_changes$added,
        samples_removed = if (is.null(state_sample_changes$removed)) {
          character()
        } else state_sample_changes$removed,
        dependencies_reconciled = if (is.null(state_dependency_changes)) {
          character()
        } else state_dependency_changes,
        caches_reconciled = if (is.null(state_cache_changes)) {
          character()
        } else state_cache_changes
      )
    )

    # 6. Update UI Dropdowns
    s_choices <- setNames(
      seq_along(paths_list$sample_dir_paths),
      basename(paths_list$sample_dir_paths)
    )
    updateSelectInput(session, "res_sample_idx", choices = s_choices, selected = 1)
    updateSelectInput(session, "sample_idx", choices = s_choices, selected = 1)

    # 7. Reveal App Tabs & Jump to Dashboard
    nav_show("main_nav", target = "menu_tab")
    nav_show("main_nav", target = "clipboard_tab")
    nav_show("main_nav", target = "res_tab")
    nav_show("main_nav", target = "anno_tab")
    nav_show("main_nav", target = "cna_tab")
    nav_hide("main_nav", target = "dataset_tab")
    updateNavbarPage(session, "main_nav", selected = "menu_tab")

    showNotification("Dataset loaded successfully!", type = "default")
  })

  observeEvent(input$btn_change_dataset, {
    # Allow user to swap datasets - reveal selection UI
    nav_show("main_nav", target = "dataset_tab")
    nav_hide("main_nav", target = "menu_tab")
    nav_hide("main_nav", target = "clipboard_tab")
    nav_hide("main_nav", target = "res_tab")
    nav_hide("main_nav", target = "anno_tab")
    updateNavbarPage(session, "main_nav", selected = "dataset_tab")
  })

  observeEvent(input$btn_create_dataset_ui, {
    showModal(modalDialog(
      title = "Create New Dataset Workspace",
      textInput("new_ds_name", "Dataset Name (Folder Name):", placeholder = "e.g., Pancreas_Dataset_02"),
      textInput("new_ds_location", "Location (Parent Directory):", value = dataset_base_dir),
      selectInput(
        "new_ds_tech",
        "Standardization Template:",
        choices = config$standardization_pipelines,
        selected = "general"
      ),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("btn_confirm_create_ds", "Create Dataset", class = "btn-primary")
      )
    ))
  })

  observeEvent(input$btn_confirm_create_ds, {
    req(input$new_ds_name, input$new_ds_location, input$new_ds_tech)

    parent_dir <- trimws(input$new_ds_location)

    if (!identical(input$new_ds_tech, "general")) {
      showNotification(
        "Only the general standardization template is supported.",
        type = "error",
        duration = 8
      )
      return()
    }

    # Validate the name — stop with a clear notification instead of a raw error
    ds_name <- tryCatch(
      sanitize_dataset_name(input$new_ds_name),
      error = function(e) {
        showNotification(e$message, type = "error", duration = 8)
        NULL
      }
    )
    req(ds_name)  # halts here if sanitize_dataset_name() failed above

    new_ds_path <- file.path(parent_dir, ds_name)

    # Belt-and-suspenders: confirm the resolved path still lives under parent_dir.
    # normalizePath(mustWork=FALSE) resolves '.', symlinks, etc. without requiring
    # the path to exist yet.
    resolved_new_path <- normalizePath(new_ds_path, mustWork = FALSE)
    resolved_parent   <- normalizePath(parent_dir, mustWork = FALSE)

    if (!startsWith(resolved_new_path, resolved_parent)) {
      showNotification("Invalid dataset location — path escapes the parent directory.",
                       type = "error", duration = 8)
      return()
    }

    # 1. Validation (existing check, now after the safety checks above)
    if (dir.exists(new_ds_path)) {
      showNotification("A dataset with this name already exists at this location.", type = "error")
      return()
    }

    template_path <- file.path(templates_dir, "dataset_config_template.yaml")
    if (!file.exists(template_path)) {
      showNotification("dataset_config_template.yaml not found in the template folder!", type = "error")
      return()
    }
    standardization_template_path <- file.path(
      templates_dir,
      "standardize_general.R"
    )
    if (!file.exists(standardization_template_path)) {
      showNotification(
        "standardize_general.R not found in the template folder!",
        type = "error",
        duration = 8
      )
      return()
    }

    # 2. Create Directory Structure
    dir.create(new_ds_path, recursive = TRUE, showWarnings = FALSE)
    subfolders <- c("cache", "data", "processed_data", "results", "logs")
    lapply(subfolders, function(f) dir.create(file.path(new_ds_path, f), showWarnings = FALSE))

    # 3. Handle dataset_config.yaml
    ds_config <- yaml::read_yaml(template_path)

    # The general template is independent of sequencing technology. Users fill
    # in the actual technology while completing the dataset/sample metadata.
    ds_config$project_info$dataset_id <- ds_name
    ds_config$project_info$technology <- ""
    ds_config$raw_files$type <- "general"
    yaml::write_yaml(ds_config, file.path(new_ds_path, config$config_files$dataset))

    # 4. Handle samples_config.yaml
    samples_config <- list(
      samples = list(
        list(
          sample = "", technology = "", cancer_type = "", patient = "", histology = "",
          site = "", sample_type = "", sample_primary_met = "", disease_extent = "", diagnosis_recurrence = "",
          instance_at_site = "", treated_naive = "", age = "", sex = "", grade = "", AJCC_stage = "",
          AJCC_T = "", AJCC_N = "", AJCC_M = "", size = "", smoking_status = "", PY = "", KI67 = "",
          genetic_hormonal_features = "", chemotherapy_exposed = "", chemotherapy_response = "",
          targeted_rx_exposed = "", targeted_rx_response = "", post_sampling_rx_exposed = "",
          post_sampling_rx_response = "", time_end_of_rx_to_sampling = "", ET_exposed = "",
          ET_response = "", ICB_exposed = "", ICB_response = "", PFS_DFS = "", OS = ""
        )
      )
    )
    yaml::write_yaml(samples_config, file.path(new_ds_path, config$config_files$samples))

    # 5. Handle selected_config.yaml
    selected_config <- setup_selected_config(character())
    yaml::write_yaml(selected_config, file.path(new_ds_path, config$config_files$selected))

    # Initialize current workflow state separately from user selections and
    # append-only event history. Samples are added after samples_config is filled.
    state_filename <- .pipeline_value_or(
      config$config_files$state,
      "pipeline_state.yaml"
    )
    initial_state <- tryCatch(
      save_pipeline_state_atomic(
        new_pipeline_state(ds_name, character()),
        dataset_dir_path = new_ds_path,
        state_filename = state_filename
      ),
      error = identity
    )
    if (inherits(initial_state, "error")) {
      record_pipeline_event(
        dataset_dir_path = new_ds_path,
        dataset = ds_name,
        stage = "state",
        event_type = "pipeline_state_initialized",
        outcome = "failed",
        reason = conditionMessage(initial_state)
      )
      showNotification(
        paste("The pipeline state could not be initialized:", conditionMessage(initial_state)),
        type = "error",
        duration = 10
      )
      return()
    }

    # 6. Copy the sole supported standardization template.
    template_copied <- file.copy(
      from = standardization_template_path,
      to = file.path(new_ds_path, "standardize.R")
    )
    if (!isTRUE(template_copied)) {
      record_pipeline_event(
        dataset_dir_path = new_ds_path,
        dataset = ds_name,
        stage = "dataset",
        event_type = "workspace_created",
        outcome = "failed",
        reason = "The general standardization template could not be copied."
      )
      showNotification(
        "The general standardization template could not be copied.",
        type = "error",
        duration = 8
      )
      return()
    }

    record_pipeline_event(
      dataset_dir_path = new_ds_path,
      dataset = ds_name,
      stage = "dataset",
      event_type = "workspace_created",
      outcome = "completed",
      parameters = list(template = "general")
    )
    record_pipeline_event(
      dataset_dir_path = new_ds_path,
      dataset = ds_name,
      stage = "state",
      event_type = "pipeline_state_initialized",
      outcome = "completed",
      parameters = list(schema_version = PIPELINE_STATE_SCHEMA_VERSION)
    )

    # 7. Update UI and Close
    all_dataset_dirs <- list.dirs(parent_dir, recursive = FALSE)
    updated_datasets <- basename(all_dataset_dirs[all_dataset_dirs != dataset_base_dir])

    available_datasets <<- updated_datasets
    updateSelectInput(session, "dataset_choice", choices = updated_datasets, selected = ds_name)

    removeModal()
    showNotification(paste("Dataset", ds_name, "initialized successfully!"), type = "message")
  })
}
