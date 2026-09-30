#!/usr/bin/env Rscript
# tests/testthat/fixtures/generate_golden_fixtures.R
#
# Run this manually, from the REPO ROOT, whenever you *intentionally* change
# the behaviour of a function covered by a golden-file test, to refresh its
# baseline:
#
#   Rscript tests/testthat/fixtures/generate_golden_fixtures.R
#
# Do NOT run this just to make a failing golden test pass without first
# understanding *why* the output changed -- that defeats the entire point of
# a regression test. Review the diff in git before committing a refreshed
# .rds fixture.

if (!dir.exists("util_scripts")) {
  stop(
    "Run this from the repo root, e.g.:\n",
    "  Rscript tests/testthat/fixtures/generate_golden_fixtures.R",
    call. = FALSE
  )
}

invisible(lapply(
  list.files("util_scripts", pattern = "\\.R$", full.names = TRUE),
  source
))
source("tests/testthat/helper-fixtures.R")

# --- compute_cna() --------------------------------------------------------
inputs <- make_cna_golden_inputs()
golden_cna <- compute_cna(inputs$expmat, inputs$gene_positions, inputs$ref_cells)
saveRDS(golden_cna, "tests/testthat/fixtures/compute_cna_golden.rds")
message("Wrote tests/testthat/fixtures/compute_cna_golden.rds")
