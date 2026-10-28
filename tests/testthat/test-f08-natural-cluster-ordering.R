test_that("F08 helper orders 13 integer-like clusters naturally", {
  shuffled <- c("10", "2", "12", "1", "0", "11", "5", "4", "3", "9", "8", "7", "6")

  expect_identical(
    natural_cluster_order(c(shuffled, "beta", "alpha", "10", NA_character_)),
    c(as.character(0:12), "alpha", "beta")
  )
  expect_identical(
    natural_cluster_order(factor(c("cluster-b", "cluster-a", "cluster-b"))),
    c("cluster-a", "cluster-b")
  )
})

test_that("F08 UMAP legends use natural labels with label-stable colours", {
  skip_if_not_installed("randomcoloR")
  skip_if_not_installed("cowplot")

  labels <- c("10", "2", "12", "1", "0", "11", "5", "4", "3", "9", "8", "7", "6")
  cells <- data.table::data.table(
    umap1 = seq_along(labels),
    umap2 = rev(seq_along(labels)),
    clust = labels
  )
  original_labels <- cells$clust

  plot <- plot_clusters(cells, "Thirteen clusters")
  built <- ggplot2::ggplot_build(plot)
  colour_scale <- built$plot$scales$get_scales("colour")
  expected <- as.character(0:12)

  expect_identical(as.character(colour_scale$get_breaks()), expected)
  expected_colours <- stats::setNames(colour_scale$map(expected), expected)
  expect_identical(
    built$data[[1]]$colour,
    unname(expected_colours[labels])
  )
  expect_identical(cells$clust, original_labels)
})

test_that("F08 DE cluster lists and axes share the natural order", {
  labels <- c("10", "2", "12", "1", "0", "11", "5", "4", "3", "9", "8", "7", "6")
  de <- data.table::data.table(
    clust = labels,
    gene = paste0("GENE", seq_along(labels)),
    m = rev(seq_along(labels))
  )
  markers <- data.table::data.table(cell_type = "TypeA", symbol = de$gene)
  matched <- match_marker_genes(de, markers, list(col_name = "clust"))
  expected <- as.character(0:12)

  expect_identical(names(matched), expected)

  counts <- data.table::data.table(
    clusters = labels,
    TypeA = seq_along(labels),
    TypeB = rev(seq_along(labels))
  )
  plot <- stacked_gene_match_count_plot(
    counts,
    list(max_match_genes = 10, cluster_type_name = "cluster"),
    res = 1
  )
  built <- ggplot2::ggplot_build(plot)
  expect_identical(
    as.character(built$layout$panel_scales_x[[1]]$get_labels()),
    expected
  )
})

test_that("F08 annotation selection and advancement use the shared helper", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  annotation_text <- paste(
    readLines(file.path(app_dir, "app/server/annotation_server.R"), warn = FALSE),
    collapse = "\n"
  )
  workflow_text <- paste(
    readLines(file.path(app_dir, "util_scripts/05_utils_workflow.R"), warn = FALSE),
    collapse = "\n"
  )

  expect_equal(
    lengths(regmatches(
      annotation_text,
      gregexpr(
        "clusters <- natural_cluster_order(rv$cells_filt$clust)",
        annotation_text,
        fixed = TRUE
      )
    )),
    3L
  )
  expect_false(grepl("order(as.numeric(clusters))", annotation_text, fixed = TRUE))
  expect_match(
    workflow_text,
    "clusters = natural_cluster_order(cells_filt$clust)",
    fixed = TRUE
  )
  expect_match(
    workflow_text,
    "cluster_levels <- natural_cluster_order(all_matches$clust)",
    fixed = TRUE
  )
})
