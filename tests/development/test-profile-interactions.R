# Development-tool contract; run explicitly from a development checkout.
# App runtime performance regressions remain in tests/testthat/.
test_that("F14 profiling entry point is portable and read-only", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  profile_path <- file.path(app_dir, "scripts/profile_interactions.R")
  expect_true(file.exists(profile_path))
  profile_text <- paste(readLines(profile_path, warn = FALSE), collapse = "\n")
  expect_match(profile_text, "benchmark_expression", fixed = TRUE)
  expect_match(profile_text, "dataset_cleanup_readiness", fixed = TRUE)
  expect_match(profile_text, "cna_sample_preflight", fixed = TRUE)
  expect_match(profile_text, "cell_type_annotation_setup", fixed = TRUE)
  expect_false(grepl("write_yaml|fwrite|cache_save_data", profile_text))
})
