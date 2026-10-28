app_dir_f10 <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
suppressPackageStartupMessages(library(shiny))
suppressPackageStartupMessages(library(bslib))
sys.source(file.path(app_dir_f10, "app/ui/dashboard_ui.R"), envir = environment())


set_overview_status <- function(state, step, status, sample = NULL, reason = NULL) {
  transition_pipeline_step(
    state,
    step,
    status,
    sample = sample,
    reason = reason,
    timestamp = as.POSIXct("2026-01-01 12:00:00", tz = "UTC"),
    force = TRUE
  )
}


complete_overview_steps <- function(state, sample, steps) {
  for (step in steps) {
    state <- set_overview_status(state, step, "completed", sample)
  }
  state
}


test_that("F10 aggregate counts preserve mixed, stale, and skipped CNA states", {
  state <- new_pipeline_state(
    "Mixed_Dataset",
    c("complete", "failed", "stale", "cna_omitted"),
    as.POSIXct("2026-01-01", tz = "UTC")
  )
  state <- set_overview_status(state, "standardization", "completed")

  state <- complete_overview_steps(state, "complete", PIPELINE_SAMPLE_STEPS)
  state <- set_overview_status(
    state, "clustering", "failed", "failed", "Clustering process exited early."
  )
  state <- complete_overview_steps(
    state, "stale", c("clustering", "resolution")
  )
  state <- set_overview_status(
    state, "differential_expression", "stale", "stale",
    "Resolution changed; rerun differential expression."
  )
  state <- set_overview_status(
    state, "annotation", "stale", "stale",
    "Differential expression changed; review annotations."
  )
  state <- complete_overview_steps(
    state, "cna_omitted",
    c("clustering", "resolution", "differential_expression", "annotation")
  )
  state <- set_overview_status(
    state, "cna_configuration", "skipped", "cna_omitted",
    "CNA was intentionally omitted for this sample."
  )

  before <- serialize(state, NULL)
  summary <- summarize_pipeline_overview(state)
  expect_identical(serialize(state, NULL), before)

  expect_identical(summary$stages$clustering$counts[["completed"]], 3L)
  expect_identical(summary$stages$clustering$counts[["failed"]], 1L)
  expect_identical(summary$stages$differential_expression$counts[["stale"]], 1L)
  expect_identical(summary$stages$annotation$counts[["stale"]], 1L)
  expect_identical(summary$stages$cna_configuration$counts[["skipped"]], 1L)
  expect_identical(summary$stages$cna_analysis$counts[["completed"]], 1L)
  expect_identical(summary$stages$cna_analysis$counts[["skipped"]], 1L)
  expect_identical(
    summary$stages$clustering$samples_by_status$failed,
    "failed"
  )
  expect_identical(
    summary$stages$cna_analysis$samples_by_status$skipped,
    "cna_omitted"
  )
  expect_match(summary$samples$failed$next_action$label, "Retry: Run clustering", fixed = TRUE)
})


test_that("F10 renders distinct accessible presentations for every status", {
  samples <- paste0("sample_", seq_along(PIPELINE_STEP_STATUSES))
  state <- new_pipeline_state(
    "Statuses",
    samples,
    as.POSIXct("2026-01-01", tz = "UTC")
  )
  for (index in seq_along(samples)) {
    status <- PIPELINE_STEP_STATUSES[[index]]
    reason <- if (status %in% c("incomplete", "failed", "skipped", "stale")) {
      paste("Reason for", status)
    } else {
      NULL
    }
    state <- set_overview_status(state, "clustering", status, samples[[index]], reason)
  }

  html <- as.character(pipeline_status_overview_ui(summarize_pipeline_overview(state)))
  expected_labels <- c(
    "Not started", "In progress", "Incomplete", "Complete", "Skipped", "Failed", "Stale"
  )
  for (index in seq_along(PIPELINE_STEP_STATUSES)) {
    expect_match(html, paste0("pipeline-status-", PIPELINE_STEP_STATUSES[[index]]), fixed = TRUE)
    expect_match(html, expected_labels[[index]], fixed = TRUE)
  }
  expect_match(html, "Reason for stale", fixed = TRUE)
  expect_match(html, "Samples in this status", fixed = TRUE)
  expect_match(html, 'tabindex="0"', fixed = TRUE)
})


test_that("F10 aggregate tooltips cap long lists and report the remainder", {
  sample_names <- paste0("long_sample_", seq_len(20L))
  html <- as.character(pipeline_overview_sample_tooltip(sample_names))

  expect_match(html, "Samples in this status (20)", fixed = TRUE)
  expect_match(html, "long_sample_1", fixed = TRUE)
  expect_match(html, "long_sample_15", fixed = TRUE)
  expect_false(grepl(">long_sample_16<", html, fixed = TRUE))
  expect_match(html, "and 5 more", fixed = TRUE)
  expect_match(html, "full list", fixed = TRUE)
})


test_that("F10 summary reflects an in-session state revision", {
  state <- new_pipeline_state("Reactive", "sample1", as.POSIXct("2026-01-01", tz = "UTC"))
  initial <- summarize_pipeline_overview(state)
  expect_identical(initial$stages$clustering$counts[["not_started"]], 1L)

  revised <- set_overview_status(state, "clustering", "completed", "sample1")
  revised$revision <- state$revision + 1L
  updated <- summarize_pipeline_overview(revised)
  expect_identical(updated$revision, 1L)
  expect_identical(updated$stages$clustering$counts[["completed"]], 1L)
})


test_that("F10 overview has no filesystem or cache dependencies", {
  overview_functions <- c(
    "summarize_pipeline_overview", "pipeline_overview_sample_records",
    "pipeline_cna_analysis_record", "pipeline_overview_next_action"
  )
  forbidden <- "file[.]exists|readLines|read_yaml|cache_load|load_pipeline_state|qs2"
  for (function_name in overview_functions) {
    expect_false(grepl(
      forbidden,
      paste(deparse(body(get(function_name))), collapse = "\n"),
      ignore.case = TRUE
    ), info = function_name)
  }
})


test_that("F10 renders zero, one, and many samples", {
  for (sample_count in c(0L, 1L, 40L)) {
    state <- new_pipeline_state(
      paste0("Dataset_", sample_count),
      if (sample_count == 0L) character() else paste0("sample_", seq_len(sample_count)),
      as.POSIXct("2026-01-01", tz = "UTC")
    )
    html <- as.character(pipeline_status_overview_ui(summarize_pipeline_overview(state)))
    expect_match(html, paste0("Dataset_", sample_count), fixed = TRUE)
    expect_match(html, "Show sample details", fixed = TRUE)
    if (sample_count == 0L) {
      expect_match(html, "No samples are configured", fixed = TRUE)
    }
  }
})


test_that("F10 Start Menu and server use the reactive in-memory state", {
  ui_lines <- readLines(file.path(app_dir_f10, "app/ui/dashboard_ui.R"), warn = FALSE)
  server_lines <- readLines(file.path(app_dir_f10, "app/server/dashboard_server.R"), warn = FALSE)
  expect_true(any(grepl('uiOutput("pipeline_status_overview")', ui_lines, fixed = TRUE)))
  expect_true(any(grepl("summarize_pipeline_overview(rv$pipeline_state)", server_lines, fixed = TRUE)))
  expect_false(any(grepl("pipeline_status_overview.*load_pipeline_state", server_lines)))
})
