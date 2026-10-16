test_that("pipeline events persist as structured and readable append-only logs", {
  dataset_dir <- withr::local_tempdir()
  fixed_time <- as.POSIXct("2026-10-14 12:34:56", tz = "UTC")

  first <- log_pipeline_event(
    dataset_dir_path = dataset_dir,
    dataset = "Example_Dataset",
    sample = "sample1",
    stage = "clustering",
    event_type = "clustering_run",
    outcome = "started",
    parameters = list(resolutions = c(0.5, 1)),
    timestamp = fixed_time
  )
  log_pipeline_event(
    dataset_dir_path = dataset_dir,
    dataset = "Example_Dataset",
    sample = "sample1",
    stage = "clustering",
    event_type = "clustering_run",
    outcome = "completed",
    parameters = list(n_cells = 42L),
    timestamp = fixed_time + 1
  )

  paths <- pipeline_log_paths(dataset_dir)
  events <- read_pipeline_events(dataset_dir)
  readable <- readLines(paths$readable, warn = FALSE, encoding = "UTF-8")

  expect_identical(first$schema_version, PIPELINE_LOG_SCHEMA_VERSION)
  expect_identical(first$timestamp, "2026-10-14T12:34:56.000Z")
  expect_true(file.exists(paths$structured))
  expect_true(file.exists(paths$readable))
  expect_length(events, 2L)
  expect_identical(events[[1]]$dataset, "Example_Dataset")
  expect_identical(events[[1]]$sample, "sample1")
  expect_identical(events[[1]]$stage, "clustering")
  expect_identical(events[[2]]$outcome, "completed")
  expect_identical(events[[2]]$parameters$n_cells, 42L)
  expect_length(readable, 2L)
  expect_match(readable[[1]], "STARTED | clustering | clustering_run", fixed = TRUE)
})


test_that("failed and skipped events require an actionable reason", {
  dataset_dir <- withr::local_tempdir()

  expect_error(
    log_pipeline_event(
      dataset_dir,
      dataset = "Example_Dataset",
      stage = "cna",
      event_type = "cna_compute",
      outcome = "failed"
    ),
    "reason is required"
  )
  expect_error(
    log_pipeline_event(
      dataset_dir,
      dataset = "Example_Dataset",
      stage = "cna",
      event_type = "cna_compute",
      outcome = "skipped",
      reason = ""
    ),
    "reason must be one non-empty value"
  )

  expect_no_error(log_pipeline_event(
    dataset_dir,
    dataset = "Example_Dataset",
    sample = "sample1",
    stage = "cna",
    event_type = "cna_compute",
    outcome = "skipped",
    reason = "No reference cell types were configured."
  ))
})


test_that("state events use the canonical dataset identifier", {
  dataset_dir <- withr::local_tempdir()
  state <- list(
    dataset_dir_path = dataset_dir,
    dataset_config = list(project_info = list(dataset_id = "Canonical_Dataset"))
  )

  record_state_event(
    state,
    stage = "annotation",
    event_type = "annotations_saved",
    outcome = "saved",
    sample = "sample1",
    parameters = list(n_cells = 12L)
  )

  event <- read_pipeline_events(dataset_dir)[[1]]
  expect_identical(event$dataset, "Canonical_Dataset")
  expect_identical(event$event_type, "annotations_saved")
  expect_identical(event$parameters$n_cells, 12L)
})


test_that("malformed structured events fail with a line number", {
  dataset_dir <- withr::local_tempdir()
  paths <- setup_pipeline_log_dir(dataset_dir)
  writeLines(c('{"valid":true}', "not-json"), paths$structured, useBytes = TRUE)

  expect_error(read_pipeline_events(dataset_dir), "line 2")
})
