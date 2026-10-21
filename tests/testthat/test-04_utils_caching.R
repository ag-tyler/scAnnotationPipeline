test_that("setup_cache_dir creates the cache/ subfolder and is idempotent", {
  dataset_dir <- withr::local_tempdir()

  cache_dir <- setup_cache_dir(dataset_dir)
  expect_true(dir.exists(cache_dir))
  expect_equal(normalizePath(cache_dir), normalizePath(file.path(dataset_dir, "cache")))
  expect_no_error(setup_cache_dir(dataset_dir))
})

test_that("cache_save_data registers an artifact and round-trips it", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  obj <- list(a = 1:5, b = "hello", df = data.frame(x = 1:3))

  cache_save_data(
    obj,
    "my_object.qs2",
    dataset_dir,
    dependencies = list(values = list(version = list(hash = cache_hash_value(1L)))),
    producer = "test"
  )

  expect_equal(cache_load_data("my_object.qs2", dataset_dir), obj)
  expect_true(cache_check_valid("my_object.qs2", dataset_dir))

  manifest <- load_cache_manifest(dataset_dir)
  record <- manifest$artifacts$my_object.qs2
  expect_equal(manifest$schema_version, CACHE_MANIFEST_SCHEMA_VERSION)
  expect_equal(manifest$revision, 1L)
  expect_equal(record$artifact_type, "generic")
  expect_equal(record$producer, "test")
  expect_match(record$checksum, "^[0-9a-f]{32}$")
  expect_gt(record$size_bytes, 0)
  expect_match(record$dependency_fingerprint, "^[0-9a-f]{32}$")
})

test_that("cache_load_data errors clearly for missing and untracked artifacts", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()

  expect_error(
    cache_load_data("nope.qs2", dataset_dir),
    "Expected cached file not found"
  )

  qs2::qs_save(42, file.path(setup_cache_dir(dataset_dir), "untracked.qs2"))
  expect_true(cache_check_exists("untracked.qs2", dataset_dir))
  expect_false(cache_check_valid("untracked.qs2", dataset_dir))
  expect_error(
    cache_load_data("untracked.qs2", dataset_dir),
    "untracked and cannot be safely reused"
  )
})


test_that("cache availability is a metadata-only screen", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  filename <- "screened.qs2"
  cache_save_data(list(value = 42L), filename, dataset_dir)
  manifest <- load_cache_manifest(dataset_dir)

  expect_true(cache_check_available(filename, dataset_dir, manifest))
  expect_false(cache_check_available("missing.qs2", dataset_dir, manifest))

  artifact_path <- file.path(dataset_dir, "cache", filename)
  bytes <- readBin(artifact_path, what = "raw", n = file.info(artifact_path)$size)
  bytes[[length(bytes)]] <- as.raw(bitwXor(as.integer(bytes[[length(bytes)]]), 1L))
  writeBin(bytes, artifact_path)
  expect_false(cache_check_available(filename, dataset_dir, manifest))

  legacy_manifest <- manifest
  legacy_manifest$artifacts[[filename]]$modified_at <- NULL

  # A legacy record has only its unchanged size as a fast screen, while
  # first-use deep validation still rejects the changed content.
  expect_true(cache_check_available(filename, dataset_dir, legacy_manifest))
  expect_false(cache_check_valid(filename, dataset_dir))
})


test_that("input fingerprints are reused only while file metadata is unchanged", {
  input_path <- withr::local_tempfile()
  writeLines("first", input_path)

  calls <- 0L
  test_env <- new.env(parent = environment(.cache_file_fingerprint))
  test_env$.cache_file_fingerprint_index <- new.env(parent = emptyenv())
  test_env$.cache_md5 <- function(path) {
    calls <<- calls + 1L
    paste0("checksum-", calls)
  }
  fingerprint <- .cache_file_fingerprint
  environment(fingerprint) <- test_env

  expect_identical(fingerprint(input_path), "checksum-1")
  expect_identical(fingerprint(input_path), "checksum-1")
  expect_identical(calls, 1L)

  Sys.setFileTime(input_path, Sys.time() + 2)
  expect_identical(fingerprint(input_path), "checksum-2")
  expect_identical(calls, 2L)
})


test_that("fast availability rejects conclusive source metadata changes", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  input_path <- file.path(dataset_dir, "expression.tsv")
  writeLines("original", input_path)
  dependencies <- cache_dependency_spec(files = c(expression = input_path))
  cache_save_data(42L, "dependent.qs2", dataset_dir, dependencies = dependencies)
  manifest <- load_cache_manifest(dataset_dir)

  expect_true(cache_check_available("dependent.qs2", dataset_dir, manifest))
  Sys.setFileTime(input_path, Sys.time() + 2)
  expect_true(cache_check_available("dependent.qs2", dataset_dir, manifest))
  writeLines(c("original", "larger"), input_path)
  expect_false(cache_check_available("dependent.qs2", dataset_dir, manifest))
})

test_that("dependency fingerprints prevent stale cache reuse", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  input_path <- file.path(dataset_dir, "input.txt")
  writeLines("first", input_path)

  dependencies <- cache_dependency_spec(
    files = c(input = input_path),
    values = list(parameter = 1L)
  )
  cache_save_data(42, "thing.qs2", dataset_dir, dependencies = dependencies)

  expect_true(cache_check_valid("thing.qs2", dataset_dir, dependencies))
  expect_equal(cache_load_data("thing.qs2", dataset_dir, dependencies = dependencies), 42)

  writeLines("changed", input_path)
  changed_dependencies <- cache_dependency_spec(
    files = c(input = input_path),
    values = list(parameter = 1L)
  )
  expect_false(cache_check_valid("thing.qs2", dataset_dir, changed_dependencies))
  expect_error(
    cache_load_data("thing.qs2", dataset_dir, dependencies = changed_dependencies),
    "failed checksum, size, or dependency validation"
  )
})

test_that("a failed replacement leaves the previous valid cache in place", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  filename <- "cells_filt_clust_res_0.5_sample1.qs2"
  valid_cells <- data.frame(
    cell_name = c("c1", "c2"),
    umap1 = c(0, 1),
    umap2 = c(1, 0),
    clust = c(1L, 2L)
  )

  cache_save_data(valid_cells, filename, dataset_dir)
  expect_error(
    cache_save_data(data.frame(cell_name = c("c1", "c1")), filename, dataset_dir),
    "duplicate cell identifiers"
  )

  expect_equal(cache_load_data(filename, dataset_dir), valid_cells)
  expect_true(cache_check_valid(filename, dataset_dir))
})

test_that("a corrupt current artifact recovers the previous valid version", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  filename <- "recoverable.qs2"
  cache_save_data(list(version = 1L), filename, dataset_dir)
  cache_save_data(list(version = 2L), filename, dataset_dir)

  artifact_path <- file.path(setup_cache_dir(dataset_dir), filename)
  writeBin(charToRaw("corrupt"), artifact_path)

  expect_warning(
    recovered <- cache_load_data(filename, dataset_dir),
    "Recovered previous valid cache artifact"
  )
  expect_equal(recovered, list(version = 1L))
  expect_equal(cache_load_data(filename, dataset_dir), list(version = 1L))
})

test_that("a corrupt manifest is restored from its valid backup", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  cache_save_data(1L, "a.qs2", dataset_dir)
  cache_save_data(2L, "b.qs2", dataset_dir)
  paths <- cache_manifest_paths(dataset_dir)

  writeLines("not: [valid", paths$primary)
  expect_warning(manifest <- load_cache_manifest(dataset_dir), "Recovered cache manifest")
  expect_true("a.qs2" %in% names(manifest$artifacts))
})

test_that("manifest recovery restores the artifact from the same checkpoint", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  cache_save_data(list(version = 1L), "versioned.qs2", dataset_dir)
  cache_save_data(list(version = 2L), "versioned.qs2", dataset_dir)
  paths <- cache_manifest_paths(dataset_dir)

  writeLines("not: [valid", paths$primary)
  expect_warning(
    expect_warning(
      restored <- cache_load_data("versioned.qs2", dataset_dir),
      "Recovered cache manifest"
    ),
    "Recovered previous valid cache artifact"
  )
  expect_equal(restored, list(version = 1L))
  expect_true(cache_check_valid("versioned.qs2", dataset_dir))
})

test_that("cache_invalidate_artifacts removes only requested artifacts and metadata", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  cache_save_data(1L, "a.qs2", dataset_dir)
  cache_save_data(2L, "b.qs2", dataset_dir)

  expect_equal(cache_invalidate_artifacts("a.qs2", dataset_dir), "a.qs2")
  expect_false(cache_check_exists("a.qs2", dataset_dir))
  expect_true(cache_check_valid("b.qs2", dataset_dir))
  expect_false("a.qs2" %in% names(load_cache_manifest(dataset_dir)$artifacts))
})

test_that("sample invalidation follows cache artifact families", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  cna_matrix <- data.frame(
    gene = c("g1", "g2"),
    chr = c("1", "1"),
    start_pos = c(1, 2),
    c1 = c(0.1, 0.2)
  )
  values <- matrix(
    c(0, 1, 1, 0),
    nrow = 2,
    dimnames = list(c("c1", "c2"), c("x", "y"))
  )
  hc <- stats::hclust(stats::dist(values))
  signal <- data.frame(
    cell_name = c("c1", "c2"),
    cna_signal = c(0.1, 0.2),
    cna_cor = c(0.2, 0.3)
  )
  cache_save_data(cna_matrix, "cna_matrix_sample1.qs2", dataset_dir)
  cache_save_data(hc, "hclust_sample1.qs2", dataset_dir)
  cache_save_data(signal, "cna_sig_cor_sample1_subclone_1.qs2", dataset_dir)
  cache_save_data(cna_matrix, "cna_matrix_sample2.qs2", dataset_dir)

  removed <- cache_invalidate_sample(
    "sample1",
    dataset_dir,
    artifact_types = "cna_signal_correlation"
  )
  expect_identical(removed, "cna_sig_cor_sample1_subclone_1.qs2")
  expect_true(cache_check_valid("cna_matrix_sample1.qs2", dataset_dir))
  expect_true(cache_check_valid("hclust_sample1.qs2", dataset_dir))

  removed <- cache_invalidate_sample("sample1", dataset_dir)
  expect_setequal(removed, c("cna_matrix_sample1.qs2", "hclust_sample1.qs2"))
  expect_true(cache_check_valid("cna_matrix_sample2.qs2", dataset_dir))
})

test_that("clear_cache_dir removes cache contents but keeps the directory", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  cache_save_data(1, "a.qs2", dataset_dir)
  cache_save_data(2, "b.qs2", dataset_dir)
  cache_dir <- setup_cache_dir(dataset_dir)

  expect_setequal(
    list.files(cache_dir, pattern = "[.]qs2$"),
    c("a.qs2", "b.qs2")
  )
  expect_true(file.exists(cache_manifest_paths(dataset_dir)$primary))

  clear_cache_dir(dataset_dir)

  expect_true(dir.exists(cache_dir))
  expect_length(list.files(cache_dir, all.files = TRUE, no.. = TRUE), 0)
})
