test_that("F05 retries the selected sample when DE becomes ready", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("qs2")
  suppressPackageStartupMessages(library(shiny))

  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  dataset_dir <- withr::local_tempdir()
  sample_dir <- file.path(dataset_dir, "processed_data", "sample1")
  dir.create(sample_dir, recursive = TRUE)
  cells_path <- file.path(sample_dir, "Cells.csv")
  raw_cells <- data.table::data.table(
    cell_name = c("cell1", "cell2"),
    sample = "sample1",
    complexity = c(10, 12),
    cell_type = c("Saved A", "Saved B")
  )
  data.table::fwrite(raw_cells, cells_path)

  test_env <- new.env(parent = globalenv())
  for (function_name in c(
    "get_pipeline_step", "pipeline_step_readiness",
    "pipeline_status_presentation", "load_cells",
    "validate_annotation_cell_alignment", "persist_pipeline_step_update",
    "cache_save_data", "cache_invalidate_sample"
  )) {
    test_env[[function_name]] <- get(function_name, inherits = TRUE)
  }
  sys.source(file.path(app_dir, "app/state.R"), envir = test_env)
  load_calls <- 0L
  test_env$cell_type_annotation_setup <- function(...) {
    load_calls <<- load_calls + 1L
    list(
      cells_filt = data.table::data.table(
        cell_name = c("cell1", "cell2"),
        sample = "sample1",
        complexity = c(10, 12),
        umap1 = c(0, 1),
        umap2 = c(1, 0),
        clust = c(0L, 1L)
      ),
      all_matches = data.table::data.table(clust = integer(), gene = character())
    )
  }
  test_env$nav_select <- function(...) invisible(NULL)
  test_env$record_state_event <- function(...) invisible(NULL)
  test_env$showNotification <- function(...) "notification"
  test_env$removeNotification <- function(...) invisible(NULL)
  sys.source(
    file.path(app_dir, "app/server/single_de_server.R"),
    envir = test_env
  )
  sys.source(
    file.path(app_dir, "app/server/annotation_server.R"),
    envir = test_env
  )

  pipeline_state <- new_pipeline_state("Synthetic_Dataset", "sample1")
  pipeline_state <- transition_pipeline_step(
    pipeline_state,
    "differential_expression",
    "stale",
    sample = "sample1",
    reason = "Differential expression is being rerun.",
    force = TRUE
  )
  pipeline_state <- transition_pipeline_step(
    pipeline_state,
    "annotation",
    "stale",
    sample = "sample1",
    reason = "Differential expression was rerun; review and save annotations again.",
    force = TRUE
  )
  state <- test_env$create_app_state(list(), session_id = "f05-test")
  state$paths_list <- list(
    sample_dir_paths = sample_dir,
    cell_file_paths = cells_path
  )
  state_path <- file.path(dataset_dir, "pipeline_state.yaml")
  pipeline_state <- save_pipeline_state_at_path(pipeline_state, state_path)
  state$pipeline_state <- pipeline_state
  state$pipeline_state_path <- state_path
  selected_config <- list(
    resolutions = list(sample1 = 0.5),
    sample_notes = list(sample1 = ""),
    cna_ref_cells = list(sample1 = list()),
    cna_pot_mal_cells = list(sample1 = list())
  )
  state$live_selected_config <- selected_config
  state$dataset_config <- list()
  state$complete_markers <- data.table::data.table(
    cell_type = "Marker type",
    gene = "GENE1"
  )
  state$samples_config <- list(samples = list(list(
    sample = "sample1",
    cancer_type = "Synthetic"
  )))
  results_dir <- file.path(dataset_dir, "results")
  dir.create(file.path(results_dir, "sample1", "2_de_plots"), recursive = TRUE)
  state$results_dir_path <- results_dir
  state$dataset_dir_path <- dataset_dir
  selected_config_path <- file.path(dataset_dir, "selected_config.yaml")
  yaml::write_yaml(selected_config, selected_config_path)
  state$selected_config_path <- selected_config_path
  state$config <- list(selected = selected_config)

  server <- function(input, output, session) {
    test_env$register_annotation_server(input, output, session, state, list())
  }

  shiny::testServer(server, {
    session$setInputs(main_nav = "anno_tab", sample_idx = "1")
    session$flushReact()
    expect_identical(load_calls, 0L)
    expect_null(state$annotation_loaded_index)
    expect_null(state$cells_filt)

    state$pipeline_state <- transition_pipeline_step(
      state$pipeline_state,
      "differential_expression",
      "completed",
      sample = "sample1",
      force = TRUE
    )
    session$flushReact()

    expect_identical(load_calls, 1L)
    expect_identical(state$annotation_loaded_index, 1)
    expect_identical(
      as.character(state$cells_filt$cell_type),
      c("Saved A", "Saved B")
    )

    session$setInputs(save_btn = 1)
    session$flushReact()
    expect_identical(
      get_pipeline_step(state$pipeline_state, "annotation", "sample1")$status,
      "completed"
    )
    expect_identical(
      get_pipeline_step(state$pipeline_state, "cna_configuration", "sample1")$status,
      "not_started"
    )

    state$annotation_dirty <- TRUE
    session$setInputs(
      cna_refs_input = "Saved A",
      cna_pot_mal_input = "Saved B",
      btn_save_refs = 1
    )
    session$flushReact()
    expect_identical(
      get_pipeline_step(state$pipeline_state, "cna_configuration", "sample1")$status,
      "not_started"
    )
    session$setInputs(btn_omit_cna = 1)
    session$flushReact()
    expect_false("omit_cna" %in% state$open_confirmations)

    state$annotation_dirty <- FALSE
    session$setInputs(btn_omit_cna = 2)
    session$flushReact()
    expect_true("omit_cna" %in% state$open_confirmations)
    session$setInputs(btn_confirm_omit_cna = 1)
    session$flushReact()
    expect_identical(
      get_pipeline_step(state$pipeline_state, "cna_configuration", "sample1")$status,
      "skipped"
    )

    session$setInputs(btn_save_refs = 2)
    session$flushReact()
    expect_identical(
      get_pipeline_step(state$pipeline_state, "cna_configuration", "sample1")$status,
      "completed"
    )
  })
})


test_that("F05 rejects saved labels whose cells do not align", {
  clustered <- data.frame(cell_name = c("cell1", "cell2"))
  saved <- data.frame(cell_name = c("cell1", "different-cell"))
  expect_error(
    validate_annotation_cell_alignment(clustered, saved),
    "do not align"
  )
  expect_no_error(validate_annotation_cell_alignment(
    clustered,
    data.frame(cell_name = c("cell2", "cell1", "filtered-out-cell"))
  ))
  expect_error(
    validate_annotation_cell_alignment(
      clustered,
      data.frame(cell_name = c("cell1", "cell1", "cell2"))
    ),
    "do not align"
  )
})
