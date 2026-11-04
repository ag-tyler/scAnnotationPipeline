write_ui_fixture_plot <- function(path, title, subtitle) {
  grDevices::png(path, width = 900, height = 650, res = 120)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mar = c(4, 4, 4, 1))
  graphics::plot(
    cos(seq(0, 2 * pi, length.out = 48)),
    sin(seq(0, 2 * pi, length.out = 48)),
    col = rep(c("#2C7BB6", "#FDAE61", "#1A9641"), each = 16),
    pch = 19,
    xlab = "UMAP 1",
    ylab = "UMAP 2",
    main = title,
    sub = subtitle
  )
}

make_portable_ui_fixture <- function(app_dir, dataset_name = "Synthetic_Demo") {
  config <- yaml::read_yaml(file.path(app_dir, "general_config.yaml"))
  resources_dir <- file.path(app_dir, config$paths$resources_dir)
  datasets_dir <- file.path(app_dir, config$paths$datasets_dir)
  dataset_dir <- file.path(datasets_dir, dataset_name)
  sample_name <- "Synthetic_sample"
  processed_dir <- file.path(dataset_dir, config$dataset_paths$processed_dir)
  sample_dir <- file.path(processed_dir, sample_name)
  results_dir <- file.path(dataset_dir, config$dataset_paths$results_dir)
  cluster_plots_dir <- file.path(results_dir, sample_name, "1_cluster_plots")
  de_plots_dir <- file.path(results_dir, sample_name, "2_de_plots")
  dir.create(resources_dir, recursive = TRUE)
  dir.create(sample_dir, recursive = TRUE)
  dir.create(cluster_plots_dir, recursive = TRUE)
  dir.create(de_plots_dir, recursive = TRUE)

  genes <- sprintf("GENE%03d", seq_len(66))
  ensembl_ids <- sprintf("ENSG%011d", seq_along(genes))
  chromosomes <- rep(as.character(1:3), each = 22)
  data.table::fwrite(
    data.table::data.table(
      cell_type = rep(c("B cell", "Epithelial"), each = 8),
      gene = genes[1:16],
      specificity = 0.9,
      sensitivity = 0.8,
      combined = 2
    ),
    file.path(resources_dir, config$resource_files$marker_sets)
  )
  data.table::fwrite(
    data.table::data.table(
      cancer_type = "SYN",
      gene = genes[17:24],
      specificity = 0.9,
      sensitivity = 0.8,
      combined = 2
    ),
    file.path(resources_dir, config$resource_files$malignant_markers)
  )
  writeLines(
    genes[25:27],
    file.path(resources_dir, config$resource_files$housekeeping_genes)
  )
  writeLines(
    genes[28:30],
    file.path(resources_dir, config$resource_files$mitochondrial_genes)
  )
  jsonlite::write_json(
    list(
      cancer_types = list("Synthetic Cancer" = "SYN"),
      cell_types = list(SYN = "Epithelial")
    ),
    file.path(resources_dir, config$resource_files$cancer_cell_map),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  data.table::fwrite(
    data.table::data.table(
      hgnc_symbol = genes,
      ensembl_gene_id = ensembl_ids,
      chromosome_name = chromosomes,
      start_position = rep(seq(1e6, by = 1e6, length.out = 22), 3),
      end_position = rep(seq(1e6, by = 1e6, length.out = 22), 3) + 1000
    ),
    file.path(resources_dir, config$resource_files$gene_positions),
    sep = "\t"
  )
  data.table::fwrite(
    data.table::data.table(
      ensembl_gene_id = ensembl_ids,
      symbol = genes,
      location_sortable = paste0(chromosomes, "p", seq_along(genes))
    ),
    file.path(resources_dir, config$resource_files$hgnc_complete_set),
    sep = "\t"
  )
  writeLines(
    "Synthetic metadata prompt used by the portable UI test.",
    file.path(resources_dir, config$resource_files$metadata_prompt)
  )

  dataset_config <- list(
    project_info = list(dataset_id = dataset_name, technology = "synthetic"),
    std_names = list(
      expmat = "Exp_data_UMIcounts.mtx",
      genes = "Genes.txt",
      cells = "Cells.csv",
      samples = "Samples.csv"
    ),
    raw_files = list(type = "synthetic"),
    marker_filter_params = list(
      cell_type = list(min_score = 1, min_genes = 2, max_genes = 8),
      cancer_type = list(min_score = 1, min_genes = 2, max_genes = 8)
    ),
    params = list(
      min_genes = 1,
      target_sum = 10000,
      log2_expr_threshold = 0,
      max_marker_genes = 8,
      pca_nv = 5,
      seed = 3988,
      resolutions = c(0.5, 1),
      umap = list(spread = 2, min_dist = 0.1),
      de = list(
        num_genes = 20,
        max_match_genes = 10,
        min_marker_found = 2
      )
    )
  )
  yaml::write_yaml(
    dataset_config,
    file.path(dataset_dir, config$config_files$dataset)
  )
  sample_entry <- make_valid_sample_entry(sample_name)
  sample_entry$technology <- "Synthetic counts"
  sample_entry$cancer_type <- "Synthetic Cancer"
  sample_entry$patient <- "synthetic_subject"
  sample_entry$sample_type <- "tumor"
  yaml::write_yaml(
    list(samples = list(sample_entry)),
    file.path(dataset_dir, config$config_files$samples)
  )

  set.seed(3988)
  cell_names <- sprintf("synthetic_cell_%03d", seq_len(48))
  counts <- matrix(
    stats::rpois(length(genes) * length(cell_names), lambda = 5),
    nrow = length(genes),
    dimnames = list(genes, cell_names)
  )
  counts <- methods::as(Matrix::Matrix(counts, sparse = TRUE), "CsparseMatrix")
  cell_types <- rep(c("B_cell", "Epithelial", NA_character_), each = 16)
  cells <- data.table::data.table(
    cell_name = cell_names,
    sample = sample_name,
    cell_type = cell_types,
    complexity = as.numeric(Matrix::colSums(counts != 0)),
    cell_subtype = NA_character_,
    patient = "synthetic_subject",
    subclone = NA_character_,
    source = "synthetic",
    cell_type_pre_cna = cell_types
  )
  Matrix::writeMM(counts, file.path(sample_dir, dataset_config$std_names$expmat))
  writeLines(genes, file.path(sample_dir, dataset_config$std_names$genes))
  data.table::fwrite(cells, file.path(sample_dir, dataset_config$std_names$cells))
  data.table::fwrite(
    data.table::data.table(
      sample = sample_name,
      n_cells = length(cell_names),
      cancer_type = "Synthetic Cancer"
    ),
    file.path(processed_dir, dataset_config$std_names$samples)
  )

  selected_config <- setup_selected_config(sample_name)
  selected_config$resolutions[[sample_name]] <- 0.5
  selected_config$cna_ref_cells[[sample_name]] <- "B_cell"
  selected_config$cna_pot_mal_cells[[sample_name]] <- "Epithelial"
  selected_config$sample_notes[[sample_name]] <- "Portable synthetic UI fixture"
  yaml::write_yaml(
    selected_config,
    file.path(dataset_dir, config$config_files$selected)
  )

  clustered_cells <- data.table::copy(cells)
  clustered_cells[, `:=`(
    umap1 = cos(seq(0, 2 * pi, length.out = .N)),
    umap2 = sin(seq(0, 2 * pi, length.out = .N)),
    clust = rep(1:3, each = 16)
  )]
  paths_list <- list(
    sample_dir_paths = sample_dir,
    cell_file_paths = file.path(sample_dir, dataset_config$std_names$cells),
    expmat_file_paths = file.path(sample_dir, dataset_config$std_names$expmat),
    genes_file_paths = file.path(sample_dir, dataset_config$std_names$genes)
  )
  cache_save_data(
    counts,
    paste0("expmat_filt_", sample_name, ".qs2"),
    dataset_dir,
    dependencies = filter_cache_dependencies(paths_list, 1, dataset_config),
    producer = "portable-ui-fixture"
  )
  for (resolution in dataset_config$params$resolutions) {
    cache_save_data(
      clustered_cells,
      paste0("cells_filt_clust_res_", resolution, "_", sample_name, ".qs2"),
      dataset_dir,
      dependencies = clustering_cache_dependencies(
        paths_list,
        1,
        dataset_config,
        resolution
      ),
      producer = "portable-ui-fixture"
    )
    write_ui_fixture_plot(
      file.path(
        cluster_plots_dir,
        paste0("clusters_plot_", sample_name, "_res_", resolution, ".png")
      ),
      paste("Synthetic clusters at resolution", resolution),
      "Portable UI regression fixture"
    )
  }
  write_ui_fixture_plot(
    file.path(de_plots_dir, "1.png"),
    "Synthetic cluster marker scores",
    "Cluster 1"
  )
  write_ui_fixture_plot(
    file.path(de_plots_dir, "top_20_unannotated_gene_count_plot.png"),
    "Synthetic differential expression summary",
    "Portable UI regression fixture"
  )
  data.table::fwrite(
    data.table::data.table(
      clust = rep(1:3, each = 4),
      symbol = genes[1:12],
      avg_log2FC = seq(2, 0.9, length.out = 12),
      p_val_adj = 0.001,
      B_cell = rep(c("match", NA_character_), 6),
      Epithelial = rep(c(NA_character_, "match"), 6),
      Housekeeping_artifact = NA_character_,
      Mito_artifact = NA_character_
    ),
    file.path(de_plots_dir, "all_marker_matches.csv")
  )

  timestamp <- as.POSIXct("2026-10-16 12:00:00", tz = "UTC")
  pipeline_state <- new_pipeline_state(dataset_name, sample_name, timestamp)
  pipeline_state <- transition_pipeline_step(
    pipeline_state,
    "standardization",
    "completed",
    details = list(sample_count = 1L),
    timestamp = timestamp + 1
  )
  for (step in c(
    "clustering", "resolution", "differential_expression", "annotation",
    "cna_configuration"
  )) {
    pipeline_state <- transition_pipeline_step(
      pipeline_state,
      step,
      "completed",
      sample = sample_name,
      force = TRUE,
      timestamp = timestamp + match(step, PIPELINE_SAMPLE_STEPS)
    )
  }
  save_pipeline_state_atomic(
    pipeline_state,
    dataset_dir,
    state_filename = config$config_files$state,
    timestamp = timestamp + 20
  )

  invisible(dataset_name)
}

make_ui_baseline_app <- function(source_app_dir, .local_envir = parent.frame()) {
  test_app_dir <- withr::local_tempdir(
    pattern = "scannotation-ui-",
    .local_envir = .local_envir
  )
  dir.create(file.path(test_app_dir, "util_scripts"))
  dir.create(file.path(test_app_dir, "app"))
  dir.create(file.path(test_app_dir, "templates"))

  file.copy(
    file.path(source_app_dir, "app.R"),
    file.path(test_app_dir, "app.R")
  )
  file.copy(
    list.files(
      file.path(source_app_dir, "util_scripts"),
      pattern = "[.]R$",
      full.names = TRUE
    ),
    file.path(test_app_dir, "util_scripts")
  )

  component_root <- file.path(source_app_dir, "app")
  component_files <- list.files(
    component_root,
    pattern = "[.]R$",
    recursive = TRUE,
    full.names = TRUE
  )
  component_relative_paths <- substring(
    component_files,
    nchar(component_root) + 2L
  )
  component_destinations <- file.path(
    test_app_dir,
    "app",
    component_relative_paths
  )
  invisible(lapply(
    unique(dirname(component_destinations)),
    dir.create,
    recursive = TRUE,
    showWarnings = FALSE
  ))
  file.copy(component_files, component_destinations)

  file.copy(
    list.files(
      file.path(source_app_dir, "templates"),
      full.names = TRUE
    ),
    file.path(test_app_dir, "templates")
  )

  config <- yaml::read_yaml(file.path(source_app_dir, "general_config.yaml"))
  yaml::write_yaml(config, file.path(test_app_dir, "general_config.yaml"))
  make_portable_ui_fixture(test_app_dir)

  test_app_dir
}

expect_ui_baseline_screenshot <- function(app, baseline_dir, filename) {
  actual_path <- tempfile(fileext = ".png")
  app$get_screenshot(file = actual_path, selector = "viewport")

  baseline_path <- file.path(baseline_dir, filename)
  update_files <- Sys.getenv("UPDATE_UI_BASELINE_FILES")
  if (identical(Sys.getenv("UPDATE_UI_BASELINES"), "true") &&
      (!nzchar(update_files) || filename %in% strsplit(update_files, ",", fixed = TRUE)[[1]])) {
    dir.create(baseline_dir, recursive = TRUE, showWarnings = FALSE)
    file.copy(actual_path, baseline_path, overwrite = TRUE)
  }

  if (!file.exists(baseline_path)) {
    testthat::succeed(paste0(
      "No reviewed UI baseline for ", basename(baseline_dir),
      "; functional browser assertions still ran for ", filename, "."
    ))
    return(invisible(FALSE))
  }

  expect_true(
    file.exists(baseline_path),
    info = paste0(
      "Missing UI baseline: ", baseline_path,
      ". Rerun with UPDATE_UI_BASELINES=true after reviewing the current UI."
    )
  )
  expect_true(
    shinytest2::compare_screenshot_threshold(
      baseline_path,
      actual_path,
      threshold = 5
    ),
    info = paste("UI differs from baseline", baseline_path)
  )

  invisible(TRUE)
}

make_cna_navigation_ui_fixture <- function(test_app) {
  dataset <- file.path(test_app, "datasets", "Synthetic_Demo")
  processed <- file.path(dataset, "processed_data")
  original <- "Synthetic_sample"
  samples <- c(original, "Z_omitted", "Z_reset")
  config <- yaml::read_yaml(file.path(dataset, "dataset_config.yaml"))
  selected <- yaml::read_yaml(file.path(dataset, "selected_config.yaml"))
  sample_config <- yaml::read_yaml(file.path(dataset, "samples_config.yaml"))
  pipeline <- load_pipeline_state(dataset)
  counts <- cache_load_data(paste0("expmat_filt_", original, ".qs2"), dataset)
  cells <- cache_load_data(paste0("cells_filt_clust_res_0.5_", original, ".qs2"), dataset)
  for (sample in samples[-1]) {
    dir.create(file.path(processed, sample))
    file.copy(list.files(file.path(processed, original), full.names = TRUE), file.path(processed, sample))
    sample_cells <- data.table::copy(cells); sample_cells[, sample := ..sample]
    data.table::fwrite(sample_cells, file.path(processed, sample, "Cells.csv"))
    entry <- sample_config$samples[[1]]; entry$sample <- sample
    sample_config$samples <- c(sample_config$samples, list(entry))
    pipeline$samples[[sample]] <- new_pipeline_state("Synthetic_Demo", sample)$samples[[sample]]
  }
  yaml::write_yaml(sample_config, file.path(dataset, "samples_config.yaml"))
  for (sample in samples) {
    selected$resolutions[[sample]] <- 0.5
    selected$cna_ref_cells[[sample]] <- "B_cell"
    selected$cna_pot_mal_cells[[sample]] <- "Epithelial"
    selected$cna_ward_ref_cluster[[sample]] <- list(list(k = 7L, cluster = 1L))
    sample_cells <- data.table::copy(cells); sample_cells[, sample := ..sample]
    if (sample != original) {
      cache_save_data(counts, paste0("expmat_filt_", sample, ".qs2"), dataset)
      for (resolution in config$params$resolutions) {
        cache_save_data(sample_cells, paste0("cells_filt_clust_res_", resolution, "_", sample, ".qs2"), dataset)
      }
    }
    for (step in c("clustering", "resolution", "differential_expression", "annotation", "cna_configuration")) {
      pipeline <- transition_pipeline_step(pipeline, step, "completed", sample, force = TRUE)
    }
    if (sample == "Z_omitted") {
      pipeline <- transition_pipeline_step(pipeline, "cna_configuration", "skipped", sample,
        reason = "CNA intentionally omitted.", details = list(omitted_by_user = TRUE), force = TRUE)
      next
    }
    matrix <- data.table::data.table(gene = rownames(counts), chr = rep(sprintf("%02d", 1:3), each = 22), start_pos = seq_len(66))
    for (index in seq_along(sample_cells$cell_name)) {
      data.table::set(matrix, j = sample_cells$cell_name[index], value = sin(seq_len(66) * index / 10) / 5)
    }
    candidate_cells <- sample_cells[is.na(cell_type) | cell_type == "Epithelial", cell_name]
    hc <- stats::hclust(stats::dist(t(as.matrix(matrix[, ..candidate_cells]))), method = "ward.D2")
    cache_save_data(matrix, paste0("cna_matrix_", sample, ".qs2"), dataset)
    cache_save_data(hc, paste0("hclust_", sample, ".qs2"), dataset)
    for (step in c("cna_compute", "cna_cluster_selection")) {
      pipeline <- transition_pipeline_step(pipeline, step, "completed", sample, force = TRUE)
    }
  }
  yaml::write_yaml(selected, file.path(dataset, "selected_config.yaml"))
  save_pipeline_state_at_path(reconcile_pipeline_state_dependencies(pipeline), file.path(dataset, "pipeline_state.yaml"))
  invisible(list(dataset = dataset, samples = samples, config = config))
}

test_that("C07 browser omits CNA from analysis, preserves outputs and reverses through configuration", {
  skip_if_not_installed("shinytest2")
  browser <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  skip_if(is.null(browser) || !nzchar(browser), "no Chromium browser is configured")
  withr::local_envvar(NOT_CRAN = "true")
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  test_app <- make_ui_baseline_app(app_dir)
  fixture <- make_cna_navigation_ui_fixture(test_app)
  dataset <- fixture$dataset; sample <- fixture$samples[[1]]
  files <- c(list.files(file.path(dataset, "processed_data"), recursive = TRUE, full.names = TRUE),
    list.files(file.path(dataset, "results"), recursive = TRUE, full.names = TRUE))
  hashes <- tools::md5sum(files)
  state <- load_pipeline_state(dataset)
  controls <- state$samples[fixture$samples[-1]]
  selected <- yaml::read_yaml(file.path(dataset, "selected_config.yaml"))
  app <- shinytest2::AppDriver$new(app_dir = test_app, name = "c07-analysis-omit", seed = 3988,
    load_timeout = 60000, timeout = 60000)
  on.exit(app$stop(), add = TRUE)
  app$set_inputs(dataset_choice = "Synthetic_Demo", wait_ = FALSE)
  app$click("btn_load_dataset", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$set_inputs(main_nav = "cna_tab", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$click("btn_cna_go_malig_clust", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_identical(app$get_value(input = "cna_main_views"), "cna_view_select_malignant")
  app$click("btn_cna_omit", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_match(app$get_text(".modal-body"), sample, fixed = TRUE)
  expect_match(app$get_text(".modal-body"), "cell labels and historical plots/exports are retained", fixed = TRUE)
  app$click("btn_cancel_omit_cna", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_identical(load_pipeline_state(dataset), state)
  app$click("btn_cna_omit", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$click("btn_confirm_omit_cna", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_identical(app$get_value(input = "cna_main_views"), "cna_view_default")
  expect_match(app$get_text("#cna_status_ui"), "intentionally omitted", fixed = TRUE)
  expect_true(pipeline_cna_is_omitted(load_pipeline_state(dataset), sample))
  expect_false(file.exists(file.path(dataset, "cache", paste0("cna_matrix_", sample, ".qs2"))))
  expect_identical(load_pipeline_state(dataset)$samples[fixture$samples[-1]], controls)
  expect_identical(tools::md5sum(files), hashes)
  saved <- tools::md5sum(file.path(dataset, c("pipeline_state.yaml", "selected_config.yaml")))
  app$run_js("Shiny.setInputValue('btn_confirm_omit_cna', 100, {priority: 'event'});")
  app$wait_for_idle(timeout = 60000)
  expect_identical(tools::md5sum(names(saved)), saved)
  app$click("btn_cna_batch_compute", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  choices <- app$get_js("Array.from(document.querySelectorAll('#cna_batch_samples input')).map(node => node.value)")
  expect_false(sample %in% unlist(choices))
  expect_false("Z_omitted" %in% unlist(choices))
  expect_true("Z_reset" %in% unlist(choices))
  first_logs <- app$get_logs()
  app$stop()
  app <- shinytest2::AppDriver$new(app_dir = test_app, name = "c07-analysis-omit-reload", seed = 3988,
    load_timeout = 60000, timeout = 60000)
  app$set_inputs(dataset_choice = "Synthetic_Demo", wait_ = FALSE)
  app$click("btn_load_dataset", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$set_inputs(main_nav = "cna_tab", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_match(app$get_text("#cna_status_ui"), "intentionally omitted", fixed = TRUE)
  app$set_inputs(main_nav = "anno_tab", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$set_inputs(cna_refs_input = "B_cell", cna_pot_mal_input = "Epithelial", wait_ = FALSE)
  app$click("btn_save_refs", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  restored <- load_pipeline_state(dataset)
  expect_false(pipeline_cna_is_omitted(restored, sample))
  expect_identical(get_pipeline_step(restored, "cna_configuration", sample)$status, "completed")
  expect_identical(get_pipeline_step(restored, "cna_compute", sample)$status, "not_started")
  expect_true(pipeline_step_readiness(restored, "cna_compute", sample)$ready)
  expect_identical(restored$samples[fixture$samples[-1]], controls)
  expect_identical(tools::md5sum(files), hashes)
  expect_identical(yaml::read_yaml(file.path(dataset, "selected_config.yaml"))$cna_ward_ref_cluster, selected$cna_ward_ref_cluster)
  logs <- rbind(first_logs, app$get_logs())
  errors <- logs[logs$level == "error" | grepl("Error|Execution halted", logs$message, ignore.case = TRUE), , drop = FALSE]
  expect_equal(nrow(errors), 0L, info = paste(errors$message, collapse = "\n"))
})

test_that("baseline navigation and writable annotation reload are preserved", {
  skip_if_not_installed("shinytest2")
  skip_if_not_installed("qs2")

  browser_path <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  skip_if(is.null(browser_path) || !nzchar(browser_path), "no Chromium browser is configured")
  withr::local_envvar(NOT_CRAN = "true")

  source_app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  dataset_name <- "Synthetic_Demo"
  browser_variant <- shinytest2::platform_variant()
  baseline_dir <- testthat::test_path(
    "fixtures",
    "ui-baseline",
    browser_variant
  )
  test_app_dir <- make_ui_baseline_app(source_app_dir)

  app <- shinytest2::AppDriver$new(
    app_dir = test_app_dir,
    name = "app-baseline",
    variant = browser_variant,
    seed = 3988,
    width = 1440,
    height = 1000,
    load_timeout = 60000,
    timeout = 60000
  )
  on.exit(app$stop(), add = TRUE)

  expect_equal(app$get_value(input = "main_nav"), "dataset_tab")
  expect_match(app$get_text("body"), "Initialize Pipeline", fixed = TRUE)
  expect_ui_baseline_screenshot(app, baseline_dir, "01-dataset-selection.png")

  app$set_inputs(dataset_choice = dataset_name, wait_ = FALSE)
  app$click(input = "btn_load_dataset", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)

  expect_equal(app$get_value(input = "main_nav"), "menu_tab")
  expect_match(app$get_text("body"), "Pipeline Dashboard", fixed = TRUE)
  app$wait_for_js("$('.shiny-notification').length === 0", timeout = 10000)
  expect_ui_baseline_screenshot(app, baseline_dir, "02-start-menu.png")

  # Review and narrow clustering scope without running scientific computation.
  fixture_dataset_dir <- file.path(test_app_dir, "datasets", dataset_name)
  selection_files <- c(file.path(fixture_dataset_dir, "pipeline_state.yaml"), cache_manifest_paths(fixture_dataset_dir)$primary)
  expect_true(all(file.exists(selection_files)))
  selection_hashes <- tools::md5sum(selection_files)
  app$click(input = "btn_run_clustering", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_match(app$get_text("#shiny-modal"), "Select Samples for Clustering", fixed = TRUE)
  selection_input <- app$get_js("document.querySelector('#shiny-modal [id^=clustering_samples_]').id")
  expect_equal(app$get_value(input = selection_input), "Synthetic_sample")
  expect_false(app$get_js("document.getElementById('confirm_run_clustering').disabled"))
  app$click(input = "clustering_select_clear", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_true(app$get_js("document.getElementById('confirm_run_clustering').disabled"))
  app$click(input = "clustering_select_stale", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_true(app$get_js("document.getElementById('confirm_run_clustering').disabled"))
  app$click(input = "clustering_select_incomplete", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_true(app$get_js("document.getElementById('confirm_run_clustering').disabled"))
  app$click(input = "clustering_select_all", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_equal(app$get_value(input = selection_input), "Synthetic_sample")
  expect_false(app$get_js("document.getElementById('confirm_run_clustering').disabled"))
  expect_ui_baseline_screenshot(app, baseline_dir, "06-clustering-sample-selection.png")
  app$run_js("document.querySelector('#shiny-modal [data-bs-dismiss=modal]').click()")
  app$wait_for_idle(timeout = 60000)
  expect_identical(tools::md5sum(selection_files), selection_hashes)

  app$click(input = "btn_go_res", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$wait_for_js("$('.shiny-notification').length === 0", timeout = 10000)
  expect_equal(app$get_value(input = "main_nav"), "res_tab")
  expect_match(app$get_text("body"), "Resolution Selection", fixed = TRUE)
  expect_ui_baseline_screenshot(app, baseline_dir, "03-resolution-selection.png")

  app$click(input = "btn_back_menu_1", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$click(input = "btn_go_anno", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$wait_for_js("$('.shiny-notification').length === 0", timeout = 10000)
  expect_equal(app$get_value(input = "main_nav"), "anno_tab")
  expect_match(app$get_text("body"), "Manual Cell Type Annotation", fixed = TRUE)
  expect_ui_baseline_screenshot(app, baseline_dir, "04-manual-annotation.png")

  app$click(input = "btn_back_menu_2", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$click(input = "btn_go_cna", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_equal(app$get_value(input = "main_nav"), "cna_tab")
  expect_match(app$get_text("body"), "CNA Pipeline Controls", fixed = TRUE)
  expect_ui_baseline_screenshot(app, baseline_dir, "05-cna-analysis.png")

  app$click(input = "btn_cna_back_menu", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$click(input = "btn_go_anno", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)

  # Exercise a real write in the disposable fixture, then verify both durable
  # representations before restarting the application. Cluster 3 begins
  # unassigned, so this also guarantees that the save changes annotations and
  # invalidates only genuinely downstream CNA work.
  app$set_inputs(cluster = "3", cell_type_input = "Epithelial", wait_ = FALSE)
  app$click(input = "assign_btn", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$click(input = "save_btn", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$wait_for_js("$('.shiny-notification').length === 0", timeout = 10000)

  fixture_dataset_dir <- file.path(test_app_dir, "datasets", dataset_name)
  fixture_cells_path <- file.path(
    fixture_dataset_dir,
    "processed_data",
    "Synthetic_sample",
    "Cells.csv"
  )
  saved_cells <- data.table::fread(fixture_cells_path)
  expect_equal(sum(saved_cells$cell_type == "Epithelial", na.rm = TRUE), 32L)

  clustered_cache_name <- "cells_filt_clust_res_0.5_Synthetic_sample.qs2"
  expect_true(cache_check_valid(clustered_cache_name, fixture_dataset_dir))
  saved_clustered_cells <- cache_load_data(
    clustered_cache_name,
    fixture_dataset_dir
  )
  expect_true(all(
    saved_clustered_cells[clust == 3]$cell_type == "Epithelial"
  ))

  saved_state <- load_pipeline_state(
    fixture_dataset_dir,
    dataset_id = dataset_name,
    sample_names = "Synthetic_sample"
  )
  expect_identical(
    get_pipeline_step(saved_state, "clustering", "Synthetic_sample")$status,
    "completed"
  )
  expect_identical(
    get_pipeline_step(saved_state, "annotation", "Synthetic_sample")$status,
    "completed"
  )

  # Restart against the same temporary workspace and confirm that the UI loads
  # the persisted annotation instead of reverting it or declaring clustering
  # stale. This is the writable save/reload regression missing from the prior
  # read-only browser baseline.
  app$stop()
  app <- shinytest2::AppDriver$new(
    app_dir = test_app_dir,
    name = "app-writable-reload",
    variant = browser_variant,
    seed = 3988,
    width = 1440,
    height = 1000,
    load_timeout = 60000,
    timeout = 60000
  )
  app$set_inputs(dataset_choice = dataset_name, wait_ = FALSE)
  app$click(input = "btn_load_dataset", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$click(input = "btn_go_anno", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$set_inputs(cluster = "3", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_match(
    app$get_text("#current_cluster_annotation"),
    "Current: Epithelial",
    fixed = TRUE
  )

  app_logs <- app$get_logs()
  error_logs <- app_logs[
    app_logs$level == "error" |
      grepl("Error|Execution halted", app_logs$message, ignore.case = TRUE),
    ,
    drop = FALSE
  ]
  expect_equal(nrow(error_logs), 0L, info = paste(error_logs$message, collapse = "\n"))
})

test_that("C01 browser switches dataset contexts with old indices, unsaved edits and archived state", {
  skip_if_not_installed("shinytest2")
  skip_if_not_installed("qs2")
  browser <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  skip_if(is.null(browser) || !nzchar(browser), "no Chromium browser is configured")
  withr::local_envvar(NOT_CRAN = "true")
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  test_app <- make_ui_baseline_app(app_dir)
  suppressWarnings(make_portable_ui_fixture(test_app, "Small"))
  suppressWarnings(make_portable_ui_fixture(test_app, "Archived"))
  large <- file.path(test_app, "datasets", "Synthetic_Demo")
  # The late sample need not be computed: its out-of-range index was sufficient
  # to crash the hidden annotation/preflight observers on the next dataset.
  config <- yaml::read_yaml(file.path(test_app, "general_config.yaml"))
  for (sample in c("Z_extra1", "Z_extra2")) {
    write_mini_sample(file.path(large, "processed_data"), sample)
  }
  samples_path <- file.path(large, config$config_files$samples)
  samples <- yaml::read_yaml(samples_path)
  samples$samples <- c(samples$samples, lapply(c("Z_extra1", "Z_extra2"), make_valid_sample_entry))
  yaml::write_yaml(samples, samples_path)
  # Persist the reconciled records up front; subsequent loads are read-only
  # apart from permitted operation logs.
  selected_path <- file.path(large, config$config_files$selected)
  yaml::write_yaml(reconcile_selected_config(yaml::read_yaml(selected_path),
    c("Synthetic_sample", "Z_extra1", "Z_extra2")), selected_path)
  pipeline_path <- file.path(large, "pipeline_state.yaml")
  pipeline <- yaml::read_yaml(pipeline_path)
  extra <- new_pipeline_state("Synthetic_Demo", c("Z_extra1", "Z_extra2"))
  pipeline$samples <- c(pipeline$samples, extra$samples)
  save_pipeline_state_at_path(pipeline, pipeline_path)
  archived_dir <- file.path(test_app, "datasets", "Archived")
  save_dataset_storage_state_atomic(transition_dataset_storage_state(
    new_dataset_storage_state("Archived"), "archived"), archived_dir)
  app <- shinytest2::AppDriver$new(app_dir = test_app, name = "c01-dataset-switch",
    seed = 3988, load_timeout = 60000, timeout = 60000)
  on.exit(app$stop(), add = TRUE)
  load_dataset <- function(name) {
    app$set_inputs(dataset_choice = name, wait_ = FALSE)
    app$click("btn_load_dataset", wait_ = FALSE)
    app$wait_for_idle(timeout = 60000)
    expect_identical(app$get_value(input = "main_nav"), "menu_tab")
  }
  change_dataset <- function() {
    app$set_inputs(main_nav = "menu_tab", wait_ = FALSE)
    app$wait_for_idle(timeout = 60000)
    app$click("btn_change_dataset", wait_ = FALSE)
    app$wait_for_idle(timeout = 60000)
    expect_identical(app$get_value(input = "main_nav"), "dataset_tab")
  }
  load_dataset("Synthetic_Demo")
  app$click("btn_go_anno", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$set_inputs(cluster = "3", cell_type_input = "Epithelial", wait_ = FALSE)
  app$click("assign_btn", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  # Exercise the existing unsaved-change dialog through the actual controls.
  app$click("btn_back_menu_2", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_identical(app$get_value(input = "main_nav"), "anno_tab")
  expect_match(app$get_text("body"), "Unsaved annotation changes", fixed = TRUE)
  app$click("btn_discard_annotation_navigation", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$set_inputs(main_nav = "anno_tab", sample_idx = "3", cna_sample_idx = "3", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  change_dataset()
  load_dataset("Small")
  expect_identical(app$get_value(input = "sample_idx"), "1")
  expect_identical(app$get_value(input = "cna_sample_idx"), "1")
  app$set_inputs(main_nav = "cna_tab", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_match(app$get_text("#cna_header_text"), "Synthetic_sample", fixed = TRUE)
  app$set_inputs(cna_main_views = "cna_view_select_malignant", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  change_dataset()
  load_dataset("Archived")
  expect_match(app$get_text("body"), "Archived", fixed = TRUE)
  change_dataset()
  load_dataset("Synthetic_Demo")
  app$click("btn_go_anno", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_match(app$get_text("body"), "Synthetic_sample", fixed = TRUE)
  logs <- app$get_logs()
  errors <- logs[logs$level == "error" | grepl("Error|Execution halted", logs$message, ignore.case = TRUE), , drop = FALSE]
  expect_equal(nrow(errors), 0L, info = paste(errors$message, collapse = "\n"))
})

test_that("C04 browser archive/reopen replay shows the current CNA recovery action through final save", {
  skip_if_not_installed("shinytest2")
  browser <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  skip_if(is.null(browser) || !nzchar(browser), "no Chromium browser is configured")
  withr::local_envvar(NOT_CRAN = "true")
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  test_app <- make_ui_baseline_app(app_dir)
  fx <- make_cna_navigation_ui_fixture(test_app)
  dataset <- fx$dataset; target <- fx$samples[[1]]
  pipeline <- load_pipeline_state(dataset)
  selected_path <- file.path(dataset, "selected_config.yaml")
  selected <- yaml::read_yaml(selected_path)
  for (sample in fx$samples) {
    for (folder in c("1_cluster_plots", "2_de_plots", "3_cna_plots")) {
      dir.create(file.path(dataset, "results", sample, folder), recursive = TRUE, showWarnings = FALSE)
    }
    if (sample != target) file.copy(list.files(file.path(dataset, "results", target, "2_de_plots"), full.names = TRUE),
      file.path(dataset, "results", sample, "2_de_plots"))
    write_ui_fixture_plot(file.path(dataset, "results", sample, "1_cluster_plots", paste0("clusters_plot_", sample, "_res_0.5.png")), "Synthetic clusters", sample)
    if (sample == "Z_omitted") next
    selected$cna_thresholds[[sample]] <- list(list(m_x = 0.6, m_y = 0.2, nm_x = 0.3, nm_y = 0.1, y_max = 0.5))
    cells <- cache_load_data(paste0("cells_filt_clust_res_0.5_", sample, ".qs2"), dataset)
    signal <- cells[, .(cell_name, sample, ct = ifelse(is.na(cell_type), "Unassigned", cell_type),
      cna_cor = ifelse(!is.na(cell_type) & cell_type == "B_cell", 0.1, 0.8),
      cna_signal = ifelse(!is.na(cell_type) & cell_type == "B_cell", 0.05, 0.3))]
    cache_save_data(signal, paste0("cna_sig_cor_", sample, "_subclone_1.qs2"), dataset)
    for (step in c("cna_signal_correlation", "cna_thresholds", "cna_assignment")) {
      pipeline <- transition_pipeline_step(pipeline, step, "completed", sample, force = TRUE)
    }
    for (name in c("cna_summary_heatmap_", "cna_umap_assigned_")) {
      write_ui_fixture_plot(file.path(dataset, "results", sample, "3_cna_plots", paste0(name, sample, ".png")), "Synthetic final CNA output", sample)
    }
  }
  yaml::write_yaml(selected, selected_path)
  pipeline <- save_pipeline_state_at_path(pipeline, file.path(dataset, "pipeline_state.yaml"))
  paths <- list(sample_dir_paths = file.path(dataset, "processed_data", fx$samples),
    cell_file_paths = file.path(dataset, "processed_data", fx$samples, "Cells.csv"))
  filenames <- list.files(file.path(dataset, "cache"), pattern = "[.]qs2$")
  payloads <- stats::setNames(lapply(filenames, cache_load_data, dataset_dir_path = dataset), filenames)
  saveRDS(payloads, file.path(test_app, "c04_payloads.rds"))
  storage <- save_dataset_storage_state_atomic(new_dataset_storage_state("Synthetic_Demo"), dataset)
  ready <- dataset_cleanup_readiness(pipeline, paths, selected, selected_path, file.path(dataset, "results"), dataset)
  expect_true(ready$ready, info = paste(ready$reasons, collapse = "; "))
  archive_dataset_cache(dataset, pipeline, storage, ready)
  # Deterministic fixture phases republish known synthetic numerical inputs;
  # decisions/configuration/thresholds/assignment use the real GUI handlers.
  # This isolates status recovery from scientific recalculation variability.
  phase_handler <- c(
    ".c04_dashboard <- register_dashboard_server",
    "register_dashboard_server <- function(input, output, session, state, context) {",
    " .c04_dashboard(input, output, session, state, context)",
    " shiny::observeEvent(input$c04_phase, {",
    "  step <- input$c04_phase; sample <- 'Synthetic_sample'",
    "  stopifnot(step %in% c('clustering', 'differential_expression', 'cna_compute', 'cna_signal_correlation'))",
    "  state$pipeline_state <- persist_pipeline_step_update(state$pipeline_state, state$pipeline_state_path, step, 'in_progress', sample)",
    "  payloads <- readRDS('c04_payloads.rds')",
    "  wanted <- switch(step, clustering = c(paste0('expmat_filt_', sample, '.qs2'), paste0('cells_filt_clust_res_', c(0.5,1), '_', sample, '.qs2')),",
    "    cna_compute = paste0(c('cna_matrix_', 'hclust_'), sample, '.qs2'), cna_signal_correlation = paste0('cna_sig_cor_', sample, '_subclone_1.qs2'), character())",
    "  for (name in wanted) {",
    "   dependencies <- if (step == 'clustering') {",
    "    if (startsWith(name, 'expmat_filt_')) filter_cache_dependencies(state$paths_list, 1L, state$dataset_config)",
    "    else clustering_cache_dependencies(state$paths_list, 1L, state$dataset_config, if (grepl('_res_0.5_', name, fixed = TRUE)) 0.5 else 1)",
    "   } else NULL",
    "   cache_save_data(payloads[[name]], name, state$dataset_dir_path, dependencies = dependencies, producer = 'c04-synthetic-rebuild')",
    "  }",
    "  state$pipeline_state <- persist_pipeline_step_update(state$pipeline_state, state$pipeline_state_path, step, 'completed', sample)",
    " })", "}", "assign('register_dashboard_server', register_dashboard_server, envir = globalenv())")
  entry <- file.path(test_app, "app.R"); lines <- readLines(entry)
  writeLines(append(lines, phase_handler, after = match("app_context <- create_app_context()", lines) - 1L), entry)
  app <- shinytest2::AppDriver$new(app_dir = test_app, name = "c04-reopen-status", seed = 3988,
    load_timeout = 60000, timeout = 60000)
  on.exit(app$stop(), add = TRUE)
  app$set_inputs(dataset_choice = "Synthetic_Demo", wait_ = FALSE)
  app$click("btn_load_dataset", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$click("btn_reopen_dataset", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$set_inputs(dataset_reopen_confirmation = "Synthetic_Demo", wait_ = FALSE)
  app$click("btn_confirm_dataset_reopen", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  controls <- load_pipeline_state(dataset)$samples[c("Z_omitted", "Z_reset")]
  phase <- function(step) {
    app$run_js(paste0("Shiny.setInputValue('c04_phase', '", step, "', {priority: 'event'});"))
    app$wait_for_idle(timeout = 60000)
  }
  phase("clustering")
  app$click("btn_go_res", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$set_inputs(selected_res = "0.5", wait_ = FALSE)
  app$click("btn_save_res", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  phase("differential_expression")
  app$set_inputs(main_nav = "anno_tab", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$click("save_btn", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_identical(get_pipeline_step(load_pipeline_state(dataset), "annotation", target)$status, "completed",
    info = app$get_text("body"))
  app$set_inputs(cna_refs_input = "B_cell", cna_pot_mal_input = "Epithelial", wait_ = FALSE)
  app$click("btn_save_refs", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_true(pipeline_step_readiness(load_pipeline_state(dataset), "cna_compute", target)$ready)
  expect_identical(get_pipeline_step(load_pipeline_state(dataset), "cna_compute", target)$status, "stale")
  app$click("btn_back_menu_2", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  row <- app$get_text(".pipeline-overview-table tbody tr:first-child")
  expect_match(row, "Compute base CNA and heatmaps", fixed = TRUE)
  expect_false(grepl("rerun clustering", row, fixed = TRUE))
  app$set_inputs(main_nav = "cna_tab", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_match(app$get_text("#cna_status_ui"), "Next: Compute base CNA and heatmaps", fixed = TRUE)
  phase("cna_compute")
  expect_match(app$get_text("#cna_status_ui"), "Review and save malignant clusters", fixed = TRUE)
  app$click("btn_cna_go_malig_clust", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$set_inputs(cna_selected_clusters = "1", wait_ = FALSE)
  app$click("btn_cna_save_malignant", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  phase("cna_signal_correlation")
  app$click("btn_cna_go_thresholds", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$click("btn_cna_save_thresholds", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$click("btn_cna_go_summary", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$click("btn_cna_save_summary", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  final <- load_pipeline_state(dataset)
  expect_identical(pipeline_cna_analysis_record(final, target)$status, "completed")
  expect_identical(final$samples[c("Z_omitted", "Z_reset")], controls)
  app$stop()
  app <- shinytest2::AppDriver$new(app_dir = test_app, name = "c04-reopen-status-reload", seed = 3988,
    load_timeout = 60000, timeout = 60000)
  app$set_inputs(dataset_choice = "Synthetic_Demo", wait_ = FALSE)
  app$click("btn_load_dataset", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_identical(pipeline_cna_analysis_record(load_pipeline_state(dataset), target)$status, "completed")
  expect_identical(load_pipeline_state(dataset)$samples[c("Z_omitted", "Z_reset")], controls)
  logs <- app$get_logs()
  errors <- logs[logs$level == "error" | grepl("Error|Execution halted", logs$message, ignore.case = TRUE), , drop = FALSE]
  expect_equal(nrow(errors), 0L, info = paste(errors$message, collapse = "\n"))
})

test_that("C02 browser recovers legacy attempts and retries real clustering without editing cell labels", {
  skip_if_not_installed("shinytest2")
  browser <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  skip_if(is.null(browser) || !nzchar(browser), "no Chromium browser is configured")
  withr::local_envvar(NOT_CRAN = "true")
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  test_app <- make_ui_baseline_app(app_dir)
  dataset <- file.path(test_app, "datasets", "Synthetic_Demo")
  state_path <- file.path(dataset, "pipeline_state.yaml")
  state <- load_pipeline_state(dataset)
  state <- persist_pipeline_step_update(state, state_path, "clustering", "in_progress", "Synthetic_sample",
    invalidate_downstream = TRUE, invalidation_reason = "Interrupted legacy test run.")
  sample_path <- file.path(dataset, "processed_data", "Synthetic_sample")
  scientific <- list.files(sample_path, full.names = TRUE)
  before <- tools::md5sum(scientific)
  app <- shinytest2::AppDriver$new(app_dir = test_app, name = "c02-clustering-recovery",
    seed = 3988, load_timeout = 60000, timeout = 60000)
  on.exit(app$stop(), add = TRUE)
  app$set_inputs(dataset_choice = "Synthetic_Demo", wait_ = FALSE)
  app$click("btn_load_dataset", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_identical(get_pipeline_step(load_pipeline_state(dataset), "clustering", "Synthetic_sample")$status, "in_progress")
  expect_match(app$get_text("#clustering_recovery_control"), "Recover Interrupted Clustering", fixed = TRUE)
  app$click("btn_recover_clustering", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_match(app$get_text(".modal"), "I have stopped the previous clustering", fixed = TRUE)
  hash <- tools::md5sum(state_path)
  app$set_inputs(clustering_recovery_stopped = TRUE, clustering_recovery_dataset = "wrong", wait_ = FALSE)
  app$click("confirm_recover_clustering", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_identical(tools::md5sum(state_path), hash)
  app$set_inputs(clustering_recovery_dataset = "Synthetic_Demo", wait_ = FALSE)
  app$click("confirm_recover_clustering", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  recovered <- load_pipeline_state(dataset)
  expect_identical(get_pipeline_step(recovered, "clustering", "Synthetic_sample")$status, "failed")
  expect_identical(get_pipeline_step(recovered, "clustering", "Synthetic_sample")$attempt, 1L)
  expect_identical(tools::md5sum(scientific), before)
  app$click("btn_run_single_clustering", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  app$click("confirm_run_single_clustering", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  retried <- load_pipeline_state(dataset)
  expect_identical(get_pipeline_step(retried, "clustering", "Synthetic_sample")$status, "completed")
  expect_identical(get_pipeline_step(retried, "clustering", "Synthetic_sample")$attempt, 2L)
  expect_equal(unlist(get_pipeline_step(retried, "clustering", "Synthetic_sample")$details$resolutions), c(0.5, 1))
  expect_identical(tools::md5sum(scientific), before)
  expect_match(app$get_text(".modal"), "Sample clustering complete", fixed = TRUE)
  app$click("btn_after_single_clustering_res", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  expect_identical(app$get_value(input = "main_nav"), "res_tab")
  app$stop()
  # Simulate a prior invocation in this now-reused PID; load must not mistake
  # the current process for that original invocation.
  ended <- begin_clustering_execution("old-invocation")
  end_clustering_execution(ended)
  ended$process_started_at <- as.character(as.numeric(ended$process_started_at) - 100)
  persist_pipeline_step_update(retried, state_path, "clustering", "in_progress", "Synthetic_sample",
    details = list(execution_owner = ended))
  app <- shinytest2::AppDriver$new(app_dir = test_app, name = "c02-restart-auto-recovery",
    seed = 3988, load_timeout = 60000, timeout = 60000)
  app$set_inputs(dataset_choice = "Synthetic_Demo", wait_ = FALSE)
  app$click("btn_load_dataset", wait_ = FALSE)
  app$wait_for_idle(timeout = 60000)
  automatically_recovered <- load_pipeline_state(dataset)
  expect_identical(get_pipeline_step(automatically_recovered, "clustering", "Synthetic_sample")$status, "failed")
  expect_identical(get_pipeline_step(automatically_recovered, "clustering", "Synthetic_sample")$details$interruption_recovery$mode, "owner_ended")
  expect_identical(tools::md5sum(scientific), before)
  logs <- app$get_logs()
  errors <- logs[logs$level == "error" | grepl("Error|Execution halted", logs$message, ignore.case = TRUE), , drop = FALSE]
  expect_equal(nrow(errors), 0L, info = paste(errors$message, collapse = "\n"))
})

test_that("C03 browser keeps status and unavailable samples free of main heatmap work", {
  skip_if_not_installed("shinytest2")
  browser <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
  skip_if(is.null(browser) || !nzchar(browser), "no Chromium browser is configured")
  withr::local_envvar(NOT_CRAN = "true")
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  test_app <- make_ui_baseline_app(app_dir)
  fixture <- make_cna_navigation_ui_fixture(test_app)
  dataset <- fixture$dataset
  original <- fixture$samples[[1]]
  processed <- file.path(dataset, 'processed_data')
  # Instrument only the disposable app, leaving production cache/plot functions
  # intact. Metadata preflight cell reads are distinct from the main CNA matrix.
  entry <- file.path(test_app, "app.R")
  lines <- readLines(entry)
  instrumentation <- c(
    ".c03_heatmap <- cna_heatmap",
    "cna_heatmap <- function(...) { write('heatmap', file = 'c03_trace.log', append = TRUE); .c03_heatmap(...) }",
    "assign('cna_heatmap', cna_heatmap, envir = globalenv())",
    ".c03_cache_load <- cache_load_data",
    "cache_load_data <- function(data_file_name, ...) { if (grepl('^(hclust_|cna_matrix_)', data_file_name)) write(data_file_name, file = 'c03_trace.log', append = TRUE); .c03_cache_load(data_file_name, ...) }",
    "assign('cache_load_data', cache_load_data, envir = globalenv())")
  insertion <- match("app_context <- create_app_context()", lines)
  writeLines(append(lines, instrumentation, after = insertion - 1L), entry)
  trace <- function() {
    path <- file.path(test_app, "c03_trace.log")
    if (file.exists(path)) readLines(path) else character()
  }
  scientific <- list.files(file.path(processed, original), full.names = TRUE)
  before <- tools::md5sum(scientific)
  app <- shinytest2::AppDriver$new(app_dir = test_app, name = "c03-cna-navigation",
    seed = 3988, width = 1440, height = 1000, load_timeout = 60000, timeout = 60000)
  on.exit(app$stop(), add = TRUE)
  app$set_inputs(dataset_choice = "Synthetic_Demo", wait_ = FALSE)
  app$click("btn_load_dataset", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$set_inputs(main_nav = "cna_tab", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_length(trace(), 0)
  expect_match(app$get_text("#btn_cna_status"), "CNA Pipeline Status", fixed = TRUE)
  started <- proc.time()[["elapsed"]]
  app$click("btn_cna_go_malig_clust", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  cold <- proc.time()[["elapsed"]] - started
  expect_identical(app$get_value(input = "cna_main_views"), "cna_view_select_malignant")
  expect_equal(sum(trace() == "heatmap"), 1)
  expect_equal(sum(startsWith(trace(), "hclust_")), 1)
  expect_equal(sum(startsWith(trace(), "cna_matrix_")), 1)
  expect_equal(app$get_value(input = "cna_selected_clusters"), "1")
  app$set_inputs(cna_k_clusters = 8, wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$set_inputs(cna_sample_idx = "2", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_identical(app$get_value(input = "cna_main_views"), "cna_view_default")
  expect_match(app$get_text("#cna_status_ui"), "intentionally omitted", fixed = TRUE)
  expect_equal(sum(trace() == "heatmap"), 1)
  app$set_inputs(cna_sample_idx = "3", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_equal(sum(trace() == "heatmap"), 1)
  app$click("btn_cna_reset", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  app$click("confirm_cna_reset", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_identical(get_pipeline_step(load_pipeline_state(dataset), "cna_compute", "Z_reset")$status, "not_started")
  expect_equal(sum(trace() == "heatmap"), 1)
  app$set_inputs(cna_sample_idx = "1", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_identical(app$get_value(input = "cna_main_views"), "cna_view_default")
  started <- proc.time()[["elapsed"]]
  app$click("btn_cna_go_malig_clust", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  warm <- proc.time()[["elapsed"]] - started
  expect_equal(sum(trace() == "heatmap"), 1)
  expect_equal(app$get_value(input = "cna_selected_clusters"), "1")
  app$click("btn_cna_status", wait_ = FALSE); app$wait_for_idle(timeout = 60000)
  expect_identical(app$get_value(input = "cna_main_views"), "cna_view_default")
  expect_equal(sum(trace() == "heatmap"), 1)
  expect_identical(tools::md5sum(scientific), before)
  message(sprintf("C03 browser synthetic main-heatmap first entry %.2fs; warm re-entry %.2fs; heatmap builds=1", cold, warm))
  logs <- app$get_logs()
  errors <- logs[logs$level == "error" | grepl("Error|Execution halted", logs$message, ignore.case = TRUE), , drop = FALSE]
  expect_equal(nrow(errors), 0L, info = paste(errors$message, collapse = "\n"))
})
