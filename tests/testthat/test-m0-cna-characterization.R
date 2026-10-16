test_that("CNA computation rejects an empty reference set cleanly", {
  inputs <- make_cna_golden_inputs()
  empty_ref_cells <- inputs$ref_cells[0, ]

  expect_error(
    compute_cna(
      inputs$expmat,
      inputs$gene_positions,
      empty_ref_cells
    ),
    "requires at least one reference cell",
    class = "cna_ineligible_error"
  )
})

test_that("CNA computation rejects non-finite expression values", {
  inputs <- make_cna_golden_inputs()
  inputs$expmat[1, 1] <- Inf

  expect_error(
    compute_cna(inputs$expmat, inputs$gene_positions, inputs$ref_cells),
    "non-finite expression values",
    class = "cna_input_error"
  )
})

test_that("CNA computation classifies missing positioned genes as ineligible", {
  inputs <- make_cna_golden_inputs()
  inputs$gene_positions$symbol <- paste0("NOT_PRESENT_", seq_len(nrow(inputs$gene_positions)))

  expect_error(
    compute_cna(inputs$expmat, inputs$gene_positions, inputs$ref_cells),
    "No expression genes have genomic positions",
    class = "cna_ineligible_error"
  )
})

test_that("CNA clustering rejects non-finite matrix values cleanly", {
  hdata <- matrix(
    c(1, 2, 3, 1, NA, 3, 3, 2, 1),
    nrow = 3,
    dimnames = list(NULL, c("cell_1", "cell_2", "cell_3"))
  )

  expect_error(
    hierarchical_clustering_cna(hdata),
    "contains non-finite values",
    class = "cna_input_error"
  )
})

test_that("CNA clustering classifies a single candidate as ineligible", {
  hdata <- matrix(
    c(1, 2, 3),
    ncol = 1,
    dimnames = list(NULL, "cell_1")
  )

  expect_error(
    hierarchical_clustering_cna(hdata),
    "fewer than two candidate cells",
    class = "cna_ineligible_error"
  )
})

test_that("M0 characterization: existence-only cache check accepts corrupt cache", {
  skip_if_not_installed("qs2")

  dataset_dir <- withr::local_tempdir()
  cache_dir <- setup_cache_dir(dataset_dir)
  corrupt_name <- "corrupt.qs2"
  writeLines("not a qs2 object", file.path(cache_dir, corrupt_name))

  expect_true(cache_check_exists(corrupt_name, dataset_dir))
  expect_error(cache_load_data(corrupt_name, dataset_dir))
})
