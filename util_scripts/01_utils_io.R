# ==============================================================================
# Script: utils_io.R
# Purpose: Collection of personal functions to load specific types of files.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Environment & Packages
# ------------------------------------------------------------------------------

library(docstring)


# ------------------------------------------------------------------------------
# 2. Loading functions
# ------------------------------------------------------------------------------


load_samples <- function(samples_file_path) {
  #' Loads the Samples.csv file
  #' 
  #' @param samples_file_path Path to Samples.csv
  #' 
  #' @return Samples table in data table format
  
  samples <- data.table::fread(samples_file_path, colClasses = c(sample = 'character'), na.strings = '')
  return(samples)
}


load_cells <- function(cells_file_path) {
  #' Loads Cells.csv 
  #' 
  #' @param cells_file_path Path to Cells.csv
  #' 
  #' @return The cells data table.
  
  cells <- data.table::fread(cells_file_path, colClasses = c(cell_name = 'character', 
                                                             sample = 'character',
                                                             cell_type = 'character'), 
                             na.strings = '')
  return(cells)
}


load_expmat <- function(expmat_file_path) {
  #' Loads expression matrix .mtx file as sparse matrix with no col- and row-names.
  #' 
  #' @param expmat_file_path Path to .mtx file
  #' 
  #' @return Expression matrix in sparse matrix format
  
  expmat <- Matrix::readMM(expmat_file_path)
  return(expmat)
}


load_genes <- function(genes_file_path) {
  #' Loads Genes.txt file as character vector
  #'
  #' @param genes_file_path Path to Genes.txt
  #'
  #' @return List of genes as character vector
  
  genes <- data.table::fread(genes_file_path, header = FALSE)$V1
  return(genes)
}


load_expdt <- function(cna_mat_path) {
  #' Loads and melts a CNA matrix into a long-format data table.
  #' 
  #' Reads a wide-format copy number alteration (CNA) matrix from disk and 
  #' transforms it into a long-format data table for downstream analysis.
  #' 
  #' @param cna_mat_path Path to the saved CNA matrix file.
  #' 
  #' @return A long-format data table containing CNA values per cell and gene.
  
  cna_mat <- data.table::fread(cna_mat_path)
  expdt <- data.table::melt(cna_mat, id.vars = c('gene', 'chr', 'start_pos'), 
                            variable.name = 'cell_name', value.name = 'cna', 
                            variable.factor = FALSE)
  return(expdt)
}

require_file <- function(path, what, hint = NULL) {
  #' Assert a file exists before attempting to read it, with an actionable message.
  #'
  #' @param path Character. The path that should exist.
  #' @param what Character. Human-readable description of what this file is 
  #'   (used in the error message).
  #' @param hint Character. Optional pointer to where the user should look to fix it 
  #'   (a config key, a folder name, etc.).
  
  if (!file.exists(path)) {
    msg <- sprintf("Missing required file: %s\nExpected at: %s", what, path)
    if (!is.null(hint)) msg <- paste0(msg, "\n", hint)
    stop(msg, call. = FALSE)
  }
  invisible(TRUE)
}

