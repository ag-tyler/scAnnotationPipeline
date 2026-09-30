# tests/testthat/test-05_utils_workflow_cna.R


make_cna_threshold_fixture <- function(dataset_dir) {
  cells <- data.table::data.table(
    cell_name = sprintf("cell_%02d", 1:6),
    sample = "sample1",
    cell_type = c(
      "TumorLike",
      "TumorLike",
      "TumorLike",
      "TumorLike",
      "TumorLike",
      "Immune"
    )
  )
  
  selected_config <- list(
    resolutions = list(
      sample1 = 0.5
    ),
    cna_pot_mal_cells = list(
      sample1 = "TumorLike"
    ),
    cna_thresholds = list(
      sample1 = list(
        list(
          m_x = 0.7,
          m_y = 0.7,
          nm_x = 0.3,
          nm_y = 0.3
        ),
        list(
          m_x = 0.7,
          m_y = 0.7,
          nm_x = 0.3,
          nm_y = 0.3
        )
      )
    )
  )
  
  # Subclone 1:
  # cell_01 -> malignant
  # cell_03 -> malignant (and also malignant for subclone 2 = collision)
  # cell_04 -> safely non-malignant
  # cell_05 -> gray zone
  # cell_06 -> malignant-shaped signal, but its cell type is not eligible
  sig1 <- data.table::data.table(
    cell_name = cells$cell_name,
    cna_cor = c(
      0.9,
      0.1,
      0.9,
      0.1,
      0.5,
      0.9
    ),
    cna_signal = c(
      0.9,
      0.1,
      0.9,
      0.1,
      0.5,
      0.9
    )
  )
  
  # Subclone 2:
  # cell_02 -> malignant
  # cell_03 -> malignant again = collision
  sig2 <- data.table::data.table(
    cell_name = cells$cell_name,
    cna_cor = c(
      0.1,
      0.9,
      0.9,
      0.1,
      0.5,
      0.1
    ),
    cna_signal = c(
      0.1,
      0.9,
      0.9,
      0.1,
      0.5,
      0.1
    )
  )
  
  cache_save_data(
    cells,
    "cells_filt_clust_res_0.5_sample1.qs2",
    dataset_dir
  )
  
  cache_save_data(
    sig1,
    "cna_sig_cor_sample1_subclone_1.qs2",
    dataset_dir
  )
  
  cache_save_data(
    sig2,
    "cna_sig_cor_sample1_subclone_2.qs2",
    dataset_dir
  )
  
  list(
    cells = cells,
    selected_config = selected_config
  )
}


make_cna_visualization_fixture <- function(dataset_dir) {
  set.seed(2026)
  
  sample_name <- "sample1"
  
  # Two chromosomes with 22 genes each. This deliberately clears the
  # n > 20 chromosome filter used by cna_clustering_and_heatmaps() and
  # summary_cna_heatmap().
  n_genes_per_chr <- 22L
  n_genes <- 2L * n_genes_per_chr
  
  genes <- sprintf("GENE%03d", seq_len(n_genes))
  chr <- rep(
    c("01", "02"),
    each = n_genes_per_chr
  )
  
  cell_names <- sprintf("cell_%02d", 1:6)
  
  # Cell roles:
  #   cell_01 = reference
  #   cell_02 = potentially malignant
  #   cell_03 = potentially malignant
  #   cell_04 = unassigned
  #   cell_05 = another non-malignant type
  #   cell_06 = potentially malignant
  cells <- data.table::data.table(
    cell_name = cell_names,
    sample = sample_name,
    cell_type = c(
      "Reference",
      "TumorLike",
      "TumorLike",
      "Unassigned",
      "Immune",
      "TumorLike"
    ),
    umap1 = c(-2, -1, 0, 1, 2, 3),
    umap2 = c(1, 2, -1, 0, -2, 1)
  )
  
  # Build non-degenerate CNA profiles. Randomness is seeded above, so this
  # remains deterministic while avoiding perfect correlations / zero variance.
  cna_values <- matrix(
    stats::rnorm(
      n_genes * length(cell_names),
      mean = 0,
      sd = 0.25
    ),
    nrow = n_genes,
    ncol = length(cell_names),
    dimnames = list(genes, cell_names)
  )
  
  # Give the potentially malignant cells visibly different CNA structure.
  cna_values[1:10, "cell_02"] <-
    cna_values[1:10, "cell_02"] + 0.6
  
  cna_values[23:34, "cell_03"] <-
    cna_values[23:34, "cell_03"] - 0.5
  
  cna_values[c(5:12, 28:35), "cell_06"] <-
    cna_values[c(5:12, 28:35), "cell_06"] + 0.45
  
  cna_wide <- data.table::data.table(
    gene = genes,
    chr = chr,
    start_pos = c(
      seq_len(n_genes_per_chr) * 1e6,
      seq_len(n_genes_per_chr) * 1e6
    )
  )
  
  for (cell in cell_names) {
    cna_wide[[cell]] <- cna_values[, cell]
  }
  
  selected_config <- list(
    resolutions = list(
      sample1 = 0.5
    ),
    
    cna_ref_cells = list(
      sample1 = "Reference"
    ),
    
    cna_pot_mal_cells = list(
      sample1 = "TumorLike"
    ),
    
    cna_thresholds = list(
      sample1 = list(
        list(
          m_x = 0.7,
          m_y = 0.7,
          nm_x = 0.3,
          nm_y = 0.3
        )
      )
    )
  )
  
  # Signal/correlation values for preview_cna_summary().
  #
  # cell_02: malignant
  # cell_03: gray zone -> Unassigned
  # cell_04: malignant even though originally Unassigned; Unassigned is
  #          intentionally an allowed CNA candidate type
  # cell_06: safely non-malignant
  sig_cor <- data.table::data.table(
    sample = sample_name,
    subclone = 1L,
    cell_name = cell_names,
    cna_signal = c(
      0.1,  # Reference
      0.9,  # Malignant
      0.5,  # Gray zone
      0.9,  # Malignant
      0.1,  # Immune
      0.1   # Non-malignant
    ),
    cna_cor = c(
      0.1,
      0.9,
      0.5,
      0.9,
      0.1,
      0.1
    ),
    ct = c(
      "Reference",
      "Candidate malignant",
      NA_character_,
      "Candidate malignant",
      NA_character_,
      NA_character_
    )
  )
  
  cache_save_data(
    cells,
    "cells_filt_clust_res_0.5_sample1.qs2",
    dataset_dir
  )
  
  cache_save_data(
    cna_wide,
    "cna_matrix_sample1.qs2",
    dataset_dir
  )
  
  cache_save_data(
    sig_cor,
    "cna_sig_cor_sample1_subclone_1.qs2",
    dataset_dir
  )
  
  list(
    sample_name = sample_name,
    cells = cells,
    cna_wide = cna_wide,
    selected_config = selected_config
  )
}


test_that("apply_cna_thresholds assigns unique malignant subclones and gray-zone cells", {
  skip_if_not_installed("qs2")
  
  dataset_dir <- withr::local_tempdir()
  fx <- make_cna_threshold_fixture(dataset_dir)
  
  res <- apply_cna_thresholds(
    sample_name = "sample1",
    dataset_dir_path = dataset_dir,
    selected_config = fx$selected_config,
    save = FALSE
  )
  
  value_for <- function(cell, column) {
    res[[column]][match(cell, res$cell_name)]
  }
  
  # Unique malignant assignment.
  expect_equal(
    value_for("cell_01", "cell_type"),
    "Malignant"
  )
  
  expect_identical(
    value_for("cell_01", "subclone"),
    1L
  )
  
  expect_equal(
    value_for("cell_02", "cell_type"),
    "Malignant"
  )
  
  expect_identical(
    value_for("cell_02", "subclone"),
    2L
  )
  
  # Safely below non-malignant thresholds for both subclones:
  # preserve the pre-CNA annotation.
  expect_equal(
    value_for("cell_04", "cell_type"),
    "TumorLike"
  )
  
  expect_true(
    is.na(value_for("cell_04", "subclone"))
  )
  
  # Intermediate/gray-zone signal.
  expect_equal(
    value_for("cell_05", "cell_type"),
    "Unassigned"
  )
  
  expect_true(
    is.na(value_for("cell_05", "subclone"))
  )
  
  # Immune is not in cna_pot_mal_cells, so it must never
  # receive a malignant subclone.
  expect_false(
    identical(
      value_for("cell_06", "cell_type"),
      "Malignant"
    )
  )
  
  expect_true(
    is.na(value_for("cell_06", "subclone"))
  )
})


test_that("apply_cna_thresholds keeps multi-subclone collisions malignant without a subclone", {
  skip_if_not_installed("qs2")
  
  dataset_dir <- withr::local_tempdir()
  fx <- make_cna_threshold_fixture(dataset_dir)
  
  res <- apply_cna_thresholds(
    sample_name = "sample1",
    dataset_dir_path = dataset_dir,
    selected_config = fx$selected_config,
    save = FALSE
  )
  
  idx <- match("cell_03", res$cell_name)
  
  expect_equal(
    res$cell_type[idx],
    "Malignant"
  )
  
  expect_true(
    is.na(res$subclone[idx])
  )
})


test_that("apply_cna_thresholds with save FALSE does not modify cached cells", {
  skip_if_not_installed("qs2")
  
  dataset_dir <- withr::local_tempdir()
  fx <- make_cna_threshold_fixture(dataset_dir)
  
  apply_cna_thresholds(
    sample_name = "sample1",
    dataset_dir_path = dataset_dir,
    selected_config = fx$selected_config,
    save = FALSE
  )
  
  cached <- cache_load_data(
    "cells_filt_clust_res_0.5_sample1.qs2",
    dataset_dir
  )
  
  expect_equal(
    cached$cell_type,
    fx$cells$cell_type
  )
  
  expect_false(
    "subclone" %in% names(cached)
  )
})


test_that("apply_cna_thresholds with save TRUE persists assignments", {
  skip_if_not_installed("qs2")
  
  dataset_dir <- withr::local_tempdir()
  fx <- make_cna_threshold_fixture(dataset_dir)
  
  res <- apply_cna_thresholds(
    sample_name = "sample1",
    dataset_dir_path = dataset_dir,
    selected_config = fx$selected_config,
    save = TRUE
  )
  
  cached <- cache_load_data(
    "cells_filt_clust_res_0.5_sample1.qs2",
    dataset_dir
  )
  
  expect_equal(
    cached$cell_type,
    res$cell_type
  )
  
  expect_equal(
    cached$subclone,
    res$subclone
  )
})


test_that("compute_signal_cor_cna caches metrics and cell classifications", {
  skip_if_not_installed("qs2")
  
  dataset_dir <- withr::local_tempdir()
  
  set.seed(99)
  
  n_genes <- 30
  cell_names <- sprintf(
    "cell_%02d",
    1:6
  )
  
  gene_names <- sprintf(
    "GENE%02d",
    seq_len(n_genes)
  )
  
  values <- matrix(
    stats::rnorm(
      n_genes * length(cell_names),
      sd = 0.15
    ),
    nrow = n_genes,
    dimnames = list(
      gene_names,
      cell_names
    )
  )
  
  # Engineer cells 1/2 to have a similar CNA profile.
  values[1:8, "cell_01"] <-
    values[1:8, "cell_01"] + 2
  
  values[1:8, "cell_02"] <-
    values[1:8, "cell_02"] + 2
  
  cna_mat <- data.table::data.table(
    gene = gene_names,
    chr = rep(
      c("1", "2"),
      each = n_genes / 2
    ),
    start_pos = seq_len(n_genes) * 1e6
  )
  
  for (cell in cell_names) {
    cna_mat[[cell]] <- values[, cell]
  }
  
  hc <- stats::hclust(
    stats::dist(t(values)),
    method = "ward.D2"
  )
  
  cut <- stats::cutree(
    hc,
    k = 2
  )
  
  target_cluster <- unname(
    cut["cell_01"]
  )
  
  candidate_cells <- names(cut)[
    cut == target_cluster
  ]
  
  selected_config <- list(
    cna_ward_ref_cluster = list(
      sample1 = list(
        list(
          k = 2,
          cluster = target_cluster
        )
      )
    )
  )
  
  ref_cells <- data.table::data.table(
    sample = "sample1",
    cell_name = c(
      "cell_05",
      "cell_06"
    ),
    cell_type = "Reference"
  )
  
  cache_save_data(
    cna_mat,
    "cna_matrix_sample1.qs2",
    dataset_dir
  )
  
  cache_save_data(
    hc,
    "hclust_sample1.qs2",
    dataset_dir
  )
  
  compute_signal_cor_cna(
    sample_name = "sample1",
    subclone_i = 1,
    ref_cells = ref_cells,
    selected_config = selected_config,
    dataset_dir_path = dataset_dir
  )
  
  expect_true(
    cache_check_exists(
      "cna_sig_cor_sample1_subclone_1.qs2",
      dataset_dir
    )
  )
  
  res <- cache_load_data(
    "cna_sig_cor_sample1_subclone_1.qs2",
    dataset_dir
  )
  
  expect_true(
    all(
      c(
        "sample",
        "subclone",
        "cell_name",
        "cna_signal",
        "cna_cor",
        "ct"
      ) %in% names(res)
    )
  )
  
  expect_true(
    all(res$sample == "sample1")
  )
  
  expect_true(
    all(res$subclone == 1)
  )
  
  candidate_idx <- match(
    candidate_cells,
    res$cell_name
  )
  
  expect_true(
    all(
      res$ct[candidate_idx] ==
        "Candidate malignant"
    )
  )
  
  reference_cells <- setdiff(
    ref_cells$cell_name,
    candidate_cells
  )
  
  if (length(reference_cells) > 0) {
    ref_idx <- match(
      reference_cells,
      res$cell_name
    )
    
    expect_true(
      all(
        res$ct[ref_idx] ==
          "Reference"
      )
    )
  }
  
  expect_true(
    all(is.finite(res$cna_signal))
  )
  
  expect_true(
    all(is.finite(res$cna_cor))
  )
})


test_that("batch_compute_cna_and_heatmaps skips samples without CNA configuration", {
  dataset_dir <- withr::local_tempdir()
  
  sample_dir <- file.path(
    dataset_dir,
    "processed_data",
    "sample1"
  )
  
  dir.create(
    sample_dir,
    recursive = TRUE
  )
  
  paths_list <- list(
    sample_dir_paths = sample_dir
  )
  
  selected_config <- list(
    resolutions = list(
      sample1 = 0.5
    ),
    cna_ref_cells = list(
      sample1 = character()
    ),
    cna_pot_mal_cells = list(
      sample1 = character()
    )
  )
  
  res <- batch_compute_cna_and_heatmaps(
    paths_list = paths_list,
    dataset_dir_path = dataset_dir,
    results_dir_path = file.path(
      dataset_dir,
      "results"
    ),
    selected_config = selected_config,
    gene_positions = data.table::data.table()
  )
  
  expect_length(
    res$processed,
    0
  )
  
  expect_equal(
    res$skipped,
    "sample1"
  )
})


test_that("batch_compute_cna_and_heatmaps skips configured samples with missing cache", {
  skip_if_not_installed("qs2")
  
  dataset_dir <- withr::local_tempdir()
  
  sample_dir <- file.path(
    dataset_dir,
    "processed_data",
    "sample1"
  )
  
  dir.create(
    sample_dir,
    recursive = TRUE
  )
  
  paths_list <- list(
    sample_dir_paths = sample_dir
  )
  
  selected_config <- list(
    resolutions = list(
      sample1 = 0.5
    ),
    cna_ref_cells = list(
      sample1 = "Reference"
    ),
    cna_pot_mal_cells = list(
      sample1 = "TumorLike"
    )
  )
  
  res <- batch_compute_cna_and_heatmaps(
    paths_list = paths_list,
    dataset_dir_path = dataset_dir,
    results_dir_path = file.path(
      dataset_dir,
      "results"
    ),
    selected_config = selected_config,
    gene_positions = data.table::data.table()
  )
  
  expect_length(
    res$processed,
    0
  )
  
  expect_equal(
    res$skipped,
    "sample1 (Missing Cache)"
  )
})


test_that("batch_compute_cna_and_heatmaps forwards dataset_dir_path to CNA helpers", {
  dataset_dir <- withr::local_tempdir()
  
  results_dir <- file.path(
    dataset_dir,
    "results"
  )
  
  sample_dir <- file.path(
    dataset_dir,
    "processed_data",
    "sample1"
  )
  
  dir.create(
    sample_dir,
    recursive = TRUE
  )
  
  cells <- data.table::data.table(
    cell_name = c(
      "cell_01",
      "cell_02"
    ),
    cell_type = c(
      "Reference",
      "TumorLike"
    )
  )
  
  expmat <- Matrix::Matrix(
    matrix(
      1:8,
      nrow = 4,
      dimnames = list(
        paste0("GENE", 1:4),
        cells$cell_name
      )
    ),
    sparse = TRUE
  )
  
  paths_list <- list(
    sample_dir_paths = sample_dir
  )
  
  selected_config <- list(
    resolutions = list(
      sample1 = 0.5
    ),
    cna_ref_cells = list(
      sample1 = "Reference"
    ),
    cna_pot_mal_cells = list(
      sample1 = "TumorLike"
    )
  )
  
  calls <- new.env(
    parent = emptyenv()
  )
  
  calls$compute_called <- FALSE
  calls$heatmap_called <- FALSE
  
  test_env <- new.env(
    parent = environment(batch_compute_cna_and_heatmaps)
  )
  
  test_env$cache_check_exists <- function(
    file_name,
    dataset_dir_path
  ) {
    !startsWith(
      file_name,
      "cna_matrix_"
    )
  }
  
  test_env$cache_load_data <- function(
    file_name,
    dataset_dir_path
  ) {
    if (startsWith(
      file_name,
      "cells_filt_"
    )) {
      return(
        data.table::copy(cells)
      )
    }
    
    if (startsWith(
      file_name,
      "expmat_filt_"
    )) {
      return(expmat)
    }
    
    stop(
      "Unexpected test cache request: ",
      file_name
    )
  }
  
  test_env$compute_cna_and_cache <- function(
    expmat,
    gene_positions,
    ref_cells,
    sample_name,
    dataset_dir_path
  ) {
    calls$compute_called <- TRUE
    calls$compute_dataset_dir <-
      dataset_dir_path
    
    invisible(NULL)
  }
  
  test_env$cna_clustering_and_heatmaps <- function(
    ref_cells,
    sample_name,
    selected_config,
    cna_plots_dir_path,
    dataset_dir_path
  ) {
    calls$heatmap_called <- TRUE
    calls$heatmap_dataset_dir <-
      dataset_dir_path
    
    invisible(NULL)
  }
  
  batch_test <-
    batch_compute_cna_and_heatmaps
  
  environment(batch_test) <- test_env
  
  res <- batch_test(
    paths_list = paths_list,
    dataset_dir_path = dataset_dir,
    results_dir_path = results_dir,
    selected_config = selected_config,
    gene_positions = data.table::data.table(
      symbol = paste0("GENE", 1:4),
      chromosome_name = "1",
      start_position = 1:4
    )
  )
  
  expect_true(
    calls$compute_called
  )
  
  expect_true(
    calls$heatmap_called
  )
  
  expect_identical(
    calls$compute_dataset_dir,
    dataset_dir
  )
  
  expect_identical(
    calls$heatmap_dataset_dir,
    dataset_dir
  )
  
  expect_equal(
    res$processed,
    "sample1"
  )
  
  expect_length(
    res$skipped,
    0
  )
})

test_that("cna_clustering_and_heatmaps caches hclust and writes the heatmap", {
  skip_if_not_installed("qs2")
  skip_if_not_installed("dbscan")
  skip_if_not_installed("ggdendro")
  skip_if_not_installed("cowplot")
  skip_if_not_installed("randomcoloR")
  skip_if_not_installed("RColorBrewer")
  skip_if_not_installed("scales")
  
  dataset_dir <- withr::local_tempdir()
  
  cna_plots_dir <- file.path(
    dataset_dir,
    "results",
    "sample1",
    "3_cna_plots"
  )
  
  dir.create(
    cna_plots_dir,
    recursive = TRUE
  )
  
  fx <- make_cna_visualization_fixture(
    dataset_dir
  )
  
  ref_cells <- fx$cells[
    fx$cells$cell_type == "Reference",
  ]
  
  expect_message(
    cna_clustering_and_heatmaps(
      ref_cells = ref_cells,
      sample_name = fx$sample_name,
      selected_config = fx$selected_config,
      cna_plots_dir_path = cna_plots_dir,
      dataset_dir_path = dataset_dir
    ),
    "Run ward clustering"
  )
  
  # Main workflow side effects.
  expect_true(
    cache_check_exists(
      "hclust_sample1.qs2",
      dataset_dir
    )
  )
  
  expect_true(
    file.exists(
      file.path(
        cna_plots_dir,
        "hclust.png"
      )
    )
  )
  
  expect_gt(
    file.info(
      file.path(
        cna_plots_dir,
        "hclust.png"
      )
    )$size,
    0
  )
  
  hc <- cache_load_data(
    "hclust_sample1.qs2",
    dataset_dir
  )
  
  expect_s3_class(
    hc,
    "hclust"
  )
  
  # cna_clustering_and_heatmaps() intentionally clusters only
  # potentially malignant + Unassigned cells.
  expected_clustered_cells <- fx$cells$cell_name[
    fx$cells$cell_type %in%
      c(
        fx$selected_config$cna_pot_mal_cells$sample1,
        "Unassigned"
      )
  ]
  
  expect_setequal(
    hc$labels,
    expected_clustered_cells
  )
  
  expect_equal(
    length(hc$order),
    length(expected_clustered_cells)
  )
  
  expect_equal(
    sort(hc$order),
    seq_along(expected_clustered_cells)
  )
})

test_that("preview_cna_summary returns complete previews without modifying cached cells", {
  skip_if_not_installed("qs2")
  skip_if_not_installed("randomcoloR")
  skip_if_not_installed("RColorBrewer")
  skip_if_not_installed("scales")
  skip_if_not_installed("cowplot")
  
  dataset_dir <- withr::local_tempdir()
  
  fx <- make_cna_visualization_fixture(
    dataset_dir
  )
  
  cells_file <-
    "cells_filt_clust_res_0.5_sample1.qs2"
  
  before <- cache_load_data(
    cells_file,
    dataset_dir
  )
  
  # Deep copy matters because data.table uses reference semantics.
  before <- data.table::copy(before)
  
  res <- preview_cna_summary(
    sample_name = fx$sample_name,
    dataset_dir_path = dataset_dir,
    selected_config = fx$selected_config
  )
  
  # The function actually returns five objects.
  expect_named(
    res,
    c(
      "cells_filt",
      "summary_heatmap",
      "pre_scatter_plots",
      "post_scatter_plots",
      "umap_plot"
    )
  )
  
  # Preview annotations should have been computed in memory.
  expect_true(
    "subclone" %in% names(res$cells_filt)
  )
  
  expect_equal(
    nrow(res$cells_filt),
    nrow(before)
  )
  
  expect_setequal(
    res$cells_filt$cell_name,
    before$cell_name
  )
  
  # Engineered fixture:
  # cell_02 exceeds malignant thresholds.
  idx_02 <- match(
    "cell_02",
    res$cells_filt$cell_name
  )
  
  expect_equal(
    res$cells_filt$cell_type[idx_02],
    "Malignant"
  )
  
  expect_identical(
    res$cells_filt$subclone[idx_02],
    1L
  )
  
  # cell_03 is deliberately in the intermediate / gray zone.
  idx_03 <- match(
    "cell_03",
    res$cells_filt$cell_name
  )
  
  expect_equal(
    res$cells_filt$cell_type[idx_03],
    "Unassigned"
  )
  
  expect_true(
    is.na(
      res$cells_filt$subclone[idx_03]
    )
  )
  
  # Validate all generated plot objects by building them rather than
  # snapshotting pixels.
  expect_s3_class(
    res$summary_heatmap,
    "ggplot"
  )
  
  expect_s3_class(
    res$umap_plot,
    "ggplot"
  )
  
  expect_no_error(
    ggplot2::ggplot_build(
      res$summary_heatmap
    )
  )
  
  expect_no_error(
    ggplot2::ggplot_build(
      res$umap_plot
    )
  )
  
  expect_length(
    res$pre_scatter_plots,
    1
  )
  
  expect_length(
    res$post_scatter_plots,
    1
  )
  
  expect_s3_class(
    res$pre_scatter_plots[[1]],
    "ggplot"
  )
  
  expect_s3_class(
    res$post_scatter_plots[[1]],
    "ggplot"
  )
  
  expect_no_error(
    ggplot2::ggplot_build(
      res$pre_scatter_plots[[1]]
    )
  )
  
  expect_no_error(
    ggplot2::ggplot_build(
      res$post_scatter_plots[[1]]
    )
  )
  
  # Critical contract: preview_cna_summary() calls
  # apply_cna_thresholds(..., save = FALSE), so no preview annotations
  # may leak back into the cached source data.
  after <- cache_load_data(
    cells_file,
    dataset_dir
  )
  
  expect_equal(
    after,
    before
  )
  
  expect_false(
    "subclone" %in% names(after)
  )
  
  expect_equal(
    after$cell_type,
    before$cell_type
  )
})