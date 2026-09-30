# mean_diff_exp / match_marker_genes / count_matched_marker_genes /
# marker_genes_in_expmat_genes / check_min_n_marker_genes are pure
# data.table + stringr logic with no matkot/Seurat/uwot dependency, unlike
# most of the rest of 02_utils_annotation.R -- so these run unconditionally,
# no skip_if_not_installed() needed.

# Shared engineered fixture: 6 genes x 10 cells, split into two clusters.
# GENE01 is deliberately boosted in cluster "0", GENE04 in cluster "1", so
# we have a known-correct answer for "which gene should come out on top".
make_de_fixture <- function() {
  set.seed(7)
  n_genes <- 6
  cell_names <- sprintf("cell_%02d", seq_len(10))
  gene_names <- sprintf("GENE%02d", seq_len(n_genes))

  base <- matrix(rnorm(n_genes * 10, mean = 2, sd = 0.2),
                  nrow = n_genes, dimnames = list(gene_names, cell_names))
  base["GENE01", 1:5] <- base["GENE01", 1:5] + 10 # boosted in cluster "0"
  base["GENE04", 6:10] <- base["GENE04", 6:10] + 10 # boosted in cluster "1"

  expmat <- Matrix::Matrix(base, sparse = TRUE)
  cells <- data.table::data.table(
    cell_name = cell_names,
    clust = rep(c("0", "1"), each = 5)
  )
  list(expmat = expmat, cells = cells)
}

test_that("mean_diff_exp ranks the engineered marker gene top within its cluster", {
  fx <- make_de_fixture()
  de <- mean_diff_exp(fx$expmat, fx$cells, list(col_name = "clust", num_genes = 100))

  expect_named(de, c("clust", "gene", "m"))
  expect_equal(nrow(de), 2 * nrow(fx$expmat)) # all 6 genes ranked per cluster

  idx0 <- de$clust == "0"
  idx1 <- de$clust == "1"
  
  top_cluster0 <- de$gene[idx0][which.max(de$m[idx0])]
  top_cluster1 <- de$gene[idx1][which.max(de$m[idx1])]
  expect_equal(top_cluster0, "GENE01")
  expect_equal(top_cluster1, "GENE04")
})

test_that("mean_diff_exp respects num_genes", {
  fx <- make_de_fixture()
  
  de <- mean_diff_exp(
    fx$expmat,
    fx$cells,
    list(col_name = "clust", num_genes = 2)
  )
  
  expect_equal(nrow(de), 4L)
  expect_equal(sum(de$clust == "0"), 2L)
  expect_equal(sum(de$clust == "1"), 2L)
})

test_that("match_marker_genes attaches one column per marker cell type, matched by exact gene name", {
  fx <- make_de_fixture()
  de <- mean_diff_exp(fx$expmat, fx$cells, list(col_name = "clust", num_genes = 100))

  marker_gene_sets <- data.table::data.table(
    cell_type = c("TypeA", "TypeA", "TypeB"),
    symbol = c("GENE01", "GENE99", "GENE04")
  )
  de_parameters <- list(col_name = "clust")

  matched <- match_marker_genes(de, marker_gene_sets, de_parameters)

  expect_named(matched, c("0", "1"))
  expect_true(all(c("TypeA", "TypeB") %in% names(matched[["0"]])))

  row0 <- matched[["0"]]$gene == "GENE01"
  expect_equal(matched[["0"]]$TypeA[row0], "GENE01")
  expect_true(is.na(matched[["0"]]$TypeB[row0]))
  
  row1 <- matched[["1"]]$gene == "GENE04"
  expect_equal(matched[["1"]]$TypeB[row1], "GENE04")
})

test_that("match_marker_genes does not partial-match gene name substrings", {
  # "GENE1" should not match "GENE10" or vice versa -- the function wraps
  # each marker symbol in \\b...\\b word boundaries specifically to avoid this.
  fx <- make_de_fixture()
  de <- mean_diff_exp(fx$expmat, fx$cells, list(col_name = "clust", num_genes = 100))

  marker_gene_sets <- data.table::data.table(cell_type = "TypeA", symbol = "GENE0")
  matched <- match_marker_genes(de, marker_gene_sets, list(col_name = "clust"))

  # None of GENE01..GENE06 should match the bare token "GENE0"
  expect_true(all(is.na(matched[["0"]]$TypeA)))
  expect_true(all(is.na(matched[["1"]]$TypeA)))
})

test_that("count_matched_marker_genes counts hits within the top-N window per cluster", {
  fx <- make_de_fixture()
  de <- mean_diff_exp(fx$expmat, fx$cells, list(col_name = "clust", num_genes = 100))
  marker_gene_sets <- data.table::data.table(
    cell_type = c("TypeA", "TypeB"),
    symbol = c("GENE01", "GENE04")
  )
  # max_match_genes = 1: only the single top-ranked gene per cluster counts,
  # which is exactly what distinguishes "this cluster's top marker" from
  # "this gene exists somewhere in this cluster's full (6-gene) DE table" --
  # with all 6 genes in the marker_gene_sets universe, a wide window would
  # trivially count every marker in every cluster.
  de_parameters <- list(col_name = "clust", marker_cell_type_col_name = "cell_type",
                         max_match_genes = 1)
  matched <- match_marker_genes(de, marker_gene_sets, de_parameters)

  counts <- count_matched_marker_genes(matched, marker_gene_sets, de_parameters)

  expect_equal(counts$clusters, names(matched))
  
  idx0 <- counts$clusters == "0"
  idx1 <- counts$clusters == "1"
  
  expect_equal(counts$TypeA[idx0], 1L)
  expect_equal(counts$TypeB[idx0], 0L)
  expect_equal(counts$TypeB[idx1], 1L)
  expect_equal(counts$TypeA[idx1], 0L)
})

test_that("marker_genes_in_expmat_genes drops genes absent from the expression matrix", {
  fx <- make_de_fixture()
  marker_gene_sets <- data.table::data.table(
    cell_type = c("TypeA", "TypeA", "TypeA"),
    symbol = c("GENE01", "GENE02", "NOT_IN_EXPMAT")
  )

  res <- marker_genes_in_expmat_genes(fx$expmat, marker_gene_sets, n_marker_genes = 50)

  expect_named(res, "TypeA")
  expect_setequal(res$TypeA, c("GENE01", "GENE02"))
})

test_that("marker_genes_in_expmat_genes caps genes per cell type except for 'artifact' types", {
  fx <- make_de_fixture()
  marker_gene_sets <- data.table::data.table(
    cell_type = c("Normal", "Normal", "Cluster_artifact", "Cluster_artifact"),
    symbol = c("GENE01", "GENE02", "GENE03", "GENE04")
  )

  res <- marker_genes_in_expmat_genes(fx$expmat, marker_gene_sets, n_marker_genes = 1)

  expect_length(res$Normal, 1) # capped
  expect_length(res$Cluster_artifact, 2) # NOT capped, "artifact" in the name
})

test_that("check_min_n_marker_genes flags cell types below the minimum gene count", {
  marker_genes_for_scores <- list(
    Tcell = paste0("g", 1:25),
    Bcell = paste0("g", 1:5),
    Artifact = character(0)
  )

  res <- check_min_n_marker_genes(marker_genes_for_scores, min_n_genes = 20)

  expect_equal(res$n_gene_pass[res$cell_types == "Tcell"], TRUE)
  expect_equal(res$n_gene_pass[res$cell_types == "Bcell"], FALSE)
  expect_equal(res$gene_count[res$cell_types == "Artifact"], 0)
})

test_that("score_and_fill_cells adds signature scores aligned by cell_name", {
  skip_if_not_installed("matkot")
  
  mat <- make_mini_expmat(
    n_genes = 220,
    n_cells = 8,
    n_low_count_cells = 0,
    n_low_expr_genes = 0,
    seed = 21
  )
  
  expmat <- log_normalize_expmat(
    mat,
    cell_names = colnames(mat),
    target_sum = 1e5
  )
  
  marker_sets <- list(
    TypeA = c("GENE01", "GENE02"),
    TypeB = c("GENE03", "GENE04")
  )
  
  # Deliberately put metadata in a different order from the matrix columns.
  cells <- data.table::data.table(
    cell_name = rev(colnames(expmat))
  )
  
  expected <- withr::with_seed(
    123,
    lapply(
      marker_sets,
      function(m_genes) {
        matkot::sig_score(expmat, m_genes)
      }
    )
  )
  
  res <- withr::with_seed(
    123,
    score_and_fill_cells(
      expmat,
      marker_sets,
      data.table::copy(cells)
    )
  )
  
  expect_true(all(c("TypeA", "TypeB") %in% names(res)))
  
  expect_equal(
    res$TypeA,
    unname(expected$TypeA[res$cell_name])
  )
  
  expect_equal(
    res$TypeB,
    unname(expected$TypeB[res$cell_name])
  )
})
