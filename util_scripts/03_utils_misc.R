# ==================================================================================================
# Script: utils_misc.R
# Purpose: Collection of miscellaneous functions.
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# 1. Environment & Packages
# --------------------------------------------------------------------------------------------------

library(docstring)



# --------------------------------------------------------------------------------------------------
# 2. Matrix functions
# --------------------------------------------------------------------------------------------------


sum_dup_rows_sparse <- function(mat) {
  #' Sums up rows with same names in sparse matrices.
  #' 
  #' @param mat Sparse matrix (dgCMatrix)
  #' 
  #' @return Sparse matrix with unique rownames
  # 1. Input Check
  if (is.null(rownames(mat))) stop("Matrix must have rownames to aggregate.")
  # 2. Handle NAs in names to prevent data loss
  rn <- rownames(mat)
  rn[is.na(rn)] <- "NA_row"
  
  gene_factors <- factor(rn)
  
  bit_mat <- Matrix::sparseMatrix(
    i = as.integer(gene_factors),
    j = seq_along(gene_factors),
    x = 1
  )
  
  res <- bit_mat %*% mat
  rownames(res) <- levels(gene_factors)
  return(res)
}


# --------------------------------------------------------------------------------------------------
# 3. Mapping
# --------------------------------------------------------------------------------------------------


map_ensembl_to_symbol_vector <- function(ensembl_ids, hgnc_complete_set) {
  #' Map a Vector of Ensembl IDs to HGNC Symbols
  #'
  #' @description Takes a character vector of Ensembl Gene IDs and returns a vector
  #'   of official HGNC gene symbols in the exact same order. This is useful for 
  #'   translating identifiers while maintaining alignment with downstream data structures.
  #'
  #' @param ensembl_ids A character vector of Ensembl Gene IDs to be mapped.
  #' @param hgnc_complete_set A data.frame or data.table containing the HGNC reference data.
  #'   Must contain `ensembl_gene_id` and `symbol` columns.
  #'
  #' @return A character vector of HGNC symbols of the same length and order as `ensembl_ids`.
  #'   Ensembl IDs that do not have a match in the reference set will return as `NA`.
  
  # Ensure the reference is a data.table without altering the global environment unexpectedly
  if (!data.table::is.data.table(hgnc_complete_set)) {
    data.table::setDT(hgnc_complete_set)
  }
  
  # Extract just the necessary columns to save memory
  # Using list() instead of .() for strict namespace compliance
  map_dt <- hgnc_complete_set[!is.na(ensembl_gene_id) & ensembl_gene_id != "", list(ensembl_gene_id, symbol)]
  
  # Ensure unique Ensembl IDs in our reference dictionary to prevent mapping collisions
  map_dt <- map_dt[!duplicated(ensembl_gene_id)]
  
  # base::match() finds the index of the first match for each ensembl_id.
  # This strictly guarantees the output matches the length and order of the input vector.
  matched_indices <- base::match(ensembl_ids, map_dt$ensembl_gene_id)
  
  # Extract the corresponding symbols (unmatched indices return NA automatically)
  mapped_symbols <- map_dt$symbol[matched_indices]
  
  return(mapped_symbols)
}



# --------------------------------------------------------------------------------------------------
# 4. Config functions
# --------------------------------------------------------------------------------------------------


normalize_marker_table <- function(marker_table, group_column, table_label = "Marker table") {
  #' Validate and normalize a marker-gene resource table
  #'
  #' Marker resources historically use `gene`, while downstream annotation
  #' code uses the canonical name `symbol`. This function accepts either input
  #' spelling, returns an independent data.table with `symbol`, and fails early
  #' with an actionable schema error when required fields are absent.
  required_columns <- c(group_column, "combined")
  missing_columns <- setdiff(required_columns, names(marker_table))
  if (length(missing_columns) > 0L) {
    stop(
      table_label, " is missing required column(s): ",
      paste(missing_columns, collapse = ", "), ".",
      call. = FALSE
    )
  }

  normalized <- data.table::as.data.table(data.table::copy(marker_table))
  if (!"symbol" %in% names(normalized)) {
    if (!"gene" %in% names(normalized)) {
      stop(
        table_label, " must contain a 'symbol' column (or legacy 'gene' column).",
        call. = FALSE
      )
    }
    data.table::setnames(normalized, "gene", "symbol")
  }

  normalized[, symbol := trimws(as.character(symbol))]
  if (anyNA(normalized$symbol) || any(normalized$symbol == "")) {
    stop(table_label, " contains missing or empty gene symbols.", call. = FALSE)
  }

  normalized
}

setup_selected_config <- function(sample_names) {
  #' Setup Configuration List for Samples
  #'
  #' @description Initializes a nested configuration list for a given set of samples. 
  #' This list is structured to be easily exported to a `config.yaml` file. It sets 
  #' default resolutions to `0.0` and creates empty lists (which serialize to empty 
  #' arrays in YAML) for the CNA reference cells for each sample.
  #'
  #' @param sample_names A character vector specifying the names of the samples.
  #'
  #' @return A named list containing two top-level elements: 
  #'   \itemize{
  #'     \item \code{resolutions}: A list where each sample name maps to a numeric value of `0.0`.
  #'     \item \code{cna_ref_cells}: A list where each sample name maps to an empty list `list()`.
  #'   }
  #'
  #' @examples
  #' # Example usage:
  #' samples <- c("Sample_1", "Sample_2")
  #' config <- setup_selected_config(samples)
  #' 
  #' # To save as a YAML file, use the 'yaml' package:
  #' # library(yaml)
  #' # write_yaml(config, "config.yaml")
  
  selected_config <- list()
  resolutions <- list()
  cna_ref_cells <- list()
  cna_pot_mal_cells = list()
  cna_ward_ref_cluster = list()
  cna_thresholds = list()
  sample_notes = list()
  for (sample_name in sample_names) {
    resolutions[[sample_name]] <- 0.0
    cna_ref_cells[[sample_name]] <- list()
    cna_pot_mal_cells[[sample_name]] <- list()
    cna_ward_ref_cluster[[sample_name]] <- list()
    cna_thresholds[[sample_name]] <- list()
    sample_notes[[sample_name]] <- ""
  }
  selected_config[['resolutions']] <- resolutions
  selected_config[['cna_ref_cells']] <- cna_ref_cells
  selected_config[['cna_pot_mal_cells']] <- cna_pot_mal_cells
  selected_config[['cna_ward_ref_cluster']] <- cna_ward_ref_cluster
  selected_config[['cna_thresholds']] <- cna_thresholds
  selected_config[['sample_notes']] <- sample_notes
  return(selected_config)
}


reconcile_selected_config <- function(selected_config, sample_names) {
  #' Add missing selected-config sections and sample entries
  #'
  #' Existing decisions are preserved while older selected_config.yaml files
  #' gain defaults introduced by newer app versions.
  defaults <- setup_selected_config(sample_names)
  if (is.null(selected_config) || !is.list(selected_config)) selected_config <- list()

  for (section in names(defaults)) {
    if (is.null(selected_config[[section]]) || !is.list(selected_config[[section]])) {
      selected_config[[section]] <- list()
    }
    for (sample_name in sample_names) {
      if (is.null(selected_config[[section]][[sample_name]])) {
        selected_config[[section]][[sample_name]] <- defaults[[section]][[sample_name]]
      }
    }
  }
  selected_config
}


save_sample_note <- function(selected_config, selected_config_path, sample_name, note) {
  if (is.null(sample_name) || length(sample_name) != 1L || is.na(sample_name) || !nzchar(sample_name)) {
    stop("A sample name is required to save a note.", call. = FALSE)
  }
  if (is.null(selected_config$sample_notes)) selected_config$sample_notes <- list()
  note <- if (is.null(note) || length(note) == 0L || is.na(note[[1]])) {
    ""
  } else {
    as.character(note[[1]])
  }
  selected_config$sample_notes[[sample_name]] <- note
  yaml::write_yaml(selected_config, selected_config_path)
  selected_config
}


# --------------------------------------------------------------------------------------------------
# 5. Standardization functions
# --------------------------------------------------------------------------------------------------

validate_samples_config <- function(samples_cfg) {
  #' Validate Sample Configuration Identifiers
  #'
  #' @description Enforces `sample` as the sole identifier in a parsed
  #' `samples_config.yaml` object. The former `id` key is rejected rather than
  #' converted so configuration errors cannot propagate into later stages.
  #'
  #' @param samples_cfg Parsed samples configuration containing a `samples` list.
  #'
  #' @return The configuration with trimmed character `sample` identifiers.

  if (is.null(samples_cfg$samples)) {
    samples_cfg$samples <- list()
    return(samples_cfg)
  }

  sample_value <- function(value, index) {
    if (is.null(value) || length(value) == 0 || is.na(value[[1]])) {
      return("")
    }
    if (length(value) != 1) {
      stop(
        sprintf(
          "SAMPLE CONFIGURATION FAILED: Sample at index %d has a non-scalar 'sample' identifier.",
          index
        ),
        call. = FALSE
      )
    }
    trimws(as.character(value[[1]]))
  }

  samples_cfg$samples <- lapply(seq_along(samples_cfg$samples), function(i) {
    sample_meta <- samples_cfg$samples[[i]]
    if ("id" %in% names(sample_meta)) {
      stop(
        sprintf(
          "SAMPLE CONFIGURATION FAILED: Sample at index %d uses unsupported 'id'; rename it to 'sample'.",
          i
        ),
        call. = FALSE
      )
    }
    sample_meta$sample <- sample_value(sample_meta$sample, i)
    sample_meta
  })

  samples_cfg
}

prevalidate_setup <- function(dataset_dir_path, config) {
  #' Pre-validate Sample Configuration
  #'
  #' @description Checks if the user has properly filled out the necessary 
  #' configuration files before running the pipeline. Specifically, it reads the 
  #' samples configuration YAML and verifies that it is not empty, every sample
  #' uses the canonical `sample` identifier, every identifier is valid,
  #' identifier, and all required metadata attributes are present.
  #'
  #' @param dataset_dir_path Character string specifying the base path to the dataset directory.
  #' @param config List containing general configuration settings, including `config_files$samples`.
  #'
  #' @return The validated parsed configuration, invisibly. Throws a hard error
  #' if validation fails, otherwise prints a success message to the console.
  
  samples_config_path <- file.path(dataset_dir_path, config$config_files$samples)
  samples_cfg <- validate_samples_config(yaml::read_yaml(samples_config_path))
  
  # 1. Hard stop if the config is entirely empty
  if (length(samples_cfg$samples) == 0) {
    stop(
      "PREVALIDATION FAILED: The samples_config.yaml file contains no samples. \n
      Please manually fill in your sample metadata before running this script.", 
      call. = FALSE
    )
  }
  
  # 2. Define the exact necessary attributes expected in the YAML
  required_attrs <- c(
    "sample", "technology", "cancer_type", "patient", "histology", "site",
    "sample_type", "sample_primary_met", "disease_extent", "diagnosis_recurrence", 
    "instance_at_site", "treated_naive", "age", "sex", "grade", "AJCC_stage", 
    "AJCC_T", "AJCC_N", "AJCC_M", "size", "smoking_status", "PY", "KI67", 
    "genetic_hormonal_features", "chemotherapy_exposed", "chemotherapy_response", 
    "targeted_rx_exposed", "targeted_rx_response", "post_sampling_rx_exposed", 
    "post_sampling_rx_response", "time_end_of_rx_to_sampling", "ET_exposed", 
    "ET_response", "ICB_exposed", "ICB_response", "PFS_DFS", "OS"
  )
  
  # 3. Iterate through every sample and validate attributes
  for (i in seq_along(samples_cfg$samples)) {
    sample_meta <- samples_cfg$samples[[i]]
    
    # Check if the canonical sample identifier is empty
    if (is.null(sample_meta$sample) || trimws(sample_meta$sample) == "") {
      stop(
        sprintf("PREVALIDATION FAILED: Sample at index %d has an empty 'sample'.", i),
        call. = FALSE
      )
    }
    if (
      sample_meta$sample %in% c(".", "..") ||
        grepl("[/\\\\]", sample_meta$sample)
    ) {
      stop(
        sprintf(
          "PREVALIDATION FAILED: Sample '%s' is not a safe directory identifier.",
          sample_meta$sample
        ),
        call. = FALSE
      )
    }
    
    # Check for missing attributes
    missing_attrs <- setdiff(required_attrs, names(sample_meta))
    
    if (length(missing_attrs) > 0) {
      stop(
        sprintf(
          "PREVALIDATION FAILED: Sample '%s' is missing the following necessary attributes: %s", 
          sample_meta$sample,
          paste(missing_attrs, collapse = ", ")
        ), 
        call. = FALSE
      )
    }
  }
  
  sample_names <- vapply(
    samples_cfg$samples,
    function(sample_meta) sample_meta$sample,
    character(1)
  )
  duplicate_samples <- unique(sample_names[duplicated(sample_names)])
  if (length(duplicate_samples) > 0) {
    stop(
      "PREVALIDATION FAILED: Duplicate sample identifiers: ",
      paste(duplicate_samples, collapse = ", "),
      call. = FALSE
    )
  }

  message("Prevalidation passed! Configuration files look good.")
  invisible(samples_cfg)
}

infer_standardized_expression_type <- function(expmat_filename) {
  #' Infer Standardized Expression Type From Its Filename
  #'
  #' @param expmat_filename Configured Matrix Market filename.
  #'
  #' @return One of `counts`, `TPM`, `CPM`, or `NA_character_` when the
  #' filename does not declare a supported scale.

  filename <- if (is.null(expmat_filename) || length(expmat_filename) == 0) {
    ""
  } else {
    tolower(basename(expmat_filename[[1]]))
  }
  if (grepl("umi|count", filename)) return("counts")
  if (grepl("tpm", filename)) return("TPM")
  if (grepl("cpm", filename)) return("CPM")
  NA_character_
}


validate_standardization <- function(
  processed_dir_path,
  sample_names,
  std_names,
  strict = FALSE
) {
  #' Validate Standardization Output
  #'
  #' @description Validates the complete standardized-data contract: declared
  #' expression scale, sample directories/files, required cell columns,
  #' identifiers, expression values, matrix dimensions, gene identifiers, and
  #' the optional dataset-wide Samples table. All problems are collected so one
  #' run gives an actionable report.
  #'
  #' @param processed_dir_path Directory containing standardized sample folders.
  #' @param sample_names Canonical sample identifiers expected in the dataset.
  #' @param std_names Expected filenames (`expmat`, `genes`, `cells`, and
  #' optionally `samples`).
  #' @param strict Logical. If `TRUE`, invalid output raises an error after the
  #' complete report is printed. If `FALSE`, it raises a warning.
  #'
  #' @return Invisibly returns a structured list with `valid`, `errors`,
  #' `expression_type`, and per-sample dimensions.

  `%or_empty%` <- function(value, fallback) {
    if (is.null(value) || length(value) == 0) fallback else value[[1]]
  }
  add_error <- function(errors, sample_name = NULL, message) {
    prefix <- if (is.null(sample_name)) "Dataset" else paste0("Sample '", sample_name, "'")
    c(errors, paste0(prefix, ": ", message))
  }

  errors <- character()
  sample_reports <- list()
  all_cell_names <- character()
  sample_names <- trimws(as.character(sample_names))

  required_std_names <- c("expmat", "genes", "cells")
  missing_std_names <- required_std_names[
    !vapply(std_names[required_std_names], function(x) {
      length(x) == 1 && !is.na(x) && nzchar(trimws(x))
    }, logical(1))
  ]
  if (length(missing_std_names) > 0) {
    stop(
      "Standard filename configuration is missing: ",
      paste(missing_std_names, collapse = ", "),
      call. = FALSE
    )
  }

  expression_type <- infer_standardized_expression_type(std_names$expmat)
  if (is.na(expression_type)) {
    errors <- add_error(
      errors,
      message = paste0(
        "expression filename '", std_names$expmat,
        "' does not declare a supported counts, TPM, or CPM scale"
      )
    )
  }

  if (length(sample_names) == 0) {
    errors <- add_error(errors, message = "no sample identifiers were supplied")
  }
  if (any(is.na(sample_names) | !nzchar(sample_names))) {
    errors <- add_error(errors, message = "sample identifiers contain missing or blank values")
  }
  duplicate_samples <- unique(sample_names[duplicated(sample_names)])
  if (length(duplicate_samples) > 0) {
    errors <- add_error(
      errors,
      message = paste("duplicate sample identifiers:", paste(duplicate_samples, collapse = ", "))
    )
  }

  unsafe_samples <- unique(sample_names[
    !is.na(sample_names) &
      (sample_names %in% c(".", "..") | grepl("[/\\\\]", sample_names))
  ])
  if (length(unsafe_samples) > 0) {
    errors <- add_error(
      errors,
      message = paste(
        "sample identifiers are not safe directory names:",
        paste(unsafe_samples, collapse = ", ")
      )
    )
  }

  valid_sample_names <- sample_names[
    !is.na(sample_names) &
      nzchar(sample_names) &
      !(sample_names %in% unsafe_samples)
  ]
  for (s_name in unique(valid_sample_names)) {
    sample_dir <- file.path(processed_dir_path, s_name)
    if (!dir.exists(sample_dir)) {
      errors <- add_error(errors, s_name, paste0("directory is missing: ", sample_dir))
      next
    }

    sample_paths <- file.path(
      sample_dir,
      unlist(std_names[required_std_names], use.names = FALSE)
    )
    names(sample_paths) <- required_std_names
    missing_files <- basename(sample_paths[!file.exists(sample_paths)])
    if (length(missing_files) > 0) {
      errors <- add_error(
        errors,
        s_name,
        paste("missing required files:", paste(missing_files, collapse = ", "))
      )
      next
    }

    expmat <- tryCatch(Matrix::readMM(sample_paths[["expmat"]]), error = identity)
    cells <- tryCatch(
      data.table::fread(
        sample_paths[["cells"]],
        colClasses = c(cell_name = "character", sample = "character"),
        na.strings = ""
      ),
      error = identity
    )
    genes <- tryCatch(
      trimws(readLines(sample_paths[["genes"]], warn = FALSE)),
      error = identity
    )

    read_failures <- c(
      if (inherits(expmat, "error")) paste0("expression matrix: ", conditionMessage(expmat)),
      if (inherits(cells, "error")) paste0("cell metadata: ", conditionMessage(cells)),
      if (inherits(genes, "error")) paste0("gene list: ", conditionMessage(genes))
    )
    if (length(read_failures) > 0) {
      errors <- add_error(
        errors,
        s_name,
        paste("could not read", paste(read_failures, collapse = "; "))
      )
      next
    }

    required_cell_columns <- c(
      "cell_name", "sample", "cell_type", "complexity", "cell_subtype",
      "patient", "subclone", "source"
    )
    missing_cell_columns <- setdiff(required_cell_columns, names(cells))
    if (length(missing_cell_columns) > 0) {
      errors <- add_error(
        errors,
        s_name,
        paste("Cells file is missing columns:", paste(missing_cell_columns, collapse = ", "))
      )
    }

    if (nrow(cells) != ncol(expmat)) {
      errors <- add_error(
        errors,
        s_name,
        sprintf("Cells rows (%d) do not match matrix columns (%d)", nrow(cells), ncol(expmat))
      )
    }
    if (length(genes) != nrow(expmat)) {
      errors <- add_error(
        errors,
        s_name,
        sprintf("Genes entries (%d) do not match matrix rows (%d)", length(genes), nrow(expmat))
      )
    }

    if (any(is.na(genes) | !nzchar(genes))) {
      errors <- add_error(errors, s_name, "Genes file contains missing or blank identifiers")
    }
    duplicate_genes <- unique(genes[duplicated(genes)])
    if (length(duplicate_genes) > 0) {
      errors <- add_error(
        errors,
        s_name,
        paste0(
          "Genes file contains duplicate identifiers (for example: ",
          paste(utils::head(duplicate_genes, 5), collapse = ", "), ")"
        )
      )
    }

    if ("cell_name" %in% names(cells)) {
      invalid_cells <- is.na(cells$cell_name) | !nzchar(trimws(cells$cell_name))
      if (any(invalid_cells)) {
        errors <- add_error(errors, s_name, "Cells file contains missing or blank cell identifiers")
      }
      duplicate_cells <- unique(cells$cell_name[duplicated(cells$cell_name)])
      if (length(duplicate_cells) > 0) {
        errors <- add_error(
          errors,
          s_name,
          paste0(
            "Cells file contains duplicate cell identifiers (for example: ",
            paste(utils::head(duplicate_cells, 5), collapse = ", "), ")"
          )
        )
      }
      all_cell_names <- c(
        all_cell_names,
        unique(cells$cell_name[!invalid_cells])
      )
    }

    if ("sample" %in% names(cells)) {
      cell_samples <- trimws(cells$sample)
      if (any(is.na(cell_samples) | !nzchar(cell_samples))) {
        errors <- add_error(errors, s_name, "Cells file contains missing sample assignments")
      }
      unexpected_samples <- unique(cell_samples[
        !is.na(cell_samples) & nzchar(cell_samples) & cell_samples != s_name
      ])
      if (length(unexpected_samples) > 0) {
        errors <- add_error(
          errors,
          s_name,
          paste(
            "Cells file contains assignments to other samples:",
            paste(unexpected_samples, collapse = ", ")
          )
        )
      }
    }

    if ("complexity" %in% names(cells)) {
      complexity <- suppressWarnings(as.numeric(cells$complexity))
      if (any(!is.finite(complexity) | complexity < 0)) {
        errors <- add_error(
          errors,
          s_name,
          "Cells complexity must contain finite, non-negative numeric values"
        )
      }
    }

    matrix_values <- if (inherits(expmat, "sparseMatrix")) expmat@x else as.numeric(expmat)
    if (any(!is.finite(matrix_values))) {
      errors <- add_error(errors, s_name, "expression matrix contains non-finite values")
    }
    if (any(matrix_values < 0, na.rm = TRUE)) {
      errors <- add_error(errors, s_name, "expression matrix contains negative values")
    }
    if (
      identical(expression_type, "counts") &&
        any(abs(matrix_values - round(matrix_values)) > sqrt(.Machine$double.eps), na.rm = TRUE)
    ) {
      errors <- add_error(errors, s_name, "count matrix contains non-integer values")
    }

    sample_reports[[s_name]] <- list(
      genes = nrow(expmat),
      cells = ncol(expmat)
    )
  }

  duplicate_dataset_cells <- unique(all_cell_names[duplicated(all_cell_names)])
  if (length(duplicate_dataset_cells) > 0) {
    errors <- add_error(
      errors,
      message = paste0(
        "cell identifiers are not unique across samples (for example: ",
        paste(utils::head(duplicate_dataset_cells, 5), collapse = ", "), ")"
      )
    )
  }

  samples_filename <- std_names$samples %or_empty% ""
  if (nzchar(samples_filename)) {
    samples_path <- file.path(processed_dir_path, samples_filename)
    if (!file.exists(samples_path)) {
      errors <- add_error(
        errors,
        message = paste0("dataset-wide Samples file is missing: ", samples_filename)
      )
    } else {
      samples <- tryCatch(
        data.table::fread(
          samples_path,
          colClasses = c(sample = "character"),
          na.strings = ""
        ),
        error = identity
      )
      if (inherits(samples, "error")) {
        errors <- add_error(
          errors,
          message = paste("could not read Samples file:", conditionMessage(samples))
        )
      } else {
        missing_samples_columns <- setdiff(c("sample", "n_cells"), names(samples))
        if (length(missing_samples_columns) > 0) {
          errors <- add_error(
            errors,
            message = paste(
              "Samples file is missing columns:",
              paste(missing_samples_columns, collapse = ", ")
            )
          )
        }
        if ("sample" %in% names(samples)) {
          samples$sample <- trimws(samples$sample)
          if (any(is.na(samples$sample) | !nzchar(samples$sample))) {
            errors <- add_error(errors, message = "Samples file contains blank identifiers")
          }
          if (anyDuplicated(samples$sample)) {
            errors <- add_error(errors, message = "Samples file contains duplicate identifiers")
          }
          missing_rows <- setdiff(sample_names, samples$sample)
          unexpected_rows <- setdiff(samples$sample, sample_names)
          if (length(missing_rows) > 0 || length(unexpected_rows) > 0) {
            errors <- add_error(
              errors,
              message = paste0(
                "Samples file identifiers do not match configured samples",
                if (length(missing_rows) > 0) {
                  paste0("; missing: ", paste(missing_rows, collapse = ", "))
                } else "",
                if (length(unexpected_rows) > 0) {
                  paste0("; unexpected: ", paste(unexpected_rows, collapse = ", "))
                } else ""
              )
            )
          }
        }
        if (all(c("sample", "n_cells") %in% names(samples))) {
          expected_counts <- vapply(sample_reports, `[[`, integer(1), "cells")
          recorded_counts <- suppressWarnings(as.numeric(samples$n_cells))
          names(recorded_counts) <- samples$sample
          comparable <- intersect(names(expected_counts), names(recorded_counts))
          mismatched_counts <- comparable[
            !is.finite(recorded_counts[comparable]) |
              recorded_counts[comparable] != expected_counts[comparable]
          ]
          if (length(mismatched_counts) > 0) {
            errors <- add_error(
              errors,
              message = paste(
                "Samples n_cells does not match Cells rows for:",
                paste(mismatched_counts, collapse = ", ")
              )
            )
          }
        }
      }
    }
  }

  result <- structure(
    list(
      valid = length(errors) == 0,
      errors = errors,
      expression_type = expression_type,
      samples = sample_reports
    ),
    class = "standardization_validation"
  )

  if (!result$valid) {
    cat("\n:::{.callout-warning appearance='default'}\n")
    cat("## POST-VALIDATION FAILED\n\n")
    for (msg in result$errors) cat("* ", msg, "\n", sep = "")
    cat(":::\n")

    failure_message <- paste0(
      "Post-validation failed with ", length(result$errors),
      " issue(s). Review the complete validation report above."
    )
    if (isTRUE(strict)) {
      stop(failure_message, call. = FALSE)
    }
    warning(failure_message, call. = FALSE)
  } else {
    cat("\n:::{.callout-success appearance='default'}\n")
    cat("## POST-VALIDATION PASSED\n\n")
    cat(
      "All standardized files, identifiers, values, and dimensions satisfy ",
      "the data contract.\n",
      sep = ""
    )
    cat(":::\n")
  }

  invisible(result)
}


build_samples <- function(sample_ids) {
  #' Build Empty Samples Metadata Table
  #'
  #' @description Constructs a blank `data.table` formatted to hold sample-level metadata. 
  #' It initializes a predefined set of clinical and technical columns with `NA_character_` 
  #' and populates the primary `sample` identifier column.
  #'
  #' @param sample_ids Character vector of sample identifiers used to populate the `sample` column.
  #'
  #' @return A `data.table` containing standard sample metadata columns.
  
  col_names <- c(
    "sample", "technology", "cancer_type", "patient", "histology", "site",
    "sample_type", "sample_primary_met", "disease_extent", "diagnosis_recurrence", 
    "instance_at_site", "treated_naive", "age", "sex", "grade", "AJCC_stage", 
    "AJCC_T", "AJCC_N", "AJCC_M", "size", "smoking_status", "PY", "KI67", 
    "genetic_hormonal_features", "chemotherapy_exposed", "chemotherapy_response", 
    "targeted_rx_exposed", "targeted_rx_response", "post_sampling_rx_exposed", 
    "post_sampling_rx_response", "time_end_of_rx_to_sampling", "ET_exposed", 
    "ET_response", "ICB_exposed", "ICB_response", "PFS_DFS", "OS"
  )
  
  blank_matrix <- matrix(NA_character_, nrow = length(sample_ids), ncol = length(col_names))
  
  samples_dt <- data.table::as.data.table(blank_matrix)
  data.table::setnames(samples_dt, col_names)
  
  samples_dt[, sample := as.character(sample_ids)]
  
  return(samples_dt)
}


build_cells <- function(cell_ids) {
  #' Build Empty Cells Metadata Table
  #'
  #' @description Constructs a blank `data.table` formatted to hold cell-level annotations. 
  #' It initializes standard columns for tracking cell types, sub-clonal architecture, and 
  #' technical metrics with `NA_character_`, and populates the primary `cell_name` column.
  #'
  #' @param cell_ids Character vector of cell identifiers used to populate the `cell_name` column.
  #'
  #' @return A `data.table` containing standard cell metadata columns.
  
  col_names <- c('cell_name', 'sample', 'cell_type', 'complexity', 'cell_subtype', 'patient', 
                 'subclone', 'source')
  
  blank_matrix <- matrix(NA_character_, nrow = length(cell_ids), ncol = length(col_names))
  
  cells <- data.table::as.data.table(blank_matrix)
  data.table::setnames(cells, col_names)
  
  cells[, cell_name := cell_ids]
  
  return(cells)
}


sanitize_dataset_name <- function(name) {
  #' Validate a user-supplied dataset folder name against path traversal
  #'
  #' @description Ensures a name is safe to use as a single path segment 
  #' (e.g. via file.path(parent_dir, name)) by rejecting path separators, 
  #' traversal sequences, and other characters that could escape the intended 
  #' parent directory or cause cross-platform issues.
  #'
  #' @param name Character. The raw, user-supplied dataset name.
  #'
  #' @return Character. The trimmed, validated name. Throws an error if invalid.
  
  name <- trimws(name)
  
  if (name == "") {
    stop("Dataset name cannot be empty.", call. = FALSE)
  }
  
  # Reject absolute-path-looking inputs first.
  if (grepl("^(~|[A-Za-z]:|/)", name)) {
    stop("Dataset name must be a plain folder name, not a path.", call. = FALSE)
  }
  
  # Then reject separators / traversal in otherwise-relative names.
  if (grepl("[/\\\\]", name) || grepl("\\.\\.", name)) {
    stop(
      "Dataset name cannot contain path separators ('/', '\\') or '..'.",
      call. = FALSE
    )
  }
  
  # Reject null bytes and other control characters
  if (grepl("[\\x00-\\x1f]", name, perl = TRUE)) {
    stop("Dataset name contains invalid control characters.", call. = FALSE)
  }
  
  # Restrict to a safe, portable character set (letters, digits, space, 
  # underscore, hyphen, period — adjust if you need to allow more)
  if (!grepl("^[A-Za-z0-9 _.-]+$", name)) {
    stop("Dataset name may only contain letters, numbers, spaces, '_', '-', and '.'.", 
         call. = FALSE)
  }
  
  # Reject Windows-reserved device names (CON, PRN, AUX, NUL, COM1-9, LPT1-9), 
  # relevant since local_config.yaml shows this app runs on Windows
  reserved <- c("CON", "PRN", "AUX", "NUL", paste0("COM", 1:9), paste0("LPT", 1:9))
  if (toupper(name) %in% reserved) {
    stop("'", name, "' is a reserved name on Windows and cannot be used.", call. = FALSE)
  }
  
  return(name)
}
