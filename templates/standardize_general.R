# ==============================================================================
# General Data Standardization Template
# scAnnotationPipeline
# ==============================================================================
#
# PURPOSE
# -------
# Adapt this file when the raw dataset does not fit a fixed import recipe.
# Dataset-specific extraction, loading, sample mapping, and gene mapping belong
# in the two USER CODE functions below. The remaining workflow enforces the
# shared standardized-data contract and writes the app-ready outputs.
#
# This template intentionally does not replace standardize_10x.R or either
# Quarto template. Copy it into a dataset directory, edit the marked sections,
# and keep the completed copy with the dataset as its reproducible import script.
#
# STANDARD OUTPUT
# ---------------
# processed_data/
#   Samples.csv
#   <sample>/
#     Exp_data_<matrix_state>.mtx
#     Genes.txt
#     Cells.csv
#
# The canonical sample identifier is `sample`. The former `id` key is not
# supported. Matrix columns correspond by position to Cells.csv rows, and
# matrix rows correspond by position to Genes.txt entries.
#
# WORKFLOW
# --------
#   1. Edit USER SETTINGS.
#   2. Implement prepare_raw_data() and load_sample_input().
#   3. Complete samples_config.yaml.
#   4. Set RUN_STANDARDIZATION <- TRUE.
#   5. Run this entire file from a clean R session.
#   6. Correct every reported issue until strict postvalidation passes.
#
# ==============================================================================


# ==============================================================================
# 1. USER SETTINGS
# ==============================================================================

RUN_STANDARDIZATION <- FALSE

settings <- list(
  # Root of the scAnnotationPipeline checkout containing general_config.yaml.
  app_folder_path = "/path/to/scAnnotationPipeline",

  # Folder name under the configured datasets directory.
  dataset_name = "<dataset_name>",

  # Supported values: "UMIcounts", "TPM", or "CPM".
  # This must describe the values actually returned by load_sample_input().
  matrix_state = "UMIcounts",

  # Preserve existing clustering/CNA choices on a repeat standardization run.
  # Set TRUE only when those choices should intentionally be reset.
  reset_selected_config = FALSE
)


# ==============================================================================
# 2. USER CODE: RAW-DATA PREPARATION
# ==============================================================================

prepare_raw_data <- function(
  raw_data_dir_path,
  resources_dir_path,
  sample_names,
  samples_info_dt,
  config,
  dataset_config
) {
  # USER INPUT REQUIRED
  #
  # Perform work shared by all samples here. Examples:
  #   - extract an archive when necessary;
  #   - discover input files and construct a sample-to-file map;
  #   - load a combined matrix once;
  #   - load a raw cell-metadata table;
  #   - load a gene-ID mapping resource.
  #
  # Return any object that load_sample_input() needs. It may be a list of file
  # paths, an in-memory combined object, or NULL when no shared setup is needed.
  # Do not write standardized outputs in this function.

  stop(
    "USER INPUT REQUIRED: implement prepare_raw_data() in standardize_general.R.",
    call. = FALSE
  )
}


# ==============================================================================
# 3. USER CODE: LOAD AND SPLIT ONE SAMPLE
# ==============================================================================

load_sample_input <- function(
  sample_name,
  raw_context,
  raw_data_dir_path,
  resources_dir_path,
  samples_info_dt,
  config,
  dataset_config
) {
  # USER INPUT REQUIRED
  #
  # Load and isolate exactly one canonical sample. Map raw sample identifiers to
  # sample_name here. Return a list with this exact core contract:
  #
  #   list(
  #     expmat = <genes x cells numeric matrix>,
  #     genes = <character vector aligned to matrix rows>,
  #     cells = <character vector aligned to matrix columns>,
  #     cell_metadata = <optional data.frame/data.table keyed by cell_name>
  #   )
  #
  # Requirements:
  #   - genes contains final gene symbols, preferably current HGNC symbols;
  #   - cells contains final dataset-wide unique cell identifiers;
  #   - cell_metadata, when supplied, has one unique cell_name row per cell;
  #   - expmat values match settings$matrix_state and are not log-transformed;
  #   - do not remove/reorder genes or cells without applying the same operation
  #     to the matrix and its corresponding identifier vector.
  #
  # The shared code below removes blank/unmapped genes with their matrix rows,
  # sums rows with duplicate gene symbols, constructs the required Cells schema,
  # fills sample/patient/source from samples_config.yaml, computes complexity,
  # and verifies all remaining invariants.

  stop(
    paste0(
      "USER INPUT REQUIRED: implement load_sample_input() for sample '",
      sample_name,
      "'."
    ),
    call. = FALSE
  )
}


# ==============================================================================
# 4. SHARED HELPERS -- CHANGE ONLY IF THE STANDARD CONTRACT CHANGES
# ==============================================================================

validate_general_settings <- function(settings) {
  required_settings <- c(
    "app_folder_path",
    "dataset_name",
    "matrix_state",
    "reset_selected_config"
  )
  missing_settings <- setdiff(required_settings, names(settings))
  if (length(missing_settings) > 0) {
    stop(
      "Missing template settings: ",
      paste(missing_settings, collapse = ", "),
      call. = FALSE
    )
  }

  scalar_text <- function(value, name) {
    if (
      length(value) != 1 || is.na(value) ||
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

  if (
    identical(settings$app_folder_path, "/path/to/scAnnotationPipeline") ||
      identical(settings$dataset_name, "<dataset_name>")
  ) {
    stop("Complete USER SETTINGS before running standardization.", call. = FALSE)
  }

  supported_states <- c("UMIcounts", "TPM", "CPM")
  if (!(settings$matrix_state %in% supported_states)) {
    stop(
      "matrix_state must be one of: ",
      paste(supported_states, collapse = ", "),
      call. = FALSE
    )
  }

  if (length(settings$reset_selected_config) != 1) {
    stop("reset_selected_config must be TRUE or FALSE.", call. = FALSE)
  }
  settings$reset_selected_config <- isTRUE(settings$reset_selected_config)
  settings
}


sample_config_value <- function(sample_meta, field) {
  value <- sample_meta[[field]]
  if (is.null(value) || length(value) == 0 || is.na(value[[1]])) {
    return(NA_character_)
  }
  as.character(value[[1]])
}


prepare_standardized_sample <- function(
  sample_input,
  sample_name,
  sample_meta,
  matrix_state
) {
  if (!is.list(sample_input)) {
    stop("Sample '", sample_name, "': loader must return a list.", call. = FALSE)
  }

  required_items <- c("expmat", "genes", "cells")
  missing_items <- setdiff(required_items, names(sample_input))
  if (length(missing_items) > 0) {
    stop(
      "Sample '", sample_name, "': loader result is missing: ",
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
  if (length(genes) == 0) {
    stop("Sample '", sample_name, "': no valid genes remain.", call. = FALSE)
  }

  rownames(expmat) <- genes
  colnames(expmat) <- cell_names
  if (anyDuplicated(genes)) {
    message(
      "Sample '", sample_name,
      "': summing matrix rows with duplicate gene symbols."
    )
    expmat <- sum_dup_rows_sparse(expmat)
    genes <- rownames(expmat)
  }

  cells <- build_cells(cell_names)
  supplied_metadata <- sample_input$cell_metadata
  if (!is.null(supplied_metadata)) {
    supplied_metadata <- data.table::as.data.table(supplied_metadata)
    if (!("cell_name" %in% names(supplied_metadata))) {
      stop(
        "Sample '", sample_name,
        "': cell_metadata must contain cell_name.",
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
    reserved_columns <- c(
      "cell_name", "sample", "patient", "source", "complexity"
    )
    copied_columns <- setdiff(names(supplied_metadata), reserved_columns)
    for (column in copied_columns) {
      cells[[column]] <- supplied_metadata[[column]][metadata_order]
    }
  }

  data.table::set(cells, j = "sample", value = sample_name)
  data.table::set(
    cells,
    j = "patient",
    value = sample_config_value(sample_meta, "patient")
  )
  data.table::set(
    cells,
    j = "source",
    value = sample_config_value(sample_meta, "site")
  )
  data.table::set(
    cells,
    j = "complexity",
    value = as.numeric(Matrix::colSums(expmat != 0))
  )

  list(
    expmat = expmat,
    genes = genes,
    cells = cells
  )
}


write_standardized_sample <- function(
  standardized_sample,
  sample_name,
  processed_dir_path,
  std_names
) {
  sample_dir_path <- file.path(processed_dir_path, sample_name)
  dir.create(sample_dir_path, recursive = TRUE, showWarnings = FALSE)

  invisible(
    Matrix::writeMM(
      standardized_sample$expmat,
      file.path(sample_dir_path, std_names$expmat)
    )
  )
  writeLines(
    standardized_sample$genes,
    file.path(sample_dir_path, std_names$genes),
    useBytes = TRUE
  )
  data.table::fwrite(
    standardized_sample$cells,
    file.path(sample_dir_path, std_names$cells)
  )
}


# ==============================================================================
# 5. SHARED PIPELINE
# ==============================================================================

run_general_standardization <- function(settings) {
  settings <- validate_general_settings(settings)

  required_packages <- c("data.table", "docstring", "jsonlite", "Matrix", "yaml")
  missing_packages <- required_packages[
    !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
  ]
  if (length(missing_packages) > 0) {
    stop(
      "Install required packages before standardization: ",
      paste(missing_packages, collapse = ", "),
      call. = FALSE
    )
  }

  app_folder_path <- normalizePath(
    settings$app_folder_path,
    winslash = "/",
    mustWork = TRUE
  )
  utils_paths <- file.path(
    app_folder_path,
    "util_scripts",
    c("03_utils_misc.R", "06_utils_logging.R", "07_utils_state.R")
  )
  missing_utils <- utils_paths[!file.exists(utils_paths)]
  if (length(missing_utils) > 0L) {
    stop(
      "Standardization utilities are missing: ",
      paste(missing_utils, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(lapply(
    utils_paths,
    source,
    local = environment(prepare_standardized_sample)
  ))

  dataset_name <- sanitize_dataset_name(settings$dataset_name)
  config_path <- file.path(app_folder_path, "general_config.yaml")
  config <- yaml::read_yaml(config_path)

  dataset_dir_path <- file.path(
    app_folder_path,
    config$paths$datasets_dir,
    dataset_name
  )
  resources_dir_path <- file.path(
    app_folder_path,
    config$paths$resources_dir
  )
  raw_data_dir_path <- file.path(
    dataset_dir_path,
    config$dataset_paths$raw_dir
  )
  processed_dir_path <- file.path(
    dataset_dir_path,
    config$dataset_paths$processed_dir
  )
  dir.create(processed_dir_path, recursive = TRUE, showWarnings = FALSE)

  dataset_config_path <- file.path(
    dataset_dir_path,
    config$config_files$dataset
  )
  selected_config_path <- file.path(
    dataset_dir_path,
    config$config_files$selected
  )
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

  expression_filename <- paste0(
    "Exp_data_",
    settings$matrix_state,
    ".mtx"
  )
  std_names <- dataset_config$std_names
  std_names$expmat <- expression_filename

  raw_context <- prepare_raw_data(
    raw_data_dir_path = raw_data_dir_path,
    resources_dir_path = resources_dir_path,
    sample_names = sample_names,
    samples_info_dt = samples_info_dt,
    config = config,
    dataset_config = dataset_config
  )

  sample_cell_counts <- stats::setNames(integer(length(sample_names)), sample_names)
  dataset_cell_names <- character()

  for (sample_name in sample_names) {
    message("Standardizing sample: ", sample_name)
    sample_input <- load_sample_input(
      sample_name = sample_name,
      raw_context = raw_context,
      raw_data_dir_path = raw_data_dir_path,
      resources_dir_path = resources_dir_path,
      samples_info_dt = samples_info_dt,
      config = config,
      dataset_config = dataset_config
    )
    sample_meta <- samples_config$samples[[match(sample_name, sample_names)]]
    standardized_sample <- prepare_standardized_sample(
      sample_input = sample_input,
      sample_name = sample_name,
      sample_meta = sample_meta,
      matrix_state = settings$matrix_state
    )

    repeated_cells <- intersect(
      dataset_cell_names,
      standardized_sample$cells$cell_name
    )
    if (length(repeated_cells) > 0) {
      stop(
        "Sample '", sample_name,
        "' reuses dataset cell identifiers (for example: ",
        paste(utils::head(repeated_cells, 5), collapse = ", "),
        ").",
        call. = FALSE
      )
    }
    dataset_cell_names <- c(
      dataset_cell_names,
      standardized_sample$cells$cell_name
    )

    write_standardized_sample(
      standardized_sample = standardized_sample,
      sample_name = sample_name,
      processed_dir_path = processed_dir_path,
      std_names = std_names
    )
    sample_cell_counts[[sample_name]] <- nrow(standardized_sample$cells)
  }

  samples <- build_samples(sample_names)
  metadata_columns <- setdiff(
    names(samples_info_dt),
    c("sample", "n_cells")
  )
  if (length(metadata_columns) > 0) {
    metadata_order <- match(samples$sample, samples_info_dt$sample)
    for (column in metadata_columns) {
      data.table::set(
        samples,
        j = column,
        value = samples_info_dt[[column]][metadata_order]
      )
    }
  }
  data.table::set(
    samples,
    j = "n_cells",
    value = as.integer(sample_cell_counts[samples$sample])
  )
  data.table::fwrite(
    samples,
    file.path(processed_dir_path, std_names$samples)
  )

  dataset_config$std_names$expmat <- expression_filename
  yaml::write_yaml(dataset_config, dataset_config_path)

  if (
    isTRUE(settings$reset_selected_config) ||
      !file.exists(selected_config_path)
  ) {
    yaml::write_yaml(
      setup_selected_config(sample_names),
      selected_config_path
    )
  } else {
    message("Preserving existing selected_config.yaml.")
  }

  validation <- validate_standardization(
    processed_dir_path = processed_dir_path,
    sample_names = sample_names,
    std_names = dataset_config$std_names,
    strict = TRUE
  )

  record_pipeline_event(
    dataset_dir_path = dataset_dir_path,
    dataset = dataset_name,
    stage = "standardization",
    event_type = "standardization_validated",
    outcome = "completed",
    parameters = list(
      sample_count = length(sample_names),
      expression_type = validation$expression_type,
      matrix_state = settings$matrix_state
    )
  )

  state_filename <- .pipeline_value_or(
    config$config_files$state,
    "pipeline_state.yaml"
  )
  pipeline_state <- tryCatch({
    current_state <- load_or_initialize_pipeline_state(
      dataset_dir_path = dataset_dir_path,
      dataset_id = dataset_name,
      sample_names = sample_names,
      dataset_config = dataset_config,
      selected_config = yaml::read_yaml(selected_config_path),
      config = config,
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
        sample_count = length(sample_names),
        expression_type = validation$expression_type,
        matrix_state = settings$matrix_state
      )
    )
    save_pipeline_state_atomic(
      current_state,
      dataset_dir_path = dataset_dir_path,
      state_filename = state_filename
    )
  }, error = identity)
  if (inherits(pipeline_state, "error")) {
    record_pipeline_event(
      dataset_dir_path = dataset_dir_path,
      dataset = dataset_name,
      stage = "state",
      event_type = "pipeline_state_update",
      outcome = "failed",
      reason = conditionMessage(pipeline_state)
    )
    stop(
      "Standardization passed, but pipeline state could not be persisted: ",
      conditionMessage(pipeline_state),
      call. = FALSE
    )
  }

  message(
    "Standardization complete for ", length(sample_names),
    " sample(s). Expression type: ", validation$expression_type, "."
  )
  invisible(validation)
}


# ==============================================================================
# 6. RUN
# ==============================================================================

if (isTRUE(RUN_STANDARDIZATION)) {
  run_general_standardization(settings)
} else {
  message(
    "General standardization template loaded but not run. ",
    "Complete USER SETTINGS and USER CODE, then set RUN_STANDARDIZATION <- TRUE."
  )
}
