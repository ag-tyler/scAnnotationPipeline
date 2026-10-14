# ==============================================================================
# Data Standardization (10x Technology)
# scRNA-seq Pipeline
# ==============================================================================
#
# PURPOSE
# -------
# This script standardizes raw 10x Genomics single-cell datasets for use in the
# downstream scAnnotationPipeline.
#
# It performs the following steps:
#   1. Defines dataset-specific paths and settings.
#   2. Loads project configuration and utility functions.
#   3. Validates the dataset setup.
#   4. Optionally extracts an archive containing raw 10x files.
#   5. Maps matrix, feature, and barcode files to samples.
#   6. Allows manual alignment of raw sample IDs to configured sample IDs.
#   7. Inspects the expression matrix to determine its state.
#   8. Standardizes every sample.
#   9. Creates the final Samples.csv and selected_config.yaml files.
#  10. Validates the standardized output.
#
# USER INTERACTION
# ----------------
# Sections marked with:
#
#     USER INPUT REQUIRED
#
# should be reviewed and adjusted for every new dataset.
#
# This script is intentionally written as a mostly linear workflow so that the
# standardization procedure is transparent and can easily be adapted when a
# dataset does not follow the expected structure.
#
# ==============================================================================


# ==============================================================================
# 1. USER SETTINGS
# ==============================================================================
#
# USER INPUT REQUIRED
#
# Define the project, dataset, and resource directories.
#
# Relative paths can be used if the working directory is known and stable.
# Otherwise, absolute paths are recommended.
#
# ==============================================================================

rm(list = ls(all.names = TRUE))
gc()


# ------------------------------------------------------------------------------
# 1.1 Path definitions
# ------------------------------------------------------------------------------

# Path to the scAnnotationPipeline application folder
app_folder_path <- file.path("/path/to/app_folder")

# Path to the dataset folder
dataset_dir_path <- file.path(app_folder_path, "datasets/dataset_name")

# Path containing global resource files
resources_path <- file.path(app_folder_path, "resources")


# ------------------------------------------------------------------------------
# 1.2 Raw archive settings
# ------------------------------------------------------------------------------
#
# Set extract_archive to TRUE when the raw data are still stored in an archive
# that needs to be extracted.
#
# After successful extraction, changing this back to FALSE prevents the archive
# from being extracted again on subsequent runs.
#
# ------------------------------------------------------------------------------

extract_archive <- FALSE

archive_name <- "<file_name>.tar"


# ==============================================================================
# 2. PACKAGE AND PROJECT SETUP
# ==============================================================================

library(data.table)
library(stringr)
library(Matrix)
library(yaml)


# ------------------------------------------------------------------------------
# 2.1 Load general application configuration
# ------------------------------------------------------------------------------

config <- read_yaml(
  file.path(app_folder_path, "general_config.yaml")
)


# ------------------------------------------------------------------------------
# 2.2 Source project utility scripts
# ------------------------------------------------------------------------------
#
# Utility functions shared by the application are loaded here.
#
# Dataset-specific standardization logic remains in this script so that the
# complete transformation procedure can be followed from beginning to end.
#
# ------------------------------------------------------------------------------

invisible(
  lapply(
    list.files(
      file.path(app_folder_path, "util_scripts"),
      pattern = "\\.R$",
      full.names = TRUE
    ),
    source
  )
)


# ------------------------------------------------------------------------------
# 2.3 Construct dataset paths
# ------------------------------------------------------------------------------

processed_dataset_dir_path <- file.path(
  dataset_dir_path,
  config$dataset_paths$processed_dir
)

raw_data_dir_path <- file.path(
  dataset_dir_path,
  config$dataset_paths$raw_dir
)


# ------------------------------------------------------------------------------
# 2.4 Load dataset configuration
# ------------------------------------------------------------------------------

dataset_config_path <- file.path(
  dataset_dir_path,
  config$config_files$dataset
)

dataset_config <- read_yaml(dataset_config_path)


# ------------------------------------------------------------------------------
# 2.5 Load sample configuration
# ------------------------------------------------------------------------------

samples_config_path <- file.path(
  dataset_dir_path,
  config$config_files$samples
)

samples_config <- read_yaml(samples_config_path)


# ------------------------------------------------------------------------------
# 2.6 Load global HGNC resource
# ------------------------------------------------------------------------------
#
# The HGNC table is used later if the gene symbols contained in the raw 10x
# files are not unique and Ensembl IDs therefore need to be mapped to symbols.
#
# Ensembl IDs that occur more than once in the HGNC resource are removed to
# prevent ambiguous mappings.
#
# ------------------------------------------------------------------------------

hgnc_complete_set <- fread(
  file.path(
    resources_path,
    config$resource_files$hgnc_complete_set
  ),
  key = "symbol"
)

hgnc_complete_set <- hgnc_complete_set[
  !(
    ensembl_gene_id %in%
      names(table(ensembl_gene_id))[table(ensembl_gene_id) > 1]
  )
]


# ==============================================================================
# 3. PRE-VALIDATION
# ==============================================================================
#
# Verify that the dataset has been prepared correctly before processing begins.
#
# In particular, samples_config.yaml must contain the required sample metadata.
# If validation fails, correct the configuration file before continuing.
#
# ==============================================================================

samples_config <- prevalidate_setup(
  dataset_dir_path,
  config
)


# ------------------------------------------------------------------------------
# 3.1 Convert sample configuration into a table
# ------------------------------------------------------------------------------

samples_info_dt <- rbindlist(
  samples_config$samples,
  fill = TRUE,
  use.names = TRUE
)

sample_names <- samples_info_dt$sample


# ==============================================================================
# 4. RAW DATA EXTRACTION
# ==============================================================================
#
# If the raw dataset is stored in an archive, it can optionally be extracted
# into:
#
#     <raw data directory>/extracted/
#
# Set extract_archive = TRUE in Section 1 before running this section.
#
# ==============================================================================

raw_tar_path <- file.path(
  raw_data_dir_path,
  archive_name
)

extracted_dir_path <- file.path(
  raw_data_dir_path,
  "extracted"
)


# ------------------------------------------------------------------------------
# 4.1 Check archive location
# ------------------------------------------------------------------------------

message(
  "Does the archive exist? ",
  file.exists(raw_tar_path)
)


# ------------------------------------------------------------------------------
# 4.2 Extract archive when requested
# ------------------------------------------------------------------------------

if (extract_archive) {
  
  message("Extracting tarball... This may take a while.")
  
  untar(
    raw_tar_path,
    exdir = extracted_dir_path
  )
  
  message("Extraction complete.")
  
} else {
  
  message("Archive extraction skipped.")
  
}


# ==============================================================================
# 5. MAP RAW 10x FILES TO SAMPLES
# ==============================================================================
#
# USER INPUT REQUIRED
#
# The raw 10x files must be grouped into:
#
#   - barcodes
#   - features
#   - matrix
#
# for every sample.
#
# The following regular expression extracts the sample identifier and file type
# from each filename.
#
# The example pattern matches filenames such as:
#
#     GSM6204109_P01_barcodes.tsv.gz
#     GSM6204109_P01_features.tsv.gz
#     GSM6204109_P01_matrix.mtx.gz
#
# Different datasets frequently use different naming conventions. Adjust the
# regular expression below when necessary.
#
# ==============================================================================


# ------------------------------------------------------------------------------
# 5.1 Define filename pattern
# ------------------------------------------------------------------------------

pattern <- "GSM[0-9]+_([A-Za-z0-9_]+)_(barcodes|features|matrix)\\.(tsv|mtx)\\.gz"


# ------------------------------------------------------------------------------
# 5.2 Define capture groups and standardized file types
# ------------------------------------------------------------------------------
#
# The regular expression above contains capture groups:
#
#   group 1 -> sample ID
#   group 2 -> file type
#
# File types are renamed to the terminology expected by the standardization
# pipeline.
#
# ------------------------------------------------------------------------------

group_indices <- list(
  sample_id = 1,
  file_type = 2
)

type_mapping <- list(
  barcodes = "cells",
  features = "genes",
  matrix = "matrix"
)


# ------------------------------------------------------------------------------
# 5.3 Inspect files in extracted directory
# ------------------------------------------------------------------------------

all_files <- list.files(
  extracted_dir_path,
  full.names = TRUE
)

file_info <- data.table(
  path = all_files,
  file_name = basename(all_files)
)


# ------------------------------------------------------------------------------
# 5.4 Extract sample IDs and file types from filenames
# ------------------------------------------------------------------------------

matches <- str_match(
  file_info$file_name,
  pattern
)

file_info[
  ,
  sample_id := matches[, group_indices$sample_id + 1]
]

file_info[
  ,
  std_type := unlist(type_mapping)[
    matches[, group_indices$file_type + 1]
  ]
]


# ------------------------------------------------------------------------------
# 5.5 Build one row per sample
# ------------------------------------------------------------------------------
#
# Resulting structure:
#
#     sample_id | cells | genes | matrix
#
# Each path points to the corresponding raw 10x file.
#
# ------------------------------------------------------------------------------

sample_map <- dcast(
  file_info[!is.na(sample_id)],
  sample_id ~ std_type,
  value.var = "path"
)


# ==============================================================================
# 6. REVIEW AND ALIGN SAMPLE IDS
# ==============================================================================
#
# USER INPUT REQUIRED
#
# IDs encoded in raw filenames do not necessarily match the clean sample IDs
# defined in samples_config.yaml.
#
# Compare both sets printed below.
#
# If they differ, use the "changes" vector to map:
#
#     raw filename ID -> configured sample ID
#
# If they already match exactly, leave "changes" empty.
#
# ==============================================================================


# ------------------------------------------------------------------------------
# 6.1 Display detected and configured IDs
# ------------------------------------------------------------------------------

message("Raw IDs found in file names:")
print(unique(sample_map$sample_id))

message("IDs configured in samples_config.yaml:")
print(sample_names)


# ------------------------------------------------------------------------------
# 6.2 Manually align IDs when necessary
# ------------------------------------------------------------------------------
#
# Example:
#
# changes <- c(
#   "KC_08_1" = "CC_02_1",
#   "KC_08_2" = "CC_02_2"
# )
#
# Leave the vector empty when no mapping is required.
#
# ------------------------------------------------------------------------------

changes <- c(
  # "raw_file_id_01" = "clean_config_id_01"
  # "KC_08_1" = "CC_02_1"
)


if (length(changes) > 0) {
  
  matched_ids <- changes[sample_map$sample_id]
  
  sample_map$sample_id <- ifelse(
    is.na(matched_ids),
    sample_map$sample_id,
    matched_ids
  )
  
}


# ==============================================================================
# 7. MATRIX INSPECTION
# ==============================================================================
#
# USER INPUT REQUIRED
#
# Load the first sample's matrix and inspect its values to determine the matrix
# state.
#
# Typical interpretations:
#
#   UMIcounts
#       Values are normally non-negative integers representing raw UMI counts.
#
#   CP10k
#       Columns may sum to approximately 10,000 after normalization.
#
#   TPM
#       Columns may sum to approximately 1,000,000.
#
# Do not rely only on these heuristics if the source publication or dataset
# documentation explicitly states how the matrix was generated.
#
# ==============================================================================


# ------------------------------------------------------------------------------
# 7.1 Load one matrix for inspection
# ------------------------------------------------------------------------------

test_expmat <- readMM(
  sample_map$matrix[1]
)


# ------------------------------------------------------------------------------
# 7.2 Inspect matrix values
# ------------------------------------------------------------------------------

message("Summary of the first 100 column sums:")

print(
  summary(
    Matrix::colSums(test_expmat)[1:100]
  )
)

message(
  "Maximum matrix value: ",
  max(test_expmat)
)


# ==============================================================================
# 8. DEFINE MATRIX STATE
# ==============================================================================
#
# USER INPUT REQUIRED
#
# Based on the matrix inspection above and the dataset documentation, define the
# matrix state.
#
# Examples:
#
#     "UMIcounts"
#     "CP10k"
#     "TPM"
#
# This value becomes part of the standardized expression matrix filename.
#
# ==============================================================================

matrix_state <- "UMIcounts"


# ------------------------------------------------------------------------------
# 8.1 Update standardized expression matrix filename
# ------------------------------------------------------------------------------

new_expmat_name <- paste0(
  "Exp_data_",
  matrix_state,
  ".mtx"
)

dataset_config$std_names$expmat <- new_expmat_name


# ------------------------------------------------------------------------------
# 8.2 Save updated dataset configuration
# ------------------------------------------------------------------------------

write_yaml(
  dataset_config,
  dataset_config_path
)

message(
  "Updated dataset_config.yaml. Expected matrix name is now: ",
  new_expmat_name
)


# ==============================================================================
# 9. STANDARDIZE ALL SAMPLES
# ==============================================================================
#
# The following loop processes every sample detected during file mapping.
#
# For each sample it:
#
#   1. Loads the sparse expression matrix.
#   2. Loads cell barcodes.
#   3. Loads gene information.
#   4. Checks whether gene identifiers need to be remapped.
#   5. Assigns gene and cell names to the matrix.
#   6. Removes genes that could not be mapped.
#   7. Creates standardized cell metadata.
#   8. Saves the matrix, Cells.csv, and gene list.
#
# This section intentionally remains explicit rather than hiding the processing
# inside a utility function. Dataset-specific standardization often requires
# modifications, and keeping the operations visible makes those modifications
# easier to understand and review.
#
# ==============================================================================

sample_cell_counts <- list()


for (i in seq_len(nrow(sample_map))) {
  
  # ---------------------------------------------------------------------------
  # 9.1 Identify current sample
  # ---------------------------------------------------------------------------
  
  sample_name <- sample_map$sample_id[i]
  
  message(
    i,
    ". Standardizing sample: ",
    sample_name
  )
  
  
  # ---------------------------------------------------------------------------
  # 9.2 Load expression matrix
  # ---------------------------------------------------------------------------
  
  expmat <- readMM(
    sample_map$matrix[i]
  )
  
  # Convert to compressed sparse column format when necessary.
  if (!inherits(expmat, "dgCMatrix")) {
    
    expmat <- as(
      expmat,
      "CsparseMatrix"
    )
    
  }
  
  
  # ---------------------------------------------------------------------------
  # 9.3 Load cell barcodes
  # ---------------------------------------------------------------------------
  
  cell_names <- fread(
    sample_map$cells[i],
    header = FALSE
  )$V1
  
  
  # ---------------------------------------------------------------------------
  # 9.4 Load gene information
  # ---------------------------------------------------------------------------
  #
  # Standard 10x feature files generally contain:
  #
  #   V1 -> Ensembl gene ID
  #   V2 -> gene symbol
  #
  # Initially use the supplied gene symbols. They are replaced using HGNC
  # mapping below if duplicate symbols are detected.
  #
  # ---------------------------------------------------------------------------
  
  genes <- fread(
    sample_map$genes[i],
    header = FALSE
  )
  
  genes_mapped <- genes$V2
  
  
  # ---------------------------------------------------------------------------
  # 9.5 Validate and potentially remap genes
  # ---------------------------------------------------------------------------
  
  if (any(duplicated(genes$V1))) {
    
    stop(
      "Ensembl gene IDs are not unique for sample: ",
      sample_name
    )
    
  }
  
  
  if (any(duplicated(genes$V2))) {
    
    message(
      "Gene symbols are not unique. ",
      "Mapping using Ensembl gene IDs..."
    )
    
    genes_mapped <- map_ensembl_to_symbol_vector(
      genes$V1,
      hgnc_complete_set
    )
    
  }
  
  
  # ---------------------------------------------------------------------------
  # 9.6 Validate cell names
  # ---------------------------------------------------------------------------
  
  if (length(unique(cell_names)) != length(cell_names)) {
    
    stop(
      "Cell names are not unique for sample: ",
      sample_name
    )
    
  }
  
  
  # ---------------------------------------------------------------------------
  # 9.7 Assign matrix row and column names
  # ---------------------------------------------------------------------------
  
  rownames(expmat) <- genes_mapped
  colnames(expmat) <- cell_names
  
  
  # ---------------------------------------------------------------------------
  # 9.8 Remove genes without a valid mapped symbol
  # ---------------------------------------------------------------------------
  
  valid_genes <- !is.na(genes_mapped)
  
  expmat <- expmat[
    valid_genes,
    ,
    drop = FALSE
  ]
  
  genes_mapped <- genes_mapped[
    valid_genes
  ]

  # Multiple Ensembl IDs can resolve to the same HGNC symbol. Preserve their
  # total expression by collapsing those rows before writing standardized data.
  if (anyDuplicated(genes_mapped)) {
    expmat <- sum_dup_rows_sparse(expmat)
    genes_mapped <- rownames(expmat)
  }
  
  
  # ---------------------------------------------------------------------------
  # 9.9 Build standardized Cells metadata
  # ---------------------------------------------------------------------------
  
  cells <- build_cells(
    colnames(expmat)
  )
  
  cells[
    ,
    sample := sample_name
  ]
  
  
  # Locate the corresponding entry in samples_config.yaml.
  sample_config_index <- which(
    sample_names == sample_name
  )
  
  
  cells[
    ,
    patient :=
      samples_config$samples[[sample_config_index]]$patient
  ]
  
  cells[
    ,
    complexity :=
      matkot::col_nnz(expmat)
  ]
  
  cells[
    ,
    source :=
      samples_config$samples[[sample_config_index]]$site
  ]
  
  
  # ---------------------------------------------------------------------------
  # 9.10 Record number of cells
  # ---------------------------------------------------------------------------
  
  sample_cell_counts[[sample_name]] <- nrow(cells)
  
  
  # ---------------------------------------------------------------------------
  # 9.11 Create sample output directory
  # ---------------------------------------------------------------------------
  
  sample_dir_path <- file.path(
    processed_dataset_dir_path,
    sample_name
  )
  
  dir.create(
    sample_dir_path,
    showWarnings = FALSE
  )
  
  
  # ---------------------------------------------------------------------------
  # 9.12 Save standardized expression matrix
  # ---------------------------------------------------------------------------
  
  writeMM(
    expmat,
    file = file.path(
      sample_dir_path,
      dataset_config$std_names$expmat
    )
  )
  
  
  # ---------------------------------------------------------------------------
  # 9.13 Save standardized cell metadata
  # ---------------------------------------------------------------------------
  
  fwrite(
    cells,
    file = file.path(
      sample_dir_path,
      dataset_config$std_names$cells
    )
  )
  
  
  # ---------------------------------------------------------------------------
  # 9.14 Save standardized gene list
  # ---------------------------------------------------------------------------
  
  fwrite(
    data.table(genes_mapped),
    file = file.path(
      sample_dir_path,
      dataset_config$std_names$genes
    ),
    col.names = FALSE
  )
  
}


# ==============================================================================
# 10. FINALIZE PIPELINE CONFIGURATION
# ==============================================================================
#
# After every sample has been standardized:
#
#   - create the global Samples.csv registry;
#   - add dataset-specific sample metadata;
#   - add the number of cells per sample;
#   - initialize selected_config.yaml.
#
# ==============================================================================


# ------------------------------------------------------------------------------
# 10.1 Create base Samples table
# ------------------------------------------------------------------------------

samples <- build_samples(
  sample_names
)


# ------------------------------------------------------------------------------
# 10.2 Add metadata from samples_config.yaml
# ---------------------------------------------------------------------------
#
# The canonical "sample" column identifies the same row in both the
# configuration and the standardized Samples table. All remaining fields are
# copied into Samples.csv.
#
# ------------------------------------------------------------------------------

cols_to_add <- setdiff(
  names(samples_info_dt),
  "sample"
)

samples[
  samples_info_dt,
  (cols_to_add) := mget(
    paste0("i.", cols_to_add)
  ),
  on = .(sample)
]


# ------------------------------------------------------------------------------
# 10.3 Add cell counts
# ------------------------------------------------------------------------------

samples[
  ,
  n_cells := unlist(sample_cell_counts)[sample]
]


# ------------------------------------------------------------------------------
# 10.4 Save Samples.csv
# ------------------------------------------------------------------------------

fwrite(
  samples,
  file = file.path(
    processed_dataset_dir_path,
    dataset_config$std_names$samples
  )
)


# ------------------------------------------------------------------------------
# 10.5 Initialize selected_config.yaml
# ------------------------------------------------------------------------------

selected_config <- setup_selected_config(
  samples$sample
)

write_yaml(
  selected_config,
  file.path(
    dataset_dir_path,
    config$config_files$selected
  )
)


# ==============================================================================
# 11. POST-VALIDATION
# ==============================================================================
#
# Run the final structural validation expected by the Shiny application.
#
# The validator checks whether the standardized files and directories satisfy
# the downstream pipeline requirements.
#
# Correct any reported problems before continuing with the annotation pipeline.
#
# ==============================================================================

validate_standardization(
  processed_dir_path = processed_dataset_dir_path,
  sample_names = sample_names,
  std_names = dataset_config$std_names,
  strict = TRUE
)


# ==============================================================================
# END OF STANDARDIZATION
# ==============================================================================
#
# If validation succeeds, the dataset should now be ready for the downstream
# scAnnotationPipeline workflow.
#
# ==============================================================================
