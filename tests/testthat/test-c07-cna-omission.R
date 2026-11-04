make_c07_fixture <- function(root) {
  env <- new.env(parent = environment())
  app <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  for (file in c("app/state.R", "app/ui/cna_ui.R", "app/server/single_de_server.R", "app/server/annotation_server.R",
    paste0("app/server/cna_", c("status", "compute", "cluster", "threshold", "summary", "reset"), "_server.R"),
    "app/server/cna_server.R")) sys.source(file.path(app, file), env)
  env$notices <- character(); env$modal <- ""; env$events <- list(); env$reads <- character()
  env$nav_select <- env$removeModal <- env$removeNotification <- function(...) invisible(NULL)
  env$showModal <- function(ui, ...) env$modal <- as.character(ui)
  env$showNotification <- function(ui, ...) { env$notices <- c(env$notices, as.character(ui)); "notice" }
  env$record_state_event <- function(...) env$events <- c(env$events, list(list(...)))
  env$cache_load_data <- function(filename, ...) { env$reads <- c(env$reads, filename); stop("Unexpected scientific cache read") }
  env$cna_sample_preflight <- function(sample_name, ..., pipeline_state) {
    if (pipeline_cna_is_omitted(pipeline_state, sample_name)) return(list(status = "omitted", eligible = FALSE,
      reasons = "CNA explicitly omitted", counts = list()))
    list(status = "eligible", eligible = TRUE, reasons = character(), counts = list())
  }
  samples <- c("Sample_A", "Sample_B")
  dirs <- file.path(root, "processed_data", samples)
  selected <- setup_selected_config(samples)
  pipeline <- new_pipeline_state(basename(root), samples)
  pipeline <- transition_pipeline_step(pipeline, "standardization", "completed", force = TRUE)
  for (i in seq_along(samples)) {
    sample <- samples[[i]]; dir.create(dirs[[i]], recursive = TRUE)
    cells <- data.table::data.table(cell_name = paste0(sample, 1:2), sample = sample,
      cell_type = c("T_cell", "Malignant"), cell_type_pre_cna = c("T_cell", "Epithelial"), subclone = c(NA_integer_, 1L))
    data.table::fwrite(cells, file.path(dirs[[i]], "Cells.csv"))
    cache_save_data(cells, paste0("cells_filt_clust_res_0.5_", sample, ".qs2"), root)
    matrix <- data.table::data.table(gene = "GENE1", chr = "01", start_pos = 1L)
    for (cell in cells$cell_name) data.table::set(matrix, j = cell, value = 0.1)
    cache_save_data(matrix, paste0("cna_matrix_", sample, ".qs2"), root)
    selected$resolutions[[sample]] <- 0.5
    selected$cna_ref_cells[[sample]] <- "T_cell"; selected$cna_pot_mal_cells[[sample]] <- "Epithelial"
    selected$cna_ward_ref_cluster[[sample]] <- list(list(k = 2L, cluster = 1L))
    selected$cna_thresholds[[sample]] <- list(list(m_x = 0.6, m_y = 0.2, nm_x = 0.3, nm_y = 0.1))
    for (step in PIPELINE_SAMPLE_STEPS) pipeline <- transition_pipeline_step(pipeline, step, "completed", sample, force = TRUE)
    folder <- file.path(root, "results", sample, "3_cna_plots"); dir.create(folder, recursive = TRUE)
    writeLines("historical CNA plot", file.path(folder, "plot.png"))
    writeLines("historical export", file.path(folder, "cna_values.csv.gz"))
  }
  rv <- env$create_app_state(list())
  rv$dataset_dir_path <- root; rv$results_dir_path <- file.path(root, "results")
  rv$paths_list <- list(sample_dir_paths = dirs, cell_file_paths = file.path(dirs, "Cells.csv"))
  rv$pipeline_state <- save_pipeline_state_atomic(pipeline, root); rv$pipeline_state_path <- file.path(root, "pipeline_state.yaml")
  rv$live_selected_config <- selected; rv$config <- list(selected = selected)
  rv$selected_config_path <- file.path(root, "selected_config.yaml"); yaml::write_yaml(selected, file.path(root, "selected_config.yaml"))
  rv$storage_state <- new_dataset_storage_state(basename(root)); rv$sample_name <- "Sample_A"
  env$state <- rv
  env$server <- function(input, output, session) {
    env$register_annotation_server(input, output, session, rv, list())
    env$register_cna_server(input, output, session, rv, list(resources = list()))
  }
  env
}

test_that("C07 CNA-view omission cancels or confirms once, preserving upstream files and other samples", {
  fx <- make_c07_fixture(withr::local_tempdir()); rv <- fx$state
  original <- shiny::isolate(rv$pipeline_state)
  config <- shiny::isolate(rv$live_selected_config)
  files <- c(shiny::isolate(rv$paths_list$cell_file_paths), list.files(shiny::isolate(rv$results_dir_path), recursive = TRUE, full.names = TRUE))
  hashes <- tools::md5sum(files)
  shiny::testServer(fx$server, {
    session$setInputs(main_nav = "cna_tab", sample_idx = "1", cna_sample_idx = "2", cna_main_views = "cna_view_default")
    session$setInputs(btn_cna_omit = 1)
    expect_match(fx$modal, "Sample_B", fixed = TRUE)
    expect_match(fx$modal, "historical plots/exports are retained", fixed = TRUE)
    session$setInputs(btn_cancel_omit_cna = 1, btn_confirm_omit_cna = 1)
    expect_identical(rv$pipeline_state, original)
    expect_identical(rv$live_selected_config, config)
    session$setInputs(btn_cna_omit = 2)
    session$setInputs(btn_confirm_omit_cna = 2)
    expect_true(pipeline_cna_is_omitted(rv$pipeline_state, "Sample_B"))
    expect_false(pipeline_cna_is_omitted(rv$pipeline_state, "Sample_A"))
    expect_identical(rv$pipeline_state$samples$Sample_A, original$samples$Sample_A)
    upstream <- c("clustering", "resolution", "differential_expression", "annotation")
    expect_identical(rv$pipeline_state$samples$Sample_B[upstream], original$samples$Sample_B[upstream])
    expect_identical(rv$live_selected_config$cna_thresholds, config$cna_thresholds)
    expect_identical(rv$live_selected_config$cna_ward_ref_cluster, config$cna_ward_ref_cluster)
    expect_identical(rv$live_selected_config$cna_ref_cells$Sample_B, list())
    expect_identical(tools::md5sum(files), hashes)
    expect_false(file.exists(file.path(rv$dataset_dir_path, "cache", "cna_matrix_Sample_B.qs2")))
    expect_true(file.exists(file.path(rv$dataset_dir_path, "cache", "cna_matrix_Sample_A.qs2")))
    expect_true(file.exists(file.path(rv$dataset_dir_path, "cache", "cells_filt_clust_res_0.5_Sample_B.qs2")))
    expect_match(output$cna_status_ui$html, "intentionally omitted", fixed = TRUE)
    session$setInputs(btn_cna_go_malig_clust = 1, cna_main_views = "cna_view_select_malignant")
    expect_length(fx$reads, 0L)
    saved_hash <- tools::md5sum(c(rv$selected_config_path, rv$pipeline_state_path))
    session$setInputs(btn_confirm_omit_cna = 3, btn_cna_omit = 3)
    expect_identical(tools::md5sum(names(saved_hash)), saved_hash)
    loaded <- load_pipeline_state(rv$dataset_dir_path)
    expect_true(pipeline_cna_is_omitted(loaded, "Sample_B"))
    expect_identical(loaded$samples$Sample_A, original$samples$Sample_A)
    session$setInputs(btn_cna_batch_compute = 1)
    expect_false(grepl('value="Sample_B"', fx$modal, fixed = TRUE))
    expect_match(fx$modal, 'value="Sample_A"', fixed = TRUE)
    # The existing configuration-save handler reverses the omission. It must
    # not revive the invalidated computation or its downstream saved results.
    rv$sample_name <- "Sample_B"
    session$setInputs(cna_refs_input = "T_cell", cna_pot_mal_input = "Epithelial", btn_save_refs = 1)
    expect_false(pipeline_cna_is_omitted(rv$pipeline_state, "Sample_B"))
    expect_identical(get_pipeline_step(rv$pipeline_state, "cna_configuration", "Sample_B")$status, "completed")
    expect_identical(get_pipeline_step(rv$pipeline_state, "cna_compute", "Sample_B")$status, "not_started")
    expect_true(pipeline_step_readiness(rv$pipeline_state, "cna_compute", "Sample_B")$ready)
    expect_identical(tools::md5sum(files), hashes)
  })
})

test_that("C07 omission rejects dirty, busy, archived, changed and invalid confirmation contexts", {
  fx <- make_c07_fixture(withr::local_tempdir()); rv <- fx$state
  paths <- shiny::isolate(c(rv$selected_config_path, rv$pipeline_state_path))
  hashes <- tools::md5sum(paths)
  shiny::testServer(fx$server, {
    session$setInputs(main_nav = "cna_tab", sample_idx = "1", cna_sample_idx = "2")
    rv$annotation_dirty <- TRUE
    session$setInputs(btn_cna_omit = 1)
    expect_false("omit_cna" %in% rv$open_confirmations)
    rv$annotation_dirty <- FALSE; rv$active_actions <- "compute"
    session$setInputs(btn_cna_omit = 2)
    expect_false("omit_cna" %in% rv$open_confirmations)
    rv$active_actions <- character(); rv$storage_state$status <- "archived"
    session$setInputs(btn_cna_omit = 3)
    expect_false("omit_cna" %in% rv$open_confirmations)
    rv$storage_state$status <- "active"
    for (change in c("sample", "generation", "configuration", "dirty", "busy", "archived", "index")) {
      session$setInputs(cna_sample_idx = "2", btn_cna_omit = which(change == c("sample", "generation", "configuration", "dirty", "busy", "archived", "index")) + 3)
      expect_true("omit_cna" %in% rv$open_confirmations)
      if (change == "sample") session$setInputs(cna_sample_idx = "1")
      if (change == "generation") rv$dataset_generation <- rv$dataset_generation + 1L
      if (change == "configuration") rv$live_selected_config$cna_ref_cells$Sample_B <- "Changed"
      if (change == "dirty") rv$annotation_dirty <- TRUE
      if (change == "busy") rv$active_actions <- "compute"
      if (change == "archived") rv$storage_state$status <- "archived"
      if (change == "index") session$setInputs(cna_sample_idx = "100")
      session$setInputs(btn_confirm_omit_cna = which(change == c("sample", "generation", "configuration", "dirty", "busy", "archived", "index")))
      expect_identical(tools::md5sum(paths), hashes)
      rv$annotation_dirty <- FALSE; rv$active_actions <- character(); rv$storage_state$status <- "active"
    }
  })
})
