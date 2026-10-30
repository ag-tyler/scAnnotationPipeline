test_that("R08 guidance keeps three compact visible rules and optional boundary details", {
  suppressPackageStartupMessages(library(shiny))
  env <- new.env(parent = environment())
  sys.source(testthat::test_path("..", "..", "app", "ui", "cna_ui.R"), env)
  env$cache_load_data <- env$cache_check_valid <- function(...) stop("Unexpected I/O in guidance")
  html <- as.character(env$cna_threshold_guidance_ui())
  visible <- sub("(?s)<details>.*</details>", "", html, perl = TRUE)
  words <- function(value) {
    length(strsplit(trimws(gsub("<[^>]+>", " ", value)), "\\s+")[[1]])
  }
  expect_equal(lengths(regmatches(html, gregexpr("<li>", html, fixed = TRUE))), 3L)
  expect_lte(words(visible), 65L)
  expect_lte(words(html), 100L)
  expect_match(visible, "potentially malignant or Unassigned/NA", fixed = TRUE)
  expect_match(visible, "retain their prior annotation", fixed = TRUE)
  expect_match(visible, "every tested subclone", fixed = TRUE)
  expect_match(visible, "other tested, non-Malignant cells become Unassigned/NA", fixed = TRUE)
  expect_match(visible, "m_x and m_y", fixed = TRUE)
  expect_match(visible, "nm_x and nm_y", fixed = TRUE)
  expect_match(html, "<summary>Boundary details</summary>", fixed = TRUE)
  expect_false(grepl("<details[^>]*\\bopen\\b", html))
  expect_match(html, "Comparisons are strict", fixed = TRUE)
  expect_match(html, "Equal Y thresholds are allowed", fixed = TRUE)
  expect_match(html, "meet neither Y condition for that subclone", fixed = TRUE)
  expect_false(grepl("\\b(red|blue)\\b", html, ignore.case = TRUE))
})

test_that("R08 compact wording agrees with unchanged multi-subclone classification", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  cells <- data.table::data.table(
    cell_name = c("low_all", "mixed", "mal_one", "mal_both", "unassigned_mal",
                  "ineligible", "untested", "equal_y", "prior_mal_equal_y"),
    sample = "sample1",
    cell_type = c(rep("TumorLike", 4), NA, "Immune", "Immune", "TumorLike", "Malignant")
  )
  config <- list(
    resolutions = list(sample1 = 0.5),
    cna_pot_mal_cells = list(sample1 = "TumorLike"),
    cna_thresholds = list(sample1 = rep(list(list(m_x = 0.7, m_y = 0.5, nm_x = 0.3, nm_y = 0.5)), 2))
  )
  signal1 <- data.table::data.table(
    cell_name = cells$cell_name[-7],
    cna_cor = c(0.1, 0.1, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8),
    cna_signal = c(0.4, 0.4, 0.6, 0.6, 0.6, 0.6, 0.5, 0.5)
  )
  signal2 <- data.table::copy(signal1)
  signal2[cell_name == "mixed", `:=`(cna_cor = 0.5, cna_signal = 0.5)]
  signal2[cell_name %in% c("mal_one", "unassigned_mal"), `:=`(cna_cor = 0.1, cna_signal = 0.4)]
  cache_name <- "cells_filt_clust_res_0.5_sample1.qs2"
  cache_save_data(cells, cache_name, dataset_dir)
  cache_save_data(signal1, "cna_sig_cor_sample1_subclone_1.qs2", dataset_dir)
  cache_save_data(signal2, "cna_sig_cor_sample1_subclone_2.qs2", dataset_dir)
  paths <- list.files(file.path(dataset_dir, "cache"), full.names = TRUE)
  before <- tools::md5sum(paths)
  preview <- apply_cna_thresholds("sample1", dataset_dir, config, save = FALSE)
  expect_identical(preview$cell_type,
    c("TumorLike", "Unassigned", "Malignant", "Malignant", "Malignant",
      "Unassigned", "Immune", "Unassigned", "Malignant"))
  expect_identical(preview$subclone[c(3, 5)], c(1L, 1L))
  expect_true(all(is.na(preview$subclone[c(1, 2, 4, 6, 7, 8, 9)])))
  expect_identical(tools::md5sum(paths), before)
  expect_identical(cells$cell_type,
    c(rep("TumorLike", 4), NA_character_, "Immune", "Immune", "TumorLike", "Malignant"))
  finalized <- apply_cna_thresholds("sample1", dataset_dir, config, save = TRUE)
  reloaded <- cache_load_data(cache_name, dataset_dir)
  expect_identical(finalized$cell_type, preview$cell_type)
  expect_identical(reloaded$cell_type, preview$cell_type)
  expect_identical(reloaded$subclone, preview$subclone)
})

test_that("R08 guidance stays beside each subclone's sliders without extra cache work", {
  suppressPackageStartupMessages(library(shiny))
  suppressPackageStartupMessages(library(bslib))
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  env <- new.env(parent = environment())
  sys.source(file.path(app_dir, "app/ui/cna_ui.R"), env)
  sys.source(file.path(app_dir, "app/server/cna_threshold_server.R"), env)
  loads <- 0L
  env$cache_load_data <- function(...) {
    loads <<- loads + 1L
    data.table::data.table(cell_name = c("cell1", "cell2"), cna_cor = c(0.1, 0.8), cna_signal = c(0.4, 0.6))
  }
  env$cache_save_data <- env$persist_pipeline_step_update <- function(...) stop("Unexpected write while rendering guidance")
  state <- shiny::reactiveValues(
    paths_list = list(sample_dir_paths = file.path(tempdir(), "sample1")),
    dataset_dir_path = tempdir(),
    pipeline_state = new_pipeline_state("R08_UI", "sample1"),
    live_selected_config = list(
      cna_ward_ref_cluster = list(sample1 = list(list(cluster = 1L, k = 2L), list(cluster = 2L, k = 2L))),
      cna_thresholds = list(sample1 = rep(list(list(m_x = 0.7, m_y = 0.5, nm_x = 0.3, nm_y = 0.5)), 2))
    )
  )
  server <- function(input, output, session) env$register_cna_threshold_server(input, output, session, state, list())
  shiny::testServer(server, {
    session$setInputs(cna_sample_idx = "1")
    html <- output$cna_dynamic_thresholds_ui$html
    count <- function(pattern) lengths(regmatches(html, gregexpr(pattern, html, fixed = TRUE)))
    expect_identical(count("cna-threshold-guidance"), 2L)
    expect_identical(count("Gray zone:"), 2L)
    expect_identical(count("<summary>Boundary details</summary>"), 2L)
    for (i in 1:2) {
      expect_match(html, paste0('id="cna_thresh_my_', i, '"'), fixed = TRUE)
      expect_match(html, paste0('id="cna_thresh_nmy_', i, '"'), fixed = TRUE)
    }
    expect_identical(loads, 2L)
    expect_identical(output$cna_dynamic_thresholds_ui$html, html)
    expect_identical(loads, 2L)
  })
})
