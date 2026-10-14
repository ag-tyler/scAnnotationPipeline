ui_baseline_prerequisites <- function(app_dir, dataset_name) {
  config_path <- file.path(app_dir, "general_config.yaml")
  if (!file.exists(config_path)) {
    return("general_config.yaml is unavailable")
  }

  config <- yaml::read_yaml(config_path)
  resource_paths <- file.path(
    app_dir,
    config$paths$resources_dir,
    unlist(config$resource_files, use.names = FALSE)
  )
  missing_resources <- resource_paths[!file.exists(resource_paths)]
  if (length(missing_resources) > 0) {
    return("local biological resources are unavailable")
  }

  dataset_dir <- file.path(app_dir, config$paths$datasets_dir, dataset_name)
  required_dataset_paths <- file.path(
    dataset_dir,
    c(
      config$config_files$dataset,
      config$config_files$samples,
      config$config_files$selected,
      config$dataset_paths$processed_dir
    )
  )
  if (any(!file.exists(required_dataset_paths))) {
    return(paste0("the local ", dataset_name, " UI workspace is unavailable"))
  }

  NULL
}

make_ui_baseline_app <- function(source_app_dir, .local_envir = parent.frame()) {
  test_app_dir <- withr::local_tempdir(
    pattern = "scannotation-ui-",
    .local_envir = .local_envir
  )
  dir.create(file.path(test_app_dir, "util_scripts"))

  file.copy(
    file.path(source_app_dir, "app.R"),
    file.path(test_app_dir, "app.R")
  )
  file.copy(
    list.files(
      file.path(source_app_dir, "util_scripts"),
      pattern = "[.]R$",
      full.names = TRUE
    ),
    file.path(test_app_dir, "util_scripts")
  )

  config <- yaml::read_yaml(file.path(source_app_dir, "general_config.yaml"))
  config$paths$resources_dir <- normalizePath(
    file.path(source_app_dir, config$paths$resources_dir),
    winslash = "/"
  )
  config$paths$datasets_dir <- normalizePath(
    file.path(source_app_dir, config$paths$datasets_dir),
    winslash = "/"
  )
  yaml::write_yaml(config, file.path(test_app_dir, "general_config.yaml"))

  test_app_dir
}

expect_ui_baseline_screenshot <- function(app, baseline_dir, filename) {
  actual_path <- tempfile(fileext = ".png")
  app$get_screenshot(file = actual_path, selector = "viewport")

  baseline_path <- file.path(baseline_dir, filename)
  if (identical(Sys.getenv("UPDATE_UI_BASELINES"), "true")) {
    dir.create(baseline_dir, recursive = TRUE, showWarnings = FALSE)
    file.copy(actual_path, baseline_path, overwrite = TRUE)
  }

  expect_true(
    file.exists(baseline_path),
    info = paste0(
      "Missing UI baseline: ", baseline_path,
      ". Rerun with UPDATE_UI_BASELINES=true after reviewing the current UI."
    )
  )
  if (file.exists(baseline_path)) {
    expect_true(
      shinytest2::compare_screenshot_threshold(
        baseline_path,
        actual_path,
        threshold = 5
      ),
      info = paste("UI differs from baseline", baseline_path)
    )
  }
}

test_that("baseline workflow navigation is preserved", {
  skip_if_not_installed("shinytest2")

  browser_path <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  skip_if(is.null(browser_path) || !nzchar(browser_path), "no Chromium browser is configured")

  source_app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  dataset_name <- "Che2021_Colorectal"
  browser_variant <- shinytest2::platform_variant()
  baseline_dir <- testthat::test_path(
    "fixtures",
    "ui-baseline",
    browser_variant
  )
  missing_prerequisite <- ui_baseline_prerequisites(source_app_dir, dataset_name)
  skip_if(!is.null(missing_prerequisite), missing_prerequisite)

  test_app_dir <- make_ui_baseline_app(source_app_dir)

  app <- shinytest2::AppDriver$new(
    app_dir = test_app_dir,
    name = "app-baseline",
    variant = browser_variant,
    seed = 3988,
    width = 1440,
    height = 1000,
    load_timeout = 60000,
    timeout = 60000
  )
  on.exit(app$stop(), add = TRUE)

  expect_equal(app$get_value(input = "main_nav"), "dataset_tab")
  expect_match(app$get_text("body"), "Initialize Pipeline", fixed = TRUE)
  expect_ui_baseline_screenshot(app, baseline_dir, "01-dataset-selection.png")

  app$set_inputs(dataset_choice = dataset_name, wait_ = FALSE)
  app$click(input = "btn_load_dataset", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)

  expect_equal(app$get_value(input = "main_nav"), "menu_tab")
  expect_match(app$get_text("body"), "Pipeline Dashboard", fixed = TRUE)
  expect_ui_baseline_screenshot(app, baseline_dir, "02-start-menu.png")

  app$click(input = "btn_go_res", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_equal(app$get_value(input = "main_nav"), "res_tab")
  expect_match(app$get_text("body"), "Resolution Selection", fixed = TRUE)
  expect_ui_baseline_screenshot(app, baseline_dir, "03-resolution-selection.png")

  app$click(input = "btn_back_menu_1", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$click(input = "btn_go_anno", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_equal(app$get_value(input = "main_nav"), "anno_tab")
  expect_match(app$get_text("body"), "Manual Cell Type Annotation", fixed = TRUE)
  expect_ui_baseline_screenshot(app, baseline_dir, "04-manual-annotation.png")

  app$click(input = "btn_back_menu_2", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$click(input = "btn_go_cna", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_equal(app$get_value(input = "main_nav"), "cna_tab")
  expect_match(app$get_text("body"), "CNA Pipeline Controls", fixed = TRUE)
  expect_ui_baseline_screenshot(app, baseline_dir, "05-cna-analysis.png")

  app_logs <- app$get_logs()
  error_logs <- app_logs[
    app_logs$level == "error" |
      grepl("Error|Execution halted", app_logs$message, ignore.case = TRUE),
    ,
    drop = FALSE
  ]
  expect_equal(nrow(error_logs), 0L, info = paste(error_logs$message, collapse = "\n"))
})
