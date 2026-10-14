# CNA server composition.

register_cna_server <- function(input, output, session, state, context) {
  register_cna_status_server(input, output, session, state, context)
  register_cna_compute_server(input, output, session, state, context)
  register_cna_cluster_server(input, output, session, state, context)
  register_cna_threshold_server(input, output, session, state, context)
  register_cna_summary_server(input, output, session, state, context)
  register_cna_reset_server(input, output, session, state, context)
}
