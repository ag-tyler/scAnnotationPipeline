# Synthetic, disposable CNA export profiler. No biological dataset is accessed.
# Rscript scripts/profile_cna_export.R [genes=5000] [cells=3000] [--export]
local({
  arguments <- commandArgs(trailingOnly = TRUE)
  dimensions <- arguments[!startsWith(arguments, "--")]
  gene_count <- if (length(dimensions)) as.integer(dimensions[[1]]) else 5000L
  cell_count <- if (length(dimensions) > 1L) as.integer(dimensions[[2]]) else 3000L
  stopifnot(is.finite(gene_count), gene_count > 0L, is.finite(cell_count), cell_count > 0L)
  suppressPackageStartupMessages(library(data.table))
  for (path in sort(list.files("util_scripts", pattern = "[.]R$", full.names = TRUE))) source(path)
  root <- tempfile("cna-export-profile-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  set.seed(3988)
  cna <- list(gene = paste0("GENE", seq_len(gene_count)),
    chr = sprintf("%02d", rep(1:22, length.out = gene_count)),
    start_pos = seq_len(gene_count) * 1000L)
  for (index in seq_len(cell_count)) {
    cna[[paste0("synthetic_cell_", index)]] <- round(rnorm(gene_count, sd = 0.25), 4)
  }
  setDT(cna)
  columns <- paste0("synthetic_cell_", seq_len(min(25L, cell_count)))
  old_conversion <- function(matrix, columns) {
    melt(as.data.table(matrix)[, c("gene", "chr", "start_pos", columns), with = FALSE],
      id.vars = c("gene", "chr", "start_pos"), measure.vars = columns,
      variable.name = "cell_name", value.name = "cna", variable.factor = FALSE)
  }
  profile_conversion <- function(label, converter) {
    invisible(converter(cna, columns)) # warm method/JIT dispatch before profiling
    gc()
    allocation_file <- file.path(root, paste0(label, ".allocations"))
    if (capabilities("profmem")) Rprofmem(allocation_file, threshold = 0)
    elapsed <- system.time(for (iteration in 1:5) invisible(converter(cna, columns)))[["elapsed"]]
    if (capabilities("profmem")) Rprofmem(NULL)
    allocation_lines <- if (file.exists(allocation_file)) readLines(allocation_file) else character()
    bytes <- sum(as.numeric(sub(" .*", "", allocation_lines[grepl("^[0-9]+", allocation_lines)])))
    data.frame(conversion = label, genes = gene_count, cells = cell_count,
      chunk_cells = length(columns), iterations = 5, elapsed_seconds = elapsed,
      allocated_mb = bytes / 1024^2)
  }
  print(rbind(profile_conversion("previous", old_conversion), profile_conversion("bounded", cna_matrix_to_long)),
    row.names = FALSE)
  if ("--export" %in% arguments) {
    dataset_dir <- file.path(root, "dataset")
    dir.create(dataset_dir)
    cache_save_data(cna, "cna_matrix_Synthetic.qs2", dataset_dir)
    last_stage <- NULL
    stages <- list()
    result <- export_cna_values_table("Synthetic", dataset_dir, file.path(root, "results"),
      progress_callback = function(stage, progress, detail, elapsed_seconds) {
        if (!identical(stage, last_stage)) {
          message(stage, " | ", detail)
          stages[[length(stages) + 1L]] <<- data.frame(stage = stage, elapsed_seconds = elapsed_seconds)
        }
        last_stage <<- stage
      })
    print(do.call(rbind, stages), row.names = FALSE)
    print(data.frame(rows = result$row_count, csv_mb = result$csv_size_bytes / 1024^2,
      elapsed_seconds = result$elapsed_seconds,
      current = cna_values_export_status("Synthetic", dataset_dir, file.path(root, "results"))$current))
  }
})
