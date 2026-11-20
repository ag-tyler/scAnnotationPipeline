suppressPackageStartupMessages(library(shiny))
suppressPackageStartupMessages(library(bslib))

make_marker_loading_fixture <- function(cancer = "Synthetic Cancer", reverse_rows = FALSE) {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  root <- make_ui_baseline_app(app_dir, .local_envir = parent.frame())
  config_path <- file.path(root, "general_config.yaml")
  config <- yaml::read_yaml(config_path)
  config$paths$resources_dir <- file.path(root, "resources")
  config$paths$datasets_dir <- file.path(root, "datasets")
  yaml::write_yaml(config, config_path)
  env <- new.env(parent = environment())
  for (path in c("app/context.R", "app/state.R", "app/server/dataset_server.R")) {
    eval(parse(file.path(app_dir, path), encoding = "UTF-8"), env)
  }
  context <- env$create_app_context(config_path)
  context$paths$docs_dir <- file.path(root, "docs")
  dataset <- file.path(config$paths$datasets_dir, "Synthetic_Demo")
  dataset_config_path <- file.path(dataset, config$config_files$dataset)
  dataset_config <- yaml::read_yaml(dataset_config_path)
  limits <- list(min_score = 1, min_genes = 2L, max_genes = 3L)
  dataset_config$marker_filter_params <- list(cell_type = limits, cancer_type = limits)
  yaml::write_yaml(dataset_config, dataset_config_path)
  sample_path <- file.path(dataset, config$dataset_paths$processed_dir, dataset_config$std_names$samples)
  samples <- data.table::fread(sample_path)
  samples[, cancer_type := cancer]
  data.table::fwrite(samples, sample_path)

  markers <- data.table::data.table(
    cell_type = c(rep("Strong", 5), rep("Fallback", 4), rep("Cutoff", 4)),
    symbol = c("S_low", "S8", "S6", "S9", "S7", "F_low", "F08", "F3", "F04",
      "C_low", "C2", "C3", "C_lower"),
    combined = c(0.2, 8, 6, 9, 7, 0.1, 0.8, 3, 0.4, 0.2, 2, 3, 0.1)
  )
  malignant <- data.table::data.table(
    cancer_type = c(rep("SYN", 5), rep("HNSCC_HPV-neg", 4), rep("HNSCC_HPV-pos", 4)),
    symbol = c("M_low", "M7", "M9", "M8", "M6", "HN_low", "HN6", "HN9", "HN8",
      "HP_low", "HP7", "HP3", "HP9"),
    combined = c(0.4, 7, 9, 8, 6, 0.1, 6, 9, 8, 0.2, 7, 3, 9)
  )
  if (reverse_rows) {
    markers <- markers[.N:1L]
    malignant <- malignant[.N:1L]
  }
  context$resources$marker_genes <- markers
  context$resources$malignant_markers <- malignant
  context$resources$housekeeping_genes <- c("HK6", "HK1", "HK5", "HK2", "HK4", "HK3")
  context$resources$mt_genes <- c("MT4", "MT1", "MT3", "MT2")
  context$resources$cancer_cell_map <- list(
    cancer_types = list("Synthetic Cancer" = "SYN", "Head and Neck Cancer" = "HNSCC"),
    cell_types = list(SYN = "Epithelial", HNSCC = "Epithelial")
  )
  env$nav_show <- env$nav_hide <- env$updateNavbarPage <- env$removeModal <-
    env$removeNotification <- function(...) invisible(NULL)
  env$showNotification <- function(...) "notification"
  state <- env$create_app_state(context)
  server <- function(input, output, session) {
    env$register_dataset_server(input, output, session, state, context)
  }
  list(context = context, state = state, server = server,
    markers_before = data.table::copy(markers), malignant_before = data.table::copy(malignant))
}

test_that("marker loading sorts scores independently of input order and preserves count/cutoff rules", {
  for (reverse_rows in c(FALSE, TRUE)) {
    fixture <- make_marker_loading_fixture(reverse_rows = reverse_rows)
    shiny::testServer(fixture$server, {
      session$setInputs(dataset_choice = "Synthetic_Demo", btn_load_dataset = 1)
      markers <- fixture$state$complete_markers
      expect_false(is.null(markers))
      expect_identical(markers[cell_type == "Strong", symbol], c("S9", "S8", "S7"))
      expect_identical(markers[cell_type == "Fallback", symbol], c("F3", "F08"))
      expect_identical(markers[cell_type == "Cutoff", symbol], c("C3", "C2"))
      expect_identical(markers[cell_type == "Epithelial", symbol], c("M9", "M8", "M7"))
      expect_identical(markers[cell_type == "Housekeeping_artifact", symbol], fixture$context$resources$housekeeping_genes)
      expect_identical(markers[cell_type == "Mito_artifact", symbol], fixture$context$resources$mt_genes)
      expect_identical(fixture$context$resources$marker_genes, fixture$markers_before)
      expect_identical(fixture$context$resources$malignant_markers, fixture$malignant_before)
    })
  }
})

test_that("HNSCC selection takes the highest-scoring markers within each HPV subtype", {
  fixture <- make_marker_loading_fixture(cancer = "Head and Neck Cancer")
  shiny::testServer(fixture$server, {
    session$setInputs(dataset_choice = "Synthetic_Demo", btn_load_dataset = 1)
    expect_identical(fixture$state$complete_markers[cell_type == "Epithelial", symbol],
      c("HN9", "HN8", "HP9", "HP7"))
  })
})

test_that("an unmapped cancer type leaves ordinary and artifact markers available", {
  fixture <- make_marker_loading_fixture(cancer = "Unmapped cancer")
  shiny::testServer(fixture$server, {
    session$setInputs(dataset_choice = "Synthetic_Demo", btn_load_dataset = 1)
    markers <- fixture$state$complete_markers
    expect_false("Epithelial" %in% markers$cell_type)
    expect_identical(markers[cell_type == "Strong", symbol], c("S9", "S8", "S7"))
    expect_identical(markers[cell_type == "Mito_artifact", symbol], fixture$context$resources$mt_genes)
  })
})
