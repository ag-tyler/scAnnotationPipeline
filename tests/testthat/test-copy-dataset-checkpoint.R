checkpoint_script <- new.env(parent = globalenv())
sys.source(testthat::test_path("..", "..", "scripts", "copy_dataset_checkpoint.R"), envir = checkpoint_script)
checkpoint_app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")

make_checkpoint_workspace <- function(root, finished = FALSE) {
  dir.create(root)
  id <- basename(root)
  sample_ids <- c("CRC_N2", "CRC_T2", "CRC_LM2")
  processed <- file.path(root, "processed_data")
  dir.create(processed)
  metadata <- build_samples(sample_ids)
  metadata$n_cells <- rep("4", 3)
  metadata$patient <- rep("002", 3)
  data.table::fwrite(metadata, file.path(processed, "Samples.csv"))
  config <- list(project_info = list(dataset_id = id),
    std_names = list(expmat = "Exp_data_UMIcounts.mtx", genes = "Genes.txt", cells = "Cells.csv", samples = "Samples.csv"),
    params = list(resolutions = 0.1, min_genes = 1, target_sum = 100000,
      log2_expr_threshold = 4, pca_nv = 2, seed = 3988, umap = list(spread = 5, min_dist = 0.1)))
  yaml::write_yaml(config, file.path(root, "dataset_config.yaml"), precision = 17)
  selected <- setup_selected_config(sample_ids)
  selected$resolutions[] <- list(0.1)
  selected$cna_sample_notes <- list(CRC_N2 = "Normal tissue: omit CNA.", CRC_T2 = "Inspect epithelial cells.")
  state <- new_pipeline_state(id, sample_ids)
  state <- transition_pipeline_step(state, "standardization", "completed", force = TRUE)
  for (sample in sample_ids) {
    folder <- file.path(processed, sample)
    dir.create(folder)
    expression <- Matrix::Matrix(matrix(seq_len(12), nrow = 3), sparse = TRUE)
    dimnames(expression) <- list(paste0("G", 1:3), paste0(sample, "_", 1:4))
    Matrix::writeMM(expression, file.path(folder, config$std_names$expmat))
    writeLines(rownames(expression), file.path(folder, "Genes.txt"))
    cells <- build_cells(colnames(expression))
    data.table::set(cells, j = "sample", value = rep(sample, nrow(cells)))
    cells[, `:=`(cell_type = rep(c("T_cell", "Epithelial"), 2),
      complexity = 3L, umap1 = as.numeric(1:4), umap2 = as.numeric(4:1), clust = c("0", "1", "0", "1"))]
    data.table::fwrite(cells, file.path(folder, "Cells.csv"))
    paths <- list(expmat_file_paths = file.path(folder, config$std_names$expmat),
      genes_file_paths = file.path(folder, "Genes.txt"), cell_file_paths = file.path(folder, "Cells.csv"))
    deps <- filter_cache_dependencies(paths, 1, config)
    for (repeat_save in 1:2) cache_save_data(expression, paste0("expmat_filt_", sample, ".qs2"), root,
      dependencies = deps, nthreads = 1)
    cache_save_data(cells, paste0("cells_filt_clust_res_0.1_", sample, ".qs2"), root,
      dependencies = clustering_cache_dependencies(paths, 1, config, 0.1), nthreads = 1)
    state <- transition_pipeline_step(state, "clustering", "completed", sample, force = TRUE)
    if (!finished) next
    for (step in c("resolution", "differential_expression", "annotation")) {
      state <- transition_pipeline_step(state, step, "completed", sample, force = TRUE)
    }
    result <- file.path(root, "results", sample)
    for (name in c("1_cluster_plots", "2_de_plots", "3_cna_plots")) dir.create(file.path(result, name), recursive = TRUE)
    for (name in c("1_cluster_plots/clusters_plot_SAMPLE_res_0.1.png", "2_de_plots/0.png", "2_de_plots/cell_types.png")) {
      writeBin(as.raw(1:12), file.path(result, sub("SAMPLE", sample, name)))
    }
    writeLines("gene,cluster\nG1,0", file.path(result, "2_de_plots", "all_marker_matches.csv"))
    if (sample == "CRC_N2") {
      state <- transition_pipeline_step(state, "cna_configuration", "skipped", sample,
        reason = "Normal tissue.", details = list(omitted_by_user = TRUE), force = TRUE)
      state <- synchronize_pipeline_cna_omission(state, sample)
      next
    }
    selected$cna_ward_ref_cluster[[sample]] <- list(list(k = 2, cluster = 1))
    cna <- data.table::data.table(gene = rownames(expression), chr = "01", start_pos = 1:3)
    for (cell in cells$cell_name) data.table::set(cna, j = cell, value = c(0.1, 0.2, 0.3))
    matrix_file <- paste0("cna_matrix_", sample, ".qs2")
    cache_save_data(cna, matrix_file, root, nthreads = 1,
      dependencies = cache_dependency_spec(artifacts = paste0("expmat_filt_", sample, ".qs2"), dataset_dir_path = root))
    tree <- stats::hclust(stats::dist(matrix(seq_len(8), nrow = 4, dimnames = list(cells$cell_name, NULL))))
    cache_save_data(tree, paste0("hclust_", sample, ".qs2"), root, nthreads = 1,
      dependencies = cache_dependency_spec(artifacts = matrix_file, dataset_dir_path = root))
    signal <- data.table::data.table(cell_name = cells$cell_name, cna_signal = 0.1, cna_cor = 0.9)
    cache_save_data(signal, paste0("cna_sig_cor_", sample, "_subclone_1.qs2"), root, nthreads = 1,
      dependencies = cache_dependency_spec(artifacts = matrix_file, dataset_dir_path = root))
    for (step in c("cna_configuration", "cna_compute", "cna_cluster_selection", "cna_signal_correlation", "cna_thresholds", "cna_assignment")) {
      state <- transition_pipeline_step(state, step, "completed", sample, force = TRUE)
    }
    for (name in c(paste0("cna_summary_heatmap_", sample, ".png"), paste0("cna_umap_assigned_", sample, ".png"))) {
      writeBin(as.raw(1:12), file.path(result, "3_cna_plots", name))
    }
  }
  yaml::write_yaml(selected, file.path(root, "selected_config.yaml"), precision = 17)
  for (name in c("pipeline_state.yaml", "pipeline_state.yaml.bak")) yaml::write_yaml(state, file.path(root, name), precision = 17)
  for (name in c("storage_state.yaml", "storage_state.yaml.bak")) {
    yaml::write_yaml(new_dataset_storage_state(id), file.path(root, name), precision = 17)
  }
  dir.create(file.path(root, "logs"))
  writeLines(paste("historical event from", id), file.path(root, "logs", "pipeline.log"))
  root
}

checkpoint_hashes <- function(root) {
  paths <- sort(list.files(root, all.files = TRUE, no.. = TRUE, recursive = TRUE, full.names = TRUE))
  stats::setNames(unname(tools::md5sum(paths)), substring(paths, nchar(root) + 2L))
}

test_that("checkpoint copies preserve caches, recovery metadata, notes and scientific state", {
  root <- withr::local_tempdir()
  source <- make_checkpoint_workspace(file.path(root, "Working"))
  original_hashes <- checkpoint_hashes(source)
  output <- file.path(root, "01_Clustered")
  result <- checkpoint_script$copy_dataset_checkpoint(source, output, checkpoint_app_dir)
  expect_identical(checkpoint_hashes(source), original_hashes)
  expect_equal(result$dataset_id, "01_Clustered")
  expect_equal(result$samples, c("CRC_N2", "CRC_T2", "CRC_LM2"))
  for (name in c("pipeline_state.yaml", "pipeline_state.yaml.bak", "storage_state.yaml", "storage_state.yaml.bak")) {
    expect_equal(yaml::read_yaml(file.path(output, name))$dataset_id, "01_Clustered")
  }
  source_state <- yaml::read_yaml(file.path(source, "pipeline_state.yaml"))
  output_state <- yaml::read_yaml(file.path(output, "pipeline_state.yaml"))
  expect_identical(output_state$samples, source_state$samples)
  expect_identical(output_state$dataset_steps, source_state$dataset_steps)
  expect_identical(readBin(file.path(source, "selected_config.yaml"), "raw", 10000),
    readBin(file.path(output, "selected_config.yaml"), "raw", 10000))
  expect_identical(readLines(file.path(output, "logs", "pipeline.log")), "historical event from Working")
  expect_true(file.exists(file.path(output, "checkpoint_copy.yaml")))
  manifest <- load_cache_manifest(output)
  for (filename in names(manifest$artifacts)) {
    expect_identical(manifest$artifacts[[filename]]$dataset_root, normalizePath(output, winslash = "/"))
    expect_true(cache_check_available(filename, output))
    expect_true(cache_check_valid(filename, output))
    dependency <- manifest$artifacts[[filename]]$dependencies$files$expression
    expect_true(startsWith(dependency$path, normalizePath(output, winslash = "/")))
  }
  # Independence: original files disappear, yet copied caches remain usable.
  expect_true(file.rename(source, file.path(root, "Moved_Original")))
  for (filename in names(manifest$artifacts)) expect_true(cache_check_available(filename, output))
  # Chaining checkpoints must rebase references again, without recomputation.
  next_output <- file.path(root, "02_Annotation")
  checkpoint_script$copy_dataset_checkpoint(output, next_output, checkpoint_app_dir)
  expect_equal(yaml::read_yaml(file.path(next_output, "pipeline_state.yaml"))$dataset_id, "02_Annotation")
})

test_that("finished checkpoints retain omission and remain snapshot/cleanup eligible", {
  root <- withr::local_tempdir()
  source <- make_checkpoint_workspace(file.path(root, "Working"), finished = TRUE)
  output <- file.path(root, "04_Finished")
  checkpoint_script$copy_dataset_checkpoint(source, output, checkpoint_app_dir)
  config <- yaml::read_yaml(file.path(output, "dataset_config.yaml"))
  selected <- yaml::read_yaml(file.path(output, "selected_config.yaml"))
  state <- yaml::read_yaml(file.path(output, "pipeline_state.yaml"))
  storage <- yaml::read_yaml(file.path(output, "storage_state.yaml"))
  checked <- check_prepared_data(file.path(output, "processed_data"), config$std_names)
  arguments <- list(pipeline_state = state, paths_list = checked$paths_list, selected_config = selected,
    selected_config_path = file.path(output, "selected_config.yaml"),
    results_dir_path = file.path(output, "results"), dataset_dir_path = output)
  cleanup <- do.call(dataset_cleanup_readiness, arguments)
  expect_true(cleanup$ready, info = paste(cleanup$reasons, collapse = "; "))
  snapshot <- do.call(dataset_snapshot_readiness, c(arguments, list(storage_state = storage,
    dataset_config = config, processed_dir_path = file.path(output, "processed_data"))))
  expect_true(snapshot$ready, info = paste(snapshot$reasons, collapse = "; "))
  expect_true(pipeline_cna_is_omitted(state, "CRC_N2"))
  expect_equal(get_pipeline_step(state, "cna_assignment", "CRC_T2")$status, "completed")
})

test_that("transferred cache paths are rebased without the old machine being accessible", {
  root <- withr::local_tempdir()
  source <- make_checkpoint_workspace(file.path(root, "Transferred"))
  source_path <- normalizePath(source, winslash = "/")
  old_root <- "Z:/OldComputer/datasets/Transferred"
  for (name in c("cache_manifest.yaml", "cache_manifest.yaml.bak")) {
    path <- file.path(source, "cache", name)
    text <- readLines(path)
    writeLines(gsub(source_path, old_root, text, fixed = TRUE), path)
  }
  output <- file.path(root, "Mac_Ready")
  checkpoint_script$copy_dataset_checkpoint(source, output, checkpoint_app_dir)
  for (filename in names(load_cache_manifest(output)$artifacts)) expect_true(cache_check_available(filename, output))
})

test_that("unsafe or inconsistent sources never publish a partial checkpoint", {
  root <- withr::local_tempdir()
  source <- make_checkpoint_workspace(file.path(root, "Working"))
  output <- file.path(root, "New")
  run <- function(...) checkpoint_script$copy_dataset_checkpoint(source, output, checkpoint_app_dir, ...)
  expect_error(checkpoint_script$copy_dataset_checkpoint(source, source, checkpoint_app_dir), "non-nested")
  expect_error(checkpoint_script$copy_dataset_checkpoint(source, file.path(source, "nested"), checkpoint_app_dir), "non-nested")
  expect_error(checkpoint_script$copy_dataset_checkpoint(source, root, checkpoint_app_dir), "non-nested")
  dir.create(output)
  expect_error(run(), "already exists")
  unlink(output, recursive = TRUE)
  dir.create(file.path(source, ".storage-operation.lock"))
  expect_error(run(), "lock/temporary")
  unlink(file.path(source, ".storage-operation.lock"), recursive = TRUE)
  path <- file.path(source, "pipeline_state.yaml")
  state <- yaml::read_yaml(path)
  state$samples$CRC_N2$clustering$status <- "in_progress"
  yaml::write_yaml(state, path, precision = 17)
  expect_error(run(), "in progress")
  state$samples$CRC_N2$clustering$status <- "completed"
  yaml::write_yaml(state, path, precision = 17)
  path <- file.path(source, "storage_state.yaml")
  storage <- yaml::read_yaml(path)
  storage$status <- "archived"
  yaml::write_yaml(storage, path, precision = 17)
  expect_error(run(), "Only active")
  storage$status <- "active"
  yaml::write_yaml(storage, path, precision = 17)
  # Tampering with a recorded standardized input must not be legitimized.
  writeLines("G1\nG2\nchanged", file.path(source, "processed_data", "CRC_T2", "Genes.txt"))
  expect_error(run(), "recorded checksum")
  expect_false(dir.exists(output))
  expect_length(list.files(root, pattern = "^\\.checkpoint-copy-", all.files = TRUE), 0L)
})

test_that("checkpoint copying runs in a clean R process without the app test helpers", {
  root <- withr::local_tempdir()
  source <- make_checkpoint_workspace(file.path(root, "Working"))
  output <- file.path(root, "Standalone")
  runner <- file.path(root, "run.R")
  literal <- function(value) paste(capture.output(dput(value)), collapse = "\n")
  writeLines(c(
    paste0("source(", literal(file.path(checkpoint_app_dir, "scripts", "copy_dataset_checkpoint.R")), ")"),
    paste0("copy_dataset_checkpoint(", literal(source), ", ", literal(output),
      ", app_dir = ", literal(checkpoint_app_dir), ")")
  ), runner)
  executable <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  result <- suppressWarnings(system2(executable, c("--vanilla", shQuote(runner)), stdout = TRUE, stderr = TRUE))
  expect_null(attr(result, "status"), info = paste(result, collapse = "\n"))
  expect_true(file.exists(file.path(output, "checkpoint_copy.yaml")))
})
