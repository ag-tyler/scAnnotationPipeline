test_that("release contracts survive a multi-sample restart and recovery", {
  skip_if_not_installed("qs2")

  dataset_dir <- withr::local_tempdir()
  processed_dir <- file.path(dataset_dir, "processed_data")
  dir.create(processed_dir)
  sample_names <- c("sample1", "sample2")
  std_names <- list(
    expmat = "Exp_data_UMIcounts.mtx",
    genes = "Genes.txt",
    cells = "Cells.csv",
    samples = "Samples.csv"
  )

  fixtures <- Map(
    function(sample_name, seed) {
      write_mini_sample(
        processed_dir,
        sample_name = sample_name,
        n_genes = 20,
        n_cells = 12,
        seed = seed,
        cell_prefix = paste0(sample_name, "_")
      )
    },
    sample_names,
    c(101, 102)
  )
  data.table::fwrite(
    data.table::data.table(
      sample = sample_names,
      n_cells = vapply(fixtures, function(fixture) nrow(fixture$cells), integer(1))
    ),
    file.path(processed_dir, std_names$samples)
  )

  validation <- NULL
  expect_output(
    validation <- validate_standardization(
      processed_dir,
      sample_names,
      std_names,
      strict = TRUE
    ),
    "POST-VALIDATION PASSED"
  )
  expect_true(validation$valid)

  timestamp <- as.POSIXct("2026-10-16 12:00:00", tz = "UTC")
  state <- new_pipeline_state("Release_Dataset", sample_names, timestamp)
  state <- transition_pipeline_step(
    state,
    "standardization",
    "completed",
    details = list(samples = length(sample_names)),
    timestamp = timestamp + 1
  )
  for (index in seq_along(sample_names)) {
    sample_name <- sample_names[[index]]
    state <- transition_pipeline_step(
      state,
      "clustering",
      "completed",
      sample = sample_name,
      force = TRUE,
      details = list(resolutions = 0.5),
      timestamp = timestamp + index + 1
    )
    cache_save_data(
      fixtures[[index]]$cells,
      paste0("cells_filt_clust_res_0.5_", sample_name, ".qs2"),
      dataset_dir,
      producer = "t23-release-integration"
    )
    log_pipeline_event(
      dataset_dir,
      dataset = "Release_Dataset",
      sample = sample_name,
      stage = "clustering",
      event_type = "clustering_run",
      outcome = "completed",
      parameters = list(resolution = 0.5),
      timestamp = timestamp + index + 1
    )
  }
  saved <- save_pipeline_state_atomic(state, dataset_dir, timestamp = timestamp + 10)

  reloaded <- load_pipeline_state(
    dataset_dir,
    dataset_id = "Release_Dataset",
    sample_names = sample_names
  )
  events_before_recovery <- read_pipeline_events(dataset_dir)
  expect_identical(reloaded, saved)
  expect_length(events_before_recovery, 2L)
  expect_identical(
    vapply(events_before_recovery, `[[`, character(1), "sample"),
    sample_names
  )
  expect_true(all(vapply(sample_names, function(sample_name) {
    cache_check_valid(
      paste0("cells_filt_clust_res_0.5_", sample_name, ".qs2"),
      dataset_dir
    )
  }, logical(1))))

  newer <- transition_pipeline_step(
    reloaded,
    "resolution",
    "completed",
    sample = "sample1",
    force = TRUE,
    details = list(resolution = 0.5),
    timestamp = timestamp + 11
  )
  save_pipeline_state_atomic(newer, dataset_dir, timestamp = timestamp + 12)
  writeLines("not: [valid", pipeline_state_paths(dataset_dir)$primary, useBytes = TRUE)

  expect_warning(
    recovered <- load_pipeline_state(
      dataset_dir,
      dataset_id = "Release_Dataset",
      sample_names = sample_names
    ),
    "Recovered pipeline state from backup"
  )
  expect_identical(recovered$revision, saved$revision)
  expect_identical(read_pipeline_events(dataset_dir), events_before_recovery)
})
