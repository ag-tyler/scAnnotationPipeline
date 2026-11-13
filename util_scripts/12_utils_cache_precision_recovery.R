# Explicit recovery of metadata defects (precision or relocation). This is not
# called during normal loading: stale work must never be silently promoted.
.recover_dataset_cache_metadata <- function(
  dataset_dir_path, paths_list, dataset_config, selected_config,
  dry_run = TRUE, state_filename = "pipeline_state.yaml",
  .location = FALSE, gene_positions = NULL
) {
  state_paths <- pipeline_state_paths(dataset_dir_path, state_filename)
  current <- yaml::read_yaml(state_paths$primary)
  previous <- yaml::read_yaml(state_paths$backup)
  validate_pipeline_state(current)
  validate_pipeline_state(previous)
  if (!identical(current$dataset_id, previous$dataset_id) ||
      !setequal(names(current$samples), names(previous$samples)) ||
      previous$revision >= current$revision) {
    stop("State backup does not match the current dataset and revision.", call. = FALSE)
  }
  if (.location && !identical(current$dataset_steps, previous$dataset_steps)) {
    stop("Dataset prerequisites changed since the state backup.", call. = FALSE)
  }
  storage <- if (file.exists(file.path(dataset_dir_path, "storage_state.yaml"))) {
    load_dataset_storage_state(dataset_dir_path, recover = FALSE)
  } else NULL
  if (!is.null(storage) && dataset_storage_cache_is_retired(storage)) {
    stop("Cannot recover cache state for retired storage.", call. = FALSE)
  }
  plan <- if (.location) .cache_manifest_location_plan(dataset_dir_path) else .cache_manifest_precision_plan(dataset_dir_path)
  if (any(plan$report$action == "blocked")) {
    stop("Cache recovery is blocked; inspect the manifest repair dry-run first.", call. = FALSE)
  }
  proposed <- current
  restored <- character()
  replayed <- character()
  verified_cna <- character()
  expected_reason <- paste0(
    "Clustering cache is missing, corrupt, or no longer matches its standardized ",
    "inputs and parameters. Rerun clustering."
  )
  validate_artifact <- function(filename, dependencies) {
    record <- plan$manifest$artifacts[[filename]]
    path <- file.path(dataset_dir_path, "cache", filename)
    if (is.null(dependencies) || !.cache_record_matches(record, path, dependencies)) {
      stop("Current scientific inputs do not validate cache: ", filename, ".", call. = FALSE)
    }
    object <- qs2::qs_read(path)
    validate_cache_object(object, record$artifact_type, filename)
    object
  }
  normalize_labels <- function(labels) {
    labels <- as.character(labels)
    labels[!is.na(labels) & labels == ""] <- NA_character_
    labels
  }
  for (index in seq_along(paths_list$sample_dir_paths)) {
    sample_name <- basename(paths_list$sample_dir_paths[[index]])
    clustering <- get_pipeline_step(current, "clustering", sample_name)
    recovering <- identical(clustering$status, "stale") &&
      identical(clustering$reason, expected_reason) &&
      identical(clustering$details$stale_after, "cache_validation")
    migrating <- .location && identical(clustering$status, "completed")
    if (!recovering && !migrating) next
    evidence <- if (recovering) previous else current
    if (!identical(get_pipeline_step(evidence, "clustering", sample_name)$status, "completed")) {
      stop("No completed clustering snapshot exists for ", sample_name, ".", call. = FALSE)
    }
    selected_resolution <- selected_config$resolutions[[sample_name]]
    downstream_completed <- any(vapply(c("resolution", "differential_expression", "annotation", "cna_configuration"),
      function(step) get_pipeline_step(evidence, step, sample_name)$status %in% c("completed", "skipped"), logical(1)))
    if ((is.null(selected_resolution) && (recovering || downstream_completed)) || length(dataset_config$params$resolutions) == 0L) {
      stop("Missing resolution decisions for ", sample_name, ".", call. = FALSE)
    }
    filter_filename <- paste0("expmat_filt_", sample_name, ".qs2")
    filter_dependencies <- filter_cache_dependencies(paths_list, index, dataset_config)
    filter_record <- plan$manifest$artifacts[[filter_filename]]
    if (.location && is.null(filter_record$fingerprint_format) &&
        !.cache_dependency_matches(filter_record, filter_dependencies)) {
      # Old compressed RDS hashes can include representation details that can
      # no longer be reproduced. Prove the actual scientific result instead of
      # assuming such a mismatch is harmless. No PCA/UMAP or result writes run.
      plan <- .verify_legacy_clustering_inputs(plan, dataset_dir_path, paths_list,
        index, dataset_config, selected_resolution)
      replayed <- c(replayed, sample_name)
    }
    validate_artifact(filter_filename, filter_dependencies)
    selected_cells <- NULL
    for (resolution in unique(c(dataset_config$params$resolutions, selected_resolution))) {
      cells <- validate_artifact(
        paste0("cells_filt_clust_res_", resolution, "_", sample_name, ".qs2"),
        clustering_cache_dependencies(paths_list, index, dataset_config, resolution)
      )
      if (identical(as.numeric(resolution), as.numeric(selected_resolution))) selected_cells <- cells
    }
    if (!is.null(selected_resolution)) {
      raw_cells <- data.table::fread(paths_list$cell_file_paths[[index]])
      validate_annotation_cell_alignment(selected_cells, raw_cells)
      saved_labels <- raw_cells$cell_type[match(selected_cells$cell_name, raw_cells$cell_name)]
      if (!identical(normalize_labels(selected_cells$cell_type), normalize_labels(saved_labels))) {
        stop("Saved annotations disagree with the selected cache for ", sample_name, ".", call. = FALSE)
      }
    }
    for (step in c("clustering", "resolution", "differential_expression", "annotation", "cna_configuration",
      if (.location) "cna_compute")) {
      now <- get_pipeline_step(current, step, sample_name)
      before <- get_pipeline_step(evidence, step, sample_name)
      restoring <- identical(now$status, "stale") && identical(now$reason, expected_reason)
      if (!restoring && !(migrating && before$status %in% c("completed", "skipped"))) next
      if (!(before$status %in% c("completed", "skipped")) ||
          !identical(now$attempt, before$attempt) ||
          !identical(now$started_at, before$started_at) ||
          !identical(now$finished_at, before$finished_at)) {
        stop("Prior completion cannot be safely established: ", sample_name, "/", step, ".", call. = FALSE)
      }
      if (.location && restoring) {
        # Only the precise metadata-screen transition may be undone. Edits to
        # decisions, provenance, or other step details block recovery.
        expected <- before
        expected$status <- "stale"
        expected$reason <- expected_reason
        expected$updated_at <- now$updated_at
        expected$details$stale_after <- if (step == "clustering") "cache_validation" else "clustering"
        if (!identical(now, expected)) stop("Step changed since the state backup: ", sample_name, "/", step, ".", call. = FALSE)
      }
      if (step %in% c("resolution", "differential_expression", "annotation") &&
          !is.null(before$details$resolution) &&
          !identical(as.numeric(before$details$resolution), as.numeric(selected_resolution))) {
        stop("Resolution decision changed since the state backup.", call. = FALSE)
      }
      if (step == "cna_configuration") {
        if (before$status == "skipped" && !isTRUE(before$details$omitted_by_user)) {
          stop("Prior CNA omission was not explicit.", call. = FALSE)
        }
        if (before$status == "completed") {
          references <- selected_config$cna_ref_cells[[sample_name]]
          candidates <- selected_config$cna_pot_mal_cells[[sample_name]]
          if (!length(references) || !length(candidates) ||
              !setequal(references, before$details$reference_cell_types) ||
              !setequal(candidates, before$details$potentially_malignant_cell_types)) {
            stop("Saved CNA configuration differs from the prior state snapshot.", call. = FALSE)
          }
        }
      }
      if (.location && step == "cna_compute") {
        if (before$status == "skipped") {
          if (!isTRUE(before$details$omitted_by_user) || !pipeline_cna_is_omitted(proposed, sample_name)) {
            stop("Prior CNA omission was not explicit.", call. = FALSE)
          }
        } else {
          if (is.null(gene_positions)) stop("Gene positions are required to validate CNA recovery.", call. = FALSE)
          preflight <- cna_sample_preflight(sample_name, selected_config, dataset_dir_path,
            gene_positions = gene_positions, pipeline_state = proposed)
          if (!isTRUE(preflight$eligible)) stop("Current CNA inputs are not eligible for recovery.", call. = FALSE)
          filename <- paste0("cna_matrix_", sample_name, ".qs2")
          dependencies <- cna_matrix_cache_dependencies(sample_name, dataset_dir_path, gene_positions,
            preflight$ref_cells)
          if (is.null(plan$manifest$artifacts[[filename]]$fingerprint_format) &&
              !.cache_dependency_matches(plan$manifest$artifacts[[filename]], dependencies)) {
            plan <- .verify_legacy_cna_positions(plan, dataset_dir_path, filename,
              dependencies, preflight$expmat, gene_positions)
            verified_cna <- c(verified_cna, sample_name)
          }
          validate_artifact(filename, dependencies)
          validate_artifact(paste0("hclust_", sample_name, ".qs2"),
            cna_hclust_cache_dependencies(sample_name, dataset_dir_path, selected_config))
        }
      }
      if (restoring) {
        proposed$samples[[sample_name]][[step]] <- before
        restored <- c(restored, paste(sample_name, step, sep = "/"))
      }
    }
  }
  validate_pipeline_state(proposed)
  backup_dir <- NULL
  if (!isTRUE(dry_run) && (length(restored) || any(plan$report$action == "repair"))) {
    # Preserve both state generations before atomic writers rotate their usual
    # backups. A failed state write leaves conservative stale states, not false
    # completion; the original evidence remains available here for retry.
    backup_dir <- tempfile(if (.location) "cache-location-recovery-" else "cache-precision-recovery-", tmpdir = dataset_dir_path)
    dir.create(backup_dir)
    manifest_paths <- cache_manifest_paths(dataset_dir_path)
    originals <- c(state_paths$primary, state_paths$backup, manifest_paths$primary,
      if (file.exists(manifest_paths$backup)) manifest_paths$backup)
    if (!all(file.copy(originals, backup_dir))) stop("Could not preserve recovery evidence.", call. = FALSE)
    if (.location) {
      acquire_cache_manifest_lock(manifest_paths$lock)
      tryCatch({
        latest <- load_cache_manifest(dataset_dir_path, recover = FALSE)
        if (!identical(latest$revision, plan$manifest$revision)) {
          stop("Cache manifest changed during recovery; preview again.", call. = FALSE)
        }
        .save_cache_manifest_unlocked(plan$manifest, dataset_dir_path)
      }, finally = unlink(manifest_paths$lock, recursive = TRUE, force = TRUE))
    } else repair_cache_manifest_precision(dataset_dir_path, dry_run = FALSE)
    if (length(restored)) save_pipeline_state_at_path(proposed, state_paths$primary)
  }
  list(cache = plan$report, restored_steps = restored, replayed_samples = replayed,
    coordinate_verified_samples = verified_cna, backup_dir = backup_dir, dry_run = dry_run)
}


# This explicit migration accepts a legacy cell-input hash only after replaying
# deterministic filtering from checksum-verified sources and matching every
# clustered cache's input rows. Other parameters and dependency fingerprints
# must still validate with their original hash profile before anything is saved.
.verify_legacy_clustering_inputs <- function(plan, dataset_dir, paths, index, config, selected_resolution) {
  sample <- basename(paths$sample_dir_paths[[index]])
  expression_name <- paste0("expmat_filt_", sample, ".qs2")
  original <- plan$manifest$artifacts[[expression_name]]
  dependencies <- filter_cache_dependencies(paths, index, config)
  input <- attr(dependencies, "cache_values")$cells_input
  if (is.null(input) || is.null(original$dependencies$values$cells_input$hash)) {
    stop("Legacy clustering inputs cannot be independently verified.", call. = FALSE)
  }
  message("Verifying legacy clustering inputs by replaying filtering for ", sample, ".")
  computed <- load_filter_cells_expmat(paths$cell_file_paths[[index]],
    paths$expmat_file_paths[[index]], paths$genes_file_paths[[index]], config)
  saved <- cache_load_data(expression_name, dataset_dir, recover = FALSE)
  if (!isTRUE(all.equal(saved, computed$expmat_filt, tolerance = 0))) {
    stop("Replayed filtering differs from the saved expression cache: ", sample, ".", call. = FALSE)
  }
  proof <- list(method = "filtered-expression-replay-v1",
    canonical_hash = cache_hash_value(input),
    legacy_hash = original$dependencies$values$cells_input$hash,
    expression_checksum = original$checksum)
  filenames <- c(expression_name, paste0("cells_filt_clust_res_",
    unique(c(config$params$resolutions, selected_resolution)), "_", sample, ".qs2"))
  for (filename in filenames) {
    record <- plan$manifest$artifacts[[filename]]
    if (is.null(record) || !identical(record$dependencies$values$cells_input$hash, proof$legacy_hash)) {
      stop("Legacy clustering caches have different recorded inputs: ", filename, ".", call. = FALSE)
    }
    if (!identical(filename, expression_name)) {
      cells <- cache_load_data(filename, dataset_dir, recover = FALSE)
      for (column in c("cell_name", "sample", "complexity")) {
        if (!identical(as.character(cells[[column]]), as.character(computed$cells_filt[[column]]))) {
          stop("Replayed cell inputs differ from the saved clustering cache: ", filename, ".", call. = FALSE)
        }
      }
    }
    record$verified_legacy_values$cells_input <- proof
    plan$manifest$artifacts[[filename]] <- record
    plan$report$action[plan$report$artifact == filename] <- "repair"
  }
  plan
}


# The old gene-position hash also included data.table's session bookkeeping.
# Verify every coordinate actually used by compute_cna(), and its gene/cell
# selection, against the intact saved matrix. Reference identities, upstream
# checksums and implementation must still pass their original fingerprints.
.verify_legacy_cna_positions <- function(plan, dataset_dir, filename, dependencies, expmat, gene_positions) {
  means <- Matrix::rowMeans(expmat)
  means <- means[names(means) %in% gene_positions$symbol]
  genes <- utils::head(names(means)[order(-means)], 5000)
  positions <- data.table::copy(data.table::as.data.table(gene_positions))
  expected <- positions[genes, .(gene = symbol, chr = chromosome_name,
    start_pos = start_position), on = "symbol"]
  data.table::setorderv(expected, c("chr", "start_pos", "gene"))
  saved <- cache_load_data(filename, dataset_dir, recover = FALSE)
  if (nrow(expected) != nrow(saved) || anyDuplicated(expected$gene) ||
      !identical(as.character(expected$gene), as.character(saved$gene)) ||
      !identical(as.character(expected$chr), as.character(saved$chr)) ||
      !identical(as.numeric(expected$start_pos), as.numeric(saved$start_pos)) ||
      !setequal(setdiff(names(saved), c("gene", "chr", "start_pos")), colnames(expmat))) {
    stop("Current CNA coordinates or cell membership differ from the saved matrix: ", filename, ".", call. = FALSE)
  }
  record <- plan$manifest$artifacts[[filename]]
  record$verified_legacy_values$gene_positions <- list(method = "cna-coordinate-check-v1",
    canonical_hash = cache_hash_value(attr(dependencies, "cache_values")$gene_positions),
    legacy_hash = record$dependencies$values$gene_positions$hash,
    matrix_checksum = record$checksum)
  plan$manifest$artifacts[[filename]] <- record
  plan$report$action[plan$report$artifact == filename] <- "repair"
  plan
}


recover_dataset_cache_precision <- function(
  dataset_dir_path, paths_list, dataset_config, selected_config,
  dry_run = TRUE, state_filename = "pipeline_state.yaml"
) {
  .recover_dataset_cache_metadata(dataset_dir_path, paths_list, dataset_config,
    selected_config, dry_run, state_filename)
}


# Explicit recovery only: normal dataset loads never promote stale work.
# Later CNA decisions remain stale for review; this restores through base CNA.
recover_dataset_cache_location <- function(
  dataset_dir_path, paths_list, dataset_config, selected_config,
  gene_positions = NULL, dry_run = TRUE, state_filename = "pipeline_state.yaml"
) {
  .recover_dataset_cache_metadata(dataset_dir_path, paths_list, dataset_config,
    selected_config, dry_run, state_filename, .location = TRUE, gene_positions = gene_positions)
}
