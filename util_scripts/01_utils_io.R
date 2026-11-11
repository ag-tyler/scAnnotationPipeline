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


read_prepared_samples <- function(samples_file_path) {
  #' Read Prepared Sample Metadata Without Identifier Conversion
  #'
  #' @description Reads CSV headers and values as supplied. All columns remain
  #'   character, including numeric-looking identifiers and extra user fields.
  #'   Structural validation is performed by `check_prepared_data()`.
  #' @param samples_file_path Path to the authoritative sample CSV.
  #' @return A data.table with blank values represented by NA_character_.

  # The metadata table is small. Base CSV parsing correctly unescapes doubled
  # quotes and closes its connection even when malformed input warns/errors.
  # Strip an optional UTF-8 BOM before CSV parsing (including quoted headers).
  # Leave bytes unconverted and mark parsed strings as UTF-8 below, rather
  # than transcoding metadata to a potentially incompatible native locale.
  prefix <- readBin(samples_file_path, "raw", n = 3L)
  connection <- file(samples_file_path, open = "rt")
  on.exit(close(connection), add = TRUE)
  offset <- if (identical(prefix, as.raw(c(239, 187, 191)))) 3L else 0L
  seek(connection, offset, origin = "start")
  # Check record widths first: read.csv otherwise treats a consistent extra
  # field as implicit row names, silently shifting sample identifiers.
  widths <- utils::count.fields(
    connection, sep = ",", quote = '"', comment.char = "",
    blank.lines.skip = FALSE
  )
  if (length(widths) && (is.na(widths[[1]]) ||
      any(widths != widths[[1]], na.rm = TRUE))) {
    stop("CSV records must have the same number of fields as the header.", call. = FALSE)
  }
  seek(connection, offset, origin = "start")
  data.table::as.data.table(utils::read.csv(
    connection,
    colClasses = "character", na.strings = "", row.names = NULL,
    strip.white = FALSE, check.names = FALSE, fill = FALSE,
    blank.lines.skip = FALSE, encoding = "UTF-8"
  ))
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

