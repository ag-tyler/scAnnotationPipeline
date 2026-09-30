# tests/testthat/test-05_utils_workflow_clustering.R


test_that("cluster_all_samples writes cluster cache, expression cache, and plot", {
  skip_if_not_installed("qs2")
  skip_if_not_installed("matkot")
  skip_if_not_installed("irlba")
  skip_if_not_installed("uwot")
  skip_if_not_installed("Seurat")
  skip_if_not_installed("randomcoloR")
  skip_if_not_installed("cowplot")
  
  dataset_dir <- withr::local_tempdir()
  
  processed_dir <- file.path(
    dataset_dir,
    "processed_data"
  )
  
  results_dir <- file.path(
    dataset_dir,
    "results"
  )
  
  dir.create(
    processed_dir,
    recursive = TRUE
  )
  
  dir.create(
    results_dir,
    recursive = TRUE
  )
  
  # Keep this comparable to the existing clustering regression fixture:
  # UMAP needs more cells than the tiny unit-test datasets.
  fixture <- write_mini_sample(
    processed_dir,
    sample_name = "sample1",
    n_genes = 60,
    n_cells = 40,
    seed = 51
  )
  
  paths_list <- list(
    sample_dir_paths = fixture$sample_dir,
    cell_file_paths = fixture$cells_path,
    expmat_file_paths = fixture$expmat_path,
    genes_file_paths = fixture$genes_path
  )
  
  config <- list(
    params = list(
      min_genes = 3,
      target_sum = 1e5,
      log2_expr_threshold = 0.1,
      pca_nv = 5,
      resolutions = 0.5,
      seed = 3988,
      umap = list(
        spread = 5,
        min_dist = 0.1
      )
    )
  )
  
  cluster_all_samples(
    paths_list = paths_list,
    config = config,
    results_dir_path = results_dir,
    dataset_dir_path = dataset_dir
  )
  
  expect_true(
    cache_check_exists(
      "cells_filt_clust_res_0.5_sample1.qs2",
      dataset_dir
    )
  )
  
  expect_true(
    cache_check_exists(
      "expmat_filt_sample1.qs2",
      dataset_dir
    )
  )
  
  plot_path <- file.path(
    results_dir,
    "sample1",
    "1_cluster_plots",
    "clusters_plot_sample1_res_0.5.png"
  )
  
  expect_true(
    file.exists(plot_path)
  )
  
  cells_out <- cache_load_data(
    "cells_filt_clust_res_0.5_sample1.qs2",
    dataset_dir
  )
  
  expect_true(
    all(
      c(
        "cell_name",
        "umap1",
        "umap2",
        "clust"
      ) %in% names(cells_out)
    )
  )
  
  expect_false(
    anyNA(cells_out$umap1)
  )
  
  expect_false(
    anyNA(cells_out$umap2)
  )
  
  expect_false(
    anyNA(cells_out$clust)
  )
})