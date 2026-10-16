# Copy-number alteration analysis UI.

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
                  helpText("Cluster IDs are identical in the heatmap legend, selector, saved configuration, and later threshold views. Select one or more clusters with clear malignant copy-number alterations."),
                  selectizeInput(
                    "cna_selected_clusters",
                    label = "Select Malignant Subclones:",
                    choices = NULL,
                    multiple = TRUE,
                    options = list(placeholder = "e.g., Cluster 02, Cluster 04")
                  ),
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
