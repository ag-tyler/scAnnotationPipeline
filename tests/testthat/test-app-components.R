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
      "session_id", "session_started_at", "session_logged_datasets",
      "live_selected_config", "complete_markers", "results_dir_path",
      "selected_config_path", "pipeline_state", "pipeline_state_path",
      "dataset_dir_path", "config", "cells_filt",
      "all_matches", "cells_raw", "sample_name", "res", "final_plot",
      "annotation_dirty", "annotation_loaded_index", "annotation_pending_navigation",
      "cna_preview_res", "cna_preview_sample", "cna_preview_fingerprint"
    )
  )
  expect_false(any(c(
    "gene_positions",
    "cancer_cell_map",
    "clipboard_text"
  ) %in% state_names))
})


test_that("application state carries a stable per-session diagnostic identity", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  component_env <- new.env(parent = globalenv())
  sys.source(file.path(app_dir, "app/state.R"), envir = component_env)

  started_at <- as.POSIXct("2026-10-21 12:00:00", tz = "UTC")
  state <- component_env$create_app_state(
    list(),
    session_id = "test-session-token",
    session_started_at = started_at
  )

  expect_identical(shiny::isolate(state$session_id), "test-session-token")
  expect_identical(
    shiny::isolate(state$session_started_at),
    "2026-10-21T12:00:00.000Z"
  )
  expect_identical(shiny::isolate(state$session_logged_datasets), character())
  expect_match(component_env$new_app_session_id(), "^session-")
})


test_that("top-level server isolates startup reads from reactive state", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  server_text <- paste(
    readLines(file.path(app_dir, "app/server/app_server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(
    server_text,
    "shiny::isolate(state$session_id)",
    fixed = TRUE
  )
  expect_match(
    server_text,
    "shiny::isolate(state$session_started_at)",
    fixed = TRUE
  )
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
    "app/server/dataset_server.R" = c(
      "workspace_created", "app_session_started", "dataset_load"
    ),
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

test_that("long-running dashboard tasks provide next-step completion actions", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  dashboard_text <- paste(
    readLines(file.path(app_dir, "app/server/dashboard_server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(dashboard_text, "Clustering complete", fixed = TRUE)
  expect_match(dashboard_text, "Go to Resolution Selection", fixed = TRUE)
  expect_match(dashboard_text, 'selected = "res_tab"', fixed = TRUE)
  expect_match(dashboard_text, "Differential expression complete", fixed = TRUE)
  expect_match(dashboard_text, "Go to Manual Annotation", fixed = TRUE)
  expect_match(dashboard_text, 'selected = "anno_tab"', fixed = TRUE)
})

test_that("manual annotation views have deterministic navigation", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  ui_text <- paste(
    readLines(file.path(app_dir, "app/ui/annotation_ui.R"), warn = FALSE),
    collapse = "\n"
  )
  server_text <- paste(
    readLines(file.path(app_dir, "app/server/annotation_server.R"), warn = FALSE),
    collapse = "\n"
  )
  dataset_text <- paste(
    readLines(file.path(app_dir, "app/server/dataset_server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(ui_text, 'id = "annotation_view"', fixed = TRUE)
  expect_match(ui_text, 'value = "annotation_cluster"', fixed = TRUE)
  expect_match(ui_text, 'value = "annotation_preview"', fixed = TRUE)
  expect_match(
    server_text,
    'nav_select("annotation_view", "annotation_cluster")',
    fixed = TRUE
  )
  expect_match(
    server_text,
    'nav_select("annotation_view", "annotation_preview")',
    fixed = TRUE
  )
  expect_match(server_text, "plot_subtitle", fixed = TRUE)
  expect_match(dataset_text, 'choices = s_choices, selected = 1', fixed = TRUE)
})

test_that("manual annotation protects unsaved edits and records CNA omission", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  server_text <- paste(
    readLines(file.path(app_dir, "app/server/annotation_server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(server_text, "Unsaved annotation changes", fixed = TRUE)
  expect_match(server_text, "Discard and continue", fixed = TRUE)
  expect_match(server_text, "Save and continue", fixed = TRUE)
  expect_match(server_text, "annotation_dirty <- isTRUE", fixed = TRUE)
  expect_match(server_text, 'observeEvent(input$main_nav', fixed = TRUE)
  expect_match(server_text, 'type = "navbar"', fixed = TRUE)
  expect_match(server_text, "CNA configuration is incomplete", fixed = TRUE)
  expect_match(server_text, "Save; configure CNA next", fixed = TRUE)
  expect_match(server_text, "Save and omit CNA", fixed = TRUE)
  expect_match(server_text, '"cna_configuration",\n        "skipped"')
  expect_match(server_text, "cna_configuration_skipped", fixed = TRUE)
})

test_that("sample notes are available and persisted across workflow stages", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  stage_files <- list(
    res = c("app/ui/resolution_ui.R", "app/server/resolution_server.R"),
    anno = c("app/ui/annotation_ui.R", "app/server/annotation_server.R"),
    cna = c("app/ui/cna_ui.R", "app/server/cna_status_server.R")
  )

  for (stage in names(stage_files)) {
    stage_text <- paste(
      unlist(lapply(file.path(app_dir, stage_files[[stage]]), readLines, warn = FALSE)),
      collapse = "\n"
    )
    expect_match(stage_text, paste0(stage, "_sample_notes"), fixed = TRUE)
    expect_match(stage_text, "save_sample_note", fixed = TRUE)
    expect_match(stage_text, "sample_note_saved", fixed = TRUE)
  }
})

test_that("CNA eligibility is shared by status, single-run, and batch paths", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  relevant_files <- c(
    "app/ui/cna_ui.R",
    "app/server/cna_status_server.R",
    "app/server/cna_compute_server.R",
    "util_scripts/05_utils_workflow.R"
  )
  relevant_text <- lapply(
    file.path(app_dir, relevant_files),
    function(path) paste(readLines(path, warn = FALSE), collapse = "\n")
  )
  names(relevant_text) <- relevant_files

  expect_match(relevant_text[["app/ui/cna_ui.R"]], "cna_eligibility_ui", fixed = TRUE)
  expect_match(
    relevant_text[["app/server/cna_status_server.R"]],
    "cna_sample_preflight",
    fixed = TRUE
  )
  expect_match(
    relevant_text[["app/server/cna_compute_server.R"]],
    "cna_sample_preflight",
    fixed = TRUE
  )
  expect_gte(
    lengths(regmatches(
      relevant_text[["util_scripts/05_utils_workflow.R"]],
      gregexpr("cna_sample_preflight", relevant_text[["util_scripts/05_utils_workflow.R"]], fixed = TRUE)
    )),
    2L
  )
})

test_that("batch CNA supports subset selection, resume, and partial-failure summaries", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  server_text <- paste(
    readLines(file.path(app_dir, "app/server/cna_compute_server.R"), warn = FALSE),
    collapse = "\n"
  )
  workflow_text <- paste(
    readLines(file.path(app_dir, "util_scripts/05_utils_workflow.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(
    server_text,
    'checkboxGroupInput(\n        "cna_batch_samples"',
    fixed = TRUE
  )
  expect_match(server_text, "resume_samples <-", fixed = TRUE)
  expect_match(server_text, "res$failed", fixed = TRUE)
  expect_match(server_text, '"completed_with_failures"', fixed = TRUE)
  expect_match(workflow_text, "sample_names = NULL", fixed = TRUE)
  expect_match(workflow_text, "failed_samples[[s_name]]", fixed = TRUE)
})

test_that("CNA computation exposes stage progress and logs sample switches", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  compute_text <- paste(
    readLines(file.path(app_dir, "app/server/cna_compute_server.R"), warn = FALSE),
    collapse = "\n"
  )
  cluster_text <- paste(
    readLines(file.path(app_dir, "app/server/cna_cluster_server.R"), warn = FALSE),
    collapse = "\n"
  )
  status_text <- paste(
    readLines(file.path(app_dir, "app/server/cna_status_server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(compute_text, 'withProgress(message = paste("CNA:"', fixed = TRUE)
  expect_match(compute_text, 'message = "Batch CNA computation"', fixed = TRUE)
  expect_match(compute_text, '"Sample ", sample_index, " of ", sample_total', fixed = TRUE)
  expect_match(cluster_text, 'withProgress(message = paste("Signal/correlation:"', fixed = TRUE)
  expect_match(cluster_text, 'paste("Computing subclone", i, "of", n_subclones)', fixed = TRUE)
  expect_match(status_text, 'event_type = "cna_sample_selected"', fixed = TRUE)
  expect_match(status_text, "last_cna_sample", fixed = TRUE)
  expect_match(compute_text, 'nav_select("cna_main_views", "cna_view_select_malignant")', fixed = TRUE)
  expect_match(cluster_text, 'nav_select("cna_main_views", "cna_view_thresholds")', fixed = TRUE)
})

test_that("CNA thresholds use one shared scale and fixed precision", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  threshold_text <- paste(
    readLines(file.path(app_dir, "app/server/cna_threshold_server.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(threshold_text, '"cna_shared_ymax"', fixed = TRUE)
  expect_match(threshold_text, "cna_signal_axis_summary", fixed = TRUE)
  expect_match(threshold_text, "threshold assignments still use the original, unclipped values", fixed = TRUE)
  expect_match(threshold_text, "value = def_mx", fixed = TRUE)
  expect_false(grepl("cna_step_size_", threshold_text, fixed = TRUE))
  expect_false(grepl("cna_ymax_", threshold_text, fixed = TRUE))
})

test_that("Assign and Summary auto-previews current inputs with before/after views", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  summary_text <- paste(
    readLines(file.path(app_dir, "app/server/cna_summary_server.R"), warn = FALSE),
    collapse = "\n"
  )
  ui_text <- paste(
    readLines(file.path(app_dir, "app/ui/cna_ui.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_match(summary_text, "observeEvent(input$cna_main_views", fixed = TRUE)
  expect_match(summary_text, '"cna_view_summary"', fixed = TRUE)
  expect_match(summary_text, "cna_preview_fingerprint", fixed = TRUE)
  expect_match(summary_text, "reusable <-", fixed = TRUE)
  expect_match(summary_text, 'nav_select("cna_preview_tabs", "cna_preview_scatter")', fixed = TRUE)
  expect_match(summary_text, "cna_preview_umap_pre", fixed = TRUE)
  expect_match(summary_text, "The CNA preview is stale", fixed = TRUE)
  expect_match(ui_text, 'value = "cna_preview_scatter"', fixed = TRUE)
  expect_match(ui_text, 'value = "cna_preview_umap_comparison"', fixed = TRUE)
  expect_match(ui_text, "Before CNA", fixed = TRUE)
  expect_match(ui_text, "Preview after CNA", fixed = TRUE)
})
