app_dir_f11 <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
suppressPackageStartupMessages(library(shiny))
suppressPackageStartupMessages(library(bslib))
sys.source(file.path(app_dir_f11, "app/ui/cna_ui.R"), envir = environment())


test_that("F11 Y-threshold normalization permits equality and clamps the moved boundary", {
  expect_identical(
    normalize_cna_y_threshold_pair(0.5, 0.5, changed = "nm_y"),
    list(m_y = 0.5, nm_y = 0.5)
  )
  expect_identical(
    normalize_cna_y_threshold_pair(0.7, 0.3, changed = "m_y"),
    list(m_y = 0.7, nm_y = 0.3)
  )
  expect_identical(
    normalize_cna_y_threshold_pair(0.4, 0.6, changed = "nm_y"),
    list(m_y = 0.6, nm_y = 0.6)
  )
  expect_identical(
    normalize_cna_y_threshold_pair(0.4, 0.6, changed = "m_y"),
    list(m_y = 0.4, nm_y = 0.4)
  )
})


test_that("F11 independent subclone pairs retain their own valid values", {
  pairs <- list(
    normalize_cna_y_threshold_pair(0.4, 0.4, changed = "nm_y"),
    normalize_cna_y_threshold_pair(0.9, 0.2, changed = "m_y")
  )
  expect_identical(pairs[[1]], list(m_y = 0.4, nm_y = 0.4))
  expect_identical(pairs[[2]], list(m_y = 0.9, nm_y = 0.2))
})


test_that("F11 save validation documents strict X and inclusive Y rules", {
  expect_true(validate_cna_threshold_pair(0.7, 0.5, 0.3, 0.5)$valid)
  expect_true(validate_cna_threshold_pair(0.7, 0.7, 0.3, 0.3)$valid)

  invalid_y <- validate_cna_threshold_pair(0.7, 0.49, 0.3, 0.5)
  expect_false(invalid_y$valid)
  expect_match(invalid_y$reason, "m_y >= nm_y", fixed = TRUE)
  expect_match(invalid_y$reason, "equal Y thresholds are allowed", fixed = TRUE)

  invalid_x <- validate_cna_threshold_pair(0.3, 0.5, 0.3, 0.5)
  expect_false(invalid_x$valid)
  expect_match(invalid_x$reason, "m_x > nm_x", fixed = TRUE)

  missing_value <- validate_cna_threshold_pair(NULL, 0.5, 0.3, 0.5)
  expect_false(missing_value$valid)
  expect_match(missing_value$reason, "All four", fixed = TRUE)
})


test_that("F11 equal Y boundary preserves strict classification semantics", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  cells <- data.table::data.table(
    cell_name = c("above", "mal_boundary", "below", "nonmal_boundary", "ineligible"),
    sample = "sample1",
    cell_type = c("TumorLike", "TumorLike", "TumorLike", "TumorLike", "Immune")
  )
  signal <- data.table::data.table(
    cell_name = cells$cell_name,
    cna_cor = c(0.8, 0.8, 0.1, 0.1, 0.8),
    cna_signal = c(0.6, 0.5, 0.4, 0.5, 0.6)
  )
  config <- list(
    resolutions = list(sample1 = 0.5),
    cna_pot_mal_cells = list(sample1 = "TumorLike"),
    cna_thresholds = list(sample1 = list(list(
      m_x = 0.7, m_y = 0.5, nm_x = 0.3, nm_y = 0.5
    )))
  )
  cache_save_data(cells, "cells_filt_clust_res_0.5_sample1.qs2", dataset_dir)
  cache_save_data(signal, "cna_sig_cor_sample1_subclone_1.qs2", dataset_dir)

  preview <- apply_cna_thresholds("sample1", dataset_dir, config, save = FALSE)
  type_for <- function(data, cell) data$cell_type[match(cell, data$cell_name)]
  expect_identical(type_for(preview, "above"), "Malignant")
  expect_identical(type_for(preview, "mal_boundary"), "Unassigned")
  expect_identical(type_for(preview, "below"), "TumorLike")
  expect_identical(type_for(preview, "nonmal_boundary"), "Unassigned")
  expect_false(identical(type_for(preview, "ineligible"), "Malignant"))

  finalized <- apply_cna_thresholds("sample1", dataset_dir, config, save = TRUE)
  reloaded <- cache_load_data("cells_filt_clust_res_0.5_sample1.qs2", dataset_dir)
  expect_identical(finalized$cell_type, preview$cell_type)
  expect_identical(reloaded$cell_type, preview$cell_type)
})


test_that("F11 guidance explains eligibility, safe retention, and the gray zone without colour", {
  html <- as.character(cna_threshold_guidance_ui())
  expect_match(html, "potentially malignant", fixed = TRUE)
  expect_match(html, "Unassigned/NA", fixed = TRUE)
  expect_match(html, "retain their prior annotation", fixed = TRUE)
  expect_match(html, "every tested subclone", fixed = TRUE)
  expect_match(html, "m_x and m_y", fixed = TRUE)
  expect_match(html, "nm_x and nm_y", fixed = TRUE)
  expect_match(html, "Comparisons are strict", fixed = TRUE)
  expect_match(html, "exactly on their shared boundary", fixed = TRUE)
  expect_false(grepl("\\b(red|blue)\\b", html, ignore.case = TRUE))
})


test_that("F11 linked sliders use inclusive Y bounds while retaining strict X bounds", {
  server_text <- paste(
    readLines(file.path(app_dir_f11, "app/server/cna_threshold_server.R"), warn = FALSE),
    collapse = "\n"
  )
  expect_match(server_text, 'min = nm_y, value = normalized$m_y', fixed = TRUE)
  expect_match(server_text, 'max = m_y, value = normalized$nm_y', fixed = TRUE)
  expect_false(grepl('cna_thresh_nmy_", i)]] + step_val', server_text, fixed = TRUE))
  expect_false(grepl('cna_thresh_my_", i)]] - step_val', server_text, fixed = TRUE))
  expect_match(server_text, 'min = input[[paste0("cna_thresh_nmx_", i)]] + 0.05', fixed = TRUE)
  expect_match(server_text, 'max = input[[paste0("cna_thresh_mx_", i)]] - 0.05', fixed = TRUE)
  expect_match(server_text, "value = def_my, step = 0.01", fixed = TRUE)
  expect_match(server_text, "value = def_nmy, step = 0.01", fixed = TRUE)
  expect_match(server_text, "cna_threshold_guidance_ui()", fixed = TRUE)
})


test_that("F11 leaves CNA computation progress and return navigation unchanged", {
  compute_text <- paste(
    readLines(file.path(app_dir_f11, "app/server/cna_compute_server.R"), warn = FALSE),
    collapse = "\n"
  )
  expect_match(compute_text, 'withProgress(message = paste("CNA:"', fixed = TRUE)
  expect_match(compute_text, 'nav_select("cna_main_views", "cna_view_select_malignant")', fixed = TRUE)
})
