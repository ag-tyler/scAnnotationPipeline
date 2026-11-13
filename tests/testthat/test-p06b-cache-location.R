test_that("copied caches use this workspace and verify changed metadata", {
  skip_if_not_installed("qs2")
  original <- withr::local_tempdir()
  destination <- file.path(withr::local_tempdir(), "copy with spaces")
  dir.create(destination)
  dir.create(file.path(original, "processed_data", "Sample"), recursive = TRUE)
  input <- file.path(original, "processed_data", "Sample", "Genes.txt")
  writeLines("original", input)
  cache_save_data(42L, "object.qs2", original,
    dependencies = cache_dependency_spec(files = c(genes = input)))
  fast_environment <- new.env(parent = environment(cache_check_available))
  fast_environment$.cache_file_fingerprint <- function(...) stop("Unexpected checksum on the fast path")
  fast_screen <- cache_check_available
  environment(fast_screen) <- fast_environment
  expect_true(fast_screen("object.qs2", original))
  expect_true(file.copy(file.path(original, "processed_data"), destination, recursive = TRUE))
  expect_true(file.copy(file.path(original, "cache"), destination, recursive = TRUE))
  artifact <- file.path(destination, "cache", "object.qs2")
  copied_input <- file.path(destination, "processed_data", "Sample", "Genes.txt")
  Sys.setFileTime(artifact, Sys.time() - 120)
  manifest <- load_cache_manifest(destination)
  expect_true(cache_check_available("object.qs2", destination, manifest))
  expect_identical(cache_load_data("object.qs2", destination,
    dependencies = cache_dependency_spec(files = c(genes = copied_input))), 42L)
  expect_true(file.rename(copied_input, paste0(copied_input, ".moved")))
  expect_false(cache_check_available("object.qs2", destination, manifest))
  expect_true(file.rename(paste0(copied_input, ".moved"), copied_input))

  # The original still exists: changing this copy must never consult that one.
  writeLines("modified", copied_input)
  Sys.setFileTime(copied_input, Sys.time() + 10)
  expect_false(cache_check_available("object.qs2", destination, manifest))
  writeLines("original", copied_input)
  Sys.setFileTime(copied_input, Sys.time() + 20)

  # Reproduce a schema-v1 Windows manifest, with either slash convention.
  record <- manifest$artifacts$object.qs2
  record$dataset_root <- NULL
  for (prefix in c("C:/old/workspace", "C:\\old\\workspace")) {
    record$dependencies$files$genes$path <- paste0(prefix, "/processed_data/Sample/Genes.txt")
    manifest$artifacts$object.qs2 <- record
    expect_true(cache_check_available("object.qs2", destination, manifest))
  }
  yaml::write_yaml(manifest, cache_manifest_paths(destination)$primary, precision = 17)
  fingerprint <- record$dependency_fingerprint
  expect_identical(repair_cache_manifest_location(destination)$action, "repair")
  expect_identical(repair_cache_manifest_location(destination, dry_run = FALSE)$action, "repair")
  expect_identical(repair_cache_manifest_location(destination)$action, "unchanged")
  refreshed <- load_cache_manifest(destination)$artifacts$object.qs2
  expect_identical(refreshed$dependency_fingerprint, fingerprint)
  expect_true(cache_check_available("object.qs2", destination))

  # Corruption with the same byte count still fails the timestamp fallback.
  bytes <- readBin(artifact, "raw", n = file.info(artifact)$size)
  bytes[[length(bytes)]] <- as.raw(bitwXor(as.integer(bytes[[length(bytes)]]), 1L))
  writeBin(bytes, artifact)
  Sys.setFileTime(artifact, Sys.time() + 30)
  expect_false(cache_check_available("object.qs2", destination))
  expect_identical(repair_cache_manifest_location(destination)$action, "blocked")
  before <- unname(tools::md5sum(cache_manifest_paths(destination)$primary))
  expect_error(repair_cache_manifest_location(destination, dry_run = FALSE), "No manifest was changed")
  expect_identical(unname(tools::md5sum(cache_manifest_paths(destination)$primary)), before)
})

test_that("source resolution rejects traversal and never guesses by basename", {
  root <- withr::local_tempdir()
  expect_null(.cache_source_path(list(path = "C:/old/processed_data/../Genes.txt"), root))
  expect_identical(.cache_source_path(list(path = "C:/external/Genes.txt"), root), "C:/external/Genes.txt")
  expect_null(.cache_source_path(list(path = "C:/old/../external.txt"), root, "C:/old"))
})

make_location_state_fixture <- function(dataset_dir, n_genes = 12) {
  fixture <- write_mini_sample(file.path(dataset_dir, "processed_data"), n_genes = n_genes, n_cells = 8)
  paths <- list(sample_dir_paths = fixture$sample_dir, cell_file_paths = fixture$cells_path,
    expmat_file_paths = fixture$expmat_path, genes_file_paths = fixture$genes_path)
  sample <- basename(fixture$sample_dir)
  config <- list(params = list(min_genes = 1, target_sum = 10000,
    log2_expr_threshold = 0, pca_nv = 2, seed = 1,
    umap = list(spread = 1, min_dist = 0.1), resolutions = 0.5))
  filtered <- load_filter_cells_expmat(fixture$cells_path, fixture$expmat_path, fixture$genes_path, config)
  cells <- data.table::copy(filtered$cells_filt)
  cells[, `:=`(umap1 = seq_len(.N), umap2 = seq_len(.N), clust = 1L)]
  cache_save_data(filtered$expmat_filt, paste0("expmat_filt_", sample, ".qs2"), dataset_dir,
    dependencies = filter_cache_dependencies(paths, 1, config))
  cache_save_data(cells, paste0("cells_filt_clust_res_0.5_", sample, ".qs2"), dataset_dir,
    dependencies = clustering_cache_dependencies(paths, 1, config, 0.5))
  state <- new_pipeline_state("Copied", sample)
  for (step in c("standardization", "clustering", "resolution", "differential_expression", "annotation")) {
    state <- transition_pipeline_step(state, step, "completed",
      sample = if (step == "standardization") NULL else sample,
      details = if (step == "resolution") list(resolution = 0.5) else NULL, force = TRUE)
  }
  state <- transition_pipeline_step(state, "cna_configuration", "skipped", sample,
    reason = "Explicit omission", details = list(omitted_by_user = TRUE), force = TRUE)
  state <- synchronize_pipeline_cna_omission(state, sample)
  state <- save_pipeline_state_atomic(state, dataset_dir)
  list(state = state, paths = paths, config = config, sample = sample,
    selected = list(resolutions = stats::setNames(list(0.5), sample)))
}

test_that("load and reload preserve copied progress; explicit recovery validates provenance", {
  skip_if_not_installed("qs2")
  dataset <- withr::local_tempdir()
  f <- make_location_state_fixture(dataset)
  manifest <- load_cache_manifest(dataset)
  for (name in names(manifest$artifacts)) {
    manifest$artifacts[[name]]$dataset_root <- NULL
    for (key in names(manifest$artifacts[[name]]$dependencies$files)) {
      source <- manifest$artifacts[[name]]$dependencies$files[[key]]
      source$path <- sub("^.*(/processed_data/)", "C:/unavailable/workspace\\1", source$path)
      manifest$artifacts[[name]]$dependencies$files[[key]] <- source
    }
    Sys.setFileTime(file.path(dataset, "cache", name), Sys.time() - 120)
  }
  yaml::write_yaml(manifest, cache_manifest_paths(dataset)$primary, precision = 17)
  original_revision <- manifest$revision
  refreshed_revision <- NULL
  for (reload in 1:2) {
    state <- reconcile_pipeline_state_cache(load_pipeline_state(dataset), f$paths, f$config,
      f$selected, dataset, data.table::data.table())
    expect_length(attr(state, "cache_changes"), 0L)
    expect_identical(state$samples, f$state$samples)
    current_manifest <- load_cache_manifest(dataset)
    if (reload == 1L) {
      refreshed_revision <- current_manifest$revision
      expect_gt(refreshed_revision, original_revision)
      expect_identical(current_manifest$artifacts[[1]]$dataset_root, normalizePath(dataset, winslash = "/"))
    } else expect_identical(current_manifest$revision, refreshed_revision)
  }
  reason <- paste0("Clustering cache is missing, corrupt, or no longer matches its ",
    "standardized inputs and parameters. Rerun clustering.")
  stale <- transition_pipeline_step(f$state, "clustering", "stale", f$sample,
    reason = reason, details = list(stale_after = "cache_validation"))
  stale <- mark_pipeline_steps_stale(stale, "clustering", f$sample, reason = reason)
  save_pipeline_state_atomic(stale, dataset)
  state_path <- pipeline_state_paths(dataset)$primary
  before <- unname(tools::md5sum(state_path))
  preview <- recover_dataset_cache_location(dataset, f$paths, f$config, f$selected)
  expect_length(preview$restored_steps, 6L)
  expect_identical(unname(tools::md5sum(state_path)), before)
  changed <- f$config
  changed$params$seed <- 99
  expect_error(recover_dataset_cache_location(dataset, f$paths, changed, f$selected),
    "Current scientific inputs do not validate")
  expect_identical(unname(tools::md5sum(state_path)), before)
  result <- recover_dataset_cache_location(dataset, f$paths, f$config, f$selected, dry_run = FALSE)
  expect_true(file.exists(file.path(result$backup_dir, "pipeline_state.yaml.bak")))
  restored <- load_pipeline_state(dataset)
  expect_identical(restored$samples, f$state$samples)
  expect_identical(get_pipeline_step(restored, "cna_compute", f$sample)$status, "skipped")
  reconciled <- reconcile_pipeline_state_cache(restored, f$paths, f$config,
    f$selected, dataset, data.table::data.table())
  expect_length(attr(reconciled, "cache_changes"), 0L)

  # An actual rerun invalidation cannot be promoted by the recovery command.
  stale <- transition_pipeline_step(restored, "clustering", "stale", f$sample,
    reason = "Clustering rerun", details = list(stale_after = "clustering"))
  stale <- mark_pipeline_steps_stale(stale, "clustering", f$sample, reason = "Clustering rerun")
  save_pipeline_state_atomic(stale, dataset)
  expect_length(recover_dataset_cache_location(dataset, f$paths, f$config, f$selected)$restored_steps, 0L)
})

test_that("portable fingerprints omit writer metadata and validate historical Windows hashes", {
  # This is the actual implementation-string hash recorded by Tang's Windows R
  # 4.5.3 manifest, rather than a fixture generated by the current hash writer.
  profile <- c(0L, 4L, 5L, 3L, 6L)
  expect_identical(.cache_legacy_hash("filter-v1", profile), "c173b621c79cb4e083e07705a0e0af98")
  environment_copy <- new.env(parent = environment(cache_hash_value))
  environment_copy$serialize <- function(...) {
    bytes <- base::serialize(...)
    bytes[7:10] <- as.raw(c(0, 4, 5, 3))
    bytes
  }
  other_writer <- cache_hash_value
  environment(other_writer) <- environment_copy
  value <- list(cells = data.frame(id = c("A", "B"), complexity = c(10L, 20L)), seed = 1L)
  reordered <- value
  a <- attributes(reordered$cells)
  attributes(reordered$cells) <- a[rev(seq_along(a))]
  expect_identical(cache_hash_value(value), cache_hash_value(reordered))
  expect_identical(other_writer(value), cache_hash_value(value))

  current <- cache_dependency_spec(values = list(input = value, implementation = "filter-v1"))
  legacy <- .cache_scientific_dependencies(current)
  legacy$values <- lapply(attr(current, "cache_values"), function(v) list(hash = .cache_legacy_hash(v, profile)))
  record <- list(dependencies = legacy, dependency_fingerprint = .cache_legacy_hash(legacy, profile))
  expect_true(.cache_dependency_matches(record, current))
  value$seed <- 2L
  changed <- cache_dependency_spec(values = list(input = value, implementation = "filter-v1"))
  expect_false(.cache_dependency_matches(record, changed))
})

test_that("recovery refuses altered checkpoints and retired storage", {
  skip_if_not_installed("qs2")
  dataset <- withr::local_tempdir()
  f <- make_location_state_fixture(dataset)
  reason <- paste0("Clustering cache is missing, corrupt, or no longer matches its ",
    "standardized inputs and parameters. Rerun clustering.")
  stale <- transition_pipeline_step(f$state, "clustering", "stale", f$sample,
    reason = reason, details = list(stale_after = "cache_validation"))
  stale <- mark_pipeline_steps_stale(stale, "clustering", f$sample, reason = reason)
  stale$samples[[f$sample]]$clustering$details$extra_edit <- TRUE
  save_pipeline_state_atomic(stale, dataset)
  before <- unname(tools::md5sum(pipeline_state_paths(dataset)$primary))
  expect_error(recover_dataset_cache_location(dataset, f$paths, f$config, f$selected,
    dry_run = FALSE), "Step changed since")
  expect_identical(unname(tools::md5sum(pipeline_state_paths(dataset)$primary)), before)
  storage <- new_dataset_storage_state("Copied")
  storage$status <- "archived"
  yaml::write_yaml(storage, file.path(dataset, "storage_state.yaml"))
  expect_error(recover_dataset_cache_location(dataset, f$paths, f$config, f$selected,
    dry_run = FALSE), "retired storage")
  expect_identical(unname(tools::md5sum(pipeline_state_paths(dataset)$primary)), before)
})

test_that("legacy cell hash migration requires an exact deterministic filtering replay", {
  skip_if_not_installed("qs2")
  dataset <- withr::local_tempdir()
  f <- make_location_state_fixture(dataset)
  profile <- c(0L, 4L, 5L, 3L, 6L)
  manifest <- load_cache_manifest(dataset)
  for (name in names(manifest$artifacts)) {
    deps <- if (startsWith(name, "expmat")) filter_cache_dependencies(f$paths, 1, f$config) else
      clustering_cache_dependencies(f$paths, 1, f$config, 0.5)
    values <- attr(deps, "cache_values")
    # Represent a historical dataframe attribute that no longer exists in the
    # current reader. It changes old RDS bytes without changing filtering.
    attr(values$cells_input, "historical_attribute") <- "old"
    deps <- .cache_scientific_dependencies(deps)
    deps$values <- lapply(values, function(value) list(hash = .cache_legacy_hash(value, profile)))
    record <- manifest$artifacts[[name]]
    record$dependencies <- deps
    record$dependency_fingerprint <- .cache_legacy_hash(deps, profile)
    record$fingerprint_format <- NULL
    manifest$artifacts[[name]] <- record
  }
  yaml::write_yaml(manifest, cache_manifest_paths(dataset)$primary, precision = 17)
  checkpoint <- f$state
  checkpoint$revision <- 0L
  yaml::write_yaml(checkpoint, pipeline_state_paths(dataset)$backup)
  migration <- recover_dataset_cache_location(dataset, f$paths, f$config, f$selected)
  expect_length(migration$restored_steps, 0L)
  expect_identical(migration$replayed_samples, f$sample)
  reason <- paste0("Clustering cache is missing, corrupt, or no longer matches its ",
    "standardized inputs and parameters. Rerun clustering.")
  stale <- transition_pipeline_step(f$state, "clustering", "stale", f$sample,
    reason = reason, details = list(stale_after = "cache_validation"))
  stale <- mark_pipeline_steps_stale(stale, "clustering", f$sample, reason = reason)
  save_pipeline_state_atomic(stale, dataset)
  preview <- recover_dataset_cache_location(dataset, f$paths, f$config, f$selected)
  expect_identical(preview$replayed_samples, f$sample)
  expect_length(preview$restored_steps, 6L)
  filename <- paste0("cells_filt_clust_res_0.5_", f$sample, ".qs2")
  expect_false(cache_check_valid(filename, dataset,
    dependencies = clustering_cache_dependencies(f$paths, 1, f$config, 0.5)))
  recover_dataset_cache_location(dataset, f$paths, f$config, f$selected, dry_run = FALSE)
  expect_true(cache_check_valid(filename, dataset,
    dependencies = clustering_cache_dependencies(f$paths, 1, f$config, 0.5)))
  # Annotation saves inherit scientific provenance, including the verified
  # legacy input binding, while replacing their own checksum and labels.
  cells <- cache_load_data(filename, dataset)
  cache_save_data(cells, filename, dataset)
  expect_true(cache_check_valid(filename, dataset,
    dependencies = clustering_cache_dependencies(f$paths, 1, f$config, 0.5)))
  repeat_recovery <- recover_dataset_cache_location(dataset, f$paths, f$config, f$selected)
  expect_length(repeat_recovery$restored_steps, 0L)
  expect_length(repeat_recovery$replayed_samples, 0L)
  changed <- f$config
  changed$params$seed <- 99L
  expect_false(cache_check_valid(filename, dataset,
    dependencies = clustering_cache_dependencies(f$paths, 1, changed, 0.5)))

  # A validly registered but scientifically different matrix must not be
  # accepted merely because it has a legacy manifest and intact checksums.
  matrix_name <- paste0("expmat_filt_", f$sample, ".qs2")
  matrix <- cache_load_data(matrix_name, dataset)
  matrix@x[[1]] <- matrix@x[[1]] + 1
  cache_save_data(matrix, matrix_name, dataset)
  current <- load_pipeline_state(dataset)
  stale <- transition_pipeline_step(current, "clustering", "stale", f$sample,
    reason = reason, details = list(stale_after = "cache_validation"))
  stale <- mark_pipeline_steps_stale(stale, "clustering", f$sample, reason = reason)
  save_pipeline_state_atomic(stale, dataset)
  # Remove the previously established proof to force independent replay again.
  manifest <- load_cache_manifest(dataset)
  for (name in names(manifest$artifacts)) manifest$artifacts[[name]]$verified_legacy_values <- NULL
  yaml::write_yaml(manifest, cache_manifest_paths(dataset)$primary, precision = 17)
  expect_error(recover_dataset_cache_location(dataset, f$paths, f$config, f$selected,
    dry_run = FALSE), "Replayed filtering differs")
})

test_that("base CNA recovery checks legacy coordinates and preserves reference validation", {
  skip_if_not_installed("qs2")
  dataset <- withr::local_tempdir()
  f <- make_location_state_fixture(dataset, n_genes = 30)
  sample <- f$sample
  filename <- paste0("cells_filt_clust_res_0.5_", sample, ".qs2")
  cells <- cache_load_data(filename, dataset)
  cells$cell_type <- rep(c("Reference", "Candidate"), each = nrow(cells) / 2)
  raw <- data.table::fread(f$paths$cell_file_paths)
  raw[, cell_type := as.character(cell_type)]
  raw[cells, on = "cell_name", cell_type := i.cell_type]
  data.table::fwrite(raw, f$paths$cell_file_paths)
  cache_save_data(cells, filename, dataset)
  f$selected$cna_ref_cells <- stats::setNames(list("Reference"), sample)
  f$selected$cna_pot_mal_cells <- stats::setNames(list("Candidate"), sample)
  expmat <- cache_load_data(paste0("expmat_filt_", sample, ".qs2"), dataset)
  positions <- data.table::data.table(symbol = rownames(expmat), chromosome_name = "01",
    start_position = seq_len(nrow(expmat)))
  references <- cells[cell_type == "Reference"]
  deps <- cna_matrix_cache_dependencies(sample, dataset, positions, references)
  matrix_name <- paste0("cna_matrix_", sample, ".qs2")
  cna <- data.table::data.table(gene = positions$symbol, chr = positions$chromosome_name,
    start_pos = positions$start_position)
  for (cell in colnames(expmat)) cna[[cell]] <- rep(0, nrow(cna))
  cache_save_data(cna, matrix_name, dataset, dependencies = deps)
  profile <- c(0L, 4L, 5L, 3L, 6L)
  values <- attr(deps, "cache_values")
  values$gene_positions <- data.table::copy(values$gene_positions)
  attr(values$gene_positions, "historical_index") <- "old bookkeeping"
  legacy <- .cache_scientific_dependencies(deps)
  legacy$values <- lapply(values, function(value) list(hash = .cache_legacy_hash(value, profile)))
  manifest <- load_cache_manifest(dataset)
  manifest$artifacts[[matrix_name]]$dependencies <- legacy
  manifest$artifacts[[matrix_name]]$dependency_fingerprint <- .cache_legacy_hash(legacy, profile)
  manifest$artifacts[[matrix_name]]$fingerprint_format <- NULL
  yaml::write_yaml(manifest, cache_manifest_paths(dataset)$primary, precision = 17)
  candidates <- cells[cell_type == "Candidate"]$cell_name
  tree_input <- diag(length(candidates))
  rownames(tree_input) <- candidates
  tree <- stats::hclust(stats::dist(tree_input))
  cache_save_data(tree, paste0("hclust_", sample, ".qs2"), dataset,
    dependencies = cna_hclust_cache_dependencies(sample, dataset, f$selected))
  completed <- transition_pipeline_step(f$state, "cna_configuration", "completed", sample,
    details = list(omitted_by_user = FALSE, reference_cell_types = "Reference",
      potentially_malignant_cell_types = "Candidate"), force = TRUE)
  completed <- transition_pipeline_step(completed, "cna_compute", "completed", sample,
    details = list(reference_cell_count = nrow(references), omitted_by_user = FALSE), force = TRUE)
  completed <- save_pipeline_state_atomic(completed, dataset)
  reason <- paste0("Clustering cache is missing, corrupt, or no longer matches its ",
    "standardized inputs and parameters. Rerun clustering.")
  stale <- transition_pipeline_step(completed, "clustering", "stale", sample,
    reason = reason, details = list(stale_after = "cache_validation"))
  stale <- mark_pipeline_steps_stale(stale, "clustering", sample, reason = reason)
  save_pipeline_state_atomic(stale, dataset)
  before <- unname(tools::md5sum(pipeline_state_paths(dataset)$primary))
  changed_positions <- data.table::copy(positions)
  changed_positions$start_position[[1]] <- 10000L
  expect_error(recover_dataset_cache_location(dataset, f$paths, f$config, f$selected,
    gene_positions = changed_positions, dry_run = FALSE), "coordinates or cell membership differ")
  expect_identical(unname(tools::md5sum(pipeline_state_paths(dataset)$primary)), before)
  result <- recover_dataset_cache_location(dataset, f$paths, f$config, f$selected,
    gene_positions = positions, dry_run = FALSE)
  expect_identical(result$coordinate_verified_samples, sample)
  expect_identical(load_pipeline_state(dataset)$samples, completed$samples)
  expect_true(cache_check_valid(matrix_name, dataset,
    dependencies = cna_matrix_cache_dependencies(sample, dataset, positions, references)))
  expect_false(cache_check_valid(matrix_name, dataset,
    dependencies = cna_matrix_cache_dependencies(sample, dataset, changed_positions, references)))
  expect_false(cache_check_valid(matrix_name, dataset,
    dependencies = cna_matrix_cache_dependencies(sample, dataset, positions, references[-1])))
})
