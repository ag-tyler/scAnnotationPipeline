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

test_that("hierarchical_clustering_cna reports zero-variance profiles", {
  mat <- matrix(
    c(1, 1, 1, 1, 2, 3),
    nrow = 3,
    dimnames = list(paste0("gene_", 1:3), c("constant", "variable"))
  )

  expect_error(
    hierarchical_clustering_cna(mat),
    "zero variance",
    class = "cna_input_error"
  )
})


test_that("CNA cluster labels remain numerically ordered above ten clusters", {
  choices <- cna_cluster_choices(12)

  expect_identical(unname(choices), as.character(1:12))
  expect_identical(
    names(choices),
    sprintf("Cluster %02d", 1:12)
  )
  expect_identical(cna_cluster_labels(c(2, 10), 12), c("Cluster 02", "Cluster 10"))
})


test_that("CNA cluster plot legend uses the canonical cluster order", {
  cluster_levels <- cna_cluster_labels(1:12, 12)
  cells <- data.frame(
    cell_num = 1:12,
    k_cluster = factor(rev(cluster_levels), levels = cluster_levels)
  )
  colors <- stats::setNames(viridis::viridis(12), cluster_levels)

  plot <- cluster_or_cell_type_bar_plot(
    cells,
    "k_cluster",
    "Cluster ID (k=12)",
    custom_colors = colors
  )
  built_plot <- ggplot2::ggplot_build(plot)
  fill_scale <- built_plot$plot$scales$get_scales("fill")

  expect_identical(as.character(fill_scale$get_breaks()), cluster_levels)
  expect_identical(plot$labels$fill, "Cluster ID (k=12)")
})
