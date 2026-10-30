test_that("R03 annotation labels normalize only their display representation", {
  labels <- factor(c(NA, "", "  ", "NA", "Unassigned", "T cell"))
  expect_identical(
    annotation_plot_labels(labels),
    c(rep("Unassigned", 5), "T cell")
  )
  expect_identical(as.character(labels), c(NA_character_, "", "  ", "NA", "Unassigned", "T cell"))
})

test_that("R03 partial and wholly unassigned plots retain every cell and a grey legend key", {
  skip_if_not_installed("randomcoloR")
  skip_if_not_installed("cowplot")
  for (labels in list(
    c("T cell", NA, "", "NA", "Unassigned"),
    rep(NA_character_, 5),
    c("T cell", "B cell", "T cell", "B cell", "T cell")
  )) {
    cells <- data.table::data.table(
      umap1 = seq_along(labels), umap2 = rev(seq_along(labels)), cell_type = labels
    )
    original <- data.table::copy(cells)
    plot <- plot_clusters(cells, "Annotation", cluster_col = cell_type)
    built <- ggplot2::ggplot_build(plot)
    scale <- built$plot$scales$get_scales("colour")
    expect_identical(as.character(scale$get_breaks()), natural_cluster_order(annotation_plot_labels(labels)))
    expect_equal(nrow(built$data[[1]]), length(labels))
    expect_false(anyNA(built$data[[1]]$colour))
    if (any(annotation_plot_labels(labels) == "Unassigned")) {
      expect_identical(unname(scale$map("Unassigned")), "#BDBDBD")
      expect_true(all(built$data[[1]]$colour[annotation_plot_labels(labels) == "Unassigned"] == "#BDBDBD"))
    }
    expect_no_error(ggplot2::ggplotGrob(plot))
    expect_equal(cells, original)
  }
})

make_r03_preview_fixture <- function(dataset_dir) {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  env <- new.env(parent = environment())
  sys.source(file.path(app_dir, "app/state.R"), envir = env)
  env$register_single_sample_de_handlers <- function(...) invisible(NULL)
  env$record_state_event <- function(...) invisible(NULL)
  env$notifications <- list()
  env$navigation <- list()
  env$showNotification <- function(ui, type = "default", ...) {
    env$notifications <- c(env$notifications, list(list(text = as.character(ui), type = type)))
    "notification"
  }
  env$removeNotification <- function(...) invisible(NULL)
  env$nav_select <- function(...) {
    env$navigation <- c(env$navigation, list(list(...)))
  }
  sys.source(file.path(app_dir, "app/server/annotation_server.R"), envir = env)
  cells <- data.table::data.table(
    cell_name = c("cell1", "cell2", "cell3"), sample = "sample1",
    complexity = c(10, 12, 14), umap1 = c(0, 1, 2), umap2 = c(1, 0, 1),
    clust = c(0L, 1L, 2L), cell_type = NA_character_
  )
  sample_dir <- file.path(dataset_dir, "processed_data", "sample1")
  dir.create(sample_dir, recursive = TRUE)
  cells_path <- file.path(sample_dir, "Cells.csv")
  data.table::fwrite(cells, cells_path)
  cache_save_data(cells, "cells_filt_clust_res_0.5_sample1.qs2", dataset_dir)
  pipeline <- new_pipeline_state("Synthetic_R03", "sample1")
  for (step in c("clustering", "resolution", "differential_expression")) {
    pipeline <- transition_pipeline_step(pipeline, step, "completed", sample = "sample1", force = TRUE)
  }
  state_path <- file.path(dataset_dir, "pipeline_state.yaml")
  pipeline <- save_pipeline_state_at_path(pipeline, state_path)
  selected <- list(
    resolutions = list(sample1 = 0.5), sample_notes = list(sample1 = ""),
    cna_ref_cells = list(sample1 = list()), cna_pot_mal_cells = list(sample1 = list())
  )
  selected_path <- file.path(dataset_dir, "selected_config.yaml")
  yaml::write_yaml(selected, selected_path)
  state <- env$create_app_state(list(), session_id = "r03-preview")
  state$paths_list <- list(sample_dir_paths = sample_dir, cell_file_paths = cells_path)
  state$dataset_dir_path <- dataset_dir
  results_dir <- file.path(dataset_dir, "results")
  state$results_dir_path <- results_dir
  dir.create(file.path(results_dir, "sample1", "2_de_plots"), recursive = TRUE)
  state$pipeline_state <- pipeline
  state$pipeline_state_path <- state_path
  state$live_selected_config <- selected
  state$selected_config_path <- selected_path
  state$config <- list(selected = selected)
  state$samples_config <- list(samples = list(list(sample = "sample1", cancer_type = "Synthetic")))
  state$complete_markers <- data.table::data.table(cell_type = "T cell", gene = "G1")
  state$sample_name <- "sample1"
  state$res <- 0.5
  state$cells_raw <- data.table::copy(cells)
  state$cells_filt <- data.table::copy(cells)
  state$annotation_loaded_index <- 1
  env$state <- state
  env$server <- function(input, output, session) {
    env$register_annotation_server(input, output, session, state, list())
  }
  env
}

r03_disk_snapshot <- function(dataset_dir) {
  paths <- sort(list.files(dataset_dir, all.files = TRUE, recursive = TRUE, full.names = TRUE))
  tools::md5sum(paths)
}

test_that("R03 unavailable, empty and failed previews warn without mutating workflow or caches", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("qs2")
  suppressPackageStartupMessages(library(shiny))
  dataset_dir <- withr::local_tempdir()
  fixture <- make_r03_preview_fixture(dataset_dir)
  state <- fixture$state
  shiny::testServer(fixture$server, {
    session$setInputs(main_nav = "anno_tab", sample_idx = "1")
    original_cells <- data.table::copy(state$cells_filt)
    original_state <- state$pipeline_state
    disk <- r03_disk_snapshot(dataset_dir)
    preview_attempt <- 0L
    for (cells in list(
      NULL, original_cells[0], original_cells[, !"cell_type"], original_cells,
      transform(as.data.frame(original_cells), cell_type = c("", "NA", "Unassigned")),
      transform(as.data.frame(original_cells), cell_type = c("T cell", NA, NA))[, -5]
    )) {
      state$cells_filt <- cells
      preview_attempt <- preview_attempt + 1L
      session$setInputs(preview_btn = preview_attempt)
      session$flushReact()
      expect_null(state$final_plot)
      expect_identical(tail(fixture$notifications, 1)[[1]]$type, "warning")
      expect_length(fixture$navigation, 0)
      expect_identical(state$pipeline_state, original_state)
      expect_identical(r03_disk_snapshot(dataset_dir), disk)
      expect_false(isTRUE(session$isClosed()))
    }
    expect_match(tail(fixture$notifications, 1)[[1]]$text, "Could not generate annotation preview")
    # A drawing-time failure is also caught, not just missing-column errors.
    state$cells_filt <- data.table::copy(original_cells)
    state$cells_filt[, cell_type := c("T cell", NA, NA)]
    fixture$plot_clusters <- function(...) {
      ggplot2::ggplot(data.frame(x = 1), ggplot2::aes(x, missing_axis)) + ggplot2::geom_point()
    }
    session$setInputs(preview_btn = 10)
    expect_null(state$final_plot)
    expect_match(tail(fixture$notifications, 1)[[1]]$text, "Could not generate annotation preview")
    rm("plot_clusters", envir = fixture)
    # Retry succeeds in the same live session with unsaved partial annotations.
    session$setInputs(preview_btn = 11)
    expect_s3_class(state$final_plot, "ggplot")
    expect_length(fixture$navigation, 1)
    expect_identical(state$pipeline_state, original_state)
    expect_identical(r03_disk_snapshot(dataset_dir), disk)
    expect_identical(state$cells_filt$cell_type, c("T cell", NA_character_, NA_character_))
  })
})

test_that("R03 saving a partial preview preserves its Unassigned legend and scientific labels", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("qs2")
  skip_if_not_installed("png")
  suppressPackageStartupMessages(library(shiny))
  dataset_dir <- withr::local_tempdir()
  fixture <- make_r03_preview_fixture(dataset_dir)
  state <- fixture$state
  shiny::testServer(fixture$server, {
    session$setInputs(main_nav = "anno_tab", sample_idx = "1")
    session$setInputs(cluster = "0", cell_type_input = "T cell", assign_btn = 1)
    session$setInputs(preview_btn = 1)
    expect_s3_class(state$final_plot, "ggplot")
    scale <- ggplot2::ggplot_build(state$final_plot)$plot$scales$get_scales("colour")
    expect_true("Unassigned" %in% scale$get_breaks())
    expected_png <- file.path(dataset_dir, "expected-preview.png")
    ggplot2::ggsave(expected_png, state$final_plot, width = 8, height = 6)
    session$setInputs(save_btn = 1)
    saved_png <- file.path(state$results_dir_path, "sample1", "2_de_plots", "cell_types.png")
    expect_true(file.exists(saved_png))
    expect_identical(png::readPNG(saved_png), png::readPNG(expected_png))
    expect_identical(state$cells_filt$cell_type, c("T cell", NA_character_, NA_character_))
    expect_identical(get_pipeline_step(state$pipeline_state, "annotation", "sample1")$status, "completed")
    aggregate <- get_pipeline_step(state$pipeline_state, "annotation", "sample1")$details$snapshot_annotations
    expect_identical(aggregate$schema_version, 1L)
    expect_identical(aggregate$cell_file_checksum, .cache_md5(state$paths_list$cell_file_paths[1]))
    expect_equal(sum(vapply(aggregate$counts, `[[`, numeric(1), "cell_count")), 3)
    for (step in c("clustering", "resolution", "differential_expression")) {
      expect_identical(get_pipeline_step(state$pipeline_state, step, "sample1")$status, "completed")
    }
    reloaded <- load_cells(state$paths_list$cell_file_paths[1])
    expect_identical(annotation_plot_labels(reloaded$cell_type), c("T cell", "Unassigned", "Unassigned"))
    expect_false(any(reloaded$cell_type == "Unassigned", na.rm = TRUE))
  })
})
