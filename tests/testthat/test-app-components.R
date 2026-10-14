component_paths <- c(
  "app/context.R",
  "app/state.R",
  "app/ui/dataset_ui.R",
  "app/ui/dashboard_ui.R",
  "app/ui/resolution_ui.R",
  "app/ui/annotation_ui.R",
  "app/ui/cna_ui.R",
  "app/ui/app_ui.R",
  "app/server/dataset_server.R",
  "app/server/dashboard_server.R",
  "app/server/resolution_server.R",
  "app/server/annotation_server.R",
  "app/server/cna_status_server.R",
  "app/server/cna_compute_server.R",
  "app/server/cna_cluster_server.R",
  "app/server/cna_threshold_server.R",
  "app/server/cna_summary_server.R",
  "app/server/cna_reset_server.R",
  "app/server/cna_server.R",
  "app/server/app_server.R"
)

test_that("app entry point explicitly registers every component", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  app_lines <- readLines(file.path(app_dir, "app.R"))

  expect_lte(length(app_lines), 100L)
  expect_false(any(grepl("observe(Event)?[(]", app_lines)))

  for (component_path in component_paths) {
    expect_true(file.exists(file.path(app_dir, component_path)))
    expect_equal(
      sum(grepl(paste0('"', component_path, '"'), app_lines, fixed = TRUE)),
      1L,
      info = component_path
    )
  }
})

test_that("shared state remains flat and contains only mutable session data", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  component_env <- new.env(parent = globalenv())
  sys.source(file.path(app_dir, "app/state.R"), envir = component_env)

  state <- component_env$create_app_state(list())
  state_names <- shiny::isolate(sort(names(state)))

  expect_setequal(
    state_names,
    c(
      "paths_list", "dataset_config", "samples_config",
      "live_selected_config", "complete_markers", "results_dir_path",
      "selected_config_path", "dataset_dir_path", "config", "cells_filt",
      "all_matches", "cells_raw", "sample_name", "res", "final_plot",
      "cna_preview_res"
    )
  )
  expect_false(any(c(
    "gene_positions",
    "cancer_cell_map",
    "clipboard_text"
  ) %in% state_names))
})

test_that("each server registration is composed exactly once", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  component_env <- new.env(parent = globalenv())
  server_paths <- component_paths[grepl("app/server/", component_paths, fixed = TRUE)]
  invisible(lapply(
    file.path(app_dir, server_paths),
    sys.source,
    envir = component_env
  ))

  top_level_registrations <- c(
    "register_dataset_server",
    "register_dashboard_server",
    "register_resolution_server",
    "register_annotation_server",
    "register_cna_server"
  )
  app_server_body <- paste(
    deparse(body(component_env$build_app_server)),
    collapse = "\n"
  )
  for (registration in top_level_registrations) {
    expect_equal(
      lengths(regmatches(
        app_server_body,
        gregexpr(registration, app_server_body, fixed = TRUE)
      )),
      1L,
      info = registration
    )
  }

  cna_registrations <- c(
    "register_cna_status_server",
    "register_cna_compute_server",
    "register_cna_cluster_server",
    "register_cna_threshold_server",
    "register_cna_summary_server",
    "register_cna_reset_server"
  )
  cna_server_body <- paste(
    deparse(body(component_env$register_cna_server)),
    collapse = "\n"
  )
  for (registration in cna_registrations) {
    expect_equal(
      lengths(regmatches(
        cna_server_body,
        gregexpr(registration, cna_server_body, fixed = TRUE)
      )),
      1L,
      info = registration
    )
  }
})
