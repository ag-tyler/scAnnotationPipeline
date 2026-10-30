app_dir_f16 <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
suppressPackageStartupMessages(library(shiny))
suppressPackageStartupMessages(library(bslib))


make_f16_workspace <- function(sample_name = "Sample_A") {
  root <- tempfile("f16-")
  dataset_dir <- file.path(root, "dataset")
  sample_dir <- file.path(dataset_dir, "processed", sample_name)
  results_dir <- file.path(dataset_dir, "results")
  sample_results <- file.path(results_dir, sample_name)
  de_dir <- file.path(sample_results, "2_de_plots")
  cluster_dir <- file.path(sample_results, "1_cluster_plots")
  dir.create(sample_dir, recursive = TRUE)
  dir.create(de_dir, recursive = TRUE)
  dir.create(cluster_dir, recursive = TRUE)

  cell_path <- file.path(sample_dir, "Cells.csv")
  writeLines(c("cell_name,sample,cell_type", "cell_1,Sample_A,T cell"), cell_path)
  writeLines("marker,cluster", file.path(de_dir, "all_marker_matches.csv"))
  writeBin(as.raw(1:12), file.path(de_dir, "score_plot.png"))
  resolution <- "0.5"
  cluster_plot <- file.path(
    cluster_dir, paste0("clusters_plot_", sample_name, "_res_", resolution, ".png")
  )
  writeBin(as.raw(20:31), cluster_plot)

  selected_config_path <- file.path(dataset_dir, "selected_config.yaml")
  selected_config <- list(resolutions = stats::setNames(list(resolution), sample_name))
  yaml::write_yaml(selected_config, selected_config_path)

  state <- new_pipeline_state(
    basename(dataset_dir), sample_name,
    as.POSIXct("2026-10-28 08:00:00", tz = "UTC")
  )
  state <- transition_pipeline_step(
    state, "standardization", "completed", force = TRUE
  )
  for (step in c("clustering", "resolution", "differential_expression", "annotation")) {
    state <- transition_pipeline_step(state, step, "completed", sample_name, force = TRUE)
  }
  state <- transition_pipeline_step(
    state,
    "cna_configuration",
    "skipped",
    sample_name,
    reason = "CNA was explicitly omitted by the user.",
    details = list(omitted_by_user = TRUE),
    force = TRUE
  )
  state_path <- file.path(dataset_dir, "pipeline_state.yaml")
  state <- save_pipeline_state_at_path(state, state_path)

  cache_save_data(
    data.frame(cell_name = "cell_1", value = 1),
    paste0("cells_", sample_name, "_res_", resolution, ".qs2"),
    dataset_dir,
    producer = "test-f16"
  )
  storage <- save_dataset_storage_state_atomic(
    new_dataset_storage_state(basename(dataset_dir)), dataset_dir
  )
  paths_list <- list(
    sample_dir_paths = sample_dir,
    cell_file_paths = cell_path
  )
  readiness <- dataset_cleanup_readiness(
    state,
    paths_list,
    selected_config,
    selected_config_path,
    results_dir,
    dataset_dir
  )
  list(
    root = root,
    dataset_dir = dataset_dir,
    results_dir = results_dir,
    sample_name = sample_name,
    paths_list = paths_list,
    selected_config = selected_config,
    selected_config_path = selected_config_path,
    state = state,
    state_path = state_path,
    storage = storage,
    readiness = readiness,
    retained = c(cell_path, cluster_plot, file.path(de_dir, "all_marker_matches.csv"))
  )
}


test_that("F16 inventory handles absent and empty caches before clustering", {
  dataset_dir <- withr::local_tempdir()
  absent <- dataset_cache_inventory(dataset_dir)
  dir.create(file.path(dataset_dir, "cache"))
  empty <- dataset_cache_inventory(dataset_dir)

  expect_identical(empty, absent)
  expect_identical(empty$file_count, 0L)
  expect_equal(empty$size_bytes, 0)
  expect_length(empty$unknown, 0L)
  expect_identical(empty$files$relative_path, character())

  state <- new_pipeline_state("New_Dataset", "Sample_A")
  state <- transition_pipeline_step(state, "standardization", "completed", force = TRUE)
  readiness <- dataset_cleanup_readiness(
    state,
    list(
      sample_dir_paths = file.path(dataset_dir, "processed", "Sample_A"),
      cell_file_paths = file.path(dataset_dir, "processed", "Sample_A", "Cells.csv")
    ),
    list(resolutions = list()),
    file.path(dataset_dir, "selected_config.yaml"),
    file.path(dataset_dir, "results"),
    dataset_dir
  )
  expect_false(readiness$ready)
  expect_true("The dataset cache is already empty." %in% readiness$reasons)
  expect_true("Sample_A: clustering is not_started." %in% readiness$reasons)
})

test_that("F16 readiness accepts an explicit CNA omission and inventories only known cache files", {
  workspace <- make_f16_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)

  expect_true(workspace$readiness$ready)
  expect_gt(workspace$readiness$cache$file_count, 0L)
  expect_gt(workspace$readiness$cache$size_bytes, 0)
  expect_length(workspace$readiness$cache$unknown, 0L)

  state <- transition_pipeline_step(
    workspace$state,
    "cna_configuration",
    "skipped",
    workspace$sample_name,
    reason = "Skipped without an explicit user decision.",
    details = list(omitted_by_user = FALSE),
    force = TRUE
  )
  blocked <- dataset_cleanup_readiness(
    state,
    workspace$paths_list,
    workspace$selected_config,
    workspace$selected_config_path,
    workspace$results_dir,
    workspace$dataset_dir
  )
  expect_false(blocked$ready)
  expect_true(any(grepl("explicit omission", blocked$reasons, fixed = TRUE)))

  dir.create(file.path(workspace$dataset_dir, "cache", "unexpected"))
  writeLines("do not delete", file.path(workspace$dataset_dir, "cache", "unexpected", "file.txt"))
  blocked_unknown <- dataset_cleanup_readiness(
    workspace$state,
    workspace$paths_list,
    workspace$selected_config,
    workspace$selected_config_path,
    workspace$results_dir,
    workspace$dataset_dir
  )
  expect_false(blocked_unknown$ready)
  expect_true(any(grepl("unrecognized entries", blocked_unknown$reasons, fixed = TRUE)))
})


test_that("F16 completed CNA allows optional exports and warns before cleanup", {
  workspace <- make_f16_workspace("Sample_CNA")
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)
  state <- transition_pipeline_step(
    workspace$state,
    "cna_configuration",
    "completed",
    workspace$sample_name,
    force = TRUE
  )
  for (step in c(
    "cna_compute", "cna_cluster_selection", "cna_signal_correlation",
    "cna_thresholds", "cna_assignment"
  )) {
    state <- transition_pipeline_step(state, step, "completed", workspace$sample_name, force = TRUE)
  }
  cna_dir <- file.path(workspace$results_dir, workspace$sample_name, "3_cna_plots")
  dir.create(cna_dir, recursive = TRUE)
  writeBin(
    as.raw(1:8),
    file.path(cna_dir, paste0("cna_summary_heatmap_", workspace$sample_name, ".png"))
  )
  writeBin(
    as.raw(9:16),
    file.path(cna_dir, paste0("cna_umap_assigned_", workspace$sample_name, ".png"))
  )

  without_export <- dataset_cleanup_readiness(
    state,
    workspace$paths_list,
    workspace$selected_config,
    workspace$selected_config_path,
    workspace$results_dir,
    workspace$dataset_dir
  )
  expect_true(without_export$ready)
  expect_identical(without_export$optional_export_samples, workspace$sample_name)
  expect_match(without_export$warnings, "recompute CNA", fixed = TRUE)

  matrix <- data.table::data.table(
    gene = c("GENE1", "GENE2"),
    chr = c("01", "02"),
    start_pos = c(100L, 200L),
    cell_1 = c(-0.1, 0.2)
  )
  cache_save_data(
    matrix,
    paste0("cna_matrix_", workspace$sample_name, ".qs2"),
    workspace$dataset_dir,
    producer = "test-f16"
  )
  export <- export_cna_values_table(
    workspace$sample_name, workspace$dataset_dir, workspace$results_dir
  )
  with_export <- dataset_cleanup_readiness(
    state,
    workspace$paths_list,
    workspace$selected_config,
    workspace$selected_config_path,
    workspace$results_dir,
    workspace$dataset_dir
  )
  expect_true(with_export$ready)
  expect_length(with_export$warnings, 0L)
  expect_length(with_export$optional_export_samples, 0L)

  Sys.setFileTime(export$paths$csv, file.info(export$paths$csv)$mtime + 2)
  outdated <- dataset_cleanup_readiness(
    state,
    workspace$paths_list,
    workspace$selected_config,
    workspace$selected_config_path,
    workspace$results_dir,
    workspace$dataset_dir
  )
  expect_true(outdated$ready)
  expect_identical(outdated$optional_export_samples, workspace$sample_name)
  expect_match(outdated$warnings, "recompute CNA", fixed = TRUE)
  expect_true(all(c(export$paths$csv, export$paths$metadata) %in% outdated$retained_outputs$path))

  # Missing optional exports do not prevent the real archive lifecycle. Existing
  # (even outdated) exports remain retained and audited rather than deleted.
  before <- unname(tools::md5sum(c(export$paths$csv, export$paths$metadata)))
  archived <- archive_dataset_cache(workspace$dataset_dir, state, workspace$storage, outdated)
  expect_identical(archived$status, "archived")
  expect_identical(unname(tools::md5sum(c(export$paths$csv, export$paths$metadata))), before)
  expect_identical(unlist(archived$details$cleanup$optional_export_samples), workspace$sample_name)
  expect_true(dataset_archive_output_audit(archived, workspace$dataset_dir)$intact)
})


test_that("F16 archive removes only caches and preserves scientific state and durable outputs", {
  workspace <- make_f16_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)
  state_before <- serialize(workspace$state, NULL)
  checksums_before <- tools::md5sum(workspace$retained)

  archived <- archive_dataset_cache(
    workspace$dataset_dir,
    workspace$state,
    workspace$storage,
    workspace$readiness,
    timestamp = as.POSIXct("2026-10-28 09:00:00", tz = "UTC")
  )

  expect_identical(archived$status, "archived")
  expect_true(archived$details$cache_retired)
  expect_false(archived$details$deletion_pending)
  expect_false(dir.exists(file.path(workspace$dataset_dir, "cache")))
  expect_gt(archived$details$recovered_bytes, 0)
  expect_identical(serialize(workspace$state, NULL), state_before)
  expect_identical(unname(tools::md5sum(workspace$retained)), unname(checksums_before))
  expect_true(all(file.exists(workspace$retained)))
  expect_identical(
    load_dataset_storage_state(workspace$dataset_dir, basename(workspace$dataset_dir))$status,
    "archived"
  )
  audit <- dataset_archive_output_audit(archived, workspace$dataset_dir)
  expect_true(audit$applicable)
  expect_true(audit$intact)
  expect_gt(audit$checked, 0L)
  retained_manifest <- archived$details$cleanup$retained_outputs
  expect_true(all(!grepl("^[A-Za-z]:|^/", vapply(retained_manifest, `[[`, character(1), "path"))))

  expect_true(file.remove(workspace$retained[[1]]))
  damaged <- dataset_archive_output_audit(archived, workspace$dataset_dir)
  expect_false(damaged$intact)
  expect_true(any(grepl("retained output is missing", damaged$issues, fixed = TRUE)))
})


test_that("F16 refuses a cache that changed after the user reviewed cleanup", {
  workspace <- make_f16_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)
  cache_save_data(
    data.frame(value = 2),
    "new_after_review.qs2",
    workspace$dataset_dir,
    producer = "test-f16"
  )

  expect_error(
    archive_dataset_cache(
      workspace$dataset_dir,
      workspace$state,
      workspace$storage,
      workspace$readiness
    ),
    "cache changed after cleanup review",
    fixed = TRUE
  )
  expect_true(dir.exists(file.path(workspace$dataset_dir, "cache")))
  expect_identical(load_dataset_storage_state(workspace$dataset_dir)$status, "active")
})


test_that("F16 failed retirement is recoverable without deleting the active cache", {
  workspace <- make_f16_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)

  expect_error(
    archive_dataset_cache(
      workspace$dataset_dir,
      workspace$state,
      workspace$storage,
      workspace$readiness,
      rename_directory = function(from, to) FALSE
    ),
    "Could not retire",
    fixed = TRUE
  )
  persisted <- load_dataset_storage_state(workspace$dataset_dir)
  expect_identical(persisted$status, "cleanup_failed")
  expect_false(persisted$details$cache_retired)
  expect_true(dir.exists(file.path(workspace$dataset_dir, "cache")))
})


test_that("F16 deletion failure remains read-only and can be retried", {
  workspace <- make_f16_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)

  pending <- archive_dataset_cache(
    workspace$dataset_dir,
    workspace$state,
    workspace$storage,
    workspace$readiness,
    delete_directory = function(path) FALSE
  )
  expect_identical(pending$status, "cleanup_failed")
  expect_true(dataset_storage_cache_is_retired(pending))
  expect_true(pending$details$deletion_pending)
  expect_false(dir.exists(file.path(workspace$dataset_dir, "cache")))
  expect_true(dir.exists(pending$details$retired_path))

  archived <- retry_dataset_cache_deletion(workspace$dataset_dir, pending)
  expect_identical(archived$status, "archived")
  expect_false(archived$details$deletion_pending)
  expect_false(dir.exists(pending$details$retired_path))
})


test_that("F16 state-write failure after rename rolls the cache back", {
  workspace <- make_f16_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)
  calls <- 0L
  injected_save <- function(state, dataset_dir_path, state_filename, timestamp) {
    calls <<- calls + 1L
    if (calls == 2L) stop("injected storage write failure")
    save_dataset_storage_state_atomic(state, dataset_dir_path, state_filename, timestamp)
  }

  expect_error(
    archive_dataset_cache(
      workspace$dataset_dir,
      workspace$state,
      workspace$storage,
      workspace$readiness,
      save_storage = injected_save
    ),
    "rolled back",
    fixed = TRUE
  )
  persisted <- load_dataset_storage_state(workspace$dataset_dir)
  expect_identical(persisted$status, "cleanup_failed")
  expect_false(persisted$details$cache_retired)
  expect_true(dir.exists(file.path(workspace$dataset_dir, "cache")))
  expect_false(dir.exists(persisted$details$retired_path))
})


test_that("F16 records a retired cache when checkpoint and rollback both fail", {
  workspace <- make_f16_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)
  save_calls <- 0L
  injected_save <- function(state, dataset_dir_path, state_filename, timestamp) {
    save_calls <<- save_calls + 1L
    if (save_calls == 2L) stop("injected checkpoint failure")
    save_dataset_storage_state_atomic(state, dataset_dir_path, state_filename, timestamp)
  }
  rename_calls <- 0L
  injected_rename <- function(from, to) {
    rename_calls <<- rename_calls + 1L
    if (rename_calls == 2L) return(FALSE)
    file.rename(from, to)
  }

  expect_error(
    archive_dataset_cache(
      workspace$dataset_dir,
      workspace$state,
      workspace$storage,
      workspace$readiness,
      rename_directory = injected_rename,
      save_storage = injected_save
    ),
    "could not be restored",
    fixed = TRUE
  )
  persisted <- load_dataset_storage_state(workspace$dataset_dir)
  expect_identical(persisted$status, "cleanup_failed")
  expect_true(persisted$details$cache_retired)
  expect_true(persisted$details$deletion_pending)
  expect_false(dir.exists(file.path(workspace$dataset_dir, "cache")))
  expect_true(dir.exists(persisted$details$retired_path))
})


test_that("F16 reload reconciliation distinguishes pre- and post-retirement interruptions", {
  workspace <- make_f16_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)
  cleaning <- transition_dataset_storage_state(
    workspace$storage,
    "cleaning",
    details = list(
      retired_path = file.path(workspace$dataset_dir, ".cache-retired-test"),
      cache_retired = FALSE,
      deletion_pending = FALSE
    )
  )
  before <- reconcile_interrupted_dataset_storage(cleaning, workspace$dataset_dir)
  expect_identical(before$status, "cleanup_failed")
  expect_false(before$details$cache_retired)

  expect_true(file.rename(
    file.path(workspace$dataset_dir, "cache"), cleaning$details$retired_path
  ))
  after <- reconcile_interrupted_dataset_storage(cleaning, workspace$dataset_dir)
  expect_identical(after$status, "cleanup_failed")
  expect_true(after$details$cache_retired)
  expect_true(after$details$deletion_pending)
})


test_that("F16 explicit reopen preserves results and makes cache-dependent work stale", {
  workspace <- make_f16_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE, force = TRUE), add = TRUE)
  checksums_before <- tools::md5sum(workspace$retained)
  archived <- archive_dataset_cache(
    workspace$dataset_dir,
    workspace$state,
    workspace$storage,
    workspace$readiness
  )

  reopened <- reopen_archived_dataset(
    workspace$dataset_dir,
    workspace$state,
    workspace$state_path,
    archived
  )
  expect_identical(reopened$storage_state$status, "active")
  expect_false(dataset_storage_cache_is_retired(reopened$storage_state))
  expect_true(dir.exists(file.path(workspace$dataset_dir, "cache")))
  expect_identical(
    get_pipeline_step(reopened$pipeline_state, "standardization")$status,
    "completed"
  )
  statuses <- vapply(
    PIPELINE_SAMPLE_STEPS,
    function(step) get_pipeline_step(reopened$pipeline_state, step, workspace$sample_name)$status,
    character(1)
  )
  expect_true(all(statuses[c("clustering", "resolution", "differential_expression", "annotation", "cna_configuration")] == "stale"))
  expect_true(all(statuses[setdiff(names(statuses), c("clustering", "resolution", "differential_expression", "annotation", "cna_configuration"))] == "not_started"))
  expect_identical(unname(tools::md5sum(workspace$retained)), unname(checksums_before))
})


test_that("F16 Start Menu exposes cleanup status, confirmation, retry, and reopen controls", {
  sys.source(file.path(app_dir_f16, "app/ui/dashboard_ui.R"), envir = environment())
  active <- new_dataset_storage_state("dataset")
  readiness <- list(
    ready = TRUE,
    reasons = character(),
    cache = list(size_bytes = 2048, file_count = 2L)
  )
  active_html <- as.character(dataset_storage_card_ui(active, readiness))
  expect_match(active_html, "btn_review_dataset_cleanup", fixed = TRUE)
  expect_match(active_html, "2 KB", fixed = TRUE)

  archived <- transition_dataset_storage_state(
    active, "archived", details = list(cache_retired = TRUE, recovered_bytes = 2048)
  )
  archived_html <- as.character(dataset_storage_card_ui(archived, NULL))
  expect_match(archived_html, "btn_reopen_dataset", fixed = TRUE)
  expect_match(archived_html, "read-only archive mode", fixed = TRUE)

  server_text <- paste(readLines(
    file.path(app_dir_f16, "app/server/storage_server.R"), warn = FALSE
  ), collapse = "\n")
  expect_match(server_text, "dataset_cleanup_confirmation", fixed = TRUE)
  expect_match(server_text, "btn_retry_dataset_cleanup", fixed = TRUE)
  expect_match(server_text, "dataset_reopen_confirmation", fixed = TRUE)
  expect_match(server_text, "archive_dataset_cache", fixed = TRUE)
  expect_match(server_text, "reopen_archived_dataset", fixed = TRUE)

  app_text <- paste(readLines(file.path(app_dir_f16, "app.R"), warn = FALSE), collapse = "\n")
  expect_match(app_text, '"app/server/storage_server.R"', fixed = TRUE)
})

make_optional_export_cleanup_fixture <- function(.local_envir = parent.frame()) {
  workspace <- make_f16_workspace()
  withr::defer(unlink(workspace$root, recursive = TRUE, force = TRUE), envir = .local_envir)
  for (step in c("cna_configuration", "cna_compute", "cna_cluster_selection", "cna_signal_correlation",
    "cna_thresholds", "cna_assignment")) {
    workspace$state <- transition_pipeline_step(workspace$state, step, "completed", workspace$sample_name, force = TRUE)
  }
  workspace$state <- save_pipeline_state_at_path(workspace$state, workspace$state_path)
  plot_dir <- file.path(workspace$results_dir, workspace$sample_name, "3_cna_plots")
  dir.create(plot_dir)
  for (prefix in c("cna_summary_heatmap_", "cna_umap_assigned_")) {
    writeBin(as.raw(1:8), file.path(plot_dir, paste0(prefix, workspace$sample_name, ".png")))
  }
  workspace
}

test_that("optional-export cleanup warns in its modal and archives a finished sample without a CSV", {
  workspace <- make_optional_export_cleanup_fixture()
  env <- new.env(parent = environment(dataset_cleanup_readiness))
  sys.source(file.path(app_dir_f16, "app/state.R"), envir = env)
  sys.source(file.path(app_dir_f16, "app/ui/dashboard_ui.R"), envir = env)
  sys.source(file.path(app_dir_f16, "app/server/storage_server.R"), envir = env)
  env$nav_hide <- function(...) invisible(NULL)
  env$record_state_event <- function(...) invisible(NULL)
  modal <- NULL
  env$showModal <- function(ui, ...) modal <<- as.character(ui)
  rv <- env$create_app_state(list())
  rv$dataset_dir_path <- workspace$dataset_dir
  rv$results_dir_path <- workspace$results_dir
  rv$paths_list <- workspace$paths_list
  rv$pipeline_state <- workspace$state
  rv$storage_state <- workspace$storage
  rv$selected_config_path <- workspace$selected_config_path
  rv$live_selected_config <- workspace$selected_config
  server <- function(input, output, session) env$register_storage_server(input, output, session, rv, list())
  shiny::testServer(server, {
    session$setInputs(main_nav = "menu_tab", btn_review_dataset_cleanup = 1)
    expect_match(modal, "Sample_A", fixed = TRUE)
    expect_match(modal, "recompute CNA", fixed = TRUE)
    expect_match(modal, "Export is optional", fixed = TRUE)
    expect_true(dir.exists(file.path(workspace$dataset_dir, "cache")))
    session$setInputs(dataset_cleanup_confirmation = "dataset", btn_confirm_dataset_cleanup = 1)
    expect_identical(rv$storage_state$status, "archived")
    expect_false(dir.exists(file.path(workspace$dataset_dir, "cache")))
    expect_identical(get_pipeline_step(rv$pipeline_state, "cna_assignment", "Sample_A")$status, "completed")
    expect_identical(unlist(rv$storage_state$details$cleanup$optional_export_samples), "Sample_A")
    expect_true(all(file.exists(workspace$retained)))
    expect_true(dataset_archive_output_audit(rv$storage_state, workspace$dataset_dir)$intact)
  })
})

test_that("cleanup requires a fresh warning if an export disappears after review", {
  workspace <- make_optional_export_cleanup_fixture()
  matrix <- data.table::data.table(gene = "G", chr = "01", start_pos = 1L, cell_1 = 0.1)
  cache_save_data(matrix, "cna_matrix_Sample_A.qs2", workspace$dataset_dir)
  export <- export_cna_values_table("Sample_A", workspace$dataset_dir, workspace$results_dir)
  env <- new.env(parent = environment(dataset_cleanup_readiness))
  sys.source(file.path(app_dir_f16, "app/state.R"), envir = env)
  sys.source(file.path(app_dir_f16, "app/ui/dashboard_ui.R"), envir = env)
  sys.source(file.path(app_dir_f16, "app/server/storage_server.R"), envir = env)
  env$nav_hide <- env$record_state_event <- function(...) invisible(NULL)
  env$showModal <- function(...) invisible(NULL)
  notifications <- character()
  env$showNotification <- function(ui, ...) { notifications <<- c(notifications, ui); "test" }
  rv <- env$create_app_state(list())
  rv$dataset_dir_path <- workspace$dataset_dir
  rv$results_dir_path <- workspace$results_dir
  rv$paths_list <- workspace$paths_list
  rv$pipeline_state <- workspace$state
  rv$storage_state <- workspace$storage
  rv$selected_config_path <- workspace$selected_config_path
  rv$live_selected_config <- workspace$selected_config
  server <- function(input, output, session) env$register_storage_server(input, output, session, rv, list())
  shiny::testServer(server, {
    session$setInputs(main_nav = "menu_tab", btn_review_dataset_cleanup = 1)
    file.remove(export$paths$csv)
    session$setInputs(dataset_cleanup_confirmation = "dataset", btn_confirm_dataset_cleanup = 1)
    expect_identical(rv$storage_state$status, "active")
    expect_true(dir.exists(file.path(workspace$dataset_dir, "cache")))
    expect_true(any(grepl("CNA export availability changed", notifications, fixed = TRUE)))
  })
})

test_that("storage state preserves large output sizes and safely audits older rounded records", {
  dataset_dir <- withr::local_tempdir()
  path <- file.path(dataset_dir, "large-output.csv.gz")
  connection <- file(path, "wb")
  seek(connection, 100000002, origin = "start", rw = "write")
  writeBin(as.raw(0), connection)
  close(connection)
  checksum <- .cache_md5(path)
  storage <- transition_dataset_storage_state(new_dataset_storage_state("Large"), "archived",
    details = list(recovered_bytes = 635679743,
      cleanup = list(cache_size_bytes = 242739668, retained_outputs = list(list(
        path = basename(path), label = "Optional CNA values CSV", sample = "Sample",
        size_bytes = file.info(path)$size, checksum = checksum)))))
  persisted <- save_dataset_storage_state_atomic(storage, dataset_dir)
  expect_equal(persisted$details$cleanup$retained_outputs[[1]]$size_bytes, 100000003)
  expect_equal(persisted$details$cleanup$cache_size_bytes, 242739668)
  expect_equal(persisted$details$recovered_bytes, 635679743)
  loaded <- load_dataset_storage_state(dataset_dir, "Large", recover = FALSE)
  expect_true(dataset_archive_output_audit(loaded, dataset_dir)$intact)
  expect_true(dataset_archive_output_audit(loaded, dataset_dir, verify_checksums = TRUE)$intact)

  state_path <- dataset_storage_state_paths(dataset_dir)$primary
  yaml::write_yaml(loaded, state_path, precision = 7)
  legacy <- load_dataset_storage_state(dataset_dir, "Large", recover = FALSE)
  expect_equal(legacy$details$cleanup$retained_outputs[[1]]$size_bytes, 100000000)
  before <- unname(tools::md5sum(state_path))
  expect_true(dataset_archive_output_audit(legacy, dataset_dir)$intact)
  expect_true(dataset_archive_output_audit(legacy, dataset_dir, verify_checksums = TRUE)$intact)
  expect_identical(unname(tools::md5sum(state_path)), before)

  # A same-size content edit still matches the rounded byte count, but must
  # fail checksum verification. Deleted outputs must also remain errors.
  connection <- file(path, "r+b")
  writeBin(as.raw(1), connection)
  close(connection)
  expect_false(dataset_archive_output_audit(legacy, dataset_dir)$intact)
  expect_false(dataset_archive_output_audit(loaded, dataset_dir, verify_checksums = TRUE)$intact)
  file.remove(path)
  missing <- dataset_archive_output_audit(legacy, dataset_dir)
  expect_false(missing$intact)
  expect_match(missing$issues, "retained output is missing", fixed = TRUE)
})
