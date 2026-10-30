make_r01_large_source <- function(dataset_dir) {
  path <- file.path(dataset_dir, "large-input.bin")
  connection <- file(path, "wb")
  # A sparse temporary file exercises real file.info() byte counts and hashes
  # without allocating a large R object or depending on private data.
  seek(connection, 100000002, origin = "start", rw = "write")
  writeBin(as.raw(0), connection)
  close(connection)
  path
}

test_that("R01 manifest precision survives source metadata and annotation rewrites", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  source <- make_r01_large_source(dataset_dir)
  dependencies <- cache_dependency_spec(files = c(expression = source))
  filename <- "artifact.qs2"
  cache_save_data(list(label = "before"), filename, dataset_dir, dependencies = dependencies)

  manifest <- load_cache_manifest(dataset_dir)
  expect_identical(manifest$artifacts[[filename]]$dependencies, dependencies)
  expect_equal(manifest$artifacts[[filename]]$dependencies$files$expression$size_bytes, 100000003)
  expect_true(cache_check_available(filename, dataset_dir))
  cache_save_data(list(label = "annotated"), filename, dataset_dir)

  for (reload in 1:2) {
    cache_clear_fingerprint_index()
    current_dependencies <- cache_dependency_spec(files = c(expression = source))
    expect_true(cache_check_available(filename, dataset_dir))
    expect_identical(
      cache_load_data(filename, dataset_dir, dependencies = current_dependencies, recover = FALSE),
      list(label = "annotated")
    )
  }
  changed_values <- cache_dependency_spec(files = c(expression = source), values = list(parameter = 2))
  expect_false(cache_check_valid(filename, dataset_dir, dependencies = changed_values))
  connection <- file(source, "r+b")
  writeBin(as.raw(1), connection)
  close(connection)
  Sys.setFileTime(source, file.info(source)$mtime + 2)
  changed_source <- cache_dependency_spec(files = c(expression = source))
  expect_false(cache_check_valid(filename, dataset_dir, dependencies = changed_source))
})

test_that("R01 explicit legacy repair verifies checksums and restores exact dependencies", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  source <- make_r01_large_source(dataset_dir)
  dependencies <- cache_dependency_spec(files = c(expression = source))
  filename <- "artifact.qs2"
  cache_save_data(list(label = "saved"), filename, dataset_dir, dependencies = dependencies)
  path <- cache_manifest_paths(dataset_dir)$primary
  # Reproduce the old writer: metadata loses two bytes after YAML serialization.
  yaml::write_yaml(load_cache_manifest(dataset_dir), path, precision = 7)
  expect_false(cache_check_available(filename, dataset_dir))
  legacy <- load_cache_manifest(dataset_dir)
  expect_equal(legacy$artifacts[[filename]]$dependencies$files$expression$size_bytes, 100000000)
  cache_save_data(list(label = "saved"), filename, dataset_dir)
  expect_identical(load_cache_manifest(dataset_dir)$artifacts[[filename]]$dependency_fingerprint,
    cache_dependency_fingerprint(dependencies))
  # Old annotation saves rehashed this already-rounded dependency spec.
  legacy$artifacts[[filename]]$dependency_fingerprint <- cache_dependency_fingerprint(
    legacy$artifacts[[filename]]$dependencies
  )
  yaml::write_yaml(legacy, path, precision = 7)
  before <- unname(tools::md5sum(path))
  preview <- repair_cache_manifest_precision(dataset_dir)
  expect_identical(preview$action, "repair")
  expect_identical(unname(tools::md5sum(path)), before)
  expect_false(cache_check_valid(filename, dataset_dir, dependencies))

  expect_identical(repair_cache_manifest_precision(dataset_dir, dry_run = FALSE)$action, "repair")
  expect_true(cache_check_available(filename, dataset_dir))
  expect_identical(cache_load_data(filename, dataset_dir, dependencies = dependencies), list(label = "saved"))
  expect_identical(repair_cache_manifest_precision(dataset_dir)$action, "unchanged")

  # A checksum alone is insufficient to explain an unrelated dependency record.
  precise <- load_cache_manifest(dataset_dir)
  invalid <- precise
  invalid$artifacts[[filename]]$dependencies$files$expression$size_bytes <- 100000000
  invalid$artifacts[[filename]]$dependency_fingerprint <- "unrelated-fingerprint"
  yaml::write_yaml(invalid, path, precision = 17)
  expect_identical(repair_cache_manifest_precision(dataset_dir)$action, "blocked")
  yaml::write_yaml(precise, path, precision = 17)

  artifact <- file.path(dataset_dir, "cache", filename)
  bytes <- readBin(artifact, "raw", n = file.info(artifact)$size)
  writeBin(as.raw(1), artifact)
  expect_identical(repair_cache_manifest_precision(dataset_dir)$action, "blocked")
  writeBin(bytes, artifact)

  # Genuine changes must never be excused as a rounding error, even at the same
  # size. Repair is all-or-nothing and must preserve the prior manifest.
  connection <- file(source, "r+b")
  writeBin(as.raw(1), connection)
  close(connection)
  cache_clear_fingerprint_index()
  before <- unname(tools::md5sum(path))
  expect_identical(repair_cache_manifest_precision(dataset_dir)$action, "blocked")
  expect_error(repair_cache_manifest_precision(dataset_dir, dry_run = FALSE), "No manifest was changed")
  expect_identical(unname(tools::md5sum(path)), before)
})

test_that("R01 recovering identical contents refreshes the manifest's file metadata", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  filename <- "artifact.qs2"
  cache_save_data(list(label = "saved"), filename, dataset_dir)
  artifact <- file.path(dataset_dir, "cache", filename)
  Sys.setFileTime(artifact, file.info(artifact)$mtime - 30)
  cache_save_data(list(label = "saved"), filename, dataset_dir)
  record <- load_cache_manifest(dataset_dir)$artifacts[[filename]]
  expect_identical(record$checksum, record$previous$checksum)
  writeBin(as.raw(1), artifact)
  expect_warning(recovered <- cache_load_data(filename, dataset_dir), "Recovered previous valid cache artifact")
  expect_identical(recovered, list(label = "saved"))
  expect_true(cache_check_available(filename, dataset_dir))
  expect_identical(load_cache_manifest(dataset_dir)$artifacts[[filename]]$modified_at,
    .cache_mtime_token(file.info(artifact)$mtime))
})

test_that("R01 annotation save, two reloads and dataset switches preserve scientific states", {
  skip_if_not_installed("qs2")
  dataset_dir <- withr::local_tempdir()
  fixture <- write_mini_sample(file.path(dataset_dir, "processed_data"), n_genes = 12, n_cells = 8)
  paths <- list(
    sample_dir_paths = fixture$sample_dir,
    cell_file_paths = fixture$cells_path,
    expmat_file_paths = fixture$expmat_path,
    genes_file_paths = fixture$genes_path
  )
  sample_name <- basename(fixture$sample_dir)
  config <- list(params = list(
    min_genes = 1, target_sum = 10000, log2_expr_threshold = 0,
    pca_nv = 2, seed = 1, umap = list(spread = 1, min_dist = 0.1), resolutions = c(0.5, 1)
  ))
  cache_save_data(fixture$mat, paste0("expmat_filt_", sample_name, ".qs2"), dataset_dir,
    dependencies = filter_cache_dependencies(paths, 1, config))
  cells <- data.table::copy(fixture$cells)
  cells[, `:=`(umap1 = seq_len(.N), umap2 = seq_len(.N), clust = rep(1:2, length.out = .N))]
  for (resolution in config$params$resolutions) {
    cache_save_data(cells, paste0("cells_filt_clust_res_", resolution, "_", sample_name, ".qs2"),
      dataset_dir, dependencies = clustering_cache_dependencies(paths, 1, config, resolution))
  }
  cells[, cell_type := rep(c("T_cell", "Hepatocyte"), length.out = .N)]
  data.table::fwrite(cells, fixture$cells_path)
  selected <- paste0("cells_filt_clust_res_0.5_", sample_name, ".qs2")
  cache_save_data(cells, selected, dataset_dir)
  state <- new_pipeline_state("Dataset_A", sample_name)
  for (step in c("standardization", "clustering", "resolution", "differential_expression", "annotation")) {
    state <- transition_pipeline_step(state, step, "completed",
      sample = if (step == "standardization") NULL else sample_name,
      details = if (step == "resolution") list(resolution = 0.5) else NULL, force = TRUE)
  }
  state <- transition_pipeline_step(state, "cna_configuration", "skipped", sample_name,
    reason = "Explicit omission", details = list(omitted_by_user = TRUE), force = TRUE)
  save_pipeline_state_atomic(state, dataset_dir)
  other_dir <- withr::local_tempdir()
  save_pipeline_state_atomic(new_pipeline_state("Dataset_B", "Other"), other_dir)
  for (reload in 1:2) {
    load_pipeline_state(other_dir, "Dataset_B", "Other")
    cache_clear_fingerprint_index()
    restored <- load_pipeline_state(dataset_dir, "Dataset_A", sample_name)
    reconciled <- reconcile_pipeline_state_cache(restored, paths, config,
      list(resolutions = stats::setNames(list(0.5), sample_name)), dataset_dir, data.table::data.table())
    expect_length(attr(reconciled, "cache_changes"), 0L)
    for (step in c("clustering", "resolution", "differential_expression", "annotation")) {
      expect_identical(get_pipeline_step(reconciled, step, sample_name)$status, "completed")
    }
    restored_cells <- cache_load_data(selected, dataset_dir,
      dependencies = clustering_cache_dependencies(paths, 1, config, 0.5), recover = FALSE)
    expect_identical(restored_cells$cell_type, cells$cell_type)
    expect_identical(data.table::fread(fixture$cells_path)$cell_type, cells$cell_type)
    reconciled <- save_pipeline_state_atomic(reconciled, dataset_dir)
  }

  # Simulate the old startup screen falsely invalidating previously completed
  # work. Recovery must establish exact scientific provenance and saved labels
  # before restoring the preserved pre-reconciliation snapshot.
  reason <- paste0("Clustering cache is missing, corrupt, or no longer matches its ",
    "standardized inputs and parameters. Rerun clustering.")
  stale <- transition_pipeline_step(reconciled, "clustering", "stale", sample_name,
    reason = reason, details = list(stale_after = "cache_validation"))
  stale <- mark_pipeline_steps_stale(stale, "clustering", sample_name, reason = reason)
  save_pipeline_state_atomic(stale, dataset_dir)
  decisions <- list(resolutions = stats::setNames(list(0.5), sample_name))
  state_path <- pipeline_state_paths(dataset_dir)$primary
  before <- unname(tools::md5sum(state_path))
  preview <- recover_dataset_cache_precision(dataset_dir, paths, config, decisions)
  expect_length(preview$restored_steps, 5L)
  expect_identical(unname(tools::md5sum(state_path)), before)

  changed_cells <- data.table::copy(cells)
  changed_cells$cell_type[[1]] <- "Other"
  data.table::fwrite(changed_cells, fixture$cells_path)
  expect_error(recover_dataset_cache_precision(dataset_dir, paths, config, decisions, dry_run = FALSE),
    "Saved annotations disagree")
  expect_identical(unname(tools::md5sum(state_path)), before)
  data.table::fwrite(cells, fixture$cells_path)

  changed <- config
  changed$params$seed <- 2
  expect_false(cache_check_valid(selected, dataset_dir,
    dependencies = clustering_cache_dependencies(paths, 1, changed, 0.5)))
  expect_error(recover_dataset_cache_precision(dataset_dir, paths, changed, decisions, dry_run = FALSE),
    "Current scientific inputs do not validate cache")
  expect_identical(unname(tools::md5sum(state_path)), before)
  outcome <- recover_dataset_cache_precision(dataset_dir, paths, config, decisions, dry_run = FALSE)
  expect_true(file.exists(file.path(outcome$backup_dir, "pipeline_state.yaml.bak")))
  recovered <- load_pipeline_state(dataset_dir, "Dataset_A", sample_name)
  expect_identical(get_pipeline_step(recovered, "annotation", sample_name)$status, "completed")
  expect_identical(get_pipeline_step(recovered, "cna_configuration", sample_name)$status, "skipped")
  expect_identical(cache_load_data(selected, dataset_dir)$cell_type, cells$cell_type)
  for (reload in 1:2) {
    recovered <- reconcile_pipeline_state_cache(recovered, paths, config,
      decisions, dataset_dir, data.table::data.table())
    expect_length(attr(recovered, "cache_changes"), 0L)
    expect_identical(get_pipeline_step(recovered, "clustering", sample_name)$status, "completed")
  }

  recovered <- transition_pipeline_step(recovered, "cna_configuration", "completed", sample_name,
    details = list(reference_cell_types = "T_cell", potentially_malignant_cell_types = "Hepatocyte"),
    force = TRUE)
  recovered <- save_pipeline_state_atomic(recovered, dataset_dir)
  stale <- transition_pipeline_step(recovered, "clustering", "stale", sample_name,
    reason = reason, details = list(stale_after = "cache_validation"))
  stale <- mark_pipeline_steps_stale(stale, "clustering", sample_name, reason = reason)
  save_pipeline_state_atomic(stale, dataset_dir)
  decisions$cna_ref_cells <- stats::setNames(list("T_cell"), sample_name)
  decisions$cna_pot_mal_cells <- stats::setNames(list("Hepatocyte"), sample_name)
  expect_length(recover_dataset_cache_precision(dataset_dir, paths, config, decisions)$restored_steps, 5L)
  decisions$cna_ref_cells[[sample_name]] <- "Other"
  expect_error(recover_dataset_cache_precision(dataset_dir, paths, config, decisions),
    "Saved CNA configuration differs")
})
