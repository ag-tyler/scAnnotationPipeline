f17_completion_environment <- function() {
  env <- new.env(parent = environment())
  sys.source(testthat::test_path("..", "..", "app", "server", "snapshot_server.R"), env)
  env
}

f17_long_display_paths <- function() {
  # Deliberately exceed filesystem limits: these are display strings only.
  folder <- paste0("C:\\review output\\", paste(rep("very_long_dataset_name_", 20), collapse = ""),
    "Liu2022_Liver_review_20261030T153000_unique")
  c(folder, paste0(folder, ".zip"))
}

test_that("F17 completion paths remain full selectable text with explicit wrapping", {
  env <- f17_completion_environment()
  paths <- f17_long_display_paths()
  html <- as.character(env$snapshot_completion_dialog_ui(list(outputs = paths, warnings = character())))
  expect_match(html, "Review snapshot verified", fixed = TRUE)
  for (path in paths) expect_true(grepl(path, html, fixed = TRUE))
  expect_match(html, "overflow-wrap: anywhere", fixed = TRUE)
  expect_match(html, "word-break: break-word", fixed = TRUE)
  expect_match(html, "white-space: normal", fixed = TRUE)
  expect_match(html, "max-width: 100%", fixed = TRUE)
  expect_false(grepl("text-overflow|overflow: hidden|white-space: nowrap", html))
  expect_equal(lengths(regmatches(html, gregexpr('class="review-snapshot-output-path"', html, fixed = TRUE))), 2L)
  # Paths are escaped as text, never treated as HTML or converted to file URLs.
  escaped <- as.character(env$snapshot_completion_dialog_ui(list(outputs = "<script>unsafe</script>", warnings = "notice")))
  expect_match(escaped, "&lt;script&gt;unsafe&lt;/script&gt;", fixed = TRUE)
  expect_false(grepl("<script>unsafe</script>", escaped, fixed = TRUE))
  expect_match(escaped, "notice", fixed = TRUE)
})

test_that("F17 completion paths fit the actual modal on desktop and narrow screens", {
  skip_if_not_installed("shinytest2")
  browser <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  skip_if(is.null(browser) || !nzchar(browser), "no Chromium browser is configured")
  withr::local_envvar(NOT_CRAN = "true")
  app_dir <- withr::local_tempdir(pattern = "f17-layout-")
  paths <- f17_long_display_paths()
  # The fixture only displays the production modal. It performs no export or I/O
  # against any displayed destination, so paths beyond MAX_PATH are safe here.
  file.copy(testthat::test_path("..", "..", "app", "server", "snapshot_server.R"), app_dir)
  saveRDS(paths, file.path(app_dir, "paths.rds"))
  writeLines(c(
    "library(shiny)", "source('snapshot_server.R')",
    "paths <- readRDS('paths.rds')",
    "ui <- bslib::page_fluid(actionButton('show_completion', 'Show completion'))",
    "server <- function(input, output, session) {",
    "  observeEvent(input$show_completion, {",
    "    showModal(snapshot_completion_dialog_ui(list(outputs = paths, warnings = character())))",
    "  })",
    "}", "shinyApp(ui, server)"
  ), file.path(app_dir, "app.R"))
  app <- shinytest2::AppDriver$new(app_dir = app_dir, name = "f17-completion-layout",
    width = 1280, height = 900, load_timeout = 60000, timeout = 60000)
  on.exit(app$stop(), add = TRUE)
  app$click("show_completion")
  app$wait_for_idle()
  measure <- function() app$get_js("(() => {
    const body = document.querySelector('.modal-body');
    const modal = document.querySelector('.modal-content');
    const bounds = body.getBoundingClientRect();
    const viewport = document.documentElement.clientWidth;
    return {
      bodyWidth: body.clientWidth, bodyScrollWidth: body.scrollWidth,
      viewportWidth: viewport, documentScrollWidth: document.documentElement.scrollWidth,
      modalRight: modal.getBoundingClientRect().right,
      paths: Array.from(document.querySelectorAll('.review-snapshot-output-path')).map(node => {
        const rect = node.getBoundingClientRect();
        return {text: node.textContent, clientWidth: node.clientWidth, scrollWidth: node.scrollWidth,
          left: rect.left, right: rect.right, height: rect.height,
          lineHeight: parseFloat(getComputedStyle(node).lineHeight), bodyRight: bounds.right};
      })
    };
  })()")
  for (width in c(1280, 375)) {
    app$set_window_size(width = width, height = 900)
    app$wait_for_idle()
    measured <- measure()
    expect_equal(length(measured$paths), 2L)
    expect_lte(measured$bodyScrollWidth, measured$bodyWidth + 1)
    expect_lte(measured$documentScrollWidth, measured$viewportWidth + 1)
    expect_lte(measured$modalRight, measured$viewportWidth + 1)
    for (i in seq_along(paths)) {
      path <- measured$paths[[i]]
      expect_identical(path$text, paths[[i]])
      expect_lte(path$scrollWidth, path$clientWidth + 1)
      expect_lte(path$right, path$bodyRight + 1)
      expect_gt(path$height, path$lineHeight)
    }
  }
})
