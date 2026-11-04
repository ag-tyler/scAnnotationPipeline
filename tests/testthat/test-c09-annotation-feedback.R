test_that("C09 progress counts saved ready records across configured samples without I/O", {
  root <- withr::local_tempdir()
  state <- new_pipeline_state("Progress", c("Saved", "Pending", "Rerun", "Unconfigured"))
  state <- transition_pipeline_step(state, "standardization", "completed", force = TRUE)
  for (sample in names(state$samples)) for (step in c("clustering", "resolution", "differential_expression", "annotation")) {
    state <- transition_pipeline_step(state, step, "completed", sample, force = TRUE)
  }
  state <- transition_pipeline_step(state, "annotation", "incomplete", "Pending", reason = "Review annotations", force = TRUE)
  configured <- c("Saved", "Pending", "Rerun", "Missing")
  before <- state
  summary <- annotation_progress_summary(state, configured, "Saved", TRUE)
  expect_equal(summary$saved, 2L)
  expect_equal(summary$total, 4L)
  expect_identical(summary$unsaved_sample, "Saved")
  expect_identical(state, before)
  expect_null(annotation_progress_summary(state, configured, NULL, TRUE)$unsaved_sample)
  expect_equal(annotation_progress_summary(state, character())$total, 0L)
  path <- file.path(root, "pipeline_state.yaml")
  state <- persist_pipeline_step_update(state, path, "annotation", "completed", "Pending")
  expect_equal(annotation_progress_summary(state, configured)$saved, 3L)
  state <- persist_pipeline_step_update(state, path, "differential_expression", "in_progress", "Rerun",
    invalidate_downstream = TRUE, invalidation_reason = "DE rerun")
  expect_equal(annotation_progress_summary(state, configured)$saved, 2L)
  expect_equal(annotation_progress_summary(load_pipeline_state(root), configured)$saved, 2L)
  expect_false("Unconfigured" %in% annotation_progress_summary(state, configured)$samples)
  code <- paste(deparse(body(annotation_progress_summary)), collapse = "\n")
  expect_false(grepl("cache_|read_yaml|fread|write|save_", code))
})

test_that("C09 origin reminder is optional and accepts either DOI or URL", {
  for (origin in list(NULL, list(), list(source_doi = " ", source_url = NA_character_))) {
    expect_match(dataset_origin_reminder(list(project_info = origin)), "Optional source DOI or URL", fixed = TRUE)
    expect_match(dataset_origin_reminder(list(project_info = origin)), "snapshots remain available", fixed = TRUE)
  }
  expect_null(dataset_origin_reminder(list(project_info = list(source_doi = "10.1234/example"))))
  expect_null(dataset_origin_reminder(list(project_info = list(source_url = "https://example.org/data"))))
  options <- app_annotation_dropdown_options(create = TRUE, placeholder = "Search")
  expect_identical(options$dropdownParent, "body")
  expect_identical(options$create, TRUE)
  expect_match(as.character(options$onInitialize), "window.innerHeight", fixed = TRUE)
  expect_match(as.character(options$onInitialize), "overflowY: 'auto'", fixed = TRUE)
})
