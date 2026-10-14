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
