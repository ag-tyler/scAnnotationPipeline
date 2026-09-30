# Regression test for the CNA caching leg of the pipeline. Unlike the
# clustering regression test, this one doesn't touch PCA/UMAP/Seurat at all
# -- compute_cna() is pure arithmetic (already covered exactly by the golden
# test in test-golden_outputs.R) and qs2 caching is deterministic, so this
# can assert exact values, not just shape.

test_that("compute_cna_and_cache + load_expdt_from_cna_matrix round-trip correctly", {
  skip_if_not_installed("qs2")

  dataset_dir <- withr::local_tempdir()
  inputs <- make_cna_golden_inputs()

  expected <- compute_cna(inputs$expmat, inputs$gene_positions, inputs$ref_cells)

  compute_cna_and_cache(
    inputs$expmat, inputs$gene_positions, inputs$ref_cells,
    sample_name = "sample1", dataset_dir_path = dataset_dir
  )

  expect_true(cache_check_exists("cna_matrix_sample1.qs2", dataset_dir))

  roundtripped <- load_expdt_from_cna_matrix("sample1", dataset_dir)

  # Round-tripping through the wide cache format rounds `cna` to 4 decimals
  # (see compute_cna_and_cache()) and both sides get re-sorted by
  # chr/start_pos, so compare on that basis rather than expecting an exact
  # data.table match.
  data.table::setorder(expected, chr, start_pos, cell_name)
  data.table::setorder(roundtripped, chr, start_pos, cell_name)

  expect_equal(roundtripped$gene, expected$gene)
  expect_equal(roundtripped$cell_name, expected$cell_name)
  expect_equal(roundtripped$cna, round(expected$cna, 4), tolerance = 1e-8)
})

test_that("load_expdt_from_cna_matrix errors clearly when nothing has been cached yet", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()

  expect_error(
    load_expdt_from_cna_matrix("never_computed", dataset_dir),
    "Expected cached file not found"
  )
})
