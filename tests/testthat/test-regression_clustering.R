# Regression test for the "Pre-Processing & Clustering" step of the pipeline:
# load_filter_cells_expmat() -> pca_umap_louvain(). This is deliberately an
# invariant/shape check, not an exact-value check: irlba/uwot/Seurat results
# can shift slightly across package versions even with a fixed seed, so
# asserting exact cluster IDs would make this test flaky rather than useful.
#
# Once the pipeline is stable, consider promoting the `cells_filt` output of
# this test to a golden fixture (saveRDS once, compare with expect_equal()
# thereafter) to catch even small numeric drift -- see
# test-golden_outputs.R for that pattern on a cheaper function.

test_that("load_filter_cells_expmat + pca_umap_louvain run end to end on a mini dataset", {
  skip_if_not_installed("matkot")
  skip_if_not_installed("irlba")
  skip_if_not_installed("uwot")
  skip_if_not_installed("Seurat")

  dir <- withr::local_tempdir()
  # Deliberately larger than the other unit-test fixtures: UMAP/Louvain need
  # enough cells to behave sensibly (n_neighbors etc.), see run_expmat_umap().
  fixture <- write_mini_sample(dir, "sample1", n_genes = 60, n_cells = 40, seed = 42)

  config <- list(params = list(
    min_genes = 3, # low on purpose: real value is ~500, our synthetic cells are tiny
    target_sum = 1e5,
    log2_expr_threshold = 0.1,
    pca_nv = 5,
    seed = 3988,
    umap = list(spread = 5, min_dist = 0.1)
  ))

  loaded <- load_filter_cells_expmat(
    fixture$cells_path, fixture$expmat_path, fixture$genes_path, config
  )

  expect_true(all(c("cells_filt", "expmat_filt") %in% names(loaded)))
  expect_gt(nrow(loaded$cells_filt), 0)
  expect_equal(nrow(loaded$cells_filt), ncol(loaded$expmat_filt))

  selected_config <- setup_selected_config("sample1")
  selected_config$resolutions$sample1 <- 0.5

  cells_out <- pca_umap_louvain(
    loaded$expmat_filt, loaded$cells_filt, config, selected_config, "sample1"
  )

  # Shape / completeness invariants -- these are what should stay true no
  # matter how clustering parameters or package versions drift.
  expect_equal(nrow(cells_out), nrow(loaded$cells_filt))
  expect_true(all(c("umap1", "umap2", "clust") %in% names(cells_out)))
  expect_false(anyNA(cells_out$umap1))
  expect_false(anyNA(cells_out$umap2))
  expect_false(anyNA(cells_out$clust))
  expect_gte(length(unique(cells_out$clust)), 1)
})
