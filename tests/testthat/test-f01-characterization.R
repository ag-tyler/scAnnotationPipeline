test_that("F01 cache validity checks eagerly deserialize the artifact", {
  calls <- list()
  test_env <- new.env(parent = environment(cache_check_valid))
  test_env$cache_load_data <- function(...) {
    calls <<- list(...)
    42L
  }
  characterized_check <- cache_check_valid
  environment(characterized_check) <- test_env

  expect_true(characterized_check(
    "artifact.qs2",
    "synthetic-dataset",
    dependencies = list(values = list(version = list(hash = "abc")))
  ))
  expect_identical(calls[[1]], "artifact.qs2")
  expect_identical(calls[[2]], "synthetic-dataset")
  expect_identical(calls$nthreads, 1)
  expect_false(calls$recover)
})


test_that("F01 initial reconciliation work scales with samples and resolutions", {
  sample_names <- c("sample1", "sample2")
  resolutions <- c(0.25, 0.5, 1)
  state <- new_pipeline_state("Synthetic_Dataset", sample_names)
  for (sample_name in sample_names) {
    state <- transition_pipeline_step(
      state,
      "clustering",
      "completed",
      sample = sample_name,
      force = TRUE
    )
  }

  calls <- new.env(parent = emptyenv())
  calls$filter_dependencies <- 0L
  calls$clustering_dependencies <- 0L
  calls$validations <- 0L
  test_env <- new.env(parent = environment(reconcile_pipeline_state_cache))
  test_env$filter_cache_dependencies <- function(...) {
    calls$filter_dependencies <- calls$filter_dependencies + 1L
    list(kind = "filter")
  }
  test_env$clustering_cache_dependencies <- function(...) {
    calls$clustering_dependencies <- calls$clustering_dependencies + 1L
    list(kind = "clustering")
  }
  test_env$cache_check_valid <- function(...) {
    calls$validations <- calls$validations + 1L
    TRUE
  }
  characterized_reconcile <- reconcile_pipeline_state_cache
  environment(characterized_reconcile) <- test_env

  result <- characterized_reconcile(
    state,
    paths_list = list(sample_dir_paths = file.path("processed_data", sample_names)),
    dataset_config = list(params = list(resolutions = resolutions)),
    selected_config = list(resolutions = setNames(as.list(rep(0.5, 2)), sample_names)),
    dataset_dir_path = "synthetic-dataset",
    gene_positions = data.table::data.table()
  )

  expect_length(attr(result, "cache_changes"), 0L)
  expect_identical(calls$filter_dependencies, length(sample_names))
  expect_identical(
    calls$clustering_dependencies,
    length(sample_names) * length(resolutions)
  )
  expect_identical(
    calls$validations,
    length(sample_names) * (length(resolutions) + 1L)
  )
})


test_that("F01 current annotation-only cache rewrite does not stale clustering", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  processed_dir <- file.path(dataset_dir, "processed_data")
  fixture <- write_mini_sample(
    processed_dir,
    sample_name = "sample1",
    n_genes = 12,
    n_cells = 8,
    seed = 101
  )
  paths_list <- list(
    sample_dir_paths = fixture$sample_dir,
    cell_file_paths = fixture$cells_path,
    expmat_file_paths = fixture$expmat_path,
    genes_file_paths = fixture$genes_path
  )
  dataset_config <- list(params = list(
    min_genes = 1,
    target_sum = 1e4,
    log2_expr_threshold = 0,
    pca_nv = 2,
    seed = 1,
    umap = list(spread = 1, min_dist = 0.1),
    resolutions = c(0.5, 1)
  ))

  filter_dependencies <- filter_cache_dependencies(paths_list, 1L, dataset_config)
  cache_save_data(
    fixture$mat,
    "expmat_filt_sample1.qs2",
    dataset_dir,
    dependencies = filter_dependencies,
    producer = "F01 fixture"
  )
  clustered_cells <- data.table::copy(fixture$cells)
  clustered_cells[, `:=`(
    umap1 = seq_len(.N),
    umap2 = rev(seq_len(.N)),
    clust = rep(0:1, length.out = .N)
  )]
  for (resolution in dataset_config$params$resolutions) {
    cache_save_data(
      clustered_cells,
      paste0("cells_filt_clust_res_", resolution, "_sample1.qs2"),
      dataset_dir,
      dependencies = clustering_cache_dependencies(
        paths_list,
        1L,
        dataset_config,
        resolution
      ),
      producer = "F01 fixture"
    )
  }

  state <- new_pipeline_state("Synthetic_Dataset", "sample1")
  for (step in c("clustering", "resolution", "differential_expression", "annotation")) {
    state <- transition_pipeline_step(
      state,
      step,
      "completed",
      sample = "sample1",
      force = TRUE
    )
  }

  # Characterize the current annotation-save behavior: the selected clustered
  # cache is overwritten without its original clustering dependencies.
  clustered_cells[, cell_type := rep(c("Tumour", "T cell"), length.out = .N)]
  cache_save_data(
    clustered_cells,
    "cells_filt_clust_res_0.5_sample1.qs2",
    dataset_dir
  )

  reconciled <- reconcile_pipeline_state_cache(
    state,
    paths_list,
    dataset_config,
    selected_config = list(resolutions = list(sample1 = 0.5)),
    dataset_dir_path = dataset_dir,
    gene_positions = data.table::data.table()
  )

  expect_identical(get_pipeline_step(reconciled, "clustering", "sample1")$status, "completed")
  expect_identical(get_pipeline_step(reconciled, "resolution", "sample1")$status, "completed")
  expect_identical(
    get_pipeline_step(reconciled, "differential_expression", "sample1")$status,
    "completed"
  )
  expect_identical(get_pipeline_step(reconciled, "annotation", "sample1")$status, "completed")
  expect_length(attr(reconciled, "cache_changes"), 0L)
})


test_that("F01 annotation remains stale after an upstream rerun completes", {
  state <- new_pipeline_state("Synthetic_Dataset", "sample1")
  for (step in c("clustering", "resolution", "differential_expression", "annotation")) {
    state <- transition_pipeline_step(
      state,
      step,
      "completed",
      sample = "sample1",
      force = TRUE
    )
  }

  state <- mark_pipeline_steps_stale(
    state,
    upstream_step = "clustering",
    sample = "sample1",
    reason = "The clustering step is being rerun for this sample."
  )
  state <- transition_pipeline_step(
    state, "clustering", "completed", sample = "sample1", force = TRUE
  )
  state <- transition_pipeline_step(
    state, "resolution", "completed", sample = "sample1", force = TRUE
  )
  state <- transition_pipeline_step(
    state,
    "differential_expression",
    "completed",
    sample = "sample1",
    force = TRUE
  )

  annotation <- get_pipeline_step(state, "annotation", "sample1")
  expect_identical(annotation$status, "stale")
  expect_identical(
    annotation$reason,
    "The clustering step is being rerun for this sample."
  )
})


test_that("F01 Dataset Selection has only initial and explicit-change navigation", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  server_files <- list.files(
    file.path(app_dir, "app", "server"),
    pattern = "[.]R$",
    full.names = TRUE
  )
  navigation_counts <- vapply(server_files, function(path) {
    sum(grepl(
      'updateNavbarPage\\(session, "main_nav", selected = "dataset_tab"\\)',
      readLines(path, warn = FALSE)
    ))
  }, integer(1))

  expect_identical(sum(navigation_counts), 2L)
  expect_identical(
    unname(navigation_counts[basename(server_files) == "app_server.R"]),
    1L
  )
  expect_identical(
    unname(navigation_counts[basename(server_files) == "dataset_server.R"]),
    1L
  )
})
