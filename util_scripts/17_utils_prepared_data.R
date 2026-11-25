# Prepared-input structure checks shared by the import and load workflows.
# Read sample metadata, matrix dimensions, and gene/cell record counts. Matrix
# values, identifiers, expression state, and scientific alignment are not audited.

prepared_sample_columns <- function() {
  #' Required Prepared Sample CSV Headers
  #' @return Current sample metadata columns, followed by n_cells.
  c(names(build_samples(character())), "n_cells")
}


prepared_input_filenames <- function(template_path = NULL) {
  #' Read Default Prepared Filenames From the Dataset Template
  #' @param template_path Explicit template, or NULL to find the application
  #'   root by searching upward from the working directory.
  #' @return The template's std_names list. No input files are inspected.
  if (is.null(template_path)) {
    root <- getwd()
    while (!file.exists(file.path(root, "general_config.yaml"))) {
      parent <- dirname(root)
      if (identical(parent, root)) {
        stop("Cannot find the dataset configuration template. Supply std_names explicitly or run from the application directory.", call. = FALSE)
      }
      root <- parent
    }
    template_path <- file.path(root, "templates", "dataset_config_template.yaml")
  }
  template <- yaml::read_yaml(template_path)
  if (!is.list(template)) stop("The dataset configuration template must be a YAML mapping.", call. = FALSE)
  if (is.null(template$std_names)) list() else template$std_names
}


.prepared_matrix_dimensions <- function(path) {
  connection <- file(path, open = "rt")
  on.exit(close(connection), add = TRUE)
  banner <- strsplit(tolower(trimws(readLines(connection, n = 1L, warn = FALSE))), "[[:space:]]+")[[1]]
  if (length(banner) != 5L || !identical(banner[1:2], c("%%matrixmarket", "matrix")) ||
      !banner[[3]] %in% c("coordinate", "array")) {
    stop("Expected a Matrix Market matrix header.", call. = FALSE)
  }
  repeat {
    line <- readLines(connection, n = 1L, warn = FALSE)
    if (!length(line)) stop("Matrix Market dimensions are missing.", call. = FALSE)
    line <- trimws(line)
    if (!nzchar(line) || startsWith(line, "%")) next
    parts <- strsplit(line, "[[:space:]]+")[[1]]
    dimensions <- suppressWarnings(as.numeric(parts[1:2]))
    if (length(parts) < 2L || any(!is.finite(dimensions)) ||
        any(dimensions < 0 | dimensions != floor(dimensions))) {
      stop("Matrix Market row and column counts must be non-negative integers.", call. = FALSE)
    }
    return(stats::setNames(dimensions, c("rows", "columns")))
  }
}

.prepared_record_count <- function(path, header = FALSE, sep = "\t") {
  connection <- file(path, open = "rt")
  on.exit(close(connection), add = TRUE)
  # count.fields scans records without allocating full metadata tables. A
  # quoted multiline field has NA continuation entries and one completed record.
  fields <- utils::count.fields(connection, sep = sep, quote = '"',
    comment.char = "", blank.lines.skip = TRUE)
  max(0, sum(!is.na(fields)) - as.integer(header))
}

check_prepared_data <- function(processed_dir_path, std_names = NULL) {
  #' Check Prepared Input Structure
  #'
  #' @description Checks the sample CSV, exact sample-directory membership,
  #'   required non-empty readable files, and gene/cell counts against matrix
  #'   rows/columns. It does not audit matrix values, expression state, IDs,
  #'   positional alignment, or scientific correctness. Never changes
  #'   inputs, prints a report, or persists validation state.
  #' @param processed_dir_path Directory containing the sample CSV and folders.
  #' @param std_names A list with expmat, genes, cells, and samples filenames.
  #'   NULL reads defaults from the dataset template; existing workspaces should
  #'   supply their own saved list. Names must be distinct portable basenames.
  #' @return A prepared_data_check list: valid; errors (code, sample, path,
  #'   message); message (aggregate display text); samples (character metadata);
  #'   std_names; expression_type (always NA for compatibility, never inferred);
  #'   and paths_list in CSV order (only if valid).

  errors <- data.frame(
    code = character(), sample = character(), path = character(),
    message = character(), stringsAsFactors = FALSE
  )
  samples <- NULL
  paths_list <- NULL
  expression_type <- NA_character_
  detected_names <- list()
  add_error <- function(code, path, message, sample = NA_character_) {
    errors[nrow(errors) + 1L, ] <<- list(code, sample, path, message)
  }
  result <- function() {
    valid <- nrow(errors) == 0L
    structure(list(
      valid = valid,
      errors = errors,
      message = if (valid) "Input structure check passed." else paste(
        "Input structure check failed:",
        paste0("- ", errors$message, " [", errors$path, "]", collapse = "\n"),
        sep = "\n"
      ),
      samples = samples, std_names = detected_names,
      expression_type = expression_type,
      paths_list = if (valid) paths_list else NULL
    ), class = "prepared_data_check")
  }
  scalar_text <- function(x) {
    is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
  }
  portable_name <- function(x) {
    !is.na(x) & nzchar(x) & x == trimws(x) &
      !(x %in% c(".", "..")) &
      !grepl('[<>:"/\\\\|?*[:cntrl:]]', x) &
      !grepl("[. ]$", x) &
      !grepl("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\\.)", x, ignore.case = TRUE)
  }
  entries <- function(path) {
    list.files(path, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  }
  check_file <- function(parent, filename, sample = NA_character_) {
    path <- file.path(parent, filename)
    subject <- if (is.na(sample)) "Dataset" else paste0("Sample '", sample, "'")
    if (!(filename %in% basename(entries(parent)))) {
      add_error("missing_file", path, paste0(subject, ": supply the required file '", filename, "' with this exact capitalization."), sample)
      return(FALSE)
    }
    info <- file.info(path)
    if (is.na(info$isdir) || info$isdir) {
      add_error("not_a_file", path, paste0(subject, ": '", filename, "' must be a file, not a directory."), sample)
      return(FALSE)
    }
    if (file.access(path, 4L) != 0L) {
      add_error("unreadable_file", path, paste0(subject, ": make '", filename, "' readable by the R process."), sample)
      return(FALSE)
    }
    if (is.na(info$size) || info$size == 0) {
      add_error("empty_file", path, paste0(subject, ": supply a non-empty '", filename, "' file."), sample)
      return(FALSE)
    }
    TRUE
  }

  if (!scalar_text(processed_dir_path)) {
    add_error("invalid_directory", "", "Select one prepared-data directory.")
    return(result())
  }
  if (!dir.exists(processed_dir_path)) {
    add_error("missing_directory", processed_dir_path, "Prepared-data directory does not exist; select an existing directory.")
    return(result())
  }
  if (file.access(processed_dir_path, 4L) != 0L) {
    add_error("unreadable_directory", processed_dir_path, "Make the prepared-data directory readable by the R process.")
    return(result())
  }
  if (is.null(std_names)) std_names <- prepared_input_filenames()
  keys <- c("expmat", "genes", "cells", "samples")
  if (!is.list(std_names) || !all(vapply(keys, function(key) {
    value <- std_names[[key]]
    scalar_text(value) && portable_name(value)
  }, logical(1)))) {
    add_error("invalid_filenames", processed_dir_path, "Configure expmat, genes, cells, and samples as portable filenames without directory components.")
    return(result())
  }
  detected_names <- std_names[keys]
  if (anyDuplicated(tolower(unlist(detected_names, use.names = FALSE)))) {
    add_error("invalid_filenames", processed_dir_path, "Configure distinct matrix, gene, cell, and sample filenames.")
    return(result())
  }

  samples_path <- file.path(processed_dir_path, detected_names$samples)
  if (!check_file(processed_dir_path, detected_names$samples)) return(result())
  samples <- tryCatch(
    read_prepared_samples(samples_path), error = identity, warning = identity
  )
  if (inherits(samples, "condition")) {
    add_error("unreadable_csv", samples_path, paste0("Repair the sample CSV: ", conditionMessage(samples)))
    samples <- NULL
    return(result())
  }
  missing_columns <- setdiff(prepared_sample_columns(), names(samples))
  if (length(missing_columns)) {
    add_error("missing_columns", samples_path, paste("Add the required sample CSV headers:", paste(missing_columns, collapse = ", ")))
  }
  if (anyDuplicated(names(samples)) || any(!nzchar(trimws(names(samples))))) {
    add_error("invalid_columns", samples_path, "Give every sample CSV column a non-empty, unique header.")
  }
  if (nrow(samples) == 0L) {
    add_error("no_samples", samples_path, "Add at least one sample row to the sample CSV.")
  }
  if (!("sample" %in% names(samples))) return(result())

  sample_names <- samples$sample
  safe_samples <- portable_name(sample_names)
  for (i in which(!safe_samples)) {
    add_error("invalid_sample", samples_path, paste0("CSV data row ", i, ": supply a non-empty portable sample identifier without surrounding whitespace, path separators, reserved names, or a trailing period."), sample_names[[i]])
  }
  duplicates <- unique(sample_names[duplicated(tolower(sample_names)) & !is.na(sample_names)])
  for (sample in duplicates) {
    add_error("duplicate_sample", samples_path, paste0("Sample '", sample, "': identifiers must be unique, including when capitalization is ignored."), sample)
  }

  root_entries <- entries(processed_dir_path)
  sample_dirs <- root_entries[dir.exists(root_entries)]
  actual_names <- basename(sample_dirs)
  expected_names <- unique(sample_names[safe_samples])
  for (sample in setdiff(actual_names, expected_names)) {
    add_error("unexpected_sample_directory", file.path(processed_dir_path, sample), paste0("Directory '", sample, "' is absent from the sample CSV; add its sample row or remove this directory from the prepared input."), sample)
  }
  for (sample in expected_names) {
    sample_dir <- file.path(processed_dir_path, sample)
    if (!(sample %in% actual_names)) {
      add_error("missing_sample_directory", sample_dir, paste0("Sample '", sample, "': supply its same-named directory with this exact capitalization."), sample)
      next
    }
    if (file.access(sample_dir, 4L) != 0L) {
      add_error("unreadable_directory", sample_dir, paste0("Sample '", sample, "': make this directory readable by the R process."), sample)
      next
    }
    genes_ok <- check_file(sample_dir, detected_names$genes, sample)
    cells_ok <- check_file(sample_dir, detected_names$cells, sample)
    matrix_ok <- check_file(sample_dir, detected_names$expmat, sample)
    if (!matrix_ok || !(genes_ok || cells_ok)) next
    matrix_path <- file.path(sample_dir, detected_names$expmat)
    dimensions <- tryCatch(.prepared_matrix_dimensions(matrix_path), error = identity, warning = identity)
    if (inherits(dimensions, "condition")) {
      add_error("matrix_dimensions_unreadable", matrix_path,
        paste0("Sample '", sample, "': could not read matrix dimensions: ", conditionMessage(dimensions)), sample)
      next
    }
    for (kind in c("genes", "cells")) {
      if ((kind == "genes" && !genes_ok) || (kind == "cells" && !cells_ok)) next
      path <- file.path(sample_dir, detected_names[[kind]])
      is_cells <- kind == "cells"
      count <- tryCatch(.prepared_record_count(path, header = is_cells,
        sep = if (is_cells) "," else "\t"), error = identity, warning = identity)
      if (inherits(count, "condition")) {
        add_error(paste0(kind, "_count_unreadable"), path,
          paste0("Sample '", sample, "': could not count ", kind, " records: ", conditionMessage(count)), sample)
        next
      }
      expected <- dimensions[[if (is_cells) "columns" else "rows"]]
      if (count != expected) {
        add_error(if (is_cells) "cell_count_mismatch" else "gene_count_mismatch", path,
          sprintf("Sample '%s': %s (%s) do not match matrix %s (%s).", sample,
            if (is_cells) "Cell metadata rows" else "Gene entries", count,
            if (is_cells) "columns" else "rows", expected), sample)
      }
    }
  }
  if (nrow(errors) == 0L) {
    ordered_dirs <- file.path(processed_dir_path, sample_names)
    paths_list <- list(
      sample_dir_paths = ordered_dirs,
      cell_file_paths = file.path(ordered_dirs, detected_names$cells),
      expmat_file_paths = file.path(ordered_dirs, detected_names$expmat),
      genes_file_paths = file.path(ordered_dirs, detected_names$genes)
    )
  }
  result()
}
