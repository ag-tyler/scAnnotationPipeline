setup_source <- normalizePath(testthat::test_path("..", "..", "scripts", "check_test_setup.R"), winslash = "/")
setup_env <- new.env(parent = globalenv())
eval(parse(setup_source, encoding = "UTF-8"), setup_env)

make_setup_zip_root <- function() {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(root, "tests"))
  file.create(file.path(root, "app.R"), file.path(root, "tests", "testthat.R"))
  for (path in c("DESCRIPTION", "general_config.yaml")) {
    file.copy(testthat::test_path("..", "..", path), root)
  }
  root
}

test_that("test setup identifies ZIP roots and does not require private resources", {
  expect_error(setup_env$check_test_setup(tempdir(), browser = FALSE, worker = FALSE, quiet = TRUE),
    "application root", fixed = TRUE)
  root <- make_setup_zip_root()
  before <- tools::md5sum(list.files(root, recursive = TRUE, full.names = TRUE))
  result <- setup_env$check_test_setup(root, browser = FALSE, worker = FALSE, quiet = TRUE)
  expect_equal(sum(result$resources), 0)
  expect_false(dir.exists(file.path(root, ".git")))
  expect_false(dir.exists(file.path(root, "resources")))
  expect_identical(tools::md5sum(names(before)), before)
})

test_that("test setup gives actionable missing-package and browser diagnostics", {
  root <- make_setup_zip_root()
  description <- read.dcf(file.path(root, "DESCRIPTION"))
  description[1, "Imports"] <- paste(description[1, "Imports"], "NoSuchScAnnotationSetupPackage", sep = ", ")
  write.dcf(description, file.path(root, "DESCRIPTION"))
  expect_error(setup_env$check_test_setup(root, browser = FALSE, worker = FALSE, quiet = TRUE),
    "Missing or unloadable package: NoSuchScAnnotationSetupPackage", fixed = TRUE)
  root <- make_setup_zip_root()
  withr::local_envvar(CHROMOTE_CHROME = file.path(root, "missing-browser"))
  expect_error(setup_env$check_test_setup(root, worker = FALSE, quiet = TRUE), "CHROMOTE_CHROME", fixed = TRUE)
  expect_identical(Sys.getenv("CHROMOTE_CHROME"), file.path(root, "missing-browser"))
})

test_that("test setup rejects a non-UTF-8 host with platform-specific advice", {
  root <- make_setup_zip_root()
  withr::with_locale(c(LC_CTYPE = "C"), {
    expect_error(setup_env$check_test_setup(root, browser = FALSE, worker = FALSE, quiet = TRUE),
      "host R process is not using UTF-8", fixed = TRUE)
  })
})

test_that("test setup detects locale overrides that break child R despite a UTF-8 host", {
  root <- make_setup_zip_root()
  expect_true(isTRUE(l10n_info()[["UTF-8"]]))
  withr::local_envvar(c(LC_ALL = "C", LC_CTYPE = "C", LANG = "C"))
  expect_error(setup_env$check_test_setup(root, browser = FALSE, quiet = TRUE),
    "Independent R worker failed its UTF-8/startup check", fixed = TRUE)
  expect_identical(Sys.getenv("LC_ALL"), "C")
})
