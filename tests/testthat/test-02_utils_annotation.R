# These functions all call into `matkot` (col_nnz / to_frac / log_transform),
# a GitHub-only dependency (see README.md "Requirements"). skip_if_not_installed
# lets the suite run cleanly on machines/CI where it hasn't been installed,
# while still testing the real thing wherever it is available.

test_that("filter_cell_gene_count keeps only cells above the min_genes threshold", {
  skip_if_not_installed("matkot")

  mat <- make_mini_expmat(n_genes = 30, n_cells = 20, n_low_count_cells = 3, n_low_expr_genes = 0)
  cells <- make_mini_cells_dt(colnames(mat))

  # The 3 engineered low-count cells have nnz == 2 (see helper-fixtures.R);
  # everything else has much higher density (~0.6 * 30 genes).
  filtered <- filter_cell_gene_count(cells, mat, min_genes = 3)

  expect_true(nrow(filtered) < nrow(cells))
  expect_setequal(filtered$cell_name, colnames(mat)[-(1:3)])
})

test_that("filter_cell_gene_count keeps everyone when the threshold is trivially low", {
  skip_if_not_installed("matkot")

  mat <- make_mini_expmat(n_genes = 30, n_cells = 20, n_low_count_cells = 3, n_low_expr_genes = 0)
  cells <- make_mini_cells_dt(colnames(mat))

  filtered <- filter_cell_gene_count(cells, mat, min_genes = 0)

  expect_equal(nrow(filtered), nrow(cells))
})

test_that("gene_expr_filter drops genes with zero expression everywhere", {
  skip_if_not_installed("matkot")

  mat <- make_mini_expmat(n_genes = 30, n_cells = 20, n_low_count_cells = 0, n_low_expr_genes = 5)
  zero_genes <- rownames(mat)[(nrow(mat) - 4):nrow(mat)]

  normalized <- log_normalize_expmat(mat, colnames(mat), target_sum = 1e5)
  kept_genes <- gene_expr_filter(normalized, target_sum = 1e5, log2_threshold = 0.1)

  expect_true(is.character(kept_genes))
  expect_true(all(kept_genes %in% rownames(mat)))
  expect_false(any(zero_genes %in% kept_genes))
})

test_that("log_normalize_expmat only returns the requested cell_names, in that order", {
  skip_if_not_installed("matkot")

  mat <- make_mini_expmat(n_genes = 10, n_cells = 8)
  subset_cells <- colnames(mat)[c(5, 2, 7)]

  normalized <- log_normalize_expmat(mat, subset_cells, target_sum = 1e5)

  expect_equal(colnames(normalized), subset_cells)
  expect_equal(nrow(normalized), nrow(mat))
})
