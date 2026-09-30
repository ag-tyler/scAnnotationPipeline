# tests/testthat/helper-fixtures.R
#
# Synthetic, from-scratch test data. Nothing here is real biological data --
# it exists purely so tests don't depend on the (untracked, multi-GB)
# resource files described in README.md. Every generator takes a `seed` so
# fixtures are reproducible across runs and machines.
#
# Loaded automatically by testthat as a "helper-*.R" file, same as
# helper-source.R.

#' Build a tiny synthetic sparse UMI-count matrix.
#'
#' Deliberately gives a handful of cells very low total counts and a handful
#' of genes very low expression, so filter_cell_gene_count()/gene_expr_filter()
#' tests have something real to filter out.
make_mini_expmat <- function(n_genes = 30, n_cells = 20, seed = 1,
                              n_low_count_cells = 3, n_low_expr_genes = 4) {
  set.seed(seed)
  gene_names <- sprintf("GENE%02d", seq_len(n_genes))
  cell_names <- sprintf("cell_%02d", seq_len(n_cells))

  # Baseline: most genes/cells get plausible-looking UMI counts.
  mat <- Matrix::rsparsematrix(
    nrow = n_genes, ncol = n_cells, density = 0.6,
    rand.x = function(n) rpois(n, lambda = 8) + 1
  )

  # Force a known subset of cells to have very few detected genes.
  if (n_low_count_cells > 0) {
    low_cols <- seq_len(n_low_count_cells)
    mat[, low_cols] <- 0
    mat[1:2, low_cols] <- 1 # a couple of genes so the column isn't all-zero
  }

  # Force a known subset of genes to have very low expression everywhere.
  if (n_low_expr_genes > 0) {
    low_rows <- seq(n_genes - n_low_expr_genes + 1, n_genes)
    mat[low_rows, ] <- 0
  }

  mat <- methods::as(mat, "CsparseMatrix")
  rownames(mat) <- gene_names
  colnames(mat) <- cell_names
  mat
}

#' Build a Cells.csv-shaped data.table for a set of cell names.
make_mini_cells_dt <- function(cell_names, sample_name = "sample1") {
  cells <- build_cells(cell_names) # defined in 03_utils_misc.R
  cells[, sample := sample_name]
  cells
}

#' Write one standardized sample folder (expmat/genes/cells) to disk, in
#' exactly the layout load_expmat()/load_genes()/load_cells() expect.
#'
#' @return A list with the on-disk paths and the in-memory objects used to
#'   generate them, so tests can assert against ground truth.
write_mini_sample <- function(parent_dir, sample_name = "sample1",
                               n_genes = 30, n_cells = 20, seed = 1,
                               std_names = list(expmat = "Exp_data_UMIcounts.mtx",
                                                 genes = "Genes.txt",
                                                 cells = "Cells.csv")) {
  sample_dir <- file.path(parent_dir, sample_name)
  dir.create(sample_dir, recursive = TRUE, showWarnings = FALSE)

  mat <- make_mini_expmat(n_genes = n_genes, n_cells = n_cells, seed = seed)
  cells <- make_mini_cells_dt(colnames(mat), sample_name = sample_name)

  Matrix::writeMM(mat, file.path(sample_dir, std_names$expmat))
  writeLines(rownames(mat), file.path(sample_dir, std_names$genes))
  data.table::fwrite(cells, file.path(sample_dir, std_names$cells))

  list(
    sample_dir = sample_dir,
    expmat_path = file.path(sample_dir, std_names$expmat),
    genes_path = file.path(sample_dir, std_names$genes),
    cells_path = file.path(sample_dir, std_names$cells),
    mat = mat,
    cells = cells
  )
}

#' A tiny HGNC-style ensembl_gene_id -> symbol lookup table.
make_mini_hgnc <- function(n = 10, seed = 1) {
  set.seed(seed)
  data.table::data.table(
    ensembl_gene_id = sprintf("ENSG%011d", seq_len(n)),
    symbol = sprintf("GENE%02d", seq_len(n))
  )
}

#' Full list of attributes prevalidate_setup()/build_samples() require per
#' sample, matching the list documented in README.md / hard-coded in
#' 03_utils_misc.R.
required_sample_attrs <- function() {
  c(
    "id", "technology", "cancer_type", "patient", "histology", "site",
    "sample_type", "sample_primary_met", "disease_extent", "diagnosis_recurrence",
    "instance_at_site", "treated_naive", "age", "sex", "grade", "AJCC_stage",
    "AJCC_T", "AJCC_N", "AJCC_M", "size", "smoking_status", "PY", "KI67",
    "genetic_hormonal_features", "chemotherapy_exposed", "chemotherapy_response",
    "targeted_rx_exposed", "targeted_rx_response", "post_sampling_rx_exposed",
    "post_sampling_rx_response", "time_end_of_rx_to_sampling", "ET_exposed",
    "ET_response", "ICB_exposed", "ICB_response", "PFS_DFS", "OS"
  )
}

#' One fully-populated (blank-but-present) sample metadata entry.
make_valid_sample_entry <- function(id = "sample1") {
  attrs <- required_sample_attrs()
  entry <- as.list(rep(NA, length(attrs)))
  names(entry) <- attrs
  entry$id <- id
  entry
}

#' Deterministic inputs for the compute_cna() golden-file test.
#' Used by both generate_golden_fixtures.R and test-golden_outputs.R, so the
#' two can never drift apart.
make_cna_golden_inputs <- function(n_genes = 12, n_cells = 15, seed = 123) {
  set.seed(seed)

  gene_positions <- data.table::data.table(
    symbol = sprintf("GENE%02d", seq_len(n_genes)),
    chromosome_name = rep(c("1", "2"), each = n_genes / 2),
    start_position = seq(1e6, by = 1e6, length.out = n_genes)
  )

  cell_names <- sprintf("cell_%02d", seq_len(n_cells))
  expmat <- matrix(
    stats::rnorm(n_genes * n_cells, mean = 5, sd = 1.5),
    nrow = n_genes, dimnames = list(gene_positions$symbol, cell_names)
  )
  expmat <- Matrix::Matrix(expmat, sparse = TRUE)

  ref_cells <- data.table::data.table(
    cell_name = cell_names[1:5],
    cell_type = "Non-malignant"
  )

  list(expmat = expmat, gene_positions = gene_positions, ref_cells = ref_cells)
}

#' Write a samples_config.yaml fixture to `path`.
#'
#' @param problem One of "none" (valid), "empty" (no samples at all),
#'   "blank_id" (a sample with an empty id), or "missing_attr" (a sample
#'   missing a required attribute), to exercise prevalidate_setup()'s
#'   individual failure branches.
write_samples_config <- function(path, problem = c("none", "empty", "blank_id", "missing_attr")) {
  problem <- match.arg(problem)

  samples <- switch(problem,
    none = list(make_valid_sample_entry("sample1"), make_valid_sample_entry("sample2")),
    empty = list(),
    blank_id = list(modifyList(make_valid_sample_entry(""), list(id = ""))),
    missing_attr = {
      entry <- make_valid_sample_entry("sample1")
      entry[["cancer_type"]] <- NULL
      list(entry)
    }
  )

  yaml::write_yaml(list(samples = samples), path)
  invisible(path)
}
