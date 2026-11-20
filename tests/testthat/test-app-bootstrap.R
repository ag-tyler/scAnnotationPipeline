test_that("Shiny package-directory support autoload is disabled", {
  skip_if_not_installed("shiny")

  app_dir <- testthat::test_path("..", "..")

  expect_no_warning(
    shiny:::loadSupport(
      appDir = app_dir,
      renv = new.env(parent = emptyenv()),
      globalrenv = NULL
    )
  )
})

test_that("componentized app entry point assembles a Shiny application", {
  skip_if_not_installed("shiny")

  source_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  app_dir <- make_ui_baseline_app(source_dir)
  app <- shiny::as.shiny.appobj(app_dir)

  expect_s3_class(app, "shiny.appobj")
  expect_type(app$serverFuncSource, "closure")
})


test_that("component loading preserves the dashboard dash in a C-locale R worker", {
  source_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  app_dir <- make_ui_baseline_app(source_dir)
  script <- paste0(
    'invisible(Sys.setlocale("LC_CTYPE", "C")); ',
    'suppressPackageStartupMessages(source("app.R")); ',
    'summary <- summarize_pipeline_overview(new_pipeline_state("UTF8", "sample1")); ',
    'html <- as.character(pipeline_status_overview_ui(summary)); ',
    'stopifnot(grepl(intToUtf8(8212L), html, fixed=TRUE)); ',
    'cat("DASH_UTF8_OK")'
  )
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  result <- processx::run(rscript, c("--vanilla", "-e", script), wd = app_dir,
    error_on_status = FALSE, timeout = 60000)
  expect_equal(result$status, 0, info = result$stderr)
  expect_match(result$stdout, "DASH_UTF8_OK", fixed = TRUE)
})

test_that("stable launcher disables autoreload before starting Shiny", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  launcher_path <- file.path(app_dir, "scripts", "run_app.R")
  launcher_lines <- readLines(launcher_path, warn = FALSE)

  autoreload_line <- grep(
    "options(shiny.autoreload = FALSE)",
    launcher_lines,
    fixed = TRUE
  )
  run_app_line <- grep("shiny::runApp", launcher_lines, fixed = TRUE)

  expect_true(file.exists(launcher_path))
  expect_length(autoreload_line, 1L)
  expect_length(run_app_line, 1L)
  expect_lt(autoreload_line, run_app_line)
  expect_false(any(grepl("shiny.autoreload.legacy_warning", launcher_lines, fixed = TRUE)))
})


test_that("user documentation recommends the stable launcher", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  for (relative_path in c("README.md", "docs/USER_GUIDE.md")) {
    text <- paste(
      readLines(file.path(app_dir, relative_path), warn = FALSE),
      collapse = "\n"
    )
    expect_match(text, 'source("scripts/run_app.R")', fixed = TRUE)
    expect_true(
      grepl("shiny.autoreload = FALSE", text, fixed = TRUE) ||
        grepl("disabl[^\n]*autoreload", text, ignore.case = TRUE)
    )
  }
})
