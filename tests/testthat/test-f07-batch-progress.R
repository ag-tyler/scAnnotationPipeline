test_that("F07 shared progress contract computes monotonic batch fractions", {
  events <- list()
  callback <- function(...) {
    events[[length(events) + 1L]] <<- list(...)
  }

  report_batch_progress(
    callback, "clustering", "sample1", 1, 2,
    "loading_filtering", "Loading inputs", 0.1,
    elapsed_seconds = 0.5
  )
  report_batch_progress(
    callback, "clustering", "sample1", 1, 2,
    "completed", "Complete", 1,
    outcome = "completed", elapsed_seconds = 2
  )
  report_batch_progress(
    callback, "clustering", "sample2", 2, 2,
    "pca_umap", "Computing PCA and UMAP", 0.25,
    elapsed_seconds = 1
  )
  report_batch_progress(
    callback, "clustering", "sample2", 2, 2,
    "completed", "Complete", 1,
    outcome = "completed", elapsed_seconds = 3
  )

  fractions <- vapply(events, `[[`, numeric(1), "fraction")
  expect_equal(fractions, c(0.05, 0.5, 0.625, 1))
  expect_true(all(diff(fractions) >= 0))
  expect_equal(events[[4]]$sample_index, 2)
  expect_equal(events[[4]]$sample_total, 2)
  expect_identical(events[[4]]$outcome, "completed")
  expect_identical(events[[4]]$elapsed_seconds, 3)
})

test_that("F07 Shiny formatter includes sample position, stage, and outcome", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  server_env <- new.env(parent = globalenv())
  progress_updates <- list()
  server_env$setProgress <- function(value, detail = NULL, ...) {
    progress_updates[[length(progress_updates) + 1L]] <<- list(
      value = value,
      detail = detail
    )
  }
  sys.source(
    file.path(app_dir, "app/server/dashboard_server.R"),
    envir = server_env
  )

  context <- new.env(parent = emptyenv())
  callback <- server_env$make_shiny_batch_progress_callback(context)
  callback(
    operation = "differential_expression",
    sample_name = "sample8",
    sample_index = 8,
    sample_total = 15,
    stage = "marker_matching",
    detail = "Matching marker genes",
    outcome = NULL,
    fraction = 0.5,
    elapsed_seconds = 12.5
  )

  expect_identical(progress_updates[[1]]$value, 0.5)
  expect_match(progress_updates[[1]]$detail, "Sample 8 of 15: sample8", fixed = TRUE)
  expect_match(progress_updates[[1]]$detail, "marker matching", fixed = TRUE)
  expect_identical(context$stage, "marker_matching")

  callback(
    operation = "differential_expression",
    sample_name = "sample8",
    sample_index = 8,
    sample_total = 15,
    stage = "output_writing",
    detail = "Failed during output_writing: disk full",
    outcome = "failed",
    fraction = 0.55,
    elapsed_seconds = 14
  )
  error <- simpleError("disk full")
  failure <- server_env$format_batch_failure(
    "Differential expression",
    context,
    error
  )
  expect_match(failure, "sample sample8", fixed = TRUE)
  expect_match(failure, "during output writing", fixed = TRUE)
  expect_match(progress_updates[[2]]$detail, "[failed]", fixed = TRUE)
})

test_that("F07 DE failure identifies the sample and last real stage", {
  test_env <- new.env(parent = environment(de_analysis))
  test_env$single_de_analysis <- function(
    sample_idx,
    paths_list,
    dataset_config,
    selected_config,
    complete_markers,
    results_dir_path,
    dataset_dir_path,
    progress_callback = NULL
  ) {
    progress_callback("input_loading", "Loading inputs", 0.05)
    progress_callback(
      "differential_expression",
      "Calculating cluster differential expression",
      0.25
    )
    if (sample_idx == 2L) stop("synthetic DE failure", call. = FALSE)
  }
  de_analysis_test <- de_analysis
  environment(de_analysis_test) <- test_env

  events <- list()
  states <- list()
  expect_error(
    de_analysis_test(
      paths_list = list(sample_dir_paths = c("sample1", "sample2", "sample3")),
      dataset_config = list(),
      selected_config = list(),
      complete_markers = data.table::data.table(),
      results_dir_path = tempfile(),
      dataset_dir_path = tempfile(),
      state_callback = function(sample_name, status, reason = NULL, details = NULL) {
        states[[length(states) + 1L]] <<- list(
          sample_name = sample_name,
          status = status,
          reason = reason
        )
      },
      progress_callback = function(...) {
        events[[length(events) + 1L]] <<- list(...)
      }
    ),
    "synthetic DE failure"
  )

  terminal <- events[[length(events)]]
  expect_identical(terminal$sample_name, "sample2")
  expect_identical(terminal$stage, "differential_expression")
  expect_identical(terminal$outcome, "failed")
  expect_match(terminal$detail, "Failed during differential_expression", fixed = TRUE)
  expect_true(all(diff(vapply(events, `[[`, numeric(1), "fraction")) >= 0))
  expect_false(any(vapply(
    events,
    function(event) identical(event$sample_name, "sample3"),
    logical(1)
  )))
  expect_identical(states[[length(states)]]$status, "failed")
})

test_that("F07 both bulk handlers use the shared Shiny progress callback", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  server_text <- paste(
    readLines(file.path(app_dir, "app/server/dashboard_server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(server_text, 'withProgress(message = "Bulk clustering"', fixed = TRUE)
  expect_match(
    server_text,
    'withProgress(message = "Bulk differential expression"',
    fixed = TRUE
  )
  expect_equal(
    lengths(regmatches(
      server_text,
      gregexpr(
        "progress_callback = make_shiny_batch_progress_callback(progress_context)",
        server_text,
        fixed = TRUE
      )
    )),
    2L
  )
})
