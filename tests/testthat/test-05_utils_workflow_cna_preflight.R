make_cna_preflight_fixture <- function(
  cell_types = c("Reference", "Reference", "TumorLike", "TumorLike"),
  n_genes = 30L
) {
  dataset_dir <- withr::local_tempdir(.local_envir = parent.frame())
  sample_name <- "sample1"
  cell_names <- paste0("cell_", seq_along(cell_types))
  cells <- data.table::data.table(
    cell_name = cell_names,
    sample = sample_name,
    cell_type = cell_types,
    umap1 = seq_along(cell_types),
    umap2 = rev(seq_along(cell_types)),
    clust = rep(c("0", "1"), length.out = length(cell_types))
  )
  genes <- paste0("GENE", seq_len(n_genes))
  expmat <- Matrix::Matrix(
    matrix(
      seq_len(n_genes * length(cell_names)),
      nrow = n_genes,
      dimnames = list(genes, cell_names)
    ),
    sparse = TRUE
  )
  selected_config <- list(
    resolutions = list(sample1 = 0.5),
    cna_ref_cells = list(sample1 = "Reference"),
    cna_pot_mal_cells = list(sample1 = "TumorLike")
  )
  gene_positions <- data.table::data.table(
    symbol = genes,
    chromosome_name = "01",
    start_position = seq_len(n_genes)
  )

  cache_save_data(
    cells,
    "cells_filt_clust_res_0.5_sample1.qs2",
    dataset_dir
  )
  cache_save_data(expmat, "expmat_filt_sample1.qs2", dataset_dir)

  list(
    dataset_dir = dataset_dir,
    sample_name = sample_name,
    cells = cells,
    expmat = expmat,
    selected_config = selected_config,
    gene_positions = gene_positions
  )
}


test_that("CNA preflight reports an eligible sample with useful counts", {
  skip_if_not_installed("qs2")
  fx <- make_cna_preflight_fixture()
  workflow_env <- environment(cna_sample_preflight)
  original_cache_loader <- get("cache_load_data", envir = workflow_env)
  withr::defer(assign("cache_load_data", original_cache_loader, envir = workflow_env))
  loaded_files <- character()
  assign(
    "cache_load_data",
    function(data_file_name, ...) {
      loaded_files <<- c(loaded_files, data_file_name)
      original_cache_loader(data_file_name, ...)
    },
    envir = workflow_env
  )

  result <- cna_sample_preflight(
    fx$sample_name,
    fx$selected_config,
    fx$dataset_dir,
    fx$gene_positions
  )

  expect_s3_class(result, "cna_preflight")
  expect_true(result$eligible, info = result$reason)
  expect_identical(result$status, "eligible")
  expect_identical(result$counts$reference, 2L)
  expect_identical(result$counts$configured_candidate, 2L)
  expect_identical(result$counts$unassigned, 0L)
  expect_identical(result$counts$positioned_genes, 30L)
  expect_equal(nrow(result$ref_cells), 2L)
  expect_identical(
    loaded_files,
    c("cells_filt_clust_res_0.5_sample1.qs2", "expmat_filt_sample1.qs2")
  )
})


test_that("CNA preflight rejects all-NA annotations because references are absent", {
  skip_if_not_installed("qs2")
  fx <- make_cna_preflight_fixture(rep(NA_character_, 4))
  workflow_env <- environment(cna_sample_preflight)
  original_cache_loader <- get("cache_load_data", envir = workflow_env)
  withr::defer(assign("cache_load_data", original_cache_loader, envir = workflow_env))
  loaded_files <- character()
  assign(
    "cache_load_data",
    function(data_file_name, ...) {
      loaded_files <<- c(loaded_files, data_file_name)
      original_cache_loader(data_file_name, ...)
    },
    envir = workflow_env
  )

  result <- cna_sample_preflight(
    fx$sample_name,
    fx$selected_config,
    fx$dataset_dir,
    fx$gene_positions,
    validate_expression = FALSE
  )

  expect_false(result$eligible)
  expect_identical(result$status, "ineligible")
  expect_identical(result$counts$reference, 0L)
  expect_identical(result$counts$unassigned, 4L)
  expect_match(result$reason, "reference cells")
  expect_identical(loaded_files, "cells_filt_clust_res_0.5_sample1.qs2")
})


test_that("CNA preflight rejects zero candidate cells and too few references", {
  skip_if_not_installed("qs2")
  fx <- make_cna_preflight_fixture(c("Reference", "Immune", "Immune", "Immune"))

  result <- cna_sample_preflight(
    fx$sample_name,
    fx$selected_config,
    fx$dataset_dir,
    fx$gene_positions,
    validate_expression = FALSE
  )

  expect_false(result$eligible)
  expect_identical(result$counts$reference, 1L)
  expect_identical(result$counts$candidate_total, 0L)
  expect_match(result$reason, "at least 2")
  expect_match(result$reason, "potentially malignant or unassigned")
})


test_that("CNA preflight distinguishes incomplete setup from ineligible data", {
  skip_if_not_installed("qs2")
  fx <- make_cna_preflight_fixture()
  fx$selected_config$cna_ref_cells$sample1 <- character()

  result <- cna_sample_preflight(
    fx$sample_name,
    fx$selected_config,
    fx$dataset_dir,
    fx$gene_positions,
    validate_expression = FALSE
  )

  expect_false(result$eligible)
  expect_identical(result$status, "incomplete")
  expect_match(result$reason, "Reference cell types are not configured")
})


test_that("CNA preflight requires enough genes with genomic positions", {
  skip_if_not_installed("qs2")
  fx <- make_cna_preflight_fixture(n_genes = 20L)

  result <- cna_sample_preflight(
    fx$sample_name,
    fx$selected_config,
    fx$dataset_dir,
    fx$gene_positions
  )

  expect_false(result$eligible)
  expect_identical(result$status, "ineligible")
  expect_identical(result$counts$positioned_genes, 20L)
  expect_match(result$reason, "at least 21")
})


test_that("CNA preflight honors an explicit persisted omission", {
  skip_if_not_installed("qs2")
  fx <- make_cna_preflight_fixture()
  state <- new_pipeline_state("dataset1", fx$sample_name)
  state <- transition_pipeline_step(
    state,
    "annotation",
    "completed",
    sample = fx$sample_name,
    force = TRUE
  )
  state <- transition_pipeline_step(
    state,
    "cna_configuration",
    "skipped",
    sample = fx$sample_name,
    reason = "CNA is not warranted for this sample.",
    force = TRUE
  )

  result <- cna_sample_preflight(
    fx$sample_name,
    fx$selected_config,
    fx$dataset_dir,
    fx$gene_positions,
    pipeline_state = state,
    validate_expression = FALSE
  )

  expect_false(result$eligible)
  expect_identical(result$status, "omitted")
  expect_match(result$reason, "explicitly omitted")
  expect_match(result$reason, "not warranted")
})
