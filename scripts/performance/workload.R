perf_source_utilities <- function(root) {
  env <- new.env(parent = globalenv())
  env$.datatable.aware <- TRUE
  for (path in sort(list.files(file.path(root, "util_scripts"), pattern = "[.]R$", full.names = TRUE))) {
    sys.source(path, env)
  }
  env
}

perf_environment <- function() {
  packages <- c("Matrix", "irlba", "uwot", "Seurat", "data.table", "matkot", "caTools", "qs2")
  list(R = R.version.string, platform = R.version$platform,
    packages = setNames(lapply(packages, function(p) as.character(utils::packageVersion(p))), packages),
    data_table_threads = data.table::getDTthreads(), seurat_threads = Seurat::getThreads(verbose = FALSE),
    BLAS = sessionInfo()$BLAS, LAPACK = sessionInfo()$LAPACK,
    locale = Sys.getlocale(), thread_environment = Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS")))
}

perf_fixture <- function(env, boundary = FALSE) {
  set.seed(if (boundary) 702L else 701L)
  sizes <- if (boundary) c(99L, 100L, 101L, 4720L) else c(97L, 100L, 103L, 120L)
  genes <- sprintf("GENE%05d", seq_len(sum(sizes)))
  cells <- sprintf("Synthetic_cell_%03d", 1:64)
  chromosome <- rep(sprintf("%02d", 1:4), sizes)
  gene_wave <- rep(seq(-2, 2, length.out = 121), length.out = length(genes))
  phase <- seq(0, 2 * pi, length.out = length(cells) + 1L)[-1L]
  means <- 8 * exp(outer(gene_wave, sin(phase)) +
    outer(as.numeric(chromosome) - 2.5, cos(phase)) / 3)
  raw <- matrix(stats::rpois(length(means), pmax(means, 0.1)), nrow = length(genes),
    dimnames = list(genes, cells))
  if (boundary) raw[nrow(raw) - 1L, ] <- raw[nrow(raw), ] # exact gene-mean ties
  metadata <- env$build_cells(cells)
  metadata$sample <- "Synthetic"
  metadata$cell_type <- rep(c("Reference_A", "Reference_B", "TumorLike", "TumorLike"), each = 16L)
  metadata$complexity <- colSums(raw != 0)
  metadata$patient <- "0007"
  config <- list(project_info = list(dataset_id = "Synthetic"), std_names = list(
    expmat = "Exp_data_UMIcounts.mtx", genes = "Genes.txt", cells = "Cells.csv", samples = "Samples.csv"),
    params = list(min_genes = 3, target_sum = 1e5, log2_expr_threshold = 0.1,
      pca_nv = 5L, seed = 3988L, resolutions = c(0.1, 0.5, 1),
      umap = list(spread = 5, min_dist = 0.1), max_marker_genes = 20L,
      de = list(num_genes = 40L, max_match_genes = 20L, min_marker_found = 3L)))
  selected <- env$setup_selected_config("Synthetic")
  selected$resolutions$Synthetic <- 0.5
  selected$cna_ref_cells$Synthetic <- c("Reference_A", "Reference_B")
  selected$cna_pot_mal_cells$Synthetic <- "TumorLike"
  selected$cna_ward_ref_cluster$Synthetic <- list(list(k = 2L, cluster = 1L), list(k = 2L, cluster = 2L))
  selected$cna_thresholds$Synthetic <- rep(list(list(m_x = 0.25, m_y = 0.05, nm_x = 0.1, nm_y = 0.01)), 2L)
  list(id = if (boundary) "synthetic_boundaries" else "synthetic_main", sample = "Synthetic",
    raw = methods::as(Matrix::Matrix(raw, sparse = TRUE), "dgCMatrix"), cells = metadata,
    config = config, selected = selected,
    gene_positions = data.table::data.table(symbol = genes, chromosome_name = chromosome,
      start_position = sequence(sizes) * 1000L),
    markers = data.table::data.table(cell_type = rep(c("Reference_A", "Reference_B", "TumorLike"), each = 30),
      symbol = genes[1:90]), provenance = list(kind = "synthetic", seed = if (boundary) 702L else 701L,
        full_size_acceptance = FALSE, decision_origin = "fixed harness decisions"))
}

perf_prepare_workspace <- function(fixture, directory) {
  sample_dir <- file.path(directory, "processed_data", fixture$sample)
  dir.create(sample_dir, recursive = TRUE)
  dir.create(file.path(directory, "results"))
  std <- fixture$config$std_names
  Matrix::writeMM(fixture$raw, file.path(sample_dir, std$expmat))
  writeLines(rownames(fixture$raw), file.path(sample_dir, std$genes))
  data.table::fwrite(fixture$cells, file.path(sample_dir, std$cells))
  yaml::write_yaml(fixture$config, file.path(directory, "dataset_config.yaml"))
  yaml::write_yaml(fixture$selected, file.path(directory, "selected_config.yaml"))
  list(sample_dir_paths = sample_dir, cell_file_paths = file.path(sample_dir, std$cells),
    genes_file_paths = file.path(sample_dir, std$genes), expmat_file_paths = file.path(sample_dir, std$expmat))
}

perf_observer <- function(env, directory, capture) {
  state <- new.env(parent = emptyenv())
  state$active <- TRUE
  state$capturing <- capture
  state$artifacts <- list()
  state$stages <- list()
  state$write_seconds <- 0
  state$counts <- c(neighbor_graph_builds = 0L, cache_deserializations = 0L,
    cache_load_calls = 0L, cache_validation_calls = 0L, melts = 0L, casts = 0L)
  state$save <- function(key, object, kind = "exact") {
    if (!state$capturing || !state$active) return(invisible(NULL))
    start <- proc.time()[["elapsed"]]
    file <- sprintf("artifact_%03d.rds", length(state$artifacts) + 1L)
    if (!is.null(state$artifacts[[key]])) file <- state$artifacts[[key]]$file
    saveRDS(object, file.path(directory, file), compress = FALSE)
    state$artifacts[[key]] <- list(file = file, kind = kind)
    state$write_seconds <- state$write_seconds + proc.time()[["elapsed"]] - start
    invisible(NULL)
  }
  restorations <- list()
  install <- function(where, name, make) {
    original <- get(name, where, inherits = FALSE)
    locked <- bindingIsLocked(name, where)
    if (locked) unlockBinding(name, where)
    assign(name, make(original), where)
    if (locked) lockBinding(name, where)
    restorations[[length(restorations) + 1L]] <<- list(where = where, name = name, original = original, locked = locked)
  }
  state$restore <- function() {
    for (record in rev(restorations)) {
      if (record$locked) unlockBinding(record$name, record$where)
      assign(record$name, record$original, record$where)
      if (record$locked) lockBinding(record$name, record$where)
    }
    invisible(NULL)
  }
  # Timing runs execute untouched functions/namespaces. Counter/stage probes
  # belong only to capture runs, whose outputs are checked against timing runs.
  if (!capture) return(state)
  timed <- function(original, name, counter = NULL, observe = NULL) {
    force(original); force(name); force(counter); force(observe)
    function(...) {
      if (!state$active) return(original(...))
      before_counts <- state$counts
      if (!is.null(counter)) state$counts[[counter]] <- state$counts[[counter]] + 1L
      start <- proc.time()[["elapsed"]]
      before_write <- state$write_seconds
      success <- FALSE
      on.exit({
        state$stages[[length(state$stages) + 1L]] <- list(stage = name, completed = success,
          elapsed_seconds = proc.time()[["elapsed"]] - start - (state$write_seconds - before_write),
          counts = state$counts - before_counts)
      }, add = TRUE)
      answer <- withVisible(original(...))
      success <- TRUE
      if (capture && !is.null(observe)) {
        # Do not force NSE plotting columns such as umap1/cell_num_hclust.
        expressions <- head(as.list(substitute(list(...)))[-1L], 2L)
        observe(answer$value, lapply(expressions, eval, envir = parent.frame()))
      }
      if (answer$visible) answer$value else invisible(answer$value)
    }
  }
  stages <- c("load_filter_cells_expmat", "run_expmat_pca", "run_expmat_umap", "louvain_clustering",
    "single_de_analysis", "mean_diff_exp", "compute_cna", "compute_cna_and_cache",
    "hclust_cluster_heatmap", "compute_signal_cor_cna", "apply_cna_thresholds",
    "score_and_fill_cells", "cna_heatmap", "plot_clusters")
  for (name in stages) {
    local({
      stage_name <- name
      observer <- switch(stage_name,
        run_expmat_pca = function(value, args) state$save("pca", value, "pca"),
        run_expmat_umap = function(value, args) state$save("umap", value, "embedding"),
        compute_cna = function(value, args) state$save("raw_cna", value, "table"),
        mean_diff_exp = function(value, args) state$save("de_ranked", value, "table"),
        apply_cna_thresholds = function(value, args) state$save("final_assignments", value, "cells"),
        score_and_fill_cells = function(value, args) state$save("signature_scores", value, "table"),
        cna_heatmap = function(value, args) state$save("heatmap_data", args[[1]], "table"),
        plot_clusters = function(value, args) state$save(paste0("cluster_plot_data/", args[[2]]), args[[1]], "cells"), NULL)
      install(env, stage_name, function(original) timed(original, stage_name, observe = observer))
    })
  }
  for (entry in list(c("cache_load_data", "cache_load_calls"), c("cache_check_valid", "cache_validation_calls"))) {
    local({
      method <- entry[[1]]; counter <- entry[[2]]
      install(env, method, function(original) timed(original, method, counter))
    })
  }
  install(asNamespace("Seurat"), "FindNeighbors", function(original) timed(original, "FindNeighbors", "neighbor_graph_builds"))
  install(asNamespace("Seurat"), "FindClusters", function(original) {
    force(original)
    function(object, ...) {
      if (state$active && capture) {
        parameters <- list(...)
        for (resolution in parameters$resolution) state$save(paste0("graph_", resolution), object, "graph")
      }
      original(object, ...)
    }
  })
  install(asNamespace("qs2"), "qs_read", function(original) timed(original, "qs_read", "cache_deserializations"))
  install(asNamespace("data.table"), "melt", function(original) timed(original, "melt", "melts"))
  install(asNamespace("data.table"), "dcast", function(original) timed(original, "dcast", "casts"))
  state
}

perf_cache_controls <- function(env, root, on_measure = NULL) {
  outcomes <- list()
  for (scenario in c("valid", "missing", "corrupt", "stale", "recovery")) {
    directory <- file.path(root, scenario)
    dir.create(directory, recursive = TRUE)
    dependency <- env$cache_dependency_spec(values = list(version = 1L))
    matrix <- Matrix::Matrix(matrix(1:12, nrow = 3), sparse = TRUE)
    dimnames(matrix) <- list(paste0("g", 1:3), paste0("c", 1:4))
    if (scenario != "missing") env$cache_save_data(matrix, "expmat_filt_Probe.qs2", directory,
      dependencies = dependency)
    if (scenario == "recovery") env$cache_save_data(matrix * 2, "expmat_filt_Probe.qs2", directory,
      dependencies = dependency)
    if (scenario %in% c("corrupt", "recovery")) {
      writeBin(charToRaw("deliberately corrupt owned test cache"), file.path(directory, "cache", "expmat_filt_Probe.qs2"))
    }
    if (scenario == "stale") dependency <- env$cache_dependency_spec(values = list(version = 2L))
    started <- proc.time()[["elapsed"]]
    outcomes[[scenario]] <- tryCatch({
      value <- env$cache_load_data("expmat_filt_Probe.qs2", directory, dependencies = dependency,
        recover = scenario == "recovery")
      list(outcome = "returned", value = value)
    }, error = function(error) list(outcome = "error", classes = class(error),
      reason = gsub(root, "<CACHE_CONTROLS>", conditionMessage(error), fixed = TRUE)))
    if (is.function(on_measure)) on_measure(scenario, proc.time()[["elapsed"]] - started)
  }
  outcomes
}

perf_worker <- function(job) {
  setup_start <- proc.time()[["elapsed"]]
  suppressPackageStartupMessages(library(data.table))
  .datatable.aware <- TRUE
  for (package in c("Matrix", "Seurat", "uwot", "irlba", "matkot", "caTools", "qs2",
                    "ggplot2", "cowplot", "randomcoloR")) loadNamespace(package)
  env <- perf_source_utilities(job$source_root)
  fixture <- readRDS(job$input)
  paths <- perf_prepare_workspace(fixture, file.path(job$directory, "dataset"))
  setup_seconds <- proc.time()[["elapsed"]] - setup_start
  observer <- perf_observer(env, job$directory, capture = job$mode == "capture")
  on.exit(observer$restore(), add = TRUE)
  observer$save("identity", list(cells = fixture$cells$cell_name, genes = rownames(fixture$raw),
    config = fixture$config, selected = fixture$selected, metadata = as.data.frame(fixture$cells),
    gene_positions = as.data.frame(fixture$gene_positions), markers = as.data.frame(fixture$markers)))
  coverage <- list(profile = job$profile)
  final_cells <- NULL
  selected <- fixture$selected
  start <- proc.time()[["elapsed"]]
  before_write <- observer$write_seconds
  if (job$profile != "cache") {
    env$cluster_all_samples(paths, fixture$config, file.path(job$directory, "dataset", "results"),
      file.path(job$directory, "dataset"))
    coverage$clustering <- TRUE
    if (job$profile == "all") {
      env$de_analysis(paths, fixture$config, selected, fixture$markers,
        file.path(job$directory, "dataset", "results"), file.path(job$directory, "dataset"))
      # Full ranking diagnostic is outside the measured workload and runs below.
      batch <- env$batch_compute_cna_and_heatmaps(paths, file.path(job$directory, "dataset"),
        file.path(job$directory, "dataset", "results"), selected, fixture$gene_positions)
      if (!identical(batch$processed, fixture$sample)) stop("Baseline CNA setup was not eligible: ",
        paste(c(batch$skipped, unlist(batch$failed)), collapse = "; "))
      coverage$cna <- TRUE
      coverage$signals <- tryCatch({
        cells <- env$cache_load_data(paste0("cells_filt_clust_res_", selected$resolutions[[fixture$sample]],
          "_", fixture$sample, ".qs2"), file.path(job$directory, "dataset"))
        ref <- cells[cell_type %in% selected$cna_ref_cells[[fixture$sample]]]
        for (i in seq_along(selected$cna_ward_ref_cluster[[fixture$sample]])) {
          env$compute_signal_cor_cna(fixture$sample, i, ref, selected, file.path(job$directory, "dataset"))
        }
        final_cells <- env$apply_cna_thresholds(fixture$sample, file.path(job$directory, "dataset"), selected, save = FALSE)
        list(outcome = "completed")
      }, error = function(error) list(outcome = "error", classes = class(error), reason = conditionMessage(error)))
      observer$save("signal_outcome", coverage$signals)
      if (!identical(coverage$signals$outcome, "completed")) {
        stop("Signal/assignment coverage failed: ", coverage$signals$reason)
      }
    }
  }
  cache_timings <- list()
  controls <- perf_cache_controls(env, file.path(job$directory, "cache-controls"),
    on_measure = function(scenario, seconds) cache_timings[[scenario]] <<- seconds)
  coverage$cache_controls <- identical(controls$valid$outcome, "returned") &&
    all(vapply(controls[c("missing", "corrupt", "stale")], function(x) identical(x$outcome, "error"), logical(1))) &&
    identical(controls$recovery$outcome, "returned") && identical(controls$valid$value, controls$recovery$value)
  if (!coverage$cache_controls) stop("Cache safety controls did not meet their known expected outcomes")
  observer$save("cache_controls", controls)
  elapsed <- proc.time()[["elapsed"]] - start
  native_memory <- ps::ps_memory_info()
  writeLines("Timed workload ended", file.path(job$directory, ".measurement-complete"))
  observer$active <- FALSE
  observer$restore()
  # Remove the restoration exit hook before validation-only output collection.
  on.exit(NULL)
  measured_counts <- observer$counts
  measured_stages <- observer$stages
  measured_write_seconds <- observer$write_seconds - before_write
  observer$active <- TRUE
  observer$capturing <- TRUE
  observer$save("identity", list(cells = fixture$cells$cell_name, genes = rownames(fixture$raw),
    config = fixture$config, selected = fixture$selected, metadata = as.data.frame(fixture$cells),
    gene_positions = as.data.frame(fixture$gene_positions), markers = as.data.frame(fixture$markers)))
  observer$save("cache_controls", controls)
  if (!is.null(final_cells)) observer$save("final_assignments", final_cells, "cells")
  {
    # Collection uses direct qs reads outside the timed/instrumented pipeline.
    cache <- file.path(job$directory, "dataset", "cache")
    for (path in list.files(cache, pattern = "[.]qs2$", full.names = TRUE)) {
      name <- basename(path)
      value <- qs2::qs_read(path)
      kind <- if (startsWith(name, "cells_")) "cells" else if (startsWith(name, "cna_matrix_"))
        "rounded_cna" else if (startsWith(name, "hclust_")) "hclust" else if (is.data.frame(value)) "table" else "numeric"
      observer$save(paste0("cache/", name), value, kind)
    }
    if (job$profile == "all" && job$mode == "capture") {
      matrix <- qs2::qs_read(file.path(cache, paste0("expmat_filt_", fixture$sample, ".qs2")))
      cells <- qs2::qs_read(file.path(cache, paste0("cells_filt_clust_res_", selected$resolutions[[fixture$sample]],
        "_", fixture$sample, ".qs2")))
      parameters <- c(list(clusters = env$natural_cluster_order(cells$clust), col_name = "clust",
        marker_cell_type_col_name = "cell_type", cluster_type_name = "cluster"), fixture$config$params$de)
      parameters$num_genes <- nrow(matrix)
      observer$save("de_full_ranking_diagnostic", env$mean_diff_exp(matrix, cells, parameters), "table")
      marker_file <- file.path(job$directory, "dataset", "results", fixture$sample, "2_de_plots", "all_marker_matches.csv")
      observer$save("marker_matches", data.table::fread(marker_file), "table")
    }
  }
  result <- list(schema_version = 1L, mode = job$mode, environment = perf_environment(),
    input_checksum = unname(tools::md5sum(job$input)), coverage = coverage,
    artifacts = observer$artifacts, counts = measured_counts, stages = measured_stages,
    elapsed_seconds = elapsed, observation_write_seconds = measured_write_seconds,
    cache_control_load_seconds = cache_timings,
    adjusted_elapsed_seconds = elapsed - measured_write_seconds,
    native_memory_at_workload_end = native_memory,
    setup_seconds = setup_seconds, contract_checksum = job$contract_checksum)
  saveRDS(result, file.path(job$directory, "result.rds"))
  invisible(result)
}
