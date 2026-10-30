# Copy-number alteration analysis UI.


cna_threshold_guidance_ui <- function() {
  tags$div(
    class = "alert alert-info small cna-threshold-guidance py-2",
    strong("Threshold rules (tested cells)"),
    tags$ul(
      class = "mb-1 mt-1 ps-3",
      tags$li(
        strong("Above both malignant thresholds (m_x and m_y): "),
        "configured potentially malignant or Unassigned/NA cells become Malignant."
      ),
      tags$li(
        strong("Below both non-malignant thresholds (nm_x and nm_y): "),
        "retain their prior annotation; must hold for every tested subclone."
      ),
      tags$li(
        strong("Gray zone: "),
        "other tested, non-Malignant cells become Unassigned/NA."
      )
    ),
    tags$details(
      tags$summary("Boundary details"),
      tags$p(
        class = "mb-0 mt-1",
        "Comparisons are strict (> malignant, < non-malignant). Equal Y thresholds are allowed; cells exactly on their shared boundary meet neither Y condition for that subclone."
      )
    )
  )
}


cna_cluster_navigator_ui <- function(identity_map, selected = character()) {
  clusters <- identity_map$clusters
  selected <- intersect(as.character(selected), as.character(clusters$cluster_id))
  choice_names <- lapply(seq_len(nrow(clusters)), function(index) {
    cluster <- clusters[index, ]
    tags$span(
      class = "d-flex align-items-center gap-2 cna-cluster-choice-label",
      tags$span(
        class = "d-inline-block flex-shrink-0",
        style = paste0(
          "width: 0.9rem; height: 1.8rem; border: 1px solid #212529; ",
          "background-color: ", cluster$color, ";"
        ),
        `aria-hidden` = "true"
      ),
      tags$span(
        strong(sprintf("Position %02d", cluster$display_position)),
        " · ", cluster$label,
        " · ", cluster$cell_count,
        if (cluster$cell_count == 1L) " cell" else " cells"
      )
    )
  })

  tags$div(
    class = "cna-cluster-navigator",
    tags$p(
      "Ordered from the top to the bottom of the heatmap cluster bar. Select by position and stable cluster ID; colour is only a secondary cue.",
      class = "small text-body-secondary"
    ),
    tags$div(
      class = "border rounded p-2 overflow-auto",
      style = "max-height: 430px;",
      checkboxGroupInput(
        "cna_selected_clusters",
        label = "Potentially malignant subtrees:",
        selected = selected,
        choiceNames = choice_names,
        choiceValues = as.character(clusters$cluster_id)
      )
    )
  )
}


cna_cluster_selection_summary_ui <- function(identity_map, selected = character()) {
  selected <- as.character(selected)
  clusters <- identity_map$clusters[
    as.character(identity_map$clusters$cluster_id) %in% selected,
    , drop = FALSE
  ]
  if (nrow(clusters) == 0L) {
    return(tags$div(
      class = "alert alert-secondary py-2 mt-3 mb-0",
      "No subtrees selected."
    ))
  }
  tags$div(
    class = "alert alert-info py-2 mt-3 mb-0 cna-cluster-selection-summary",
    strong("Selection to save:"),
    tags$ul(
      class = "mb-0 mt-1 ps-3",
      lapply(seq_len(nrow(clusters)), function(index) {
        cluster <- clusters[index, ]
        tags$li(paste0(
          sprintf("Position %02d", cluster$display_position),
          " / ", cluster$label,
          " / ", cluster$cell_count,
          if (cluster$cell_count == 1L) " cell" else " cells"
        ))
      })
    )
  )
}

cna_panel <- function(sample_choices) {
  nav_panel(
    title = "CNA Analysis",
    value = "cna_tab",
    page_sidebar(
      sidebar = sidebar(
        title = "CNA Pipeline Controls",
        selectInput(
          "cna_sample_idx",
          "1. Select Sample:",
          choices = sample_choices
        ),
        textAreaInput(
          "cna_sample_notes",
          "Sample Notes:",
          rows = 4,
          placeholder = "Record observations for this sample..."
        ),
        actionButton(
          "btn_save_cna_notes",
          "Save Notes",
          class = "btn-outline-secondary btn-sm w-100"
        ),
        actionButton(
          "btn_cna_next",
          "Next Sample",
          class = "btn-secondary btn-sm w-100 mt-2"
        ),
        hr(),
        h5("Pipeline Steps", class = "mb-3"),
        actionButton(
          "btn_cna_compute_heatmaps",
          "1. Compute CNA & Heatmaps",
          class = "btn-primary w-100 mb-2"
        ),
        actionButton(
          "btn_cna_batch_compute",
          "Batch Compute (All Samples)",
          icon = icon("layer-group"),
          class = "btn-outline-primary btn-sm w-100 mb-2"
        ),
        actionButton(
          "btn_cna_go_malig_clust",
          "2. Select Malignant Clusters",
          class = "btn-info w-100 mb-2"
        ),
        actionButton(
          "btn_cna_compute_sig_cor",
          "3. Compute Signal & Cor",
          class = "btn-primary w-100 mb-2"
        ),
        actionButton(
          "btn_cna_go_thresholds",
          "4. Select Thresholds",
          class = "btn-info w-100 mb-2"
        ),
        actionButton(
          "btn_cna_go_summary",
          "5. Assign & Summary",
          class = "btn-warning w-100 mb-2"
        ),
        hr(),
        actionButton(
          "btn_cna_reset",
          "Reset Sample CNA",
          icon = icon("trash-alt"),
          class = "btn-danger w-100 mb-2"
        ),
        actionButton(
          "btn_cna_back_menu",
          "Back to Menu",
          class = "btn-secondary w-100"
        )
      ),
      navset_hidden(
        id = "cna_main_views",
        nav_panel(
          "cna_view_default",
          div(
            class = "container mt-5 text-center",
            h3(textOutput("cna_header_text")),
            p(
              "Select a sample from the sidebar to check its persisted workflow status.",
              class = "text-muted"
            ),
            uiOutput("cna_eligibility_ui"),
            uiOutput("cna_status_ui")
          )
        ),
        nav_panel(
          "cna_view_select_malignant",
          h3("2. Select Malignant Clusters"),
          p("Adjust the slider to split the tree into 'k' clusters. The heatmap will update to visually separate or color these clusters. Select the malignant ones below."),
          fluidRow(
            column(
              3,
              card(
                card_header("Cluster Settings"),
                card_body(
                  sliderInput(
                    "cna_k_clusters",
                    "Number of Clusters (k):",
                    min = 2,
                    max = 20,
                    value = 7,
                    step = 1
                  ),
                  hr(),
                  helpText("Stable Cluster IDs are used in the saved configuration and later threshold views. The navigator orders them by their actual position in the heatmap bar."),
                  uiOutput("cna_cluster_navigator_ui"),
                  uiOutput("cna_cluster_selection_summary"),
                  hr(),
                  actionButton(
                    "btn_cna_save_malignant",
                    "Save Clusters",
                    icon = icon("cogs"),
                    class = "btn-success w-100"
                  )
                )
              )
            ),
            column(
              9,
              plotOutput("cna_combined_heatmap_plot", height = "850px")
            )
          )
        ),
        nav_panel(
          "cna_view_thresholds",
          h3("Malignant Threshold Selection"),
          p("Adjust the malignant and non-malignant thresholds for each subclone using the tabs below."),
          uiOutput("cna_dynamic_thresholds_ui")
        ),
        nav_panel(
          "cna_view_summary",
          h3("CNA Summary & Final Assignment"),
          p("The preview is generated automatically when this step opens and reused while its inputs remain current. Use Refresh Preview to re-check it, then finalize when satisfied."),
          fluidRow(
            column(
              6,
              actionButton(
                "btn_cna_preview_summary",
                "Refresh Preview",
                icon = icon("eye"),
                class = "btn-info w-100 mb-3"
              )
            ),
            column(
              6,
              shinyjs::disabled(
                actionButton(
                  "btn_cna_save_summary",
                  "2. Finalize & Save CNA Analysis",
                  icon = icon("save"),
                  class = "btn-success w-100 mb-3"
                )
              )
            )
          ),
          h5("Optional CNA Values Table"),
          p("Export the reusable values table separately if needed. Finalizing CNA does not export it automatically.", class = "text-muted small"),
          fluidRow(
            column(
              6,
              uiOutput("cna_values_export_status")
            ),
            column(
              6,
              actionButton(
                "btn_cna_export_values",
                "Export/Re-export CNA Values Table",
                icon = icon("file-export"),
                class = "btn-outline-secondary w-100 mb-3"
              )
            )
          ),
          navset_card_underline(
            id = "cna_preview_tabs",
            nav_panel(
              "Scatter Plots",
              value = "cna_preview_scatter",
              br(),
              uiOutput("cna_preview_scatter_ui")
            ),
            nav_panel(
              "Before / After UMAP",
              value = "cna_preview_umap_comparison",
              br(),
              fluidRow(
                column(
                  6,
                  h4("Before CNA", class = "text-center"),
                  plotOutput("cna_preview_umap_pre", height = "600px")
                ),
                column(
                  6,
                  h4("Preview after CNA", class = "text-center"),
                  plotOutput("cna_preview_umap", height = "600px")
                )
              )
            ),
            nav_panel(
              "Summary Heatmap",
              value = "cna_preview_heatmap_tab",
              br(),
              plotOutput("cna_preview_heatmap", height = "700px")
            )
          )
        )
      )
    )
  )
}
