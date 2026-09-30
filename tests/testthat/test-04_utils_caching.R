test_that("setup_cache_dir creates the cache/ subfolder and is idempotent", {
  dataset_dir <- withr::local_tempdir()

  cache_dir <- setup_cache_dir(dataset_dir)
  expect_true(dir.exists(cache_dir))
  expect_equal(normalizePath(cache_dir), normalizePath(file.path(dataset_dir, "cache")))

  # Calling it again on an already-existing dir must not error.
  expect_no_error(setup_cache_dir(dataset_dir))
})

test_that("cache_save_data / cache_load_data round-trip an R object", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()

  obj <- list(a = 1:5, b = "hello", df = data.frame(x = 1:3))
  cache_save_data(obj, "my_object.qs2", dataset_dir)

  loaded <- cache_load_data("my_object.qs2", dataset_dir)
  expect_equal(loaded, obj)
})

test_that("cache_load_data errors with a helpful message if the file is missing", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()

  expect_error(
    cache_load_data("nope.qs2", dataset_dir),
    "Expected cached file not found"
  )
})

test_that("cache_check_exists reflects presence/absence correctly", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()

  expect_false(cache_check_exists("thing.qs2", dataset_dir))
  cache_save_data(42, "thing.qs2", dataset_dir)
  expect_true(cache_check_exists("thing.qs2", dataset_dir))
})

test_that("clear_cache_dir removes cached files but keeps the cache dir itself", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()

  cache_save_data(1, "a.qs2", dataset_dir)
  cache_save_data(2, "b.qs2", dataset_dir)
  expect_length(list.files(setup_cache_dir(dataset_dir)), 2)

  clear_cache_dir(dataset_dir)

  expect_true(dir.exists(setup_cache_dir(dataset_dir)))
  expect_length(list.files(setup_cache_dir(dataset_dir)), 0)
})
