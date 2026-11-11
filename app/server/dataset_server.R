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
  session_workspace_paths <- reactiveVal(list())
  directory_browser <- reactiveVal(NULL)
  import_error <- reactiveVal(NULL)
  workspace_path <- function(name) {
    registered <- session_workspace_paths()
    if (name %in% names(registered)) registered[[name]] else file.path(dataset_base_dir, name)
  }
  workspace_choices <- function() {
    unique(c(basename(dataset_workspace_directories(dataset_base_dir)), names(session_workspace_paths())))
  }

  output$download_input_specification <- downloadHandler(
    filename = function() "README.md",
    content = function(file) {
      path <- file.path(dirname(docs_dir), "README.md")
      if (!file.copy(path, file)) stop("README.md could not be downloaded; open it in the repository.")
    }
  )
  output$dataset_import_report <- renderUI({
    message <- import_error()
    if (is.null(message)) return(NULL)
    div(class = "alert alert-danger mt-3",
      tags$strong("Dataset could not be created"),
      tags$pre(message, style = "white-space: pre-wrap; overflow-wrap: anywhere; max-height: 240px; overflow-y: auto;"))
  })
  output$dataset_import_paths <- renderUI({
    req(input$new_ds_name, input$new_ds_source, input$new_ds_location)
    source <- normalizePath(input$new_ds_source, winslash = "/", mustWork = FALSE)
    parent <- normalizePath(input$new_ds_location, winslash = "/", mustWork = FALSE)
    div(class = "small mt-3",
      p(tags$strong("Resolved source: "), tags$code(source,
        style = "white-space: normal; overflow-wrap: anywhere;")),
      p(tags$strong("Workspace: "), tags$code(file.path(parent, input$new_ds_name),
        style = "white-space: normal; overflow-wrap: anywhere;")))
  })

  selected_workspace <- function() {
    name <- input$dataset_choice
    if (is.null(name) || identical(name, "")) return(NULL)
    if (length(name) != 1L || is.na(name)) stop("Select one dataset workspace.", call. = FALSE)
    name <- sanitize_dataset_name(name)
    path <- workspace_path(name)
    if (!dir.exists(path)) stop("Selected workspace not found: ", path, call. = FALSE)
    normalizePath(path, winslash = "/", mustWork = TRUE)
  }
  output$workspace_origin_reminder <- renderUI({
    workspace <- tryCatch(selected_workspace(), error = function(e) NULL)
    if (is.null(workspace)) return(NULL)
    path <- file.path(workspace, config$config_files$dataset)
    if (!file.exists(path)) return(NULL)
    dataset_config <- tryCatch(yaml::read_yaml(path), error = function(e) NULL)
    if (is.null(dataset_config)) return(NULL)
    reminder <- dataset_origin_reminder(dataset_config)
    if (!is.null(reminder)) tags$p(reminder, class = "small text-body-secondary mb-2")
  })

  load_dataset <- function(dataset_name, dataset_dir_path = workspace_path(dataset_name)) {
    if (isTRUE(rv$annotation_dirty) || length(rv$active_actions) > 0L) {
      showNotification("Save or discard annotation changes and finish the current action before loading a dataset.", type = "warning")
      return()
    }
    if (!begin_app_action(rv, "dataset_load")) return()
    on.exit(finish_app_action(rv, "dataset_load"), add = TRUE)
    clear_app_dataset(rv)
    for (input_id in c("sample_idx", "res_sample_idx", "cna_sample_idx")) {
      shiny::freezeReactiveValue(input, input_id)
      updateSelectInput(session, input_id, choices = character())
    }
    removeModal()

    id <- showNotification(paste("Loading workspace:", dataset_name), duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)


    # 1. Verify Dataset Files
    dataset_config_path <- file.path(dataset_dir_path, config$config_files$dataset)
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

    if (file.exists(selected_config_path)) {
      selected_config <- yaml::read_yaml(selected_config_path)
    } else {
      # Initialize empty state if it's a new dataset
      selected_config <- list(resolutions = list(), cna_ref_cells = list(), cna_pot_mal_cells = list())
    }

    # 3. Read the authoritative sample CSV once per load. Metadata and all
    # sample paths share its exact row order; only input structure is checked.
    processed_dir_path <- file.path(dataset_dir_path, config$dataset_paths$processed_dir)
    input_check <- tryCatch(
      check_prepared_data(
        processed_dir_path,
        std_names = if (is.null(dataset_config$std_names)) list() else dataset_config$std_names
      ),
      error = identity
    )
    # Archived workspaces remain reviewable when retained sample files are
    # damaged. Their existing archive audit blocks editing/export as needed.
    # CSV/schema/membership failures still block loading; never infer metadata.
    archived_input_review <- FALSE
    if (!inherits(input_check, "error") && !isTRUE(input_check$valid) &&
        all(!is.na(input_check$errors$sample)) &&
        all(input_check$errors$code %in% c(
          "missing_file", "empty_file", "unreadable_file", "not_a_file",
          "missing_sample_directory", "unreadable_directory"
        ))) {
      stored <- tryCatch(
        load_dataset_storage_state(dataset_dir_path, dataset_name, recover = FALSE),
        error = function(e) NULL
      )
      archived_input_review <- dataset_storage_cache_is_retired(stored)
    }
    if (inherits(input_check, "error") ||
        (!isTRUE(input_check$valid) && !archived_input_review)) {
      report <- if (inherits(input_check, "error")) {
        paste("Input structure check failed:", conditionMessage(input_check))
      } else input_check$message
      record_pipeline_event(
        dataset_dir_path = dataset_dir_path,
        dataset = dataset_name,
        stage = "dataset",
        event_type = "dataset_load",
        outcome = "failed",
        reason = report
      )
      showNotification("Input structure check failed. Review the input report.", type = "error", duration = 10)
      showModal(modalDialog(
        title = "Input structure check failed",
        tags$pre(report, style = "white-space: pre-wrap; overflow-wrap: anywhere; max-height: 60vh; overflow-y: auto;"),
        easyClose = TRUE, footer = modalButton("Close")
      ))
      return()
    }
    samples <- input_check$samples
    paths_list <- input_check$paths_list
    if (archived_input_review) {
      dirs <- file.path(processed_dir_path, samples$sample)
      paths_list <- list(
        sample_dir_paths = dirs,
        cell_file_paths = file.path(dirs, dataset_config$std_names$cells),
        expmat_file_paths = file.path(dirs, dataset_config$std_names$expmat),
        genes_file_paths = file.path(dirs, dataset_config$std_names$genes)
      )
    }
    sample_dir_paths <- paths_list$sample_dir_paths

    results_dir_path <- file.path(dataset_dir_path, config$dataset_paths$results_dir)

    dir.create(results_dir_path, showWarnings = FALSE)


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
    clustering_recovered <- character()
    if (!dataset_storage_cache_is_retired(storage_state)) {
      recovered_state <- tryCatch(reconcile_interrupted_clustering(
        pipeline_state, file.path(dataset_dir_path, state_filename)), error = identity)
      if (inherits(recovered_state, "error")) {
        showNotification(paste("Clustering recovery could not be checked:", conditionMessage(recovered_state)), type = "error", duration = 15)
        return()
      }
      pipeline_state <- recovered_state
      clustering_recovered <- attr(pipeline_state, "clustering_recovered")
      attr(pipeline_state, "clustering_recovered") <- NULL
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
    rv$sample_metadata <- samples
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
        input_structure_valid = isTRUE(input_check$valid),
        archived_input_review = archived_input_review,
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
    updateSelectInput(session, "cna_sample_idx", choices = s_choices, selected = 1)

    # 7. Reveal App Tabs & Jump to Dashboard
    nav_show("main_nav", target = "menu_tab")
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
    if (length(clustering_recovered)) {
      record_state_event(rv, stage = "clustering", event_type = "interrupted_clustering_recovered",
        outcome = "recovered", parameters = list(samples = clustering_recovered, mode = "owner_ended"))
      showNotification(paste("Interrupted clustering is ready to retry:", paste(clustering_recovered, collapse = ", ")),
        type = "warning", duration = 15)
    }
    invisible(TRUE)
  }

  observeEvent(input$btn_load_dataset, {
    req(input$dataset_choice)
    load_dataset(input$dataset_choice)
  })

  observeEvent(input$btn_change_dataset, {
    if (isTRUE(rv$annotation_dirty) || length(rv$active_actions) > 0L) {
      showNotification("Save or discard annotation changes and finish the current action before changing datasets.", type = "warning")
      return()
    }
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
    clear_app_dataset(rv)
    removeModal()
    for (input_id in c("sample_idx", "res_sample_idx", "cna_sample_idx")) {
      shiny::freezeReactiveValue(input, input_id)
      updateSelectInput(session, input_id, choices = character())
    }
    nav_show("main_nav", target = "dataset_tab")
    nav_hide("main_nav", target = "menu_tab")
    nav_hide("main_nav", target = "res_tab")
    nav_hide("main_nav", target = "anno_tab")
    nav_hide("main_nav", target = "cna_tab")
    updateNavbarPage(session, "main_nav", selected = "dataset_tab")
  })

  set_browser_path <- function(path, target) {
    if (!dir.exists(path) || file.access(path, 4L) != 0L) {
      showNotification("Select a readable existing directory.", type = "error")
      return()
    }
    directory_browser(list(path = normalizePath(path, winslash = "/", mustWork = TRUE), target = target))
  }
  browse_target <- function(target, path) {
    if (is.null(path) || !nzchar(path) || !dir.exists(path)) path <- dataset_base_dir
    set_browser_path(path, target)
  }
  output$dataset_directory_browser <- renderUI({
    browser <- directory_browser()
    if (is.null(browser)) return(NULL)
    dataset_directory_browser_ui(browser$path, browser$target)
  })
  observeEvent(input$btn_browse_dataset_source, {
    browse_target("new_ds_source", input$new_ds_source)
  })
  observeEvent(input$btn_browse_dataset_parent, {
    browse_target("new_ds_location", input$new_ds_location)
  })
  observeEvent(input$btn_dataset_browser_go, {
    req(directory_browser(), input$dataset_browser_path)
    set_browser_path(input$dataset_browser_path, directory_browser()$target)
  })
  observeEvent(input$btn_dataset_browser_up, {
    req(directory_browser())
    set_browser_path(dirname(directory_browser()$path), directory_browser()$target)
  })
  observeEvent(input$btn_dataset_browser_home, {
    req(directory_browser())
    set_browser_path(path.expand("~"), directory_browser()$target)
  })
  observeEvent(input$btn_dataset_browser_datasets, {
    req(directory_browser())
    set_browser_path(dataset_base_dir, directory_browser()$target)
  })
  observeEvent(input$btn_dataset_browser_open, {
    req(directory_browser(), input$dataset_browser_child)
    # Only descend into an immediate directory actually listed by this browser.
    children <- list.dirs(directory_browser()$path, recursive = FALSE, full.names = TRUE)
    if (input$dataset_browser_child %in% children) {
      set_browser_path(input$dataset_browser_child, directory_browser()$target)
    }
  })
  observeEvent(input$btn_dataset_browser_select, {
    req(directory_browser())
    browser <- directory_browser()
    updateTextInput(session, browser$target, value = browser$path)
    directory_browser(NULL)
  })
  observeEvent(input$btn_dataset_browser_cancel, { directory_browser(NULL) })

  observeEvent(input$btn_create_dataset_ui, {
    if (isTRUE(rv$annotation_dirty) || length(rv$active_actions) > 0L) {
      showNotification("Save or discard annotation changes and finish the current action before creating a dataset.", type = "warning")
      return()
    }
    directory_browser(NULL)
    import_error(NULL)
    arm_app_confirmation(rv, "create_dataset")
    showModal(dataset_import_dialog(dataset_base_dir))
  })

  observeEvent(input$btn_cancel_create_ds, {
    if (length(rv$active_actions) > 0L) return()
    claim_app_confirmation(rv, "create_dataset")
    directory_browser(NULL)
    import_error(NULL)
    removeModal()
  })

  observeEvent(input$btn_confirm_create_ds, {
    if (isTRUE(rv$annotation_dirty) || length(rv$active_actions) > 0L) return()
    if (!claim_app_confirmation(rv, "create_dataset")) return()
    if (!begin_app_action(rv, "create_dataset")) return()
    shinyjs::disable("btn_create_dataset_ui")
    shinyjs::disable("btn_confirm_create_ds")
    on.exit({
      finish_app_action(rv, "create_dataset")
      shinyjs::enable("btn_create_dataset_ui")
      shinyjs::enable("btn_confirm_create_ds")
    }, add = TRUE)

    imported <- tryCatch({
      name <- sanitize_dataset_name(.pipeline_value_or(input$new_ds_name, ""))
      if (name %in% workspace_choices()) {
        stop("A dataset with this name is already available in this session; choose another name.", call. = FALSE)
      }
      started <- Sys.time()
      shiny::withProgress(message = "Creating dataset from prepared data", value = 0, {
        import_prepared_dataset(
          trimws(.pipeline_value_or(input$new_ds_source, "")),
          trimws(.pipeline_value_or(input$new_ds_location, "")), name,
          config, file.path(templates_dir, "dataset_config_template.yaml"),
          progress = function(copied, total, path) {
            elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
            shiny::setProgress(value = if (total > 0) copied / total else 0,
              detail = sprintf("%s | %.1f / %.1f MiB copied | %.0fs elapsed",
                basename(path), copied / 1024^2, total / 1024^2, elapsed))
          }
        )
      })
    }, error = identity)
    if (inherits(imported, "error")) {
      import_error(conditionMessage(imported))
      showNotification(conditionMessage(imported), type = "error", duration = 15)
      # Keep the draft and browser available for correction/retry. The consumed
      # confirmation prevents duplicate delivery after a successful publication.
      arm_app_confirmation(rv, "create_dataset")
      return()
    }
    registered <- session_workspace_paths()
    registered[[basename(imported$path)]] <- imported$path
    session_workspace_paths(registered)
    available_datasets <<- workspace_choices()
    updateSelectInput(session, "dataset_choice", choices = available_datasets, selected = basename(imported$path))
    directory_browser(NULL)
    removeModal()
    # Loading is the same guarded path used by the Load Dataset button. Release
    # the creation action first so it does not conflict with the load action.
    finish_app_action(rv, "create_dataset")
    if (isTRUE(load_dataset(basename(imported$path), imported$path))) {
      showNotification(paste("Workspace created:", imported$path), type = "message", duration = 10)
    } else {
      showNotification("Workspace was created but could not be opened. Correct the reported issue and load it again.", type = "error", duration = 15)
    }
  })
}
