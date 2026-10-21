# Stable launcher for interactive use from the repository root.
#
# The pipeline writes logs, state, caches, plots, and configuration below the
# app directory. Positron's development launcher may interpret those writes as
# source changes when Shiny autoreload is enabled, so disable it before
# `runApp()` initializes its watcher.

local({
  app_dir <- normalizePath(".", winslash = "/", mustWork = TRUE)
  app_entrypoint <- file.path(app_dir, "app.R")
  if (!file.exists(app_entrypoint)) {
    stop(
      "scripts/run_app.R must be sourced from the repository root.",
      call. = FALSE
    )
  }

  options(shiny.autoreload = FALSE)
  message("Starting scAnnotationPipeline with Shiny autoreload disabled.")
  shiny::runApp(appDir = app_dir)
})
