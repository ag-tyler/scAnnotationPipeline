test_that("creation filename and source disclosures support keyboard input at desktop and narrow widths", {
  skip_if_not_installed("shinytest2")
  browser <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  skip_if(is.null(browser) || !nzchar(browser), "no Chromium browser is configured")
  withr::local_envvar(NOT_CRAN = "true")
  app_dir <- withr::local_tempdir()
  root <- testthat::test_path("..", "..")
  file.copy(file.path(root, "app", "ui", "dataset_ui.R"), app_dir)
  file.copy(file.path(root, "util_scripts", "07_utils_state.R"), app_dir)
  writeLines(c(
    "library(shiny); library(bslib)",
    "source('07_utils_state.R', encoding = 'UTF-8')",
    "source('dataset_ui.R', encoding = 'UTF-8')",
    "ui <- page_fluid(actionButton('show_dialog', 'Create dataset'))",
    "server <- function(input, output, session) {",
    "  observeEvent(input$show_dialog, {",
    "    showModal(dataset_import_dialog(tempdir(), project_info = list(",
    "      source_doi = '10.1234/template', source_url = 'https://example.org/database'),",
    "      std_names = list(expmat = 'expression.mtx', genes = 'symbols.txt',",
    "        cells = 'cells.csv', samples = 'samples.csv')))",
    "  })",
    "}",
    "shinyApp(ui, server)"
  ), file.path(app_dir, "app.R"))
  app <- shinytest2::AppDriver$new(app_dir = app_dir, name = "dc04-source-layout",
    width = 1280, height = 900, load_timeout = 60000, timeout = 60000)
  on.exit(app$stop(), add = TRUE)
  app$click("show_dialog")
  # Bootstrap moves focus inside the modal after its opening transition. Wait
  # for that handoff before moving focus to the disclosure summary.
  app$wait_for_js("(() => { const modal = document.querySelector('.modal'); return modal && modal.contains(document.activeElement); })()")
  expect_false(app$get_js("document.querySelector('#new_ds_filenames').open"))
  expect_false(app$get_js("document.querySelector('#new_ds_origin').open"))
  closed_height <- app$get_js("document.querySelector('#new_ds_origin').getBoundingClientRect().height")
  artifact_dir <- Sys.getenv("DC04_ARTIFACT_DIR")
  if (nzchar(artifact_dir)) app$get_screenshot(
    file = tempfile("dc04-source-collapsed-", tmpdir = artifact_dir, fileext = ".png"), selector = "viewport")
  app$get_js("document.querySelector('#new_ds_origin summary').focus(); true")
  expect_identical(app$get_js("document.activeElement.tagName"), "SUMMARY")
  cdp <- app$get_chromote_session()
  press <- function(key, code) {
    cdp$Input$dispatchKeyEvent(type = "keyDown", key = key, code = key,
      windowsVirtualKeyCode = code, text = if (key == "Enter") "\r" else "")
    cdp$Input$dispatchKeyEvent(type = "keyUp", key = key, code = key, windowsVirtualKeyCode = code)
  }
  app$get_js("document.querySelector('#new_ds_filenames summary').focus(); true")
  press("Enter", 13L)
  expect_true(app$get_js("document.querySelector('#new_ds_filenames').open"))
  press("Tab", 9L)
  expect_identical(app$get_js("document.activeElement.id"), "new_ds_std_expmat")
  defaults <- list(expmat = "expression.mtx", genes = "symbols.txt",
    cells = "cells.csv", samples = "samples.csv")
  for (key in names(defaults)) {
    expect_identical(app$get_value(input = paste0("new_ds_std_", key)), defaults[[key]])
  }
  app$set_inputs(new_ds_std_expmat = "my expression.mtx", new_ds_std_genes = "my genes.txt",
    new_ds_std_cells = "my cells.csv", new_ds_std_samples = "my samples.csv")
  app$get_js("document.querySelector('#new_ds_origin summary').focus(); true")
  press("Enter", 13L)
  expect_true(app$get_js("document.querySelector('#new_ds_origin').open"))
  expect_gt(app$get_js("document.querySelector('#new_ds_origin').getBoundingClientRect().height"), closed_height + 100)
  press("Tab", 9L)
  expect_identical(app$get_js("document.activeElement.id"), "new_ds_source_doi")
  expect_identical(app$get_value(input = "new_ds_source_doi"), "10.1234/template")
  expect_identical(app$get_value(input = "new_ds_source_url"), "https://example.org/database")
  app$set_inputs(new_ds_source_doi = "10.1234/edited", new_ds_source_url = "https://example.org/edited")
  for (width in c(1280, 375)) {
    app$set_window_size(width = width, height = 900)
    metrics <- app$get_js("(() => {
      const body = document.querySelector('.modal-body');
      const inputs = Array.from(document.querySelectorAll('#new_ds_filenames input, #new_ds_origin input'));
      return {width: document.documentElement.clientWidth,
        scrollWidth: document.documentElement.scrollWidth,
        bodyWidth: body.clientWidth, bodyScrollWidth: body.scrollWidth,
        inputs: inputs.map(input => ({width: input.getBoundingClientRect().width,
          left: input.getBoundingClientRect().left, right: input.getBoundingClientRect().right,
          label: document.querySelector('label[for=' + input.id + ']').textContent}))};
    })()")
    expect_lte(metrics$scrollWidth, metrics$width + 1)
    expect_lte(metrics$bodyScrollWidth, metrics$bodyWidth + 1)
    expect_length(metrics$inputs, 6)
    for (input in metrics$inputs) {
      expect_gt(input$width, 100)
      expect_gte(input$left, 0)
      expect_lte(input$right, metrics$width + 1)
      expect_true(input$label %in% c("Expression matrix filename", "Gene list filename",
        "Cell metadata filename", "Sample metadata filename", "Paper DOI", "Database URL"))
    }
    if (nzchar(artifact_dir)) app$get_screenshot(
      file = tempfile(paste0("dc04-source-expanded-", width, "-"),
        tmpdir = artifact_dir, fileext = ".png"), selector = "viewport")
  }
  app$get_js("document.querySelector('#new_ds_origin summary').focus(); true")
  press("Enter", 13L)
  expect_false(app$get_js("document.querySelector('#new_ds_origin').open"))
  press("Enter", 13L)
  expect_identical(app$get_value(input = "new_ds_source_doi"), "10.1234/edited")
  expect_identical(app$get_value(input = "new_ds_source_url"), "https://example.org/edited")
  app$get_js("document.querySelector('#new_ds_filenames summary').focus(); true")
  press("Enter", 13L)
  expect_false(app$get_js("document.querySelector('#new_ds_filenames').open"))
  press("Enter", 13L)
  expect_identical(app$get_value(input = "new_ds_std_expmat"), "my expression.mtx")
  expect_identical(app$get_value(input = "new_ds_std_genes"), "my genes.txt")
  expect_identical(app$get_value(input = "new_ds_std_cells"), "my cells.csv")
  expect_identical(app$get_value(input = "new_ds_std_samples"), "my samples.csv")
})
