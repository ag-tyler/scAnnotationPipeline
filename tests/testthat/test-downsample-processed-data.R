downsample_script <- new.env(parent = globalenv())
sys.source(testthat::test_path("..", "..", "scripts", "downsample_processed_data.R"),
  envir = downsample_script)

make_downsample_input <- function(root, matrix_name = "Exp_data_UMIcounts.mtx") {
  dir.create(root)
  metadata <- build_samples(c("S1", "S2"))
  metadata[, n_cells := c(8L, 2L)]
  metadata[, patient := c("001", "002")]
  data.table::fwrite(metadata, file.path(root, "Samples.csv"), na = "")
  for (sample in metadata$sample) {
    n <- if (sample == "S1") 8L else 2L
    folder <- file.path(root, sample)
    dir.create(folder)
    # Unique columns expose any matrix/metadata ordering mistakes. Cell 8
    # fails min_genes=2, despite deliberately inaccurate stored complexity.
    expression <- Matrix::Matrix(rbind(seq_len(n), seq_len(n) * 10, rep(0, n)), sparse = TRUE)
    if (n == 8L) expression[2, 8] <- 0
    Matrix::writeMM(expression, file.path(folder, matrix_name))
    writeLines(c("G1", "G2", "G3"), file.path(folder, "Genes.txt"))
    cells <- data.table::data.table(cell_name = paste0(sample, "_", seq_len(n)),
      sample = sample, cell_type = rep(c("A", "B"), length.out = n), complexity = 999L,
      cell_subtype = "old subtype", patient = "001", subclone = "old clone", source = "colon",
      cell_type_pre_cna = "old type", original_label = "external label", raw_barcode = sprintf("%03d", seq_len(n)),
      clust = 1L, umap1 = 0, umap2 = 1)
    data.table::fwrite(cells, file.path(folder, "Cells.csv"))
  }
  root
}

test_that("downsampling preserves proportions, expression alignment and import structure", {
  root <- withr::local_tempdir()
  input <- make_downsample_input(file.path(root, "input"))
  files <- list.files(input, recursive = TRUE, full.names = TRUE)
  checksums <- tools::md5sum(files)
  set.seed(123)
  rng_before <- .Random.seed
  report <- downsample_script$downsample_processed_data(input, file.path(root, "output"),
    n_cells = 4, min_genes = 2)
  expect_identical(.Random.seed, rng_before)
  expect_equal(report$output_cells, c(4, 2))
  expect_equal(report$eligible_cells, c(7, 2))
  expect_identical(tools::md5sum(files), checksums)
  expect_true(check_prepared_data(file.path(root, "output"))$valid)
  metadata <- data.table::fread(file.path(root, "output", "Samples.csv"), colClasses = "character")
  expect_equal(metadata$n_cells, c("4", "2"))
  expect_equal(metadata$patient, c("001", "002"))
  cells <- data.table::fread(file.path(root, "output", "S1", "Cells.csv"),
    colClasses = "character", na.strings = "")
  original <- data.table::fread(file.path(input, "S1", "Cells.csv"))
  positions <- match(cells$cell_name, original$cell_name)
  expect_equal(as.integer(table(original$cell_type[positions])), c(2L, 2L))
  expect_true(all(diff(positions) > 0))
  expect_false(8L %in% positions)
  expect_equal(cells$raw_barcode, sprintf("%03d", positions))
  expression <- Matrix::readMM(file.path(root, "output", "S1", "Exp_data_UMIcounts.mtx"))
  expect_equal(as.matrix(expression), rbind(positions, positions * 10, rep(0, 4)), ignore_attr = TRUE)
  expect_equal(as.integer(cells$complexity), rep(2L, 4))
  expect_true(all(vapply(cells[, c("cell_type", "cell_subtype", "subclone", "cell_type_pre_cna"), with = FALSE],
    function(x) all(is.na(x)), logical(1))))
  expect_false(any(c("clust", "umap1", "umap2") %in% names(cells)))
  expect_equal(readLines(file.path(input, "S1", "Genes.txt")),
    readLines(file.path(root, "output", "S1", "Genes.txt")))
  downsample_script$downsample_processed_data(input, file.path(root, "repeat"), n_cells = 4, min_genes = 2)
  expect_identical(readBin(file.path(root, "output", "S1", "Cells.csv"), "raw", n = 10000),
    readBin(file.path(root, "repeat", "S1", "Cells.csv"), "raw", n = 10000))
})

test_that("sample selection, uniform sampling, multiple strata and reset controls work", {
  root <- withr::local_tempdir()
  input <- make_downsample_input(file.path(root, "input"), "Exp_data_TPM.mtx")
  downsample_script$downsample_processed_data(input, file.path(root, "uniform"),
    n_cells = 50, samples = "S2", stratify_by = NULL, min_genes = 0, reset_annotations = FALSE)
  expect_equal(basename(list.dirs(file.path(root, "uniform"), recursive = FALSE)), "S2")
  expect_true(check_prepared_data(file.path(root, "uniform"))$valid)
  cells <- data.table::fread(file.path(root, "uniform", "S2", "Cells.csv"))
  expect_equal(cells$cell_type, c("A", "B"))
  expect_true("umap1" %in% names(cells))
  # Missing labels and literal strings must not collide during stratification.
  cells <- data.table::fread(file.path(input, "S1", "Cells.csv"))
  cells$cell_type <- rep(c(NA, "NA"), 4)
  data.table::fwrite(cells, file.path(input, "S1", "Cells.csv"), na = "")
  downsample_script$downsample_processed_data(input, file.path(root, "stratified"),
    n_cells = 4, samples = "S1", min_genes = 0,
    stratify_by = c("cell_type", "cell_subtype"),
    annotation_columns = c("cell_type", "cell_subtype", "subclone", "cell_type_pre_cna", "original_label"))
  output <- data.table::fread(file.path(root, "stratified", "S1", "Cells.csv"), na.strings = "")
  positions <- match(output$cell_name, cells$cell_name)
  expect_equal(sum(is.na(cells$cell_type[positions])), 2L)
  expect_true(all(is.na(output$original_label)))
})

test_that("invalid input never overwrites sources or publishes partial output", {
  root <- withr::local_tempdir()
  input <- make_downsample_input(file.path(root, "input"))
  run <- downsample_script$downsample_processed_data
  expect_error(run(input, input), "outside input_dir")
  expect_error(run(input, file.path(input, "nested")), "outside input_dir")
  expect_error(run(input, root), "already exists")
  expect_error(run(input, file.path(root, "bad"), n_cells = 0), "positive integer")
  expect_error(run(input, file.path(root, "bad"), samples = "absent"), "sample identifiers")
  expect_error(run(input, file.path(root, "bad"), annotation_columns = "cell_name"), "cannot include")
  expect_error(run(input, file.path(root, "bad"), min_genes = 99), "no cells pass")
  expect_false(dir.exists(file.path(root, "bad")))
  # Fail after S1 has been staged: no partial dataset should be published.
  writeLines("G1", file.path(input, "S2", "Genes.txt"))
  expect_error(run(input, file.path(root, "bad"), n_cells = 1, min_genes = 0), "dimensions")
  expect_false(dir.exists(file.path(root, "bad")))
  expect_length(list.files(root, pattern = "^\\.downsample-", all.files = TRUE), 0L)
})
