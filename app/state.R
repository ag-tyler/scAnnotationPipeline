# Per-session mutable application state.

create_app_state <- function(context) {
  shiny::reactiveValues(
    # Dataset/session configuration.
    paths_list = NULL,
    dataset_config = NULL,
    samples_config = NULL,
    live_selected_config = NULL,
    complete_markers = NULL,
    results_dir_path = NULL,
    selected_config_path = NULL,
    pipeline_state = NULL,
    pipeline_state_path = NULL,
    dataset_dir_path = NULL,
    config = NULL,

    # Active annotation state.
    cells_filt = NULL,
    all_matches = NULL,
    cells_raw = NULL,
    sample_name = NULL,
    res = NULL,
    final_plot = NULL,
    annotation_dirty = FALSE,
    annotation_loaded_index = NULL,
    annotation_pending_navigation = NULL,

    # Active CNA preview state.
    cna_preview_res = NULL
  )
}
