# ==================================================================================================
# Script: 08_utils_standardization.R
# Purpose: Reusable lifecycle helpers for dataset standardization scripts.
# ==================================================================================================


validate_standardization_settings <- function(settings) {
  #' Validate settings used by the general standardization workflow.
  #'
  #' @description Checks the application root, dataset name, expression scale,
  #'   and selected-configuration reset flag before any output is created.
  #'
  #' @param settings Named list containing `app_folder_path`, `dataset_name`,
  #'   `matrix_state`, and `reset_selected_config`.
  #'
  #' @return A normalized settings list. Raises an error for incomplete or
  #'   unsupported settings. This function does not write files.
  required_settings <- c(
    "app_folder_path",
    "dataset_name",
    "matrix_state",
    "reset_selected_config"
  )
  missing_settings <- setdiff(required_settings, names(settings))
  if (length(missing_settings) > 0L) {
    stop(
      "Missing standardization settings: ",
      paste(missing_settings, collapse = ", "),
      call. = FALSE
    )
  }

  scalar_text <- function(value, name) {
    if (
      length(value) != 1L || is.na(value) ||
        !nzchar(trimws(as.character(value)))
    ) {
      stop("Setting '", name, "' must be one non-empty value.", call. = FALSE)
    }
    trimws(as.character(value))
  }

  settings$app_folder_path <- scalar_text(
    settings$app_folder_path,
    "app_folder_path"
  )
  settings$dataset_name <- scalar_text(settings$dataset_name, "dataset_name")
  settings$matrix_state <- scalar_text(settings$matrix_state, "matrix_state")

  supported_states <- c("UMIcounts", "TPM", "CPM")
  if (!(settings$matrix_state %in% supported_states)) {
    stop(
      "matrix_state must be one of: ",
      paste(supported_states, collapse = ", "),
      call. = FALSE
    )
  }
  if (length(settings$reset_selected_config) != 1L) {
    stop("reset_selected_config must be TRUE or FALSE.", call. = FALSE)
  }
  settings$reset_selected_config <- isTRUE(settings$reset_selected_config)
  settings$app_folder_path <- normalizePath(
    settings$app_folder_path,
    winslash = "/",
    mustWork = TRUE
  )
  settings
}


map_standardization_sample_ids <- function(raw_ids, mapping, strict = TRUE) {
  #' Map raw sample identifiers to canonical configured identifiers.
  #'
  #' @description Applies an explicit named mapping without changing the order
  #'   or length of the input. This is intended for dataset-specific code in
  #'   `standardize.R`.
  #'
  #' @param raw_ids Character vector of identifiers found in the raw data.
  #' @param mapping Named character vector. Names are raw identifiers and values
  #'   are canonical identifiers from `samples_config.yaml`.
  #' @param strict If `TRUE`, stop when a raw identifier has no mapping. If
  #'   `FALSE`, leave unmapped identifiers unchanged.
  #'
  #' @return Character vector aligned to `raw_ids`. This function does not write
  #'   files.
  raw_ids <- as.character(raw_ids)
  if (is.null(names(mapping)) || any(!nzchar(names(mapping)))) {
    stop("mapping must be a named character vector.", call. = FALSE)
  }
  mapping_names <- names(mapping)
  mapping <- as.character(mapping)
  names(mapping) <- mapping_names
  duplicate_raw_ids <- unique(names(mapping)[duplicated(names(mapping))])
  if (length(duplicate_raw_ids) > 0L) {
    stop(
      "mapping contains duplicate raw identifiers: ",
      paste(duplicate_raw_ids, collapse = ", "),
      call. = FALSE
    )
  }

  matched <- unname(mapping[match(raw_ids, names(mapping))])
  missing <- is.na(matched)
  if (isTRUE(strict) && any(missing)) {
    stop(
      "No canonical mapping was supplied for raw sample identifier(s): ",
      paste(unique(raw_ids[missing]), collapse = ", "),
      call. = FALSE
    )
  }
  matched[missing] <- raw_ids[missing]
  matched
}


validate_standardization_sample_mapping <- function(
  detected_samples,
  configured_samples
) {
  #' Check that detected and configured sample identifiers agree exactly.
  #'
  #' @param detected_samples Canonical identifiers produced by dataset code.
  #' @param configured_samples Identifiers from `samples_config.yaml`.
  #'
  #' @return `TRUE`, invisibly. Raises an error listing missing and unexpected
  #'   identifiers when the sets differ. This function does not write files.
  detected_samples <- unique(trimws(as.character(detected_samples)))
  configured_samples <- unique(trimws(as.character(configured_samples)))
  if (!setequal(detected_samples, configured_samples)) {
    stop(
      "Detected samples do not match samples_config.yaml. Missing: ",
      paste(setdiff(configured_samples, detected_samples), collapse = ", "),
      "; unexpected: ",
      paste(setdiff(detected_samples, configured_samples), collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}


.standardization_sample_config_value <- function(sample_meta, field) {
  value <- sample_meta[[field]]
  if (is.null(value) || length(value) == 0L || is.na(value[[1]])) {
    return(NA_character_)
  }
  as.character(value[[1]])
}


.reset_standardization_working_dir <- function(working_dir_path, final_dir_path) {
  parent_path <- normalizePath(dirname(final_dir_path), winslash = "/", mustWork = TRUE)
  resolved_working_parent <- normalizePath(
    dirname(working_dir_path),
    winslash = "/",
    mustWork = TRUE
  )
  expected_name <- paste0(basename(final_dir_path), "_staging")
  if (
    !identical(parent_path, resolved_working_parent) ||
      !identical(basename(working_dir_path), expected_name)
  ) {
    stop("Refusing to reset an unsafe standardization staging path.", call. = FALSE)
  }
  if (dir.exists(working_dir_path)) {
    unlink(working_dir_path, recursive = TRUE, force = TRUE)
  }
  if (!dir.create(working_dir_path, recursive = TRUE, showWarnings = FALSE)) {
    stop("Could not create standardization staging directory: ", working_dir_path, call. = FALSE)
  }
}


initialize_standardization <- function(settings) {
  #' Initialize and prevalidate a standardization run.
  #'
  #' @description Loads project and dataset configuration, validates
  #'   `samples_config.yaml`, determines standardized filenames, and creates an
  #'   isolated staging directory. Existing published output is left untouched.
  #'
  #' @param settings Settings accepted by `validate_standardization_settings()`.
  #'
  #' @return A mutable `standardization_context` environment containing paths,
  #'   configuration, sample metadata, filenames, and run bookkeeping.
  #'   The staging directory is recreated on every call.
  required_packages <- c("data.table", "docstring", "jsonlite", "Matrix", "yaml")
  missing_packages <- required_packages[
    !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing_packages) > 0L) {
    stop(
      "Install required packages before standardization: ",
      paste(missing_packages, collapse = ", "),
      call. = FALSE
    )
  }

  settings <- validate_standardization_settings(settings)
  app_folder_path <- settings$app_folder_path
  config <- yaml::read_yaml(file.path(app_folder_path, "general_config.yaml"))
  dataset_name <- sanitize_dataset_name(settings$dataset_name)
  dataset_dir_path <- file.path(
    app_folder_path,
    config$paths$datasets_dir,
    dataset_name
  )
  resources_dir_path <- file.path(app_folder_path, config$paths$resources_dir)
  raw_data_dir_path <- file.path(dataset_dir_path, config$dataset_paths$raw_dir)
  processed_dir_path <- file.path(
    dataset_dir_path,
    config$dataset_paths$processed_dir
  )
  dir.create(dirname(processed_dir_path), recursive = TRUE, showWarnings = FALSE)

  dataset_config_path <- file.path(dataset_dir_path, config$config_files$dataset)
  selected_config_path <- file.path(dataset_dir_path, config$config_files$selected)
  if (!file.exists(dataset_config_path)) {
    stop("Dataset configuration is missing: ", dataset_config_path, call. = FALSE)
  }

  dataset_config <- yaml::read_yaml(dataset_config_path)
  samples_config <- prevalidate_setup(dataset_dir_path, config)
  samples_info_dt <- data.table::rbindlist(
    samples_config$samples,
    fill = TRUE,
    use.names = TRUE
  )
  sample_names <- samples_info_dt$sample
  expression_filename <- paste0("Exp_data_", settings$matrix_state, ".mtx")
  std_names <- dataset_config$std_names
  std_names$expmat <- expression_filename

  working_dir_path <- paste0(processed_dir_path, "_staging")
  .reset_standardization_working_dir(working_dir_path, processed_dir_path)

  context <- new.env(parent = emptyenv())
  class(context) <- "standardization_context"
  context$settings <- settings
  context$app_folder_path <- app_folder_path
  context$dataset_name <- dataset_name
  context$config <- config
  context$dataset_dir_path <- dataset_dir_path
  context$resources_dir_path <- resources_dir_path
  context$raw_data_dir_path <- raw_data_dir_path
  context$processed_dir_path <- processed_dir_path
  context$working_dir_path <- working_dir_path
  context$dataset_config_path <- dataset_config_path
  context$selected_config_path <- selected_config_path
  context$dataset_config <- dataset_config
  context$samples_config <- samples_config
  context$samples_info_dt <- samples_info_dt
  context$sample_names <- sample_names
  context$std_names <- std_names
  context$sample_cell_counts <- stats::setNames(integer(length(sample_names)), sample_names)
  context$dataset_cell_names <- character()
  context$registered_samples <- character()
  context
}


prepare_standardized_sample <- function(
  sample_input,
  sample_name,
  sample_meta,
  matrix_state
) {
  #' Validate and transform one sample into the standardized in-memory format.
  #'
  #' @description Checks matrix dimensions and values, removes blank or
  #'   unmapped genes with their rows, sums duplicate gene-symbol rows, aligns
  #'   optional cell metadata by `cell_name`, creates required cell columns,
  #'   and calculates per-cell complexity. It does not write files.
  #'
  #' @param sample_input List containing `expmat` (genes by cells), `genes`,
  #'   `cells`, and optionally `cell_metadata` keyed by `cell_name`.
  #' @param sample_name Canonical sample identifier.
  #' @param sample_meta One sample entry from `samples_config.yaml`.
  #' @param matrix_state One of `UMIcounts`, `TPM`, or `CPM`.
  #'
  #' @return List containing a column-compressed sparse matrix, unique gene
  #'   symbols, and aligned standardized cell metadata.
  if (!is.list(sample_input)) {
    stop("Sample '", sample_name, "': sample_input must be a list.", call. = FALSE)
  }
  required_items <- c("expmat", "genes", "cells")
  missing_items <- setdiff(required_items, names(sample_input))
  if (length(missing_items) > 0L) {
    stop(
      "Sample '", sample_name, "': sample_input is missing: ",
      paste(missing_items, collapse = ", "),
      call. = FALSE
    )
  }

  expmat <- sample_input$expmat
  if (!inherits(expmat, "Matrix")) {
    expmat <- Matrix::Matrix(expmat, sparse = TRUE)
  }
  if (!inherits(expmat, "CsparseMatrix")) {
    expmat <- methods::as(expmat, "CsparseMatrix")
  }
  genes <- trimws(as.character(sample_input$genes))
  cell_names <- trimws(as.character(sample_input$cells))

  if (length(genes) != nrow(expmat)) {
    stop(
      "Sample '", sample_name, "': genes length (", length(genes),
      ") does not match matrix rows (", nrow(expmat), ").",
      call. = FALSE
    )
  }
  if (length(cell_names) != ncol(expmat)) {
    stop(
      "Sample '", sample_name, "': cells length (", length(cell_names),
      ") does not match matrix columns (", ncol(expmat), ").",
      call. = FALSE
    )
  }
  if (any(is.na(cell_names) | !nzchar(cell_names))) {
    stop("Sample '", sample_name, "': cell identifiers contain blanks.", call. = FALSE)
  }
  if (anyDuplicated(cell_names)) {
    stop("Sample '", sample_name, "': cell identifiers are duplicated.", call. = FALSE)
  }

  matrix_values <- expmat@x
  if (any(!is.finite(matrix_values))) {
    stop("Sample '", sample_name, "': matrix contains non-finite values.", call. = FALSE)
  }
  if (any(matrix_values < 0)) {
    stop("Sample '", sample_name, "': matrix contains negative values.", call. = FALSE)
  }
  if (
    identical(matrix_state, "UMIcounts") &&
      any(abs(matrix_values - round(matrix_values)) > sqrt(.Machine$double.eps))
  ) {
    stop("Sample '", sample_name, "': UMI counts must be integers.", call. = FALSE)
  }

  valid_genes <- !is.na(genes) & nzchar(genes)
  if (!all(valid_genes)) {
    message(
      "Sample '", sample_name, "': removing ", sum(!valid_genes),
      " row(s) without a mapped gene symbol."
    )
    expmat <- expmat[valid_genes, , drop = FALSE]
    genes <- genes[valid_genes]
  }
  if (length(genes) == 0L) {
    stop("Sample '", sample_name, "': no valid genes remain.", call. = FALSE)
  }

  rownames(expmat) <- genes
  colnames(expmat) <- cell_names
  if (anyDuplicated(genes)) {
    message("Sample '", sample_name, "': summing duplicate gene-symbol rows.")
    expmat <- sum_dup_rows_sparse(expmat)
    genes <- rownames(expmat)
  }

  cells <- build_cells(cell_names)
  supplied_metadata <- sample_input$cell_metadata
  if (!is.null(supplied_metadata)) {
    supplied_metadata <- data.table::as.data.table(supplied_metadata)
    if (!("cell_name" %in% names(supplied_metadata))) {
      stop(
        "Sample '", sample_name, "': cell_metadata must contain cell_name.",
        call. = FALSE
      )
    }
    data.table::set(
      supplied_metadata,
      j = "cell_name",
      value = trimws(as.character(supplied_metadata$cell_name))
    )
    if (anyDuplicated(supplied_metadata$cell_name)) {
      stop(
        "Sample '", sample_name,
        "': cell_metadata contains duplicate cell_name values.",
        call. = FALSE
      )
    }
    if (!setequal(cell_names, supplied_metadata$cell_name)) {
      stop(
        "Sample '", sample_name,
        "': cell_metadata identifiers do not match matrix cells.",
        call. = FALSE
      )
    }
    metadata_order <- match(cell_names, supplied_metadata$cell_name)
    reserved_columns <- c("cell_name", "sample", "patient", "source", "complexity")
    copied_columns <- setdiff(names(supplied_metadata), reserved_columns)
    for (column in copied_columns) {
      cells[[column]] <- supplied_metadata[[column]][metadata_order]
    }
  }

  data.table::set(cells, j = "sample", value = sample_name)
  data.table::set(
    cells,
    j = "patient",
    value = .standardization_sample_config_value(sample_meta, "patient")
  )
  data.table::set(
    cells,
    j = "source",
    value = .standardization_sample_config_value(sample_meta, "site")
  )
  data.table::set(
    cells,
    j = "complexity",
    value = as.numeric(Matrix::colSums(expmat != 0))
  )
  list(expmat = expmat, genes = genes, cells = cells)
}


write_standardized_sample <- function(
  standardized_sample,
  sample_name,
  output_dir_path,
  std_names
) {
  #' Write one prepared sample using the standardized file layout.
  #'
  #' @param standardized_sample Result from `prepare_standardized_sample()`.
  #' @param sample_name Canonical sample identifier and directory name.
  #' @param output_dir_path Parent output or staging directory.
  #' @param std_names Configured standardized filenames.
  #'
  #' @return The sample directory path, invisibly. Writes the expression matrix,
  #'   gene list, and cell table.
  sample_dir_path <- file.path(output_dir_path, sample_name)
  dir.create(sample_dir_path, recursive = TRUE, showWarnings = FALSE)
  invisible(Matrix::writeMM(
    standardized_sample$expmat,
    file.path(sample_dir_path, std_names$expmat)
  ))
  writeLines(
    standardized_sample$genes,
    file.path(sample_dir_path, std_names$genes),
    useBytes = TRUE
  )
  data.table::fwrite(
    standardized_sample$cells,
    file.path(sample_dir_path, std_names$cells)
  )
  invisible(sample_dir_path)
}


register_standardized_sample <- function(context, sample_name, standardized_sample) {
  #' Check dataset-wide identifiers, stage one sample, and record its cell count.
  #'
  #' @description Ensures the sample is configured and registered once, rejects
  #'   cell identifiers reused by another sample, writes the sample to the
  #'   staging directory, and records its cell count for `Samples.csv`.
  #'
  #' @param context Context returned by `initialize_standardization()`.
  #' @param sample_name Canonical configured sample identifier.
  #' @param standardized_sample Result from `prepare_standardized_sample()`.
  #'
  #' @return The context, invisibly. Mutates run bookkeeping and writes staged
  #'   sample files; published output is not changed.
  if (!(sample_name %in% context$sample_names)) {
    stop("Cannot register unconfigured sample '", sample_name, "'.", call. = FALSE)
  }
  if (sample_name %in% context$registered_samples) {
    stop("Sample '", sample_name, "' was registered more than once.", call. = FALSE)
  }
  repeated_cells <- intersect(
    context$dataset_cell_names,
    standardized_sample$cells$cell_name
  )
  if (length(repeated_cells) > 0L) {
    stop(
      "Sample '", sample_name,
      "' reuses dataset cell identifiers (for example: ",
      paste(utils::head(repeated_cells, 5), collapse = ", "),
      ").",
      call. = FALSE
    )
  }

  write_standardized_sample(
    standardized_sample = standardized_sample,
    sample_name = sample_name,
    output_dir_path = context$working_dir_path,
    std_names = context$std_names
  )
  context$dataset_cell_names <- c(
    context$dataset_cell_names,
    standardized_sample$cells$cell_name
  )
  context$sample_cell_counts[[sample_name]] <- nrow(standardized_sample$cells)
  context$registered_samples <- c(context$registered_samples, sample_name)
  invisible(context)
}


write_standardized_samples_table <- function(context) {
  #' Create the staged dataset-wide `Samples.csv` table.
  #'
  #' @description Requires every configured sample to have been registered,
  #'   copies sample metadata from `samples_config.yaml`, and inserts calculated
  #'   cell counts.
  #'
  #' @param context Context returned by `initialize_standardization()`.
  #'
  #' @return The completed sample table, invisibly. Writes only to staging.
  missing_samples <- setdiff(context$sample_names, context$registered_samples)
  unexpected_samples <- setdiff(context$registered_samples, context$sample_names)
  if (length(missing_samples) > 0L || length(unexpected_samples) > 0L) {
    stop(
      "Registered samples do not match samples_config.yaml",
      if (length(missing_samples) > 0L) {
        paste0("; missing: ", paste(missing_samples, collapse = ", "))
      } else "",
      if (length(unexpected_samples) > 0L) {
        paste0("; unexpected: ", paste(unexpected_samples, collapse = ", "))
      } else "",
      call. = FALSE
    )
  }

  samples <- build_samples(context$sample_names)
  metadata_columns <- setdiff(names(context$samples_info_dt), c("sample", "n_cells"))
  metadata_order <- match(samples$sample, context$samples_info_dt$sample)
  for (column in metadata_columns) {
    data.table::set(
      samples,
      j = column,
      value = context$samples_info_dt[[column]][metadata_order]
    )
  }
  data.table::set(
    samples,
    j = "n_cells",
    value = as.integer(context$sample_cell_counts[samples$sample])
  )
  data.table::fwrite(
    samples,
    file.path(context$working_dir_path, context$std_names$samples)
  )
  invisible(samples)
}


.publish_staged_standardization <- function(context) {
  final_dir <- context$processed_dir_path
  staging_dir <- context$working_dir_path
  backup_dir <- paste0(final_dir, "_previous")
  if (!dir.exists(staging_dir)) {
    stop("Standardization staging directory is missing: ", staging_dir, call. = FALSE)
  }
  if (dir.exists(backup_dir)) {
    if (!dir.exists(final_dir)) {
      if (!file.rename(backup_dir, final_dir)) {
        stop(
          "A previous output backup could not be restored: ",
          backup_dir,
          call. = FALSE
        )
      }
    } else {
      unlink(backup_dir, recursive = TRUE, force = TRUE)
    }
  }

  had_previous <- dir.exists(final_dir)
  if (had_previous && !file.rename(final_dir, backup_dir)) {
    stop("Could not move the previous standardized output aside.", call. = FALSE)
  }
  published <- file.rename(staging_dir, final_dir)
  if (!published) {
    if (had_previous) file.rename(backup_dir, final_dir)
    stop("Could not publish the validated standardized output.", call. = FALSE)
  }
  if (had_previous && dir.exists(backup_dir)) {
    unlink(backup_dir, recursive = TRUE, force = TRUE)
  }
  invisible(final_dir)
}


publish_standardization <- function(context, validation) {
  #' Publish validated staged output and record standardization completion.
  #'
  #' @description Requires a successful strict validation result, atomically
  #'   replaces the published processed-data directory where supported, updates
  #'   dataset and selected configuration, records the pipeline event, and marks
  #'   the standardization state completed. Existing selected choices are
  #'   preserved unless `reset_selected_config` is `TRUE`.
  #'
  #' @param context Context returned by `initialize_standardization()`.
  #' @param validation Successful result from `validate_standardization()` run
  #'   against `context$working_dir_path`.
  #'
  #' @return The validation result, invisibly. Writes published output,
  #'   configuration, logs, and pipeline state.
  if (is.null(validation$valid) || !isTRUE(validation$valid)) {
    stop("Refusing to publish output that did not pass strict validation.", call. = FALSE)
  }

  .publish_staged_standardization(context)
  context$dataset_config$std_names$expmat <- context$std_names$expmat
  yaml::write_yaml(context$dataset_config, context$dataset_config_path)
  if (
    isTRUE(context$settings$reset_selected_config) ||
      !file.exists(context$selected_config_path)
  ) {
    yaml::write_yaml(
      setup_selected_config(context$sample_names),
      context$selected_config_path
    )
  } else {
    message("Preserving existing selected_config.yaml.")
  }

  record_pipeline_event(
    dataset_dir_path = context$dataset_dir_path,
    dataset = context$dataset_name,
    stage = "standardization",
    event_type = "standardization_validated",
    outcome = "completed",
    parameters = list(
      sample_count = length(context$sample_names),
      expression_type = validation$expression_type,
      matrix_state = context$settings$matrix_state
    )
  )

  state_filename <- .pipeline_value_or(
    context$config$config_files$state,
    "pipeline_state.yaml"
  )
  pipeline_state <- tryCatch({
    current_state <- load_or_initialize_pipeline_state(
      dataset_dir_path = context$dataset_dir_path,
      dataset_id = context$dataset_name,
      sample_names = context$sample_names,
      dataset_config = context$dataset_config,
      selected_config = yaml::read_yaml(context$selected_config_path),
      config = context$config,
      state_filename = state_filename,
      infer_legacy = FALSE
    )
    previous_standardization <- get_pipeline_step(
      current_state,
      "standardization"
    )$status
    if (identical(previous_standardization, "completed")) {
      current_state <- mark_pipeline_steps_stale(
        current_state,
        upstream_step = "standardization",
        reason = "Standardized inputs were regenerated."
      )
    }
    current_state <- transition_pipeline_step(
      current_state,
      step = "standardization",
      status = "in_progress"
    )
    current_state <- transition_pipeline_step(
      current_state,
      step = "standardization",
      status = "completed",
      details = list(
        sample_count = length(context$sample_names),
        expression_type = validation$expression_type,
        matrix_state = context$settings$matrix_state
      )
    )
    save_pipeline_state_atomic(
      current_state,
      dataset_dir_path = context$dataset_dir_path,
      state_filename = state_filename
    )
  }, error = identity)
  if (inherits(pipeline_state, "error")) {
    record_pipeline_event(
      dataset_dir_path = context$dataset_dir_path,
      dataset = context$dataset_name,
      stage = "state",
      event_type = "pipeline_state_update",
      outcome = "failed",
      reason = conditionMessage(pipeline_state)
    )
    stop(
      "Standardization was published, but pipeline state could not be persisted: ",
      conditionMessage(pipeline_state),
      call. = FALSE
    )
  }

  message(
    "Standardization complete for ", length(context$sample_names),
    " sample(s). Expression type: ", validation$expression_type, "."
  )
  invisible(validation)
}
