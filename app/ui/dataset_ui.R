# Dataset selection UI.

dataset_selection_panel <- function(available_datasets) {
  nav_panel(
    title = "Dataset Selection",
    value = "dataset_tab",
    div(
      class = "container mt-5",
      style = "max-width: 800px;",
      h2("Initialize Pipeline", class = "mb-4 text-center"),
      card(
        card_header(h4("Select Workspace", class = "mb-0 text-center")),
        card_body(
          p(
            "Please select a dataset folder to load its configurations and processed data.",
            class = "text-muted"
          ),
          selectInput(
            "dataset_choice",
            "Available Datasets:",
            choices = available_datasets,
            width = "100%"
          ),
          actionButton(
            "btn_load_dataset",
            "Load Dataset",
            icon = icon("folder-open"),
            class = "btn-primary btn-lg w-100 mt-3"
          ),
          actionButton(
            "btn_create_dataset_ui",
            "Create New Dataset",
            icon = icon("folder-plus"),
            class = "btn-success btn-lg w-100 mt-2"
          )
        )
      )
    )
  )
}
