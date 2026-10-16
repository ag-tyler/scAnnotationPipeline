test_that("M0 characterization: CNA computation exposes empty reference input", {
  inputs <- make_cna_golden_inputs()
  empty_ref_cells <- inputs$ref_cells[0, ]

  warning_messages <- character()
  cna <- withCallingHandlers(
    compute_cna(
      inputs$expmat,
      inputs$gene_positions,
      empty_ref_cells
    ),
    warning = function(w) {
      warning_messages <<- c(warning_messages, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  expect_match(paste(warning_messages, collapse = "\n"), "no non-missing arguments")
  expect_match(paste(warning_messages, collapse = "\n"), "returning Inf")
  expect_match(paste(warning_messages, collapse = "\n"), "returning -Inf")
  expect_true(any(!is.finite(cna$cna)))
})

test_that("M0 characterization: CNA clustering rejects non-finite correlations", {
  hdata <- matrix(
    c(1, 2, 3, 1, NA, 3, 3, 2, 1),
    nrow = 3,
    dimnames = list(NULL, c("cell_1", "cell_2", "cell_3"))
  )

  expect_error(
    hierarchical_clustering_cna(hdata),
    "NA/NaN/Inf"
  )
})

test_that("M0 characterization: CNA clustering rejects a single object", {
  hdata <- matrix(
    c(1, 2, 3),
    ncol = 1,
    dimnames = list(NULL, "cell_1")
  )

  expect_error(
    hierarchical_clustering_cna(hdata),
    "must have n >= 2 objects"
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
