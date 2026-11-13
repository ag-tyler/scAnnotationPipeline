# Create a fresh, import-ready subset of an existing processed_data directory.
# Edit settings below and run: Rscript scripts/downsample_processed_data.R
# Or source this file (which only defines the function), then call:
# downsample_processed_data(input_dir = "...", output_dir = "...", n_cells = 3000)
# Requires only Matrix and data.table; does not load or modify app state/caches.

settings <- list(
  input_dir = "datasets/Tang2026_Colorectal/processed_data",
  output_dir = "datasets/Tang2026_Colorectal_demo_input",
  n_cells = 3000L,                 # Maximum per sample, after min_genes filtering.
  samples = NULL,                  # NULL = all; e.g. c("CRC_T3", "CRC_LM3").
  stratify_by = "cell_type",       # Proportional allocation; NULL = uniform.
  min_genes = 500L,                # Matches app default; 0 keeps all input cells.
  reset_annotations = TRUE,
  annotation_columns = c("cell_type", "cell_subtype", "subclone", "cell_type_pre_cna"),
  seed = 3988L
)

downsample_processed_data <- function(
  input_dir, output_dir, n_cells = 3000L, samples = NULL,
  stratify_by = "cell_type", min_genes = 500L, reset_annotations = TRUE,
  annotation_columns = c("cell_type", "cell_subtype", "subclone", "cell_type_pre_cna"),
  seed = 3988L
) {
  # Largest-remainder allocation preserves proportions to integer rounding.
  # No rare-type oversampling: populations can receive zero cells at small caps.
  for (package in c("Matrix", "data.table")) {
    if (!requireNamespace(package, quietly = TRUE)) {
      stop("Install the required R package: ", package, call. = FALSE)
    }
  }
  fail <- function(...) stop(..., call. = FALSE)
  whole_number <- function(value, minimum) {
    is.numeric(value) && length(value) == 1L && !is.na(value) &&
      is.finite(value) && value >= minimum && value <= .Machine$integer.max &&
      value == floor(value)
  }
  if (!whole_number(n_cells, 1)) fail("n_cells must be a positive integer per sample.")
  if (!whole_number(min_genes, 0)) fail("min_genes must be a non-negative integer.")
  if (!whole_number(seed, 0)) fail("seed must be a non-negative integer.")
  if (!is.logical(reset_annotations) || length(reset_annotations) != 1L ||
      is.na(reset_annotations)) fail("reset_annotations must be TRUE or FALSE.")
  column_names <- function(value) {
    is.character(value) && !anyNA(value) && all(nzchar(value)) && !anyDuplicated(value)
  }
  if (!is.null(stratify_by) && !column_names(stratify_by)) {
    fail("stratify_by must be column names or NULL for uniform sampling.")
  }
  if (!column_names(annotation_columns)) fail("annotation_columns must be column names.")
  protected <- c("cell_name", "sample", "complexity", "patient", "source")
  if (any(annotation_columns %in% protected)) {
    fail("annotation_columns cannot include identifiers, complexity, patient or source.")
  }
  scalar_path <- function(value) {
    is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
  }
  if (!scalar_path(input_dir) || !dir.exists(input_dir)) fail("input_dir must exist.")
  if (!scalar_path(output_dir)) fail("output_dir must be a non-empty path.")
  input_dir <- normalizePath(input_dir, winslash = "/", mustWork = TRUE)
  # Resolve existing ancestors before creating anything, including symlinks.
  resolve_path <- function(path) {
    path <- path.expand(path)
    if (file.exists(path)) return(normalizePath(path, winslash = "/", mustWork = TRUE))
    parent <- dirname(path)
    if (identical(parent, path)) fail("Cannot resolve output path: ", path)
    file.path(resolve_path(parent), basename(path))
  }
  output_dir <- resolve_path(output_dir)
  input_key <- tolower(sub("/+$", "", input_dir))
  output_key <- tolower(sub("/+$", "", output_dir))
  if (identical(input_key, output_key) || startsWith(output_key, paste0(input_key, "/"))) {
    fail("output_dir must be outside input_dir.")
  }
  if (file.exists(output_dir)) fail("output_dir already exists; choose a new folder: ", output_dir)

  read_csv <- function(path) {
    if (!file.exists(path) || dir.exists(path)) fail("Missing input file: ", path)
    result <- data.table::fread(path, colClasses = "character", na.strings = "", check.names = FALSE)
    if (anyDuplicated(names(result))) fail("Duplicate CSV column names: ", path)
    result
  }
  sample_table <- read_csv(file.path(input_dir, "Samples.csv"))
  if (!all(c("sample", "n_cells") %in% names(sample_table)) || !nrow(sample_table)) {
    fail("Samples.csv must contain sample, n_cells and at least one sample row.")
  }
  sample_ids <- sample_table[["sample"]]
  safe_name <- !is.na(sample_ids) & nzchar(sample_ids) & sample_ids == trimws(sample_ids) &
    !(sample_ids %in% c(".", "..")) & !grepl('[<>:"/\\\\|?*[:cntrl:]]', sample_ids) &
    !grepl("[. ]$", sample_ids) &
    !grepl("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\\.)", sample_ids, ignore.case = TRUE)
  if (!all(safe_name) || anyDuplicated(tolower(sample_ids))) {
    fail("Samples.csv must contain unique, portable sample identifiers.")
  }
  actual_ids <- basename(list.dirs(input_dir, recursive = FALSE, full.names = TRUE))
  if (!setequal(actual_ids, sample_ids)) fail("Sample folders must exactly match Samples.csv.")
  if (!is.null(samples)) {
    if (!column_names(samples) || !length(samples) || !all(samples %in% sample_ids)) {
      fail("samples must be unique sample identifiers present in Samples.csv.")
    }
    sample_table <- sample_table[which(sample_ids %in% samples)]
    sample_ids <- sample_table[["sample"]]
  }
  matrix_names <- c("Exp_data_UMIcounts.mtx", "Exp_data_TPM.mtx", "Exp_data_CPM.mtx")
  matrix_files <- vapply(sample_ids, function(sample) {
    folder <- file.path(input_dir, sample)
    found <- intersect(matrix_names, list.files(folder))
    if (length(found) != 1L) fail(sample, ": expected exactly one supported expression matrix.")
    for (name in c(found, "Cells.csv", "Genes.txt")) {
      path <- file.path(folder, name)
      if (!file.exists(path) || dir.exists(path)) fail("Missing input file: ", path)
    }
    found
  }, character(1))
  if (length(unique(matrix_files)) != 1L) fail("All selected samples must use the same expression scale.")

  # Leave the caller's random-number generator unchanged when used via source().
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) previous_seed <- get(".Random.seed", envir = .GlobalEnv)
  on.exit({
    if (had_seed) assign(".Random.seed", previous_seed, envir = .GlobalEnv)
    else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(list = ".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(as.integer(seed))

  parent <- dirname(output_dir)
  if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE)) fail("Cannot create output parent.")
  staging <- tempfile(pattern = ".downsample-", tmpdir = parent)
  if (!dir.create(staging)) fail("Cannot create staging directory.")
  # Only this freshly created sibling directory is owned/removed by the script.
  staging <- normalizePath(staging, winslash = "/", mustWork = TRUE)
  stopifnot(identical(dirname(staging), normalizePath(parent, winslash = "/", mustWork = TRUE)))
  on.exit(if (dir.exists(staging)) unlink(staging, recursive = TRUE), add = TRUE)
  report <- vector("list", length(sample_ids))
  output_cell_ids <- character()

  for (sample_index in seq_along(sample_ids)) {
    sample <- sample_ids[[sample_index]]
    message("[", sample_index, "/", length(sample_ids), "] Reading ", sample)
    source_dir <- file.path(input_dir, sample)
    cells <- read_csv(file.path(source_dir, "Cells.csv"))
    required <- c("cell_name", "sample", "cell_type", "complexity", "cell_subtype", "patient", "subclone", "source")
    missing <- setdiff(c(required, stratify_by), names(cells))
    if (length(missing)) fail(sample, ": missing Cells.csv columns: ", paste(missing, collapse = ", "))
    if (anyNA(cells[["cell_name"]]) || any(!nzchar(cells[["cell_name"]])) ||
        anyDuplicated(cells[["cell_name"]]) || anyNA(cells[["sample"]]) ||
        any(cells[["sample"]] != sample)) fail(sample, ": invalid cell identifiers or sample membership.")
    genes <- readLines(file.path(source_dir, "Genes.txt"), warn = FALSE, encoding = "UTF-8")
    expression <- Matrix::readMM(file.path(source_dir, matrix_files[[sample_index]]))
    if (nrow(expression) != length(genes) || ncol(expression) != nrow(cells)) {
      fail(sample, ": matrix dimensions do not match Genes.txt and Cells.csv.")
    }
    if (!length(genes) || anyNA(genes) || any(!nzchar(trimws(genes))) || anyDuplicated(genes)) {
      fail(sample, ": Genes.txt must contain non-empty, unique gene identifiers.")
    }
    expression <- Matrix::drop0(methods::as(methods::as(expression, "generalMatrix"), "CsparseMatrix"))
    if (!"x" %in% methods::slotNames(expression)) fail(sample, ": expression matrix must contain numeric values.")
    values <- expression@x
    if (anyNA(values) || any(!is.finite(values)) || any(values < 0) ||
        (matrix_files[[sample_index]] == "Exp_data_UMIcounts.mtx" && any(values != floor(values)))) {
      fail(sample, ": expression values must be finite, non-negative and integer for UMI counts.")
    }
    complexity <- diff(expression@p)
    eligible <- which(complexity >= min_genes)
    if (!length(eligible)) fail(sample, ": no cells pass min_genes = ", min_genes, ".")
    target <- min(as.integer(n_cells), length(eligible))
    if (length(stratify_by)) {
      # Missing labels form their own stratum. Multiple columns can define
      # finer strata; original annotations are used before any reset.
      grouped <- data.table::copy(cells[eligible, stratify_by, with = FALSE])
      strata <- grouped[, list(indices = list(eligible[.I])), by = stratify_by][["indices"]]
    } else strata <- list(eligible)
    sizes <- lengths(strata)
    exact <- target * sizes / sum(sizes)
    quotas <- as.integer(floor(exact))
    remaining <- target - sum(quotas)
    if (remaining > 0L) {
      extra <- order(-(exact - quotas), seq_along(quotas))[seq_len(remaining)]
      quotas[extra] <- quotas[extra] + 1L
    }
    selected <- sort(unlist(lapply(seq_along(strata), function(index) {
      pool <- strata[[index]]
      if (!quotas[[index]]) return(integer())
      pool[sample.int(length(pool), size = quotas[[index]], replace = FALSE)]
    }), use.names = FALSE))
    selected_cells <- data.table::copy(cells[selected])
    if (any(selected_cells[["cell_name"]] %in% output_cell_ids)) fail("Cell identifiers must be unique across samples.")
    output_cell_ids <- c(output_cell_ids, selected_cells[["cell_name"]])
    data.table::set(selected_cells, j = "complexity", value = complexity[selected])
    if (reset_annotations) {
      for (column in intersect(annotation_columns, names(selected_cells))) {
        data.table::set(selected_cells, j = column, value = rep(NA_character_, nrow(selected_cells)))
      }
      # Do not import prior clustering/embedding coordinates as fresh input.
      for (column in intersect(c("clust", "umap1", "umap2"), names(selected_cells))) {
        data.table::set(selected_cells, j = column, value = NULL)
      }
    }
    destination <- file.path(staging, sample)
    if (!dir.create(destination)) fail("Cannot create sample output: ", sample)
    Matrix::writeMM(expression[, selected, drop = FALSE], file.path(destination, matrix_files[[sample_index]]))
    if (!file.copy(file.path(source_dir, "Genes.txt"), file.path(destination, "Genes.txt"))) {
      fail("Cannot copy Genes.txt for ", sample)
    }
    data.table::fwrite(selected_cells, file.path(destination, "Cells.csv"), na = "")
    data.table::set(sample_table, i = sample_index, j = "n_cells", value = as.character(target))
    report[[sample_index]] <- data.frame(sample = sample, input_cells = nrow(cells),
      eligible_cells = length(eligible), output_cells = target, strata = length(strata),
      omitted_strata = sum(quotas == 0L), seed = seed, min_genes = min_genes,
      stratify_by = paste(stratify_by, collapse = ";"), reset_annotations = reset_annotations)
    message("  Retained ", target, " / ", length(eligible), " eligible cells (", nrow(cells), " input).")
    if (any(quotas == 0L)) message("  Note: ", sum(quotas == 0L), " strata received zero cells at this cap.")
    rm(expression, values, cells, selected_cells)
    invisible(gc())
  }
  report <- do.call(rbind, report)
  data.table::fwrite(sample_table, file.path(staging, "Samples.csv"), na = "")
  data.table::fwrite(report, file.path(staging, "downsampling_report.csv"), na = "")
  if (file.exists(output_dir) || !file.rename(staging, output_dir)) {
    fail("Cannot publish output; destination must not already exist: ", output_dir)
  }
  message("Import-ready subset written to: ", output_dir)
  invisible(report)
}

if (sys.nframe() == 0L) do.call(downsample_processed_data, settings)
