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
  docs_dir <- if (is.null(context$paths$docs_dir)) "docs" else context$paths$docs_dir
  active_standardization_document <- reactiveVal(NULL)
  created_workspace_path <- reactiveVal(NULL)

  show_standardization_document <- function(type, dataset_dir = NULL) {
    result <- tryCatch({
      document <- read_standardization_document(type, docs_dir, dataset_dir)
      modal <- standardization_document_modal(document)
      active_standardization_document(document)
      showModal(modal)
      TRUE
    }, error = function(e) {
      showNotification(
        paste("Could not open documentation:", conditionMessage(e)),
        type = "error", duration = 15
      )
      FALSE
    })
    invisible(result)
  }

  selected_standardization_workspace <- function() {
    name <- input$dataset_choice
    if (is.null(name) || identical(name, "")) return(NULL)
    if (length(name) != 1L || is.na(name)) stop("Select one dataset workspace.", call. = FALSE)
    name <- sanitize_dataset_name(name)
    path <- file.path(dataset_base_dir, name)
    # The creation dialog can target another parent directory. Its checklist
    # still belongs to that exact workspace, not a same-named default folder.
    created_path <- created_workspace_path()
    if (!is.null(created_path) && identical(basename(created_path), name)) path <- created_path
    if (!dir.exists(path)) {
      stop("Selected workspace not found. Check its location in your editor: ", path, call. = FALSE)
    }
    normalizePath(path, winslash = "/", mustWork = TRUE)
  }

  observeEvent(input$btn_view_standardization_checklist, {
    workspace <- tryCatch(selected_standardization_workspace(), error = identity)
    if (inherits(workspace, "error")) {
      showNotification(conditionMessage(workspace), type = "error", duration = 15)
      return()
    }
    show_standardization_document("checklist", workspace)
  })

  observeEvent(input$btn_view_setup_guide, {
    show_standardization_document("user_guide")
  })

  observeEvent(input$btn_open_created_checklist, {
    req(created_workspace_path())
    show_standardization_document("checklist", created_workspace_path())
  })

  observeEvent(input$btn_create_dataset_checklist, {
    document <- active_standardization_document()
    req(document, identical(document$type, "checklist"), document$dataset_dir)
    result <- tryCatch(
      ensure_dataset_standardization_checklist(
        document$dataset_dir, file.path(docs_dir, "STANDARDIZATION_CHECKLIST.md")
      ),
      error = identity
    )
    if (inherits(result, "error")) {
      showNotification(conditionMessage(result), type = "error", duration = 15)
      return()
    }
    show_standardization_document("checklist", document$dataset_dir)
  })

  output$download_standardization_document <- downloadHandler(
    filename = function() {
      req(active_standardization_document())
      basename(active_standardization_document()$path)
    },
    content = function(file) {
      req(active_standardization_document())
      writeLines(active_standardization_document()$lines, file, useBytes = TRUE)
    },
    contentType = "text/markdown; charset=utf-8"
  )

  observeEvent(input$btn_select_standardization_prompt, {
    runjs(paste0(
      "const prompt = document.getElementById('standardization_prompt_text');",
      "if (prompt) { prompt.focus(); prompt.select(); }"
    ))
  })

  observeEvent(input$btn_copy_standardization_prompt, {
    runjs(paste0(
      "const prompt = document.getElementById('standardization_prompt_text');",
      "if (prompt) { prompt.focus(); prompt.select(); ",
      "if (navigator.clipboard && window.isSecureContext) {",
      "navigator.clipboard.writeText(prompt.value);",
      "} else { document.execCommand('copy'); } }"
    ))
    showNotification("Metadata prompt copied to the clipboard.", type = "message")
  })

  observeEvent(input$btn_open_standardization_guide, {
    removeModal()
    nav_select("dataset_setup_view", "standardization_guide")
  })


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

    storage_state <- tryCatch(
      load_or_initialize_dataset_storage_state(
        dataset_dir_path,
        dataset_name
      ),
      error = identity
    )
    if (inherits(storage_state, "error")) {
      record_pipeline_event(
        dataset_dir_path = dataset_dir_path,
        dataset = dataset_name,
        stage = "storage",
        event_type = "storage_state_load",
        outcome = "failed",
        reason = conditionMessage(storage_state)
      )
      showNotification(
        paste("Dataset storage state could not be loaded:", conditionMessage(storage_state)),
        type = "error",
        duration = 10
      )
      return()
    }
    storage_initialized <- isTRUE(attr(storage_state, "initialized"))
    if (storage_initialized) {
      attr(storage_state, "initialized") <- NULL
      storage_state <- save_dataset_storage_state_atomic(storage_state, dataset_dir_path)
    }
    storage_state <- reconcile_interrupted_dataset_storage(
      storage_state,
      dataset_dir_path
    )
    if (isTRUE(attr(storage_state, "storage_reconciled"))) {
      attr(storage_state, "storage_reconciled") <- NULL
      storage_state <- save_dataset_storage_state_atomic(storage_state, dataset_dir_path)
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
    state_cache_changes <- character()
    if (!dataset_storage_cache_is_retired(storage_state)) {
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
    rv$storage_state <- storage_state
    rv$storage_state_path <- file.path(dataset_dir_path, "storage_state.yaml")
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

    if (!(dataset_name %in% rv$session_logged_datasets)) {
      record_state_event(
        rv,
        stage = "session",
        event_type = "app_session_started",
        outcome = "started",
        parameters = list(
          session_id = rv$session_id,
          session_started_at = rv$session_started_at,
          process_id = Sys.getpid(),
          r_version = R.version.string,
          shiny_version = as.character(utils::packageVersion("shiny")),
          shiny_autoreload = if (is.null(getOption("shiny.autoreload"))) {
            "unset"
          } else {
            as.character(getOption("shiny.autoreload"))
          }
        )
      )
      rv$session_logged_datasets <- unique(c(rv$session_logged_datasets, dataset_name))
    }

    record_state_event(
      rv,
      stage = "dataset",
      event_type = "dataset_load",
      outcome = "completed",
      parameters = list(
        sample_count = length(sample_dir_paths),
        session_id = rv$session_id
      )
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
        } else state_cache_changes,
        storage_status = storage_state$status,
        storage_initialized = storage_initialized
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
    if (dataset_storage_cache_is_retired(storage_state)) {
      nav_hide("main_nav", target = "res_tab")
      nav_hide("main_nav", target = "anno_tab")
      nav_hide("main_nav", target = "cna_tab")
    } else {
      nav_show("main_nav", target = "res_tab")
      nav_show("main_nav", target = "anno_tab")
      nav_show("main_nav", target = "cna_tab")
    }
    nav_hide("main_nav", target = "dataset_tab")
    updateNavbarPage(session, "main_nav", selected = "menu_tab")

    showNotification("Dataset loaded successfully!", type = "default")
  })

  observeEvent(input$btn_change_dataset, {
    # Allow user to swap datasets - reveal selection UI
    record_state_event(
      rv,
      stage = "navigation",
      event_type = "change_dataset",
      outcome = "selected",
      parameters = list(
        source = "menu_tab",
        target = "dataset_tab",
        session_id = rv$session_id
      )
    )
    nav_show("main_nav", target = "dataset_tab")
    nav_hide("main_nav", target = "menu_tab")
    nav_hide("main_nav", target = "clipboard_tab")
    nav_hide("main_nav", target = "res_tab")
    nav_hide("main_nav", target = "anno_tab")
    updateNavbarPage(session, "main_nav", selected = "dataset_tab")
  })

  observeEvent(input$btn_create_dataset_ui, {
    arm_app_confirmation(rv, "create_dataset")
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

    if (!dir.exists(parent_dir)) {
      showNotification("The parent directory does not exist. Create or select an existing parent directory first.",
                       type = "error", duration = 10)
      return()
    }
    # Resolve the existing parent first. On Windows, normalizePath() for a
    # not-yet-created child can retain relative/mixed separators and falsely
    # report that a valid new workspace escapes its parent.
    resolved_parent <- normalizePath(parent_dir, winslash = "/", mustWork = TRUE)
    new_ds_path <- file.path(resolved_parent, ds_name)
    resolved_new_path <- new_ds_path
    parent_prefix <- paste0(sub("/+$", "", resolved_parent), "/")
    if (!startsWith(resolved_new_path, parent_prefix)) {
      showNotification("Invalid dataset location — path escapes the parent directory.",
                       type = "error", duration = 8)
      return()
    }

    # 1. Validation (existing check, now after the safety checks above)
    if (file.exists(new_ds_path)) {
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
    checklist_template_path <- file.path(docs_dir, "STANDARDIZATION_CHECKLIST.md")
    if (!file.exists(checklist_template_path)) {
      showNotification(
        paste("Checklist template is missing. Restore this file before creating a workspace:", checklist_template_path),
        type = "error", duration = 15
      )
      return()
    }

    if (!claim_app_confirmation(rv, "create_dataset")) return()
    if (!begin_app_action(rv, "create_dataset")) return()
    shinyjs::disable("btn_create_dataset_ui")
    shinyjs::disable("btn_confirm_create_ds")
    on.exit({
      finish_app_action(rv, "create_dataset")
      shinyjs::enable("btn_create_dataset_ui")
      shinyjs::enable("btn_confirm_create_ds")
    }, add = TRUE)

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

    checklist_result <- tryCatch(
      ensure_dataset_standardization_checklist(new_ds_path, checklist_template_path),
      error = identity
    )
    if (inherits(checklist_result, "error")) {
      record_pipeline_event(
        dataset_dir_path = new_ds_path, dataset = ds_name, stage = "dataset",
        event_type = "workspace_created", outcome = "failed",
        reason = conditionMessage(checklist_result)
      )
      showNotification(conditionMessage(checklist_result), type = "error", duration = 15)
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
    created_workspace_path(normalizePath(new_ds_path, winslash = "/", mustWork = TRUE))
    showModal(dataset_created_modal(ds_name, resolved_new_path))
  })
}
