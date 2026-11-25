# Load one qs2 cache file into your own R session.
# source("scripts/load_dataset_cache.R")
# x <- load_cache_file("datasets/MyStudy/cache/expmat_filt_Sample_A.qs2")
# Accepts relative or absolute paths; returns the stored object unchanged.
# This personal reader does not perform pipeline cache validation or recovery.

load_cache_file <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(trimws(path))) {
    stop("path must be one non-empty relative or absolute file path.", call. = FALSE)
  }
  path <- path.expand(path)
  if (!file.exists(path)) stop("Cache file does not exist: ", path, call. = FALSE)
  if (dir.exists(path)) stop("Cache path is a directory, not a file: ", path, call. = FALSE)
  if (file.access(path, 4L) != 0L) stop("Cache file is not readable: ", path, call. = FALSE)
  if (!requireNamespace("qs2", quietly = TRUE)) {
    stop("Install 'qs2' to load cache files: install.packages('qs2').", call. = FALSE)
  }
  tryCatch(qs2::qs_read(path), error = function(error) {
    stop("Could not read qs2 cache file '", path, "': ", conditionMessage(error), call. = FALSE)
  })
}
