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

test_that("F08 score plots preserve long sample identifiers and compact metadata", {
  skip_if_not_installed("randomcoloR")
  skip_if_not_installed("cowplot")

  long_sample_name <- paste0("Sample_", paste(rep("LongIdentifier", 9), collapse = ""))
  cells <- data.table::data.table(
    cell_name = paste0("cell", 1:3),
    clust = "10",
    TypeA = c(0.1, 0.3, 0.2),
    TypeB = c(0.7, 0.8, 0.6)
  )
  marker_genes_found <- data.table::data.table(
    cell_types = c("TypeA", "TypeB"),
    gene_count = c(12L, 8L),
    n_gene_pass = c(TRUE, FALSE)
  )

  long_plot <- sig_scores_cluster_boxplot(
    cells,
    c("TypeA", "TypeB"),
    marker_genes_found,
    cluster_name = "10",
    sample_name = long_sample_name,
    resolution = 1.25
  )

  expect_gt(nchar(long_sample_name), 100)
  expect_match(long_plot$labels$title, "\n", fixed = TRUE)
  expect_identical(gsub("\n", "", long_plot$labels$title, fixed = TRUE), long_sample_name)
  expect_identical(
    long_plot$labels$subtitle,
    "Cluster 10 scores | Resolution: 1.25 | Cells: 3"
  )

  short_labels <- format_signature_score_plot_labels("Sample_1", "2", 0.5, 18)
  expect_false(grepl("\n", short_labels$title, fixed = TRUE))
  expect_identical(short_labels$title, "Sample_1")
})

test_that("F08 score plot exports use explicit dimensions", {
  skip_if_not_installed("png")

  export_formals <- formals(save_signature_score_plot)
  expect_identical(export_formals$width, 9)
  expect_identical(export_formals$height, 7)
  expect_identical(export_formals$units, "in")
  expect_identical(export_formals$dpi, 300)

  output_path <- withr::local_tempfile(fileext = ".png")
  save_signature_score_plot(
    ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) +
      ggplot2::geom_point(),
    output_path,
    dpi = 10
  )
  image <- png::readPNG(output_path)

  expect_identical(dim(image)[1:2], c(70L, 90L))
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
