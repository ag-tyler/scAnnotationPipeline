make_c04_archived_fixture <- function(root) {
  samples <- c("Recover", "Control", "Omitted")
  state <- new_pipeline_state(basename(root), samples)
  state <- transition_pipeline_step(state, "standardization", "completed", force = TRUE)
  selected <- setup_selected_config(samples)
  cells_paths <- character()
  results <- file.path(root, "results")
  for (sample in samples) {
    selected$resolutions[[sample]] <- 0.5
    selected$cna_ref_cells[[sample]] <- "T_cell"
    selected$cna_pot_mal_cells[[sample]] <- "Epithelial"
    selected$cna_ward_ref_cluster[[sample]] <- list(list(k = 2L, cluster = 1L))
    folder <- file.path(root, "processed_data", sample)
    dir.create(folder, recursive = TRUE)
    cell_path <- file.path(folder, "Cells.csv")
    writeLines(paste0("cell_name,sample,cell_type\ncell1,", sample, ",T_cell"), cell_path)
    cells_paths <- c(cells_paths, cell_path)
    for (step in PIPELINE_SAMPLE_STEPS) state <- transition_pipeline_step(state, step, "completed", sample, force = TRUE)
    if (sample == "Omitted") state <- transition_pipeline_step(state, "cna_configuration", "skipped", sample,
      reason = "CNA intentionally omitted.", details = list(omitted_by_user = TRUE), force = TRUE)
    files <- c(file.path("1_cluster_plots", paste0("clusters_plot_", sample, "_res_0.5.png")),
      "2_de_plots/all_marker_matches.csv", "2_de_plots/score_plot.png",
      file.path("3_cna_plots", paste0("cna_summary_heatmap_", sample, ".png")),
      file.path("3_cna_plots", paste0("cna_umap_assigned_", sample, ".png")))
    for (file in files) {
      path <- file.path(results, sample, file)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      writeLines("retained scientific output fixture", path)
    }
    cache_save_data(data.frame(cell_name = "cell1", value = 1), paste0("cells_", sample, "_res_0.5.qs2"), root)
  }
  state <- save_pipeline_state_atomic(state, root)
  selected_path <- file.path(root, "selected_config.yaml")
  yaml::write_yaml(selected, selected_path)
  paths <- list(sample_dir_paths = dirname(cells_paths), cell_file_paths = cells_paths)
  storage <- save_dataset_storage_state_atomic(new_dataset_storage_state(basename(root)), root)
  ready <- dataset_cleanup_readiness(state, paths, selected, selected_path, results, root)
  stopifnot(ready$ready)
  archived <- archive_dataset_cache(root, state, storage, ready)
  reopened <- reopen_archived_dataset(root, state, file.path(root, "pipeline_state.yaml"), archived)
  list(state = reopened$pipeline_state, path = file.path(root, "pipeline_state.yaml"),
    scientific = c(cells_paths, list.files(results, recursive = TRUE, full.names = TRUE)))
}

test_that("C04 archive/reopen recovery advances CNA next actions without completing retained stale work", {
  fx <- make_c04_archived_fixture(withr::local_tempdir())
  state <- fx$state
  control <- state$samples$Control
  omitted <- state$samples$Omitted
  hashes <- tools::md5sum(fx$scientific)
  expect_identical(pipeline_cna_analysis_record(state, "Recover")$status, "stale")
  expect_match(get_pipeline_step(state, "cna_compute", "Recover")$reason, "rerun clustering")
  for (step in PIPELINE_SAMPLE_STEPS) {
    if (!(step %in% PIPELINE_ATOMIC_DECISION_STEPS)) {
      state <- persist_pipeline_step_update(state, fx$path, step, "in_progress", "Recover")
      if (step %in% PIPELINE_STALE_DEPENDENCIES$cna_configuration) {
        expect_identical(pipeline_cna_analysis_record(state, "Recover")$status, "in_progress")
      }
    }
    state <- persist_pipeline_step_update(state, fx$path, step, "completed", "Recover")
    summary <- summarize_pipeline_overview(state)
    pending <- PIPELINE_SAMPLE_STEPS[match(step, PIPELINE_SAMPLE_STEPS) + 1L]
    if (step == "cna_configuration") {
      expect_true(pipeline_step_readiness(state, "cna_compute", "Recover")$ready)
      expect_identical(get_pipeline_step(state, "cna_compute", "Recover")$status, "stale")
      expect_null(get_pipeline_step(state, "cna_configuration", "Recover")$reason)
      expect_identical(summary$samples$Recover$records$cna_analysis$status, "incomplete")
      expect_match(summary$samples$Recover$next_action$label, "Compute base CNA", fixed = TRUE)
    }
    if (step != "cna_assignment") {
      expect_match(get_pipeline_step(state, "cna_assignment", "Recover")$reason, pipeline_recovery_action(pending), fixed = TRUE)
      expect_false(grepl("rerun clustering", get_pipeline_step(state, "cna_assignment", "Recover")$reason, fixed = TRUE))
    }
    if (step %in% c("cna_compute", "cna_cluster_selection", "cna_signal_correlation", "cna_thresholds")) {
      expect_identical(summary$samples$Recover$records$cna_analysis$status, "incomplete")
      expect_identical(summary$samples$Recover$records$cna_analysis$details$next_step, pending)
    }
    reloaded <- reconcile_pipeline_state_dependencies(load_pipeline_state(dirname(fx$path)))
    expect_length(attr(reloaded, "dependency_changes"), 0L)
    expect_identical(reloaded$samples, state$samples)
    expect_identical(state$samples$Control, control)
    expect_identical(state$samples$Omitted, omitted)
    expect_identical(tools::md5sum(fx$scientific), hashes)
  }
  expect_identical(pipeline_cna_analysis_record(state, "Recover")$status, "completed")
  expect_true(summarize_pipeline_overview(state)$samples$Recover$next_action$complete)
  expect_identical(summarize_pipeline_overview(state)$samples$Control$records$cna_analysis$status, "stale")
})

test_that("C04 ready legacy cleanup reasons reconcile on reload; missing config and omission stay distinct", {
  fx <- make_c04_archived_fixture(withr::local_tempdir())
  state <- fx$state
  for (step in c("clustering", "resolution", "differential_expression", "annotation", "cna_configuration")) {
    state <- transition_pipeline_step(state, step, "completed", "Recover", force = TRUE)
  }
  expect_match(get_pipeline_step(state, "cna_compute", "Recover")$reason, "rerun clustering")
  refreshed <- reconcile_pipeline_state_dependencies(state)
  expect_match(get_pipeline_step(refreshed, "cna_compute", "Recover")$reason, "Compute base CNA", fixed = TRUE)
  expect_true("Recover/cna_compute" %in% attr(refreshed, "dependency_changes"))
  expect_identical(refreshed$samples$Control, state$samples$Control)
  state <- save_pipeline_state_at_path(refreshed, fx$path)
  state <- persist_pipeline_step_update(state, fx$path, "cna_configuration", "incomplete", "Recover",
    reason = "Both reference and candidate types are required.", force = TRUE)
  expect_false(pipeline_cna_is_omitted(state, "Recover"))
  expect_false(pipeline_step_readiness(state, "cna_compute", "Recover")$ready)
  expect_match(get_pipeline_step(state, "cna_compute", "Recover")$reason, "Configure or omit CNA", fixed = TRUE)
  state <- persist_pipeline_step_update(state, fx$path, "cna_configuration", "skipped", "Recover",
    reason = "CNA intentionally omitted.", details = list(omitted_by_user = TRUE))
  expect_true(pipeline_cna_is_omitted(state, "Recover"))
  expect_identical(pipeline_cna_analysis_record(state, "Recover")$status, "skipped")
  state <- persist_pipeline_step_update(state, fx$path, "cna_configuration", "completed", "Recover",
    details = list(omitted_by_user = FALSE))
  expect_identical(pipeline_cna_analysis_record(state, "Recover")$status, "not_started")
})

test_that("C04 read-only summary preserves real cache failures and follows the first unfinished CNA step", {
  state <- new_pipeline_state("Diagnosis", "sample")
  for (step in PIPELINE_SAMPLE_STEPS) state <- transition_pipeline_step(state, step, "completed", "sample", force = TRUE)
  state <- transition_pipeline_step(state, "cna_compute", "stale", "sample",
    reason = "CNA cache checksum mismatch; recompute CNA.", details = list(stale_after = "cache_validation"), force = TRUE)
  before <- serialize(state, NULL)
  record <- pipeline_cna_analysis_record(state, "sample")
  expect_identical(record$status, "stale")
  expect_match(record$reason, "checksum mismatch", fixed = TRUE)
  expect_identical(serialize(state, NULL), before)
  state <- transition_pipeline_step(state, "cna_compute", "in_progress", "sample")
  state <- transition_pipeline_step(state, "cna_assignment", "failed", "sample", reason = "Earlier assignment failed.", force = TRUE)
  expect_identical(pipeline_cna_analysis_record(state, "sample")$status, "in_progress")
})
