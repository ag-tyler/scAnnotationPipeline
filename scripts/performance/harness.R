perf_inside <- function(path, parent) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  parent <- normalizePath(parent, winslash = "/", mustWork = TRUE)
  if (.Platform$OS.type == "windows") { path <- tolower(path); parent <- tolower(parent) }
  identical(path, parent) || startsWith(path, paste0(parent, "/"))
}

perf_new_output <- function(output, repo, protected = character()) {
  if (file.exists(output)) stop("Output must be a new directory; nothing is overwritten: ", output)
  # Resolve the existing ancestor, including symlinks, before creating anything.
  ancestor <- dirname(output)
  suffix <- basename(output)
  while (!dir.exists(ancestor)) {
    suffix <- file.path(basename(ancestor), suffix)
    next_ancestor <- dirname(ancestor)
    if (identical(next_ancestor, ancestor)) stop("No existing output ancestor")
    ancestor <- next_ancestor
  }
  resolved <- file.path(as.character(fs::path_real(ancestor)), suffix)
  if (any(vapply(protected, function(path) perf_inside(resolved, as.character(fs::path_real(path))), logical(1)))) {
    stop("Output must not be inside an original data workspace")
  }
  if (perf_inside(resolved, repo) &&
      !perf_inside(resolved, file.path(repo, "artifacts", "local-checks"))) {
    stop("Repository output is restricted to artifacts/local-checks/")
  }
  dir.create(resolved, recursive = TRUE)
  writeLines("Owned disposable performance experiment", file.path(resolved, ".performance-run"))
  normalizePath(resolved, winslash = "/", mustWork = TRUE)
}

perf_snapshot_sources <- function(repo, output, baseline_commit) {
  commit <- processx::run("git", c("-C", repo, "rev-parse", "--verify", paste0(baseline_commit, "^{commit}")))$stdout
  commit <- trimws(commit)
  if (!grepl("^[0-9a-f]{40}$", commit)) stop("Baseline must resolve to a commit")
  baseline <- file.path(output, "baseline-source")
  candidate <- file.path(output, "candidate-source")
  dir.create(baseline)
  dir.create(file.path(candidate, "util_scripts"), recursive = TRUE)
  archive <- file.path(output, "baseline.tar")
  processx::run("git", c("-C", repo, "archive", "--format=tar", paste0("--output=", archive),
    commit, "util_scripts"))
  utils::untar(archive, exdir = baseline)
  source_files <- list.files(file.path(repo, "util_scripts"), pattern = "[.]R$", full.names = TRUE)
  if (any(fs::is_link(source_files))) stop("Utility source links are not supported")
  if (!all(file.copy(source_files, file.path(candidate, "util_scripts")))) stop("Candidate snapshot copy failed")
  fingerprints <- function(directory) {
    paths <- sort(list.files(file.path(directory, "util_scripts"), pattern = "[.]R$", full.names = TRUE))
    stats::setNames(unname(tools::md5sum(paths)), basename(paths))
  }
  list(baseline = baseline, candidate = candidate, baseline_commit = commit,
    candidate_head = trimws(processx::run("git", c("-C", repo, "rev-parse", "HEAD"))$stdout),
    candidate_diff = processx::run("git", c("-C", repo, "diff", commit, "--", "util_scripts"))$stdout,
    baseline_checksums = fingerprints(baseline), candidate_checksums = fingerprints(candidate))
}

perf_tang_fixture <- function(env, repo, dataset, sample, cell_limit = 128L, max_memory_bytes = 12e9) {
  dataset <- normalizePath(dataset, winslash = "/", mustWork = TRUE)
  config_path <- file.path(dataset, "dataset_config.yaml")
  selected_path <- file.path(dataset, "selected_config.yaml")
  config <- yaml::read_yaml(config_path)
  selected <- yaml::read_yaml(selected_path)
  if (!sample %in% names(selected$resolutions)) stop("Unknown configured sample")
  directory <- file.path(dataset, "processed_data", sample)
  cache_file <- file.path(dataset, "cache", paste0("cells_filt_clust_res_", selected$resolutions[[sample]], "_", sample, ".qs2"))
  manifest_path <- file.path(dataset, "cache", "cache_manifest.yaml")
  general <- yaml::read_yaml(file.path(repo, "general_config.yaml"))
  positions_path <- file.path(repo, general$paths$resources_dir, general$resource_files$gene_positions)
  markers_path <- file.path(repo, general$paths$resources_dir, general$resource_files$marker_sets)
  hgnc_path <- file.path(repo, general$paths$resources_dir, general$resource_files$hgnc_complete_set)
  files <- c(config_path, selected_path, manifest_path, cache_file, positions_path, markers_path, hgnc_path,
    file.path(directory, unlist(config$std_names[c("expmat", "genes", "cells")], use.names = FALSE)))
  if (!all(file.exists(files))) stop("Real-data extraction requires existing prepared files, cells cache and resources")
  before <- tools::md5sum(files)
  manifest <- yaml::read_yaml(manifest_path)
  record <- manifest$artifacts[[basename(cache_file)]]
  if (is.null(record) || !identical(unname(before[[cache_file]]), record$checksum)) stop("Source cells cache checksum mismatch")
  # Direct read only: cache_load_data() may recover/write; never call it on the source workspace.
  cached <- qs2::qs_read(cache_file)
  env$validate_cache_object(cached, "clustered_cells", basename(cache_file))
  if ("cell_type_pre_cna" %in% names(cached)) cached$cell_type <- cached$cell_type_pre_cna
  original_cells <- env$load_cells(file.path(directory, config$std_names$cells))
  if (cell_limit > 0L && cell_limit < nrow(cached)) {
    set.seed(3988)
    strata <- split(seq_len(nrow(cached)), ifelse(is.na(cached$cell_type), "Unassigned", cached$cell_type))
    strata <- lapply(strata, function(index) sample(index, length(index)))
    selected_indices <- integer()
    for (i in seq_len(max(lengths(strata)))) {
      selected_indices <- c(selected_indices, vapply(strata[lengths(strata) >= i], `[[`, integer(1), i))
      if (length(selected_indices) >= cell_limit) break
    }
    keep <- cached$cell_name[head(selected_indices, cell_limit)]
    original_cells <- original_cells[cell_name %in% keep]
  }
  annotations <- match(original_cells$cell_name, cached$cell_name)
  known <- !is.na(annotations)
  original_cells$cell_type[known] <- cached$cell_type[annotations[known]]
  if ("cell_type_pre_cna" %in% names(original_cells)) original_cells$cell_type_pre_cna <- original_cells$cell_type
  matrix_path <- file.path(directory, config$std_names$expmat)
  if (file.size(matrix_path) * 6 > max_memory_bytes) stop("Raw-matrix preparation estimate exceeds the declared memory budget")
  raw <- methods::as(Matrix::readMM(matrix_path), "dgCMatrix")
  genes <- env$load_genes(file.path(directory, config$std_names$genes))
  all_cell_names <- env$load_cells(file.path(directory, config$std_names$cells))$cell_name
  raw <- raw[, match(original_cells$cell_name, all_cell_names), drop = FALSE]
  rownames(raw) <- genes
  colnames(raw) <- original_cells$cell_name
  # Match app/context.R resource preparation without starting the app or touching data caches.
  positions <- data.table::fread(positions_path, colClasses = list(character = "chromosome_name"))
  hgnc <- data.table::fread(hgnc_path)
  duplicates <- names(which(table(hgnc$ensembl_gene_id) > 1L))
  hgnc <- hgnc[!ensembl_gene_id %in% duplicates]
  positions[hgnc, on = "ensembl_gene_id", c("symbol", "location") := .(i.symbol, i.location_sortable)]
  positions <- positions[!is.na(hgnc_symbol) & chromosome_name %in% c(as.character(1:22), "X", "Y")]
  positions[chromosome_name %in% as.character(1:9), chromosome_name := paste0("0", chromosome_name)]
  data.table::setkey(positions, hgnc_symbol)
  markers <- env$normalize_marker_table(data.table::fread(markers_path), group_column = "cell_type")
  markers <- markers[cell_type != "Malignant" & symbol %in% genes]
  markers[, cell_type := gsub(" ", "_", cell_type)]
  markers <- markers[order(-combined), head(.SD, 30L), by = cell_type][, .(cell_type, symbol)]
  decisions <- selected
  if (!length(decisions$cna_ward_ref_cluster[[sample]])) {
    decisions$cna_ward_ref_cluster[[sample]] <- list(list(k = 2L, cluster = 1L), list(k = 2L, cluster = 2L))
    decisions$cna_thresholds[[sample]] <- rep(list(list(m_x = 0.25, m_y = 0.05, nm_x = 0.1, nm_y = 0.01)), 2L)
    decision_origin <- "fixed harness k=2/threshold decisions; not biological acceptance"
  } else decision_origin <- "copied saved decisions"
  if (!identical(before, tools::md5sum(files))) stop("Source changed during extraction")
  list(id = paste0("Tang_", sample, "_", ncol(raw), "cells"), sample = sample,
    raw = raw, cells = original_cells, config = config, selected = decisions,
    gene_positions = positions, markers = markers,
    provenance = list(kind = "real", dataset = dataset, source_checksums = before,
      original_prepared_cells = length(all_cell_names), extracted_cells = ncol(raw),
      cell_limit = cell_limit, full_size_acceptance = cell_limit == 0L,
      sampling = "seeded cell-type round robin, retaining original input order",
      markers = "resource-derived top-30 panel; not complete app marker-selection replay",
      decision_origin = decision_origin))
}

perf_run_process <- function(job, harness_root, timeout_seconds = 900, max_memory_bytes = 12e9) {
  path <- file.path(job$directory, "job.rds")
  saveRDS(job, path)
  worker <- file.path(harness_root, "worker.R")
  executable <- file.path(R.home("bin"), "Rscript.exe")
  if (.Platform$OS.type != "windows") executable <- file.path(R.home("bin"), "Rscript")
  process <- processx::process$new(executable, c("--vanilla", worker, path),
    stdout = file.path(job$directory, "stdout.log"), stderr = file.path(job$directory, "stderr.log"),
    env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
      LC_ALL = if (.Platform$OS.type == "windows") "English_United States.utf8" else "C.UTF-8",
      R_USER_CACHE_DIR = file.path(job$directory, "user-cache")), supervise = TRUE)
  on.exit(if (process$is_alive()) { process$kill_tree(); process$wait() }, add = TRUE)
  started <- proc.time()[["elapsed"]]
  sampled_peak <- 0
  native_peak <- 0
  while (process$is_alive()) {
    info <- if (file.exists(file.path(job$directory, ".measurement-complete"))) NULL else
      tryCatch(ps::ps_memory_info(ps::ps_handle(process$get_pid())), error = function(e) NULL)
    if (!is.null(info)) {
      sampled_peak <- max(sampled_peak, info[["rss"]])
      if ("peak_wset" %in% names(info)) native_peak <- max(native_peak, info[["peak_wset"]])
    }
    if (max(sampled_peak, native_peak) > max_memory_bytes) stop("Owned worker exceeded memory budget: ", job$directory)
    if (proc.time()[["elapsed"]] - started > timeout_seconds) stop("Owned worker exceeded timeout: ", job$directory)
    process$wait(timeout = 100)
  }
  process$wait()
  if (process$get_exit_status() != 0L) {
    stop("Worker failed (exit ", process$get_exit_status(), "); inspect ", file.path(job$directory, "stderr.log"))
  }
  result <- readRDS(file.path(job$directory, "result.rds"))
  if ("peak_wset" %in% names(result$native_memory_at_workload_end)) {
    native_peak <- max(native_peak, result$native_memory_at_workload_end[["peak_wset"]])
  }
  result$sampled_peak_rss_bytes <- sampled_peak
  result$native_lifetime_peak_rss_bytes <- if (native_peak) native_peak else NA_real_
  result$memory_scope <- "fresh worker lifetime, including startup/input/setup; captured runs include observer writes"
  saveRDS(result, file.path(job$directory, "result.rds"))
  result
}

perf_run_experiment <- function(repo, output, fixture = NULL, case = "synthetic", dataset = NULL,
                                sample = "CRC_T1", cell_limit = 128L, repeats = 3L,
                                profile = "all", policy = "exact", timeout_seconds = 900,
                                max_memory_bytes = 12e9) {
  repo <- normalizePath(repo, winslash = "/", mustWork = TRUE)
  if (!profile %in% c("all", "clustering", "cache") || !policy %in% c("exact", "numerical")) stop("Invalid profile/policy")
  if (length(repeats) != 1L || is.na(repeats) || repeats < 1L) stop("repeats must be positive")
  if (!case %in% c("synthetic", "boundaries", "tang")) stop("Unknown case")
  if (length(cell_limit) != 1L || is.na(cell_limit) || cell_limit < 0L) stop("Invalid cell limit")
  if (!is.finite(timeout_seconds) || timeout_seconds <= 0 || !is.finite(max_memory_bytes) || max_memory_bytes <= 0) stop("Invalid resource budget")
  output <- perf_new_output(output, repo, protected = if (case == "tang") dataset else character())
  contract_path <- file.path(repo, "scripts", "performance", "contract.yaml")
  contract <- yaml::read_yaml(contract_path)
  contract_checksum <- unname(tools::md5sum(contract_path))
  file.copy(contract_path, file.path(output, "contract.yaml"))
  snapshots <- perf_snapshot_sources(repo, output, contract$baseline_commit)
  harness_root <- file.path(output, "harness")
  dir.create(harness_root)
  files <- list.files(file.path(repo, "scripts", "performance"), pattern = "[.]R$", full.names = TRUE)
  if (!all(file.copy(files, harness_root))) stop("Harness snapshot failed")
  env <- perf_source_utilities(snapshots$baseline)
  preparation_start <- proc.time()[["elapsed"]]
  if (is.null(fixture)) fixture <- if (case == "tang") perf_tang_fixture(env, repo, dataset, sample,
    cell_limit, max_memory_bytes) else perf_fixture(env, boundary = case == "boundaries")
  input <- file.path(output, "input.rds")
  saveRDS(fixture, input, compress = FALSE)
  input_checksum <- unname(tools::md5sum(input))
  preparation_seconds <- proc.time()[["elapsed"]] - preparation_start
  source_checksums <- fixture$provenance$source_checksums
  on.exit({
    if (!is.null(source_checksums) && !identical(source_checksums, tools::md5sum(names(source_checksums)))) {
      warning("Source fingerprints changed; this experiment is invalid")
    }
  }, add = TRUE)
  metadata <- list(schema_version = 1L, input = fixture$provenance, case = fixture$id,
    dimensions = dim(fixture$raw), baseline = snapshots,
    harness_checksums = tools::md5sum(file.path(harness_root, basename(files))), contract_checksum = contract_checksum,
    preparation_seconds = preparation_seconds, profile = profile, policy = policy, repeats = repeats,
    OS = Sys.info()[c("sysname", "release", "version", "machine")],
    measurement_protocol = "fresh processes; capture passes separate from measurement passes; role order alternates; OS file cache not flushed")
  saveRDS(metadata, file.path(output, "experiment.rds"))
  runs <- list()
  comparisons <- list()
  for (iteration in seq_len(repeats)) {
    roles <- if (iteration %% 2L) c("baseline", "candidate") else c("candidate", "baseline")
    for (mode in c("capture", "measure")) for (role in roles) {
      name <- paste(mode, role, iteration, sep = "_")
      directory <- file.path(output, name)
      dir.create(directory)
      job <- list(directory = directory, source_root = snapshots[[role]], input = input,
        profile = profile, mode = mode, contract_checksum = contract_checksum, harness_root = harness_root)
      message("Running ", name, " | ", fixture$id)
      runs[[name]] <- perf_run_process(job, harness_root, timeout_seconds, max_memory_bytes)
    }
    comparisons[[paste0("paired_", iteration)]] <- perf_compare_runs(
      file.path(output, paste0("capture_baseline_", iteration)),
      file.path(output, paste0("capture_candidate_", iteration)), contract, policy)
    for (role in c("baseline", "candidate")) {
      comparisons[[paste0("observer_control_", role, "_", iteration)]] <- perf_compare_runs(
        file.path(output, paste0("capture_", role, "_", iteration)),
        file.path(output, paste0("measure_", role, "_", iteration)), contract, "exact", common_only = TRUE)
    }
    if (iteration > 1L) comparisons[[paste0("baseline_repeat_", iteration)]] <- perf_compare_runs(
      file.path(output, "capture_baseline_1"), file.path(output, paste0("capture_baseline_", iteration)), contract, "exact")
    saveRDS(comparisons, file.path(output, "comparisons.rds"))
    jsonlite::write_json(comparisons, file.path(output, "comparisons.json"),
      pretty = TRUE, auto_unbox = TRUE, digits = 16, null = "null")
  }
  sources_unchanged <- is.null(source_checksums) || identical(source_checksums, tools::md5sum(names(source_checksums)))
  input_unchanged <- identical(input_checksum, unname(tools::md5sum(input)))
  rows <- lapply(names(runs), function(name) {
    value <- runs[[name]]
    data.frame(run = name, elapsed_seconds = value$elapsed_seconds,
      adjusted_elapsed_seconds = value$adjusted_elapsed_seconds,
      sampled_peak_rss_bytes = value$sampled_peak_rss_bytes,
      native_lifetime_peak_rss_bytes = value$native_lifetime_peak_rss_bytes,
      as.list(value$counts), check.names = FALSE)
  })
  table <- do.call(rbind, rows)
  utils::write.csv(table, file.path(output, "measurements.csv"), row.names = FALSE)
  timing <- table[startsWith(table$run, "measure_"), , drop = FALSE]
  timing$role <- sub("^measure_(baseline|candidate)_.*$", "\\1", timing$run)
  medians <- stats::aggregate(timing[c("elapsed_seconds", "sampled_peak_rss_bytes",
    "native_lifetime_peak_rss_bytes")], list(role = timing$role), stats::median, na.rm = TRUE)
  utils::write.csv(medians, file.path(output, "measurement_medians.csv"), row.names = FALSE)
  passed <- sources_unchanged && input_unchanged && all(vapply(comparisons, function(x) isTRUE(x$pass), logical(1)))
  summary <- list(pass = passed, source_unchanged = sources_unchanged, input_unchanged = input_unchanged,
    case = fixture$id, comparisons = vapply(comparisons, function(x) isTRUE(x$pass), logical(1)),
    full_size_acceptance = isTRUE(fixture$provenance$full_size_acceptance),
    coverage = runs$capture_baseline_1$coverage)
  saveRDS(summary, file.path(output, "summary.rds"))
  writeLines(c(paste("Result:", if (passed) "PASS" else "FAIL"), paste("Case:", fixture$id),
    paste("Policy:", policy), paste("Repeats:", repeats),
    paste("Original source files unchanged:", sources_unchanged),
    paste("Full-size acceptance evidence:", summary$full_size_acceptance),
    "Capture passes establish scientific equivalence; measure passes supply timings/peak memory.",
    "Use measurements.csv, measurement_medians.csv and per-worker result.rds for metrics.",
    "Use comparisons.json for per-artifact equivalence metrics; capture results contain counts/stages.",
    "Measure passes have no observation probes; capture stage timings are instrumented diagnostics.",
    "Memory includes worker setup and package loading; OS caches are not flushed.",
    "No performance speedup claim is made by an A/A run."),
    file.path(output, "SUMMARY.txt"))
  if (!passed) stop("Equivalence check failed; inspect comparisons.rds in ", output)
  invisible(summary)
}
