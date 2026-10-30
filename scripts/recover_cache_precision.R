# Run from the repository root, with the app stopped. Preview is the default:
# Rscript scripts/recover_cache_precision.R Liu2022_Liver
# Rscript scripts/recover_cache_precision.R Liu2022_Liver --apply
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) < 1L || length(arguments) > 2L ||
    (length(arguments) == 2L && !identical(arguments[[2]], "--apply")) ||
    !nzchar(arguments[[1]]) || arguments[[1]] %in% c(".", "..") ||
    !identical(basename(arguments[[1]]), arguments[[1]])) {
  stop("Usage: Rscript scripts/recover_cache_precision.R DATASET [--apply]", call. = FALSE)
}
suppressPackageStartupMessages(library(data.table))
invisible(lapply(sort(list.files("util_scripts", pattern = "[.]R$", full.names = TRUE)), source))
config <- yaml::read_yaml("general_config.yaml")
dataset_dir <- file.path(config$paths$datasets_dir, arguments[[1]])
dataset_config <- yaml::read_yaml(file.path(dataset_dir, config$config_files$dataset))
selected_config <- yaml::read_yaml(file.path(dataset_dir, config$config_files$selected))
sample_dirs <- list.dirs(file.path(dataset_dir, config$dataset_paths$processed_dir), recursive = FALSE)
paths <- list(
  sample_dir_paths = sample_dirs,
  cell_file_paths = file.path(sample_dirs, dataset_config$std_names$cells),
  expmat_file_paths = file.path(sample_dirs, dataset_config$std_names$expmat),
  genes_file_paths = file.path(sample_dirs, dataset_config$std_names$genes)
)
print(recover_dataset_cache_precision(
  dataset_dir, paths, dataset_config, selected_config,
  dry_run = !"--apply" %in% arguments, state_filename = config$config_files$state
))
