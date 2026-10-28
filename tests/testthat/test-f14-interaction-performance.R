app_dir_f14 <- normalizePath(testthat::test_path("..", ".."), winslash = "/")


test_that("F14 CNA status shares one metadata preflight across its consumers", {
  server_text <- paste(readLines(
    file.path(app_dir_f14, "app/server/cna_status_server.R"),
    warn = FALSE
  ), collapse = "\n")

  expect_identical(
    lengths(regmatches(server_text, gregexpr("cna_sample_preflight\\(", server_text))),
    1L
  )
  expect_match(server_text, "cna_status_preflight <- reactive", fixed = TRUE)
  expect_gte(
    lengths(regmatches(server_text, gregexpr("cna_status_preflight\\(\\)", server_text))),
    2L
  )
})


test_that("F14 threshold slider rendering reuses signal tables held in memory", {
  threshold_text <- paste(readLines(
    file.path(app_dir_f14, "app/server/cna_threshold_server.R"),
    warn = FALSE
  ), collapse = "\n")
  expect_match(threshold_text, "cna_signal_tables <- reactive", fixed = TRUE)
  expect_match(threshold_text, "cna_sig_cor <- cna_signal_tables()[[i]]", fixed = TRUE)

  plot_start <- regexpr(
    "output[[paste0(\"cna_sig_cor_plot_\", i)]] <- renderPlot",
    threshold_text,
    fixed = TRUE
  )[[1]]
  plot_end <- regexpr("lapply(1:20", threshold_text, fixed = TRUE)[[1]]
  expect_gt(plot_start, 0L)
  expect_gt(plot_end, plot_start)
  plot_renderers <- substr(threshold_text, plot_start, plot_end - 1L)
  expect_false(grepl("cache_load_data", plot_renderers, fixed = TRUE))
  expect_false(grepl("cache_check_valid", plot_renderers, fixed = TRUE))
})


test_that("F14 profiling entry point is portable and read-only", {
  profile_path <- file.path(app_dir_f14, "scripts/profile_interactions.R")
  expect_true(file.exists(profile_path))
  profile_text <- paste(readLines(profile_path, warn = FALSE), collapse = "\n")
  expect_match(profile_text, "benchmark_expression", fixed = TRUE)
  expect_match(profile_text, "dataset_cleanup_readiness", fixed = TRUE)
  expect_match(profile_text, "cna_sample_preflight", fixed = TRUE)
  expect_match(profile_text, "cell_type_annotation_setup", fixed = TRUE)
  expect_false(grepl("write_yaml|fwrite|cache_save_data", profile_text))
})
