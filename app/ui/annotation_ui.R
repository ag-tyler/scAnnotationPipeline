# Manual-annotation UI.

annotation_panel <- function(sample_choices) {
  nav_panel(
    title = "Manual Annotation",
    value = "anno_tab",
    page_sidebar(
      sidebar = sidebar(
        title = "Annotation Controls",
        selectInput(
          "sample_idx",
          "1. Select Sample:",
          choices = sample_choices,
          selected = sample_choices[1]
        ),
        uiOutput("anno_status_badge"),
        actionButton(
          "btn_anno_next",
          "Next Sample",
          class = "btn-secondary btn-sm w-100 mt-2"
        ),
        hr(),
        uiOutput("cluster_selector"),
        uiOutput("current_cluster_annotation"),
        actionButton(
          "btn_cluster_next",
          "Next Cluster",
          class = "btn-secondary btn-sm w-100 mt-2"
        ),
        hr(),
        h5("3. Assign Cell Type"),
        uiOutput("cell_type_input_ui"),
        actionButton(
          "assign_btn",
          "Assign to Cluster",
          class = "btn-primary w-100"
        ),
        hr(),
        h5("4. Finalize Annotation"),
        actionButton(
          "preview_btn",
          "1. Preview Annotated Plot",
          class = "btn-info w-100"
        ),
        br(),
        actionButton(
          "save_btn",
          "2. Save Annotations to Disk",
          class = "btn-success w-100"
        ),
        hr(),
        h5("5. CNA Configuration"),
        uiOutput("ref_cell_selector"),
        uiOutput("pot_mal_cell_selector"),
        actionButton(
          "btn_save_refs",
          "Save CNA Config",
          class = "btn-warning w-100"
        ),
        hr(),
        actionButton(
          "btn_back_menu_2",
          "Back to Menu",
          class = "btn-secondary w-100"
        )
      ),
      navset_card_underline(
        nav_panel(
          "Cluster Exploration",
          fluidRow(
            column(
              6,
              h4("UMAP Reference"),
              imageOutput("umap_ref_plot", height = "auto")
            ),
            column(
              6,
              h4("Cluster Score Boxplot"),
              imageOutput("cluster_boxplot", height = "auto")
            )
          )
        ),
        nav_panel(
          "DE Marker Matches",
          h4("Matched Marker Genes for Selected Cluster"),
          DT::DTOutput("marker_table")
        ),
        nav_panel(
          "Final Annotation Preview",
          h4("Annotated UMAP"),
          p("Click 'Preview Annotated Plot' to render this view before saving."),
          plotOutput("final_umap_plot", height = "600px")
        )
      )
    )
  )
}
