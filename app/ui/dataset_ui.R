# Dataset selection and standardization-onboarding UI.

standardization_guide <- function(clipboard_text) {
  div(
    class = "p-3",
    h3("Prepare a Dataset for the Pipeline"),
    p(
      "Creating a workspace prepares the folder structure and configuration files. ",
      "Standardization is the next step and runs outside this app."
    ),
    tags$ol(
      tags$li("Add the raw source files to the workspace's ", tags$code("data/"), " folder."),
      tags$li("Complete ", tags$code("samples_config.yaml"), " using the metadata prompt below."),
      tags$li(
        "Open and adapt ", tags$code("datasets/<dataset>/standardize.R"),
        " for the source data."
      ),
      tags$li(
        "Run ", tags$code("source(\"standardize.R\")"),
        " from an R console whose working directory is the dataset workspace."
      ),
      tags$li("Return to this page and use Load Dataset after the run succeeds.")
    ),
    div(
      class = "alert alert-warning",
      icon("triangle-exclamation"),
      tags$strong(" Load Dataset stays guarded until standardization is complete. "),
      "The script must pass strict post-validation and produce populated ",
      tags$code("processed_data/"),
      "; an incomplete workspace will not initialize the downstream pipeline."
    ),
    div(
      class = "d-flex flex-wrap gap-2 mb-4",
      tags$a(
        "Open Standardization Checklist",
        href = "pipeline-docs/STANDARDIZATION_CHECKLIST.md",
        target = "_blank",
        rel = "noopener noreferrer",
        class = "btn btn-outline-primary"
      ),
      tags$a(
        "Open User Guide: Dataset Setup",
        href = "pipeline-docs/USER_GUIDE.md#setting-up-a-new-dataset",
        target = "_blank",
        rel = "noopener noreferrer",
        class = "btn btn-outline-primary"
      )
    ),
    h4("Sample-metadata gathering prompt"),
    p(
      "Use this prompt with the dataset publication or supplementary material, ",
      "then review the extracted values before adding them to samples_config.yaml.",
      class = "text-muted"
    ),
    div(
      class = "d-flex flex-wrap gap-2 mb-2",
      actionButton(
        "btn_select_standardization_prompt",
        "Select Prompt Text",
        icon = icon("i-cursor")
      ),
      actionButton(
        "btn_copy_standardization_prompt",
        "Copy Prompt",
        icon = icon("copy"),
        class = "btn-primary"
      )
    ),
    tags$textarea(
      id = "standardization_prompt_text",
      class = "form-control",
      style = paste(
        "width: 100%; height: 260px;",
        "font-family: monospace; resize: vertical;"
      ),
      readonly = TRUE,
      clipboard_text
    )
  )
}

dataset_created_modal <- function(dataset_name, dataset_path) {
  standardize_path <- file.path(dataset_path, "standardize.R")

  modalDialog(
    title = paste("Workspace created:", dataset_name),
    div(
      class = "alert alert-success",
      icon("circle-check"),
      " Workspace created at ",
      tags$code(dataset_path)
    ),
    p(
      tags$strong("Next action: "),
      "open and adapt ",
      tags$code(standardize_path),
      ", then run it from the dataset workspace in an R console."
    ),
    p(
      "Load Dataset will work after standardize.R passes strict post-validation ",
      "and creates populated output under ",
      tags$code(file.path(dataset_path, "processed_data")),
      "."
    ),
    footer = tagList(
      modalButton("Close"),
      actionButton(
        "btn_open_standardization_guide",
        "Open Standardization Guide",
        icon = icon("book-open"),
        class = "btn-primary"
      )
    )
  )
}

dataset_selection_panel <- function(available_datasets, clipboard_text) {
  nav_panel(
    title = "Dataset Selection",
    value = "dataset_tab",
    div(
      class = "container mt-5",
      style = "max-width: 800px;",
      h2("Initialize Pipeline", class = "mb-4 text-center"),
      navset_card_underline(
        id = "dataset_setup_view",
        nav_panel(
          title = "Workspace",
          value = "dataset_workspace",
          card_body(
            p(
              "Select a standardized dataset, or create a workspace for a new one.",
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
            ),
            p(
              "New workspaces must be standardized before they can be loaded.",
              class = "small text-muted mt-3 mb-0"
            )
          )
        ),
        nav_panel(
          title = "Standardization Guide",
          value = "standardization_guide",
          standardization_guide(clipboard_text)
        )
      )
    )
  )
}
