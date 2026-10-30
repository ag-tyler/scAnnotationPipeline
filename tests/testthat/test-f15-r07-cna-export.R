test_that("R07 CNA chunk conversion bounds allocation independently of matrix width", {
  skip_if_not(capabilities("profmem"))
  matrix <- data.table::as.data.table(matrix(0.25, nrow = 2000, ncol = 1000))
  data.table::setnames(matrix, paste0("cell", 1:1000))
  matrix[, `:=`(gene = paste0("GENE", 1:2000), chr = "01", start_pos = 1:2000)]
  columns <- c("cell2", "cell1")
  invisible(cna_matrix_to_long(matrix, columns))
  path <- withr::local_tempfile()
  Rprofmem(path, threshold = 0)
  actual <- tryCatch(cna_matrix_to_long(matrix, columns), finally = Rprofmem(NULL))
  allocations <- readLines(path)
  bytes <- sum(as.numeric(sub(" .*", "", allocations[grepl("^[0-9]+", allocations)])))
  expect_lt(bytes, as.numeric(object.size(matrix)) / 2)
  expect_identical(unique(actual$cell_name), columns)
  expect_equal(nrow(actual), 4000L)
  expect_identical(matrix$cell1, rep(0.25, 2000))
  expect_identical(names(matrix)[1:2], c("cell1", "cell2"))
  expect_equal(actual, cna_matrix_to_long(as.data.frame(matrix), columns))
})

test_that("R07 streamed exports advance through truthful stages and preserve exact metadata", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  results_dir <- withr::local_tempdir()
  matrix <- data.table::data.table(gene = paste0("G", 1:10), chr = "01", start_pos = 1:10,
    cell1 = seq_len(10) / 3, cell2 = seq_len(10) / 7, cell3 = seq_len(10) / 11)
  cache_save_data(matrix, "cna_matrix_Sample.qs2", dataset_dir)
  events <- list()
  result <- export_cna_values_table("Sample", dataset_dir, results_dir, chunk_cell_count = 1,
    progress_callback = function(stage, progress, detail, elapsed_seconds) {
      events[[length(events) + 1L]] <<- list(stage = stage, progress = progress, detail = detail, elapsed = elapsed_seconds)
    })
  progress <- vapply(events, `[[`, numeric(1), "progress")
  stages <- vapply(events, `[[`, character(1), "stage")
  expect_true(all(diff(progress) >= 0))
  expect_equal(range(progress), c(0, 1))
  expect_identical(unique(stages), c("loading", "writing", "validation", "checksum", "metadata", "publication", "completed"))
  expect_equal(sum(stages == "writing"), 4)
  expect_true(all(grepl("elapsed", vapply(events, `[[`, character(1), "detail"))))
  expect_equal(data.table::fread(result$paths$csv, colClasses = list(character = "chr")), cna_matrix_to_long(matrix))
  expect_true(cna_values_export_status("Sample", dataset_dir, results_dir)$current)
  expect_gte(result$elapsed_seconds, 0)
})

test_that("R07 interrupted or failed exports retain the previous pair and can be retried", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  results_dir <- withr::local_tempdir()
  matrix <- data.table::data.table(gene = "G", chr = "01", start_pos = 1L, cell1 = 0.5, cell2 = -0.5)
  cache_save_data(matrix, "cna_matrix_Sample.qs2", dataset_dir)
  original <- export_cna_values_table("Sample", dataset_dir, results_dir)
  originals <- unname(tools::md5sum(c(original$paths$csv, original$paths$metadata)))
  for (stage_to_stop in c("writing", "validation", "publication")) {
    callback <- function(stage, progress, detail, elapsed_seconds) {
      if (stage == stage_to_stop && (stage != "writing" || progress > 0.1)) {
        stop("synthetic export failure")
      }
    }
    expect_error(export_cna_values_table("Sample", dataset_dir, results_dir,
      chunk_cell_count = 1, progress_callback = callback),
      paste0("failed during ", stage_to_stop, ": synthetic export failure"))
    expect_identical(unname(tools::md5sum(c(original$paths$csv, original$paths$metadata))), originals)
    expect_setequal(list.files(original$paths$directory, all.files = TRUE, no.. = TRUE),
      basename(c(original$paths$csv, original$paths$metadata)))
  }
  interrupt <- function(stage, ...) {
    if (stage == "validation") stop(structure(list(message = "Stopped", call = NULL), class = c("interrupt", "condition")))
  }
  interrupted <- tryCatch(export_cna_values_table("Sample", dataset_dir, results_dir,
    progress_callback = interrupt), interrupt = function(condition) TRUE)
  expect_true(interrupted)
  expect_identical(unname(tools::md5sum(c(original$paths$csv, original$paths$metadata))), originals)
  expect_setequal(list.files(original$paths$directory, all.files = TRUE, no.. = TRUE),
    basename(c(original$paths$csv, original$paths$metadata)))
  interrupt_publication <- function(from, to) {
    if (identical(to, original$paths$metadata)) {
      stop(structure(list(message = "Stopped during pair publication", call = NULL), class = c("interrupt", "condition")))
    }
    file.rename(from, to)
  }
  interrupted <- tryCatch(export_cna_values_table("Sample", dataset_dir, results_dir,
    rename_file = interrupt_publication), interrupt = function(condition) TRUE)
  expect_true(interrupted)
  expect_identical(unname(tools::md5sum(c(original$paths$csv, original$paths$metadata))), originals)
  expect_setequal(list.files(original$paths$directory, all.files = TRUE, no.. = TRUE),
    basename(c(original$paths$csv, original$paths$metadata)))
  expect_no_error(export_cna_values_table("Sample", dataset_dir, results_dir))
  expect_true(cna_values_export_status("Sample", dataset_dir, results_dir)$current)
})

test_that("R07 interrupting first publication leaves no partial final export", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  results_dir <- withr::local_tempdir()
  matrix <- data.table::data.table(gene = "G", chr = "01", start_pos = 1L, cell1 = 0.5)
  cache_save_data(matrix, "cna_matrix_Sample.qs2", dataset_dir)
  paths <- cna_values_export_paths(results_dir, "Sample")
  interrupted <- tryCatch(export_cna_values_table("Sample", dataset_dir, results_dir,
    rename_file = function(from, to) {
      if (identical(to, paths$metadata)) {
        stop(structure(list(message = "Stopped", call = NULL), class = c("interrupt", "condition")))
      }
      file.rename(from, to)
    }), interrupt = function(condition) TRUE)
  expect_true(interrupted)
  expect_false(file.exists(paths$csv))
  expect_false(file.exists(paths$metadata))
  expect_length(list.files(paths$directory, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("R07 the CNA server reports interrupted export and retains saved assignment state", {
  skip_if_not_installed("qs2")
  suppressPackageStartupMessages(library(shiny))
  dataset_dir <- withr::local_tempdir()
  results_dir <- withr::local_tempdir()
  matrix <- data.table::data.table(gene = "G", chr = "01", start_pos = 1L, cell1 = 0.5)
  cache_save_data(matrix, "cna_matrix_Sample.qs2", dataset_dir)
  pipeline <- new_pipeline_state("Dataset", "Sample")
  pipeline <- transition_pipeline_step(pipeline, "cna_assignment", "completed", "Sample", force = TRUE)
  rv <- reactiveValues(dataset_dir_path = dataset_dir, results_dir_path = results_dir,
    paths_list = list(sample_dir_paths = file.path(dataset_dir, "processed_data", "Sample")),
    pipeline_state = pipeline)
  env <- new.env(parent = environment(export_cna_values_table))
  events <- list()
  notifications <- character()
  env$record_state_event <- function(state, ...) events[[length(events) + 1L]] <<- list(...)
  env$showNotification <- function(ui, ...) { notifications <<- c(notifications, ui); "test-notification" }
  env$export_cna_values_table <- function(sample_name, dataset_dir_path, results_dir_path, progress_callback) {
    progress_callback(stage = "writing", progress = 0.5, detail = "Writing", elapsed_seconds = 1)
    stop(structure(list(message = "User stopped export", call = NULL), class = c("interrupt", "condition")))
  }
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  sys.source(file.path(app_dir, "app/server/cna_summary_server.R"), envir = env)
  server <- function(input, output, session) env$register_cna_summary_server(input, output, session, rv, list())
  shiny::testServer(server, {
    session$setInputs(cna_sample_idx = "1", btn_cna_export_values = 1)
    expect_identical(get_pipeline_step(rv$pipeline_state, "cna_assignment", "Sample")$status, "completed")
    outcomes <- vapply(events, function(event) event$outcome, character(1))
    expect_true("interrupted" %in% outcomes)
    expect_false("completed" %in% outcomes)
    expect_true(any(grepl("interrupted during writing", notifications)))

    env$export_cna_values_table <- export_cna_values_table
    session$setInputs(btn_cna_export_values = 2)
    expect_true(cna_values_export_status("Sample", dataset_dir, results_dir)$current)
    expect_identical(get_pipeline_step(rv$pipeline_state, "cna_assignment", "Sample")$status, "completed")
    expect_identical(tail(events, 1)[[1]]$outcome, "completed")
    expect_match(output$cna_values_export_status$html, "Current compressed table", fixed = TRUE)
  })
})

test_that("R07 binary gzip validation rejects wrong headers and row counts", {
  path <- withr::local_tempfile(fileext = ".csv.gz")
  data <- data.table::data.table(gene = c('G,"quoted"', "G2"), chr = c("01", "X"),
    start_pos = c(1L, 2L), cell_name = c("cell,1", "cell2"), cna = c(0.25, -0.25))
  data.table::fwrite(data, path, compress = "gzip")
  expect_equal(validate_cna_values_export_file(path, 2), 2)
  expect_error(validate_cna_values_export_file(path, 3), "row count mismatch")
  compressed <- readBin(path, "raw", n = file.info(path)$size)
  writeBin(compressed[seq_len(floor(length(compressed) / 2))], path)
  expect_error(validate_cna_values_export_file(path, 2), "row count|header|decompressed|unterminated")
  data.table::fwrite(data[1], path, compress = "gzip")
  expect_error(validate_cna_values_export_file(path, 2), "row count mismatch")
  connection <- gzfile(path, "wt")
  writeLines(paste0(paste(CNA_VALUES_EXPORT_COLUMNS, collapse = ","),
    "\nG1,01,1,cell1,0.25\nG2,01,2,cell2,-0.25\nunfinished"), connection, sep = "")
  close(connection)
  expect_error(validate_cna_values_export_file(path, 2), "unterminated final CSV row")
  data.table::setnames(data, "cna", "wrong")
  data.table::fwrite(data, path, compress = "gzip")
  expect_error(validate_cna_values_export_file(path, 2), "unexpected CSV header")
})
