test_that("require_file passes silently when the file exists", {
  f <- withr::local_tempfile()
  writeLines("x", f)
  expect_true(isTRUE(require_file(f, "a test file")))
})

test_that("require_file stops with an actionable message when the file is missing", {
  missing_path <- file.path(withr::local_tempdir(), "does_not_exist.txt")
  expect_error(
    require_file(missing_path, "the HGNC reference", hint = "check resources_dir"),
    "Missing required file: the HGNC reference"
  )
  expect_error(require_file(missing_path, "the HGNC reference", hint = "check resources_dir"),
               "check resources_dir")
})

test_that("load_genes / load_expmat / load_cells round-trip a written sample", {
  dir <- withr::local_tempdir()
  fixture <- write_mini_sample(dir, "sample1", n_genes = 12, n_cells = 9)

  genes <- load_genes(fixture$genes_path)
  expmat <- load_expmat(fixture$expmat_path)
  cells <- load_cells(fixture$cells_path)

  expect_equal(genes, rownames(fixture$mat))
  expect_equal(dim(expmat), dim(fixture$mat))
  expect_equal(as.matrix(expmat), as.matrix(unname(fixture$mat)), ignore_attr = TRUE)
  expect_equal(nrow(cells), ncol(fixture$mat))
  expect_equal(cells$cell_name, fixture$cells$cell_name)
  expect_type(cells$cell_name, "character")
})

test_that("load_cells accepts only identifiers without warnings or changing the file", {
  path <- file.path(withr::local_tempdir(), "Cells.csv")
  original <- data.table::data.table(
    cell_name = c("003", "001", "002"), sample = "001"
  )
  data.table::fwrite(original, path)
  before <- tools::md5sum(path)

  expect_no_warning(loaded <- load_cells(path))
  expect_named(loaded, c("cell_name", "sample"))
  expect_identical(loaded$cell_name, original$cell_name)
  expect_identical(loaded$sample, original$sample)
  expect_identical(tools::md5sum(path), before)

  original[, cell_type_pre_cna := c("001", NA_character_, "T cell")]
  data.table::fwrite(original, path)
  expect_no_warning(loaded <- load_cells(path))
  expect_false("cell_type" %in% names(loaded))
  expect_identical(loaded$cell_type_pre_cna, original$cell_type_pre_cna)
})

test_that("load_cells preserves optional pre-CNA labels as text without adding absent columns", {
  path <- file.path(withr::local_tempdir(), "Cells.csv")
  scenarios <- list(absent = NULL, blank = rep(NA_character_, 3),
    populated = c("T_cell", "Epithelial", NA_character_),
    numeric_labels = c("001", "002", NA_character_),
    logical_labels = c("TRUE", "FALSE", NA_character_))
  for (scenario in names(scenarios)) {
    original <- data.table::data.table(cell_name = c("001", "002", "003"),
      sample = "sample1", cell_type = NA_character_, complexity = c(12L, 25L, 4L))
    labels <- scenarios[[scenario]]
    if (!is.null(labels)) original[, cell_type_pre_cna := labels]
    data.table::fwrite(original, path)
    before <- tools::md5sum(path)
    expect_no_warning(loaded <- load_cells(path))
    expect_identical(loaded$cell_name, original$cell_name)
    expect_identical(loaded$complexity, original$complexity)
    if (is.null(labels)) {
      expect_false("cell_type_pre_cna" %in% names(loaded))
    } else {
      expect_type(loaded$cell_type_pre_cna, "character")
      expect_identical(loaded$cell_type_pre_cna, labels)
    }
    expect_identical(tools::md5sum(path), before)
  }
})

test_that("load_samples reads sample ids as character even if numeric-looking", {
  dir <- withr::local_tempdir()
  samples_dt <- build_samples(c("001", "002"))
  path <- file.path(dir, "Samples.csv")
  data.table::fwrite(samples_dt, path)

  loaded <- load_samples(path)

  expect_type(loaded$sample, "character")
  expect_equal(loaded$sample, c("001", "002")) # would become 1/2 if read as numeric
})

test_that("load_expdt melts a wide CNA matrix into long format", {
  dir <- withr::local_tempdir()
  cna_wide <- data.table::data.table(
    gene = c("GENE1", "GENE2"),
    chr = c("1", "1"),
    start_pos = c(100, 200),
    cell_01 = c(0.1, -0.2),
    cell_02 = c(0.3, 0.0)
  )
  path <- file.path(dir, "cna_matrix.csv")
  data.table::fwrite(cna_wide, path)

  expdt <- load_expdt(path)

  expect_named(expdt, c("gene", "chr", "start_pos", "cell_name", "cna"))
  expect_equal(nrow(expdt), nrow(cna_wide) * 2) # 2 genes x 2 cells
  expect_true(all(c("cell_01", "cell_02") %in% expdt$cell_name))
})
