test_that("console timing distinguishes step duration from cumulative sample time", {
  now <- 0
  report <- new_console_step_timer("[2/3] Sample_A | DE", clock = function() now)
  messages <- capture.output({
    now <- 2
    report("input_loading", "Loading inputs")
    now <- 7
    report("differential_expression", "Calculating DE")
    now <- 10
    report("completed", "Outputs complete")
    report("failed", "Must not print a second terminal outcome")
  }, type = "message")
  expect_length(messages, 5L)
  expect_match(messages[[2]], "[2/3] Sample_A | DE | input_loading | completed | step 5.0s | elapsed 7.0s", fixed = TRUE)
  expect_match(messages[[4]], "differential_expression | completed | step 3.0s | elapsed 10.0s", fixed = TRUE)
  expect_match(messages[[5]], "completed | Outputs complete | elapsed 10.0s", fixed = TRUE)
  expect_false(any(grepl("Must not print", messages, fixed = TRUE)))
})

test_that("console failures and skips do not claim that the active step completed", {
  for (outcome in c("failed", "skipped")) {
    now <- 0
    report <- new_console_step_timer("Sample | CNA", clock = function() now)
    messages <- capture.output({
      report("preflight", "Checking eligibility")
      now <- 4
      report(outcome, "Specific reason")
    }, type = "message")
    expect_match(messages[[2]], paste0("preflight | ", outcome, " | step 4.0s | elapsed 4.0s"), fixed = TRUE)
    expect_match(messages[[3]], "Specific reason", fixed = TRUE)
    expect_false(any(grepl("| completed |", messages, fixed = TRUE)))
  }
})

test_that("same-stage updates preserve the step's original start time", {
  now <- 0
  report <- new_console_step_timer("Sample | CNA", clock = function() now)
  messages <- capture.output({
    report("clustering", "Checking cache")
    now <- 2
    report("clustering", "Reusing validated clustering")
    now <- 5
    report("completed", "Heatmaps saved")
  }, type = "message")
  expect_length(messages, 4L)
  expect_match(messages[[3]], "clustering | completed | step 5.0s | elapsed 5.0s", fixed = TRUE)
})

test_that("standalone DE reports failed input loading and preserves the original error", {
  paths <- list(sample_dir_paths = "/prepared/Sample_A", cell_file_paths = tempfile(),
    expmat_file_paths = tempfile(), genes_file_paths = tempfile())
  messages <- capture.output({
    expect_error(single_de_analysis(1, paths, list(), list(), data.table::data.table(),
      tempdir(), tempdir()))
  }, type = "message")
  text <- paste(messages, collapse = "\n")
  expect_match(text, "[1/1] Sample_A | DE | input_loading", fixed = TRUE)
  expect_match(text, "input_loading | failed | step", fixed = TRUE)
  expect_false(grepl("| completed |", text, fixed = TRUE))
})

test_that("interrupted CNA computation preserves its condition and never prints success", {
  env <- new.env(parent = environment(compute_cna_and_cache))
  env$compute_cna <- function(...) {
    stop(structure(list(message = "synthetic interruption", call = NULL),
      class = c("interrupt", "condition")))
  }
  compute <- compute_cna_and_cache
  environment(compute) <- env
  messages <- capture.output({
    condition <- tryCatch(compute(NULL, NULL, NULL, "Sample_A", tempdir()),
      interrupt = function(condition) condition)
  }, type = "message")
  expect_s3_class(condition, "interrupt")
  expect_match(conditionMessage(condition), "synthetic interruption", fixed = TRUE)
  expect_true(any(grepl("computation | failed | step", messages, fixed = TRUE)))
  expect_false(any(grepl("| completed |", messages, fixed = TRUE)))
})

test_that("CNA batch console reports reuse, skips, isolated failures and exact totals without changing callbacks", {
  directory <- withr::local_tempdir()
  env <- new.env(parent = environment(batch_compute_cna_and_heatmaps))
  env$cna_sample_preflight <- function(sample_name, ...) {
    list(eligible = sample_name != "skip", status = if (sample_name == "skip") "omitted" else "eligible",
      reason = "User omitted CNA", reasons = "User omitted CNA", counts = list(),
      cells = data.table::data.table(), expmat = NULL, ref_cells = data.table::data.table(x = 1:2))
  }
  env$cna_matrix_cache_dependencies <- function(...) NULL
  env$cache_check_valid <- function(...) TRUE
  env$compute_cna_and_cache <- function(...) stop("Validated CNA must be reused")
  env$cna_clustering_and_heatmaps <- function(ref_cells, sample_name, ...) {
    if (sample_name == "B") stop("synthetic heatmap failure")
  }
  batch <- batch_compute_cna_and_heatmaps
  environment(batch) <- env
  events <- list()
  messages <- capture.output({
    result <- batch(list(sample_dir_paths = file.path(directory, c("A", "skip", "B", "C"))),
      directory, file.path(directory, "results"), list(), data.table::data.table(),
      progress_callback = function(sample_name, sample_index, sample_total, stage, detail = NULL) {
        events[[length(events) + 1L]] <<- list(name = sample_name, stage = stage)
      })
  }, type = "message")
  text <- paste(messages, collapse = "\n")
  expect_identical(result$processed, c("A", "C"))
  expect_identical(result$skipped, "skip")
  expect_identical(names(result$failed), "B")
  expect_match(text, "[1/4] A | CNA | cna_matrix | Reusing validated CNA matrix", fixed = TRUE)
  expect_match(text, "[2/4] skip | CNA | skipped | User omitted CNA", fixed = TRUE)
  expect_match(text, "[3/4] B | CNA | heatmaps | failed | step", fixed = TRUE)
  expect_false(any(grepl("[3/4] B | CNA | completed", messages, fixed = TRUE)))
  expect_match(text, "CNA batch finished: completed=2, failed=1, skipped=1, not_run=0, elapsed=", fixed = TRUE)
  expect_identical(vapply(events, `[[`, character(1), "stage"), c(
    "preflight", "cna_matrix", "heatmaps", "completed", "preflight", "skipped",
    "preflight", "cna_matrix", "heatmaps", "failed", "preflight", "cna_matrix", "heatmaps", "completed"))

  state_messages <- capture.output({
    state_result <- batch(list(sample_dir_paths = file.path(directory, "A")), directory,
      file.path(directory, "results"), list(), data.table::data.table(),
      state_callback = function(sample_name, status, ...) {
        if (status == "completed") stop("synthetic state write failure")
      })
  }, type = "message")
  expect_length(state_result$processed, 0L)
  expect_identical(names(state_result$failed), "A")
  expect_false(any(grepl("[1/1] A | CNA | completed", state_messages, fixed = TRUE)))
  expect_true(any(grepl("CNA batch finished: completed=0, failed=1, skipped=0, not_run=0", state_messages, fixed = TRUE)))
})
