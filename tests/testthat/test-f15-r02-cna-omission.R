make_r02_workspace <- function(.local_envir = parent.frame()) {
  dataset_dir <- withr::local_tempdir(.local_envir = .local_envir)
  sample_names <- c("Omitted", "Configured")
  state <- new_pipeline_state("R02", sample_names)
  state <- transition_pipeline_step(state, "standardization", "completed", force = TRUE)
  selected <- setup_selected_config(sample_names)
  genes <- paste0("GENE", 1:30)
  for (sample in sample_names) {
    for (step in c("clustering", "resolution", "differential_expression", "annotation")) {
      state <- transition_pipeline_step(state, step, "completed", sample, force = TRUE)
    }
    cell_names <- paste0(sample, "_cell", 1:4)
    cells <- data.table::data.table(
      cell_name = cell_names, sample = sample,
      cell_type = c("Reference", "Reference", "Candidate", "Candidate"),
      umap1 = 1:4, umap2 = 4:1, clust = c(1L, 1L, 2L, 2L)
    )
    matrix <- Matrix::Matrix(matrix(1:120, 30, dimnames = list(genes, cell_names)), sparse = TRUE)
    cache_save_data(cells, paste0("cells_filt_clust_res_0.5_", sample, ".qs2"), dataset_dir)
    cache_save_data(matrix, paste0("expmat_filt_", sample, ".qs2"), dataset_dir)
    selected$resolutions[[sample]] <- 0.5
  }
  state <- transition_pipeline_step(state, "cna_configuration", "skipped", "Omitted",
    reason = "CNA is not warranted.", details = list(omitted_by_user = TRUE), force = TRUE)
  state <- transition_pipeline_step(state, "cna_configuration", "completed", "Configured", force = TRUE)
  selected$cna_ref_cells$Configured <- "Reference"
  selected$cna_pot_mal_cells$Configured <- "Candidate"
  state <- save_pipeline_state_atomic(state, dataset_dir)
  yaml::write_yaml(selected, file.path(dataset_dir, "selected_config.yaml"))
  list(dataset_dir = dataset_dir, state = state, selected = selected,
    positions = data.table::data.table(symbol = genes),
    paths = list(sample_dir_paths = file.path(dataset_dir, "processed_data", sample_names)),
    config = list(params = list(resolutions = 0.5)))
}

test_that("R02 explicit omissions survive dependency/cache reconciliation and repeated reloads", {
  skip_if_not_installed("qs2")
  fx <- make_r02_workspace()
  # Reproduce the persisted state left by the old batch/reload path.
  state <- transition_pipeline_step(fx$state, "cna_compute", "stale", "Omitted",
    reason = "cna_configuration is skipped", details = list(preflight_status = "omitted"), force = TRUE)
  save_pipeline_state_atomic(state, fx$dataset_dir)
  other <- withr::local_tempdir()
  save_pipeline_state_atomic(new_pipeline_state("Other", "OtherSample"), other)
  for (iteration in 1:2) {
    load_pipeline_state(other, "Other", "OtherSample")
    selected <- yaml::read_yaml(file.path(fx$dataset_dir, "selected_config.yaml"))
    loaded <- load_or_initialize_pipeline_state(fx$dataset_dir, "R02", c("Omitted", "Configured"))
    reconciled <- reconcile_pipeline_state_cache(loaded, fx$paths, fx$config,
      selected, fx$dataset_dir, fx$positions)
    expect_identical(get_pipeline_step(reconciled, "cna_compute", "Omitted")$status, "skipped")
    expect_identical(get_pipeline_step(reconciled, "cna_configuration", "Omitted")$status, "skipped")
    expect_length(attr(reconciled, "cache_changes"), 0L)
    expect_true(pipeline_cna_is_omitted(reconciled, "Omitted"))
    expect_false(pipeline_step_readiness(reconciled, "cna_compute", "Omitted")$ready)
    expect_identical(get_pipeline_step(reconciled, "cna_compute", "Configured")$status, "not_started")
    expect_true(cna_sample_preflight("Configured", selected, fx$dataset_dir,
      fx$positions, pipeline_state = reconciled)$eligible)
  }
  second <- reconcile_pipeline_state_dependencies(reconciled)
  expect_length(attr(second, "dependency_changes"), 0L)
  expect_identical(get_pipeline_step(second, "cna_compute", "Omitted"),
    get_pipeline_step(reconciled, "cna_compute", "Omitted"))

  # An omitted decision does not excuse a real upstream rerun.
  upstream <- transition_pipeline_step(second, "annotation", "stale", "Omitted",
    reason = "DE was rerun", force = TRUE)
  invalidated <- reconcile_pipeline_state_dependencies(upstream)
  expect_identical(get_pipeline_step(invalidated, "cna_configuration", "Omitted")$status, "stale")
  expect_identical(get_pipeline_step(invalidated, "cna_compute", "Omitted")$status, "stale")
})

test_that("R02 omission preflight does no cache I/O and does not complain about empty configuration", {
  state <- new_pipeline_state("R02", "Sample")
  state <- transition_pipeline_step(state, "annotation", "completed", "Sample", force = TRUE)
  state <- transition_pipeline_step(state, "cna_configuration", "skipped", "Sample",
    reason = "CNA is not warranted.", details = list(omitted_by_user = TRUE), force = TRUE)
  env <- new.env(parent = environment(cna_sample_preflight))
  env$load_cache_manifest <- env$cache_load_data <- function(...) stop("Unexpected cache I/O")
  preflight <- cna_sample_preflight
  environment(preflight) <- env
  result <- preflight("Sample", setup_selected_config("Sample"), "absent-directory",
    pipeline_state = state)
  expect_identical(result$status, "omitted")
  expect_false(result$eligible)
  expect_length(result$reasons, 1L)
  expect_match(result$reason, "explicitly omitted")
  expect_false(grepl("missing|not configured|invalid", result$reason))
  expect_null(result$cells)
  expect_null(result$expmat)
  expect_true(all(is.na(unlist(result$counts))))

  # A generic skipped status is not evidence of a user's explicit decision.
  state$samples$Sample$cna_configuration$details$omitted_by_user <- FALSE
  ordinary <- cna_sample_preflight("Sample", setup_selected_config("Sample"),
    withr::local_tempdir(), pipeline_state = state)
  expect_identical(ordinary$status, "incomplete")
})

test_that("R02 saving configuration reverses omission without enabling stale results", {
  skip_if_not_installed("qs2")
  fx <- make_r02_workspace()
  state_path <- pipeline_state_paths(fx$dataset_dir)$primary
  state <- persist_pipeline_step_update(fx$state, state_path, "cna_configuration", "skipped", "Omitted",
    reason = "CNA is not warranted.", details = list(omitted_by_user = TRUE))
  expect_identical(get_pipeline_step(state, "cna_compute", "Omitted")$status, "skipped")
  state <- persist_pipeline_step_update(state, state_path, "cna_configuration", "completed", "Omitted",
    details = list(omitted_by_user = FALSE), invalidate_downstream = TRUE,
    invalidation_reason = "New CNA configuration saved.")
  fx$selected$cna_ref_cells$Omitted <- "Reference"
  fx$selected$cna_pot_mal_cells$Omitted <- "Candidate"
  yaml::write_yaml(fx$selected, file.path(fx$dataset_dir, "selected_config.yaml"))
  expect_identical(get_pipeline_step(state, "cna_compute", "Omitted")$status, "not_started")
  expect_true(pipeline_step_readiness(state, "cna_compute", "Omitted")$ready)
  expect_true(cna_sample_preflight("Omitted", fx$selected, fx$dataset_dir,
    fx$positions, pipeline_state = state)$eligible)
  expect_identical(get_pipeline_step(state, "cna_assignment", "Omitted")$status, "not_started")
  loaded <- load_or_initialize_pipeline_state(fx$dataset_dir, "R02", c("Omitted", "Configured"))
  expect_identical(get_pipeline_step(loaded, "cna_compute", "Omitted")$status, "not_started")
  expect_false(pipeline_cna_is_omitted(loaded, "Omitted"))
})

test_that("R02 mixed batch skips omissions and computes only the configured sample", {
  skip_if_not_installed("qs2")
  fx <- make_r02_workspace()
  events <- list()
  computed <- character()
  env <- new.env(parent = environment(batch_compute_cna_and_heatmaps))
  env$cna_matrix_cache_dependencies <- function(...) list()
  env$cache_check_valid <- function(...) FALSE
  env$compute_cna_and_cache <- function(expmat, gene_positions, ref_cells, sample_name, dataset_dir_path) {
    computed <<- c(computed, sample_name)
  }
  env$cna_clustering_and_heatmaps <- function(...) invisible(NULL)
  batch <- batch_compute_cna_and_heatmaps
  environment(batch) <- env
  result <- batch(fx$paths, fx$dataset_dir,
    file.path(fx$dataset_dir, "results"), fx$selected, fx$positions,
    pipeline_state = fx$state,
    state_callback = function(sample_name, status, reason = NULL, details = NULL) {
      events[[length(events) + 1L]] <<- list(sample = sample_name, status = status, details = details)
    })
  expect_identical(result$skipped, "Omitted")
  expect_identical(result$processed, "Configured")
  expect_identical(computed, "Configured")
  expect_length(events, 3L)
  expect_identical(events[[1]]$status, "skipped")
  expect_identical(events[[1]]$details$preflight_status, "omitted")
  expect_identical(result$preflight$Omitted$status, "omitted")
  expect_false(any(grepl("not configured|cache is missing", result$preflight$Omitted$reason)))
})

test_that("R02 readiness distinguishes saved configuration from missing artifacts", {
  skip_if_not_installed("qs2")
  fx <- make_r02_workspace()
  file.remove(file.path(fx$dataset_dir, "cache", "expmat_filt_Configured.qs2"))
  result <- cna_sample_preflight("Configured", fx$selected, fx$dataset_dir,
    fx$positions, pipeline_state = fx$state)
  expect_false(result$eligible)
  expect_identical(result$status, "incomplete")
  expect_match(result$reason, "filtered expression cache is missing or invalid", fixed = TRUE)
  expect_false(grepl("not configured|save reference", result$reason))
  expect_identical(get_pipeline_step(fx$state, "cna_configuration", "Configured")$status, "completed")
})

test_that("R02 CNA view reflects saved configuration and omission when switching samples", {
  skip_if_not_installed("qs2")
  suppressPackageStartupMessages(library(shiny))
  fx <- make_r02_workspace()
  env <- new.env(parent = environment(cna_sample_preflight))
  env$nav_select <- function(...) invisible(NULL)
  env$record_state_event <- function(...) invisible(NULL)
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  sys.source(file.path(app_dir, "app/server/cna_status_server.R"), envir = env)
  state <- reactiveValues(paths_list = fx$paths, live_selected_config = fx$selected,
    pipeline_state = reconcile_pipeline_state_dependencies(fx$state), dataset_dir_path = fx$dataset_dir)
  context <- list(resources = list(gene_positions = fx$positions))
  server <- function(input, output, session) env$register_cna_status_server(input, output, session, state, context)
  shiny::testServer(server, {
    session$setInputs(cna_sample_idx = "1")
    expect_match(output$cna_eligibility_ui$html, "CNA intentionally omitted")
    expect_match(output$cna_status_ui$html, "No CNA computation is required")
    expect_false(grepl("Stale|not configured|cache is missing", output$cna_status_ui$html))
    session$setInputs(cna_sample_idx = "2")
    expect_match(output$cna_eligibility_ui$html, "Eligible for CNA")
    expect_match(output$cna_status_ui$html, "Base CNA &amp; Heatmaps|Base CNA & Heatmaps")
    session$setInputs(cna_sample_idx = "1")
    expect_match(output$cna_status_ui$html, "No CNA computation is required")
  })
})
