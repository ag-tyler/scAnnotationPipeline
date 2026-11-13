# Development-only E00 harness. No application computation is changed.
# Run from repository root; see scripts/performance/README.md.
local({
  arguments <- commandArgs(trailingOnly = TRUE)
  if ("--help" %in% arguments) {
    cat("Rscript scripts/benchmark_computation.R --out <new directory> [--case synthetic|boundaries|tang]\n",
      "[--dataset datasets/Tang2026_Colorectal --sample CRC_T1 --cell-limit 128]\n",
      "[--repeats 3 --profile all|clustering|cache --policy exact|numerical]\n",
      "[--timeout-seconds 900 --max-memory-gb 12]\n")
    return(invisible(NULL))
  }
  if (!length(arguments)) stop("--out is required; use --help")
  if (length(arguments) %% 2L) stop("Arguments must be --name value pairs")
  keys <- sub("^--", "", arguments[seq.int(1L, length(arguments), by = 2L)])
  options <- as.list(stats::setNames(arguments[seq.int(2L, length(arguments), by = 2L)], keys))
  allowed <- c("out", "case", "dataset", "sample", "cell-limit", "repeats", "profile", "policy", "timeout-seconds", "max-memory-gb")
  if (any(!keys %in% allowed) || anyDuplicated(keys)) stop("Unknown or duplicate argument")
  value <- function(name, default) if (is.null(options[[name]])) default else options[[name]]
  if (is.null(options$out)) stop("--out is required; output must not already exist")
  stopifnot(nzchar(Sys.setlocale("LC_ALL", if (.Platform$OS.type == "windows")
    "English_United States.utf8" else "C.UTF-8")))
  repo <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  suppressPackageStartupMessages(library(data.table))
  .datatable.aware <- TRUE
  for (name in c("equivalence.R", "workload.R", "harness.R")) source(file.path(repo, "scripts", "performance", name))
  perf_run_experiment(repo, options$out, case = value("case", "synthetic"),
    dataset = value("dataset", file.path(repo, "datasets", "Tang2026_Colorectal")),
    sample = value("sample", "CRC_T1"), cell_limit = as.integer(value("cell-limit", "128")),
    repeats = as.integer(value("repeats", "3")), profile = value("profile", "all"),
    policy = value("policy", "exact"), timeout_seconds = as.numeric(value("timeout-seconds", "900")),
    max_memory_bytes = as.numeric(value("max-memory-gb", "12")) * 1e9)
})
