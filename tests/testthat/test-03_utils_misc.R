test_that("sanitize_dataset_name accepts a plain, safe name", {
  expect_equal(sanitize_dataset_name("Werba2023_Pancreas"), "Werba2023_Pancreas")
  expect_equal(sanitize_dataset_name("  spaced out name  "), "spaced out name")
})

test_that("sanitize_dataset_name rejects empty / whitespace-only names", {
  expect_error(sanitize_dataset_name(""), "cannot be empty")
  expect_error(sanitize_dataset_name("   "), "cannot be empty")
})

test_that("sanitize_dataset_name rejects path separators and traversal", {
  expect_error(sanitize_dataset_name("../secrets"), "path separators")
  expect_error(sanitize_dataset_name("foo/bar"), "path separators")
  expect_error(sanitize_dataset_name("foo\\bar"), "path separators")
})

test_that("sanitize_dataset_name rejects absolute-path-looking input", {
  expect_error(sanitize_dataset_name("/etc/passwd"), "plain folder name")
  expect_error(sanitize_dataset_name("C:\\Windows"), "path separators|plain folder name")
  expect_error(sanitize_dataset_name("~root"), "plain folder name")
})

test_that("sanitize_dataset_name rejects disallowed characters", {
  expect_error(sanitize_dataset_name("data set!"), "letters, numbers")
  expect_error(sanitize_dataset_name("data;rm -rf"), "letters, numbers")
})

test_that("sanitize_dataset_name rejects Windows-reserved device names", {
  expect_error(sanitize_dataset_name("CON"), "reserved name")
  expect_error(sanitize_dataset_name("com1"), "reserved name") # case-insensitive
})

test_that("sum_dup_rows_sparse sums rows sharing the same name", {
  mat <- Matrix::Matrix(
    c(1, 2, 3,
      4, 5, 6,
      7, 8, 9),
    nrow = 3, byrow = TRUE, sparse = TRUE
  )
  rownames(mat) <- c("GENE_A", "GENE_B", "GENE_A")

  res <- sum_dup_rows_sparse(mat)

  expect_equal(nrow(res), 2)
  expect_setequal(rownames(res), c("GENE_A", "GENE_B"))
  expect_equal(as.numeric(res["GENE_A", ]), c(8, 10, 12)) # row1 + row3
  expect_equal(as.numeric(res["GENE_B", ]), c(4, 5, 6))
})

test_that("sum_dup_rows_sparse errors without rownames", {
  mat <- Matrix::Matrix(1:4, nrow = 2, sparse = TRUE)
  expect_error(sum_dup_rows_sparse(mat), "must have rownames")
})

test_that("map_ensembl_to_symbol_vector preserves input order and length", {
  hgnc <- make_mini_hgnc(n = 5)
  ids <- c(hgnc$ensembl_gene_id[3], "ENSG_NOT_REAL", hgnc$ensembl_gene_id[1])

  res <- map_ensembl_to_symbol_vector(ids, hgnc)

  expect_length(res, length(ids))
  expect_equal(res, c(hgnc$symbol[3], NA_character_, hgnc$symbol[1]))
})

test_that("map_ensembl_to_symbol_vector uses first match when reference has duplicate ids", {
  hgnc <- data.table::data.table(
    ensembl_gene_id = c("ENSG1", "ENSG1"),
    symbol = c("FIRST", "SECOND")
  )
  expect_equal(map_ensembl_to_symbol_vector("ENSG1", hgnc), "FIRST")
})

test_that("setup_selected_config initializes every sample under every section", {
  samples <- c("sample1", "sample2")
  cfg <- setup_selected_config(samples)

  expect_named(cfg, c("resolutions", "cna_ref_cells", "cna_pot_mal_cells",
                       "cna_ward_ref_cluster", "cna_thresholds"))
  for (section in names(cfg)) {
    expect_named(cfg[[section]], samples)
  }
  expect_equal(cfg$resolutions$sample1, 0.0)
  expect_identical(cfg$cna_ref_cells$sample1, list())
})

test_that("build_samples creates one canonical row per sample", {
  ids <- c("s1", "s2", "s3")
  dt <- build_samples(ids)

  expect_equal(nrow(dt), length(ids))
  expect_equal(dt$sample, ids)
  expect_false("id" %in% names(dt))
  # every other column exists and starts blank
  expect_true(all(is.na(dt$cancer_type)))
})

test_that("build_cells creates one row per cell id with expected columns", {
  ids <- c("cellA", "cellB")
  dt <- build_cells(ids)

  expect_equal(dt$cell_name, ids)
  expect_named(dt, c("cell_name", "sample", "cell_type", "complexity",
                      "cell_subtype", "patient", "subclone", "source"))
  expect_true(all(is.na(dt$cell_type)))
})

test_that("validate_samples_config preserves canonical sample identifiers", {
  config <- list(samples = list(make_valid_sample_entry("sample1")))

  validated <- validate_samples_config(config)

  expect_equal(validated$samples[[1]]$sample, "sample1")
})

test_that("validate_samples_config rejects the unsupported id key", {
  legacy_entry <- make_valid_sample_entry("sample1")
  legacy_entry$id <- legacy_entry$sample
  legacy_entry$sample <- NULL

  expect_error(
    validate_samples_config(list(samples = list(legacy_entry))),
    "unsupported 'id'; rename it to 'sample'"
  )
})

test_that("prevalidate_setup passes silently on a fully filled-in config", {
  dir <- withr::local_tempdir()
  write_samples_config(file.path(dir, "samples_config.yaml"), problem = "none")
  config <- list(config_files = list(samples = "samples_config.yaml"))

  expect_message(prevalidate_setup(dir, config), "Prevalidation passed")
})

test_that("prevalidate_setup rejects id-only configuration", {
  dir <- withr::local_tempdir()
  legacy_entry <- make_valid_sample_entry("sample1")
  legacy_entry$id <- legacy_entry$sample
  legacy_entry$sample <- NULL
  yaml::write_yaml(
    list(samples = list(legacy_entry)),
    file.path(dir, "samples_config.yaml")
  )
  config <- list(config_files = list(samples = "samples_config.yaml"))

  expect_error(
    prevalidate_setup(dir, config),
    "unsupported 'id'; rename it to 'sample'"
  )
})

test_that("prevalidate_setup fails hard on an empty samples list", {
  dir <- withr::local_tempdir()
  write_samples_config(file.path(dir, "samples_config.yaml"), problem = "empty")
  config <- list(config_files = list(samples = "samples_config.yaml"))

  expect_error(prevalidate_setup(dir, config), "no samples")
})

test_that("prevalidate_setup fails hard on a blank sample identifier", {
  dir <- withr::local_tempdir()
  write_samples_config(file.path(dir, "samples_config.yaml"), problem = "blank_sample")
  config <- list(config_files = list(samples = "samples_config.yaml"))

  expect_error(prevalidate_setup(dir, config), "empty 'sample'")
})

test_that("prevalidate_setup fails hard when a required attribute is missing", {
  dir <- withr::local_tempdir()
  write_samples_config(file.path(dir, "samples_config.yaml"), problem = "missing_attr")
  config <- list(config_files = list(samples = "samples_config.yaml"))

  expect_error(prevalidate_setup(dir, config), "missing the following necessary attributes")
})

test_that("prevalidate_setup rejects duplicate and unsafe sample identifiers", {
  config <- list(config_files = list(samples = "samples_config.yaml"))

  duplicate_dir <- withr::local_tempdir()
  yaml::write_yaml(
    list(samples = list(
      make_valid_sample_entry("sample1"),
      make_valid_sample_entry("sample1")
    )),
    file.path(duplicate_dir, "samples_config.yaml")
  )
  expect_error(
    prevalidate_setup(duplicate_dir, config),
    "Duplicate sample identifiers"
  )

  unsafe_dir <- withr::local_tempdir()
  yaml::write_yaml(
    list(samples = list(make_valid_sample_entry("../outside"))),
    file.path(unsafe_dir, "samples_config.yaml")
  )
  expect_error(
    prevalidate_setup(unsafe_dir, config),
    "not a safe directory identifier"
  )
})

test_that("validate_standardization passes on a well-formed sample", {
  dir <- withr::local_tempdir()
  fixture <- write_mini_sample(dir, "sample1", n_genes = 10, n_cells = 8)
  std_names <- list(expmat = "Exp_data_UMIcounts.mtx", genes = "Genes.txt", cells = "Cells.csv")

  # validate_standardization() reports success via cat() (Quarto callout
  # markup), not message()/warning(), so we assert on printed output.
  result <- NULL
  expect_output(
    result <- validate_standardization(dir, "sample1", std_names, strict = TRUE),
    "POST-VALIDATION PASSED"
  )
  expect_true(result$valid)
  expect_equal(result$expression_type, "counts")
  expect_equal(result$samples$sample1, list(genes = 10L, cells = 8L))
})

test_that("validate_standardization reports duplicate cells", {
  dir <- withr::local_tempdir()
  fixture <- write_mini_sample(dir, "sample1", n_genes = 10, n_cells = 8)
  std_names <- list(expmat = "Exp_data_UMIcounts.mtx", genes = "Genes.txt", cells = "Cells.csv")

  # Replace one cell with a duplicate while preserving the row count.
  cells <- fixture$cells
  cells <- rbind(cells[-1, ], cells[2, ])
  data.table::fwrite(cells, fixture$cells_path)

  result <- NULL
  expect_warning(
    result <- validate_standardization(dir, "sample1", std_names),
    "Post-validation failed"
  )
  expect_false(result$valid)
  expect_match(result$errors, "duplicate cell identifiers")
})

test_that("validate_standardization reports all missing files and can fail strictly", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "sample1"))
  std_names <- list(expmat = "Exp_data_UMIcounts.mtx", genes = "Genes.txt", cells = "Cells.csv")

  result <- NULL
  expect_warning(
    result <- validate_standardization(dir, "sample1", std_names),
    "Post-validation failed"
  )
  expect_match(result$errors, "missing required files")
  expect_match(result$errors, "Exp_data_UMIcounts.mtx")
  expect_error(
    validate_standardization(dir, "sample1", std_names, strict = TRUE),
    "Post-validation failed"
  )
})

test_that("expression type is explicit in the standardized matrix filename", {
  expect_equal(infer_standardized_expression_type("Exp_data_UMIcounts.mtx"), "counts")
  expect_equal(infer_standardized_expression_type("Exp_data_counts.mtx"), "counts")
  expect_equal(infer_standardized_expression_type("Exp_data_TPM.mtx"), "TPM")
  expect_equal(infer_standardized_expression_type("Exp_data_CPM.mtx"), "CPM")
  expect_true(is.na(infer_standardized_expression_type("expression.mtx")))
})

test_that("validate_standardization detects matrix/table dimension mismatches", {
  dir <- withr::local_tempdir()
  fixture <- write_mini_sample(dir, "sample1", n_genes = 10, n_cells = 8)
  std_names <- list(
    expmat = "Exp_data_UMIcounts.mtx",
    genes = "Genes.txt",
    cells = "Cells.csv"
  )
  writeLines(rownames(fixture$mat)[-1], fixture$genes_path)
  data.table::fwrite(fixture$cells[-1, ], fixture$cells_path)

  result <- NULL
  expect_warning(
    result <- validate_standardization(dir, "sample1", std_names),
    "Post-validation failed"
  )
  expect_true(any(grepl("Cells rows.*matrix columns", result$errors)))
  expect_true(any(grepl("Genes entries.*matrix rows", result$errors)))
})

test_that("validate_standardization enforces cell schema and sample assignment", {
  dir <- withr::local_tempdir()
  fixture <- write_mini_sample(dir, "sample1", n_genes = 10, n_cells = 8)
  std_names <- list(
    expmat = "Exp_data_UMIcounts.mtx",
    genes = "Genes.txt",
    cells = "Cells.csv"
  )
  cells <- data.table::copy(fixture$cells)
  cells$cell_type <- NULL
  cells$sample[[1]] <- "another_sample"
  cells$complexity[[2]] <- NA_real_
  data.table::fwrite(cells, fixture$cells_path)

  result <- NULL
  expect_warning(
    result <- validate_standardization(dir, "sample1", std_names),
    "Post-validation failed"
  )
  expect_true(any(grepl("missing columns: cell_type", result$errors)))
  expect_true(any(grepl("assignments to other samples", result$errors)))
  expect_true(any(grepl("complexity must contain finite", result$errors)))
})

test_that("validate_standardization rejects blank and duplicate gene identifiers", {
  dir <- withr::local_tempdir()
  fixture <- write_mini_sample(dir, "sample1", n_genes = 10, n_cells = 8)
  std_names <- list(
    expmat = "Exp_data_UMIcounts.mtx",
    genes = "Genes.txt",
    cells = "Cells.csv"
  )
  genes <- rownames(fixture$mat)
  genes[2] <- ""
  genes[3] <- genes[1]
  writeLines(genes, fixture$genes_path)

  result <- NULL
  expect_warning(
    result <- validate_standardization(dir, "sample1", std_names),
    "Post-validation failed"
  )
  expect_true(any(grepl("missing or blank", result$errors)))
  expect_true(any(grepl("duplicate identifiers", result$errors)))
})

test_that("validate_standardization checks expression values for the declared scale", {
  count_dir <- withr::local_tempdir()
  count_fixture <- write_mini_sample(
    count_dir,
    "sample1",
    n_genes = 10,
    n_cells = 8
  )
  count_matrix <- count_fixture$mat
  count_matrix@x[1] <- 1.5
  count_matrix@x[2] <- -1
  Matrix::writeMM(count_matrix, count_fixture$expmat_path)
  count_names <- list(
    expmat = "Exp_data_UMIcounts.mtx",
    genes = "Genes.txt",
    cells = "Cells.csv"
  )

  count_result <- NULL
  expect_warning(
    count_result <- validate_standardization(count_dir, "sample1", count_names),
    "Post-validation failed"
  )
  expect_true(any(grepl("count matrix contains non-integer", count_result$errors)))
  expect_true(any(grepl("negative values", count_result$errors)))

  tpm_dir <- withr::local_tempdir()
  tpm_names <- list(
    expmat = "Exp_data_TPM.mtx",
    genes = "Genes.txt",
    cells = "Cells.csv"
  )
  tpm_fixture <- write_mini_sample(
    tpm_dir,
    "sample1",
    n_genes = 10,
    n_cells = 8,
    std_names = tpm_names
  )
  Matrix::writeMM(tpm_fixture$mat / 3, tpm_fixture$expmat_path)

  tpm_result <- NULL
  expect_output(
    tpm_result <- validate_standardization(
      tpm_dir,
      "sample1",
      tpm_names,
      strict = TRUE
    ),
    "POST-VALIDATION PASSED"
  )
  expect_true(tpm_result$valid)
  expect_equal(tpm_result$expression_type, "TPM")
})

test_that("validate_standardization rejects an undeclared expression scale", {
  dir <- withr::local_tempdir()
  std_names <- list(
    expmat = "expression.mtx",
    genes = "Genes.txt",
    cells = "Cells.csv"
  )
  write_mini_sample(
    dir,
    "sample1",
    n_genes = 10,
    n_cells = 8,
    std_names = std_names
  )

  result <- NULL
  expect_warning(
    result <- validate_standardization(dir, "sample1", std_names),
    "Post-validation failed"
  )
  expect_true(any(grepl("does not declare a supported", result$errors)))
})

test_that("validate_standardization validates dataset-wide sample metadata", {
  dir <- withr::local_tempdir()
  first <- write_mini_sample(dir, "sample1", n_genes = 10, n_cells = 8)
  second <- write_mini_sample(dir, "sample2", n_genes = 10, n_cells = 7)
  second_cells <- data.table::copy(second$cells)
  second_cells$cell_name <- paste0("sample2_", second_cells$cell_name)
  data.table::fwrite(second_cells, second$cells_path)

  data.table::fwrite(
    data.table::data.table(
      sample = c("sample1", "sample2"),
      n_cells = c(nrow(first$cells), nrow(second$cells))
    ),
    file.path(dir, "Samples.csv")
  )
  std_names <- list(
    expmat = "Exp_data_UMIcounts.mtx",
    genes = "Genes.txt",
    cells = "Cells.csv",
    samples = "Samples.csv"
  )

  result <- NULL
  expect_output(
    result <- validate_standardization(
      dir,
      c("sample1", "sample2"),
      std_names,
      strict = TRUE
    ),
    "POST-VALIDATION PASSED"
  )
  expect_true(result$valid)

  samples <- data.table::fread(file.path(dir, "Samples.csv"))
  samples$n_cells[samples$sample == "sample2"] <- 999
  data.table::fwrite(samples, file.path(dir, "Samples.csv"))
  invalid <- NULL
  expect_warning(
    invalid <- validate_standardization(
      dir,
      c("sample1", "sample2"),
      std_names
    ),
    "Post-validation failed"
  )
  expect_true(any(grepl("n_cells does not match", invalid$errors)))
})

test_that("validate_standardization detects cell identifiers reused across samples", {
  dir <- withr::local_tempdir()
  write_mini_sample(dir, "sample1", n_genes = 10, n_cells = 8)
  write_mini_sample(dir, "sample2", n_genes = 10, n_cells = 8)
  std_names <- list(
    expmat = "Exp_data_UMIcounts.mtx",
    genes = "Genes.txt",
    cells = "Cells.csv"
  )

  result <- NULL
  expect_warning(
    result <- validate_standardization(
      dir,
      c("sample1", "sample2"),
      std_names
    ),
    "Post-validation failed"
  )
  expect_true(any(grepl("not unique across samples", result$errors)))
})
