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

  app_dir <- testthat::test_path("..", "..")
  app <- shiny::as.shiny.appobj(app_dir)

  expect_s3_class(app, "shiny.appobj")
  expect_type(app$serverFuncSource, "closure")
})
