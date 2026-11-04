c05_review_fixture <- function() {
  list(base_directory = "C:/synthetic application/working directory",
    destination = paste0("C:/synthetic review output/", paste(rep("long_destination_", 12), collapse = "")),
    inventory = list(files = data.frame(path = c(
      "results/COL07_liver_metastasis/3_cna_plots/cna_threshold_unscaled_selection_subclone_1_COL07_liver_metastasis.png",
      paste0("results/", paste(rep("unbroken_filename_", 24), collapse = ""), ".png"))),
      size_bytes = 1024, required_space_bytes = 4096, omissions = "Caches excluded"),
    warnings = character())
}

test_that("C05 review paths are escaped, complete and show relative destination guidance", {
  env <- new.env(parent = environment())
  sys.source(testthat::test_path("..", "..", "app", "server", "snapshot_server.R"), env)
  fixture <- c05_review_fixture()
  html <- as.character(env$snapshot_review_preview_ui(fixture))
  for (path in c(fixture$base_directory, fixture$destination, fixture$inventory$files$path)) {
    expect_match(html, path, fixed = TRUE)
  }
  expect_match(html, "Relative destination paths start from this directory", fixed = TRUE)
  expect_match(html, "Validated destination directory", fixed = TRUE)
  fixture$inventory$files$path <- "<script>unsafe&path</script>"
  escaped <- as.character(env$snapshot_review_preview_ui(fixture))
  expect_match(escaped, "&lt;script&gt;unsafe&amp;path&lt;/script&gt;", fixed = TRUE)
  expect_false(grepl("<script>unsafe", escaped, fixed = TRUE))
  initial <- as.character(env$snapshot_review_preview_ui(NULL, fixture$base_directory))
  expect_match(initial, fixture$base_directory, fixed = TRUE)
  expect_match(initial, "before copying", fixed = TRUE)
  expect_false(grepl("Validated destination", initial, fixed = TRUE))
})

test_that("C05 actual review modal contains selectable paths on desktop and narrow screens", {
  skip_if_not_installed("shinytest2")
  browser <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  skip_if(is.null(browser) || !nzchar(browser), "no Chromium browser is configured")
  withr::local_envvar(NOT_CRAN = "true")
  app_dir <- withr::local_tempdir(pattern = "c05-layout-")
  fixture <- c05_review_fixture()
  file.copy(testthat::test_path("..", "..", "app", "server", "snapshot_server.R"), app_dir)
  saveRDS(fixture, file.path(app_dir, "fixture.rds"))
  writeLines(c(
    "library(shiny)", "source('snapshot_server.R', local = TRUE)",
    "fixture <- readRDS('fixture.rds')",
    "format_storage_bytes <- function(bytes) paste(bytes, 'bytes')",
    "ui <- bslib::page_fluid(shinyjs::useShinyjs(), actionButton('show_review', 'Review snapshot'))",
    "server <- function(input, output, session) {",
    " output$review_snapshot_preview <- renderUI(snapshot_review_preview_ui(fixture))",
    " observeEvent(input$show_review, {",
    "  showModal(snapshot_review_dialog_ui())",
    " })", "}", "shinyApp(ui, server)"
  ), file.path(app_dir, "app.R"))
  app <- shinytest2::AppDriver$new(app_dir = app_dir, name = "c05-review-layout",
    width = 1280, height = 900, load_timeout = 60000, timeout = 60000)
  on.exit(app$stop(), add = TRUE)
  app$click("show_review")
  expected <- c(fixture$base_directory, fixture$destination, fixture$inventory$files$path)
  for (width in c(1280, 375)) {
    app$set_window_size(width = width, height = 900)
    app$wait_for_idle()
    app$get_js("document.querySelector('.modal-body details').open = true")
    measured <- app$get_js("(() => {
      const body = document.querySelector('.modal-body');
      const modal = document.querySelector('.modal-content');
      return {detailsOpen: body.querySelector('details').open,
        bodyWidth: body.clientWidth, bodyScrollWidth: body.scrollWidth,
        viewport: document.documentElement.clientWidth, documentWidth: document.documentElement.scrollWidth,
        modalLeft: modal.getBoundingClientRect().left, modalRight: modal.getBoundingClientRect().right,
        paths: Array.from(body.querySelectorAll('code')).map(node => {
          const rect = node.getBoundingClientRect();
          const range = document.createRange(); range.selectNodeContents(node);
          const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
          const selected = selection.toString(); selection.removeAllRanges();
          return {text: node.textContent, selected: selected, width: node.clientWidth, scrollWidth: node.scrollWidth,
            left: rect.left, right: rect.right, height: rect.height,
            lineHeight: parseFloat(getComputedStyle(node).lineHeight),
            bodyLeft: body.getBoundingClientRect().left, bodyRight: body.getBoundingClientRect().right};
        })};
    })()")
    expect_length(measured$paths, length(expected))
    expect_true(measured$detailsOpen)
    expect_lte(measured$bodyScrollWidth, measured$bodyWidth + 1)
    expect_lte(measured$documentWidth, measured$viewport + 1)
    expect_gte(measured$modalLeft, 0)
    expect_lte(measured$modalRight, measured$viewport + 1)
    for (i in seq_along(expected)) {
      path <- measured$paths[[i]]
      expect_identical(path$text, expected[[i]])
      expect_identical(path$selected, expected[[i]])
      expect_lte(path$scrollWidth, path$width + 1)
      expect_gte(path$left, path$bodyLeft)
      expect_lte(path$right, path$bodyRight + 1)
      if (i %in% c(2L, 4L) || (width == 375 && i == 3L)) expect_gt(path$height, path$lineHeight)
    }
  }
})
