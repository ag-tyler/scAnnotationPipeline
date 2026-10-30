make_f17_workspace <- function(cna = FALSE) {
  root <- tempfile("f17-"); dir.create(root)
  dataset <- file.path(root, "datasets", "Dataset")
  processed <- file.path(dataset, "standardized")
  sample <- "Sample_A"
  sample_dir <- file.path(processed, sample)
  results <- file.path(dataset, "evidence")
  logs <- file.path(dataset, "journal")
  destination <- file.path(root, "DESTINATION_PRIVATE_MARKER")
  for (path in c(sample_dir, logs, destination,
    file.path(results, sample, "1_cluster_plots"), file.path(results, sample, "2_de_plots"))) dir.create(path, recursive = TRUE)
  cells <- data.table::data.table(cell_name = c("analyzed", "filtered_out"), sample = sample,
    cell_type = c("Malignant", "Source_label_not_reviewed"), subclone = c(1L, NA_integer_))
  cell_path <- file.path(sample_dir, "Cells.csv")
  data.table::fwrite(cells, cell_path)
  writeLines("%%MatrixMarket matrix coordinate integer general\n1 2 2\n1 1 1\n1 2 2", file.path(sample_dir, "expression.mtx"))
  writeLines("GENE1", file.path(sample_dir, "Genes.txt"))
  writeLines("sample\nSample_A", file.path(processed, "Samples.csv"))
  writeLines("final plot", file.path(results, sample, "1_cluster_plots", "clusters_plot_Sample_A_res_0.5.png"))
  for (name in c("cell_types.png", "score_plot.png", "all_marker_matches.csv", "alternative_resolution_plot.png")) {
    writeLines("ordinary result", file.path(results, sample, "2_de_plots", name))
  }
  writeLines("original log", file.path(logs, "pipeline.log"))
  writeLines('{"original":true}', file.path(logs, "pipeline_events.jsonl"))
  config <- list(project_info = list(dataset_id = "Dataset", source_doi = "10.1234/example", source_url = "https://example.org/dataset"),
    std_names = list(expmat = "expression.mtx", genes = "Genes.txt", cells = "Cells.csv", samples = "Samples.csv"), params = list(min_genes = 500))
  selected <- list(resolutions = list(Sample_A = "0.5"))
  config_paths <- list("dataset_config.yaml" = file.path(dataset, "dataset_config.yaml"),
    "samples_config.yaml" = file.path(dataset, "samples_config.yaml"),
    "selected_config.yaml" = file.path(dataset, "selected_config.yaml"),
    "pipeline_state.yaml" = file.path(dataset, "pipeline_state.yaml"),
    "standardize.R" = file.path(dataset, "standardize.R"),
    "STANDARDIZATION_CHECKLIST.md" = file.path(dataset, "STANDARDIZATION_CHECKLIST.md"))
  yaml::write_yaml(config, config_paths[["dataset_config.yaml"]])
  yaml::write_yaml(list(samples = list(list(sample = sample))), config_paths[["samples_config.yaml"]])
  yaml::write_yaml(selected, config_paths[["selected_config.yaml"]])
  writeLines("# Preparation provenance", config_paths[["standardize.R"]])
  writeLines("Completed", config_paths[["STANDARDIZATION_CHECKLIST.md"]])
  state <- new_pipeline_state("Dataset", sample)
  state <- transition_pipeline_step(state, "standardization", "completed", force = TRUE)
  for (step in c("clustering", "resolution", "differential_expression", "annotation")) {
    state <- transition_pipeline_step(state, step, "completed", sample, force = TRUE)
  }
  state <- transition_pipeline_step(state, "clustering", "completed", sample, details = list(
    snapshot_filtering = list(schema_version = 1L, input_cells = 2L, retained_cells = 1L, settings = list(min_genes = 500))))
  capture <- capture_snapshot_annotations(cells[1], cell_path, "0.5", get_pipeline_step(state, "clustering", sample))
  state <- transition_pipeline_step(state, "annotation", "completed", sample, details = list(snapshot_annotations = capture))
  if (cna) {
    for (step in c("cna_configuration", "cna_compute", "cna_cluster_selection", "cna_signal_correlation", "cna_thresholds", "cna_assignment")) {
      state <- transition_pipeline_step(state, step, "completed", sample, force = TRUE)
    }
    state <- transition_pipeline_step(state, "cna_assignment", "completed", sample, details = list(snapshot_annotations = capture))
    cna_dir <- file.path(results, sample, "3_cna_plots"); dir.create(cna_dir)
    for (name in c("cna_summary_heatmap_Sample_A.png", "cna_umap_assigned_Sample_A.png")) writeLines("cna plot", file.path(cna_dir, name))
    matrix <- data.table::data.table(gene = "GENE1", chr = "01", start_pos = 1L, analyzed = 0.5)
    cache_save_data(matrix, "cna_matrix_Sample_A.qs2", dataset)
    export_cna_values_table(sample, dataset, results)
  } else {
    state <- transition_pipeline_step(state, "cna_configuration", "skipped", sample,
      reason = "User omitted CNA", details = list(omitted_by_user = TRUE), force = TRUE)
    cache_save_data(cells[1], "cells_filt_clust_res_0.5_Sample_A.qs2", dataset)
  }
  state <- save_pipeline_state_at_path(state, config_paths[["pipeline_state.yaml"]])
  storage <- save_dataset_storage_state_atomic(new_dataset_storage_state("Dataset"), dataset)
  paths <- list(sample_dir_paths = sample_dir, cell_file_paths = cell_path,
    expmat_file_paths = file.path(sample_dir, "expression.mtx"), genes_file_paths = file.path(sample_dir, "Genes.txt"))
  list(root = root, args = list(destination = destination, dataset_dir_path = dataset,
    pipeline_state = state, storage_state = storage, paths_list = paths, selected_config = selected,
    selected_config_path = config_paths[["selected_config.yaml"]], dataset_config = config,
    processed_dir_path = processed, results_dir_path = results, logs_dir_path = logs,
    config_paths = config_paths, acknowledge_warnings = TRUE))
}

f17_inventory <- function(args, options = snapshot_options()) {
  do.call(build_snapshot_inventory, c(args[names(args) %in% names(formals(build_snapshot_inventory))], list(options = options)))
}
f17_readiness <- function(args) do.call(dataset_snapshot_readiness, args[names(args) %in% names(formals(dataset_snapshot_readiness))])

test_that("F17 all twelve mode/toggle combinations preserve full processed data and ordinary results", {
  workspace <- make_f17_workspace(cna = TRUE)
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  source <- list.files(args$dataset_dir_path, recursive = TRUE, full.names = TRUE)
  before <- tools::md5sum(source)
  for (mode in c("folder", "archive", "both")) for (logs in c(FALSE, TRUE)) for (values in c(FALSE, TRUE)) {
    options <- snapshot_options(mode, logs, values)
    inventory <- f17_inventory(args, options)
    events <- list()
    result <- do.call(create_review_snapshot, c(args, list(options = options,
      progress_callback = function(...) events[[length(events) + 1L]] <<- list(...))))
    expect_length(result$outputs, if (mode == "both") 2L else 1L)
    payloads <- character()
    for (output in result$outputs) {
      if (dir.exists(output)) payloads <- c(payloads, output) else {
        extracted <- tempfile("extracted-", tmpdir = workspace$root)
        zip::unzip(output, exdir = extracted)
        payloads <- c(payloads, extracted)
      }
    }
    for (payload in payloads) {
      actual <- list.files(payload, recursive = TRUE)
      expect_setequal(actual, c(inventory$files$path, "README.md", "annotation_summary.csv", "filtering_summary.csv", "snapshot_manifest.yaml"))
      expect_identical(any(startsWith(actual, "logs/")), logs)
      expect_identical(any(grepl("cna_values_.*[.]csv[.]gz$", actual)), values)
      expect_true(any(grepl("cna_summary_heatmap", actual)))
      expect_true(any(grepl("alternative_resolution_plot", actual)))
      expect_identical(unname(tools::md5sum(file.path(payload, inventory$files$path))), unname(tools::md5sum(inventory$files$source)))
      saved_cells <- data.table::fread(file.path(payload, "processed_data", "Sample_A", "Cells.csv"))
      expect_identical(saved_cells$cell_name, c("analyzed", "filtered_out"))
      readme <- paste(readLines(file.path(payload, "README.md")), collapse = "\n")
      expect_match(readme, "10.1234/example", fixed = TRUE)
      expect_match(readme, "https://example.org/dataset", fixed = TRUE)
      expect_false(grepl("DESTINATION_PRIVATE_MARKER", readme, fixed = TRUE))
      manifest <- yaml::read_yaml(file.path(payload, "snapshot_manifest.yaml"))
      expect_false(grepl("DESTINATION_PRIVATE_MARKER", yaml::as.yaml(manifest), fixed = TRUE))
      expect_identical(manifest$options, options)
    }
    progress <- vapply(events, `[[`, numeric(1), "progress")
    expect_true(all(diff(progress) >= 0))
    expect_equal(range(progress), c(0, 1))
  }
  expect_identical(tools::md5sum(source), before)
  expect_false(dir.exists(file.path(args$dataset_dir_path, ".storage-operation.lock")))
  expect_false(any(startsWith(list.files(args$destination, all.files = TRUE), ".review-snapshot-")))
})

test_that("F17 scopes annotations and filtering without guessing legacy or stale counts", {
  workspace <- make_f17_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  summaries <- build_snapshot_summaries(args$pipeline_state, args$paths_list, args$selected_config)
  expect_equal(summaries$filtering$filtered_out, 1)
  expect_equal(summaries$filtering$filtered_percent, 50)
  expect_equal(summaries$annotations[scope == "pipeline_analyzed_cells", sum(cell_count)], 1)
  expect_true("Source_label_not_reviewed" %in% summaries$annotations[scope != "pipeline_analyzed_cells", annotation])
  expect_false("Source_label_not_reviewed" %in% summaries$annotations[scope == "pipeline_analyzed_cells", annotation])
  expect_length(summaries$warnings, 0L)
  labels <- data.table::data.table(cell_type = c(NA, "", "Unassigned", "Malignant"), subclone = c(NA, NA, NA, 2L))
  counts <- data.table::rbindlist(snapshot_label_counts(labels))
  expect_equal(counts[annotation == "Unassigned/NA", cell_count], 3)
  stale <- transition_pipeline_step(args$pipeline_state, "clustering", "stale", "Sample_A", reason = "rerun")
  unavailable <- build_snapshot_summaries(stale, args$paths_list, args$selected_config)
  expect_true(is.na(unavailable$filtering$retained_for_clustering))
  expect_true(any(grepl("unavailable", unavailable$annotations$scope)))
  changed <- args$pipeline_state
  changed$samples$Sample_A$clustering$attempt <- 2L
  expect_true(any(grepl("unavailable", build_snapshot_summaries(changed, args$paths_list, args$selected_config)$annotations$scope)))
  unknown <- args$pipeline_state
  unknown$samples$Sample_A$clustering$details <- list()
  unknown$samples$Sample_A$annotation$details <- list()
  summaries <- build_snapshot_summaries(unknown, args$paths_list, args$selected_config)
  expect_true(is.na(summaries$filtering$filtered_out))
  expect_length(summaries$warnings, 2L)
})

test_that("F17 readiness is cache-independent and rejects unfinished, dirty and conflicting states", {
  workspace <- make_f17_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  expect_true(f17_readiness(args)$ready)
  unlink(file.path(args$dataset_dir_path, "cache"), recursive = TRUE)
  expect_true(f17_readiness(args)$ready)
  args$annotation_dirty <- TRUE
  expect_false(f17_readiness(args)$ready)
  args$annotation_dirty <- FALSE
  args$active_actions <- "clustering"
  expect_false(f17_readiness(args)$ready)
  args$active_actions <- character()
  for (step in c("clustering", "resolution", "differential_expression", "annotation")) {
    changed <- args
    changed$pipeline_state <- transition_pipeline_step(args$pipeline_state, step, "stale", "Sample_A", reason = "changed")
    expect_false(f17_readiness(changed)$ready)
  }
  args$storage_state$status <- "cleaning"
  expect_false(f17_readiness(args)$ready)
  args$storage_state$status <- "active"
  file.remove(args$paths_list$expmat_file_paths)
  expect_false(f17_readiness(args)$ready)
})

test_that("F17 verified retained CNA values remain eligible after real cache cleanup", {
  workspace <- make_f17_workspace(cna = TRUE)
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  ready <- dataset_cleanup_readiness(args$pipeline_state, args$paths_list, args$selected_config,
    args$selected_config_path, args$results_dir_path, args$dataset_dir_path)
  expect_true(ready$ready)
  args$storage_state <- archive_dataset_cache(args$dataset_dir_path, args$pipeline_state, args$storage_state, ready)
  expect_true(f17_readiness(args)$ready)
  expect_identical(args$storage_state$status, "archived")
  expect_true(.snapshot_cna_pair("Sample_A", args$dataset_dir_path, args$results_dir_path, args$storage_state)$eligible)
  inventory <- f17_inventory(args, snapshot_options(include_cna_values = TRUE))
  expect_identical(inventory$cna_included, "Sample_A")
  expect_no_error(do.call(create_review_snapshot, c(args, list(options = snapshot_options("both", TRUE, TRUE)))))
  pair <- cna_values_export_paths(args$results_dir_path, "Sample_A")
  cat("damage", file = pair$csv, append = TRUE)
  expect_false(.snapshot_cna_pair("Sample_A", args$dataset_dir_path, args$results_dir_path, args$storage_state)$eligible)
  # Optional damage is a warning, not a new scientific prerequisite.
  expect_no_error(f17_inventory(args))
  plot <- file.path(args$results_dir_path, "Sample_A", "1_cluster_plots", "clusters_plot_Sample_A_res_0.5.png")
  cat("damage", file = plot, append = TRUE)
  expect_error(f17_inventory(args), "Required retained outputs changed")
})

test_that("F17 missing, outdated and orphan CNA pairs warn and never compute", {
  workspace <- make_f17_workspace(cna = TRUE)
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  pair <- cna_values_export_paths(args$results_dir_path, "Sample_A")
  file.remove(pair$metadata)
  inventory <- f17_inventory(args, snapshot_options(include_cna_values = TRUE))
  expect_length(inventory$cna_included, 0L)
  expect_match(inventory$warnings, "incomplete")
  expect_false(any(grepl("cna_values_", inventory$files$path)))
  args$acknowledge_warnings <- FALSE
  expect_error(do.call(create_review_snapshot, c(args, list(options = snapshot_options(include_cna_values = TRUE)))), "acknowledge")
  expect_length(list.files(args$destination), 0L)
})

test_that("F17 failures, interruption and partial Both publication roll back only owned output", {
  workspace <- make_f17_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  prior <- file.path(args$destination, "prior-user-file.txt"); writeLines("keep", prior)
  prior_hash <- .cache_md5(prior)
  for (stage_to_fail in c("copy", "source_verification", "folder_verification", "compress", "archive_readback", "archive_verification")) {
    events <- list()
    expect_error(do.call(create_review_snapshot, c(args, list(options = snapshot_options("both"),
      progress_callback = function(stage, ...) { if (stage == stage_to_fail) stop("I/O failed at DESTINATION_PRIVATE_MARKER/private") },
      event_callback = function(...) events[[length(events) + 1L]] <<- list(...)))), "Snapshot failed")
    expect_false(grepl("DESTINATION_PRIVATE_MARKER", paste(capture.output(str(events)), collapse = ""), fixed = TRUE))
    expect_setequal(list.files(args$destination, all.files = TRUE, no.. = TRUE), basename(prior))
    expect_identical(.cache_md5(prior), prior_hash)
  }
  expect_error(do.call(create_review_snapshot, c(args, list(progress_callback = function(stage, ...) {
    if (stage == "copy") stop(structure(list(message = "interrupt DESTINATION_PRIVATE_MARKER/private", call = NULL), class = c("interrupt", "condition")))
  }))), "interrupted")
  renames <- 0L
  expect_error(do.call(create_review_snapshot, c(args, list(options = snapshot_options("both"), rename_output = function(from, to) {
    renames <<- renames + 1L
    if (renames == 2L) return(FALSE)
    file.rename(from, to)
  }))), "rolled back")
  expect_setequal(list.files(args$destination, all.files = TRUE, no.. = TRUE), basename(prior))
  expect_error(do.call(create_review_snapshot, c(args, list(available_space = function(path) 0))), "Insufficient")
  expect_no_error(do.call(create_review_snapshot, args))
})

test_that("F17 rejects overlap, links, unsafe rollback and source changes", {
  workspace <- make_f17_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  for (path in c(args$dataset_dir_path, args$processed_dir_path, dirname(args$dataset_dir_path), workspace$root)) {
    expect_error(validate_snapshot_destination(path, args$dataset_dir_path), "separate")
  }
  expect_error(.snapshot_remove_owned(args$dataset_dir_path, args$destination, TRUE), "Refusing")
  expect_error(.snapshot_relative("../outside"), "Unsafe")
  expect_error(.snapshot_relative("C:/outside"), "Unsafe")
  expect_error(do.call(create_review_snapshot, c(args, list(progress_callback = function(stage, ...) {
    if (stage == "copy") cat("changed", file = args$paths_list$cell_file_paths, append = TRUE)
  }))))
  expect_length(list.files(args$destination, all.files = TRUE, no.. = TRUE), 0L)
  link <- file.path(args$results_dir_path, "linked")
  made <- suppressWarnings(file.symlink(args$logs_dir_path, link))
  if (isTRUE(made)) expect_error(f17_inventory(args), "link")
})

test_that("F17 provenance defaults, exclusions, bounded copy, and destination-free real logs are explicit", {
  workspace <- make_f17_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  args$dataset_config$project_info <- list(dataset_id = "Dataset")
  yaml::write_yaml(args$dataset_config, args$config_paths[["dataset_config.yaml"]])
  file.remove(args$config_paths[["standardize.R"]])
  for (name in c("cache_manifest.yaml", "diagnostic.png.bak", "local_config.yaml", ".env", "x.lock")) {
    writeLines("exclude", file.path(args$results_dir_path, name))
  }
  prior_copy <- file.path(args$results_dir_path, "old_snapshot")
  dir.create(prior_copy)
  writeLines("old snapshot", file.path(prior_copy, "snapshot_manifest.yaml"))
  writeLines("old data", file.path(prior_copy, "payload.txt"))
  ordinary <- file.path(args$processed_dir_path, "Sample_A", "data")
  dir.create(ordinary)
  writeLines("ordinary standardized metadata", file.path(ordinary, "extra.csv"))
  inventory <- f17_inventory(args)
  expect_false(any(grepl("exclude|cache_manifest|diagnostic.png.bak|local_config|[.]env|x.lock|old_snapshot", inventory$files$path)))
  expect_true(any(grepl("standardize.R", inventory$warnings, fixed = TRUE)))
  expect_true("processed_data/Sample_A/data/extra.csv" %in% inventory$files$path)
  expect_identical(snapshot_options(), list(mode = "folder", include_logs = TRUE, include_cna_values = FALSE))
  expect_error(snapshot_options(include_logs = NA), "true or false")
  expect_error(snapshot_options(mode = "other"), "Choose")
  events_path <- file.path(args$logs_dir_path, "pipeline_events.jsonl")
  callback <- function(outcome, parameters) {
    cat(jsonlite::toJSON(list(event = "review_snapshot", outcome = outcome, parameters = parameters), auto_unbox = TRUE),
      "\n", file = events_path, append = TRUE)
  }
  result <- do.call(create_review_snapshot, c(args, list(event_callback = callback)))
  readme <- paste(readLines(file.path(result$outputs, "README.md")), collapse = "\n")
  expect_match(readme, "Publication DOI: not provided", fixed = TRUE)
  source_logs <- paste(readLines(events_path), collapse = "\n")
  snapshot_logs <- paste(readLines(file.path(result$outputs, "logs", "pipeline_events.jsonl")), collapse = "\n")
  expect_match(source_logs, "completed")
  expect_match(snapshot_logs, "started")
  expect_false(grepl("completed", snapshot_logs))
  expect_false(grepl("DESTINATION_PRIVATE_MARKER", source_logs, fixed = TRUE))
  expect_false(grepl("DESTINATION_PRIVATE_MARKER", snapshot_logs, fixed = TRUE))
  expect_identical(yaml::read_yaml(args$config_paths[["pipeline_state.yaml"]]), args$pipeline_state)
  source <- file.path(workspace$root, "binary.dat")
  target <- file.path(workspace$root, "copied.dat")
  writeBin(as.raw(rep(0:255, 1000)), source)
  chunks <- numeric()
  .snapshot_copy(source, target, function(bytes) chunks <<- c(chunks, bytes), block_bytes = 1024L)
  expect_true(all(chunks <= 1024))
  expect_gt(length(chunks), 1)
  expect_identical(.cache_md5(source), .cache_md5(target))
})

test_that("F17 UTF-8 and nested long filenames survive archive readback", {
  workspace <- make_f17_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  nested <- file.path(args$results_dir_path, "Sample_A", "diagnostics")
  dir.create(nested, recursive = TRUE)
  name <- paste0("annotation_", intToUtf8(252), "_", paste(rep("sample", 7), collapse = ""), ".png")
  file <- file.path(nested, name)
  fs::file_create(file)
  result <- do.call(create_review_snapshot, c(args, list(options = snapshot_options("archive"))))
  names <- zip::zip_list(result$outputs)$filename
  expect_true(any(endsWith(enc2utf8(names), enc2utf8(name))))
  # Rollback must also enumerate Unicode safely after restoring the caller locale.
  previous <- Sys.getlocale("LC_CTYPE")
  expect_error(do.call(create_review_snapshot, c(args, list(progress_callback = function(stage, ...) {
    if (stage == "folder_verification") stop("synthetic")
  }))), "Snapshot failed")
  expect_identical(Sys.getlocale("LC_CTYPE"), previous)
  expect_false(any(startsWith(list.files(args$destination, all.files = TRUE), ".review-snapshot-")))
})

test_that("F17 rejects tampered staged output, publication races, and post-rename interrupts", {
  workspace <- make_f17_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  for (mode in c("folder", "both")) {
    rename_calls <- 0L
    expect_error(do.call(create_review_snapshot, c(args, list(options = snapshot_options(mode),
      rename_output = function(from, to) {
        file.rename(from, to)
        stop(structure(list(message = "Stopped after rename", call = NULL), class = c("interrupt", "condition")))
      }))), "interrupted")
    expect_length(list.files(args$destination, all.files = TRUE, no.. = TRUE), 0L)
  }
  preserved <- NULL
  expect_error(do.call(create_review_snapshot, c(args, list(options = snapshot_options("both"),
    rename_output = function(from, to) {
      file.rename(from, to)
      preserved <<- paste0(to, ".zip")
      writeLines("other writer owns this target", preserved)
      TRUE
    }))), "no overwrite")
  expect_setequal(list.files(args$destination), basename(preserved))
  expect_identical(readLines(preserved), "other writer owns this target")
  file.remove(preserved)
  corrupted <- FALSE
  expect_error(do.call(create_review_snapshot, c(args, list(progress_callback = function(stage, ...) {
    if (stage == "folder_verification" && !corrupted) {
      stage_root <- list.dirs(args$destination, recursive = FALSE, full.names = TRUE)
      cat("corrupt", file = file.path(stage_root, "payload", "filtering_summary.csv"), append = TRUE)
      corrupted <<- TRUE
    }
  }))), "verification failed")
  expect_length(list.files(args$destination, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("F17 menu readiness never hashes files, reads caches, or builds a large inventory", {
  workspace <- make_f17_workspace(cna = TRUE)
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  env <- new.env(parent = environment(dataset_snapshot_readiness))
  function_copy <- dataset_snapshot_readiness
  environment(function_copy) <- env
  completed <- dataset_completion_readiness
  environment(completed) <- env
  env$dataset_completion_readiness <- completed
  for (name in c(".cache_md5", "cache_load_data", "cna_values_export_status", "dataset_cache_inventory", "build_snapshot_inventory")) {
    env[[name]] <- function(...) stop("Heavy operation during menu rendering")
  }
  args <- workspace$args
  expect_true(do.call(function_copy, args[names(args) %in% names(formals(function_copy))])$ready)
  args$pipeline_state <- transition_pipeline_step(args$pipeline_state, "cna_configuration", "skipped", "Sample_A",
    reason = "Omit", details = list(omitted_by_user = TRUE), force = TRUE)
  args$pipeline_state <- transition_pipeline_step(args$pipeline_state, "cna_compute", "in_progress", "Sample_A", force = TRUE)
  expect_false(f17_readiness(args)$ready)
  if (.Platform$OS.type == "windows") {
    expect_error(validate_snapshot_output_paths(paste(rep("x", 250), collapse = ""),
      list(files = data.frame(path = "processed_data/Cells.csv")), "Dataset"), "shorter")
  }
  lock <- acquire_dataset_storage_operation(args$dataset_dir_path)
  Sys.setFileTime(lock, Sys.time() - 3600)
  expect_error(acquire_dataset_storage_operation(args$dataset_dir_path), "Another")
  expect_true(dir.exists(lock))
  unlink(lock, recursive = TRUE)
})

test_that("F17 logging failures cannot undo verified exports or expose raw destination errors", {
  workspace <- make_f17_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  result <- do.call(create_review_snapshot, c(args, list(event_callback = function(...) {
    stop("Cannot log DESTINATION_PRIVATE_MARKER/private/location")
  })))
  expect_true(all(file.exists(result$outputs)))
  expect_true(any(grepl("logging was unavailable", result$warnings)))
  expect_false(grepl("DESTINATION_PRIVATE_MARKER", paste(result$warnings, collapse = ""), fixed = TRUE))
  original <- args$pipeline_state
  changed <- transition_pipeline_step(original, "annotation", "stale", "Sample_A", reason = "another session changed state")
  save_pipeline_state_at_path(changed, args$config_paths[["pipeline_state.yaml"]])
  expect_error(do.call(create_review_snapshot, args), "changed; reload")
})

test_that("F17 real GUI handlers review, confirm once, report progress and do not persist destinations", {
  workspace <- make_f17_workspace()
  on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
  args <- workspace$args
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  env <- new.env(parent = environment(create_review_snapshot))
  sys.source(file.path(app_dir, "app/state.R"), env)
  sys.source(file.path(app_dir, "app/server/snapshot_server.R"), env)
  sys.source(file.path(app_dir, "app/ui/dashboard_ui.R"), env)
  rv <- env$create_app_state(list())
  for (key in c("dataset_dir_path", "results_dir_path", "paths_list", "pipeline_state", "storage_state", "selected_config_path", "dataset_config")) rv[[key]] <- args[[key]]
  rv$pipeline_state_path <- args$config_paths[["pipeline_state.yaml"]]
  rv$live_selected_config <- args$selected_config
  context <- list(config = list(config_files = list(dataset = "dataset_config.yaml", samples = "samples_config.yaml"),
    dataset_paths = list(processed_dir = "standardized", logs_dir = "journal")), paths = list(datasets_dir = dirname(args$dataset_dir_path)))
  modal <- NULL; events <- list(); notices <- character(); progress <- list()
  env$showModal <- function(ui, ...) modal <<- as.character(ui)
  env$record_state_event <- function(...) events[[length(events) + 1L]] <<- list(...)[-1L]
  env$showNotification <- function(ui, ...) { notices <<- c(notices, as.character(ui)); "notice" }
  env$setProgress <- function(...) progress[[length(progress) + 1L]] <<- list(...)
  server <- function(input, output, session) env$register_snapshot_server(input, output, session, rv, context)
  shiny::testServer(server, {
    session$setInputs(btn_create_review_snapshot = 1)
    expect_match(modal, "Create Review Snapshot")
    expect_match(modal, "snapshot_include_logs")
    expect_match(modal, "snapshot_include_cna_values")
    session$setInputs(snapshot_destination = args$destination, snapshot_mode = "folder",
      snapshot_include_logs = TRUE, snapshot_include_cna_values = FALSE, snapshot_acknowledge = TRUE)
    session$setInputs(btn_preview_review_snapshot = 1)
    expect_length(list.files(args$destination), 0L)
    expect_match(paste(as.character(output$review_snapshot_preview), collapse = ""), "Source files")
    session$setInputs(btn_confirm_review_snapshot = 1)
    expect_match(modal, "Review snapshot verified")
    expect_length(list.files(args$destination), 1L)
    expect_gt(length(progress), 0)
    expect_false(grepl("DESTINATION_PRIVATE_MARKER", paste(capture.output(str(events)), collapse = ""), fixed = TRUE))
    expect_length(shiny::isolate(rv$active_actions), 0L)
    session$setInputs(btn_confirm_review_snapshot = 2)
    expect_length(list.files(args$destination), 1L)
    expect_identical(yaml::read_yaml(args$config_paths[["pipeline_state.yaml"]]), args$pipeline_state)
    # A dirty annotation blocks the action instead of opening another export.
    rv$annotation_dirty <- TRUE
    session$setInputs(btn_create_review_snapshot = 2)
    expect_true(any(grepl("save edits", notices)))
  })
})

# Optional expensive gate: >4 GiB entry exercises real ZIP64, not a mocked size.
# RUN_F17_LARGE_TESTS=true Rscript -e 'testthat::test_dir(..., filter="f17")'
if (identical(tolower(Sys.getenv("RUN_F17_LARGE_TESTS")), "true")) {
  test_that("F17 a real entry larger than 4 GiB survives ZIP64 copy and verification", {
    workspace <- make_f17_workspace()
    on.exit(unlink(workspace$root, recursive = TRUE), add = TRUE)
    args <- workspace$args
    path <- file.path(args$processed_dir_path, "large_binary.dat")
    connection <- file(path, "wb")
    seek(connection, where = 2^32 + 1024, origin = "start", rw = "write")
    writeBin(as.raw(0), connection)
    close(connection)
    expect_gt(file.info(path)$size, 2^32)
    result <- do.call(create_review_snapshot, c(args, list(options = snapshot_options("archive"))))
    listing <- zip::zip_list(result$outputs)
    expect_equal(listing$uncompressed_size[listing$filename == "processed_data/large_binary.dat"], file.info(path)$size)
  })
}
