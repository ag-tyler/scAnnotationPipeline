make_p03_inputs <- function(root, matrix_name = "Exp_data_UMIcounts.mtx",
                            std_names = list(expmat = matrix_name, genes = "Genes.txt",
                                             cells = "Cells.csv", samples = "Samples.csv")) {
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
      std_names = std_names)
  }
  data.table::fwrite(samples, file.path(source, std_names$samples))
  # Each fixture owns its template, matching the requested input names without
  # modifying the repository's defaults or relying on import autodetection.
  template <- yaml::read_yaml(testthat::test_path("..", "..", "templates", "dataset_config_template.yaml"))
  template$std_names <- std_names
  template_dir <- file.path(root, "templates")
  dir.create(template_dir)
  template_path <- file.path(template_dir, "dataset_config_template.yaml")
  yaml::write_yaml(template, template_path)
  list(source = source, parent = parent, config = config,
       template = template_path)
}

p03_import <- function(fixture, name = "Imported", ...) {
  import_prepared_dataset(fixture$source, fixture$parent, name,
    fixture$config, fixture$template, ...)
}

test_that("P03 imports independent complete workspaces with ready analysis state", {
  for (matrix_name in c("expression.mtx", "Exp_data_UMIcounts.mtx", "Exp_data_TPM.mtx", "Exp_data_CPM.mtx")) {
    fixture <- make_p03_inputs(withr::local_tempdir(), matrix_name)
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
    expect_false("technology" %in% names(ds_config$project_info))
    expect_identical(imported$samples$technology, rep("Synthetic", 2))
    expect_identical(ds_config$std_names$expmat, matrix_name)
    expect_null(ds_config$raw_files)
    state <- load_pipeline_state(imported$path)
    readiness <- get_pipeline_step(state, "standardization")
    expect_identical(readiness$status, "completed")
    expect_identical(readiness$details$validation_scope, "structure_only")
    expect_identical(readiness$details$provenance, "prepared_data_import")
    expect_false("expression_type" %in% names(readiness$details))
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

test_that("DC03 import preserves single, mixed, and unknown sample technologies without a dataset summary", {
  for (technologies in list(c("Synthetic", "Synthetic"), c("10x Chromium", "Smart-seq2"),
                           rep(NA_character_, 2))) {
    fixture <- make_p03_inputs(withr::local_tempdir())
    sample_csv <- file.path(fixture$source, "Samples.csv")
    samples <- read_prepared_samples(sample_csv)
    samples$technology <- technologies
    data.table::fwrite(samples, sample_csv, na = "")
    source_hash <- unname(tools::md5sum(sample_csv))
    # Even an older template must not add the obsolete summary to a new dataset.
    template <- yaml::read_yaml(fixture$template)
    template$project_info$technology <- "Obsolete template summary"
    yaml::write_yaml(template, fixture$template)

    imported <- p03_import(fixture)
    saved <- yaml::read_yaml(file.path(imported$path, "dataset_config.yaml"))
    copied_csv <- file.path(imported$path, "processed_data", saved$std_names$samples)
    expect_false("technology" %in% names(saved$project_info))
    expect_identical(imported$samples$technology, technologies)
    expect_identical(read_prepared_samples(copied_csv), samples)
    expect_identical(unname(tools::md5sum(copied_csv)), source_hash)
    expect_identical(unname(tools::md5sum(sample_csv)), source_hash)
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

test_that("dimension mismatches prevent creation before copying starts", {
  fixture <- make_p03_inputs(withr::local_tempdir())
  path <- file.path(fixture$source, "002", "Genes.txt")
  writeLines(readLines(path)[-1L], path)
  cells_path <- file.path(fixture$source, "001", "Cells.csv")
  cells <- data.table::fread(cells_path)
  data.table::fwrite(cells[-1L], cells_path)
  files <- list.files(fixture$source, recursive = TRUE, full.names = TRUE)
  hashes <- tools::md5sum(files)
  copied <- FALSE
  error <- tryCatch(p03_import(fixture, copy_file = function(...) {
    copied <<- TRUE
    stop("Copying must not start")
  }), error = identity)
  expect_s3_class(error, "error")
  expect_match(conditionMessage(error), "Gene entries (11) do not match matrix rows (12)", fixed = TRUE)
  expect_match(conditionMessage(error), "Cell metadata rows (7) do not match matrix columns (8)", fixed = TRUE)
  expect_false(copied)
  expect_length(list.files(fixture$parent, all.files = TRUE, no.. = TRUE), 0L)
  expect_identical(tools::md5sum(files), hashes)
})

test_that("post-copy dimension mismatches roll back staging without publishing a workspace", {
  fixture <- make_p03_inputs(withr::local_tempdir())
  files <- list.files(fixture$source, recursive = TRUE, full.names = TRUE)
  hashes <- tools::md5sum(files)
  changed_copy <- FALSE
  expect_error(p03_import(fixture, copy_file = function(source, destination, copied, total, progress) {
    written <- copy_prepared_input_file(source, destination, copied, total, progress)
    if (basename(source) == "Exp_data_UMIcounts.mtx") {
      bytes <- readBin(destination, "raw", n = file.info(destination)$size)
      altered <- sub("\n12 8 ", "\n13 9 ", rawToChar(bytes), fixed = TRUE)
      stopifnot(nchar(altered, type = "bytes") == length(bytes))
      writeBin(charToRaw(altered), destination)
      changed_copy <<- TRUE
    }
    written
  }), "do not match matrix", fixed = TRUE)
  expect_true(changed_copy)
  expect_length(list.files(fixture$parent, all.files = TRUE, no.. = TRUE), 0L)
  expect_identical(tools::md5sum(files), hashes)
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

test_that("loading an existing dataset blocks gene and cell dimension mismatches", {
  env <- make_p03_server_fixture(withr::local_tempdir())
  imported <- p03_import(env$fixture)
  genes <- file.path(imported$path, "processed_data", "002", "Genes.txt")
  writeLines(readLines(genes)[-1L], genes)
  cells_path <- file.path(imported$path, "processed_data", "001", "Cells.csv")
  data.table::fwrite(data.table::fread(cells_path)[-1L], cells_path)
  hashes <- tools::md5sum(c(genes, cells_path))
  shiny::testServer(env$server, {
    session$setInputs(dataset_choice = "Imported", btn_load_dataset = 1)
    expect_null(env$state$dataset_dir_path)
    expect_null(env$state$sample_metadata)
    expect_match(tail(env$modals, 1), "Gene entries (11) do not match matrix rows (12)", fixed = TRUE)
    expect_match(tail(env$modals, 1), "Cell metadata rows (7) do not match matrix columns (8)", fixed = TRUE)
  })
  expect_identical(tools::md5sum(c(genes, cells_path)), hashes)
})

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

test_that("DC01 configured filenames and non-default settings survive creation and reload", {
  root <- withr::local_tempdir()
  env <- make_p03_server_fixture(root)
  fixture <- env$fixture
  template <- yaml::read_yaml(fixture$template)
  original_names <- template$std_names
  template$std_names <- list(expmat = "expression.mtx", genes = "symbols.txt",
    cells = "cell_metadata.csv", samples = "sample_metadata.csv")
  for (sample in c("002", "001")) {
    for (key in c("expmat", "genes", "cells")) {
      expect_true(file.rename(file.path(fixture$source, sample, original_names[[key]]),
        file.path(fixture$source, sample, template$std_names[[key]])))
    }
  }
  expect_true(file.rename(file.path(fixture$source, original_names$samples),
    file.path(fixture$source, template$std_names$samples)))
  # Creation and loading must not inspect fractions or alternative matrix names.
  for (sample in c("002", "001")) {
    path <- file.path(fixture$source, sample, template$std_names$expmat)
    Matrix::writeMM(Matrix::readMM(path) / 3, path)
    writeLines("unused alternative", file.path(fixture$source, sample, "Exp_data_TPM.mtx"))
  }
  template$params <- list(min_genes = 3, target_sum = 23456, log2_expr_threshold = 0.5,
    max_marker_genes = 7, pca_nv = 2, seed = 8173, resolutions = c(0.25, 0.75),
    umap = list(spread = 1.7, min_dist = 0.35),
    de = list(num_genes = 9, max_match_genes = 5, min_marker_found = 6))
  template$marker_filter_params <- list(
    cell_type = list(min_score = 2.5, min_genes = 1, max_genes = 3),
    cancer_type = list(min_score = 3.5, min_genes = 2, max_genes = 4))
  template$project_info$dataset_id <- "Template identity"
  template$project_info$source_doi <- "10.1234/template-source"
  template$project_info$source_url <- "https://example.org/template-dataset"
  yaml::write_yaml(template, fixture$template)
  source_files <- list.files(fixture$source, recursive = TRUE, full.names = TRUE)
  source_hashes <- tools::md5sum(source_files)
  state <- env$state

  shiny::testServer(env$server, {
    session$setInputs(btn_create_dataset_ui = 1)
    session$setInputs(new_ds_name = "Configured", new_ds_source = fixture$source,
      new_ds_location = fixture$parent, btn_confirm_create_ds = 1)
    expect_identical(basename(state$dataset_dir_path), "Configured")
    expect_identical(state$dataset_config$params, template$params)
    expect_identical(state$dataset_config$marker_filter_params, template$marker_filter_params)
    expect_identical(state$dataset_config$std_names, template$std_names)
    expect_identical(state$dataset_config$project_info$dataset_id, "Configured")
    expect_identical(state$dataset_config$project_info$source_doi, template$project_info$source_doi)
    expect_identical(state$dataset_config$project_info$source_url, template$project_info$source_url)
    expect_identical(state$sample_metadata$sample, c("002", "001"))
    dirs <- file.path(state$dataset_dir_path, "processed_data", c("002", "001"))
    expect_identical(state$paths_list$cell_file_paths, file.path(dirs, template$std_names$cells))
    expect_identical(state$paths_list$expmat_file_paths, file.path(dirs, template$std_names$expmat))
    expect_identical(state$paths_list$genes_file_paths, file.path(dirs, template$std_names$genes))
    saved_path <- file.path(state$dataset_dir_path, "dataset_config.yaml")
    saved_config <- yaml::read_yaml(saved_path)
    saved_hash <- tools::md5sum(saved_path)
    expect_false("expression_type" %in% names(state$pipeline_state$dataset_steps$standardization$details))
    # Historical provenance is retained without becoming an input-state gate.
    legacy_state <- load_pipeline_state(state$dataset_dir_path)
    legacy_state$dataset_steps$standardization$details$expression_type <- "counts"
    save_pipeline_state_atomic(legacy_state, state$dataset_dir_path)

    # Future defaults must not replace the saved dataset's settings on reload.
    future_template <- template
    future_template$std_names <- original_names
    future_template$params$target_sum <- 54321
    future_template$marker_filter_params$cell_type$min_genes <- 20
    yaml::write_yaml(future_template, fixture$template)
    session$setInputs(btn_change_dataset = 1)
    session$setInputs(dataset_choice = "Configured", btn_load_dataset = 1)
    expect_identical(state$dataset_config, saved_config)
    expect_identical(tools::md5sum(saved_path), saved_hash)
    expect_identical(state$sample_metadata$sample, c("002", "001"))
    expect_identical(state$paths_list$expmat_file_paths, file.path(dirs, template$std_names$expmat))
    expect_identical(state$pipeline_state$dataset_steps$standardization$details$expression_type, "counts")
  })
  expect_identical(tools::md5sum(source_files), source_hashes)
})

test_that("creation filename edits survive validation retry and reload without template changes", {
  env <- make_p03_server_fixture(withr::local_tempdir())
  fixture <- env$fixture
  defaults <- yaml::read_yaml(fixture$template)
  chosen <- list(expmat = "expression.mtx", genes = "gene symbols.txt",
    cells = "cell metadata.csv", samples = "sample metadata.csv")
  for (sample in c("002", "001")) {
    for (key in c("expmat", "genes", "cells")) {
      expect_true(file.rename(file.path(fixture$source, sample, defaults$std_names[[key]]),
        file.path(fixture$source, sample, chosen[[key]])))
    }
  }
  expect_true(file.rename(file.path(fixture$source, defaults$std_names$samples),
    file.path(fixture$source, chosen$samples)))
  original_files <- c(fixture$template, list.files(fixture$source, recursive = TRUE, full.names = TRUE))
  original_hashes <- tools::md5sum(original_files)
  state <- env$state
  shiny::testServer(env$server, {
    session$setInputs(btn_create_dataset_ui = 1)
    for (key in names(defaults$std_names)) {
      expect_match(tail(env$modals, 1), defaults$std_names[[key]], fixed = TRUE)
    }
    session$setInputs(new_ds_name = "CustomNames", new_ds_source = fixture$source,
      new_ds_location = fixture$parent, new_ds_std_expmat = "../expression.mtx",
      new_ds_std_genes = chosen$genes, new_ds_std_cells = chosen$cells,
      new_ds_std_samples = chosen$samples, new_ds_source_doi = "10.1234/custom",
      btn_confirm_create_ds = 1)
    expect_match(output$dataset_import_report$html, "portable filenames", fixed = TRUE)
    expect_null(state$dataset_dir_path)
    expect_length(list.files(fixture$parent, all.files = TRUE, no.. = TRUE), 0L)
    expect_identical(input$new_ds_std_genes, chosen$genes)
    expect_identical(input$new_ds_std_samples, chosen$samples)
    session$setInputs(new_ds_std_expmat = chosen$expmat, btn_confirm_create_ds = 2)
    expect_identical(state$dataset_config$std_names, chosen)
    expect_identical(state$dataset_config$params, defaults$params)
    expect_identical(state$dataset_config$project_info$source_doi, "10.1234/custom")
    expect_identical(state$sample_metadata$sample, c("002", "001"))
    saved_path <- file.path(state$dataset_dir_path, fixture$config$config_files$dataset)
    expect_identical(yaml::read_yaml(saved_path)$std_names, chosen)
    session$setInputs(btn_change_dataset = 1)
    session$setInputs(dataset_choice = "CustomNames", btn_load_dataset = 1)
    expect_identical(state$dataset_config$std_names, chosen)
    dirs <- file.path(state$dataset_dir_path, "processed_data", c("002", "001"))
    expect_identical(state$paths_list$expmat_file_paths, file.path(dirs, chosen$expmat))
    expect_identical(state$paths_list$genes_file_paths, file.path(dirs, chosen$genes))
    expect_identical(state$paths_list$cell_file_paths, file.path(dirs, chosen$cells))
  })
  expect_identical(tools::md5sum(original_files), original_hashes)
})

test_that("explicit import filename overrides reject blanks, collisions and missing files before copying", {
  fixture <- make_p03_inputs(withr::local_tempdir())
  original_hash <- tools::md5sum(fixture$template)
  defaults <- yaml::read_yaml(fixture$template)$std_names
  for (value in c("", "../matrix.mtx", defaults$genes)) {
    invalid <- defaults
    invalid$expmat <- value
    expect_error(p03_import(fixture, std_names = invalid), "filenames")
    expect_length(list.files(fixture$parent, all.files = TRUE, no.. = TRUE), 0L)
  }
  missing <- defaults
  missing$expmat <- "missing.mtx"
  expect_error(p03_import(fixture, std_names = missing), "missing.mtx", fixed = TRUE)
  expect_length(list.files(fixture$parent, all.files = TRUE, no.. = TRUE), 0L)
  expect_identical(tools::md5sum(fixture$template), original_hash)
})

test_that("DC01 import refuses to replace missing or mismatched configured filenames", {
  fixture <- make_p03_inputs(withr::local_tempdir())
  template <- yaml::read_yaml(fixture$template)
  template$std_names$expmat <- "expected_counts.mtx"
  yaml::write_yaml(template, fixture$template)
  expect_error(p03_import(fixture), "expected_counts.mtx", fixed = TRUE)
  expect_length(dataset_workspace_directories(fixture$parent), 0L)
  template$std_names <- NULL
  yaml::write_yaml(template, fixture$template)
  expect_error(p03_import(fixture), "Configure expmat, genes, cells, and samples", fixed = TRUE)
  expect_length(dataset_workspace_directories(fixture$parent), 0L)
})

test_that("DC01 import uses one configuration snapshot throughout copying", {
  fixture <- make_p03_inputs(withr::local_tempdir())
  template <- yaml::read_yaml(fixture$template)
  imported <- p03_import(fixture, progress = function(copied, total, path) {
    if (copied == 0) {
      future_template <- template
      future_template$std_names <- list(expmat = "future_counts.mtx", genes = "future_genes.txt",
        cells = "future_cells.csv", samples = "future_samples.csv")
      future_template$params$target_sum <- 77777
      yaml::write_yaml(future_template, fixture$template)
    }
  })
  saved <- yaml::read_yaml(file.path(imported$path, "dataset_config.yaml"))
  expect_identical(saved$std_names, template$std_names)
  expect_identical(saved$params, template$params)
  expect_true(check_prepared_data(file.path(imported$path, "processed_data"),
    std_names = saved$std_names)$valid)
})

test_that("DC04 optional source fields persist through creation and reload in all combinations", {
  cases <- list(
    list(doi = "  ", url = "\t"),
    list(doi = " 10.1234/paper ", url = ""),
    list(doi = "", url = " https://example.org/database-entry "),
    list(doi = " 10.1234/paper ", url = " https://example.org/database-entry ")
  )
  for (origin in cases) {
    env <- make_p03_server_fixture(withr::local_tempdir())
    fixture <- env$fixture
    state <- env$state
    expected <- list(source_doi = trimws(origin$doi), source_url = trimws(origin$url))
    shiny::testServer(env$server, {
      session$setInputs(btn_create_dataset_ui = 1)
      session$setInputs(new_ds_name = "With_Origin", new_ds_source = fixture$source,
        new_ds_location = fixture$parent, new_ds_source_doi = origin$doi,
        new_ds_source_url = origin$url, btn_confirm_create_ds = 1)
      expect_identical(basename(state$dataset_dir_path), "With_Origin")
      expect_identical(state$dataset_config$project_info[names(expected)], expected)
      saved <- yaml::read_yaml(file.path(state$dataset_dir_path, "dataset_config.yaml"))
      expect_identical(saved$project_info[names(expected)], expected)
      expect_identical(is.null(dataset_origin_reminder(saved)), any(nzchar(unlist(expected))))
      session$setInputs(btn_change_dataset = 1)
      session$setInputs(dataset_choice = "With_Origin", btn_load_dataset = 1)
      expect_identical(state$dataset_config$project_info[names(expected)], expected)
    })
  }
})

test_that("DC04 explicit source arguments override or clear template defaults without lookup", {
  fixture <- make_p03_inputs(withr::local_tempdir())
  template <- yaml::read_yaml(fixture$template)
  template$project_info$source_doi <- "10.1234/template"
  template$project_info$source_url <- "https://example.org/template"
  yaml::write_yaml(template, fixture$template)
  imported <- p03_import(fixture, source_doi = "   ", source_url = "\t")
  config <- yaml::read_yaml(file.path(imported$path, "dataset_config.yaml"))
  expect_identical(config$project_info$source_doi, "")
  expect_identical(config$project_info$source_url, "")
  supplied <- p03_import(fixture, "Unverified", source_doi = " paper reference not resolved ",
    source_url = " database entry not resolved ")
  config <- yaml::read_yaml(file.path(supplied$path, "dataset_config.yaml"))
  expect_identical(config$project_info$source_doi, "paper reference not resolved")
  expect_identical(config$project_info$source_url, "database entry not resolved")
})

test_that("DC03 legacy dataset technology remains loadable without rewriting saved metadata", {
  env <- make_p03_server_fixture(withr::local_tempdir())
  fixture <- env$fixture
  source_csv <- file.path(fixture$source, "Samples.csv")
  samples <- read_prepared_samples(source_csv)
  samples$technology <- c("10x Chromium", "Smart-seq2")
  data.table::fwrite(samples, source_csv, na = "")
  imported <- p03_import(fixture, "Legacy")
  config_path <- file.path(imported$path, "dataset_config.yaml")
  legacy <- yaml::read_yaml(config_path)
  legacy$project_info$technology <- "Historical dataset summary"
  yaml::write_yaml(legacy, config_path)
  copied_csv <- file.path(imported$path, "processed_data", legacy$std_names$samples)
  original_hashes <- tools::md5sum(c(config_path, copied_csv))
  state <- env$state
  shiny::testServer(env$server, {
    session$setInputs(dataset_choice = "Legacy", btn_load_dataset = 1)
    expect_identical(state$dataset_config, legacy)
    expect_identical(state$sample_metadata$technology, samples$technology)
    expect_identical(state$sample_metadata$sample, samples$sample)
    session$setInputs(btn_change_dataset = 1)
    session$setInputs(dataset_choice = "Legacy", btn_load_dataset = 2)
    expect_identical(state$dataset_config, legacy)
    expect_identical(state$sample_metadata$technology, samples$technology)
  })
  expect_identical(tools::md5sum(names(original_hashes)), original_hashes)
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
    session$setInputs(new_ds_name = "../Unsafe", new_ds_source_doi = " 10.1234/retry ",
      new_ds_source_url = " https://example.org/retry ", btn_confirm_create_ds = 2)
    expect_match(output$dataset_import_report$html, "path separators", fixed = TRUE)
    expect_identical(input$new_ds_source, env$fixture$source)
    expect_identical(input$new_ds_source_doi, " 10.1234/retry ")
    expect_identical(input$new_ds_source_url, " https://example.org/retry ")
    expect_length(state$active_actions, 0L)
    session$setInputs(new_ds_name = "Retried", btn_confirm_create_ds = 3)
    expect_identical(basename(state$dataset_dir_path), "Retried")
    expect_identical(state$dataset_config$project_info$source_doi, "10.1234/retry")
    expect_identical(state$dataset_config$project_info$source_url, "https://example.org/retry")
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
