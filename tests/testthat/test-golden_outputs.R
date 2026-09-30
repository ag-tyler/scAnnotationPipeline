# Golden-file regression tests: catch silent numeric drift in deterministic
# functions that unit tests (which check structure/invariants) wouldn't
# notice. Baselines live in fixtures/*_golden.rds and are only ever
# refreshed deliberately, via fixtures/generate_golden_fixtures.R -- never
# automatically.
#
# compute_cna() is a good candidate: it's pure arithmetic (no PCA/UMAP/
# clustering randomness to drift across package versions), so an exact
# match is a meaningful, low-flake check.

test_that("compute_cna output matches the stored golden baseline", {
  golden_path <- testthat::test_path("fixtures", "compute_cna_golden.rds")

  skip_if_not(
    file.exists(golden_path),
    paste(
      "Golden fixture not generated yet. Run once from the repo root:",
      "  Rscript tests/testthat/fixtures/generate_golden_fixtures.R",
      sep = "\n"
    )
  )

  golden <- readRDS(golden_path)
  inputs <- make_cna_golden_inputs()

  current <- compute_cna(inputs$expmat, inputs$gene_positions, inputs$ref_cells)

  expect_equal(current, golden, tolerance = 1e-8)
})
