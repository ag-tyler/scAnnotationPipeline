# This project is not built/installed as a normal R package -- its functions
# live in util_scripts/ (sourced at runtime by app.R AND by
# tests/testthat/helper-source.R), not in R/. Because of that we deliberately
# don't use testthat::test_check(), which expects an installed package
# namespace. Plain test_dir() + the helper file gives the same
# devtools::test() / CI integration without moving util_scripts/ into R/.

if (!file.exists("scripts/check_test_setup.R")) {
  stop("Run the tests from the application root containing app.R, DESCRIPTION, ",
    "and tests/testthat.R. Current directory: ", getwd(), call. = FALSE)
}
eval(parse("scripts/check_test_setup.R", encoding = "UTF-8"), envir = environment())
check_test_setup()

library(testthat)

testthat::test_dir(file.path("tests", "testthat"))
