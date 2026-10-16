make_batch_test_function <- function(calls, fail_sample = NULL) {
  test_env <- new.env(parent = environment(batch_compute_cna_and_heatmaps))
  test_env$cna_sample_preflight <- function(
    sample_name,
    selected_config,
    dataset_dir_path,
    gene_positions = NULL,
    pipeline_state = NULL,
    validate_expression = TRUE,
    ...
  ) {
    calls$preflight <- c(calls$preflight, sample_name)
    cells <- data.table::data.table(
      cell_name = c(paste0(sample_name, "_ref1"), paste0(sample_name, "_ref2"), paste0(sample_name, "_tumor1"), paste0(sample_name, "_tumor2")),
      cell_type = c("Reference", "Reference", "TumorLike", "TumorLike")
    )
    expmat <- Matrix::Matrix(
      matrix(
        seq_len(120L),
        nrow = 30L,
        dimnames = list(paste0("GENE", 1:30), cells$cell_name)
      ),
      sparse = TRUE
    )
    list(
      eligible = TRUE,
      status = "eligible",
      reason = NULL,
      reasons = character(),
      counts = list(reference = 2L, candidate_total = 2L),
      cells = cells,
      expmat = expmat,
      ref_cells = cells[cell_type == "Reference"]
    )
  }
  test_env$cna_matrix_cache_dependencies <- function(...) list(test = TRUE)
  test_env$cache_check_valid <- function(...) FALSE
  test_env$cache_invalidate_sample <- function(...) character()
  test_env$compute_cna_and_cache <- function(
    expmat,
    gene_positions,
    ref_cells,
    sample_name,
    dataset_dir_path
  ) {
    calls$compute <- c(calls$compute, sample_name)
    if (identical(sample_name, fail_sample)) {
      stop("synthetic CNA failure", call. = FALSE)
    }
    invisible(NULL)
  }
  test_env$cna_clustering_and_heatmaps <- function(
    ref_cells,
    sample_name,
    selected_config,
    cna_plots_dir_path,
    dataset_dir_path
  ) {
    calls$heatmap <- c(calls$heatmap, sample_name)
    invisible(NULL)
  }

  batch_test <- batch_compute_cna_and_heatmaps
  environment(batch_test) <- test_env
  batch_test
}


test_that("batch CNA isolates a failed sample and continues", {
  dataset_dir <- withr::local_tempdir()
  sample_names <- c("sample1", "sample2", "sample3")
  sample_dirs <- file.path(dataset_dir, "processed_data", sample_names)
  invisible(lapply(sample_dirs, dir.create, recursive = TRUE))
  calls <- new.env(parent = emptyenv())
  calls$preflight <- character()
  calls$compute <- character()
  calls$heatmap <- character()
  calls$states <- list()
  batch_test <- make_batch_test_function(calls, fail_sample = "sample2")

  result <- batch_test(
    paths_list = list(sample_dir_paths = sample_dirs),
    dataset_dir_path = dataset_dir,
    results_dir_path = file.path(dataset_dir, "results"),
    selected_config = setup_selected_config(sample_names),
    gene_positions = data.table::data.table(),
    state_callback = function(sample_name, status, reason = NULL, details = NULL) {
      calls$states[[length(calls$states) + 1L]] <- list(
        sample = sample_name,
        status = status,
        reason = reason
      )
    }
  )

  expect_identical(result$processed, c("sample1", "sample3"))
  expect_identical(names(result$failed), "sample2")
  expect_match(result$failed[["sample2"]], "synthetic CNA failure")
  expect_identical(calls$preflight, sample_names)
  expect_identical(calls$compute, sample_names)
  expect_identical(calls$heatmap, c("sample1", "sample3"))
  expect_true(any(vapply(calls$states, function(event) {
    identical(event$sample, "sample2") && identical(event$status, "failed")
  }, logical(1))))
  expect_true(any(vapply(calls$states, function(event) {
    identical(event$sample, "sample3") && identical(event$status, "completed")
  }, logical(1))))
})


test_that("batch CNA runs only the selected sample subset", {
  dataset_dir <- withr::local_tempdir()
  sample_names <- c("sample1", "sample2", "sample3")
  sample_dirs <- file.path(dataset_dir, "processed_data", sample_names)
  invisible(lapply(sample_dirs, dir.create, recursive = TRUE))
  calls <- new.env(parent = emptyenv())
  calls$preflight <- character()
  calls$compute <- character()
  calls$heatmap <- character()
  batch_test <- make_batch_test_function(calls)

  result <- batch_test(
    paths_list = list(sample_dir_paths = sample_dirs),
    dataset_dir_path = dataset_dir,
    results_dir_path = file.path(dataset_dir, "results"),
    selected_config = setup_selected_config(sample_names),
    gene_positions = data.table::data.table(),
    sample_names = "sample2"
  )

  expect_identical(result$processed, "sample2")
  expect_identical(calls$preflight, "sample2")
  expect_identical(calls$compute, "sample2")
  expect_identical(calls$heatmap, "sample2")
  expect_length(result$skipped, 0L)
  expect_length(result$failed, 0L)
})


test_that("a failed batch sample can be retried by itself", {
  dataset_dir <- withr::local_tempdir()
  sample_names <- c("sample1", "sample2")
  sample_dirs <- file.path(dataset_dir, "processed_data", sample_names)
  invisible(lapply(sample_dirs, dir.create, recursive = TRUE))
  first_calls <- new.env(parent = emptyenv())
  first_calls$preflight <- character()
  first_calls$compute <- character()
  first_calls$heatmap <- character()
  first_run <- make_batch_test_function(first_calls, fail_sample = "sample2")

  first_result <- first_run(
    paths_list = list(sample_dir_paths = sample_dirs),
    dataset_dir_path = dataset_dir,
    results_dir_path = file.path(dataset_dir, "results"),
    selected_config = setup_selected_config(sample_names),
    gene_positions = data.table::data.table()
  )

  expect_identical(first_result$processed, "sample1")
  expect_identical(names(first_result$failed), "sample2")

  retry_calls <- new.env(parent = emptyenv())
  retry_calls$preflight <- character()
  retry_calls$compute <- character()
  retry_calls$heatmap <- character()
  retry_run <- make_batch_test_function(retry_calls)
  retry_result <- retry_run(
    paths_list = list(sample_dir_paths = sample_dirs),
    dataset_dir_path = dataset_dir,
    results_dir_path = file.path(dataset_dir, "results"),
    selected_config = setup_selected_config(sample_names),
    gene_positions = data.table::data.table(),
    sample_names = "sample2"
  )

  expect_identical(retry_result$processed, "sample2")
  expect_identical(retry_calls$preflight, "sample2")
  expect_identical(retry_calls$compute, "sample2")
  expect_identical(retry_calls$heatmap, "sample2")
  expect_length(retry_result$failed, 0L)
})


test_that("batch CNA rejects unknown selected samples", {
  expect_error(
    batch_compute_cna_and_heatmaps(
      paths_list = list(sample_dir_paths = file.path("processed_data", "sample1")),
      dataset_dir_path = tempdir(),
      results_dir_path = tempdir(),
      selected_config = setup_selected_config("sample1"),
      gene_positions = data.table::data.table(),
      sample_names = "not_a_sample"
    ),
    "Unknown batch CNA samples: not_a_sample"
  )
})
