# Prepared-input structure checks shared by the forthcoming import/load paths.
# Only the sample CSV is read; expression, cell, and gene contents are not read.

prepared_sample_columns <- function() {
  #' Required Prepared Sample CSV Headers
  #' @return Current sample metadata columns, followed by n_cells.
  c(names(build_samples(character())), "n_cells")
}


check_prepared_data <- function(processed_dir_path, std_names = NULL) {
  #' Check Prepared Input Structure
  #'
  #' @description Checks the sample CSV, exact sample-directory membership,
  #'   and required non-empty readable files. It does not audit matrix values,
  #'   dimensions, cell/gene contents, or scientific correctness. Never changes
  #'   inputs, prints a report, or persists validation state.
  #' @param processed_dir_path Directory containing the sample CSV and folders.
  #' @param std_names NULL to detect canonical new-import filenames and one
  #'   expression format, or a list with expmat, genes, cells, and samples
  #'   filenames for an existing workspace. Names must be distinct basenames.
  #' @return A prepared_data_check list: valid; errors (code, sample, path,
  #'   message); message (aggregate display text); samples (character metadata);
  #'   std_names; expression_type; and paths_list in CSV order (only if valid).

  errors <- data.frame(
    code = character(), sample = character(), path = character(),
    message = character(), stringsAsFactors = FALSE
  )
  samples <- NULL
  paths_list <- NULL
  expression_type <- NA_character_
  detected_names <- list(
    expmat = NULL, genes = "Genes.txt", cells = "Cells.csv", samples = "Samples.csv"
  )
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
  auto_names <- is.null(std_names)
  if (!auto_names) {
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
    expression_type <- infer_standardized_expression_type(detected_names$expmat)
    if (is.na(expression_type)) {
      add_error("unknown_expression_type", file.path(processed_dir_path, detected_names$expmat), "The configured matrix filename must declare counts, TPM, or CPM.")
    }
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
  canonical_matrices <- c("Exp_data_UMIcounts.mtx", "Exp_data_TPM.mtx", "Exp_data_CPM.mtx")
  found_matrices <- character()
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
    check_file(sample_dir, detected_names$genes, sample)
    check_file(sample_dir, detected_names$cells, sample)
    if (auto_names) {
      candidates <- intersect(canonical_matrices, basename(entries(sample_dir)))
      if (!length(candidates)) {
        add_error("missing_matrix", sample_dir, paste0("Sample '", sample, "': supply one matrix named ", paste(canonical_matrices, collapse = ", "), "."), sample)
      } else {
        found_matrices <- c(found_matrices, candidates)
        if (length(candidates) > 1L) {
          add_error("ambiguous_matrix", sample_dir, paste0("Sample '", sample, "': keep exactly one supported matrix; found ", paste(candidates, collapse = ", "), "."), sample)
        }
        for (filename in candidates) check_file(sample_dir, filename, sample)
      }
    } else {
      check_file(sample_dir, detected_names$expmat, sample)
    }
  }
  if (auto_names) {
    matrix_names <- unique(found_matrices)
    if (length(matrix_names) > 1L) {
      add_error("mixed_matrix_formats", processed_dir_path, paste0("Use one matrix filename/scale throughout the dataset; found ", paste(matrix_names, collapse = ", "), "."))
    } else if (length(matrix_names) == 1L) {
      detected_names$expmat <- matrix_names[[1]]
      expression_type <- infer_standardized_expression_type(detected_names$expmat)
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
