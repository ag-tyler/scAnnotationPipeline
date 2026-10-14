# Dashboard and reference-data UI.

dashboard_panel <- function() {
  nav_panel(
    title = "Start Menu",
    value = "menu_tab",
    div(
      class = "container mt-5",
      style = "max-width: 800px;",
      h2("Pipeline Dashboard", class = "mb-4 text-center"),
      actionButton(
        "btn_change_dataset",
        "Change Dataset",
        icon = icon("exchange-alt"),
        class = "btn-outline-primary btn-lg w-100 mb-4"
      ),
      card(
        card_header(h4("Utilities", class = "mb-0")),
        card_body(
          p("View and extract metadata prompt:"),
          actionButton(
            "btn_copy_info",
            "Go to Reference Data",
            icon = icon("file-alt"),
            class = "btn-outline-secondary w-100"
          )
        )
      ),
      card(
        card_header(h4("Pre-Processing & Clustering", class = "mb-0")),
        card_body(
          p("Runs PCA, UMAP, and Louvain clustering across all predefined resolutions for all samples."),
          actionButton(
            "btn_run_clustering",
            "Run Clustering for all Resolutions",
            icon = icon("cogs"),
            class = "btn-primary btn-lg w-100"
          )
        )
      ),
      card(
        card_header(h4("Resolution Selection", class = "mb-0")),
        card_body(
          p("Review UMAP plots for each sample and select the most biologically relevant clustering resolution."),
          actionButton(
            "btn_go_res",
            "Go to Resolution Selection",
            icon = icon("search"),
            class = "btn-info btn-lg w-100"
          )
        )
      ),
      card(
        card_header(h4("Differential Expression (DE)", class = "mb-0")),
        card_body(
          p(
            "Runs differential expression analysis. ",
            strong("Requires a resolution to be selected for all samples.")
          ),
          actionButton(
            "btn_run_de",
            "Run Differential Expression Analysis",
            icon = icon("chart-bar"),
            class = "btn-warning btn-lg w-100"
          )
        )
      ),
      card(
        card_header(h4("Manual Cell Type Annotation", class = "mb-0")),
        card_body(
          p("Assign final cell identities based on DE marker matches and signature scores."),
          actionButton(
            "btn_go_anno",
            "Go to Manual Annotation",
            icon = icon("edit"),
            class = "btn-success btn-lg w-100"
          )
        )
      ),
      card(
        card_header(h4("Copy Number Alteration (CNA)", class = "mb-0")),
        card_body(
          p("Run the CNA pipeline: compute CNA signals, select malignant clusters, and assign malignant cells."),
          actionButton(
            "btn_go_cna",
            "Go to CNA Analysis",
            icon = icon("dna"),
            class = "btn-danger btn-lg w-100"
          )
        )
      )
    )
  )
}

reference_panel <- function(clipboard_text) {
  nav_panel(
    title = "Reference Data",
    value = "clipboard_tab",
    div(
      class = "container mt-5",
      style = "max-width: 800px;",
      h3("Metadata Extraction Prompt", class = "mb-3"),
      div(
        class = "alert alert-info",
        icon("info-circle"),
        " Click 'Select All Text' below, then manually copy (Ctrl+C / Cmd+C)."
      ),
      actionButton(
        "btn_select_all",
        "Select All Text",
        icon = icon("check-square"),
        class = "btn-primary mb-3"
      ),
      tags$textarea(
        id = "prompt_text_area",
        class = "form-control mb-4",
        style = "height: 50vh; font-family: monospace; resize: vertical;",
        readonly = TRUE,
        clipboard_text
      ),
      actionButton(
        "btn_back_menu_3",
        "Back to Menu",
        class = "btn-secondary w-100"
      )
    )
  )
}
