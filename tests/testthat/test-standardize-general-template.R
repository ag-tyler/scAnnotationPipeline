general_template_path <- testthat::test_path(
  "..",
  "..",
  "templates",
  "standardize_general.R"
)

load_general_template <- function() {
  template_env <- new.env(parent = environment())
  suppressMessages(sys.source(general_template_path, envir = template_env))
  template_env
}


test_that("general standardization template parses and is safe by default", {
  expect_error(parse(general_template_path), NA)

  template_env <- load_general_template()
  expect_false(template_env$RUN_STANDARDIZATION)
  expect_true(is.function(template_env$prepare_raw_data))
  expect_true(is.function(template_env$load_sample_input))
  expect_true(is.function(template_env$prepare_standardized_sample))
  expect_true(is.function(template_env$run_general_standardization))
})


test_that("general template requires completed settings and a supported scale", {
  template_env <- load_general_template()

  expect_error(
    template_env$validate_general_settings(template_env$settings),
    "Complete USER SETTINGS"
  )

  settings <- template_env$settings
  settings$app_folder_path <- tempdir()
  settings$dataset_name <- "dataset1"
  settings$matrix_state <- "log2"
  expect_error(
    template_env$validate_general_settings(settings),
    "UMIcounts, TPM, CPM"
  )
})


test_that("general template aligns metadata and preserves duplicate-gene expression", {
  template_env <- load_general_template()
  expmat <- Matrix::Matrix(
    matrix(
      c(
        1, 2,
        3, 4,
        5, 6
      ),
      nrow = 3,
      byrow = TRUE
    ),
    sparse = TRUE
  )
  cell_metadata <- data.frame(
    cell_name = c("cell2", "cell1"),
    cell_type = c("Type B", "Type A")
  )

  standardized <- suppressMessages(
    template_env$prepare_standardized_sample(
      sample_input = list(
        expmat = expmat,
        genes = c("GENE1", "GENE1", ""),
        cells = c("cell1", "cell2"),
        cell_metadata = cell_metadata
      ),
      sample_name = "sample1",
      sample_meta = list(patient = "patient1", site = "primary"),
      matrix_state = "UMIcounts"
    )
  )

  expect_equal(standardized$genes, "GENE1")
  expect_equal(as.numeric(standardized$expmat[1, ]), c(4, 6))
  expect_equal(standardized$cells$cell_name, c("cell1", "cell2"))
  expect_equal(standardized$cells$cell_type, c("Type A", "Type B"))
  expect_true(all(standardized$cells$sample == "sample1"))
  expect_true(all(standardized$cells$patient == "patient1"))
  expect_true(all(standardized$cells$source == "primary"))
  expect_equal(standardized$cells$complexity, c(1, 1))
})


test_that("general template rejects invalid matrix and cell alignment", {
  template_env <- load_general_template()
  expmat <- Matrix::Matrix(matrix(c(1, 2, 3, 4), nrow = 2), sparse = TRUE)
  sample_meta <- list(patient = "patient1", site = "primary")

  expect_error(
    template_env$prepare_standardized_sample(
      list(expmat = expmat, genes = c("G1", "G2"), cells = "cell1"),
      "sample1",
      sample_meta,
      "UMIcounts"
    ),
    "cells length.*matrix columns"
  )

  fractional <- expmat
  fractional@x[1] <- 1.5
  expect_error(
    template_env$prepare_standardized_sample(
      list(
        expmat = fractional,
        genes = c("G1", "G2"),
        cells = c("cell1", "cell2")
      ),
      "sample1",
      sample_meta,
      "UMIcounts"
    ),
    "UMI counts must be integers"
  )
})


test_that("standardization checklist documents the general-template workflow", {
  root_dir <- test_path("..", "..")
  checklist_path <- file.path(root_dir, "docs", "STANDARDIZATION_CHECKLIST.md")
  user_guide_path <- file.path(root_dir, "docs", "USER_GUIDE.md")

  expect_true(file.exists(checklist_path))

  checklist <- paste(readLines(checklist_path, warn = FALSE), collapse = "\n")
  for (required_text in c(
    "## Definition of done",
    "`prepare_raw_data()`",
    "`load_sample_input()`",
    "POST-VALIDATION PASSED",
    "## 11. Repeat-run checklist",
    "## 12. Reproducibility record"
  )) {
    expect_match(checklist, required_text, fixed = TRUE)
  }

  user_guide <- paste(readLines(user_guide_path, warn = FALSE), collapse = "\n")
  expect_match(
    user_guide,
    "[Standardization Checklist](STANDARDIZATION_CHECKLIST.md)",
    fixed = TRUE
  )
})
