make_subset_clustering_fixture <- function(root, real_cache = FALSE) {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  env <- new.env(parent = environment())
  sys.source(file.path(app_dir, "app/state.R"), env)
  samples <- paste0("sample", 1:7)
  pipeline <- new_pipeline_state("Subset_Clustering", samples)
  pipeline <- transition_pipeline_step(pipeline, "standardization", "completed")
  for (sample in samples) for (step in PIPELINE_SAMPLE_STEPS) {
    pipeline <- transition_pipeline_step(pipeline, step, "completed", sample, force = TRUE)
  }
  statuses <- c("completed", "stale", "failed", "not_started", "in_progress", "incomplete", "completed")
  for (i in seq_along(samples)) {
    pipeline <- transition_pipeline_step(pipeline, "clustering", statuses[i], samples[i],
      reason = if (statuses[i] %in% c("stale", "failed", "incomplete")) "Synthetic clustering finding" else NULL, force = TRUE)
  }
  # Downstream staleness alone must not select a completed clustering sample.
  pipeline <- transition_pipeline_step(pipeline, "annotation", "stale", "sample1", reason = "DE was rerun", force = TRUE)
  state <- env$create_app_state(list(), session_id = "subset-test")
  state$paths_list <- list(sample_dir_paths = file.path(root, "processed_data", samples))
  state$dataset_dir_path <- root
  state$results_dir_path <- file.path(root, "results")
  state$dataset_config <- list(params = list(resolutions = c(0.5, 1)))
  path <- file.path(root, "pipeline_state.yaml")
  state$pipeline_state <- save_pipeline_state_at_path(pipeline, path)
  state$pipeline_state_path <- path
  state$storage_state <- new_dataset_storage_state("Subset_Clustering")
  selected <- setup_selected_config(samples)
  selected$resolutions <- stats::setNames(as.list(rep(0.5, length(samples))), samples)
  state$live_selected_config <- selected
  yaml::write_yaml(selected, file.path(root, "selected_config.yaml"))
  env$artifacts <- stats::setNames(file.path(root, paste0(samples, "-plot.txt")), samples)
  for (sample in samples) {
    writeLines(paste("Original", sample), env$artifacts[[sample]])
    if (real_cache) {
      cache_save_data(data.table::data.table(gene = "G1", chr = "01", start_pos = 1L, cell1 = 0.2),
        paste0("cna_matrix_", sample, ".qs2"), root)
    }
  }
  env$checkboxes <- list()
  env$updates <- list()
  env$modals <- character()
  env$notifications <- character()
  env$calls <- list()
  env$progress <- list()
  env$invalidated <- character()
  env$events <- list()
  env$navigation <- character()
  env$selected_indices <- integer()
  env$fail_sample <- NULL
  env$checkboxGroupInput <- function(inputId, label, choices, selected, ...) {
    env$checkboxes <- c(env$checkboxes, list(list(id = inputId, choices = choices, selected = selected)))
    shiny::checkboxGroupInput(inputId, label, choices, selected, ...)
  }
  env$updateCheckboxGroupInput <- function(session, inputId, selected, ...) {
    env$updates <- c(env$updates, list(list(id = inputId, selected = selected)))
  }
  env$showModal <- function(ui, ...) env$modals <- c(env$modals, as.character(ui))
  env$removeModal <- env$removeNotification <- function(...) invisible(NULL)
  env$showNotification <- function(ui, ...) {
    env$notifications <- c(env$notifications, as.character(ui))
    "notification"
  }
  env$setProgress <- function(value, detail, ...) {
    env$progress <- c(env$progress, list(list(value = value, detail = detail)))
  }
  env$record_state_event <- function(..., parameters = NULL) {
    env$events <- c(env$events, list(parameters))
  }
  env$pipeline_status_overview_ui <- function(...) shiny::tags$div("Overview")
  env$cache_load_data <- env$cache_check_valid <- function(...) stop("Unexpected scientific-cache read in selection")
  real_invalidate <- cache_invalidate_sample
  env$cache_invalidate_sample <- function(sample_name, dataset_dir_path) {
    env$invalidated <- c(env$invalidated, sample_name)
    if (real_cache) real_invalidate(sample_name, dataset_dir_path) else character()
  }
  env$updateNavbarPage <- function(session, inputId, selected) env$navigation <- c(env$navigation, selected)
  env$updateSelectInput <- function(session, inputId, selected, ...) {
    if (inputId == "res_sample_idx") env$selected_indices <- c(env$selected_indices, selected)
  }
  env$cluster_all_samples <- function(paths_list, config, results_dir_path, dataset_dir_path,
                                    state_callback, progress_callback, sample_indices) {
    env$calls <- c(env$calls, list(sample_indices))
    for (position in seq_along(sample_indices)) {
      sample <- basename(paths_list$sample_dir_paths[[sample_indices[position]]])
      progress_callback(operation = "clustering", sample_name = sample,
        sample_index = position, sample_total = length(sample_indices), stage = "loading_filtering",
        detail = "Loading inputs", fraction = (position - 1) / length(sample_indices))
      state_callback(sample, "in_progress")
      if (identical(sample, env$fail_sample)) {
        state_callback(sample, "failed", reason = "Synthetic subset failure")
        stop("Synthetic subset failure")
      }
      writeLines(paste("Recomputed", sample, paste(config$params$resolutions, collapse = ",")), env$artifacts[[sample]])
      state_callback(sample, "completed", details = list(resolutions = config$params$resolutions))
    }
  }
  sys.source(file.path(app_dir, "app/server/dashboard_server.R"), env)
  env$state <- state
  env$server <- function(input, output, session) env$register_dashboard_server(input, output, session, state, list())
  env
}

set_subset_checks <- function(session, fixture, samples) {
  id <- tail(fixture$checkboxes, 1)[[1]]$id
  do.call(session$setInputs, stats::setNames(list(samples), id))
}

test_that("F09 subset presets use clustering alone and validation preserves dataset order", {
  fixture <- make_subset_clustering_fixture(withr::local_tempdir())
  pipeline <- shiny::isolate(fixture$state$pipeline_state)
  samples <- names(pipeline$samples)
  before <- serialize(pipeline, NULL)
  expect_identical(clustering_selection_preset(pipeline, samples, "all"), samples)
  expect_identical(clustering_selection_preset(pipeline, samples, "stale"), "sample2")
  expect_identical(clustering_selection_preset(pipeline, samples, "incomplete"), c("sample2", "sample3", "sample4"))
  expect_identical(clustering_selection_preset(pipeline, samples, "clear"), character())
  expect_identical(validate_clustering_selection(pipeline, c("sample4", "sample2"), samples), c(2L, 4L))
  expect_error(validate_clustering_selection(pipeline, character(), samples), "at least one")
  expect_error(validate_clustering_selection(pipeline, c("sample2", "missing"), samples), "invalid or duplicate")
  expect_error(validate_clustering_selection(pipeline, c("sample2", "sample2"), samples), "invalid or duplicate")
  expect_error(validate_clustering_selection(pipeline, NA_character_, samples), "invalid or duplicate")
  expect_error(validate_clustering_selection(pipeline, "sample5", samples), "already in progress")
  expect_identical(serialize(pipeline, NULL), before)
})

test_that("F09 checklist defaults, shortcuts, live confirmation and fresh dialog inputs work", {
  suppressPackageStartupMessages(library(shiny))
  fixture <- make_subset_clustering_fixture(withr::local_tempdir())
  shiny::testServer(fixture$server, {
    session$setInputs(btn_run_clustering = 1)
    spec <- tail(fixture$checkboxes, 1)[[1]]
    expect_identical(spec$selected, paste0("sample", 1:7))
    expect_match(names(spec$choices)[2], "sample2 (stale)", fixed = TRUE)
    expect_match(tail(fixture$modals, 1), "Select incomplete", fixed = TRUE)
    set_subset_checks(session, fixture, character())
    expect_match(output$clustering_run_control$html, "disabled", fixed = TRUE)
    expect_match(output$clustering_selection_summary$html, "Select at least one", fixed = TRUE)
    for (preset in c("all", "stale", "incomplete", "clear")) {
      do.call(session$setInputs, stats::setNames(list(1), paste0("clustering_select_", preset)))
      expected <- clustering_selection_preset(fixture$state$pipeline_state, paste0("sample", 1:7), preset)
      expect_identical(tail(fixture$updates, 1)[[1]], list(id = spec$id, selected = expected))
    }
    set_subset_checks(session, fixture, c("sample4", "sample2"))
    expect_match(output$clustering_run_control$html, "Run clustering for 2 selected samples", fixed = TRUE)
    expect_false(grepl("disabled=", output$clustering_run_control$html, fixed = TRUE))
    expect_match(output$clustering_selection_summary$html, "sample2, sample4", fixed = TRUE)
    expect_match(output$clustering_selection_summary$html, "unselected samples are unchanged", fixed = TRUE)
    session$setInputs(btn_run_clustering = 2)
    expect_false(identical(spec$id, tail(fixture$checkboxes, 1)[[1]]$id))
    # The previous dialog's values cannot silently narrow a newly opened run.
    session$setInputs(confirm_run_clustering = 1)
    expect_length(fixture$calls, 0)
    expect_match(output$clustering_run_control$html, "disabled", fixed = TRUE)
  })
})

test_that("F09 selected-only reruns preserve other samples' states, decisions and real cache artifacts", {
  skip_if_not_installed("qs2")
  suppressPackageStartupMessages(library(shiny))
  root <- withr::local_tempdir()
  fixture <- make_subset_clustering_fixture(root, real_cache = TRUE)
  state <- fixture$state
  shiny::testServer(fixture$server, {
    unselected <- paste0("sample", c(1, 3, 5, 6, 7))
    original <- serialize(state$pipeline_state$samples[unselected], NULL)
    cache_paths <- file.path(root, "cache", paste0("cna_matrix_", unselected, ".qs2"))
    artifacts <- c(unname(fixture$artifacts[unselected]), cache_paths, file.path(root, "selected_config.yaml"))
    before_files <- tools::md5sum(artifacts)
    manifest_before <- load_cache_manifest(root)$artifacts[paste0("cna_matrix_", unselected, ".qs2")]
    selected_before <- serialize(state$live_selected_config, NULL)
    session$setInputs(res_sample_idx = "7", btn_run_clustering = 1)
    set_subset_checks(session, fixture, c("sample4", "sample2"))
    session$setInputs(confirm_run_clustering = 1)
    expect_identical(fixture$calls, list(c(2L, 4L)))
    expect_identical(fixture$invalidated, c("sample2", "sample4"))
    expect_identical(serialize(state$pipeline_state$samples[unselected], NULL), original)
    expect_identical(tools::md5sum(artifacts), before_files)
    expect_identical(load_cache_manifest(root)$artifacts[paste0("cna_matrix_", unselected, ".qs2")], manifest_before)
    expect_identical(serialize(state$live_selected_config, NULL), selected_before)
    for (sample in c("sample2", "sample4")) {
      expect_identical(get_pipeline_step(state$pipeline_state, "clustering", sample)$status, "completed")
      expect_identical(get_pipeline_step(state$pipeline_state, "resolution", sample)$status, "stale")
      expect_identical(get_pipeline_step(state$pipeline_state, "annotation", sample)$status, "stale")
      expect_false(file.exists(file.path(root, "cache", paste0("cna_matrix_", sample, ".qs2"))))
    }
    expect_match(fixture$progress[[1]]$detail, "Sample 1 of 2: sample2", fixed = TRUE)
    expect_match(fixture$progress[[2]]$detail, "Sample 2 of 2: sample4", fixed = TRUE)
    expect_match(tail(fixture$modals, 1), "2 selected samples clustered: sample2, sample4", fixed = TRUE)
    expect_length(fixture$navigation, 0)
    expect_length(fixture$selected_indices, 0)
    session$setInputs(btn_after_clustering_res = 1)
    session$setInputs(btn_after_clustering_res = 2)
    session$setInputs(confirm_run_clustering = 2)
    expect_identical(fixture$selected_indices, 2L)
    expect_identical(fixture$navigation, "res_tab")
    expect_length(fixture$calls, 1)
    expect_true(any(vapply(fixture$events, function(event) identical(event$selected_samples, c("sample2", "sample4")), logical(1))))
  })
})

test_that("F09 empty, invalid, duplicate and active selections cannot execute", {
  suppressPackageStartupMessages(library(shiny))
  fixture <- make_subset_clustering_fixture(withr::local_tempdir())
  state <- fixture$state
  shiny::testServer(fixture$server, {
    state_hash <- tools::md5sum(state$pipeline_state_path)
    session$setInputs(btn_run_clustering = 1)
    attempt <- 0L
    for (selection in list(character(), c("sample2", "missing"), rep("sample2", 2), NA_character_, "sample5")) {
      set_subset_checks(session, fixture, selection)
      attempt <- attempt + 1L
      session$setInputs(confirm_run_clustering = attempt)
      expect_length(fixture$calls, 0)
      expect_match(output$clustering_run_control$html, "disabled", fixed = TRUE)
      expect_identical(tools::md5sum(state$pipeline_state_path), state_hash)
    }
    # Invalid requests leave the reviewed dialog usable after correction.
    set_subset_checks(session, fixture, "sample2")
    session$setInputs(confirm_run_clustering = 20)
    expect_identical(fixture$calls, list(2L))
  })
})

test_that("F09 archived, busy, unsaved and changed-dataset contexts block execution", {
  suppressPackageStartupMessages(library(shiny))
  for (mode in c("archived", "busy", "dirty", "dataset", "samples", "resolutions", "standardization")) {
    fixture <- make_subset_clustering_fixture(withr::local_tempdir())
    state <- fixture$state
    shiny::testServer(fixture$server, {
      session$setInputs(btn_run_clustering = 1)
      set_subset_checks(session, fixture, "sample2")
      state_hash <- tools::md5sum(state$pipeline_state_path)
      switch(mode,
        archived = { state$storage_state <- list(status = "archived") },
        busy = { state$active_actions <- "cna_batch_compute" },
        dirty = { state$annotation_dirty <- TRUE },
        dataset = { state$dataset_dir_path <- paste0(state$dataset_dir_path, "-other") },
        samples = { state$paths_list <- list(sample_dir_paths = rev(state$paths_list$sample_dir_paths)) },
        resolutions = { state$dataset_config <- list(params = list(resolutions = c(0.1, 0.5))) },
        standardization = { state$pipeline_state <- transition_pipeline_step(state$pipeline_state, "standardization", "stale", reason = "Inputs changed", force = TRUE) }
      )
      session$flushReact()
      expect_match(output$clustering_run_control$html, "disabled", fixed = TRUE)
      session$setInputs(confirm_run_clustering = 1)
      expect_length(fixture$calls, 0)
      expect_identical(tools::md5sum(state$pipeline_state_path), state_hash)
      if (mode %in% c("archived", "busy", "dirty", "standardization")) {
        count <- length(fixture$modals)
        session$setInputs(btn_run_clustering = 2, btn_run_single_clustering = 1)
        expect_length(fixture$modals, count)
      }
    })
  }
})

test_that("F09 all-sample mode remains available and failures do not touch later/unselected work", {
  suppressPackageStartupMessages(library(shiny))
  fixture <- make_subset_clustering_fixture(withr::local_tempdir())
  state <- fixture$state
  shiny::testServer(fixture$server, {
    state$pipeline_state <- transition_pipeline_step(state$pipeline_state, "clustering", "failed", "sample5", reason = "Prior run interrupted", force = TRUE)
    session$setInputs(btn_run_clustering = 1)
    set_subset_checks(session, fixture, tail(fixture$checkboxes, 1)[[1]]$selected)
    session$setInputs(confirm_run_clustering = 1)
    expect_identical(fixture$calls, list(1:7))
    expect_identical(fixture$invalidated, paste0("sample", 1:7))
    fixture$fail_sample <- "sample4"
    before <- serialize(state$pipeline_state$samples[c("sample1", "sample3", "sample7")], NULL)
    session$setInputs(btn_run_clustering = 2)
    set_subset_checks(session, fixture, c("sample2", "sample4", "sample7"))
    session$setInputs(confirm_run_clustering = 2)
    expect_identical(get_pipeline_step(state$pipeline_state, "clustering", "sample4")$status, "failed")
    expect_identical(serialize(state$pipeline_state$samples[c("sample1", "sample3", "sample7")], NULL), before)
    expect_false("after_clustering_navigation" %in% state$open_confirmations)
    expect_match(tail(fixture$notifications, 1), "sample4", fixed = TRUE)
    expect_match(tail(fixture$notifications, 1), "Synthetic subset failure", fixed = TRUE)
    session$setInputs(btn_after_clustering_res = 1)
    expect_length(fixture$navigation, 0)
  })
})
