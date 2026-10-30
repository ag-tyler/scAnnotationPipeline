make_r04_resolution_fixture <- function(dataset_dir) {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  env <- new.env(parent = environment())
  sys.source(file.path(app_dir, "app/state.R"), envir = env)
  env$register_single_sample_de_handlers <- function(...) invisible(NULL)
  env$record_state_event <- function(...) invisible(NULL)
  env$showNotification <- function(...) "notification"
  env$removeNotification <- function(...) invisible(NULL)
  env$showModal <- function(...) invisible(NULL)
  env$removeModal <- function(...) invisible(NULL)
  env$pipeline_status_overview_ui <- function(...) shiny::tags$div("Overview")
  env$cache_invalidate_sample <- function(...) character()
  env$cache_load_data <- env$cache_check_valid <- function(...) stop("Unexpected scientific-cache I/O")
  env$plot_checks <- character()
  env$tab_builds <- 0L
  env$file.exists <- function(path) {
    env$plot_checks <- c(env$plot_checks, path)
    base::file.exists(path)
  }
  env$navset_card_underline <- function(...) {
    env$tab_builds <- env$tab_builds + 1L
    bslib::navset_card_underline(...)
  }
  env$generations <- c(0L, 0L)
  results_dir <- file.path(dataset_dir, "results")
  sample_dirs <- file.path(dataset_dir, "processed_data", c("sample1", "sample2"))
  invisible(lapply(sample_dirs, dir.create, recursive = TRUE))
  env$publish_plots <- function(indices) {
    for (index in indices) {
      sample <- basename(sample_dirs[index])
      env$generations[index] <- env$generations[index] + 1L
      plot_dir <- file.path(results_dir, sample, "1_cluster_plots")
      dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
      for (resolution in c(0.5, 1)) {
        png::writePNG(
          array((env$generations[index] %% 3L) / 3, dim = c(4, 4, 3)),
          file.path(plot_dir, paste0("clusters_plot_", sample, "_res_", resolution, ".png"))
        )
      }
    }
  }
  env$cluster_all_samples <- function(
    paths_list, config, results_dir_path, dataset_dir_path,
    state_callback, progress_callback, sample_indices = seq_along(sample_dirs)
  ) {
    for (index in sample_indices) {
      sample <- basename(sample_dirs[index])
      state_callback(sample, "in_progress")
      env$publish_plots(index)
      state_callback(sample, "completed", details = list(resolutions = c(0.5, 1)))
    }
  }
  sys.source(file.path(app_dir, "app/server/dashboard_server.R"), envir = env)
  sys.source(file.path(app_dir, "app/server/resolution_server.R"), envir = env)
  state <- env$create_app_state(list(), session_id = "r04-refresh")
  state$paths_list <- list(sample_dir_paths = sample_dirs)
  state$dataset_dir_path <- dataset_dir
  state$results_dir_path <- results_dir
  state$dataset_config <- list(params = list(resolutions = c(0.5, 1)))
  selected <- list(resolutions = list(sample1 = 0, sample2 = 0), sample_notes = list())
  state$live_selected_config <- selected
  selected_path <- file.path(dataset_dir, "selected_config.yaml")
  yaml::write_yaml(selected, selected_path)
  state$selected_config_path <- selected_path
  state$config <- list(selected = selected)
  pipeline <- new_pipeline_state("Synthetic_R04", basename(sample_dirs))
  pipeline <- transition_pipeline_step(pipeline, "standardization", "completed")
  state_path <- file.path(dataset_dir, "pipeline_state.yaml")
  state$pipeline_state <- save_pipeline_state_at_path(pipeline, state_path)
  state$pipeline_state_path <- state_path
  env$state <- state
  env$server <- function(input, output, session) {
    env$register_dashboard_server(input, output, session, state, list())
    env$register_resolution_server(input, output, session, state, list())
  }
  env
}

r04_image <- function(output, id) {
  # The old missing-image renderer may return an empty src or a Shiny error.
  image <- tryCatch(output[[id]], error = function(e) list(src = "", error = conditionMessage(e)))
  if (is.null(image$src)) image$src <- ""
  image
}

test_that("R04 an already opened grid and detail refresh after bulk and targeted clustering", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("png")
  suppressPackageStartupMessages(library(shiny))
  suppressPackageStartupMessages(library(bslib))
  fixture <- make_r04_resolution_fixture(withr::local_tempdir())
  state <- fixture$state
  shiny::testServer(fixture$server, {
    session$setInputs(main_nav = "res_tab", res_sample_idx = "1")
    tabs <- output$res_plots_tabs
    builds <- fixture$tab_builds
    grid <- "img_grid_sample1_0.5"
    detail <- "img_tab_sample1_0.5"
    expect_identical(r04_image(output, grid)$src, "")
    expect_identical(r04_image(output, detail)$src, "")
    expect_match(output$res_status_badge$html, "Not started")
    session$setInputs(main_nav = "menu_tab", btn_run_clustering = 1)
    session$setInputs(confirm_run_clustering = 1)
    # Observe completion without a sample switch or rebuilding the tabs.
    expect_identical(input$res_sample_idx, "1")
    bulk_grid <- r04_image(output, grid)
    bulk_detail <- r04_image(output, detail)
    expect_true(nzchar(bulk_grid$src))
    expect_identical(bulk_grid$src, bulk_detail$src)
    expect_true(nzchar(r04_image(output, "img_grid_sample1_1")$src))
    expect_identical(
      r04_image(output, "img_tab_sample1_1")$src,
      r04_image(output, "img_grid_sample1_1")$src
    )
    expect_identical(fixture$tab_builds, builds)
    expect_identical(get_pipeline_step(state$pipeline_state, "clustering", "sample1")$status, "completed")
    session$setInputs(main_nav = "res_tab", selected_res = "0.5", btn_save_res = 1)
    expect_match(output$res_status_badge$html, "Resolution: Complete")
    session$setInputs(main_nav = "menu_tab", btn_run_single_clustering = 1)
    session$setInputs(single_clustering_sample = "1", confirm_run_single_clustering = 1)
    rerun_grid <- r04_image(output, grid)
    expect_true(nzchar(rerun_grid$src))
    expect_false(identical(rerun_grid$src, bulk_grid$src))
    expect_identical(rerun_grid$src, r04_image(output, detail)$src)
    expect_match(output$res_status_badge$html, "Stale")
    expect_match(output$res_status_badge$html, "Clustering was rerun")
    expect_identical(fixture$tab_builds, builds)
    # Re-entry keeps the selected sample, saved resolution and tab structure.
    session$setInputs(main_nav = "res_tab")
    expect_identical(input$res_sample_idx, "1")
    expect_identical(state$live_selected_config$resolutions$sample1, 0.5)
    expect_identical(r04_image(output, grid)$src, rerun_grid$src)
    expect_identical(output$res_plots_tabs, tabs)
  })
})

test_that("R04 refresh is sample-scoped, idle-free and catches file changes on re-entry", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("png")
  suppressPackageStartupMessages(library(shiny))
  suppressPackageStartupMessages(library(bslib))
  fixture <- make_r04_resolution_fixture(withr::local_tempdir())
  state <- fixture$state
  fixture$publish_plots(1:2)
  shiny::testServer(fixture$server, {
    session$setInputs(main_nav = "res_tab", res_sample_idx = "1")
    tabs <- output$res_plots_tabs
    grid <- "img_grid_sample1_0.5"
    original <- r04_image(output, grid)
    checks <- length(fixture$plot_checks)
    for (i in 1:3) {
      session$flushReact()
      expect_identical(r04_image(output, grid), original)
    }
    expect_length(fixture$plot_checks, checks)
    state$pipeline_state <- transition_pipeline_step(
      state$pipeline_state, "annotation", "completed", sample = "sample1", force = TRUE
    )
    session$flushReact()
    expect_identical(r04_image(output, grid), original)
    expect_length(fixture$plot_checks, checks)
    state$pipeline_state <- transition_pipeline_step(
      state$pipeline_state, "clustering", "completed", sample = "sample2", force = TRUE
    )
    session$flushReact()
    expect_identical(r04_image(output, grid), original)
    expect_length(fixture$plot_checks, checks)
    # No polling: a same-path replacement is picked up explicitly on re-entry.
    session$setInputs(main_nav = "menu_tab")
    fixture$publish_plots(1)
    session$setInputs(main_nav = "res_tab")
    replaced <- r04_image(output, grid)
    expect_false(identical(replaced$src, original$src))
    expect_gt(length(fixture$plot_checks), checks)
    expect_identical(output$res_plots_tabs, tabs)
    # Removal on re-entry clears the old image; restoration can be retried.
    path <- file.path(state$results_dir_path, "sample1", "1_cluster_plots", "clusters_plot_sample1_res_0.5.png")
    session$setInputs(main_nav = "menu_tab")
    unlink(path)
    session$setInputs(main_nav = "res_tab")
    expect_identical(r04_image(output, grid)$src, "")
    session$setInputs(main_nav = "menu_tab")
    fixture$publish_plots(1)
    session$setInputs(main_nav = "res_tab")
    expect_true(nzchar(r04_image(output, grid)$src))
    session$setInputs(res_sample_idx = "2")
    output$res_plots_tabs
    expect_true(nzchar(r04_image(output, "img_grid_sample2_0.5")$src))
    # Switching dataset/result roots with identical sample names must not reuse
    # the previous dataset's PNG, even if its clustering record is identical.
    other_results <- file.path(state$dataset_dir_path, "other-results")
    other_plot_dir <- file.path(other_results, "sample2", "1_cluster_plots")
    dir.create(other_plot_dir, recursive = TRUE)
    png::writePNG(array(1, dim = c(4, 4, 3)), file.path(other_plot_dir, "clusters_plot_sample2_res_0.5.png"))
    before_switch <- r04_image(output, "img_grid_sample2_0.5")
    state$results_dir_path <- other_results
    session$flushReact()
    after_switch <- r04_image(output, "img_grid_sample2_0.5")
    expect_true(nzchar(after_switch$src))
    expect_false(identical(after_switch$src, before_switch$src))
  })
})
