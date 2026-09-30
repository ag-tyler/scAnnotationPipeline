# tests/testthat/helper-source.R
#
# testthat automatically sources every file matching "helper-*.R" in this
# directory before running the test suite (both for testthat::test_dir()
# and devtools::test()). We use that hook to source the actual pipeline
# code under test.
#
# util_scripts/ is intentionally NOT an R/ package directory: app.R sources
# every *.R file in it at startup (see app.R, "2. Source utility scripts"),
# so new utility scripts can be dropped in with no manual source() calls.
# We replicate exactly that logic here so the functions under test are
# always the same functions the running app actually uses -- not a copy.

# testthat automatically sources every file matching "helper-*.R" in this
# directory before running the test suite (both for testthat::test_dir()
# and devtools::test()). We use that hook to source the actual pipeline
# code under test.
#
# util_scripts/ is intentionally NOT an R/ package directory: app.R sources
# every *.R file in it at startup (see app.R, "2. Source utility scripts"),
# so new utility scripts can be dropped in with no manual source() calls.
# We replicate exactly that logic here so the functions under test are
# always the same functions the running app actually uses -- not a copy.
#
# app.R also attaches a handful of packages via library() BEFORE sourcing
# util_scripts/ (see app.R, top of file). util_scripts/ code relies on that:
# e.g. build_samples()/build_cells() in 03_utils_misc.R call setnames() and
# as.data.table() unqualified, which only resolve once data.table is
# attached to the search path -- they are not namespaced as
# data.table::setnames(). That's true of the running app too, it just never
# surfaces there because app.R happens to attach data.table first. We
# reproduce the same attach here so tests see the same environment app.R
# provides. (Longer term this is worth fixing at the source -- see the
# note in the project chat -- but attaching it here keeps tests green
# without touching pipeline code.)
suppressPackageStartupMessages(library(data.table))

util_scripts_dir <- testthat::test_path("..", "..", "util_scripts")

if (!dir.exists(util_scripts_dir)) {
  stop(
    "Could not find util_scripts/ at '", util_scripts_dir, "'. ",
    "Tests must be run from the package/repo root (e.g. via devtools::test() ",
    "or Rscript tests/testthat.R from the repo root).",
    call. = FALSE
  )
}

r_files <- sort(list.files(util_scripts_dir, pattern = "\\.R$", full.names = TRUE))

if (length(r_files) == 0) {
  stop("No .R files found in '", util_scripts_dir, "'.", call. = FALSE)
}

# data.table uses calling-environment awareness for its NSE semantics.
.datatable.aware <- TRUE

for (f in r_files) {
  source(f, local = TRUE)
}

rm(f, r_files, util_scripts_dir)