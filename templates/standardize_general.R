# ==============================================================================
# General Data Standardization Template
# scAnnotationPipeline
# ==============================================================================
#
# PURPOSE
# -------
# Adapt one clearly marked USER CODE section to convert raw single-cell data
# into the shared app-ready format. The complete workflow remains visible here;
# reusable implementation details live in util_scripts/08_utils_standardization.R
# and can be inspected with, for example, `?prepare_standardized_sample`.
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
# Matrix columns correspond by position to Cells.csv rows. Matrix rows
# correspond by position to Genes.txt entries. The canonical sample identifier
# is `sample`.
#
# VISIBLE WORKFLOW
# ----------------
#   1. Resolve and validate settings.
#   2. Load helpers and prevalidate samples_config.yaml.
#   3. Run the dataset-specific USER CODE section.
#   4. Validate and prepare every sample before staging its files.
#   5. Build Samples.csv from configured metadata and calculated cell counts.
#   6. Strictly postvalidate every staged file and cross-sample invariant.
#   7. Publish the validated staging directory and update pipeline state.
#
# Only USER SETTINGS and the region between BEGIN/END USER CODE should normally
# be edited. Run the entire file from a clean R session.
# ==============================================================================


# ==============================================================================
# 1. USER SETTINGS -- EDIT THIS SECTION
# ==============================================================================

RUN_STANDARDIZATION <- FALSE

settings <- list(
  # Usually leave NULL: the script searches upward for general_config.yaml.
  # Supply an explicit checkout path only when automatic discovery is unsuitable.
  app_folder_path = NULL,

  # Folder name under the configured datasets directory.
  dataset_name = "<dataset_name>",

  # Values returned by the user code: "UMIcounts", "TPM", or "CPM".
  matrix_state = "UMIcounts",

  # Preserve existing clustering/CNA choices during normal repeat runs.
  reset_selected_config = FALSE
)


# ==============================================================================
# 2. BOOTSTRAP PROJECT HELPERS -- PIPELINE CODE
# ==============================================================================

find_standardization_app_root <- function(explicit_path = NULL) {
  if (!is.null(explicit_path) && length(explicit_path) > 0L) {
    return(normalizePath(explicit_path, winslash = "/", mustWork = TRUE))
  }

  file_argument <- grep(
    "^--file=",
    commandArgs(trailingOnly = FALSE),
    value = TRUE
  )
  script_paths <- sub("^--file=", "", file_argument)
  frame_paths <- unlist(lapply(sys.frames(), function(frame) frame$ofile))
  starting_paths <- unique(c(
    dirname(c(script_paths, frame_paths)),
    getwd()
  ))
  starting_paths <- starting_paths[
    !is.na(starting_paths) & nzchar(starting_paths)
  ]

  for (starting_path in starting_paths) {
    candidate <- normalizePath(
      starting_path,
      winslash = "/",
      mustWork = FALSE
    )
    repeat {
      if (
        file.exists(file.path(candidate, "general_config.yaml")) &&
          dir.exists(file.path(candidate, "util_scripts"))
      ) {
        return(candidate)
      }
      parent <- dirname(candidate)
      if (identical(parent, candidate)) break
      candidate <- parent
    }
  }

  stop(
    "Could not locate the scAnnotationPipeline root. Set ",
    "settings$app_folder_path explicitly.",
    call. = FALSE
  )
}


if (isTRUE(RUN_STANDARDIZATION)) {
  settings$app_folder_path <- find_standardization_app_root(
    settings$app_folder_path
  )

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

  standardization_utils <- file.path(
    settings$app_folder_path,
    "util_scripts",
    c(
      "03_utils_misc.R",
      "06_utils_logging.R",
      "07_utils_state.R",
      "08_utils_standardization.R"
    )
  )
  missing_utils <- standardization_utils[!file.exists(standardization_utils)]
  if (length(missing_utils) > 0L) {
    stop(
      "Standardization utilities are missing: ",
      paste(missing_utils, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(lapply(standardization_utils, source, local = environment()))


  # ============================================================================
  # 3. INITIALIZE AND PREVALIDATE -- PIPELINE CODE
  # ============================================================================
  #
  # This validates settings and samples_config.yaml, loads dataset configuration,
  # and creates `processed_data_staging` beside `processed_data`. Existing
  # processed data remains untouched until the new output passes strict
  # postvalidation.

  standardization <- initialize_standardization(settings)

  raw_data_dir_path <- standardization$raw_data_dir_path
  resources_dir_path <- standardization$resources_dir_path
  sample_names <- standardization$sample_names
  samples_info_dt <- standardization$samples_info_dt
  config <- standardization$config
  dataset_config <- standardization$dataset_config


  # ============================================================================
  # BEGIN USER CODE -- EDIT ONLY THIS REGION
  # ============================================================================
  #
  # Use normal R code to load, inspect, map, filter, and split the raw data.
  # Keep the workflow that is natural for the dataset; no callback functions are
  # required. For every configured sample, create `sample_input` and pass it
  # through the two pipeline calls shown below.
  #
  # Required sample_input contract:
  #
  #   sample_input <- list(
  #     expmat = <numeric genes-by-cells matrix>,
  #     genes = <final gene symbols aligned to matrix rows>,
  #     cells = <dataset-wide unique IDs aligned to matrix columns>,
  #     cell_metadata = <optional table keyed by cell_name>
  #   )
  #
  # `prepare_standardized_sample()` validates values and dimensions, removes
  # blank genes, sums duplicate gene-symbol rows, aligns optional metadata, and
  # creates required cell metadata. `register_standardized_sample()` checks
  # cross-sample cell uniqueness and writes the prepared sample to staging.
  # Use `?prepare_standardized_sample` or `?register_standardized_sample` for the
  # detailed contract and side effects.
  #
  # Typical combined-matrix shape:
  #
  #   raw_expmat <- Matrix::readMM(file.path(raw_data_dir_path, "matrix.mtx.gz"))
  #   raw_genes <- data.table::fread(file.path(raw_data_dir_path, "genes.tsv.gz"))
  #   raw_cells <- data.table::fread(file.path(raw_data_dir_path, "barcodes.tsv.gz"))[[1]]
  #
  #   # Dataset-specific extraction or explicit mapping of raw sample IDs:
  #   sample_ids <- ...
  #   validate_standardization_sample_mapping(unique(sample_ids), sample_names)
  #
  #   for (sample_name in sample_names) {
  #     sample_columns <- which(sample_ids == sample_name)
  #     sample_input <- list(
  #       expmat = raw_expmat[, sample_columns, drop = FALSE],
  #       genes = raw_genes[[2]],
  #       cells = raw_cells[sample_columns]
  #     )
  #     sample_meta <- standardization$samples_config$samples[[
  #       match(sample_name, sample_names)
  #     ]]
  #     standardized_sample <- prepare_standardized_sample(
  #       sample_input = sample_input,
  #       sample_name = sample_name,
  #       sample_meta = sample_meta,
  #       matrix_state = settings$matrix_state
  #     )
  #     register_standardized_sample(
  #       context = standardization,
  #       sample_name = sample_name,
  #       standardized_sample = standardized_sample
  #     )
  #   }

  stop(
    "USER INPUT REQUIRED: replace this stop() with dataset-specific code.",
    call. = FALSE
  )

  # ============================================================================
  # END USER CODE
  # ============================================================================


  # ============================================================================
  # 4. BUILD DATASET-WIDE SAMPLE METADATA -- PIPELINE CODE
  # ============================================================================
  #
  # This fails if any configured sample was not registered, then creates the
  # staged Samples.csv from samples_config.yaml and calculated cell counts.

  write_standardized_samples_table(standardization)


  # ============================================================================
  # 5. STRICT POSTVALIDATION -- PIPELINE CODE
  # ============================================================================
  #
  # Every staged file is read back. The validator checks filenames, dimensions,
  # required metadata columns, identifiers, values, sample assignments, cell
  # counts, and uniqueness within and across samples. Any issue stops the run.

  validation <- validate_standardization(
    processed_dir_path = standardization$working_dir_path,
    sample_names = standardization$sample_names,
    std_names = standardization$std_names,
    strict = TRUE
  )


  # ============================================================================
  # 6. PUBLISH AND RECORD COMPLETION -- PIPELINE CODE
  # ============================================================================
  #
  # Only validated staging output is published. This replaces processed_data,
  # updates dataset_config.yaml, preserves selected_config.yaml unless reset was
  # requested, records an event, and marks pipeline standardization completed.

  publish_standardization(standardization, validation)
} else {
  message(
    "General standardization template loaded but not run. Complete USER ",
    "SETTINGS and USER CODE, then set RUN_STANDARDIZATION <- TRUE."
  )
}
