suppressPackageStartupMessages(library(shiny))
suppressPackageStartupMessages(library(bslib))

make_c01_fixture <- function(root) {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  config <- yaml::read_yaml(file.path(app_dir, "general_config.yaml"))
  config$paths$datasets_dir <- file.path(root, "datasets")
  env <- new.env(parent = environment())
  env$notifications <- character()
  env$modals <- list()
  env$loads <- character()
  env$nav_select <- env$nav_show <- env$nav_hide <- function(...) invisible(NULL)
  env$updateNavbarPage <- function(...) invisible(NULL)
  env$removeModal <- env$removeNotification <- function(...) invisible(NULL)
  env$showNotification <- function(ui, ...) {
    env$notifications <- c(env$notifications, as.character(ui)); "notification"
  }
  env$showModal <- function(ui, ...) { env$modals <- c(env$modals, list(as.character(ui))) }
  env$record_state_event <- env$record_pipeline_event <- function(...) invisible(NULL)
  # These fixtures have no scientific caches. Loading and rendering a waiting
  # or omitted sample must never request one; annotation setup is counted below.
  env$cache_load_data <- function(...) stop("Unexpected scientific cache read")
  env$reconcile_pipeline_state_cache <- function(state, ...) state
  env$cell_type_annotation_setup <- function(idx, paths_list, ...) {
    env$loads <- c(env$loads, paths_list$sample_dir_paths[[idx]])
    list(cells_filt = load_cells(paths_list$cell_file_paths[[idx]]),
      all_matches = data.table::data.table(clust = 0L, cell_type = "T_cell", score = 1))
  }
  for (component in c("app/state.R", "app/server/single_de_server.R",
    "app/server/dataset_server.R", "app/server/dashboard_server.R",
    "app/server/resolution_server.R", "app/server/annotation_server.R",
    paste0("app/server/cna_", c("status", "compute", "cluster", "threshold", "summary", "reset"), "_server.R"),
    "app/server/cna_server.R")) sys.source(file.path(app_dir, component), env)
  env$state <- env$create_app_state(list())
  env$context <- list(config = config,
    paths = list(datasets_dir = config$paths$datasets_dir, templates_dir = file.path(app_dir, "templates")),
    resources = list(marker_genes = data.table::data.table(cell_type = "T_cell", symbol = "GENE01", combined = 2),
      housekeeping_genes = "GENE02", mt_genes = "GENE03", gene_positions = data.table::data.table()),
    available_datasets = c("A", "B", "Archived"))
  for (dataset in env$context$available_datasets) {
    samples <- if (dataset == "B") "shared" else c("first", "shared", "third")
    dataset_dir <- file.path(config$paths$datasets_dir, dataset)
    dir.create(dataset_dir, recursive = TRUE)
    ds_config <- yaml::read_yaml(file.path(app_dir, "templates/dataset_config_template.yaml"))
    ds_config$project_info$dataset_id <- dataset
    yaml::write_yaml(ds_config, file.path(dataset_dir, config$config_files$dataset))
    yaml::write_yaml(list(samples = lapply(samples, make_valid_sample_entry)),
      file.path(dataset_dir, config$config_files$samples))
    selected <- setup_selected_config(samples)
    state <- new_pipeline_state(dataset, samples)
    state <- transition_pipeline_step(state, "standardization", "completed", force = TRUE)
    for (sample in samples) {
      written <- write_mini_sample(file.path(dataset_dir, config$dataset_paths$processed_dir), sample)
      cells <- written$cells
      cells[, `:=`(cell_type = paste0(dataset, "_label"), clust = 0L, umap1 = 0, umap2 = 0)]
      data.table::fwrite(cells, written$cells_path)
      selected$resolutions[[sample]] <- 0.5
      for (step in c("clustering", "resolution", "differential_expression", "annotation")) {
        state <- transition_pipeline_step(state, step, "completed", sample, force = TRUE)
      }
      state <- transition_pipeline_step(state, "cna_configuration", "skipped", sample,
        reason = "CNA intentionally omitted in this synthetic fixture.",
        details = list(omitted_by_user = TRUE), force = TRUE)
    }
    metadata <- build_samples(samples)
    metadata$n_cells <- 20L
    data.table::fwrite(metadata, file.path(dataset_dir, config$dataset_paths$processed_dir, ds_config$std_names$samples))
    yaml::write_yaml(selected, file.path(dataset_dir, config$config_files$selected))
    save_pipeline_state_atomic(reconcile_pipeline_state_dependencies(state), dataset_dir)
    storage <- new_dataset_storage_state(dataset)
    if (dataset == "Archived") storage <- transition_dataset_storage_state(storage, "archived")
    save_dataset_storage_state_atomic(storage, dataset_dir)
  }
  env$server <- function(input, output, session) {
    env$register_dataset_server(input, output, session, env$state, env$context)
    env$register_dashboard_server(input, output, session, env$state, env$context)
    env$register_resolution_server(input, output, session, env$state, env$context)
    env$register_annotation_server(input, output, session, env$state, env$context)
    env$register_cna_server(input, output, session, env$state, env$context)
  }
  env
}

test_that("P02 CSV alone controls metadata, sample order, annotation, and reloads", {
  fixture <- make_c01_fixture(withr::local_tempdir())
  state <- fixture$state
  dataset_root <- fixture$context$paths$datasets_dir
  csv_path <- function(dataset) file.path(dataset_root, dataset, "processed_data", "Samples.csv")
  metadata <- read_prepared_samples(csv_path("A"))[c(3L, 1L, 2L)]
  metadata$cancer_type <- c("CSV third", "CSV first", "CSV shared")
  metadata$patient <- "0007"
  metadata$extra_note <- 'Colon, "ascending"'
  data.table::fwrite(metadata, csv_path("A"))
  unlink(file.path(dataset_root, "A", "samples_config.yaml"))
  # A conflicting YAML and even a corrupt YAML must have no runtime effect.
  b_yaml <- file.path(dataset_root, "B", "samples_config.yaml")
  yaml::write_yaml(list(samples = list(list(sample = "wrong", cancer_type = "YAML cancer"))), b_yaml)
  archived_yaml <- file.path(dataset_root, "Archived", "samples_config.yaml")
  writeLines("not: [valid yaml", archived_yaml)
  yaml_hashes <- tools::md5sum(c(b_yaml, archived_yaml))
  fixture$csv_reads <- character()
  checker <- check_prepared_data
  checker_env <- new.env(parent = environment(checker))
  checker_env$read_prepared_samples <- function(path) {
    fixture$csv_reads <- c(fixture$csv_reads, path)
    read_prepared_samples(path)
  }
  environment(checker) <- checker_env
  fixture$check_prepared_data <- checker
  fixture$load_samples <- function(...) stop("Runtime metadata must not be read twice")

  shiny::testServer(fixture$server, {
    session$setInputs(dataset_choice = "A", btn_load_dataset = 1, main_nav = "menu_tab")
    expect_identical(state$sample_metadata$sample, c("third", "first", "shared"))
    expect_identical(basename(state$paths_list$sample_dir_paths), state$sample_metadata$sample)
    expect_identical(state$sample_metadata$patient, rep("0007", 3L))
    expect_identical(state$sample_metadata$extra_note, rep('Colon, "ascending"', 3L))
    expect_length(fixture$csv_reads, 1L)
    session$setInputs(sample_idx = "1", main_nav = "anno_tab")
    expect_identical(state$sample_name, "third")
    expect_match(output$ref_cell_selector$html, "CSV third", fixed = TRUE)
    session$setInputs(sample_idx = "2")
    expect_identical(state$sample_name, "first")
    expect_match(output$ref_cell_selector$html, "CSV first", fixed = TRUE)

    session$setInputs(dataset_choice = "B", btn_load_dataset = 2, main_nav = "menu_tab")
    expect_identical(state$sample_metadata$sample, "shared")
    expect_identical(state$sample_metadata$patient, NA_character_)
    session$setInputs(sample_idx = "1", main_nav = "anno_tab")
    expect_match(output$ref_cell_selector$html, "Unknown", fixed = TRUE)
    expect_false(grepl("YAML cancer", output$ref_cell_selector$html, fixed = TRUE))
    session$setInputs(dataset_choice = "Archived", btn_load_dataset = 3, main_nav = "menu_tab")
    expect_identical(state$storage_state$status, "archived")
    expect_identical(state$sample_metadata$sample, c("first", "shared", "third"))
    session$setInputs(dataset_choice = "A", btn_load_dataset = 4)
    expect_identical(state$sample_metadata$sample, c("third", "first", "shared"))
    expect_length(fixture$csv_reads, 4L)
    expect_identical(tools::md5sum(c(b_yaml, archived_yaml)), yaml_hashes)
  })
})

test_that("P02 failed structure checks clear prior metadata and never fall back to YAML", {
  fixture <- make_c01_fixture(withr::local_tempdir())
  state <- fixture$state
  dataset_root <- fixture$context$paths$datasets_dir
  unlink(file.path(dataset_root, "B", "processed_data", "Samples.csv"))
  shiny::testServer(fixture$server, {
    session$setInputs(dataset_choice = "A", btn_load_dataset = 1, main_nav = "menu_tab")
    expect_equal(nrow(state$sample_metadata), 3L)
    session$setInputs(dataset_choice = "B", btn_load_dataset = 2)
    expect_null(state$sample_metadata)
    expect_null(state$paths_list)
    expect_null(state$live_selected_config)
    expect_null(state$complete_markers)
    expect_null(state$dataset_dir_path)
    expect_null(state$pipeline_state)
    expect_length(state$active_actions, 0L)
    expect_match(tail(fixture$modals, 1)[[1]], "Samples.csv", fixed = TRUE)
    session$setInputs(dataset_choice = "A", btn_load_dataset = 3)
    expect_equal(nrow(state$sample_metadata), 3L)
    # The same workspace is checked again on reload, with aggregate errors.
    unlink(file.path(dataset_root, "A", "processed_data", "first", c("Cells.csv", "Genes.txt")))
    session$setInputs(btn_load_dataset = 4)
    expect_null(state$sample_metadata)
    expect_null(state$paths_list)
    report <- tail(fixture$modals, 1)[[1]]
    expect_match(report, "Cells.csv", fixed = TRUE)
    expect_match(report, "Genes.txt", fixed = TRUE)
    session$setInputs(dataset_choice = "Archived", btn_load_dataset = 5)
    expect_equal(nrow(state$sample_metadata), 3L)
    session$setInputs(btn_change_dataset = 1)
    expect_null(state$sample_metadata)
  })
})

test_that("P02 damaged archived inputs remain reviewable with authoritative CSV metadata", {
  fixture <- make_c01_fixture(withr::local_tempdir())
  state <- fixture$state
  archived <- file.path(fixture$context$paths$datasets_dir, "Archived")
  unlink(file.path(archived, "processed_data", "first", "Cells.csv"))
  shiny::testServer(fixture$server, {
    session$setInputs(dataset_choice = "Archived", btn_load_dataset = 1, main_nav = "menu_tab")
    expect_identical(state$storage_state$status, "archived")
    expect_identical(state$sample_metadata$sample, c("first", "shared", "third"))
    expect_identical(basename(state$paths_list$sample_dir_paths), state$sample_metadata$sample)
    expect_true(dataset_storage_cache_is_retired(state$storage_state))
    # An archive still needs its CSV; no directory or YAML fallback is allowed.
    unlink(file.path(archived, "processed_data", "Samples.csv"))
    session$setInputs(btn_load_dataset = 2)
    expect_null(state$sample_metadata)
    expect_null(state$paths_list)
    expect_match(tail(fixture$modals, 1)[[1]], "Samples.csv", fixed = TRUE)
  })
})

test_that("P02 preserves the single-unambiguous-cancer marker selection policy", {
  fixture <- make_c01_fixture(withr::local_tempdir())
  fixture$context$resources$cancer_cell_map <- list(
    cancer_types = list("Cancer A" = "A", "Cancer B" = "B"),
    cell_types = list(A = "Malignant A", B = "Malignant B")
  )
  fixture$context$resources$malignant_markers <- data.table::data.table(
    cancer_type = c("A", "B"), symbol = c("MAL_A", "MAL_B"), combined = 2
  )
  csv <- file.path(fixture$context$paths$datasets_dir, "A", "processed_data", "Samples.csv")
  metadata <- read_prepared_samples(csv)
  state <- fixture$state
  cases <- list(rep("Cancer A", 3L), c("Cancer A", "Cancer B", NA),
                rep(NA_character_, 3L), rep("Unrecognized", 3L), c("Cancer A", NA, NA))
  shiny::testServer(fixture$server, {
    for (i in seq_along(cases)) {
      metadata$cancer_type <- cases[[i]]
      data.table::fwrite(metadata, csv)
      session$setInputs(dataset_choice = "A", btn_load_dataset = i, main_nav = "menu_tab")
      expect_identical(state$sample_metadata$cancer_type, cases[[i]])
      symbols <- state$complete_markers$symbol
      expect_identical("MAL_A" %in% symbols, i %in% c(1L, 5L))
      expect_false("MAL_B" %in% symbols)
      expect_true(all(c("GENE01", "GENE02", "GENE03") %in% symbols))
    }
  })
})

test_that("C01 stale indices across real dataset loads do not crash annotation or CNA", {
  root <- withr::local_tempdir()
  fixture <- make_c01_fixture(root)
  state <- fixture$state
  files <- list.files(root, recursive = TRUE, full.names = TRUE)
  hashes <- tools::md5sum(files)
  shiny::testServer(fixture$server, {
    session$setInputs(dataset_choice = "A", btn_load_dataset = 1, main_nav = "menu_tab")
    session$setInputs(sample_idx = "3", cna_sample_idx = "3", res_sample_idx = "3", main_nav = "anno_tab")
    expect_identical(state$sample_name, "third")
    expect_true(all(state$cells_filt$cell_type == "A_label"))
    fixture$arm_app_confirmation(state, "after_de_navigation")
    fixture$arm_app_confirmation(state, "cna_reset")
    state$cna_preview_sample <- "third"
    session$setInputs(btn_change_dataset = 1)
    expect_null(state$paths_list)
    expect_null(state$cells_filt)
    expect_null(state$cna_preview_sample)
    expect_length(state$open_confirmations, 0)
    # Old browser input 3 remains until the asynchronous select update arrives.
    session$setInputs(dataset_choice = "B", btn_load_dataset = 2)
    expect_identical(basename(state$dataset_dir_path), "B")
    expect_null(state$cells_filt)
    session$setInputs(confirm_cna_reset = 1, btn_after_de_anno = 1)
    session$setInputs(sample_idx = "1", cna_sample_idx = "1", res_sample_idx = "1")
    expect_identical(state$sample_name, "shared")
    expect_true(all(state$cells_filt$cell_type == "B_label"))
    expect_match(output$cna_header_text, "shared", fixed = TRUE)
    expect_match(output$res_header_text, "shared", fixed = TRUE)
    # Same index, new dataset and sample ordering: reload the correct labels.
    session$setInputs(dataset_choice = "A", btn_load_dataset = 3)
    session$setInputs(main_nav = "menu_tab")
    session$setInputs(main_nav = "anno_tab", cna_sample_idx = "1", sample_idx = "1")
    expect_identical(state$sample_name, "first")
    expect_true(all(state$cells_filt$cell_type == "A_label"))
    previous_generation <- state$dataset_generation
    session$setInputs(btn_load_dataset = 4)
    expect_gt(state$dataset_generation, previous_generation)
    expect_null(state$cells_filt)
    session$setInputs(dataset_choice = "Archived", btn_load_dataset = 5, main_nav = "menu_tab")
    expect_identical(state$storage_state$status, "archived")
    session$setInputs(btn_change_dataset = 2)
    session$setInputs(dataset_choice = "B", btn_load_dataset = 6)
    expect_identical(state$storage_state$status, "active")
    expect_identical(tools::md5sum(files), hashes)
  })
})

test_that("C01 invalid selector values wait, but a valid sample with corrupt state still errors", {
  fixture <- make_c01_fixture(withr::local_tempdir())
  state <- fixture$state
  shiny::testServer(fixture$server, {
    session$setInputs(dataset_choice = "B", btn_load_dataset = 1, main_nav = "anno_tab")
    for (value in list("", "text", "0", "-1", "2", "1.5", "Inf", NA_character_, c("1", "2"))) {
      session$setInputs(sample_idx = value, cna_sample_idx = value, res_sample_idx = value)
      expect_null(state$cells_filt)
    }
    session$setInputs(sample_idx = "1", cna_sample_idx = "1", res_sample_idx = "1")
    expect_identical(state$sample_name, "shared")
    expect_error(get_pipeline_step(new_pipeline_state("B", character()), "annotation", "shared"), "Unknown or missing sample")
  })
})

test_that("C01 switching/loading refuses dirty or busy work and failed loads clear old context", {
  fixture <- make_c01_fixture(withr::local_tempdir())
  state <- fixture$state
  shiny::testServer(fixture$server, {
    session$setInputs(dataset_choice = "A", btn_load_dataset = 1, main_nav = "menu_tab")
    original <- state$dataset_dir_path
    state$annotation_dirty <- TRUE
    session$setInputs(btn_change_dataset = 1, dataset_choice = "B", btn_load_dataset = 2)
    expect_identical(state$dataset_dir_path, original)
    expect_true(state$annotation_dirty)
    state$annotation_dirty <- FALSE
    state$active_actions <- "cna_batch_compute"
    session$setInputs(btn_change_dataset = 2, btn_load_dataset = 3)
    expect_identical(state$dataset_dir_path, original)
    expect_identical(state$active_actions, "cna_batch_compute")
    state$active_actions <- character()
    session$setInputs(dataset_choice = "missing", btn_load_dataset = 4)
    expect_null(state$paths_list)
    expect_null(state$pipeline_state)
    expect_length(state$active_actions, 0)
    expect_true(any(grepl("Aborting load", fixture$notifications, fixed = TRUE)))
    session$setInputs(dataset_choice = "B", btn_load_dataset = 5)
    expect_identical(basename(state$dataset_dir_path), "B")
  })
})

test_that("C01 CNA cache identity changes with datasets, not unrelated downstream saves", {
  fixture <- make_c01_fixture(withr::local_tempdir())
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  sys.source(file.path(app_dir, "app/ui/cna_ui.R"), fixture)
  state <- fixture$state
  dataset <- file.path(fixture$context$paths$datasets_dir, "A")
  state$dataset_dir_path <- dataset
  state$paths_list <- list(sample_dir_paths = file.path(dataset, "processed_data", "shared"))
  state$pipeline_state <- transition_pipeline_step(new_pipeline_state("A", "shared"),
    "cna_compute", "completed", "shared", force = TRUE)
  for (step in c("annotation", "cna_configuration")) {
    state$pipeline_state <- transition_pipeline_step(shiny::isolate(state$pipeline_state), step, "completed", "shared", force = TRUE)
  }
  state$storage_state <- new_dataset_storage_state("A")
  selected <- setup_selected_config("shared")
  selected$resolutions$shared <- 0.5
  selected$cna_ref_cells$shared <- "T_cell"
  selected$cna_pot_mal_cells$shared <- "Epithelial"
  state$live_selected_config <- selected
  cells <- data.table::data.table(cell_name = paste0("cell", 1:3), cell_type = c("T_cell", "Epithelial", "Epithelial"))
  hc <- stats::hclust(stats::dist(matrix(1:9, nrow = 3, dimnames = list(cells$cell_name, NULL))))
  reads <- character()
  fixture$cache_load_data <- function(name, dataset, ...) {
    reads <<- c(reads, paste(dataset, name))
    if (startsWith(name, "hclust_")) hc else data.table::copy(cells)
  }
  fixture$load_expdt_from_cna_matrix <- function(...) {
    data.table::CJ(gene = paste0("gene", 1:24), cell_name = cells$cell_name)[, `:=`(chr = "01", cna = 0.5)]
  }
  fixture$dendrogram_plot <- fixture$cna_heatmap <- fixture$cluster_or_cell_type_bar_plot <- function(...) ggplot2::ggplot()
  server <- function(input, output, session) fixture$register_cna_cluster_server(input, output, session, state, fixture$context)
  shiny::testServer(server, {
    state$cna_view_context <- cna_analysis_context(state, "shared", "cna_view_select_malignant")
    # A fresh three-cell tree initializes to min(7, n_cells).
    session$setInputs(main_nav = "cna_tab", cna_main_views = "cna_view_select_malignant", cna_sample_idx = "1", cna_k_clusters = 3)
    output$cna_cluster_navigator_ui
    expect_length(reads, 2)
    state$pipeline_state <- transition_pipeline_step(state$pipeline_state,
      "cna_assignment", "completed", "shared", force = TRUE)
    session$flushReact()
    output$cna_cluster_navigator_ui
    expect_length(reads, 2)
    state$dataset_dir_path <- paste0(dataset, "-other")
    state$paths_list <- list(sample_dir_paths = file.path(state$dataset_dir_path, "processed_data", "shared"))
    state$cna_view_context <- cna_analysis_context(state, "shared", "cna_view_select_malignant")
    session$flushReact()
    output$cna_cluster_navigator_ui
    expect_length(reads, 4)
    expect_true(all(startsWith(tail(reads, 2), state$dataset_dir_path)))
    state$dataset_generation <- state$dataset_generation + 1L
    state$cna_view_context <- cna_analysis_context(state, "shared", "cna_view_select_malignant")
    session$flushReact()
    output$cna_cluster_navigator_ui
    expect_length(reads, 6)
  })
})
