# Non-empty placeholders are intentional: structure checks must not read their
# scientifically invalid contents, and must not require sample YAML or scripts.
write_prepared_structure <- function(root, sample_ids = c("002", "001"),
                                     matrix_name = "Exp_data_UMIcounts.mtx",
                                     std_names = NULL) {
  if (is.null(std_names)) std_names <- list(
    expmat = matrix_name, genes = "Genes.txt", cells = "Cells.csv", samples = "Samples.csv"
  )
  metadata <- build_samples(sample_ids)
  metadata$patient <- rep("0007", length(sample_ids))
  metadata$n_cells <- rep("12", length(sample_ids))
  metadata$notes <- rep('site, "quoted"', length(sample_ids))
  data.table::fwrite(metadata, file.path(root, std_names$samples))
  for (sample in unique(sample_ids)) {
    sample_dir <- file.path(root, sample)
    dir.create(sample_dir, showWarnings = FALSE)
    for (filename in unlist(std_names[c("expmat", "genes", "cells")])) {
      writeLines("not scientifically valid data", file.path(sample_dir, filename))
    }
  }
  metadata
}

test_that("P01 checks canonical formats and preserves CSV order and text metadata", {
  for (scale in c("UMIcounts", "TPM", "CPM")) {
    root <- withr::local_tempdir(pattern = "prepared data ")
    matrix_name <- paste0("Exp_data_", scale, ".mtx")
    write_prepared_structure(root, matrix_name = matrix_name)
    checked <- check_prepared_data(root)

    expect_s3_class(checked, "prepared_data_check")
    expect_true(checked$valid, info = checked$message)
    expect_equal(nrow(checked$errors), 0L)
    expect_equal(checked$message, "Input structure check passed.")
    expect_equal(checked$samples$sample, c("002", "001"))
    expect_equal(checked$samples$patient, c("0007", "0007"))
    expect_equal(checked$samples$notes, rep('site, "quoted"', 2L))
    expect_true(all(vapply(checked$samples, is.character, logical(1))))
    expect_true(all(is.na(checked$samples$age)))
    expect_equal(checked$std_names$expmat, matrix_name)
    expect_equal(checked$expression_type, if (scale == "UMIcounts") "counts" else scale)
    expect_equal(basename(checked$paths_list$sample_dir_paths), c("002", "001"))
    expect_equal(checked$paths_list$expmat_file_paths,
                 file.path(root, c("002", "001"), matrix_name))
  }
})

test_that("P01 aggregates missing folders, missing files, and unexpected folders", {
  root <- withr::local_tempdir()
  metadata <- write_prepared_structure(root, "present")
  metadata <- rbind(metadata, data.table::copy(metadata))
  metadata$sample <- c("present", "missing")
  data.table::fwrite(metadata, file.path(root, "Samples.csv"))
  unlink(file.path(root, "present", "Cells.csv"))
  file.create(file.path(root, "present", "Genes.txt"))
  dir.create(file.path(root, "unexpected"))
  checked <- check_prepared_data(root)

  expect_false(checked$valid)
  expect_null(checked$paths_list)
  expect_setequal(checked$errors$code, c(
    "missing_file", "empty_file", "missing_sample_directory", "unexpected_sample_directory"
  ))
  expect_true(all(nzchar(checked$errors$path)))
  expect_match(checked$message, "present", fixed = TRUE)
  expect_match(checked$message, "Cells.csv", fixed = TRUE)
  expect_match(checked$message, "Genes.txt", fixed = TRUE)
  expect_match(checked$message, "missing", fixed = TRUE)
  expect_match(checked$message, "unexpected", fixed = TRUE)
})

test_that("P01 CSV parsing preserves UTF-8, BOMs, literal NA, and quoted newlines", {
  root <- withr::local_tempdir()
  metadata <- write_prepared_structure(root, "M\u00fcller_01")
  metadata$notes <- 'Colon, "ascending"\nsecond line'
  metadata$patient <- "\u03b1-0007"
  metadata$site <- "M\u00fcnchen"
  metadata$cancer_type <- "NA"
  data.table::fwrite(metadata, file.path(root, "Samples.csv"), bom = TRUE, quote = TRUE)
  checked <- check_prepared_data(root)
  expect_true(checked$valid, info = checked$message)
  expect_equal(checked$samples$notes, metadata$notes)
  expect_equal(checked$samples$patient, metadata$patient)
  expect_equal(checked$samples$site, metadata$site)
  expect_identical(checked$samples$cancer_type, "NA")
  expect_identical(checked$samples$age, NA_character_)
})

test_that("P01 rejects unusable roots and missing, empty, or directory CSV paths", {
  root <- withr::local_tempdir()
  for (path in list(NULL, NA_character_, character(), c(root, root), " ")) {
    expect_equal(check_prepared_data(path)$errors$code, "invalid_directory")
  }
  expect_equal(check_prepared_data(file.path(root, "absent"))$errors$code, "missing_directory")
  expect_equal(check_prepared_data(root)$errors$code, "missing_file")
  csv_path <- file.path(root, "Samples.csv")
  file.create(csv_path)
  expect_equal(check_prepared_data(root)$errors$code, "empty_file")
  unlink(csv_path)
  dir.create(csv_path)
  expect_equal(check_prepared_data(root)$errors$code, "not_a_file")
})

test_that("P01 rejects malformed tables, missing/duplicate headers, and absent rows", {
  root <- withr::local_tempdir()
  metadata <- write_prepared_structure(root, "s1")
  csv_path <- file.path(root, "Samples.csv")
  data.table::fwrite(metadata[, c("patient", "n_cells") := NULL], csv_path)
  checked <- check_prepared_data(root)
  expect_true("missing_columns" %in% checked$errors$code)
  expect_match(checked$message, "patient, n_cells", fixed = TRUE)
  data.table::fwrite(metadata[0], csv_path)
  expect_true("no_samples" %in% check_prepared_data(root)$errors$code)
  writeLines(c("sample,sample", "s1,s1"), csv_path)
  expect_true("invalid_columns" %in% check_prepared_data(root)$errors$code)
  writeLines(c("sample,patient", "s1,p1", "s2,p2,extra", "s3,p3"), csv_path)
  checked <- check_prepared_data(root)
  expect_true("unreadable_csv" %in% checked$errors$code)
  expect_null(checked$samples)
  expect_null(checked$paths_list)
  writeLines("patient,n_cells\np1,2", csv_path)
  expect_true("missing_columns" %in% check_prepared_data(root)$errors$code)
})

test_that("P01 malformed CSV cannot silently shift fields into implicit row names", {
  root <- withr::local_tempdir()
  metadata <- write_prepared_structure(root, "s1")
  # A consistently extra field is normally accepted by read.csv as row names.
  # Keep the rest of the row correct so accidental field shifting would pass.
  header <- paste(names(metadata), collapse = ",")
  row <- paste(c("implicit", "s1", rep("", ncol(metadata) - 1L)), collapse = ",")
  writeLines(c(header, row), file.path(root, "Samples.csv"))
  checked <- check_prepared_data(root)
  expect_false(checked$valid)
  expect_equal(checked$errors$code, "unreadable_csv")
  expect_match(checked$message, "same number of fields", fixed = TRUE)
  expect_null(checked$samples)
})

test_that("P01 rejects blank, unsafe, reserved, and duplicate sample identifiers", {
  root <- withr::local_tempdir()
  metadata <- write_prepared_structure(root, "s1")
  invalid <- c(NA, "", " ", ".", "..", "../outside", "a/b", "a\\b", "a:b",
               "a*", "a?", 'a"', "a<", "a>", "a|", "a\t", " a", "a ", "a.",
               "CON", "nul.txt", "COM1", "LPT9.csv")
  metadata <- metadata[rep(1L, length(invalid))]
  metadata$sample <- invalid
  data.table::fwrite(metadata, file.path(root, "Samples.csv"))
  checked <- check_prepared_data(root)
  expect_equal(sum(checked$errors$code == "invalid_sample"), length(invalid))
  expect_null(checked$paths_list)
  metadata <- metadata[1:3]
  metadata$sample <- c("s1", "s1", "S1")
  data.table::fwrite(metadata, file.path(root, "Samples.csv"))
  checked <- check_prepared_data(root)
  expect_equal(sum(checked$errors$code == "duplicate_sample"), 2L)
})

test_that("P01 exact capitalization is enforced even on case-insensitive filesystems", {
  root <- withr::local_tempdir()
  metadata <- write_prepared_structure(root, "sample")
  metadata$sample <- "Sample"
  data.table::fwrite(metadata, file.path(root, "Samples.csv"))
  checked <- check_prepared_data(root)
  expect_true(all(c("missing_sample_directory", "unexpected_sample_directory") %in% checked$errors$code))

  metadata$sample <- "sample"
  data.table::fwrite(metadata, file.path(root, "Samples.csv"))
  unlink(file.path(root, "sample", "Cells.csv"))
  writeLines("placeholder", file.path(root, "sample", "cells.csv"))
  checked <- check_prepared_data(root)
  expect_true("missing_file" %in% checked$errors$code)
  expect_match(checked$message, "Cells.csv", fixed = TRUE)
  unlink(file.path(root, "Samples.csv"))
  data.table::fwrite(metadata, file.path(root, "samples.csv"))
  expect_equal(check_prepared_data(root)$errors$code, "missing_file")
})

test_that("P01 reports missing, ambiguous, mixed, and non-file matrices", {
  root <- withr::local_tempdir()
  write_prepared_structure(root, c("s1", "s2"))
  matrix_path <- file.path(root, "s1", "Exp_data_UMIcounts.mtx")
  unlink(matrix_path)
  expect_true("missing_matrix" %in% check_prepared_data(root)$errors$code)
  dir.create(matrix_path)
  expect_true("not_a_file" %in% check_prepared_data(root)$errors$code)
  unlink(matrix_path, recursive = TRUE)
  writeLines("placeholder", file.path(root, "s1", "Exp_data_TPM.mtx"))
  expect_true("mixed_matrix_formats" %in% check_prepared_data(root)$errors$code)
  writeLines("placeholder", matrix_path)
  checked <- check_prepared_data(root)
  expect_true("ambiguous_matrix" %in% checked$errors$code)
  expect_match(checked$message, "s1", fixed = TRUE)
})

test_that("P01 configured legacy filenames retain exact paths without renaming", {
  root <- withr::local_tempdir()
  filenames <- list(expmat = "legacy_counts.mtx", genes = "symbols.txt",
                    cells = "barcodes.csv", samples = "sample_metadata.csv")
  write_prepared_structure(root, "s1", std_names = filenames)
  checked <- check_prepared_data(root, filenames)
  expect_true(checked$valid, info = checked$message)
  expect_identical(checked$std_names, filenames)
  expect_equal(checked$paths_list$cell_file_paths, file.path(root, "s1", "barcodes.csv"))
  for (invalid in list(list(), "bad", modifyList(filenames, list(genes = "../outside")),
                       modifyList(filenames, list(cells = "symbols.txt")))) {
    expect_equal(check_prepared_data(root, invalid)$errors$code, "invalid_filenames")
  }
  filenames$expmat <- "expression.mtx"
  expect_true("unknown_expression_type" %in% check_prepared_data(root, filenames)$errors$code)
})

test_that("P01 only reads the sample CSV and does not modify inputs or accept parser warnings", {
  root <- withr::local_tempdir()
  write_prepared_structure(root, "s1")
  files <- list.files(root, recursive = TRUE, full.names = TRUE)
  before <- tools::md5sum(files)
  checker <- check_prepared_data
  checker_env <- new.env(parent = environment(checker))
  environment(checker) <- checker_env
  checker_env$read_prepared_samples <- function(path) {
    expect_equal(path, file.path(root, "Samples.csv"))
    read_prepared_samples(path)
  }
  for (name in c("readLines", "read.csv", "load_cells", "load_genes", "load_expmat",
                 "readMM", "validate_standardization")) {
    checker_env[[name]] <- function(...) stop("Input contents must not be scanned")
  }
  expect_true(checker(root)$valid)
  expect_identical(tools::md5sum(files), before)
  expect_identical(list.files(root, recursive = TRUE, full.names = TRUE), files)
  checker_env$read_prepared_samples <- function(...) warning("synthetic incomplete CSV read")
  checked <- checker(root)
  expect_equal(checked$errors$code, "unreadable_csv")
  expect_match(checked$message, "synthetic incomplete CSV read", fixed = TRUE)
})

test_that("P01 reports unreadable files and directories without content reads", {
  root <- withr::local_tempdir()
  write_prepared_structure(root, "s1")
  checker <- check_prepared_data
  checker_env <- new.env(parent = environment(checker))
  environment(checker) <- checker_env
  blocked_path <- file.path(root, "s1", "Genes.txt")
  checker_env$file.access <- function(names, mode) {
    ifelse(names == blocked_path, -1L, base::file.access(names, mode))
  }
  expect_equal(checker(root)$errors$code, "unreadable_file")
  blocked_path <- file.path(root, "s1")
  expect_equal(checker(root)$errors$code, "unreadable_directory")
  blocked_path <- root
  expect_equal(checker(root)$errors$code, "unreadable_directory")
})
