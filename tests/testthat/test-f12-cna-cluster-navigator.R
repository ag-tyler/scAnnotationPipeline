app_dir_f12 <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
suppressPackageStartupMessages(library(shiny))
suppressPackageStartupMessages(library(bslib))
sys.source(file.path(app_dir_f12, "app/ui/cna_ui.R"), envir = environment())


make_f12_hclust <- function(n_cells = 80L) {
  set.seed(12012)
  values <- matrix(stats::rnorm(n_cells * 8L), nrow = n_cells)
  rownames(values) <- sprintf("cell_%03d", seq_len(n_cells))
  stats::hclust(stats::dist(values), method = "ward.D2")
}


test_that("F12 canonical identities match cutree membership at representative k values", {
  hc <- make_f12_hclust()
  for (k in c(7L, 12L, 20L)) {
    identity <- cna_cluster_identity_map(hc, k)
    expected <- stats::cutree(hc, k = k)

    expect_identical(identity$membership, expected)
    expect_identical(nrow(identity$clusters), k)
    expect_identical(sort(identity$clusters$cluster_id), seq_len(k))
    expect_identical(sum(identity$clusters$cell_count), length(hc$labels))
    expect_identical(identity$clusters$display_position, seq_len(k))

    expected_order <- unique(unname(expected[rev(hc$labels[hc$order])]))
    expect_identical(identity$clusters$cluster_id, as.integer(expected_order))
    for (index in seq_len(k)) {
      cluster_id <- identity$clusters$cluster_id[[index]]
      expect_setequal(
        identity$clusters$cell_names[[index]],
        names(expected)[expected == cluster_id]
      )
      positions <- which(unname(expected[identity$cells_top_to_bottom]) == cluster_id)
      expect_identical(identity$clusters$leaf_start[[index]], min(positions))
      expect_identical(identity$clusters$leaf_end[[index]], max(positions))
    }
  }
})


test_that("F12 ordered navigator provides keyboard and non-colour identities", {
  identity <- cna_cluster_identity_map(make_f12_hclust(), 12L)
  selected_id <- as.character(identity$clusters$cluster_id[[2]])
  html <- as.character(cna_cluster_navigator_ui(identity, selected_id))

  expect_match(html, "top to the bottom of the heatmap cluster bar", fixed = TRUE)
  expect_match(html, "Position 01", fixed = TRUE)
  expect_match(html, "Position 12", fixed = TRUE)
  expect_match(html, "Cluster 10", fixed = TRUE)
  expect_match(html, 'type="checkbox"', fixed = TRUE)
  expect_match(html, paste0('value="', selected_id, '" checked'), fixed = TRUE)
  expect_match(html, "colour is only a secondary cue", fixed = TRUE)
})


test_that("F12 confirmation reports stable ID, position, and membership size", {
  identity <- cna_cluster_identity_map(make_f12_hclust(), 7L)
  selected <- as.character(identity$clusters$cluster_id[c(2L, 5L)])
  html <- as.character(cna_cluster_selection_summary_ui(identity, selected))

  expect_match(html, "Selection to save", fixed = TRUE)
  for (index in c(2L, 5L)) {
    expect_match(
      html,
      sprintf("Position %02d", identity$clusters$display_position[[index]]),
      fixed = TRUE
    )
    expect_match(html, identity$clusters$label[[index]], fixed = TRUE)
    expect_match(html, as.character(identity$clusters$cell_count[[index]]), fixed = TRUE)
  }
})


test_that("F12 context changes restore only an initially saved exact k", {
  saved_refs <- list(
    list(method = "cutree", k = 12, cluster = 3, label = "Cluster 03"),
    list(method = "cutree", k = 12, cluster = 9, label = "Cluster 09")
  )

  initial_mismatch <- reconcile_cna_cluster_selection(
    current_selection = "5",
    previous_context = NULL,
    sample_name = "sample1",
    k = 7L,
    saved_refs = saved_refs,
    saved_completed = TRUE
  )
  expect_length(initial_mismatch$selected, 0L)
  expect_true(initial_mismatch$context$awaiting_saved_k)

  initial_saved_k <- reconcile_cna_cluster_selection(
    current_selection = NULL,
    previous_context = initial_mismatch$context,
    sample_name = "sample1",
    k = 12L,
    saved_refs = saved_refs,
    saved_completed = TRUE
  )
  expect_identical(initial_saved_k$selected, c("3", "9"))
  expect_false(initial_saved_k$context$awaiting_saved_k)

  changed_k <- reconcile_cna_cluster_selection(
    current_selection = c("3", "9"),
    previous_context = initial_saved_k$context,
    sample_name = "sample1",
    k = 7L,
    saved_refs = saved_refs,
    saved_completed = TRUE
  )
  expect_length(changed_k$selected, 0L)

  returned_k <- reconcile_cna_cluster_selection(
    current_selection = NULL,
    previous_context = changed_k$context,
    sample_name = "sample1",
    k = 12L,
    saved_refs = saved_refs,
    saved_completed = TRUE
  )
  expect_length(returned_k$selected, 0L)

  same_context <- reconcile_cna_cluster_selection(
    current_selection = c("2", "4"),
    previous_context = returned_k$context,
    sample_name = "sample1",
    k = 12L
  )
  expect_identical(same_context$selected, c("2", "4"))
})


test_that("F12 mapping is lightweight and has no cache dependencies", {
  hc <- make_f12_hclust(500L)
  elapsed <- system.time(cna_cluster_identity_map(hc, 20L))[["elapsed"]]
  expect_lt(elapsed, 1)

  mapping_text <- paste(deparse(body(cna_cluster_identity_map)), collapse = "\n")
  expect_false(grepl("cache_|file[.]exists|readLines|qs2", mapping_text))

  server_lines <- readLines(
    file.path(app_dir_f12, "app/server/cna_cluster_server.R"),
    warn = FALSE
  )
  plot_start <- grep("output$cna_combined_heatmap_plot", server_lines, fixed = TRUE)
  save_start <- grep("observeEvent(input$btn_cna_save_malignant", server_lines, fixed = TRUE)
  live_plot_text <- paste(server_lines[plot_start:(save_start - 1L)], collapse = "\n")
  expect_false(grepl("input$cna_selected_clusters", live_plot_text, fixed = TRUE))
  expect_false(grepl("get_legend(clust_p)", live_plot_text, fixed = TRUE))
  expect_match(live_plot_text, "identity$membership", fixed = TRUE)
})


test_that("F12 save path rejects a raw k that has not reached the navigator", {
  server_text <- paste(
    readLines(file.path(app_dir_f12, "app/server/cna_cluster_server.R"), warn = FALSE),
    collapse = "\n"
  )
  expect_match(
    server_text,
    "Please wait for the selected cluster count and navigator to finish updating",
    fixed = TRUE
  )
  expect_match(server_text, "display_positions", fixed = TRUE)
  expect_match(server_text, "cna_cluster_identity_map(static$hc, k_val)", fixed = TRUE)
})
