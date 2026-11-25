cache_reader_script <- normalizePath(
  testthat::test_path("..", "..", "scripts", "load_dataset_cache.R"), winslash = "/")

test_that("DC08 sourcing defines the path-only reader without loading or creating files", {
  root <- withr::local_tempdir()
  withr::local_dir(root)
  env <- new.env(parent = baseenv())
  sys.source(cache_reader_script, envir = env)
  expect_identical(ls(env, all.names = TRUE), "load_cache_file")
  expect_identical(names(formals(env$load_cache_file)), "path")
  expect_length(list.files(root, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("DC08 relative and absolute paths preserve cache object classes and values", {
  root <- withr::local_tempdir()
  directory <- file.path(root, "cache files")
  dir.create(directory)
  env <- new.env(parent = baseenv())
  sys.source(cache_reader_script, envir = env)
  objects <- list(
    Matrix::Matrix(matrix(c(0, 1, 2, 0, 0, 3), nrow = 3,
      dimnames = list(c("G1", "G2", "G3"), c("cell_001", "cell_002"))), sparse = TRUE),
    data.table::data.table(cell = c("001", "M\u00fcller"), score = c(1.23456789012345, NA_real_),
      label = factor(c("B", "A"), levels = c("A", "B"))),
    stats::hclust(stats::dist(matrix(seq_len(12), nrow = 4)))
  )
  # The format and object type must not depend on a conventional filename.
  paths <- file.path(directory, paste0("object ", seq_along(objects), ".bin"))
  for (i in seq_along(objects)) qs2::qs_save(objects[[i]], paths[[i]])
  hashes <- tools::md5sum(paths)
  membership <- list.files(root, recursive = TRUE, all.files = TRUE, include.dirs = TRUE)
  withr::local_dir(root)
  for (i in seq_along(objects)) {
    absolute <- env$load_cache_file(paths[[i]])
    relative <- env$load_cache_file(file.path("cache files", basename(paths[[i]])))
    expect_identical(class(absolute), class(objects[[i]]))
    expect_equal(absolute, objects[[i]], tolerance = 0)
    expect_equal(relative, absolute, tolerance = 0)
  }
  expect_identical(env$load_cache_file(paths[[2]])$score, objects[[2]]$score)
  expect_identical(tools::md5sum(paths), hashes)
  expect_identical(list.files(root, recursive = TRUE, all.files = TRUE, include.dirs = TRUE), membership)
})

test_that("DC08 invalid, missing, unreadable and corrupt files produce clear errors", {
  root <- withr::local_tempdir()
  env <- new.env(parent = baseenv())
  sys.source(cache_reader_script, envir = env)
  for (path in list(NULL, character(), NA_character_, " ", c("a", "b"), 1)) {
    expect_error(env$load_cache_file(path), "one non-empty relative or absolute file path")
  }
  expect_error(env$load_cache_file(file.path(root, "missing", "cache.qs2")), "does not exist")
  expect_error(env$load_cache_file(root), "directory, not a file")
  corrupt <- file.path(root, "corrupt.qs2")
  writeBin(charToRaw("not a qs2 cache file"), corrupt)
  before <- tools::md5sum(corrupt)
  expect_error(env$load_cache_file(corrupt), "Could not read qs2 cache file.*corrupt.qs2")

  # Simulate permissions and an absent package without changing the host setup.
  denied <- env$load_cache_file
  denied_env <- new.env(parent = environment(denied))
  denied_env$file.access <- function(names, mode) -1L
  environment(denied) <- denied_env
  expect_error(denied(corrupt), "not readable")
  no_package <- env$load_cache_file
  package_env <- new.env(parent = environment(no_package))
  package_env$requireNamespace <- function(package, quietly) FALSE
  environment(no_package) <- package_env
  expect_error(no_package(corrupt), "Install 'qs2'", fixed = TRUE)
  expect_identical(tools::md5sum(corrupt), before)
  expect_identical(list.files(root, all.files = TRUE, no.. = TRUE), "corrupt.qs2")
})
