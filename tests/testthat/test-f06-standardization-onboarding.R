suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
})

load_f06_ui <- function() {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  ui_env <- new.env(parent = globalenv())
  sys.source(file.path(app_dir, "app/ui/dataset_ui.R"), envir = ui_env)
  ui_env
}

test_that("F06 guide is available before a dataset is loaded", {
  ui_env <- load_f06_ui()
  prompt <- "Synthetic metadata prompt\nwith a second line."
  html <- as.character(ui_env$dataset_selection_panel("Demo", prompt))

  expect_match(html, "Standardization Guide", fixed = TRUE)
  expect_match(html, "standardization_prompt_text", fixed = TRUE)
  expect_match(html, "btn_select_standardization_prompt", fixed = TRUE)
  expect_match(html, "btn_copy_standardization_prompt", fixed = TRUE)
  expect_match(html, prompt, fixed = TRUE)
  expect_match(
    html,
    "pipeline-docs/STANDARDIZATION_CHECKLIST.md",
    fixed = TRUE
  )
  expect_match(
    html,
    "pipeline-docs/USER_GUIDE.md#setting-up-a-new-dataset",
    fixed = TRUE
  )
  expect_match(html, "datasets/&lt;dataset&gt;/standardize.R", fixed = TRUE)
  expect_match(html, "strict post-validation", fixed = TRUE)
  expect_match(html, "processed_data/", fixed = TRUE)
})

test_that("F06 workspace success dialog gives the exact next action", {
  ui_env <- load_f06_ui()
  dataset_path <- normalizePath(
    file.path(tempdir(), "F06_Demo"),
    winslash = "/",
    mustWork = FALSE
  )
  html <- as.character(ui_env$dataset_created_modal("F06_Demo", dataset_path))

  expect_match(html, "Workspace created: F06_Demo", fixed = TRUE)
  expect_match(html, dataset_path, fixed = TRUE)
  expect_match(
    html,
    file.path(dataset_path, "standardize.R"),
    fixed = TRUE
  )
  expect_match(html, "strict post-validation", fixed = TRUE)
  expect_match(html, "btn_open_standardization_guide", fixed = TRUE)
})

test_that("F06 onboarding remains wired to creation and guarded loading", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  server_text <- paste(
    readLines(file.path(app_dir, "app/server/dataset_server.R"), warn = FALSE),
    collapse = "\n"
  )
  app_text <- paste(
    readLines(file.path(app_dir, "app.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(
    server_text,
    'showModal(dataset_created_modal(ds_name, resolved_new_path))',
    fixed = TRUE
  )
  expect_match(
    server_text,
    'nav_select("dataset_setup_view", "standardization_guide")',
    fixed = TRUE
  )
  expect_match(server_text, "navigator.clipboard.writeText", fixed = TRUE)
  expect_match(server_text, "!dir.exists(processed_dir_path)", fixed = TRUE)
  expect_match(server_text, "length(sample_dir_paths) == 0", fixed = TRUE)
  expect_match(app_text, 'addResourcePath("pipeline-docs"', fixed = TRUE)
})
