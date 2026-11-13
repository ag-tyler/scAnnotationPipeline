test_that("C08 cut settings use sample defaults, small-tree bounds and exact saved cuts", {
  expect_equal(cna_cluster_cut_settings(80)$selected, 7)
  expect_equal(cna_cluster_cut_settings(3)$selected, 3)
  expect_equal(cna_cluster_cut_settings(2)$max, 2)
  refs <- list(list(k = 25L, cluster = 3L), list(k = 25L, cluster = 21L))
  expect_equal(cna_cluster_cut_settings(40, refs, TRUE)$selected, 25)
  expect_equal(cna_cluster_cut_settings(40, refs, TRUE)$max, 25)
  expect_equal(cna_cluster_cut_settings(40, refs, FALSE)$selected, 7)
  expect_error(cna_cluster_cut_settings(10, refs, TRUE), "saved CNA cut")
  expect_error(cna_cluster_cut_settings(40, list(list(k = 7L), list(k = 8L)), TRUE), "saved CNA cut")
  expect_error(cna_cluster_cut_settings(1), "at least two")
  initial <- reconcile_cna_cluster_selection("2", NULL, "saved", 25L, refs, TRUE)
  expect_identical(initial$selected, c("3", "21"))
  away <- reconcile_cna_cluster_selection(initial$selected, initial$context, "saved", 7L, refs, TRUE)
  back <- reconcile_cna_cluster_selection(away$selected, away$context, "saved", 25L, refs, TRUE)
  expect_length(away$selected, 0)
  expect_length(back$selected, 0)
  other <- reconcile_cna_cluster_selection("3", back$context, "unsaved", 7L)
  expect_length(other$selected, 0)
  restored <- reconcile_cna_cluster_selection(other$selected, other$context, "saved", 25L, refs, TRUE)
  expect_identical(restored$selected, c("3", "21"))
})

test_that("C08 unsaved axis starts at 0.5 and saved limits/precision stay representable", {
  tables <- list(data.frame(cna_signal = c(0.1, 3.17, Inf, NA)), data.frame(cna_signal = 0.4))
  axis <- cna_signal_axis_summary(tables)
  expect_equal(axis$selected, 0.5)
  expect_equal(axis$recommended, 3.2)
  expect_gte(axis$control_max, 3.2)
  expect_equal(axis$threshold_max, 1)
  expect_gt(axis$data_max, axis$selected)
  expect_equal(cna_signal_axis_summary(list())$selected, 0.5)
  expect_equal(cna_signal_axis_summary(list())$threshold_max, 1)
  wide_view <- list(list(m_y = 0.163, nm_y = 0.15, y_max = 9))
  expect_equal(cna_signal_axis_summary(tables, wide_view)$threshold_max, 1)
  saved <- list(list(m_y = 4.137, nm_y = 4.137, y_max = 0.47), list(m_y = 0.163, nm_y = 0.163, y_max = 1.43))
  before <- saved
  axis <- cna_signal_axis_summary(tables, saved)
  expect_equal(axis$selected, 1.43)
  expect_gte(axis$control_max, 4.137)
  expect_equal(axis$threshold_max, 4.2)
  expect_identical(saved, before)
  expect_equal(cna_threshold_control_step(c(0.4, 0.6), 0.05), 0.05)
  expect_equal(cna_threshold_control_step(c(0.4, 0.43), 0.05), 0.01)
  expect_equal(cna_threshold_control_step(c(0.163, 4.137), 0.01), 0.001)
  expect_equal(cna_threshold_control_step(0.47, 0.1), 0.01)
  expect_true(validate_cna_threshold_pair(0.43, 0.163, 0.4, 0.163)$valid)
  expect_false(validate_cna_threshold_pair(0.4, 0.163, 0.4, 0.163)$valid)
  env <- new.env(parent = environment())
  sys.source(testthat::test_path("..", "..", "app", "ui", "cna_ui.R"), env)
  html <- as.character(env$cna_threshold_slider("legacy", "Saved", -1, 1, 0.43, 0.05))
  expect_match(html, 'data-from="0.43"', fixed = TRUE)
  expect_match(html, 'data-step="0.01"', fixed = TRUE)
  below <- as.character(env$cna_threshold_slider("low", "Saved limit", 0.1, 3, 0.05, 0.1))
  expect_match(below, 'data-min="0.05"', fixed = TRUE)
  outside <- as.character(env$cna_threshold_slider("high", "Saved X", -1, 1, 1.2, 0.05))
  expect_match(outside, 'data-max="1.2"', fixed = TRUE)
})

test_that("C08 rendered Y sliders stay compact and restore higher saved thresholds exactly", {
  suppressPackageStartupMessages(library(shiny))
  suppressPackageStartupMessages(library(bslib))
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  env <- new.env(parent = environment())
  sys.source(file.path(app_dir, "app/ui/cna_ui.R"), env)
  sys.source(file.path(app_dir, "app/server/cna_threshold_server.R"), env)
  env$cache_load_data <- function(...) data.table::data.table(
    cell_name = c("a", "b"), cna_cor = c(0.1, 0.8), cna_signal = c(0.2, 9.1))
  env$cache_save_data <- env$persist_pipeline_step_update <- function(...) stop("Unexpected write while rendering thresholds")
  state <- shiny::reactiveValues(
    paths_list = list(sample_dir_paths = file.path(tempdir(), "sample1")),
    dataset_dir_path = tempdir(),
    pipeline_state = new_pipeline_state("C08_UI", "sample1"),
    live_selected_config = list(
      cna_ward_ref_cluster = list(sample1 = list(list(cluster = 1L, k = 2L))),
      cna_thresholds = list(sample1 = list())
    )
  )
  server <- function(input, output, session) env$register_cna_threshold_server(input, output, session, state, list())
  shiny::testServer(server, {
    for (step in c("cna_configuration", "cna_compute", "cna_cluster_selection", "cna_signal_correlation")) {
      state$pipeline_state <- transition_pipeline_step(state$pipeline_state, step, "completed", "sample1", force = TRUE)
    }
    state$cna_view_context <- cna_analysis_context(state, "sample1", "cna_view_thresholds")
    session$setInputs(main_nav = "cna_tab", cna_main_views = "cna_view_thresholds", cna_sample_idx = "1")
    slider <- function(id) {
      html <- output$cna_dynamic_thresholds_ui$html
      regmatches(html, regexpr(paste0('<input[^>]*id="', id, '"[^>]*>'), html))
    }
    expect_match(slider("cna_thresh_my_1"), 'data-max="1"', fixed = TRUE)
    expect_match(slider("cna_thresh_nmy_1"), 'data-max="1"', fixed = TRUE)
    expect_match(slider("cna_thresh_my_1"), 'data-from="0.16"', fixed = TRUE)
    expect_match(slider("cna_shared_ymax"), 'data-max="9.1"', fixed = TRUE)
    expect_match(slider("cna_shared_ymax"), 'data-from="0.5"', fixed = TRUE)
    config <- shiny::isolate(state$live_selected_config)
    config$cna_thresholds$sample1 <- list(list(m_y = 2.137, nm_y = 1.163, y_max = 7.5))
    state$live_selected_config <- config
    session$flushReact()
    expect_match(slider("cna_thresh_my_1"), 'data-max="2.2"', fixed = TRUE)
    expect_match(slider("cna_thresh_my_1"), 'data-from="2.137"', fixed = TRUE)
    expect_match(slider("cna_thresh_my_1"), 'data-step="0.001"', fixed = TRUE)
    expect_match(slider("cna_thresh_nmy_1"), 'data-from="1.163"', fixed = TRUE)
    expect_match(slider("cna_shared_ymax"), 'data-from="7.5"', fixed = TRUE)
    expect_identical(shiny::isolate(state$live_selected_config), config)
  })
})

test_that("C08 multi-subclone assignments are identical for clipped and saved display scales", {
  root <- withr::local_tempdir()
  cells <- data.table::data.table(cell_name = c("a", "b", "c", "d"), sample = "Sample", cell_type = "Epithelial")
  cache_save_data(cells, "cells_filt_clust_res_0.5_Sample.qs2", root)
  for (i in 1:2) cache_save_data(data.table::data.table(cell_name = cells$cell_name,
    cna_cor = if (i == 1) c(0.8, 0.1, 0.4, 0.8) else c(0.1, 0.1, 0.4, 0.8),
    cna_signal = c(0.2, 0.1, 0.16, 1.2)), paste0("cna_sig_cor_Sample_subclone_", i, ".qs2"), root)
  config <- list(resolutions = list(Sample = 0.5), cna_pot_mal_cells = list(Sample = "Epithelial"),
    cna_thresholds = list(Sample = rep(list(list(m_x = 0.6, m_y = 0.16, nm_x = 0.3, nm_y = 0.16, y_max = 0.5)), 2)))
  baseline <- apply_cna_thresholds("Sample", root, config, save = FALSE)
  expect_identical(baseline$cell_type, c("Malignant", "Epithelial", "Unassigned", "Malignant"))
  expect_identical(baseline$subclone, c(1L, NA_integer_, NA_integer_, NA_integer_))
  for (limit in c(0.1, 0.47, 0.5, 3.2)) {
    for (i in 1:2) config$cna_thresholds$Sample[[i]]$y_max <- limit
    expect_identical(apply_cna_thresholds("Sample", root, config, save = FALSE), baseline)
  }
  expect_identical(cache_load_data("cells_filt_clust_res_0.5_Sample.qs2", root), cells)
})
