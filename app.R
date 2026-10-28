# ==================================================================================================
# Script: app.R
# Purpose: Shiny App for scRNA-seq cancer dataset cell type annotation
# ==================================================================================================

library(shiny)
library(data.table)
library(bslib)
library(shinyjs)

sources_path <- "util_scripts"
if (!dir.exists(sources_path)) {
  stop(
    "Utility scripts folder not found at '", sources_path,
    "'. Make sure app.R is launched from the app's root directory.",
    call. = FALSE
  )
}

utility_files <- sort(list.files(
  sources_path,
  pattern = "[.]R$",
  full.names = TRUE
))
if (length(utility_files) == 0) {
  stop(
    "No .R files found in '", sources_path,
    "'. Utility functions could not be loaded.",
    call. = FALSE
  )
}
invisible(lapply(utility_files, source))

app_component_files <- c(
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

missing_components <- app_component_files[!file.exists(app_component_files)]
if (length(missing_components) > 0) {
  stop(
    "Application component files are missing:\n",
    paste0(" - ", missing_components, collapse = "\n"),
    call. = FALSE
  )
}
invisible(lapply(app_component_files, source))

app_context <- create_app_context()

# Make the local Markdown guides reachable from the onboarding links without
# requiring internet access. Re-registering keeps repeated development starts
# pointed at the current app directory.
documentation_path <- normalizePath("docs", mustWork = FALSE)
if (dir.exists(documentation_path)) {
  registered_resources <- shiny::resourcePaths()
  if ("pipeline-docs" %in% names(registered_resources)) {
    shiny::removeResourcePath("pipeline-docs")
  }
  shiny::addResourcePath("pipeline-docs", documentation_path)
}

ui <- build_app_ui(app_context)
server <- build_app_server(app_context)

shinyApp(ui = ui, server = server)
