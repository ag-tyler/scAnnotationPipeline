# Top-level UI composition.

build_app_ui <- function(context) {
  page_navbar(
    id = "main_nav",
    title = "scRNA-seq Annotation Pipeline",
    theme = bs_theme(
      version = 5,
      bootswatch = "flatly",
      primary = "#2c3e50"
    ),
    header = tagList(useShinyjs()),
    dataset_selection_panel(context$available_datasets),
    dashboard_panel(),
    reference_panel(context$resources$clipboard_text),
    resolution_panel(context$sample_choices),
    annotation_panel(context$sample_choices),
    cna_panel(context$sample_choices)
  )
}
