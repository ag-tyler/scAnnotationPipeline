# Prepared-data selection, import, and directory browsing UI.

dataset_import_dialog <- function(parent_dir) {
  modalDialog(
    title = "Create Dataset From Prepared Data",
    div(style = "max-height: 70vh; overflow-y: auto; overflow-x: hidden;",
      textInput("new_ds_name", "Dataset name:", placeholder = "e.g., Colorectal_Study", width = "100%"),
      uiOutput("dataset_directory_browser"),
      div(class = "mb-3",
        textInput("new_ds_source", "Prepared-data directory:", width = "100%"),
        actionButton("btn_browse_dataset_source", "Browse prepared data", icon = icon("folder-open"))),
      div(class = "mb-3",
        textInput("new_ds_location", "Workspace parent directory:", value = parent_dir, width = "100%"),
        actionButton("btn_browse_dataset_parent", "Browse destination parent", icon = icon("folder-open"))),
      p(class = "small text-muted", "Select a directory containing Samples.csv and the sample folders. Files are copied; originals stay in place."),
      p(class = "small text-muted", "Paths refer to the computer running the app. The workspace is created under the selected parent using the dataset name."),
      downloadLink("download_input_specification", "Prepared-input specification (README.md)"),
      uiOutput("dataset_import_paths"),
      uiOutput("dataset_import_report")
    ),
    footer = tagList(actionButton("btn_cancel_create_ds", "Cancel"), actionButton("btn_confirm_create_ds", "Create Dataset", class = "btn-primary")),
    size = "l"
  )
}

dataset_directory_browser_ui <- function(path, target) {
  children <- list.dirs(path, recursive = FALSE, full.names = TRUE)
  div(
    class = "border rounded p-3 mt-3",
    h5(if (target == "new_ds_source") "Browse prepared data" else "Browse destination parent"),
    textInput("dataset_browser_path", "Current directory:", value = path, width = "100%"),
    div(class = "d-flex flex-wrap gap-2 mb-2",
        actionButton("btn_dataset_browser_go", "Go to path"),
        actionButton("btn_dataset_browser_up", "Up"),
        actionButton("btn_dataset_browser_home", "Home"),
        actionButton("btn_dataset_browser_datasets", "Datasets")),
    selectInput("dataset_browser_child", "Subdirectories:",
      choices = c("Choose a subdirectory" = "", stats::setNames(children, basename(children))), width = "100%"),
    div(class = "d-flex flex-wrap gap-2",
        actionButton("btn_dataset_browser_open", "Open subdirectory"),
        actionButton("btn_dataset_browser_select", "Use this directory", class = "btn-primary"),
        actionButton("btn_dataset_browser_cancel", "Close browser"))
  )
}

dataset_selection_panel <- function(available_datasets) {
  nav_panel(
    title = "Dataset Selection", value = "dataset_tab",
    div(class = "container mt-5", style = "max-width: 800px;",
      h2("Initialize Pipeline", class = "mb-4 text-center"),
      card(card_body(
        p("Select a prepared dataset, or create a workspace from prepared data.", class = "text-muted"),
        selectInput("dataset_choice", "Available Datasets:", choices = available_datasets, width = "100%"),
        uiOutput("workspace_origin_reminder"),
        actionButton("btn_load_dataset", "Load Dataset", icon = icon("folder-open"), class = "btn-primary btn-lg w-100 mt-3"),
        actionButton("btn_create_dataset_ui", "Create New Dataset", icon = icon("folder-plus"), class = "btn-success btn-lg w-100 mt-2"),
        p("Create a workspace by copying an existing prepared-data directory.", class = "small text-muted mt-3 mb-0")
      ))
    )
  )
}
