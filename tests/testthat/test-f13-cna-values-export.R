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
  expect_match(ui_html, "Optional CNA Values Table", fixed = TRUE)

  server_lines <- readLines(
    file.path(app_dir_f13, "app/server/cna_summary_server.R"), warn = FALSE
  )
  server_text <- paste(server_lines, collapse = "\n")
  persist_position <- regexpr("state_result <- tryCatch", server_text, fixed = TRUE)[[1]]
  assignment_event_position <- regexpr(
    'event_type = "cna_assignments_saved"', server_text, fixed = TRUE
  )[[1]]
  expect_gt(assignment_event_position, persist_position)
  finalize_start <- regexpr("observeEvent(input$btn_cna_save_summary", server_text, fixed = TRUE)[[1]]
  finalize_text <- substring(server_text, finalize_start)
  expect_false(grepl("publish_cna_values", finalize_text, fixed = TRUE))
  expect_match(server_text, 'event_type = "cna_values_export"', fixed = TRUE)
  expect_match(server_text, "Use Export/Re-export CNA Values Table to retry.", fixed = TRUE)

  preview_start <- regexpr("prepare_cna_preview <- function", server_text, fixed = TRUE)[[1]]
  preview_end <- regexpr(
    "observeEvent(input$btn_cna_preview_summary", server_text, fixed = TRUE
  )[[1]]
  preview_text <- substr(server_text, preview_start, preview_end - 1L)
  expect_false(grepl("export_cna_values_table", preview_text, fixed = TRUE))
})

test_that("CNA finalization keeps its preview while saving without optional export", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  sample_dir <- file.path(dataset_dir, "processed_data", "Sample")
  results_dir <- file.path(dataset_dir, "results")
  dir.create(sample_dir, recursive = TRUE)
  dir.create(file.path(results_dir, "Sample", "3_cna_plots"), recursive = TRUE)
  cells <- data.table::data.table(cell_name = c("cell1", "cell2"), sample = "Sample",
    cell_type = c("Malignant", "Unassigned"), subclone = c(1L, NA_integer_),
    umap1 = c(0, 1), umap2 = c(1, 0), clust = c(1L, 2L))
  cells_path <- file.path(sample_dir, "Cells.csv")
  data.table::fwrite(cells, cells_path)
  pipeline <- new_pipeline_state("Dataset", "Sample")
  pipeline <- transition_pipeline_step(pipeline, "standardization", "completed", force = TRUE)
  for (step in setdiff(PIPELINE_SAMPLE_STEPS, "cna_assignment")) {
    pipeline <- transition_pipeline_step(pipeline, step, "completed", "Sample", force = TRUE)
  }
  pipeline <- save_pipeline_state_atomic(pipeline, dataset_dir)
  plot <- ggplot2::ggplot(data.frame(x = 1:2, y = 2:1), ggplot2::aes(x, y)) + ggplot2::geom_point()
  rv <- shiny::reactiveValues(
    dataset_dir_path = dataset_dir, results_dir_path = results_dir,
    pipeline_state = pipeline, pipeline_state_path = pipeline_state_paths(dataset_dir)$primary,
    paths_list = list(sample_dir_paths = sample_dir, cell_file_paths = cells_path),
    live_selected_config = list(resolutions = list(Sample = 0.5),
      cna_ward_ref_cluster = list(Sample = list(list(k = 2, cluster = 1)))),
    cna_preview_sample = "Sample", cna_preview_fingerprint = "current",
    cna_preview_res = list(cells_filt = cells, summary_heatmap = plot,
      pre_umap_plot = plot, umap_plot = plot, pre_scatter_plots = list(), post_scatter_plots = list()))
  env <- new.env(parent = environment(export_cna_values_table))
  env$cna_preview_fingerprint <- function(...) {
    if (file.exists(file.path(dataset_dir, "cache", "cells_filt_clust_res_0.5_Sample.qs2"))) "saved" else "current"
  }
  env$export_cna_values_table <- function(...) stop("Optional export must not run during finalization")
  env$preview_cna_summary <- function(...) stop("Saved preview must not be recomputed")
  env$cna_sample_preflight <- function(...) list(eligible = TRUE, status = "eligible", reasons = character(),
    counts = list(reference = 1L, configured_candidate = 1L, unassigned = 0L))
  calls <- new.env(parent = emptyenv())
  calls$events <- character()
  calls$navigation <- list()
  env$record_state_event <- function(state, stage, event_type, ...) calls$events <- c(calls$events, event_type)
  env$nav_select <- function(id, selected) calls$navigation[[length(calls$navigation) + 1L]] <- c(id, selected)
  sys.source(file.path(app_dir_f13, "app/server/cna_status_server.R"), envir = env)
  sys.source(file.path(app_dir_f13, "app/server/cna_summary_server.R"), envir = env)
  server <- function(input, output, session) {
    env$register_cna_status_server(input, output, session, rv, list())
    env$register_cna_summary_server(input, output, session, rv, list())
  }
  shiny::testServer(server, {
    session$setInputs(cna_sample_idx = "1")
    rv$cna_preview_res <- list(cells_filt = cells, summary_heatmap = plot,
      pre_umap_plot = plot, umap_plot = plot, pre_scatter_plots = list(), post_scatter_plots = list())
    rv$cna_preview_sample <- "Sample"
    rv$cna_preview_fingerprint <- "current"
    session$setInputs(cna_main_views = "cna_view_summary")
    preview <- rv$cna_preview_res
    calls$events <- character()
    calls$navigation <- list()
    session$setInputs(btn_cna_save_summary = 1)
    expect_identical(get_pipeline_step(rv$pipeline_state, "cna_assignment", "Sample")$status, "completed")
    expect_identical(calls$events, "cna_assignments_saved")
    expect_length(calls$navigation, 0L)
    expect_identical(input$cna_main_views, "cna_view_summary")
    expect_identical(rv$cna_preview_res, preview)
    expect_identical(rv$cna_preview_fingerprint, "saved")
    expect_match(output$cna_status_ui$html, "Final Assignment: Complete", fixed = TRUE)
    expect_true(file.exists(file.path(results_dir, "Sample", "3_cna_plots", "cna_summary_heatmap_Sample.png")))
    expect_false(cna_values_export_status("Sample", dataset_dir, results_dir)$exists)
    expect_match(output$cna_values_export_status$html, "Optional CNA values table", fixed = TRUE)
    saved <- data.table::fread(cells_path, na.strings = "")
    expect_identical(saved$cell_type, c("Malignant", NA_character_))

    # Refresh reuses the saved preview; genuine upstream changes still clear it.
    session$setInputs(btn_cna_preview_summary = 1)
    expect_identical(rv$cna_preview_res, preview)
    expect_identical(tail(calls$events, 1), "cna_preview")
    calls$navigation <- list()
    rv$pipeline_state <- transition_pipeline_step(rv$pipeline_state, "cna_thresholds", "completed", "Sample",
      timestamp = Sys.time() + 1, force = TRUE)
    session$flushReact()
    expect_null(rv$cna_preview_res)
    expect_true(any(vapply(calls$navigation, function(call) {
      identical(call, c("cna_main_views", "cna_view_default"))
    }, logical(1))))
  })
})
