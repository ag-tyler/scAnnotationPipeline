fixed_state_time <- as.POSIXct("2026-10-14 12:00:00", tz = "UTC")


test_that("pipeline state initializes every dataset and sample step", {
  state <- new_pipeline_state(
    "Example_Dataset",
    c("sample1", "sample2"),
    timestamp = fixed_state_time
  )

  expect_no_error(validate_pipeline_state(
    state,
    dataset_id = "Example_Dataset",
    sample_names = c("sample1", "sample2")
  ))
  expect_identical(state$schema_version, PIPELINE_STATE_SCHEMA_VERSION)
  expect_identical(state$revision, 0L)
  expect_setequal(names(state$dataset_steps), PIPELINE_DATASET_STEPS)
  expect_setequal(names(state$samples$sample1), PIPELINE_SAMPLE_STEPS)
  expect_true(all(vapply(
    state$samples$sample1,
    function(record) identical(record$status, "not_started"),
    logical(1)
  )))
  expect_true(all(vapply(
    state$samples$sample1,
    function(record) identical(record$attempt, 0L),
    logical(1)
  )))
})


test_that("a new workspace may initialize before sample names are configured", {
  state <- new_pipeline_state("Empty_Dataset", character(), fixed_state_time)

  expect_length(state$samples, 0L)
  expect_no_error(validate_pipeline_state(
    state,
    dataset_id = "Empty_Dataset",
    sample_names = character()
  ))
})


test_that("pipeline transitions enforce status rules, reasons, and attempts", {
  state <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  started <- transition_pipeline_step(
    state,
    "clustering",
    "in_progress",
    sample = "sample1",
    timestamp = fixed_state_time + 1
  )
  completed <- transition_pipeline_step(
    started,
    "clustering",
    "completed",
    sample = "sample1",
    details = list(resolutions = c(0.5, 1)),
    timestamp = fixed_state_time + 2
  )

  expect_identical(get_pipeline_step(started, "clustering", "sample1")$attempt, 1L)
  expect_identical(get_pipeline_step(completed, "clustering", "sample1")$status, "completed")
  expect_identical(
    get_pipeline_step(completed, "clustering", "sample1")$details$resolutions,
    c(0.5, 1)
  )
  expect_error(
    transition_pipeline_step(
      completed,
      "clustering",
      "failed",
      sample = "sample1",
      reason = "late failure"
    ),
    "completed -> failed"
  )
  expect_error(
    transition_pipeline_step(
      state,
      "clustering",
      "failed",
      sample = "sample1"
    ),
    "requires an actionable reason"
  )

  rerun <- transition_pipeline_step(
    completed,
    "clustering",
    "in_progress",
    sample = "sample1",
    timestamp = fixed_state_time + 3
  )
  expect_identical(get_pipeline_step(rerun, "clustering", "sample1")$attempt, 2L)
})


test_that("the declared transition table accepts and rejects every status pair", {
  for (current in PIPELINE_STEP_STATUSES) {
    base <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
    if (current != "not_started") {
      base <- transition_pipeline_step(
        base,
        "clustering",
        current,
        sample = "sample1",
        reason = if (current %in% c("incomplete", "failed", "skipped", "stale")) {
          "Current-state reason"
        } else NULL,
        timestamp = fixed_state_time,
        force = TRUE
      )
    }
    for (target in PIPELINE_STEP_STATUSES) {
      allowed <- identical(current, target) || target %in% PIPELINE_TRANSITIONS[[current]]
      operation <- function() transition_pipeline_step(
        base,
        "clustering",
        target,
        sample = "sample1",
        reason = if (target %in% c("incomplete", "failed", "skipped", "stale")) {
          "Target-state reason"
        } else NULL,
        timestamp = fixed_state_time + 1
      )
      if (allowed) {
        expect_no_error(operation())
      } else {
        expect_error(operation(), "Invalid pipeline transition")
      }
    }
  }
})


test_that("atomic saved decisions may complete directly and be saved again", {
  state <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  state <- transition_pipeline_step(
    state,
    "resolution",
    "completed",
    sample = "sample1",
    details = list(resolution = 0.5),
    timestamp = fixed_state_time + 1
  )
  state <- transition_pipeline_step(
    state,
    "resolution",
    "completed",
    sample = "sample1",
    details = list(resolution = 0.5),
    timestamp = fixed_state_time + 2
  )

  resolution <- get_pipeline_step(state, "resolution", "sample1")
  expect_identical(resolution$status, "completed")
  expect_identical(resolution$attempt, 0L)
  expect_identical(resolution$details$resolution, 0.5)
  expect_identical(resolution$updated_at, "2026-10-14T12:00:02.000Z")
})


test_that("dependency invalidation is sample-scoped and preserves untouched samples", {
  state <- new_pipeline_state(
    "Example_Dataset",
    c("sample1", "sample2"),
    fixed_state_time
  )
  for (sample_name in names(state$samples)) {
    for (step in c(
      "differential_expression", "annotation", "cna_configuration",
      "cna_compute", "cna_assignment"
    )) {
      state <- transition_pipeline_step(
        state,
        step,
        "completed",
        sample = sample_name,
        force = TRUE,
        timestamp = fixed_state_time + 1
      )
    }
  }

  invalidated <- mark_pipeline_steps_stale(
    state,
    upstream_step = "resolution",
    sample = "sample1",
    reason = "Selected resolution changed from 0.5 to 1.0.",
    timestamp = fixed_state_time + 2
  )

  expect_identical(
    get_pipeline_step(invalidated, "differential_expression", "sample1")$status,
    "stale"
  )
  expect_identical(
    get_pipeline_step(invalidated, "cna_assignment", "sample1")$status,
    "stale"
  )
  expect_identical(
    get_pipeline_step(invalidated, "differential_expression", "sample2")$status,
    "completed"
  )
  expect_identical(
    get_pipeline_step(invalidated, "cna_assignment", "sample2")$status,
    "completed"
  )
  expect_identical(
    get_pipeline_step(invalidated, "differential_expression", "sample1")$details$stale_after,
    "resolution"
  )
})


test_that("dataset standardization invalidates completed work across samples", {
  state <- new_pipeline_state(
    "Example_Dataset",
    c("sample1", "sample2"),
    fixed_state_time
  )
  for (sample_name in names(state$samples)) {
    state <- transition_pipeline_step(
      state,
      "clustering",
      "completed",
      sample = sample_name,
      force = TRUE,
      timestamp = fixed_state_time + 1
    )
  }

  invalidated <- mark_pipeline_steps_stale(
    state,
    upstream_step = "standardization",
    reason = "Standardized inputs were regenerated.",
    timestamp = fixed_state_time + 2
  )

  expect_identical(get_pipeline_step(invalidated, "clustering", "sample1")$status, "stale")
  expect_identical(get_pipeline_step(invalidated, "clustering", "sample2")$status, "stale")
  expect_identical(get_pipeline_step(invalidated, "resolution", "sample1")$status, "not_started")
})


test_that("sample reconciliation adds and removes active state without changing logs", {
  state <- new_pipeline_state(
    "Example_Dataset",
    c("sample1", "retired_sample"),
    fixed_state_time
  )
  reconciled <- reconcile_pipeline_state_samples(state, c("sample1", "sample2"))
  changes <- attr(reconciled, "sample_changes")

  expect_identical(names(reconciled$samples), c("sample1", "sample2"))
  expect_identical(changes$added, "sample2")
  expect_identical(changes$removed, "retired_sample")
  expect_identical(
    get_pipeline_step(reconciled, "clustering", "sample2")$status,
    "not_started"
  )
})


test_that("prerequisite readiness distinguishes completed and stale work", {
  state <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  not_ready <- pipeline_step_readiness(state, "differential_expression", "sample1")
  expect_false(not_ready$ready)
  expect_identical(not_ready$unmet, "resolution")

  state <- transition_pipeline_step(
    state,
    "resolution",
    "completed",
    sample = "sample1",
    timestamp = fixed_state_time + 1
  )
  expect_true(pipeline_step_readiness(
    state,
    "differential_expression",
    "sample1"
  )$ready)

  state <- transition_pipeline_step(
    state,
    "resolution",
    "stale",
    sample = "sample1",
    reason = "Clustering changed.",
    timestamp = fixed_state_time + 2
  )
  stale <- pipeline_step_readiness(state, "differential_expression", "sample1")
  expect_false(stale$ready)
  expect_match(stale$reasons, "resolution is stale")
})


test_that("dependency reconciliation marks orphaned legacy completion stale", {
  state <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  state <- transition_pipeline_step(
    state,
    "cna_compute",
    "completed",
    sample = "sample1",
    timestamp = fixed_state_time + 1,
    force = TRUE
  )

  reconciled <- reconcile_pipeline_state_dependencies(
    state,
    timestamp = fixed_state_time + 2
  )
  record <- get_pipeline_step(reconciled, "cna_compute", "sample1")

  expect_identical(record$status, "stale")
  expect_match(record$reason, "annotation is not_started")
  expect_identical(attr(reconciled, "dependency_changes"), "sample1/cna_compute")
})


test_that("pipeline state persists revisions and survives a fresh reload", {
  dataset_dir <- withr::local_tempdir()
  state <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)

  saved <- save_pipeline_state_atomic(
    state,
    dataset_dir,
    timestamp = fixed_state_time + 1
  )
  reloaded <- load_pipeline_state(
    dataset_dir,
    dataset_id = "Example_Dataset",
    sample_names = "sample1"
  )

  expect_identical(saved$revision, 1L)
  expect_identical(reloaded, saved)

  changed <- transition_pipeline_step(
    reloaded,
    "resolution",
    "completed",
    sample = "sample1",
    details = list(resolution = 0.5),
    timestamp = fixed_state_time + 2
  )
  saved_again <- save_pipeline_state_atomic(
    changed,
    dataset_dir,
    timestamp = fixed_state_time + 3
  )
  expect_identical(saved_again$revision, 2L)
  expect_true(file.exists(pipeline_state_paths(dataset_dir)$backup))
})


test_that("stale revisions cannot overwrite newer pipeline state", {
  dataset_dir <- withr::local_tempdir()
  original <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  saved <- save_pipeline_state_atomic(original, dataset_dir, timestamp = fixed_state_time + 1)
  newer <- transition_pipeline_step(
    saved,
    "resolution",
    "completed",
    sample = "sample1",
    timestamp = fixed_state_time + 2
  )
  save_pipeline_state_atomic(newer, dataset_dir, timestamp = fixed_state_time + 3)

  expect_error(
    save_pipeline_state_atomic(saved, dataset_dir, timestamp = fixed_state_time + 4),
    "revision conflict"
  )
})


test_that("a corrupt primary state recovers from its retained backup", {
  dataset_dir <- withr::local_tempdir()
  original <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  saved <- save_pipeline_state_atomic(original, dataset_dir, timestamp = fixed_state_time + 1)
  changed <- transition_pipeline_step(
    saved,
    "resolution",
    "completed",
    sample = "sample1",
    timestamp = fixed_state_time + 2
  )
  save_pipeline_state_atomic(changed, dataset_dir, timestamp = fixed_state_time + 3)

  paths <- pipeline_state_paths(dataset_dir)
  writeLines("not: [valid", paths$primary, useBytes = TRUE)

  expect_warning(
    recovered <- load_pipeline_state(dataset_dir, dataset_id = "Example_Dataset"),
    "Recovered pipeline state from backup"
  )
  expect_identical(recovered$revision, 1L)
  expect_no_error(validate_pipeline_state(yaml::read_yaml(paths$primary)))
})


test_that("stale state locks are recovered and active locks time out", {
  dataset_dir <- withr::local_tempdir()
  state <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  paths <- pipeline_state_paths(dataset_dir)

  dir.create(paths$lock)
  Sys.setFileTime(paths$lock, Sys.time() - 120)
  expect_no_error(save_pipeline_state_atomic(
    state,
    dataset_dir,
    stale_lock_seconds = 1,
    timestamp = fixed_state_time + 1
  ))

  current <- load_pipeline_state(dataset_dir)
  dir.create(paths$lock)
  expect_error(
    save_pipeline_state_atomic(
      current,
      dataset_dir,
      lock_timeout_seconds = 0.05,
      stale_lock_seconds = 60
    ),
    "Timed out waiting"
  )
})


test_that("persisted step updates combine invalidation and one revisioned write", {
  dataset_dir <- withr::local_tempdir()
  state_path <- file.path(dataset_dir, "pipeline_state.yaml")
  state <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  for (step in c("resolution", "differential_expression", "annotation")) {
    state <- transition_pipeline_step(
      state,
      step,
      "completed",
      sample = "sample1",
      force = TRUE,
      timestamp = fixed_state_time + 1
    )
  }
  state <- save_pipeline_state_at_path(state, state_path, fixed_state_time + 2)

  updated <- persist_pipeline_step_update(
    state,
    state_path,
    step = "resolution",
    status = "completed",
    sample = "sample1",
    details = list(resolution = 1),
    invalidate_downstream = TRUE,
    invalidation_reason = "Selected resolution changed.",
    timestamp = fixed_state_time + 3
  )

  expect_identical(updated$revision, 2L)
  expect_identical(get_pipeline_step(updated, "resolution", "sample1")$status, "completed")
  expect_identical(
    get_pipeline_step(updated, "differential_expression", "sample1")$status,
    "stale"
  )
  expect_identical(get_pipeline_step(updated, "annotation", "sample1")$status, "stale")
})


test_that("unchanged decisions preserve downstream completion while changes stale it", {
  dataset_dir <- withr::local_tempdir()
  state_path <- file.path(dataset_dir, "pipeline_state.yaml")
  state <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  for (step in c("resolution", "differential_expression", "annotation")) {
    state <- transition_pipeline_step(
      state,
      step,
      "completed",
      sample = "sample1",
      force = TRUE,
      timestamp = fixed_state_time + 1
    )
  }
  state <- save_pipeline_state_at_path(state, state_path, fixed_state_time + 2)

  unchanged <- persist_pipeline_step_update(
    state,
    state_path,
    step = "resolution",
    status = "completed",
    sample = "sample1",
    details = list(resolution = 0.5),
    invalidate_downstream = FALSE,
    timestamp = fixed_state_time + 3
  )
  expect_identical(
    get_pipeline_step(unchanged, "differential_expression", "sample1")$status,
    "completed"
  )

  changed <- persist_pipeline_step_update(
    unchanged,
    state_path,
    step = "resolution",
    status = "completed",
    sample = "sample1",
    details = list(resolution = 1),
    invalidate_downstream = TRUE,
    invalidation_reason = "Selected resolution changed.",
    timestamp = fixed_state_time + 4
  )
  expect_identical(
    get_pipeline_step(changed, "differential_expression", "sample1")$status,
    "stale"
  )
})


test_that("CNA reset preserves configuration and resets computation onward", {
  state <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  for (step in c(
    "cna_configuration", "cna_compute", "cna_cluster_selection",
    "cna_signal_correlation", "cna_thresholds", "cna_assignment"
  )) {
    state <- transition_pipeline_step(
      state,
      step,
      "completed",
      sample = "sample1",
      force = TRUE,
      timestamp = fixed_state_time + 1
    )
  }

  reset <- reset_pipeline_steps(
    state,
    c(
      "cna_compute", "cna_cluster_selection", "cna_signal_correlation",
      "cna_thresholds", "cna_assignment"
    ),
    sample = "sample1",
    timestamp = fixed_state_time + 2
  )

  expect_identical(
    get_pipeline_step(reset, "cna_configuration", "sample1")$status,
    "completed"
  )
  expect_true(all(vapply(
    reset$samples$sample1[c(
      "cna_compute", "cna_cluster_selection", "cna_signal_correlation",
      "cna_thresholds", "cna_assignment"
    )],
    function(record) identical(record$status, "not_started"),
    logical(1)
  )))
})


test_that("every workflow status has a UI presentation", {
  for (status in PIPELINE_STEP_STATUSES) {
    record <- new_pipeline_step_record()
    record$status <- status
    if (status %in% c("incomplete", "failed", "skipped", "stale")) {
      record$reason <- "Test reason"
    }
    view <- pipeline_status_presentation(record, "Example")
    expect_identical(view$status, status)
    expect_match(view$label, "^Example:")
    expect_true(nzchar(view$class))
    expect_true(nzchar(view$icon))
  }
})


test_that("repeated state updates do not replace append-only event history", {
  dataset_dir <- withr::local_tempdir()
  state_path <- file.path(dataset_dir, "pipeline_state.yaml")
  state <- save_pipeline_state_at_path(
    new_pipeline_state("Example_Dataset", "sample1", fixed_state_time),
    state_path,
    fixed_state_time
  )

  for (index in 1:2) {
    state <- persist_pipeline_step_update(
      state,
      state_path,
      step = "resolution",
      status = "completed",
      sample = "sample1",
      details = list(resolution = 0.5),
      timestamp = fixed_state_time + index
    )
    log_pipeline_event(
      dataset_dir_path = dataset_dir,
      dataset = "Example_Dataset",
      sample = "sample1",
      stage = "resolution",
      event_type = "resolution_saved",
      outcome = "saved",
      parameters = list(revision = state$revision),
      timestamp = fixed_state_time + index
    )
  }

  paths <- pipeline_log_paths(dataset_dir)
  structured_lines <- readLines(paths$structured, warn = FALSE)
  expect_length(structured_lines, 2L)
  expect_match(structured_lines[[1]], '"revision":2')
  expect_match(structured_lines[[2]], '"revision":3')
})


test_that("legacy initialization conservatively infers current artifacts", {
  dataset_dir <- withr::local_tempdir()
  processed_dir <- file.path(dataset_dir, "processed_data")
  sample_dir <- file.path(processed_dir, "sample1")
  results_dir <- file.path(dataset_dir, "results", "sample1")
  de_dir <- file.path(results_dir, "2_de_plots")
  cache_dir <- file.path(dataset_dir, "cache")
  dir.create(sample_dir, recursive = TRUE)
  dir.create(de_dir, recursive = TRUE)
  dir.create(cache_dir)

  file.create(file.path(sample_dir, c("Exp_data_UMIcounts.mtx", "Genes.txt")))
  writeLines(
    "cell_name,sample,cell_type",
    file.path(sample_dir, "Cells.csv"),
    useBytes = TRUE
  )
  file.create(file.path(processed_dir, "Samples.csv"))
  file.create(file.path(cache_dir, c(
    "expmat_filt_sample1.qs2",
    "cells_filt_clust_res_0.5_sample1.qs2",
    "cells_filt_clust_res_1_sample1.qs2"
  )))
  file.create(file.path(de_dir, c(
    "all_marker_matches.csv",
    "top_50_unannotated_gene_count_plot.png"
  )))

  config <- list(dataset_paths = list(
    processed_dir = "processed_data",
    results_dir = "results"
  ))
  dataset_config <- list(
    std_names = list(
      expmat = "Exp_data_UMIcounts.mtx",
      genes = "Genes.txt",
      cells = "Cells.csv",
      samples = "Samples.csv"
    ),
    params = list(resolutions = c(0.5, 1))
  )
  selected_config <- list(
    resolutions = list(sample1 = 0.5),
    cna_ref_cells = list(sample1 = character()),
    cna_pot_mal_cells = list(sample1 = character()),
    cna_ward_ref_cluster = list(sample1 = list()),
    cna_thresholds = list(sample1 = list())
  )

  state <- load_or_initialize_pipeline_state(
    dataset_dir,
    dataset_id = "Legacy_Dataset",
    sample_names = "sample1",
    dataset_config = dataset_config,
    selected_config = selected_config,
    config = config,
    timestamp = fixed_state_time
  )

  expect_true(isTRUE(attr(state, "initialized")))
  expect_identical(get_pipeline_step(state, "standardization")$status, "completed")
  expect_identical(get_pipeline_step(state, "clustering", "sample1")$status, "completed")
  expect_identical(get_pipeline_step(state, "resolution", "sample1")$status, "completed")
  expect_identical(
    get_pipeline_step(state, "differential_expression", "sample1")$status,
    "completed"
  )
  expect_identical(
    get_pipeline_step(state, "clustering", "sample1")$details$provenance,
    "legacy_inference"
  )
  expect_true(file.exists(pipeline_state_paths(dataset_dir)$primary))
})


test_that("loading existing state reconciles configured samples and persists it", {
  dataset_dir <- withr::local_tempdir()
  state <- new_pipeline_state(
    "Example_Dataset",
    c("sample1", "retired"),
    fixed_state_time
  )
  saved <- save_pipeline_state_atomic(state, dataset_dir, timestamp = fixed_state_time + 1)

  reconciled <- load_or_initialize_pipeline_state(
    dataset_dir,
    dataset_id = "Example_Dataset",
    sample_names = c("sample1", "sample2"),
    infer_legacy = FALSE,
    timestamp = fixed_state_time + 2
  )

  expect_false(isTRUE(attr(reconciled, "initialized")))
  expect_identical(names(reconciled$samples), c("sample1", "sample2"))
  expect_identical(attr(reconciled, "sample_changes")$added, "sample2")
  expect_identical(attr(reconciled, "sample_changes")$removed, "retired")
  expect_identical(reconciled$revision, saved$revision + 1L)
  expect_identical(
    names(load_pipeline_state(dataset_dir)$samples),
    c("sample1", "sample2")
  )
})


test_that("cache reconciliation marks legacy untracked artifacts and downstream work stale", {
  dataset_dir <- withr::local_tempdir()
  sample_dir <- file.path(dataset_dir, "processed_data", "sample1")
  dir.create(sample_dir, recursive = TRUE)
  cells_path <- file.path(sample_dir, "Cells.csv")
  expression_path <- file.path(sample_dir, "Exp_data_UMIcounts.mtx")
  genes_path <- file.path(sample_dir, "Genes.txt")
  data.table::fwrite(
    data.table::data.table(cell_name = "c1", sample = "sample1", complexity = 1),
    cells_path
  )
  file.create(expression_path, genes_path)
  cache_dir <- setup_cache_dir(dataset_dir)
  file.create(
    file.path(
      cache_dir,
      c("expmat_filt_sample1.qs2", "cells_filt_clust_res_0.5_sample1.qs2")
    )
  )

  state <- new_pipeline_state("Example_Dataset", "sample1", fixed_state_time)
  state <- transition_pipeline_step(
    state, "clustering", "completed", sample = "sample1", force = TRUE
  )
  state <- transition_pipeline_step(
    state, "resolution", "completed", sample = "sample1", force = TRUE
  )
  paths_list <- list(
    sample_dir_paths = sample_dir,
    cell_file_paths = cells_path,
    expmat_file_paths = expression_path,
    genes_file_paths = genes_path
  )
  config <- list(params = list(
    min_genes = 1,
    target_sum = 1e5,
    log2_expr_threshold = 0,
    pca_nv = 2,
    seed = 1,
    umap = list(spread = 1, min_dist = 0.1),
    resolutions = 0.5
  ))

  reconciled <- reconcile_pipeline_state_cache(
    state,
    paths_list,
    config,
    selected_config = list(resolutions = list(sample1 = 0.5)),
    dataset_dir_path = dataset_dir,
    gene_positions = data.table::data.table()
  )

  expect_identical(get_pipeline_step(reconciled, "clustering", "sample1")$status, "stale")
  expect_identical(get_pipeline_step(reconciled, "resolution", "sample1")$status, "stale")
  expect_identical(attr(reconciled, "cache_changes"), "sample1/clustering")
})
