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

test_that("build_samples creates one row per id with 'sample' and 'id' populated", {
  ids <- c("s1", "s2", "s3")
  dt <- build_samples(ids)

  expect_equal(nrow(dt), length(ids))
  expect_equal(dt$sample, ids)
  expect_equal(dt$id, ids)
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

test_that("prevalidate_setup passes silently on a fully filled-in config", {
  dir <- withr::local_tempdir()
  write_samples_config(file.path(dir, "samples_config.yaml"), problem = "none")
  config <- list(config_files = list(samples = "samples_config.yaml"))

  expect_message(prevalidate_setup(dir, config), "Prevalidation passed")
})

test_that("prevalidate_setup fails hard on an empty samples list", {
  dir <- withr::local_tempdir()
  write_samples_config(file.path(dir, "samples_config.yaml"), problem = "empty")
  config <- list(config_files = list(samples = "samples_config.yaml"))

  expect_error(prevalidate_setup(dir, config), "no samples")
})

test_that("prevalidate_setup fails hard on a blank sample id", {
  dir <- withr::local_tempdir()
  write_samples_config(file.path(dir, "samples_config.yaml"), problem = "blank_id")
  config <- list(config_files = list(samples = "samples_config.yaml"))

  expect_error(prevalidate_setup(dir, config), "empty 'id'")
})

test_that("prevalidate_setup fails hard when a required attribute is missing", {
  dir <- withr::local_tempdir()
  write_samples_config(file.path(dir, "samples_config.yaml"), problem = "missing_attr")
  config <- list(config_files = list(samples = "samples_config.yaml"))

  expect_error(prevalidate_setup(dir, config), "missing the following necessary attributes")
})

test_that("validate_standardization passes on a well-formed sample", {
  dir <- withr::local_tempdir()
  fixture <- write_mini_sample(dir, "sample1", n_genes = 10, n_cells = 8)
  std_names <- list(expmat = "Exp_data_UMIcounts.mtx", genes = "Genes.txt", cells = "Cells.csv")

  # validate_standardization() reports success via cat() (Quarto callout
  # markup), not message()/warning(), so we assert on printed output.
  expect_output(
    validate_standardization(dir, "sample1", std_names),
    "POST-VALIDATION PASSED"
  )
})

test_that("validate_standardization warns on dimension mismatch and duplicate cells", {
  dir <- withr::local_tempdir()
  fixture <- write_mini_sample(dir, "sample1", n_genes = 10, n_cells = 8)
  std_names <- list(expmat = "Exp_data_UMIcounts.mtx", genes = "Genes.txt", cells = "Cells.csv")

  # Corrupt Cells.csv: drop a row (dimension mismatch) and duplicate another.
  cells <- fixture$cells
  cells <- rbind(cells[-1, ], cells[2, ])
  data.table::fwrite(cells, fixture$cells_path)

  expect_warning(
    validate_standardization(dir, "sample1", std_names),
    "Post-validation flagged issues"
  )
})

test_that("validate_standardization warns on missing files instead of erroring", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "sample1"))
  std_names <- list(expmat = "Exp_data_UMIcounts.mtx", genes = "Genes.txt", cells = "Cells.csv")

  expect_warning(
    validate_standardization(dir, "sample1", std_names),
    "Post-validation flagged issues"
  )
})
