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
      "selected_config_path", "pipeline_state", "pipeline_state_path",
      "dataset_dir_path", "config", "cells_filt",
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


test_that("new dataset creation offers and copies only the general template", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  config <- yaml::read_yaml(file.path(app_dir, "general_config.yaml"))
  server_lines <- readLines(file.path(app_dir, "app/server/dataset_server.R"))
  server_text <- paste(server_lines, collapse = "\n")

  expect_identical(unlist(config$standardization_pipelines), "general")
  expect_identical(config$dataset_paths$logs_dir, "logs")
  expect_identical(config$config_files$state, "pipeline_state.yaml")
  expect_true(file.exists(file.path(
    app_dir,
    "templates",
    "standardize_general.R"
  )))
  expect_match(server_text, '"Standardization Template:"', fixed = TRUE)
  expect_match(server_text, '"standardize_general.R"', fixed = TRUE)
  expect_false(grepl('paste0("standardize_"', server_text, fixed = TRUE))
  expect_match(
    server_text,
    'ds_config$project_info$technology <- ""',
    fixed = TRUE
  )
  expect_match(
    server_text,
    'sample = "", technology = ""',
    fixed = TRUE
  )
  expect_match(server_text, '"results", "logs"', fixed = TRUE)
  expect_match(server_text, "new_pipeline_state", fixed = TRUE)
  expect_match(server_text, "load_or_initialize_pipeline_state", fixed = TRUE)
})


test_that("pipeline persistence boundaries emit structured events", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  expected_events <- list(
    "app/server/dataset_server.R" = c("workspace_created", "dataset_load"),
    "app/server/dashboard_server.R" = c("clustering_run", "de_run"),
    "app/server/resolution_server.R" = c("resolution_saved", "single_sample_de"),
    "app/server/annotation_server.R" = c(
      "annotation_changed", "annotations_saved", "cna_configuration_saved"
    ),
    "app/server/cna_compute_server.R" = c("cna_compute", "cna_batch_compute"),
    "app/server/cna_cluster_server.R" = c(
      "malignant_clusters_saved", "cna_signal_correlation"
    ),
    "app/server/cna_threshold_server.R" = "cna_thresholds_saved",
    "app/server/cna_summary_server.R" = "cna_assignments_saved",
    "app/server/cna_reset_server.R" = c("cna_cache", "cna_reset")
  )

  for (server_path in names(expected_events)) {
    server_text <- paste(
      readLines(file.path(app_dir, server_path), warn = FALSE),
      collapse = "\n"
    )
    expect_match(server_text, "record_", fixed = TRUE, info = server_path)
    for (event_type in expected_events[[server_path]]) {
      expect_match(server_text, event_type, fixed = TRUE, info = server_path)
    }
  }
})


test_that("workflow servers use persisted state for guards, badges, and mutations", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  state_integrations <- list(
    "app/server/dashboard_server.R" = c(
      "pipeline_step_readiness", "persist_pipeline_step_update"
    ),
    "app/server/resolution_server.R" = c(
      "pipeline_status_presentation", "persist_pipeline_step_update"
    ),
    "app/server/annotation_server.R" = c(
      "pipeline_status_presentation", "persist_pipeline_step_update"
    ),
    "app/server/cna_compute_server.R" = c(
      "pipeline_step_readiness", "persist_pipeline_step_update"
    ),
    "app/server/cna_cluster_server.R" = c(
      "pipeline_step_readiness", "persist_pipeline_step_update"
    ),
    "app/server/cna_threshold_server.R" = c(
      "pipeline_step_readiness", "persist_pipeline_step_update"
    ),
    "app/server/cna_summary_server.R" = c(
      "pipeline_step_readiness", "persist_pipeline_step_update"
    ),
    "app/server/cna_reset_server.R" = c(
      "reset_pipeline_steps", "save_pipeline_state_at_path"
    ),
    "app/server/cna_status_server.R" = c(
      "get_pipeline_step", "pipeline_status_presentation"
    )
  )

  for (server_path in names(state_integrations)) {
    server_text <- paste(
      readLines(file.path(app_dir, server_path), warn = FALSE),
      collapse = "\n"
    )
    for (function_name in state_integrations[[server_path]]) {
      expect_match(server_text, function_name, fixed = TRUE, info = server_path)
    }
  }

  cna_status_text <- paste(
    readLines(file.path(app_dir, "app/server/cna_status_server.R"), warn = FALSE),
    collapse = "\n"
  )
  expect_false(grepl("cache_check_exists", cna_status_text, fixed = TRUE))
})
