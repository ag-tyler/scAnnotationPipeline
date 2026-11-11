perf_root <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
perf_test_env <- new.env(parent = environment())
for (file in c("equivalence.R", "workload.R", "harness.R")) {
  sys.source(file.path(perf_root, "scripts", "performance", file), perf_test_env)
}
perf_contract <- yaml::read_yaml(file.path(perf_root, "scripts", "performance", "contract.yaml"))

test_that("E00 checks every numeric entry, identity, sparse topology and special values", {
  compare <- perf_test_env$perf_numeric_metrics
  values <- setNames(c(1, 2, NA_real_, NaN, Inf, -Inf), letters[1:6])
  expect_true(compare(values, values)$pass)
  changed <- values; changed[[2]] <- changed[[2]] + 1e-9
  expect_false(compare(values, changed)$pass)
  expect_true(compare(values, changed, 1e-8)$pass)
  expect_false(compare(values, rev(values), 1e-8)$pass)
  expect_false(compare(1:3, as.numeric(1:3))$pass)
  changed <- values; changed[[4]] <- NA_real_
  expect_false(compare(values, changed, 1e-8)$pass)
  changed <- values; changed[[5]] <- -Inf
  expect_false(compare(values, changed, 1e-8)$pass)
  long <- numeric(1000001); changed <- long; changed[[1000001]] <- 0.1
  expect_equal(compare(long, changed)$max_absolute_error, 0.1)
  matrix <- Matrix::sparseMatrix(i = 1:3, j = 1:3, x = 1:3)
  expect_true(compare(matrix, matrix)$pass)
  changed <- matrix; changed[1, 2] <- 1
  expect_false(compare(matrix, changed)$pass)
})

test_that("E00 distinguishes changed partitions, label permutations and reordered cells", {
  compare <- perf_test_env$perf_partition_metrics
  a <- setNames(c("0", "0", "1", "1"), letters[1:4])
  expect_true(compare(a, a)$pass)
  b <- setNames(c("B", "B", "A", "A"), names(a))
  result <- compare(a, b)
  expect_true(result$same_membership)
  expect_equal(result$adjusted_rand_index, 1)
  expect_false(result$saved_ids_compatible)
  expect_false(result$pass)
  b <- a; b[[2]] <- "1"
  expect_false(compare(a, b)$same_membership)
  expect_lt(compare(a, b)$adjusted_rand_index, 1)
  expect_false(compare(a, a[4:1])$pass)
})

test_that("E00 PCA diagnostics allow basis ambiguity but reject scaling and subspace drift", {
  set.seed(54)
  v <- qr.Q(qr(matrix(rnorm(80), nrow = 20)))[, 1:3]
  u <- qr.Q(qr(matrix(rnorm(32), nrow = 8)))[, 1:3]
  a <- list(d = c(3, 3, 1), v = v, u = u)
  compare <- function(b, exact = FALSE) perf_test_env$perf_pca_metrics(a, b, perf_contract, exact)
  expect_true(compare(a, TRUE)$pass)
  rotation <- matrix(c(0, 1, -1, 0), 2)
  b <- a; b$v[, 1:2] <- v[, 1:2] %*% rotation; b$u[, 1:2] <- u[, 1:2] %*% rotation
  expect_true(compare(b)$pass)
  expect_false(compare(b, TRUE)$pass)
  b <- a; b$v <- v * 2
  expect_false(compare(b)$pass)
  b <- a; b$d[[1]] <- 3.1
  expect_false(compare(b)$pass)
  b <- a; b$v <- qr.Q(qr(matrix(rnorm(60), nrow = 20)))
  expect_false(compare(b)$pass)
})

test_that("E00 UMAP comparison permits rigid transforms but detects scale, outliers and reordered identities", {
  set.seed(15)
  a <- matrix(rnorm(160), ncol = 2, dimnames = list(paste0("c", 1:80), c("x", "y")))
  compare <- function(b, exact = FALSE) perf_test_env$perf_embedding_metrics(a, b, perf_contract, exact)
  expect_true(compare(a, TRUE)$pass)
  b <- a %*% matrix(c(0, 1, -1, 0), 2)
  dimnames(b) <- dimnames(a)
  b <- sweep(b, 2, c(5, -3), "+")
  expect_true(compare(b)$pass)
  expect_false(compare(b, TRUE)$pass)
  expect_equal(compare(b)$neighborhood_mean_overlap, 1)
  expect_false(compare(a * 1.2)$pass)
  b <- a; b[1, ] <- 1e4
  expect_false(compare(b)$pass)
  expect_false(compare(a[80:1, ])$pass)
  expect_lte(compare(a)$neighborhood_anchors, perf_contract$embedding_max_anchors)
})

test_that("E00 rejects changed rankings, rounded CNA and threshold-side assignments", {
  compare <- perf_test_env$perf_compare_object
  a <- data.frame(gene = c("g1", "g2"), m = c(0.3, 0.2), clust = "0")
  b <- a; b$m[[1]] <- b$m[[1]] + 1e-9
  expect_true(compare(a, b, "table", perf_contract, "numerical")$pass)
  expect_false(compare(a, b, "table", perf_contract, "exact")$pass)
  expect_false(compare(a, a[2:1, ], "table", perf_contract, "numerical")$pass)
  a <- data.frame(gene = "g1", cell = 0.1234)
  b <- a; b$cell <- 0.1235
  expect_false(compare(a, b, "rounded_cna", perf_contract, "numerical")$pass)
  a <- data.frame(cell_name = c("a", "b"), cell_type = c("Malignant", "Unassigned"), subclone = c(1L, NA_integer_))
  b <- a; b$cell_type[[2]] <- "Malignant"; b$subclone[[2]] <- 1L
  expect_false(compare(a, b, "cells", perf_contract, "numerical")$pass)
  bad <- list(outcome = "error", reason = "Cache artifact failed checksum")
  unsafe <- list(outcome = "returned", value = 1)
  expect_false(compare(bad, unsafe, "exact", perf_contract)$pass)
})

test_that("E00 refuses overwrite and output inside protected source/data directories", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "artifacts", "local-checks"), recursive = TRUE)
  protected <- file.path(root, "data"); dir.create(protected)
  expect_error(perf_test_env$perf_new_output(protected, root), "new directory")
  expect_error(perf_test_env$perf_new_output(file.path(root, "scripts", "bad"), root), "restricted")
  external <- withr::local_tempdir()
  expect_error(perf_test_env$perf_new_output(file.path(external, "bad"), root, external), "original data")
  expect_false(dir.exists(file.path(external, "bad")))
})

test_that("E00 snapshots the pinned baseline and compares independent Windows-capable cache workers", {
  root <- withr::local_tempdir()
  fixture <- perf_test_env$perf_fixture(perf_test_env$perf_source_utilities(perf_root))
  result <- perf_test_env$perf_run_experiment(perf_root, file.path(root, "experiment"),
    fixture = fixture, repeats = 1L, profile = "cache", timeout_seconds = 180)
  expect_true(result$pass)
  expect_true(result$input_unchanged)
  comparisons <- readRDS(file.path(root, "experiment", "comparisons.rds"))
  expect_true(all(vapply(comparisons, function(x) x$pass, logical(1))))
  metadata <- readRDS(file.path(root, "experiment", "experiment.rds"))
  expect_identical(metadata$baseline$baseline_commit, perf_contract$baseline_commit)
  a <- readRDS(file.path(root, "experiment", "capture_baseline_1", "result.rds"))
  expect_true(a$coverage$cache_controls)
  expect_gt(a$counts[["cache_deserializations"]], 0)
  expect_gt(a$sampled_peak_rss_bytes, 0)
  expect_setequal(names(a$cache_control_load_seconds), c("valid", "missing", "corrupt", "stale", "recovery"))
  expect_true(all(unlist(a$cache_control_load_seconds) >= 0))
  measurement <- readRDS(file.path(root, "experiment", "measure_baseline_1", "result.rds"))
  expect_true(all(measurement$counts == 0))
  expect_gte(measurement$setup_seconds, 0)
  report <- jsonlite::read_json(file.path(root, "experiment", "comparisons.json"))
  expect_true(report$paired_1$pass)
  medians <- read.csv(file.path(root, "experiment", "measurement_medians.csv"))
  expect_setequal(medians$role, c("baseline", "candidate"))
  # A deliberately unsafe candidate report must be caught by the saved-run comparator.
  target <- file.path(root, "experiment", "capture_candidate_1")
  b <- readRDS(file.path(target, "result.rds"))
  record <- b$artifacts$cache_controls
  changed <- readRDS(file.path(target, record$file))
  changed$corrupt <- list(outcome = "returned", value = "unsafe reuse")
  saveRDS(changed, file.path(target, record$file))
  expect_false(perf_test_env$perf_compare_runs(file.path(root, "experiment", "capture_baseline_1"),
    target, perf_contract)$pass)
})
