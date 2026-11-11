make_p03_inputs <- function(root, matrix_name = "Exp_data_UMIcounts.mtx") {
  source <- file.path(root, "prepared inputs")
  parent <- file.path(root, "workspaces")
  dir.create(source)
  dir.create(parent)
  config <- yaml::read_yaml(testthat::test_path("..", "..", "general_config.yaml"))
  samples <- build_samples(c("002", "001"))
  samples$patient <- c("0007", "0008")
  samples$technology <- "Synthetic"
  samples$n_cells <- 8L
  for (sample in samples$sample) {
    write_mini_sample(source, sample, n_genes = 12, n_cells = 8,
      cell_prefix = paste0(sample, "_"),
      std_names = list(expmat = matrix_name, genes = "Genes.txt", cells = "Cells.csv"))
  }
  data.table::fwrite(samples, file.path(source, "Samples.csv"))
  list(source = source, parent = parent, config = config,
       template = testthat::test_path("..", "..", "templates", "dataset_config_template.yaml"))
}

p03_import <- function(fixture, name = "Imported", ...) {
  import_prepared_dataset(fixture$source, fixture$parent, name,
    fixture$config, fixture$template, ...)
}

test_that("P03 imports independent complete workspaces with ready analysis state", {
  for (scale in c("UMIcounts", "TPM", "CPM")) {
    fixture <- make_p03_inputs(withr::local_tempdir(), paste0("Exp_data_", scale, ".mtx"))
    original_files <- list.files(fixture$source, recursive = TRUE, full.names = TRUE)
    original_hashes <- tools::md5sum(original_files)
    imported <- p03_import(fixture)
    processed <- file.path(imported$path, "processed_data")
    copied_files <- file.path(processed, as.character(fs::path_rel(original_files, start = fixture$source)))
    expect_identical(unname(tools::md5sum(copied_files)), unname(original_hashes))
    expect_identical(tools::md5sum(original_files), original_hashes)
    expect_identical(imported$samples$sample, c("002", "001"))
    expect_identical(imported$samples$patient, c("0007", "0008"))
    expect_identical(basename(dataset_workspace_directories(fixture$parent)), "Imported")
    expect_false(any(file.exists(file.path(imported$path,
      c("data", "standardize.R", "samples_config.yaml", "STANDARDIZATION_CHECKLIST.md")))))
    expect_true(all(dir.exists(file.path(imported$path, c("cache", "logs", "results")))))
    ds_config <- yaml::read_yaml(file.path(imported$path, "dataset_config.yaml"))
    expect_identical(ds_config$project_info$dataset_id, "Imported")
    expect_identical(ds_config$project_info$technology, "Synthetic")
    expect_identical(ds_config$std_names$expmat, paste0("Exp_data_", scale, ".mtx"))
    expect_null(ds_config$raw_files)
    state <- load_pipeline_state(imported$path)
    readiness <- get_pipeline_step(state, "standardization")
    expect_identical(readiness$status, "completed")
    expect_identical(readiness$details$validation_scope, "structure_only")
    expect_identical(readiness$details$provenance, "prepared_data_import")
    expect_true(pipeline_step_readiness(state, "clustering", "002")$ready)
    expect_true(all(vapply(state$samples$`002`, function(step) identical(step$status, "not_started"), logical(1))))
    expect_identical(load_dataset_storage_state(imported$path)$status, "active")
    selected <- yaml::read_yaml(file.path(imported$path, "selected_config.yaml"))
    expect_setequal(names(selected$resolutions), c("002", "001"))
    expect_true(file.exists(file.path(imported$path, "logs", "pipeline_events.jsonl")))
    # Ordinary edits to copied cell metadata must not change the source input.
    cat("\nworkspace-only edit", file = file.path(processed, "002", "Cells.csv"), append = TRUE)
    expect_identical(tools::md5sum(original_files), original_hashes)
  }
})

test_that("P03 reports real byte progress while staging remains undiscoverable", {
  fixture <- make_p03_inputs(withr::local_tempdir())
  payload <- file.path(fixture$source, "extra_payload.bin")
  writeBin(raw(17L * 1024L * 1024L), payload)
  progress_bytes <- numeric()
  total_bytes <- numeric()
  imported <- p03_import(fixture, progress = function(copied, total, path) {
    expect_length(dataset_workspace_directories(fixture$parent), 0L)
    expect_false(file.exists(file.path(fixture$parent, "Imported")))
    progress_bytes <<- c(progress_bytes, copied)
    total_bytes <<- c(total_bytes, total)
  })
  expect_true(all(diff(progress_bytes) >= 0))
  expect_true(length(progress_bytes) > length(list.files(fixture$source, recursive = TRUE)))
  expect_equal(tail(progress_bytes, 1), imported$copied_bytes)
  expect_equal(unique(total_bytes), imported$copied_bytes)
  expect_identical(unname(tools::md5sum(payload)),
    unname(tools::md5sum(file.path(imported$path, "processed_data", "extra_payload.bin"))))
})

test_that("P03 failed copies roll back only owned staging and never publish a partial workspace", {
  fixture <- make_p03_inputs(withr::local_tempdir())
  sentinel <- file.path(fixture$parent, "unrelated.txt")
  writeLines("preserve this", sentinel)
  source_files <- list.files(fixture$source, recursive = TRUE, full.names = TRUE)
  hashes <- tools::md5sum(c(source_files, sentinel))
  expect_error(p03_import(fixture, copy_file = function(source, destination, ...) {
    writeBin(as.raw(1:3), destination)
    stop("synthetic copy interruption")
  }), "synthetic copy interruption")
  expect_identical(list.files(fixture$parent, all.files = TRUE, no.. = TRUE), "unrelated.txt")
  expect_identical(tools::md5sum(c(source_files, sentinel)), hashes)
  expect_error(p03_import(fixture, copy_file = function(...) 0), "Copy failed")
  expect_identical(list.files(fixture$parent, all.files = TRUE, no.. = TRUE), "unrelated.txt")
})

test_that("P03 rejects overwrite, overlap, unsafe names and invalid inputs before publication", {
  fixture <- make_p03_inputs(withr::local_tempdir())
  dir.create(file.path(fixture$parent, "Existing"))
  sentinel <- file.path(fixture$parent, "Existing", "keep.txt")
  writeLines("keep", sentinel)
  hash <- tools::md5sum(sentinel)
  expect_error(p03_import(fixture, "Existing"), "already exists")
  expect_identical(tools::md5sum(sentinel), hash)
  expect_error(p03_import(fixture, "../outside"), "path separators")
  expect_error(p03_import(fixture, "Alias."), "must not end with a period")
  expect_error(p03_import(fixture, "CON.study"), "Windows-reserved")
  expect_error(p03_import(fixture, ".prepared-import-reserved"), "reserved")
  expect_error(import_prepared_dataset(fixture$source, fixture$source, "Nested",
    fixture$config, fixture$template), "must not overlap")
  expect_false(dir.exists(file.path(fixture$source, "Nested")))
  unlink(file.path(fixture$source, "002", c("Cells.csv", "Genes.txt")))
  expect_error(p03_import(fixture), "Cells.csv")
  expect_error(p03_import(fixture), "Genes.txt")
  expect_identical(basename(dataset_workspace_directories(fixture$parent)), "Existing")
})

test_that("P03 stale interrupted staging is not a discoverable dataset", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, ".prepared-import-interrupted"))
  dir.create(file.path(root, "Existing"))
  expect_identical(basename(dataset_workspace_directories(root)), "Existing")
})

make_p03_server_fixture <- function(root) {
  fixture <- make_p03_inputs(root)
  fixture$config$paths$datasets_dir <- fixture$parent
  app <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  env <- new.env(parent = environment())
  env$notifications <- character()
  env$modals <- character()
  env$text_updates <- list()
  env$nav_select <- env$nav_show <- env$nav_hide <- function(...) invisible(NULL)
  env$updateNavbarPage <- env$removeModal <- env$removeNotification <- function(...) invisible(NULL)
  env$showNotification <- function(ui, ...) {
    env$notifications <- c(env$notifications, as.character(ui)); "notification"
  }
  env$showModal <- function(ui, ...) { env$modals <- c(env$modals, as.character(ui)) }
  env$updateTextInput <- function(session, inputId, value, ...) {
    env$text_updates[[inputId]] <- value
    shiny::updateTextInput(session, inputId, value = value, ...)
  }
  for (component in c("app/state.R", "app/ui/dataset_ui.R", "app/server/dataset_server.R")) {
    sys.source(file.path(app, component), env)
  }
  env$context <- list(config = fixture$config,
    paths = list(datasets_dir = fixture$parent, templates_dir = dirname(fixture$template)),
    resources = list(marker_genes = data.table::data.table(cell_type = "T_cell", symbol = "GENE01", combined = 2),
      housekeeping_genes = "GENE02", mt_genes = "GENE03", gene_positions = data.table::data.table()),
    available_datasets = character())
  env$state <- env$create_app_state(list())
  env$fixture <- fixture
  env$server <- function(input, output, session) {
    env$register_dataset_server(input, output, session, env$state, env$context)
  }
  env
}

test_that("P03 creation opens external workspaces immediately and retains session reload access", {
  env <- make_p03_server_fixture(withr::local_tempdir())
  external <- withr::local_tempdir(pattern = "external workspaces ")
  state <- env$state
  shiny::testServer(env$server, {
    session$setInputs(btn_create_dataset_ui = 1)
    expect_match(tail(env$modals, 1), "new_ds_source", fixed = TRUE)
    expect_false(grepl("new_ds_tech", tail(env$modals, 1), fixed = TRUE))
    session$setInputs(new_ds_name = "External", new_ds_source = env$fixture$source,
      new_ds_location = external, btn_confirm_create_ds = 1)
    expect_identical(state$dataset_dir_path, normalizePath(file.path(external, "External"), winslash = "/"))
    expect_identical(state$sample_metadata$sample, c("002", "001"))
    expect_true(pipeline_step_readiness(state$pipeline_state, "clustering", "002")$ready)
    expect_identical(state$storage_state$status, "active")
    expect_length(state$active_actions, 0L)
    expect_length(state$open_confirmations, 0L)
    snapshot <- tools::md5sum(list.files(state$dataset_dir_path, recursive = TRUE, full.names = TRUE))
    # Duplicate delivery after publication cannot import again or change state.
    session$setInputs(btn_confirm_create_ds = 2)
    expect_identical(tools::md5sum(names(snapshot)), snapshot)
    session$setInputs(btn_change_dataset = 1)
    expect_null(state$sample_metadata)
    session$setInputs(dataset_choice = "External", btn_load_dataset = 1)
    expect_identical(state$dataset_dir_path, normalizePath(file.path(external, "External"), winslash = "/"))
    expect_identical(state$sample_metadata$sample, c("002", "001"))
    expect_length(dataset_workspace_directories(env$fixture$parent), 0L)
  })
})

test_that("P03 cancellation, active-action guards, and validation retry preserve the draft", {
  env <- make_p03_server_fixture(withr::local_tempdir())
  state <- env$state
  shiny::testServer(env$server, {
    state$active_actions <- "clustering_run"
    session$setInputs(btn_create_dataset_ui = 1)
    expect_length(env$modals, 0L)
    state$active_actions <- character()
    state$annotation_dirty <- TRUE
    session$setInputs(btn_create_dataset_ui = 2)
    expect_length(env$modals, 0L)
    state$annotation_dirty <- FALSE
    session$setInputs(btn_create_dataset_ui = 3)
    session$setInputs(new_ds_name = "Cancelled", new_ds_source = env$fixture$source,
      new_ds_location = env$fixture$parent, btn_cancel_create_ds = 1)
    session$setInputs(btn_confirm_create_ds = 1)
    expect_length(dataset_workspace_directories(env$fixture$parent), 0L)
    expect_null(state$dataset_dir_path)
    session$setInputs(btn_create_dataset_ui = 4)
    session$setInputs(new_ds_name = "../Unsafe", btn_confirm_create_ds = 2)
    expect_match(output$dataset_import_report$html, "path separators", fixed = TRUE)
    expect_identical(input$new_ds_source, env$fixture$source)
    expect_length(state$active_actions, 0L)
    session$setInputs(new_ds_name = "Retried", btn_confirm_create_ds = 3)
    expect_identical(basename(state$dataset_dir_path), "Retried")
  })
})

test_that("P03 in-app directory browsing updates only the selected path field", {
  env <- make_p03_server_fixture(withr::local_tempdir())
  shiny::testServer(env$server, {
    session$setInputs(btn_create_dataset_ui = 1, new_ds_name = "Keep this name",
      new_ds_location = env$fixture$parent, new_ds_source = env$fixture$source)
    session$setInputs(btn_browse_dataset_source = 1)
    expect_match(output$dataset_directory_browser$html, "Browse prepared data", fixed = TRUE)
    session$setInputs(btn_dataset_browser_up = 1)
    expect_match(output$dataset_directory_browser$html, "prepared inputs", fixed = TRUE)
    session$setInputs(dataset_browser_child = normalizePath(env$fixture$source, winslash = "/"), btn_dataset_browser_open = 1)
    session$setInputs(btn_dataset_browser_select = 1)
    expect_identical(env$text_updates$new_ds_source, normalizePath(env$fixture$source, winslash = "/"))
    expect_identical(input$new_ds_name, "Keep this name")
    expect_null(env$text_updates$new_ds_location)
    session$setInputs(btn_browse_dataset_parent = 1)
    session$setInputs(dataset_browser_path = env$fixture$source, btn_dataset_browser_go = 1)
    session$setInputs(btn_dataset_browser_select = 2)
    expect_identical(env$text_updates$new_ds_location, normalizePath(env$fixture$source, winslash = "/"))
    session$setInputs(btn_browse_dataset_source = 2, btn_dataset_browser_cancel = 1)
    expect_null(output$dataset_directory_browser)
  })
})
