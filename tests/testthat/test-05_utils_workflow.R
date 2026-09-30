# tests/testthat/test-05_utils_workflow_de.R


test_that("single_de_analysis runs from cached clustering results and writes DE outputs", {
  skip_if_not_installed("qs2")
  skip_if_not_installed("matkot")
  skip_if_not_installed("randomcoloR")
  skip_if_not_installed("cowplot")
  
  dataset_dir <- withr::local_tempdir()
  processed_dir <- file.path(dataset_dir, "processed_data")
  results_dir <- file.path(dataset_dir, "results")
  
  dir.create(processed_dir, recursive = TRUE)
  dir.create(results_dir, recursive = TRUE)
  
  fixture <- write_mini_sample(
    processed_dir,
    sample_name = "sample1",
    n_genes = 220,
    n_cells = 10,
    seed = 31
  )
  
  # Build the already-clustered cell metadata that single_de_analysis()
  # should load from cache.
  cells_filt <- data.table::copy(fixture$cells)
  cells_filt$clust <- rep(c("0", "1"), each = 5)
  
  # Use normalized expression because this is what the real preceding
  # preprocessing workflow stores.
  expmat_filt <- log_normalize_expmat(
    fixture$mat,
    colnames(fixture$mat),
    target_sum = 1e5
  )
  
  selected_config <- setup_selected_config("sample1")
  selected_config$resolutions$sample1 <- 0.5
  
  cache_save_data(
    cells_filt,
    "cells_filt_clust_res_0.5_sample1.qs2",
    dataset_dir
  )
  
  cache_save_data(
    expmat_filt,
    "expmat_filt_sample1.qs2",
    dataset_dir
  )
  
  paths_list <- list(
    sample_dir_paths = fixture$sample_dir,
    cell_file_paths = fixture$cells_path,
    expmat_file_paths = fixture$expmat_path,
    genes_file_paths = fixture$genes_path
  )
  
  complete_markers <- data.table::data.table(
    cell_type = c(
      "TypeA", "TypeA",
      "TypeB", "TypeB"
    ),
    symbol = c(
      "GENE01", "GENE02",
      "GENE03", "GENE04"
    )
  )
  
  dataset_config <- list(
    params = list(
      max_marker_genes = 2,
      de = list(
        num_genes = 4,
        max_match_genes = 2,
        min_marker_found = 1
      )
    )
  )
  
  expect_message(
    single_de_analysis(
      sample_idx = 1,
      paths_list = paths_list,
      dataset_config = dataset_config,
      selected_config = selected_config,
      complete_markers = complete_markers,
      results_dir_path = results_dir,
      dataset_dir_path = dataset_dir
    ),
    "Finished sample1"
  )
  
  de_dir <- file.path(
    results_dir,
    "sample1",
    "2_de_plots"
  )
  
  expect_true(dir.exists(de_dir))
  
  # max_match_genes controls the marker-count plot window and therefore
  # belongs in this filename.
  expect_true(
    file.exists(
      file.path(
        de_dir,
        "top_2_unannotated_gene_count_plot.png"
      )
    )
  )
  
  # One score plot should be generated per cluster.
  expect_true(file.exists(file.path(de_dir, "0.png")))
  expect_true(file.exists(file.path(de_dir, "1.png")))
  
  matches_path <- file.path(
    de_dir,
    "all_marker_matches.csv"
  )
  
  expect_true(file.exists(matches_path))
  
  matches <- data.table::fread(matches_path)
  
  expect_true(
    all(c("clust", "gene", "m", "TypeA", "TypeB") %in% names(matches))
  )
  
  expect_setequal(
    unique(as.character(matches$clust)),
    c("0", "1")
  )
})


test_that("de_analysis sends every sample through single_de_analysis", {
  calls <- integer()
  
  test_env <- new.env(
    parent = environment(de_analysis)
  )
  
  test_env$single_de_analysis <- function(
    sample_idx,
    paths_list,
    dataset_config,
    selected_config,
    complete_markers,
    results_dir_path,
    dataset_dir_path
  ) {
    calls <<- c(calls, sample_idx)
    invisible(NULL)
  }
  
  de_analysis_test <- de_analysis
  environment(de_analysis_test) <- test_env
  
  paths_list <- list(
    sample_dir_paths = c(
      "sample1",
      "sample2",
      "sample3"
    )
  )
  
  de_analysis_test(
    paths_list = paths_list,
    dataset_config = list(),
    selected_config = list(),
    complete_markers = data.table::data.table(),
    results_dir_path = tempfile(),
    dataset_dir_path = tempfile()
  )
  
  expect_equal(calls, 1:3)
})


test_that("cell_type_annotation_setup loads cached cells and marker matches", {
  skip_if_not_installed("qs2")
  
  dataset_dir <- withr::local_tempdir()
  processed_dir <- file.path(dataset_dir, "processed_data")
  results_dir <- file.path(dataset_dir, "results")
  
  dir.create(processed_dir, recursive = TRUE)
  dir.create(results_dir, recursive = TRUE)
  
  fixture <- write_mini_sample(
    processed_dir,
    sample_name = "sample1",
    n_genes = 8,
    n_cells = 6,
    seed = 42
  )
  
  cells_filt <- data.table::copy(fixture$cells)
  cells_filt$clust <- rep(c("0", "1"), each = 3)
  
  cache_save_data(
    cells_filt,
    "cells_filt_clust_res_0.5_sample1.qs2",
    dataset_dir
  )
  
  cache_save_data(
    fixture$mat,
    "expmat_filt_sample1.qs2",
    dataset_dir
  )
  
  de_dir <- file.path(
    results_dir,
    "sample1",
    "2_de_plots"
  )
  
  dir.create(de_dir, recursive = TRUE)
  
  expected_matches <- data.table::data.table(
    clust = c("0", "1"),
    gene = c("GENE01", "GENE02"),
    m = c(2.1, 1.9),
    TypeA = c("GENE01", NA_character_),
    TypeB = c(NA_character_, "GENE02")
  )
  
  data.table::fwrite(
    expected_matches,
    file.path(de_dir, "all_marker_matches.csv")
  )
  
  paths_list <- list(
    sample_dir_paths = fixture$sample_dir,
    cell_file_paths = fixture$cells_path,
    expmat_file_paths = fixture$expmat_path,
    genes_file_paths = fixture$genes_path
  )
  
  # cell_type_annotation_setup() currently obtains the resolution through
  # config$selected$resolutions.
  config <- list(
    selected = list(
      resolutions = list(
        sample1 = 0.5
      )
    )
  )
  
  complete_markers <- data.table::data.table(
    cell_type = c("TypeA", "TypeB"),
    symbol = c("GENE01", "GENE02")
  )
  
  res <- cell_type_annotation_setup(
    i = 1,
    paths_list = paths_list,
    results_dir_path = results_dir,
    config = config,
    dataset_dir_path = dataset_dir,
    complete_markers = complete_markers,
    dataset_config = list(),
    selected_config = list()
  )
  
  expect_named(
    res,
    c("cells_filt", "all_matches")
  )
  
  expect_equal(
    res$cells_filt$cell_name,
    cells_filt$cell_name
  )
  
  expect_equal(
    res$cells_filt$clust,
    cells_filt$clust
  )
  
  expect_equal(
    res$all_matches$gene,
    expected_matches$gene
  )
  
  expect_equal(
    res$all_matches$TypeA,
    expected_matches$TypeA
  )
})