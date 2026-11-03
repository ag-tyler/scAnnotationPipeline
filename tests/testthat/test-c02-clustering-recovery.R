suppressPackageStartupMessages(library(shiny))
suppressPackageStartupMessages(library(bslib))

make_c02_state <- function(root, samples = c("sample1", "control")) {
  state <- new_pipeline_state(basename(root), samples)
  state <- transition_pipeline_step(state, "standardization", "completed")
  for (sample in samples) for (step in PIPELINE_SAMPLE_STEPS) {
    state <- transition_pipeline_step(state, step, "completed", sample, force = TRUE)
  }
  save_pipeline_state_atomic(state, root)
}

test_that("C02 distinguishes live, ended, PID-reused and unknown clustering ownership", {
  owner <- begin_clustering_execution("session-A")
  on.exit(end_clustering_execution(owner), add = TRUE)
  expect_identical(clustering_execution_status(owner), "live")
  # A second viewer/session must not declare the same process's token abandoned.
  root <- withr::local_tempdir()
  state <- make_c02_state(root)
  path <- file.path(root, "pipeline_state.yaml")
  state <- persist_pipeline_step_update(state, path, "clustering", "in_progress", "sample1",
    details = list(execution_owner = owner), invalidate_downstream = TRUE, invalidation_reason = "Clustering is running.")
  before <- tools::md5sum(path)
  expect_length(interrupted_clustering_candidates(state), 0)
  expect_identical(reconcile_interrupted_clustering(state, path)$samples, state$samples)
  expect_identical(tools::md5sum(path), before)
  expect_error(reconcile_interrupted_clustering(state, path, "sample1"), "still active")
  reused <- owner; reused$process_started_at <- as.character(as.numeric(owner$process_started_at) - 100)
  expect_identical(clustering_execution_status(reused), "ended")
  remote <- owner; remote$host <- "different-host"
  expect_identical(clustering_execution_status(remote), "unknown")
  for (invalid in list(NULL, list(), list(pid = NA), modifyList(owner, list(pid = "bad")),
      modifyList(owner, list(pid = list(list("bad")))))) {
    expect_identical(clustering_execution_status(invalid), "unknown")
  }
  end_clustering_execution(owner)
  expect_identical(clustering_execution_status(owner), "ended")
  recovered <- reconcile_interrupted_clustering(state, path)
  record <- get_pipeline_step(recovered, "clustering", "sample1")
  expect_identical(record$status, "failed")
  expect_identical(record$attempt, get_pipeline_step(state, "clustering", "sample1")$attempt)
  expect_identical(record$started_at, get_pipeline_step(state, "clustering", "sample1")$started_at)
  expect_identical(record$details$interruption_recovery$mode, "owner_ended")
  expect_identical(recovered$samples$control, state$samples$control)
  expect_identical(get_pipeline_step(recovered, "resolution", "sample1")$status, "stale")
  expect_match(get_pipeline_step(recovered, "resolution", "sample1")$reason, "interrupted")
  again <- reconcile_interrupted_clustering(recovered, path)
  expect_identical(again$revision, recovered$revision)
  second_owner <- begin_clustering_execution("session-B")
  recovered <- persist_pipeline_step_update(recovered, path, "clustering", "in_progress", "sample1",
    details = list(execution_owner = second_owner))
  end_clustering_execution(second_owner)
  recovered <- reconcile_interrupted_clustering(recovered, path)
  history <- get_pipeline_step(recovered, "clustering", "sample1")$details$interruption_recoveries
  expect_length(history, 2)
  expect_identical(history$attempt_1$attempt, 1L)
  expect_identical(history$attempt_2$attempt, 2L)
})

test_that("C02 unknown legacy owners require explicit scoped recovery and respect revision conflicts", {
  root <- withr::local_tempdir()
  path <- file.path(root, "pipeline_state.yaml")
  state <- make_c02_state(root)
  for (sample in names(state$samples)) {
    state <- persist_pipeline_step_update(state, path, "clustering", "in_progress", sample)
  }
  before <- tools::md5sum(path)
  expect_setequal(interrupted_clustering_candidates(state), names(state$samples))
  unchanged <- reconcile_interrupted_clustering(state, path)
  expect_identical(unchanged$revision, state$revision)
  expect_identical(tools::md5sum(path), before)
  recovered <- reconcile_interrupted_clustering(state, path, "sample1")
  expect_identical(get_pipeline_step(recovered, "clustering", "sample1")$status, "failed")
  expect_identical(recovered$samples$control, state$samples$control)
  expect_identical(get_pipeline_step(recovered, "clustering", "sample1")$details$interruption_recovery$mode, "explicit_confirmation")
  expect_error(reconcile_interrupted_clustering(state, path, "sample1"), "revision conflict")
  expect_error(reconcile_interrupted_clustering(recovered, path, "sample1"), "status changed")
})

test_that("C02 process death before/after cache writes recovers without promoting partial work and retry completes", {
  skip_if_not_installed("processx")
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  for (pause_stage in c("pca_umap", "resolution_complete")) {
    root <- withr::local_tempdir()
    state <- make_c02_state(root)
    original_control <- state$samples$control
    paths <- lapply(c("sample1", "control"), function(sample) {
      write_mini_sample(file.path(root, "processed_data"), sample, n_genes = 60, n_cells = 40, seed = 51)
    })
    paths_list <- list(sample_dir_paths = vapply(paths, `[[`, "", "sample_dir"),
      cell_file_paths = vapply(paths, `[[`, "", "cells_path"),
      expmat_file_paths = vapply(paths, `[[`, "", "expmat_path"),
      genes_file_paths = vapply(paths, `[[`, "", "genes_path"))
    config <- list(params = list(min_genes = 3, target_sum = 1e5, log2_expr_threshold = 0.1,
      pca_nv = 5, resolutions = c(0.25, 0.5, 1), seed = 3988, umap = list(spread = 5, min_dist = 0.1)))
    dir.create(file.path(root, "results"))
    writeLines("prior control output", file.path(root, "results", "control.txt"))
    saveRDS(list(paths = paths_list, config = config, root = root, app = app_dir, stage = pause_stage), file.path(root, "args.rds"))
    child_script <- file.path(root, "child.R")
    writeLines(c(
      "args <- readRDS(commandArgs(TRUE)[[1]])",
      "suppressPackageStartupMessages(library(data.table))",
      "for (f in sort(list.files(file.path(args$app, 'util_scripts'), pattern = '[.]R$', full.names = TRUE))) source(f)",
      "run <- function() {",
      "  path <- file.path(args$root, 'pipeline_state.yaml')",
      "  state <- load_pipeline_state(args$root)",
      "  owner <- begin_clustering_execution('disposable-child')",
      "  on.exit(end_clustering_execution(owner))",
      "  cluster_all_samples(args$paths, args$config, file.path(args$root, 'results'), args$root, sample_indices = 1L,",
      "    state_callback = function(sample_name, status, reason = NULL, details = NULL) {",
      "      if (status == 'in_progress') details <- list(execution_owner = owner)",
      "      state <<- persist_pipeline_step_update(state, path, 'clustering', status, sample_name, reason, details,",
      "        invalidate_downstream = status == 'in_progress', invalidation_reason = 'Clustering is running.')",
      "    }, progress_callback = function(stage, ...) {",
      "      if (stage == args$stage) { writeLines('ready', file.path(args$root, 'ready')); repeat Sys.sleep(0.1) }",
      "    })",
      "}", "run()"), child_script)
    executable <- if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
    child <- processx::process$new(file.path(R.home("bin"), executable), c(child_script, file.path(root, "args.rds")),
      stdout = "|", stderr = "|", cleanup = TRUE)
    withr::defer(if (child$is_alive()) child$kill())
    deadline <- Sys.time() + 45
    while (!file.exists(file.path(root, "ready")) && child$is_alive() && Sys.time() < deadline) {
      child$poll_io(100); Sys.sleep(0.05)
    }
    expect_true(file.exists(file.path(root, "ready")), info = paste(child$read_error_lines(), collapse = "\n"))
    if (!file.exists(file.path(root, "ready"))) next
    running <- load_pipeline_state(root)
    expect_identical(clustering_execution_status(get_pipeline_step(running, "clustering", "sample1")$details$execution_owner), "live")
    expect_identical(reconcile_interrupted_clustering(running, file.path(root, "pipeline_state.yaml"))$revision, running$revision)
    child$kill(); child$wait(timeout = 5000)
    scientific <- c(paths_list$cell_file_paths, paths_list$expmat_file_paths, paths_list$genes_file_paths,
      list.files(file.path(root, "cache"), recursive = TRUE, full.names = TRUE))
    scientific <- c(scientific, list.files(file.path(root, "results"), recursive = TRUE, full.names = TRUE))
    hashes <- tools::md5sum(scientific)
    recovered <- reconcile_interrupted_clustering(load_pipeline_state(root), file.path(root, "pipeline_state.yaml"))
    expect_identical(get_pipeline_step(recovered, "clustering", "sample1")$status, "failed")
    expect_identical(recovered$samples$control, original_control)
    expect_identical(tools::md5sum(scientific), hashes)
    expect_identical(get_pipeline_step(recovered, "clustering", "sample1")$attempt, 1L)
    progress <- numeric()
    owner <- begin_clustering_execution("retry-session")
    tryCatch(cluster_all_samples(paths_list, config, file.path(root, "results"), root, sample_indices = 1L,
      state_callback = function(sample_name, status, reason = NULL, details = NULL) {
        if (status == "in_progress") details <- list(execution_owner = owner)
        recovered <<- persist_pipeline_step_update(recovered, file.path(root, "pipeline_state.yaml"),
          "clustering", status, sample_name, reason, details,
          invalidate_downstream = status == "in_progress", invalidation_reason = "Clustering retry requires review.")
      }, progress_callback = function(stage, detail, ...) {
        if (stage == "resolution_complete") progress <<- c(progress, as.numeric(sub("Resolution ([0-9.]+) complete", "\\1", detail)))
      }), finally = end_clustering_execution(owner))
    expect_equal(progress, config$params$resolutions)
    expect_identical(get_pipeline_step(recovered, "clustering", "sample1")$status, "completed")
    expect_identical(get_pipeline_step(recovered, "clustering", "sample1")$attempt, 2L)
    expect_identical(recovered$samples$control, original_control)
    expect_identical(tools::md5sum(paths_list$cell_file_paths), hashes[paths_list$cell_file_paths])
    expect_identical(unname(tools::md5sum(file.path(root, "results", "control.txt"))),
      unname(hashes[file.path(root, "results", "control.txt")]))
  }
})
