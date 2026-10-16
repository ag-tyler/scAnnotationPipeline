# Resolution-selection UI.

resolution_panel <- function(sample_choices) {
  nav_panel(
    title = "Resolution Selection",
    value = "res_tab",
    page_sidebar(
      sidebar = sidebar(
        title = "Selection Controls",
        selectInput(
          "res_sample_idx",
          "1. Select Sample:",
          choices = sample_choices
        ),
        uiOutput("res_status_badge"),
        textAreaInput(
          "res_sample_notes",
          "Sample Notes:",
          rows = 4,
          placeholder = "Record observations for this sample..."
        ),
        actionButton(
          "btn_save_res_notes",
          "Save Notes",
          class = "btn-outline-secondary btn-sm w-100"
        ),
        hr(),
        uiOutput("res_radio_ui"),
        actionButton(
          "btn_save_res",
          "Save Resolution",
          class = "btn-success w-100"
        ),
        hr(),
        h6("Targeted Reanalysis", class = "mt-2"),
        actionButton(
          "btn_rerun_single_de",
          "Rerun DE for Sample",
          icon = icon("sync"),
          class = "btn-warning w-100"
        ),
        hr(),
        actionButton(
          "btn_back_menu_1",
          "Back to Menu",
          class = "btn-secondary w-100"
        )
      ),
      h3(textOutput("res_header_text")),
      p("Click through the tabs below to view each resolution in full detail."),
      uiOutput("res_plots_tabs")
    )
  )
}
