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
  for (sample_name in sample_names) {
    resolutions[[sample_name]] <- 0.0
    cna_ref_cells[[sample_name]] <- list()
    cna_pot_mal_cells[[sample_name]] <- list()
    cna_ward_ref_cluster[[sample_name]] <- list()
    cna_thresholds[[sample_name]] <- list()
  }
  selected_config[['resolutions']] <- resolutions
  selected_config[['cna_ref_cells']] <- cna_ref_cells
  selected_config[['cna_pot_mal_cells']] <- cna_pot_mal_cells
  selected_config[['cna_ward_ref_cluster']] <- cna_ward_ref_cluster
  selected_config[['cna_thresholds']] <- cna_thresholds
  return(selected_config)
}


# --------------------------------------------------------------------------------------------------
# 5. Standardization functions
# --------------------------------------------------------------------------------------------------

prevalidate_setup <- function(dataset_dir_path, config) {
  #' Pre-validate Sample Configuration
  #'
  #' @description Checks if the user has properly filled out the necessary 
  #' configuration files before running the pipeline. Specifically, it reads the 
  #' samples configuration YAML and verifies that it is not empty, every sample has 
  #' a valid `id`, and all required metadata attributes are present.
  #'
  #' @param dataset_dir_path Character string specifying the base path to the dataset directory.
  #' @param config List containing general configuration settings, including `config_files$samples`.
  #'
  #' @return None. Throws a hard error if validation fails, otherwise prints a success message to the console.
  
  samples_config_path <- file.path(dataset_dir_path, config$config_files$samples)
  samples_cfg <- yaml::read_yaml(samples_config_path)
  
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
    "id", "technology", "cancer_type", "patient", "histology", "site", 
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
    
    # Check if ID is empty
    if (is.null(sample_meta$id) || trimws(sample_meta$id) == "") {
      stop(
        sprintf("PREVALIDATION FAILED: Sample at index %d has an empty 'id'.", i), 
        call. = FALSE
      )
    }
    
    # Check for missing attributes
    missing_attrs <- setdiff(required_attrs, names(sample_meta))
    
    if (length(missing_attrs) > 0) {
      stop(
        sprintf(
          "PREVALIDATION FAILED: Sample '%s' is missing the following necessary attributes: %s", 
          sample_meta$id, 
          paste(missing_attrs, collapse = ", ")
        ), 
        call. = FALSE
      )
    }
  }
  
  message("Prevalidation passed! Configuration files look good.")
}

validate_standardization <- function(processed_dir_path, sample_names, std_names) {
  #' Validate Standardization Output
  #'
  #' @description Asserts that the standardization process produced the correct file formats 
  #' and dimensions. It checks for the existence of standard expression matrices, cell metadata, 
  #' and gene lists. It also verifies that matrix dimensions match the metadata length and ensures 
  #' there are no duplicate cell names. Outputs Quarto-styled callouts for reporting.
  #'
  #' @param processed_dir_path Character string specifying the path to the directory containing processed samples.
  #' @param sample_names Character vector of sample directories to validate.
  #' @param std_names List containing the expected standard file names (`expmat`, `genes`, `cells`).
  #'
  #' @return None. Prints diagnostic warning or success messages to the console.
  
  error_msgs <- c()
  
  for (s_name in sample_names) {
    sample_dir <- file.path(processed_dir_path, s_name)
    
    # 1. Check file existence
    req_files <- c(std_names$expmat, std_names$genes, std_names$cells)
    missing <- req_files[!file.exists(file.path(sample_dir, req_files))]
    
    if (length(missing) > 0) {
      error_msgs <- c(error_msgs, paste("Missing files in **", s_name, "**:", paste(missing, collapse = ", ")))
      next # Skip dimension checks if files are missing to avoid crashing
    }
    
    # 2. Check Matrix Dimensions
    expmat <- Matrix::readMM(file.path(sample_dir, std_names$expmat))
    cells <- data.table::fread(file.path(sample_dir, std_names$cells))
    genes <- data.table::fread(file.path(sample_dir, std_names$genes), header = FALSE)
    
    if (nrow(cells) != ncol(expmat)) error_msgs <- c(error_msgs, paste(
      "Dimension mismatch in **", s_name, "**: Cells (", nrow(cells), ") != Matrix Columns (", ncol(expmat), ").")
    )
    if (nrow(genes) != nrow(expmat)) error_msgs <- c(error_msgs, paste(
      "Dimension mismatch in **", s_name, "**: Genes (", nrow(genes), ") != Matrix Rows (", nrow(expmat), ").")
    )
    if (any(duplicated(cells$cell_name))) error_msgs <- c(error_msgs, paste("Duplicate cells found in **", s_name, "**."))
  }
  
  # Print Quarto-styled callouts
  if (length(error_msgs) > 0) {
    cat("\n:::{.callout-warning appearance='default'}\n")
    cat("## ⚠️ POST-VALIDATION WARNINGS FOUND\n\n")
    for (msg in error_msgs) {
      cat(paste("*", msg, "\n"))
    }
    cat(":::\n")
    
    # Also throw a standard R warning for the console
    warning("Post-validation flagged issues. Check the rendered HTML report for details.", call. = FALSE)
  } else {
    cat("\n:::{.callout-success appearance='default'}\n")
    cat("## ✅ POST-VALIDATION PASSED\n\nAll standard files and dimensions are correct. The dataset is ready to be loaded into the Shiny App.\n")
    cat(":::\n")
  }
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
    "id", "technology", "cancer_type", "patient", "histology", "site", 
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
  
  samples_dt[, sample := sample_ids]
  samples_dt[, id := sample_ids]
  
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