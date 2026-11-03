# Browser select updates are asynchronous. A previous dataset's index can be
# observed after its replacement paths have been published. Invalid/transient
# selection is a waiting state; workflow corruption is still reported by the
# normal pipeline/preflight validators once a valid sample is selected.
app_sample_index <- function(state, value) {
  shiny::req(state$paths_list, !("dataset_load" %in% shiny::isolate(state$active_actions)))
  shiny::req(length(value) == 1L, is.numeric(value) || is.character(value))
  index <- suppressWarnings(as.numeric(value))
  shiny::req(length(index) == 1L, is.finite(index), index == floor(index),
    index >= 1, index <= length(state$paths_list$sample_dir_paths))
  index
}

cna_analysis_context <- function(state, sample, view) {
  list(dataset = state$dataset_dir_path, generation = state$dataset_generation,
    sample = sample, view = view)
}

require_cna_analysis_view <- function(state, input, view, completed_step) {
  index <- app_sample_index(state, input$cna_sample_idx)
  sample <- basename(state$paths_list$sample_dir_paths[[index]])
  shiny::req(identical(input$main_nav, "cna_tab"), input$cna_main_views %in% view,
    identical(state$cna_view_context, cna_analysis_context(state, sample, input$cna_main_views)),
    !dataset_storage_cache_is_retired(state$storage_state),
    !isTRUE(get_pipeline_step(state$pipeline_state, "cna_configuration", sample)$details$omitted_by_user),
    identical(get_pipeline_step(state$pipeline_state, completed_step, sample)$status, "completed"),
    pipeline_step_readiness(state$pipeline_state, completed_step, sample)$ready)
  sample
}
