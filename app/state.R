# Per-session mutable application state.

new_app_session_id <- function(token = NULL) {
  if (
    length(token) == 1L && !is.na(token) &&
      nzchar(trimws(as.character(token)))
  ) {
    return(as.character(token))
  }

  paste0(
    "session-", Sys.getpid(), "-",
    format(Sys.time(), "%Y%m%dT%H%M%OS6", tz = "UTC"), "-",
    sprintf("%08x", sample.int(.Machine$integer.max, 1L))
  )
}


app_session_timestamp <- function(timestamp = Sys.time()) {
  if (exists("format_pipeline_timestamp", mode = "function")) {
    return(format_pipeline_timestamp(timestamp))
  }
  paste0(format(as.POSIXct(timestamp, tz = "UTC"), "%Y-%m-%dT%H:%M:%OS3", tz = "UTC"), "Z")
}

create_app_state <- function(
  context,
  session_id = NULL,
  session_started_at = Sys.time()
) {
  shiny::reactiveValues(
    # Dataset/session configuration.
    session_id = new_app_session_id(session_id),
    session_started_at = app_session_timestamp(session_started_at),
    session_logged_datasets = character(),
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
    cna_preview_res = NULL,
    cna_preview_sample = NULL,
    cna_preview_fingerprint = NULL
  )
}
