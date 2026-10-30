test_that("F09 clustering targets one source sample and every configured resolution", {
  sample_root <- withr::local_tempdir()
  results_dir <- file.path(sample_root, "results")
  dir.create(results_dir)
  sample_names <- paste0("sample", 1:3)
  sample_dirs <- file.path(sample_root, "processed_data", sample_names)
  invisible(lapply(sample_dirs, dir.create, recursive = TRUE))

  paths_list <- list(
    sample_dir_paths = sample_dirs,
    cell_file_paths = file.path(sample_dirs, "Cells.csv"),
    expmat_file_paths = file.path(sample_dirs, "Exp_data_UMIcounts.mtx"),
    genes_file_paths = file.path(sample_dirs, "Genes.txt")
  )
  config <- list(params = list(
    pca_nv = 2,
    resolutions = c(0.25, 0.5, 1),
    seed = 3988,
    umap = list(spread = 1, min_dist = 0.1)
  ))

  test_env <- new.env(parent = environment(cluster_all_samples))
  targeted_cluster <- cluster_all_samples
  environment(targeted_cluster) <- test_env
  saved_files <- character()
  dependency_indices <- integer()
  state_events <- list()
  progress_events <- list()

  test_env$load_cells <- function(path) {
    sample_name <- basename(dirname(path))
    data.table::data.table(
      cell_name = paste0(sample_name, "_cell", 1:3),
      sample = sample_name
    )
  }
  test_env$load_filter_cells_expmat <- function(cells_path, expmat_path, genes_path, config) {
    cells <- test_env$load_cells(cells_path)
    list(
      cells_filt = cells,
      expmat_filt = matrix(
        1:6,
        nrow = 2,
        dimnames = list(c("gene1", "gene2"), cells$cell_name)
      )
    )
  }
  test_env$run_expmat_pca <- function(...) list(v = matrix(1:6, ncol = 2))
  test_env$run_expmat_umap <- function(...) matrix(1:6, ncol = 2)
  test_env$louvain_clustering <- function(exp_pca, exp_umap, cells, resolution, seed) {
    cells[, `:=`(umap1 = 1:3, umap2 = 3:1, clust = as.character(resolution))]
    cells
  }
  test_env$plot_clusters <- function(...) {
    ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) +
      ggplot2::geom_point()
  }
  test_env$cache_save_data <- function(data, filename, dataset_dir_path, dependencies, producer) {
    force(dependencies)
    saved_files <<- c(saved_files, filename)
    invisible(filename)
  }
  test_env$filter_cache_dependencies <- function(paths_list, sample_idx, config) {
    dependency_indices <<- c(dependency_indices, sample_idx)
    list(sample_idx = sample_idx)
  }
  test_env$clustering_cache_dependencies <- function(paths_list, sample_idx, config, resolution) {
    dependency_indices <<- c(dependency_indices, sample_idx)
    list(sample_idx = sample_idx, resolution = resolution)
  }

  targeted_cluster(
    paths_list,
    config,
    results_dir,
    sample_root,
    state_callback = function(sample_name, status, reason = NULL, details = NULL) {
      state_events[[length(state_events) + 1L]] <<- list(
        sample = sample_name,
        status = status,
        details = details
      )
    },
    progress_callback = function(...) {
      progress_events[[length(progress_events) + 1L]] <<- list(...)
    },
    sample_indices = 2
  )

  expect_identical(unique(vapply(state_events, `[[`, character(1), "sample")), "sample2")
  expect_identical(vapply(state_events, `[[`, character(1), "status"), c("in_progress", "completed"))
  expect_identical(state_events[[2]]$details$resolutions, c(0.25, 0.5, 1))
  expect_identical(state_events[[2]]$details$snapshot_filtering$schema_version, 1L)
  expect_equal(state_events[[2]]$details$snapshot_filtering$input_cells, 3)
  expect_equal(state_events[[2]]$details$snapshot_filtering$retained_cells, 3)
  expect_setequal(
    saved_files,
    c(
      "expmat_filt_sample2.qs2",
      "cells_filt_clust_res_0.25_sample2.qs2",
      "cells_filt_clust_res_0.5_sample2.qs2",
      "cells_filt_clust_res_1_sample2.qs2"
    )
  )
  expect_true(all(dependency_indices == 2L))
  expect_true(all(vapply(progress_events, `[[`, integer(1), "sample_index") == 1L))
  expect_true(all(vapply(progress_events, `[[`, integer(1), "sample_total") == 1L))
  expect_true(all(vapply(progress_events, `[[`, character(1), "sample_name") == "sample2"))
  expect_true(all(!grepl("sample1|sample3", saved_files)))

  saved_files <- character()
  dependency_indices <- integer()
  state_events <- list()
  progress_events <- list()
  targeted_cluster(
    paths_list, config, results_dir, sample_root,
    state_callback = function(...) state_events[[length(state_events) + 1L]] <<- list(...),
    progress_callback = function(...) progress_events[[length(progress_events) + 1L]] <<- list(...),
    sample_indices = c(1L, 3L)
  )
  expect_length(saved_files, 8L)
  expect_true(all(!grepl("sample2", saved_files)))
  expect_identical(unique(dependency_indices), c(1L, 3L))
  expect_identical(unique(vapply(progress_events, `[[`, integer(1), "sample_index")), 1:2)
  expect_true(all(vapply(progress_events, `[[`, integer(1), "sample_total") == 2L))
  expect_identical(unique(vapply(progress_events, `[[`, character(1), "sample_name")), c("sample1", "sample3"))

  expect_error(
    targeted_cluster(paths_list, config, results_dir, sample_root, sample_indices = c(2, 2)),
    "unique valid indices"
  )
  expect_error(
    targeted_cluster(paths_list, config, results_dir, sample_root, sample_indices = 4),
    "unique valid indices"
  )
})


test_that("F09 dashboard rerun isolates state, guards duplicates, and navigates to its sample", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  test_env <- new.env(parent = globalenv())
  sys.source(file.path(app_dir, "app/state.R"), envir = test_env)

  test_env$observeEvent <- shiny::observeEvent
  test_env$reactiveVal <- shiny::reactiveVal
  test_env$req <- shiny::req
  test_env$withProgress <- shiny::withProgress
  test_env$setProgress <- shiny::setProgress
  test_env$modalDialog <- shiny::modalDialog
  test_env$selectInput <- shiny::selectInput
  test_env$modalButton <- shiny::modalButton
  test_env$actionButton <- shiny::actionButton
  test_env$tagList <- shiny::tagList
  test_env$tags <- shiny::tags
  test_env$icon <- shiny::icon
  test_env$p <- shiny::p
  test_env$get_pipeline_step <- get_pipeline_step
  test_env$dataset_storage_cache_is_retired <- dataset_storage_cache_is_retired
  test_env$persist_pipeline_step_update <- persist_pipeline_step_update

  shown_modals <- list()
  navigation <- character()
  selected_resolution_index <- integer()
  invalidated_samples <- character()
  cluster_calls <- integer()
  fail_sample_three <- FALSE
  test_env$showModal <- function(ui, ...) {
    shown_modals[[length(shown_modals) + 1L]] <<- ui
    invisible(NULL)
  }
  test_env$removeModal <- function(...) invisible(NULL)
  test_env$showNotification <- function(...) "notification-id"
  test_env$removeNotification <- function(...) invisible(NULL)
  test_env$updateNavbarPage <- function(session, inputId, selected) {
    navigation <<- c(navigation, selected)
    invisible(NULL)
  }
  test_env$updateSelectInput <- function(session, inputId, selected, ...) {
    if (identical(inputId, "res_sample_idx")) {
      selected_resolution_index <<- c(selected_resolution_index, as.integer(selected))
    }
    invisible(NULL)
  }
  test_env$record_state_event <- function(...) invisible(NULL)
  test_env$cache_invalidate_sample <- function(sample_name, dataset_dir_path) {
    invalidated_samples <<- c(invalidated_samples, sample_name)
    paste0("cna_matrix_", sample_name, ".qs2")
  }
  test_env$cluster_all_samples <- function(
    paths_list,
    config,
    results_dir_path,
    dataset_dir_path,
    state_callback,
    progress_callback,
    sample_indices
  ) {
    cluster_calls <<- c(cluster_calls, sample_indices)
    sample_name <- basename(paths_list$sample_dir_paths[[sample_indices]])
    state_callback(sample_name, "in_progress")
    progress_callback(
      operation = "clustering",
      sample_name = sample_name,
      sample_index = 1L,
      sample_total = 1L,
      stage = "loading_filtering",
      detail = "Loading inputs",
      fraction = 0.1,
      elapsed_seconds = 0
    )
    if (isTRUE(fail_sample_three) && identical(sample_indices, 3L)) {
      state_callback(sample_name, "failed", reason = "synthetic clustering failure")
      stop("synthetic clustering failure", call. = FALSE)
    }
    state_callback(
      sample_name,
      "completed",
      details = list(resolutions = config$params$resolutions)
    )
    invisible(NULL)
  }
  sys.source(file.path(app_dir, "app/server/dashboard_server.R"), envir = test_env)

  sample_names <- paste0("sample", 1:3)
  state <- test_env$create_app_state(list(), session_id = "f09-test")
  pipeline_state <- new_pipeline_state("F09_Dataset", sample_names)
  pipeline_state <- transition_pipeline_step(
    pipeline_state,
    "standardization",
    "completed"
  )
  for (sample_name in sample_names) {
    for (step in PIPELINE_SAMPLE_STEPS) {
      pipeline_state <- transition_pipeline_step(
        pipeline_state,
        step,
        "completed",
        sample = sample_name,
        force = TRUE
      )
    }
  }

  state_dir <- withr::local_tempdir()
  sentinel_path <- file.path(state_dir, "sample3_previous_cache.qs2")
  writeLines("previous valid artifact", sentinel_path)
  shiny::isolate({
    state$paths_list <- list(
      sample_dir_paths = file.path(state_dir, "processed_data", sample_names)
    )
    state$dataset_config <- list(params = list(resolutions = c(0.25, 0.5, 1)))
    state$results_dir_path <- file.path(state_dir, "results")
    state$dataset_dir_path <- state_dir
    state$pipeline_state_path <- file.path(state_dir, "pipeline_state.yaml")
    state$pipeline_state <- pipeline_state
    state$live_selected_config <- setup_selected_config(sample_names)
  })
  sample1_before <- serialize(pipeline_state$samples$sample1, NULL)
  config_before <- serialize(shiny::isolate(state$live_selected_config), NULL)

  server <- function(input, output, session) {
    test_env$register_dashboard_server(
      input,
      output,
      session,
      state = state,
      context = list()
    )
  }

  shiny::testServer(server, {
    session$setInputs(btn_run_single_clustering = 1)
    expect_length(shown_modals, 1L)

    session$setInputs(single_clustering_sample = "2", confirm_run_single_clustering = 1)
    expect_identical(cluster_calls, 2L)
    expect_identical(invalidated_samples, "sample2")
    expect_identical(
      get_pipeline_step(state$pipeline_state, "clustering", "sample2")$status,
      "completed"
    )
    expect_identical(
      get_pipeline_step(state$pipeline_state, "resolution", "sample2")$status,
      "stale"
    )
    expect_identical(serialize(state$pipeline_state$samples$sample1, NULL), sample1_before)
    expect_identical(serialize(state$live_selected_config, NULL), config_before)

    session$setInputs(confirm_run_single_clustering = 2)
    expect_identical(cluster_calls, 2L)

    session$setInputs(btn_after_single_clustering_res = 1)
    expect_identical(selected_resolution_index, 2L)
    expect_identical(navigation, "res_tab")

    fail_sample_three <<- TRUE
    session$setInputs(btn_run_single_clustering = 2)
    session$setInputs(single_clustering_sample = "3", confirm_run_single_clustering = 3)
    expect_identical(cluster_calls, c(2L, 3L))
    expect_identical(
      get_pipeline_step(state$pipeline_state, "clustering", "sample3")$status,
      "failed"
    )
    expect_identical(invalidated_samples, "sample2")
    expect_identical(readLines(sentinel_path), "previous valid artifact")
    expect_identical(serialize(state$pipeline_state$samples$sample1, NULL), sample1_before)
  })
})


test_that("F09 single-sample action is visually secondary and explains invalidation", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  ui_text <- paste(
    readLines(file.path(app_dir, "app/ui/dashboard_ui.R"), warn = FALSE),
    collapse = "\n"
  )
  server_text <- paste(
    readLines(file.path(app_dir, "app/server/dashboard_server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(ui_text, '"btn_run_single_clustering"', fixed = TRUE)
  expect_match(ui_text, '"btn-outline-primary w-100 mt-2"', fixed = TRUE)
  expect_match(server_text, "saved resolution, DE, annotation, and CNA work stale", fixed = TRUE)
  expect_match(server_text, 'begin_app_action(rv, "single_sample_clustering")', fixed = TRUE)
  expect_match(server_text, "sample_indices = selected_index", fixed = TRUE)
  expect_match(server_text, 'updateSelectInput(session, "res_sample_idx"', fixed = TRUE)
})


test_that("F09 addendum reruns DE for the sample selected in Manual Annotation", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  test_env <- new.env(parent = globalenv())
  sys.source(file.path(app_dir, "app/state.R"), envir = test_env)

  test_env$observeEvent <- shiny::observeEvent
  test_env$req <- shiny::req
  test_env$modalDialog <- shiny::modalDialog
  test_env$modalButton <- shiny::modalButton
  test_env$actionButton <- shiny::actionButton
  test_env$tagList <- shiny::tagList
  test_env$showModal <- function(ui, ...) {
    modal_count <<- modal_count + 1L
    invisible(NULL)
  }
  test_env$removeModal <- function(...) invisible(NULL)
  notifications <- character()
  test_env$showNotification <- function(message, ...) {
    notifications <<- c(notifications, as.character(message))
    "notification-id"
  }
  test_env$removeNotification <- function(...) invisible(NULL)
  test_env$get_pipeline_step <- get_pipeline_step
  test_env$pipeline_step_readiness <- pipeline_step_readiness
  test_env$persist_pipeline_step_update <- persist_pipeline_step_update
  test_env$transition_pipeline_step <- transition_pipeline_step
  test_env$PIPELINE_STALE_DEPENDENCIES <- PIPELINE_STALE_DEPENDENCIES
  events <- list()
  test_env$record_state_event <- function(
    state,
    stage,
    event_type,
    outcome,
    sample = NULL,
    parameters = NULL,
    reason = NULL,
    ...
  ) {
    events[[length(events) + 1L]] <<- list(
      event_type = event_type,
      outcome = outcome,
      sample = sample,
      parameters = parameters,
      reason = reason
    )
    invisible(NULL)
  }
  de_indices <- integer()
  test_env$single_de_analysis <- function(sample_idx, ...) {
    de_indices <<- c(de_indices, sample_idx)
    invisible(NULL)
  }
  sys.source(file.path(app_dir, "app/server/single_de_server.R"), envir = test_env)

  sample_names <- c("sample1", "sample2")
  pipeline_state <- new_pipeline_state("F09_Addendum", sample_names)
  pipeline_state <- transition_pipeline_step(
    pipeline_state,
    "standardization",
    "completed"
  )
  for (sample_name in sample_names) {
    pipeline_state <- transition_pipeline_step(
      pipeline_state,
      "clustering",
      "completed",
      sample = sample_name,
      force = TRUE
    )
    pipeline_state <- transition_pipeline_step(
      pipeline_state,
      "resolution",
      "completed",
      sample = sample_name,
      force = TRUE
    )
  }
  pipeline_state <- transition_pipeline_step(
    pipeline_state,
    "differential_expression",
    "stale",
    sample = "sample2",
    reason = "Clustering was rerun; rerun differential expression.",
    force = TRUE
  )
  pipeline_state <- transition_pipeline_step(
    pipeline_state,
    "annotation",
    "stale",
    sample = "sample2",
    reason = "Differential expression must be rerun.",
    force = TRUE
  )

  state_dir <- withr::local_tempdir()
  state <- test_env$create_app_state(list(), session_id = "f09-addendum")
  shiny::isolate({
    state$paths_list <- list(
      sample_dir_paths = file.path(state_dir, "processed_data", sample_names)
    )
    state$dataset_config <- list(params = list())
    state$complete_markers <- data.table::data.table(cell_type = "TypeA", symbol = "GENE1")
    state$results_dir_path <- file.path(state_dir, "results")
    state$dataset_dir_path <- state_dir
    state$pipeline_state_path <- file.path(state_dir, "pipeline_state.yaml")
    state$pipeline_state <- pipeline_state
    state$live_selected_config <- setup_selected_config(sample_names)
    state$live_selected_config$resolutions$sample1 <- 0.5
    state$live_selected_config$resolutions$sample2 <- 1
  })
  sample1_before <- serialize(pipeline_state$samples$sample1, NULL)
  modal_count <- 0L

  server <- function(input, output, session) {
    test_env$register_single_sample_de_handlers(
      input = input,
      session = session,
      state = state,
      sample_input_id = "sample_idx",
      trigger_button_id = "btn_rerun_anno_single_de",
      confirm_button_id = "confirm_run_anno_single_de",
      action_key = "annotation_single_sample_de",
      source = "manual_annotation",
      protect_unsaved_annotation = TRUE
    )
  }

  shiny::testServer(server, {
    state$annotation_dirty <- TRUE
    session$setInputs(sample_idx = "2", btn_rerun_anno_single_de = 1)
    expect_identical(modal_count, 0L)
    expect_match(notifications[[length(notifications)]], "Save or discard")

    state$annotation_dirty <- FALSE
    session$setInputs(btn_rerun_anno_single_de = 2)
    expect_identical(modal_count, 1L)
    session$setInputs(confirm_run_anno_single_de = 1)

    expect_identical(de_indices, 2L)
    expect_identical(
      get_pipeline_step(state$pipeline_state, "differential_expression", "sample2")$status,
      "completed"
    )
    expect_identical(
      get_pipeline_step(state$pipeline_state, "annotation", "sample2")$reason,
      "Differential expression was rerun; review and save annotations again."
    )
    expect_identical(serialize(state$pipeline_state$samples$sample1, NULL), sample1_before)
    expect_true(any(vapply(
      events,
      function(event) identical(event$parameters$source, "manual_annotation"),
      logical(1)
    )))

    session$setInputs(confirm_run_anno_single_de = 2)
    expect_identical(de_indices, 2L)
  })
})


test_that("F09 addendum places targeted DE above the Manual Annotation back button", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  ui_text <- paste(
    readLines(file.path(app_dir, "app/ui/annotation_ui.R"), warn = FALSE),
    collapse = "\n"
  )
  annotation_server <- paste(
    readLines(file.path(app_dir, "app/server/annotation_server.R"), warn = FALSE),
    collapse = "\n"
  )
  resolution_server <- paste(
    readLines(file.path(app_dir, "app/server/resolution_server.R"), warn = FALSE),
    collapse = "\n"
  )

  de_position <- regexpr('"btn_rerun_anno_single_de"', ui_text, fixed = TRUE)[[1]]
  back_position <- regexpr('"btn_back_menu_2"', ui_text, fixed = TRUE)[[1]]
  expect_gt(de_position, 0L)
  expect_lt(de_position, back_position)
  expect_match(ui_text, '"Rerun DE for Selected Sample"', fixed = TRUE)
  expect_match(annotation_server, "register_single_sample_de_handlers", fixed = TRUE)
  expect_match(annotation_server, "protect_unsaved_annotation = TRUE", fixed = TRUE)
  expect_match(resolution_server, "register_single_sample_de_handlers", fixed = TRUE)
})
