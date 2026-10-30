# Top-level server composition.

build_app_server <- function(context) {
  force(context)

  function(input, output, session) {
    nav_hide("main_nav", target = "menu_tab")
    nav_hide("main_nav", target = "clipboard_tab")
    nav_hide("main_nav", target = "res_tab")
    nav_hide("main_nav", target = "anno_tab")
    nav_hide("main_nav", target = "cna_tab")
    updateNavbarPage(session, "main_nav", selected = "dataset_tab")

    state <- create_app_state(context, session_id = session$token)
    session_id <- shiny::isolate(state$session_id)
    session_started_at <- shiny::isolate(state$session_started_at)
    message(
      "Shiny session started: ", session_id,
      " at ", session_started_at
    )

    register_dataset_server(input, output, session, state, context)
    register_dashboard_server(input, output, session, state, context)
    register_storage_server(input, output, session, state, context)
    register_snapshot_server(input, output, session, state, context)
    register_resolution_server(input, output, session, state, context)
    register_annotation_server(input, output, session, state, context)
    register_cna_server(input, output, session, state, context)
  }
}
