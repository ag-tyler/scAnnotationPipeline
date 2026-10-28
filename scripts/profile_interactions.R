# Profile ordinary interactive paths without starting a Shiny browser.
# Usage: Rscript scripts/profile_interactions.R [dataset_id_or_path] [iterations]

args <- commandArgs(trailingOnly = TRUE)
dataset_arg <- if (length(args) >= 1L) args[[1]] else "Che2021_Colorectal_2"
iterations <- if (length(args) >= 2L) as.integer(args[[2]]) else 5L
if (is.na(iterations) || iterations < 1L) stop("iterations must be a positive integer.")

repo_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
dataset_dir <- if (dir.exists(dataset_arg)) {
  normalizePath(dataset_arg, winslash = "/", mustWork = TRUE)
} else {
  normalizePath(file.path(repo_root, "datasets", dataset_arg), winslash = "/", mustWork = TRUE)
}

suppressPackageStartupMessages({
  library(data.table)
  library(shiny)
  library(bslib)
  library(shinyjs)
})
for (path in sort(list.files("util_scripts", pattern = "[.]R$", full.names = TRUE))) {
  source(path)
}
source("app/ui/dashboard_ui.R")
source("app/context.R")

benchmark_expression <- function(label, expression, n = iterations) {
  expression <- substitute(expression)
  environment <- parent.frame()
  elapsed <- replicate(
    n,
    system.time(eval(expression, envir = environment))[["elapsed"]]
  )
  data.frame(
    path = label,
    iterations = n,
    median_seconds = unname(stats::median(elapsed)),
    p95_seconds = unname(stats::quantile(elapsed, 0.95)),
    max_seconds = max(elapsed),
    stringsAsFactors = FALSE
  )
}

sample_dirs <- sort(list.dirs(
  file.path(dataset_dir, "processed_data"),
  recursive = FALSE,
  full.names = TRUE
))
dataset_config <- yaml::read_yaml(file.path(dataset_dir, "dataset_config.yaml"))
paths_list <- list(
  sample_dir_paths = sample_dirs,
  cell_file_paths = file.path(sample_dirs, dataset_config$std_names$cells),
  expmat_file_paths = file.path(sample_dirs, dataset_config$std_names$expmat),
  genes_file_paths = file.path(sample_dirs, dataset_config$std_names$genes)
)
selected_config_path <- file.path(dataset_dir, "selected_config.yaml")
selected_config <- yaml::read_yaml(selected_config_path)
pipeline_state <- load_pipeline_state(dataset_dir, basename(dataset_dir))
storage_state <- tryCatch(
  load_dataset_storage_state(dataset_dir, basename(dataset_dir)),
  error = function(error) new_dataset_storage_state(basename(dataset_dir))
)
results_dir <- file.path(dataset_dir, "results")

results <- list()
results[[length(results) + 1L]] <- benchmark_expression(
  "Start Menu pipeline summary",
  summarize_pipeline_overview(pipeline_state),
  max(20L, iterations)
)
overview <- summarize_pipeline_overview(pipeline_state)
results[[length(results) + 1L]] <- benchmark_expression(
  "Start Menu pipeline UI",
  pipeline_status_overview_ui(overview),
  max(20L, iterations)
)
if (dataset_storage_cache_is_retired(storage_state)) {
  results[[length(results) + 1L]] <- benchmark_expression(
    "Start Menu archive audit",
    dataset_archive_output_audit(storage_state, dataset_dir)
  )
  archive_audit <- dataset_archive_output_audit(storage_state, dataset_dir)
  readiness <- NULL
  results[[length(results) + 1L]] <- benchmark_expression(
    "Start Menu storage UI",
    dataset_storage_card_ui(storage_state, archive_audit = archive_audit),
    max(20L, iterations)
  )
} else {
  results[[length(results) + 1L]] <- benchmark_expression(
    "Start Menu storage readiness",
    dataset_cleanup_readiness(
      pipeline_state,
      paths_list,
      selected_config,
      selected_config_path,
      results_dir,
      dataset_dir
    )
  )
  readiness <- dataset_cleanup_readiness(
    pipeline_state,
    paths_list,
    selected_config,
    selected_config_path,
    results_dir,
    dataset_dir
  )
  results[[length(results) + 1L]] <- benchmark_expression(
    "Start Menu storage UI",
    dataset_storage_card_ui(storage_state, readiness),
    max(20L, iterations)
  )
}

configured_samples <- names(pipeline_state$samples)[vapply(
  names(pipeline_state$samples),
  function(sample_name) {
    get_pipeline_step(pipeline_state, "cna_configuration", sample_name)$status %in%
      c("completed", "skipped")
  },
  logical(1)
)]
if (length(configured_samples) > 0L && !dataset_storage_cache_is_retired(storage_state)) {
  profile_sample <- configured_samples[[1]]
  results[[length(results) + 1L]] <- benchmark_expression(
    paste0("CNA status preflight: ", profile_sample),
    cna_sample_preflight(
      profile_sample,
      selected_config,
      dataset_dir,
      pipeline_state = pipeline_state,
      validate_expression = FALSE
    )
  )
}

annotation_samples <- names(pipeline_state$samples)[vapply(
  names(pipeline_state$samples),
  function(sample_name) {
    pipeline_step_readiness(pipeline_state, "annotation", sample_name)$ready &&
      file.exists(file.path(results_dir, sample_name, "2_de_plots", "all_marker_matches.csv"))
  },
  logical(1)
)]
if (length(annotation_samples) > 0L && !dataset_storage_cache_is_retired(storage_state)) {
  annotation_sample <- annotation_samples[[1]]
  annotation_index <- match(annotation_sample, basename(sample_dirs))
  context <- create_app_context()
  complete_markers <- context$resources$marker_genes[, .(cell_type, symbol)]
  complete_markers <- data.table::rbindlist(list(
    complete_markers,
    data.table::data.table(
      cell_type = "Housekeeping_artifact",
      symbol = context$resources$housekeeping_genes
    ),
    data.table::data.table(
      cell_type = "Mito_artifact",
      symbol = context$resources$mt_genes
    )
  ))
  results[[length(results) + 1L]] <- benchmark_expression(
    paste0("Annotation sample load: ", annotation_sample),
    cell_type_annotation_setup(
      annotation_index,
      paths_list,
      results_dir,
      dataset_dir,
      complete_markers,
      dataset_config,
      selected_config
    ),
    max(1L, min(iterations, 3L))
  )
}

timings <- data.table::rbindlist(results, use.names = TRUE, fill = TRUE)
print(timings, row.names = FALSE, digits = 4)
cat(
  "Dataset:", basename(dataset_dir),
  "| samples:", length(sample_dirs),
  "| storage:", storage_state$status,
  if (!is.null(readiness)) paste0(" | cache files: ", readiness$cache$file_count) else "",
  if (!is.null(readiness)) paste0(" | cache size: ", format_storage_bytes(readiness$cache$size_bytes)) else "",
  if (!is.null(readiness)) paste0(" | cleanup requirements: ", length(readiness$reasons)) else "",
  "\n"
)
