app_dir_f13 <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
suppressPackageStartupMessages(library(shiny))
suppressPackageStartupMessages(library(bslib))


make_f13_workspace <- function(sample_name = "Sample 01, primary") {
  root <- tempfile("f13-")
  dataset_dir <- file.path(root, "dataset")
  results_dir <- file.path(root, "results")
  dir.create(dataset_dir, recursive = TRUE)
  dir.create(results_dir, recursive = TRUE)
  matrix <- data.table::data.table(
    gene = c("GENE,1", "GENE_2", "GENE_3"),
    chr = c("01", "01", "02"),
    start_pos = c(100L, 200L, 300L),
    `cell, one` = c(-0.1257, 0, 1.2345),
    `cell two` = c(0.3333, -0.4444, 0.5555),
    check.names = FALSE
  )
  filename <- paste0("cna_matrix_", sample_name, ".qs2")
  cache_save_data(
    matrix,
    filename,
    dataset_dir,
    dependencies = list(reference = "synthetic-f13"),
    producer = "test-f13"
  )
  list(
    root = root,
    dataset_dir = dataset_dir,
    results_dir = results_dir,
    sample_name = sample_name,
    filename = filename,
    matrix = matrix
  )
}


test_that("F13 compressed export round-trips the canonical long CNA table", {
  workspace <- make_f13_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)

  result <- export_cna_values_table(
    workspace$sample_name,
    workspace$dataset_dir,
    workspace$results_dir,
    chunk_cell_count = 1L,
    timestamp = as.POSIXct("2026-10-28 09:00:00", tz = "UTC")
  )
  actual <- data.table::fread(
    result$paths$csv,
    colClasses = list(character = c("gene", "chr", "cell_name"))
  )
  expected <- cna_matrix_to_long(workspace$matrix)

  expect_identical(names(actual), CNA_VALUES_EXPORT_COLUMNS)
  expect_equal(actual, expected)
  expect_identical(nrow(actual), nrow(workspace$matrix) * 2L)
  expect_identical(unique(actual$cell_name), c("cell, one", "cell two"))
  expect_true(grepl("[.]csv[.]gz$", result$paths$csv))

  metadata <- yaml::read_yaml(result$paths$metadata)
  manifest <- load_cache_manifest(workspace$dataset_dir)
  record <- manifest$artifacts[[workspace$filename]]
  expect_silent(validate_cna_values_export_metadata(metadata))
  expect_identical(metadata$sample, workspace$sample_name)
  expect_identical(unlist(metadata$columns, use.names = FALSE), CNA_VALUES_EXPORT_COLUMNS)
  expect_equal(metadata$row_count, nrow(expected))
  expect_equal(metadata$gene_count, 3)
  expect_equal(metadata$cell_count, 2)
  expect_identical(metadata$cache$checksum, record$checksum)
  expect_identical(metadata$cache$dependency_fingerprint, record$dependency_fingerprint)
  expect_match(metadata$import_example, "data.table::fread", fixed = TRUE)
  status <- cna_values_export_status(
    workspace$sample_name, workspace$dataset_dir, workspace$results_dir
  )
  expect_true(status$current)
  Sys.setFileTime(result$paths$csv, file.info(result$paths$csv)$mtime + 2)
  expect_false(cna_values_export_status(
    workspace$sample_name, workspace$dataset_dir, workspace$results_dir
  )$current)
})


test_that("F13 re-export refreshes provenance without CNA recomputation", {
  workspace <- make_f13_workspace("Sample reexport")
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)

  first <- export_cna_values_table(
    workspace$sample_name, workspace$dataset_dir, workspace$results_dir
  )
  second <- export_cna_values_table(
    workspace$sample_name, workspace$dataset_dir, workspace$results_dir,
    chunk_cell_count = 1L
  )

  expect_identical(first$paths$csv, second$paths$csv)
  expect_true(file.exists(second$paths$csv))
  expect_equal(
    data.table::fread(
      second$paths$csv,
      colClasses = list(character = c("gene", "chr", "cell_name"))
    ),
    cna_matrix_to_long(workspace$matrix)
  )
  exporter_text <- paste(deparse(body(export_cna_values_table)), collapse = "\n")
  expect_false(grepl("compute_cna", exporter_text, fixed = TRUE))
})


test_that("F13 invalidated caches make prior exports visibly outdated", {
  workspace <- make_f13_workspace("Sample stale")
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)
  export_cna_values_table(
    workspace$sample_name, workspace$dataset_dir, workspace$results_dir
  )

  expect_true(cna_values_export_status(
    workspace$sample_name, workspace$dataset_dir, workspace$results_dir
  )$current)
  cache_invalidate_artifacts(workspace$filename, workspace$dataset_dir)
  status <- cna_values_export_status(
    workspace$sample_name, workspace$dataset_dir, workspace$results_dir
  )
  expect_true(status$exists)
  expect_false(status$current)
  expect_match(status$reason, "outdated", fixed = TRUE)
})


test_that("F13 failed pair publication restores the previous complete export", {
  directory <- tempfile("f13-publish-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE, force = TRUE), add = TRUE)
  final_csv <- file.path(directory, "values.csv.gz")
  final_metadata <- file.path(directory, "values.yaml")
  temporary_csv <- file.path(directory, "new.csv.gz")
  temporary_metadata <- file.path(directory, "new.yaml")
  writeLines("old csv", final_csv)
  writeLines("old metadata", final_metadata)
  writeLines("new csv", temporary_csv)
  writeLines("new metadata", temporary_metadata)

  rename_with_metadata_failure <- function(from, to) {
    if (identical(from, temporary_metadata)) return(FALSE)
    file.rename(from, to)
  }
  expect_error(
    .publish_cna_values_export_pair(
      temporary_csv,
      temporary_metadata,
      final_csv,
      final_metadata,
      rename_file = rename_with_metadata_failure
    ),
    "prior export was restored",
    fixed = TRUE
  )
  expect_identical(readLines(final_csv), "old csv")
  expect_identical(readLines(final_metadata), "old metadata")
  expect_false(file.exists(paste0(final_csv, ".bak")))
  expect_false(file.exists(paste0(final_metadata, ".bak")))

  file.remove(final_csv, final_metadata)
  writeLines("new csv", temporary_csv)
  writeLines("new metadata", temporary_metadata)
  expect_error(
    .publish_cna_values_export_pair(
      temporary_csv,
      temporary_metadata,
      final_csv,
      final_metadata,
      rename_file = rename_with_metadata_failure
    ),
    "no partial export was retained",
    fixed = TRUE
  )
  expect_false(file.exists(final_csv))
  expect_false(file.exists(final_metadata))
})


test_that("F13 rejects ambiguous line-break identifiers before publishing", {
  workspace <- make_f13_workspace("Sample invalid identifier")
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)
  invalid <- data.table::copy(workspace$matrix)
  invalid$gene[[1]] <- "GENE\n1"
  cache_save_data(invalid, workspace$filename, workspace$dataset_dir)

  expect_error(
    export_cna_values_table(
      workspace$sample_name, workspace$dataset_dir, workspace$results_dir
    ),
    "line breaks",
    fixed = TRUE
  )
  paths <- cna_values_export_paths(
    workspace$results_dir, workspace$sample_name, create = FALSE
  )
  expect_false(file.exists(paths$csv))
  expect_false(file.exists(paths$metadata))
})


test_that("F13 UI and finalization lifecycle expose safe export and retry", {
  sys.source(file.path(app_dir_f13, "app/ui/cna_ui.R"), envir = environment())
  ui_html <- as.character(cna_panel(c("Sample" = "1")))
  expect_match(ui_html, "btn_cna_export_values", fixed = TRUE)
  expect_match(ui_html, "Export/Re-export CNA Values Table", fixed = TRUE)
  expect_match(ui_html, "cna_values_export_status", fixed = TRUE)

  server_lines <- readLines(
    file.path(app_dir_f13, "app/server/cna_summary_server.R"), warn = FALSE
  )
  server_text <- paste(server_lines, collapse = "\n")
  persist_position <- regexpr("state_result <- tryCatch", server_text, fixed = TRUE)[[1]]
  auto_export_position <- regexpr(
    "export_result <- publish_cna_values", server_text, fixed = TRUE
  )[[1]]
  assignment_event_position <- regexpr(
    'event_type = "cna_assignments_saved"', server_text, fixed = TRUE
  )[[1]]
  expect_gt(auto_export_position, persist_position)
  expect_lt(auto_export_position, assignment_event_position)
  expect_match(server_text, 'event_type = "cna_values_export"', fixed = TRUE)
  expect_match(server_text, "Use Export/Re-export CNA Values Table to retry.", fixed = TRUE)

  preview_start <- regexpr("prepare_cna_preview <- function", server_text, fixed = TRUE)[[1]]
  preview_end <- regexpr(
    "observeEvent(input$btn_cna_preview_summary", server_text, fixed = TRUE
  )[[1]]
  preview_text <- substr(server_text, preview_start, preview_end - 1L)
  expect_false(grepl("export_cna_values_table", preview_text, fixed = TRUE))
})
