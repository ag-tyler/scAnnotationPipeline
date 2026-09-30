# tests/testthat/test-02_utils_annotation_cna.R


make_small_cna_matrix <- function(
    n_genes = 30,
    n_cells = 30,
    seed = 123
) {
  set.seed(seed)
  
  mat <- matrix(
    stats::rnorm(n_genes * n_cells),
    nrow = n_genes,
    ncol = n_cells
  )
  
  rownames(mat) <- sprintf(
    "GENE%02d",
    seq_len(n_genes)
  )
  
  colnames(mat) <- sprintf(
    "cell_%02d",
    seq_len(n_cells)
  )
  
  mat
}


test_that("hierarchical_clustering_cna returns hclust with all cell labels", {
  mat <- make_small_cna_matrix(
    n_genes = 15,
    n_cells = 8
  )
  
  hc <- hierarchical_clustering_cna(mat)
  
  expect_s3_class(hc, "hclust")
  
  expect_setequal(
    hc$labels,
    colnames(mat)
  )
  
  expect_equal(
    length(hc$order),
    ncol(mat)
  )
})


test_that("dendrogram_plot builds a valid ggplot", {
  skip_if_not_installed("ggdendro")
  skip_if_not_installed("dbscan")
  
  mat <- make_small_cna_matrix(
    n_genes = 15,
    n_cells = 8
  )
  
  hc <- hierarchical_clustering_cna(mat)
  
  p <- dendrogram_plot(hc)
  
  expect_s3_class(p, "ggplot")
  expect_no_error(ggplot2::ggplot_build(p))
})


test_that("umap_cna returns one two-dimensional coordinate per cell", {
  skip_if_not_installed("irlba")
  skip_if_not_installed("uwot")
  
  mat <- make_small_cna_matrix(
    n_genes = 30,
    n_cells = 30
  )
  
  config <- list(
    params = list(seed = 3988)
  )
  
  res <- umap_cna(
    mat,
    config,
    n_pcs = 5,
    umap_neighbors = 10
  )
  
  expect_equal(
    dim(res),
    c(ncol(mat), 2L)
  )
  
  expect_true(all(is.finite(res)))
})


test_that("hdbscan_clustering_cna preserves cell labels and returns UMAP", {
  skip_if_not_installed("irlba")
  skip_if_not_installed("uwot")
  skip_if_not_installed("dbscan")
  
  mat <- make_small_cna_matrix(
    n_genes = 30,
    n_cells = 30
  )
  
  config <- list(
    params = list(seed = 3988)
  )
  
  res <- hdbscan_clustering_cna(
    mat,
    config,
    n_pcs = 5,
    umap_neighbors = 10,
    hdbscan_minPts = 3
  )
  
  expect_length(res, 2)
  
  clustering <- res[[1]]
  embedding <- res[[2]]
  
  expect_s3_class(clustering, "hdbscan")
  
  expect_equal(
    dim(embedding),
    c(ncol(mat), 2L)
  )
  
  expect_equal(
    clustering$hc$labels,
    colnames(mat)
  )
})