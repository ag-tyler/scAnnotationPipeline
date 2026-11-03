suppressPackageStartupMessages(library(shiny))
suppressPackageStartupMessages(library(bslib))

make_c03_fixture <- function(root) {
  env <- new.env(parent = environment())
  app <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  for (file in c("app/state.R", "app/ui/cna_ui.R",
    paste0("app/server/cna_", c("status", "compute", "cluster", "threshold", "summary", "reset"), "_server.R"),
    "app/server/cna_server.R")) sys.source(file.path(app, file), env)
  env$reads <- character(); env$heatmaps <- 0L; env$navigation <- list()
  env$nav_select <- function(id, selected) env$navigation <- c(env$navigation, list(c(id, selected)))
  env$record_state_event <- env$removeNotification <- env$removeModal <- env$showModal <- function(...) invisible(NULL)
  env$showNotification <- function(...) "notification"
  env$cna_sample_preflight <- function(sample_name, ..., pipeline_state) {
    omitted <- isTRUE(get_pipeline_step(pipeline_state, "cna_configuration", sample_name)$details$omitted_by_user)
    list(status = if (omitted) "omitted" else "eligible", eligible = !omitted, reasons = character(),
      counts = list(reference = 1, configured_candidate = 2, unassigned = 0))
  }
  samples <- c("computed", "omitted", "reset")
  dirs <- file.path(root, "processed_data", samples)
  for (i in seq_along(samples)) {
    dir.create(dirs[i], recursive = TRUE)
    data.table::fwrite(data.table::data.table(cell_name = paste0(samples[i], 1:3), sample = samples[i],
      cell_type = c("T_cell", "Epithelial", "Epithelial")), file.path(dirs[i], "Cells.csv"))
  }
  state <- new_pipeline_state(basename(root), samples)
  state <- transition_pipeline_step(state, "standardization", "completed", force = TRUE)
  for (sample in samples) for (step in PIPELINE_SAMPLE_STEPS) {
    state <- transition_pipeline_step(state, step, "completed", sample, force = TRUE)
  }
  state <- transition_pipeline_step(state, "cna_configuration", "skipped", "omitted",
    reason = "CNA intentionally omitted.", details = list(omitted_by_user = TRUE), force = TRUE)
  state <- reconcile_pipeline_state_dependencies(state)
  selected <- setup_selected_config(samples)
  for (sample in samples) {
    selected$resolutions[[sample]] <- 0.5
    selected$cna_ref_cells[[sample]] <- "T_cell"
    selected$cna_pot_mal_cells[[sample]] <- "Epithelial"
    selected$cna_ward_ref_cluster[[sample]] <- list(list(k = 2L, cluster = 1L))
    selected$cna_thresholds[[sample]] <- list(list(m_x = 0.6, m_y = 0.2, nm_x = 0.3, nm_y = 0.1))
  }
  rv <- env$create_app_state(list())
  rv$dataset_dir_path <- root; rv$results_dir_path <- file.path(root, "results")
  dir.create(file.path(root, "results"))
  rv$paths_list <- list(sample_dir_paths = dirs, cell_file_paths = file.path(dirs, "Cells.csv"))
  rv$pipeline_state_path <- file.path(root, "pipeline_state.yaml")
  rv$pipeline_state <- save_pipeline_state_atomic(state, root)
  rv$storage_state <- new_dataset_storage_state(basename(root))
  rv$live_selected_config <- selected; rv$config <- list(selected = selected)
  rv$selected_config_path <- file.path(root, "selected_config.yaml")
  yaml::write_yaml(selected, file.path(root, "selected_config.yaml"))
  env$cache_load_data <- function(filename, ...) {
    env$reads <- c(env$reads, filename)
    sample <- samples[vapply(samples, function(s) grepl(s, filename, fixed = TRUE), logical(1))][1]
    if (identical(sample, "omitted") ||
        !identical(get_pipeline_step(shiny::isolate(rv$pipeline_state), "cna_compute", sample)$status, "completed")) {
      stop("Unexpected unavailable cache read")
    }
    if (startsWith(filename, "cna_sig_cor_")) {
      return(data.table::data.table(cell_name = paste0(sample, 1:3), cna_cor = c(0.1, 0.7, 0.8), cna_signal = c(0.1, 0.2, 0.3)))
    }
    cells <- load_cells(file.path(root, "processed_data", sample, "Cells.csv"))
    if (startsWith(filename, "hclust_")) {
      return(stats::hclust(stats::dist(matrix(1:9, nrow = 3, dimnames = list(cells$cell_name, NULL)))))
    }
    cells
  }
  env$load_expdt_from_cna_matrix <- function(sample, ...) {
    env$reads <- c(env$reads, paste0("matrix_", sample))
    data.table::CJ(gene = paste0("gene", 1:24), cell_name = paste0(sample, 1:3))[, `:=`(chr = "01", cna = 0.5)]
  }
  env$dendrogram_plot <- env$cluster_or_cell_type_bar_plot <- function(...) ggplot2::ggplot()
  env$cna_heatmap <- function(...) { env$heatmaps <- env$heatmaps + 1L; ggplot2::ggplot() }
  env$cache_check_valid <- function(...) FALSE
  env$state <- rv
  env$server <- function(input, output, session) env$register_cna_server(input, output, session, rv, list(resources = list()))
  env
}

test_that("C03 status, omitted and reset navigation never reads a main heatmap", {
  fx <- make_c03_fixture(withr::local_tempdir()); rv <- fx$state
  shiny::testServer(fx$server, {
    session$setInputs(main_nav = "cna_tab", cna_sample_idx = "1", cna_k_clusters = 2,
      cna_main_views = "cna_view_default")
    expect_match(output$cna_status_ui$html, "Pipeline Status", fixed = TRUE)
    expect_length(fx$reads, 0); expect_identical(fx$heatmaps, 0L)
    expect_error(output$cna_cluster_navigator_ui, class = "shiny.silent.error")
    session$setInputs(btn_cna_go_malig_clust = 1)
    session$setInputs(cna_main_views = "cna_view_select_malignant")
    html <- output$cna_cluster_navigator_ui$html
    expect_match(html, 'value="1" checked', fixed = TRUE)
    expect_identical(fx$heatmaps, 1L); expect_length(fx$reads, 3)
    # The browser still reports the old malignant view while the new sample is
    # already selected. Even forced evaluation must not reach its absent cache.
    session$setInputs(cna_sample_idx = "2")
    expect_identical(rv$cna_view_context$view, "cna_view_default")
    expect_error(output$cna_cluster_navigator_ui, class = "shiny.silent.error")
    expect_error(output$cna_dynamic_thresholds_ui, class = "shiny.silent.error")
    expect_match(output$cna_status_ui$html, "intentionally omitted", fixed = TRUE)
    expect_length(fx$reads, 3); expect_identical(fx$heatmaps, 1L)
    session$setInputs(cna_sample_idx = "3")
    expect_error(output$cna_cluster_navigator_ui, class = "shiny.silent.error")
    session$setInputs(btn_cna_reset = 1, confirm_cna_reset = 1)
    expect_identical(get_pipeline_step(rv$pipeline_state, "cna_compute", "reset")$status, "not_started")
    expect_error(output$cna_cluster_navigator_ui, class = "shiny.silent.error")
    expect_length(fx$reads, 3)
    session$setInputs(cna_sample_idx = "1", cna_selected_clusters = "2")
    expect_error(output$cna_cluster_navigator_ui, class = "shiny.silent.error")
    session$setInputs(btn_cna_go_malig_clust = 2)
    restored <- output$cna_cluster_navigator_ui$html
    expect_match(restored, 'value="1" checked', fixed = TRUE)
    expect_length(fx$reads, 3); expect_identical(fx$heatmaps, 1L)
    session$setInputs(btn_cna_status = 1)
    expect_identical(rv$cna_view_context$view, "cna_view_default")
    expect_error(output$cna_cluster_navigator_ui, class = "shiny.silent.error")
    session$setInputs(btn_cna_go_malig_clust = 3)
    output$cna_cluster_navigator_ui
    session$setInputs(cna_k_clusters = 3)
    session$elapse(1000)
    output$cna_cluster_navigator_ui
    session$setInputs(cna_selected_clusters = "1")
    output$cna_cluster_selection_summary
    expect_identical(fx$heatmaps, 1L); expect_length(fx$reads, 3)
  })
})

test_that("C03 an eligible sample waits for explicit entry; threshold data also waits for its view", {
  fx <- make_c03_fixture(withr::local_tempdir()); rv <- fx$state
  scientific <- shiny::isolate(c(rv$paths_list$cell_file_paths, rv$pipeline_state_path, rv$selected_config_path))
  hashes <- tools::md5sum(scientific)
  shiny::testServer(fx$server, {
    session$setInputs(main_nav = "cna_tab", cna_sample_idx = "1", cna_k_clusters = 2,
      cna_main_views = "cna_view_default", cna_thresh_mx_1 = 0.6, cna_thresh_my_1 = 0.2,
      cna_thresh_nmx_1 = 0.3, cna_thresh_nmy_1 = 0.1, cna_shared_ymax = 0.5)
    expect_error(output$cna_dynamic_thresholds_ui, class = "shiny.silent.error")
    expect_length(fx$reads, 0)
    session$setInputs(btn_cna_go_malig_clust = 1, cna_main_views = "cna_view_select_malignant")
    output$cna_cluster_navigator_ui
    session$setInputs(cna_sample_idx = "3")
    expect_error(output$cna_cluster_navigator_ui, class = "shiny.silent.error")
    expect_identical(fx$heatmaps, 1L)
    session$setInputs(btn_cna_go_malig_clust = 2)
    output$cna_cluster_navigator_ui
    expect_identical(fx$heatmaps, 2L)
    session$setInputs(btn_cna_status = 1, cna_main_views = "cna_view_default")
    n <- length(fx$reads)
    expect_error(output$cna_dynamic_thresholds_ui, class = "shiny.silent.error")
    session$setInputs(btn_cna_go_thresholds = 1)
    session$setInputs(cna_main_views = "cna_view_thresholds")
    output$cna_dynamic_thresholds_ui
    expect_length(fx$reads, n + 1L)
    session$setInputs(cna_thresh_my_1 = 0.3)
    output$cna_dynamic_thresholds_ui
    expect_length(fx$reads, n + 1L)
    session$setInputs(btn_cna_status = 2, cna_main_views = "cna_view_default")
    expect_error(output$cna_dynamic_thresholds_ui, class = "shiny.silent.error")
    expect_length(fx$reads, n + 1L)
    session$setInputs(btn_cna_save_thresholds = 1)
    expect_identical(tools::md5sum(scientific), hashes)
    rv$annotation_dirty <- TRUE
    session$setInputs(btn_cna_go_malig_clust = 3)
    expect_identical(rv$cna_view_context$view, "cna_view_default")
    rv$annotation_dirty <- FALSE
    session$setInputs(btn_cna_reset = 1)
    session$setInputs(cna_sample_idx = "1", confirm_cna_reset = 1)
    expect_identical(tools::md5sum(scientific), hashes)
  })
})

test_that("C03 stale summary view messages cannot load previews for a new sample", {
  fx <- make_c03_fixture(withr::local_tempdir()); rv <- fx$state
  fingerprints <- 0L; previews <- 0L
  fx$cna_preview_fingerprint <- function(...) { fingerprints <<- fingerprints + 1L; "current" }
  fx$preview_cna_summary <- function(...) {
    previews <<- previews + 1L
    list(pre_scatter_plots = list(), post_scatter_plots = list(),
      pre_umap_plot = ggplot2::ggplot(), umap_plot = ggplot2::ggplot(), summary_heatmap = ggplot2::ggplot())
  }
  shiny::testServer(fx$server, {
    session$setInputs(main_nav = "cna_tab", cna_sample_idx = "1", cna_main_views = "cna_view_default")
    session$setInputs(cna_main_views = "cna_view_summary")
    expect_identical(fingerprints, 0L); expect_identical(previews, 0L)
    session$setInputs(btn_cna_go_summary = 1)
    expect_identical(fingerprints, 1L); expect_identical(previews, 1L)
    expect_identical(rv$cna_preview_sample, "computed")
    session$setInputs(btn_cna_status = 1)
    expect_identical(fingerprints, 1L); expect_identical(previews, 1L)
    session$setInputs(cna_sample_idx = "2", btn_cna_preview_summary = 1)
    expect_null(rv$cna_preview_res)
    expect_identical(fingerprints, 1L); expect_identical(previews, 1L)
    expect_length(fx$reads, 0)
  })
})
