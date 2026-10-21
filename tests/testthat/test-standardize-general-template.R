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


test_that("general standardization template is safe and shows the complete workflow", {
  expect_error(parse(general_template_path), NA)

  template_env <- load_general_template()
  expect_false(template_env$RUN_STANDARDIZATION)
  expect_true(is.function(template_env$find_standardization_app_root))

  template_text <- paste(readLines(general_template_path), collapse = "\n")
  for (required_text in c(
    "BEGIN USER CODE",
    "END USER CODE",
    '"08_utils_standardization.R"',
    "initialize_standardization(settings)",
    "prepare_standardized_sample(",
    "register_standardized_sample(",
    "write_standardized_samples_table(standardization)",
    "validate_standardization(",
    "strict = TRUE",
    "publish_standardization(standardization, validation)"
  )) {
    expect_match(template_text, required_text, fixed = TRUE)
  }
  expect_false(grepl("prepare_raw_data <- function", template_text, fixed = TRUE))
  expect_false(grepl("load_sample_input <- function", template_text, fixed = TRUE))
})


test_that("template automatically finds the application root", {
  template_env <- load_general_template()
  nested_dir <- file.path(tempdir(), paste0("standardization-root-", Sys.getpid()))
  dir.create(file.path(nested_dir, "datasets", "example"), recursive = TRUE)
  dir.create(file.path(nested_dir, "util_scripts"), recursive = TRUE)
  file.create(file.path(nested_dir, "general_config.yaml"))

  old_wd <- setwd(file.path(nested_dir, "datasets", "example"))
  on.exit(setwd(old_wd), add = TRUE)
  detected_root <- template_env$find_standardization_app_root()
  expected_root <- normalizePath(nested_dir, winslash = "/")
  expect_equal(
    tolower(utils::shortPathName(detected_root)),
    tolower(utils::shortPathName(expected_root))
  )
})


test_that("standardization settings require a supported matrix state", {
  settings <- list(
    app_folder_path = tempdir(),
    dataset_name = "dataset1",
    matrix_state = "log2",
    reset_selected_config = FALSE
  )
  expect_error(
    validate_standardization_settings(settings),
    "UMIcounts, TPM, CPM"
  )
  settings$matrix_state <- "UMIcounts"
  validated <- validate_standardization_settings(settings)
  expect_equal(validated$matrix_state, "UMIcounts")
})


test_that("sample mapping helpers preserve order and report mismatches", {
  mapping <- c(raw_a = "sample1", raw_b = "sample2")
  expect_equal(
    map_standardization_sample_ids(c("raw_b", "raw_a", "raw_b"), mapping),
    c("sample2", "sample1", "sample2")
  )
  expect_error(
    map_standardization_sample_ids(c("raw_a", "raw_c"), mapping),
    "raw_c"
  )
  expect_true(
    validate_standardization_sample_mapping(
      c("sample2", "sample1"),
      c("sample1", "sample2")
    )
  )
  expect_error(
    validate_standardization_sample_mapping("sample1", c("sample1", "sample2")),
    "Missing: sample2"
  )
})


test_that("sample preparation aligns metadata and preserves duplicate-gene expression", {
  expmat <- Matrix::Matrix(
    matrix(c(1, 2, 3, 4, 5, 6), nrow = 3, byrow = TRUE),
    sparse = TRUE
  )
  cell_metadata <- data.frame(
    cell_name = c("cell2", "cell1"),
    cell_type = c("Type B", "Type A")
  )

  standardized <- suppressMessages(
    prepare_standardized_sample(
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


test_that("sample preparation rejects invalid matrix and cell alignment", {
  expmat <- Matrix::Matrix(matrix(c(1, 2, 3, 4), nrow = 2), sparse = TRUE)
  sample_meta <- list(patient = "patient1", site = "primary")

  expect_error(
    prepare_standardized_sample(
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
    prepare_standardized_sample(
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


test_that("staged publishing replaces old output only after preparation", {
  parent <- tempfile("standardization-publish-")
  final_dir <- file.path(parent, "processed_data")
  staging_dir <- paste0(final_dir, "_staging")
  dir.create(final_dir, recursive = TRUE)
  dir.create(staging_dir)
  writeLines("old", file.path(final_dir, "old.txt"))
  writeLines("new", file.path(staging_dir, "new.txt"))

  context <- new.env(parent = emptyenv())
  context$processed_dir_path <- final_dir
  context$working_dir_path <- staging_dir
  .publish_staged_standardization(context)

  expect_false(file.exists(file.path(final_dir, "old.txt")))
  expect_true(file.exists(file.path(final_dir, "new.txt")))
  expect_false(dir.exists(staging_dir))
  expect_false(dir.exists(paste0(final_dir, "_previous")))
})


test_that("standardization lifecycle validates staging before publishing", {
  app_dir <- tempfile("standardization-app-")
  dataset_name <- "dataset1"
  dataset_dir <- file.path(app_dir, "datasets", dataset_name)
  dir.create(file.path(dataset_dir, "data"), recursive = TRUE)
  dir.create(file.path(dataset_dir, "processed_data"))
  dir.create(file.path(dataset_dir, "logs"))
  dir.create(file.path(app_dir, "resources"), recursive = TRUE)
  writeLines("previous", file.path(dataset_dir, "processed_data", "previous.txt"))

  config <- list(
    paths = list(resources_dir = "resources", datasets_dir = "datasets"),
    dataset_paths = list(
      raw_dir = "data",
      processed_dir = "processed_data",
      results_dir = "results",
      logs_dir = "logs"
    ),
    config_files = list(
      dataset = "dataset_config.yaml",
      samples = "samples_config.yaml",
      selected = "selected_config.yaml",
      state = "pipeline_state.yaml"
    )
  )
  yaml::write_yaml(config, file.path(app_dir, "general_config.yaml"))
  yaml::write_yaml(
    list(
      project_info = list(dataset_id = dataset_name),
      std_names = list(
        expmat = "Exp_data_UMIcounts.mtx",
        genes = "Genes.txt",
        cells = "Cells.csv",
        samples = "Samples.csv"
      ),
      raw_files = list(type = "general")
    ),
    file.path(dataset_dir, "dataset_config.yaml")
  )
  yaml::write_yaml(
    list(samples = list(
      make_valid_sample_entry("sample1"),
      make_valid_sample_entry("sample2")
    )),
    file.path(dataset_dir, "samples_config.yaml")
  )

  context <- suppressMessages(initialize_standardization(list(
    app_folder_path = app_dir,
    dataset_name = dataset_name,
    matrix_state = "UMIcounts",
    reset_selected_config = FALSE
  )))
  expect_true(file.exists(file.path(context$processed_dir_path, "previous.txt")))

  for (sample_name in context$sample_names) {
    cell_names <- paste0(sample_name, "_cell", 1:2)
    prepared <- prepare_standardized_sample(
      sample_input = list(
        expmat = Matrix::Matrix(matrix(c(1, 0, 2, 3), nrow = 2), sparse = TRUE),
        genes = c("GENE1", "GENE2"),
        cells = cell_names
      ),
      sample_name = sample_name,
      sample_meta = context$samples_config$samples[[
        match(sample_name, context$sample_names)
      ]],
      matrix_state = "UMIcounts"
    )
    register_standardized_sample(context, sample_name, prepared)
  }
  write_standardized_samples_table(context)
  validation <- suppressMessages(validate_standardization(
    processed_dir_path = context$working_dir_path,
    sample_names = context$sample_names,
    std_names = context$std_names,
    strict = TRUE
  ))
  expect_true(validation$valid)
  expect_true(file.exists(file.path(context$processed_dir_path, "previous.txt")))

  suppressMessages(publish_standardization(context, validation))
  expect_false(file.exists(file.path(context$processed_dir_path, "previous.txt")))
  expect_true(file.exists(file.path(context$processed_dir_path, "Samples.csv")))
  expect_true(file.exists(file.path(dataset_dir, "selected_config.yaml")))
  state <- yaml::read_yaml(file.path(dataset_dir, "pipeline_state.yaml"))
  expect_equal(state$dataset_steps$standardization$status, "completed")
})


test_that("standardization checklist documents the linear user-code workflow", {
  root_dir <- test_path("..", "..")
  checklist_path <- file.path(root_dir, "docs", "STANDARDIZATION_CHECKLIST.md")
  user_guide_path <- file.path(root_dir, "docs", "USER_GUIDE.md")

  expect_true(file.exists(checklist_path))
  checklist <- paste(readLines(checklist_path, warn = FALSE), collapse = "\n")
  for (required_text in c(
    "## Definition of done",
    "BEGIN USER CODE",
    "`prepare_standardized_sample()`",
    "`register_standardized_sample()`",
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
