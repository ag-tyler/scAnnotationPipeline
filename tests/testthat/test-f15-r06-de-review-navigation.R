test_that("R06 review queues are read-only, scope-aware and ordered by actual processing", {
  samples <- paste0("sample", 1:4)
  state <- new_pipeline_state("Review_Queue", samples)
  for (sample in samples) {
    state <- transition_pipeline_step(state, "differential_expression", "completed", sample, force = TRUE)
  }
  state <- transition_pipeline_step(state, "annotation", "completed", "sample1", force = TRUE)
  state <- transition_pipeline_step(state, "annotation", "stale", "sample2", reason = "Review required", force = TRUE)
  state <- transition_pipeline_step(state, "differential_expression", "stale", "sample3", reason = "DE required", force = TRUE)
  original <- serialize(state, NULL)
  queue <- summarize_de_annotation_review(state, c("sample4", "sample2", "sample1", "sample4", "missing"), samples)
  expect_identical(queue$processed_samples, c("sample4", "sample2", "sample1"))
  expect_identical(queue$pending_samples, c("sample4", "sample2"))
  expect_identical(queue$ready_samples, c("sample4", "sample2"))
  expect_identical(queue$target_sample, "sample4")
  expect_identical(queue$target_index, 4L)
  expect_identical(queue$blocked_samples, character())
  blocked <- summarize_de_annotation_review(state, c("sample3", "sample2"), samples)
  expect_identical(blocked$blocked_samples, "sample3")
  expect_identical(blocked$target_sample, "sample2")
  expect_null(summarize_de_annotation_review(state, "sample3")$target_index)
  expect_null(summarize_de_annotation_review(state, "sample1")$target_index)
  expect_identical(summarize_de_annotation_review(state, character())$pending_samples, character())
  expect_identical(summarize_de_annotation_review(state, "missing")$processed_samples, character())
  expect_identical(serialize(state, NULL), original)
  state <- transition_pipeline_step(state, "annotation", "skipped", "sample4", reason = "Explicit legacy skip", force = TRUE)
  expect_null(summarize_de_annotation_review(state, "sample4")$target_index)
})

make_r06_dashboard_fixture <- function(root) {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  env <- new.env(parent = environment())
  sys.source(file.path(app_dir, "app/state.R"), env)
  env$modals <- character()
  env$notifications <- character()
  env$navigation <- character()
  env$selections <- list()
  env$de_calls <- 0L
  env$processed <- paste0("sample", 1:4)
  env$fail_sample <- NULL
  env$showModal <- function(ui, ...) env$modals <- c(env$modals, as.character(ui))
  env$showNotification <- function(ui, ...) {
    env$notifications <- c(env$notifications, as.character(ui))
    "notification"
  }
  env$removeModal <- env$removeNotification <- function(...) invisible(NULL)
  env$record_state_event <- function(...) invisible(NULL)
  env$pipeline_status_overview_ui <- function(...) shiny::tags$div("Overview")
  env$cache_load_data <- env$cache_check_valid <- function(...) stop("Unexpected cache I/O during navigation")
  env$updateNavbarPage <- function(session, inputId, selected) {
    env$navigation <- c(env$navigation, selected)
  }
  env$updateSelectInput <- function(session, inputId, selected, ...) {
    env$selections <- c(env$selections, list(list(input = inputId, selected = selected)))
  }
  env$de_analysis <- function(..., state_callback, progress_callback) {
    env$de_calls <- env$de_calls + 1L
    for (sample in env$processed) {
      state_callback(sample, "in_progress")
      if (identical(sample, env$fail_sample)) {
        state_callback(sample, "failed", reason = "Synthetic DE failure")
        stop("Synthetic DE failure")
      }
      state_callback(sample, "completed", details = list(resolution = 0.5))
    }
  }
  sys.source(file.path(app_dir, "app/server/dashboard_server.R"), env)
  samples <- paste0("sample", 1:4)
  pipeline <- new_pipeline_state("R06_Review", samples)
  pipeline <- transition_pipeline_step(pipeline, "standardization", "completed")
  for (sample in samples) {
    for (step in c("clustering", "resolution", "differential_expression", "annotation")) {
      pipeline <- transition_pipeline_step(pipeline, step, "completed", sample, force = TRUE)
    }
  }
  path <- file.path(root, "pipeline_state.yaml")
  state <- env$create_app_state(list(), session_id = "r06-de-review")
  state$paths_list <- list(sample_dir_paths = file.path(root, "processed_data", samples))
  state$pipeline_state <- save_pipeline_state_at_path(pipeline, path)
  state$pipeline_state_path <- path
  state$dataset_dir_path <- root
  state$dataset_config <- list(params = list())
  state$results_dir_path <- file.path(root, "results")
  selected <- setup_selected_config(samples)
  selected$resolutions <- stats::setNames(as.list(rep(0.5, 4)), samples)
  state$live_selected_config <- selected
  state$complete_markers <- data.table::data.table(cell_type = "T cell", gene = "G1")
  state$annotation_loaded_index <- 4
  state$sample_name <- "sample4"
  state$cells_filt <- data.table::data.table(cell_name = "cell4", cell_type = "My label")
  env$state <- state
  env$server <- function(input, output, session) {
    env$register_dashboard_server(input, output, session, state, list())
  }
  env
}

test_that("R06 bulk completion selects the first review sample only after explicit single-shot navigation", {
  suppressPackageStartupMessages(library(shiny))
  fixture <- make_r06_dashboard_fixture(withr::local_tempdir())
  state <- fixture$state
  shiny::testServer(fixture$server, {
    session$setInputs(sample_idx = "4", btn_run_de = 1)
    session$setInputs(confirm_run_de = 1)
    expect_identical(fixture$de_calls, 1L)
    expect_identical(input$sample_idx, "4")
    expect_length(fixture$selections, 0)
    expect_length(fixture$navigation, 0)
    expect_match(tail(fixture$modals, 1), "4 need annotation review", fixed = TRUE)
    expect_match(tail(fixture$modals, 1), "Continue at sample1", fixed = TRUE)
    state_hash <- tools::md5sum(state$pipeline_state_path)
    session$setInputs(btn_after_de_anno = 1)
    expect_identical(fixture$selections, list(list(input = "sample_idx", selected = 1L)))
    expect_identical(fixture$navigation, "anno_tab")
    expect_identical(tools::md5sum(state$pipeline_state_path), state_hash)
    session$setInputs(btn_after_de_anno = 2)
    session$setInputs(confirm_run_de = 2)
    expect_length(fixture$selections, 1)
    expect_identical(fixture$de_calls, 1L)
    expect_identical(fixture$navigation, "anno_tab")
  })
})

test_that("R06 subset completion ignores unrelated samples and rechecks current review needs", {
  suppressPackageStartupMessages(library(shiny))
  fixture <- make_r06_dashboard_fixture(withr::local_tempdir())
  fixture$processed <- c("sample4", "sample2")
  state <- fixture$state
  shiny::testServer(fixture$server, {
    state$pipeline_state <- transition_pipeline_step(state$pipeline_state, "annotation", "stale", "sample1", reason = "Unrelated pending review", force = TRUE)
    untouched <- serialize(state$pipeline_state$samples$sample1, NULL)
    session$setInputs(sample_idx = "3", btn_run_de = 1)
    session$setInputs(confirm_run_de = 1)
    expect_match(tail(fixture$modals, 1), "2 need annotation review", fixed = TRUE)
    expect_match(tail(fixture$modals, 1), "Continue at sample4", fixed = TRUE)
    expect_identical(serialize(state$pipeline_state$samples$sample1, NULL), untouched)
    # The initial target was reviewed after completion but before the click.
    state$pipeline_state <- transition_pipeline_step(state$pipeline_state, "annotation", "completed", "sample4", force = TRUE)
    session$setInputs(btn_after_de_anno = 1)
    expect_identical(fixture$selections, list(list(input = "sample_idx", selected = 2L)))
    expect_identical(fixture$navigation, "anno_tab")
    expect_identical(serialize(state$pipeline_state$samples$sample1, NULL), untouched)
  })
})

test_that("R06 no ready review target preserves selection with a current overview cue", {
  suppressPackageStartupMessages(library(shiny))
  for (mode in c("reviewed", "blocked")) {
    root <- withr::local_tempdir()
    fixture <- make_r06_dashboard_fixture(root)
    fixture$processed <- c("sample3", "sample2")
    state <- fixture$state
    shiny::testServer(fixture$server, {
      session$setInputs(sample_idx = "4", btn_run_de = 1)
      session$setInputs(confirm_run_de = 1)
      for (sample in fixture$processed) {
        state$pipeline_state <- if (mode == "reviewed") {
          transition_pipeline_step(state$pipeline_state, "annotation", "completed", sample, force = TRUE)
        } else transition_pipeline_step(state$pipeline_state, "differential_expression", "stale", sample, reason = "DE inputs changed", force = TRUE)
      }
      session$setInputs(btn_after_de_anno = 1)
      expect_length(fixture$selections, 0)
      expect_identical(input$sample_idx, "4")
      expect_identical(fixture$navigation, "anno_tab")
      expect_match(tail(fixture$notifications, 1), "current selection will be kept", fixed = TRUE)
      expect_match(tail(fixture$notifications, 1), if (mode == "reviewed") "No processed samples" else "unmet prerequisites", fixed = TRUE)
    })
  }
})

test_that("R06 unsaved edits block bulk DE at request/confirmation and survive completion navigation", {
  suppressPackageStartupMessages(library(shiny))
  fixture <- make_r06_dashboard_fixture(withr::local_tempdir())
  state <- fixture$state
  shiny::testServer(fixture$server, {
    session$setInputs(sample_idx = "4")
    state$annotation_dirty <- TRUE
    edits <- data.table::copy(state$cells_filt)
    state_hash <- tools::md5sum(state$pipeline_state_path)
    session$setInputs(btn_run_de = 1)
    expect_length(fixture$modals, 0)
    expect_identical(fixture$de_calls, 0L)
    expect_false("bulk_de" %in% state$open_confirmations)
    state$annotation_dirty <- FALSE
    session$setInputs(btn_run_de = 2)
    state$annotation_dirty <- TRUE
    session$setInputs(confirm_run_de = 1)
    expect_identical(fixture$de_calls, 0L)
    expect_identical(tools::md5sum(state$pipeline_state_path), state_hash)
    expect_equal(state$cells_filt, edits)
    expect_true(state$annotation_dirty)
    state$annotation_dirty <- FALSE
    session$setInputs(btn_run_de = 3)
    session$setInputs(confirm_run_de = 2)
    state$annotation_dirty <- TRUE
    completed_hash <- tools::md5sum(state$pipeline_state_path)
    session$setInputs(btn_after_de_anno = 1)
    expect_length(fixture$selections, 0)
    expect_length(fixture$navigation, 0)
    expect_true(state$annotation_dirty)
    expect_equal(state$cells_filt, edits)
    expect_identical(state$annotation_loaded_index, 4)
    expect_identical(tools::md5sum(state$pipeline_state_path), completed_hash)
    expect_match(tail(fixture$notifications, 1), "selection and edits are unchanged", fixed = TRUE)
  })
})

test_that("R06 failed reruns and dataset switches cannot reuse old completion navigation", {
  suppressPackageStartupMessages(library(shiny))
  fixture <- make_r06_dashboard_fixture(withr::local_tempdir())
  state <- fixture$state
  shiny::testServer(fixture$server, {
    session$setInputs(btn_run_de = 1)
    session$setInputs(confirm_run_de = 1)
    expect_true("after_de_navigation" %in% state$open_confirmations)
    fixture$fail_sample <- "sample2"
    session$setInputs(btn_run_de = 2)
    session$setInputs(confirm_run_de = 2)
    expect_false("after_de_navigation" %in% state$open_confirmations)
    session$setInputs(btn_after_de_anno = 1)
    expect_length(fixture$selections, 0)
    expect_length(fixture$navigation, 0)
    expect_match(tail(fixture$notifications, 1), "Synthetic DE failure", fixed = TRUE)
    # A fresh run succeeds, but the user then loads another dataset.
    fixture$fail_sample <- NULL
    session$setInputs(btn_run_de = 3)
    session$setInputs(confirm_run_de = 3)
    state$dataset_dir_path <- file.path(state$dataset_dir_path, "another-dataset")
    session$setInputs(btn_after_de_anno = 2)
    expect_length(fixture$selections, 0)
    expect_length(fixture$navigation, 0)
    expect_match(tail(fixture$notifications, 1), "no longer matches the loaded dataset", fixed = TRUE)
  })
})
