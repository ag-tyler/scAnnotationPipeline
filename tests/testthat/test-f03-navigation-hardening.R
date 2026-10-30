test_that("F03 completion-dialog navigation is single-shot", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  test_env <- new.env(parent = globalenv())
  test_env$observeEvent <- shiny::observeEvent
  test_env$removeModal <- function(...) invisible(NULL)
  test_env$showNotification <- function(...) "notification"
  navigation <- character()
  test_env$updateNavbarPage <- function(session, inputId, selected) {
    navigation <<- c(navigation, selected)
    invisible(NULL)
  }
  test_env$record_state_event <- function(...) invisible(NULL)
  state_env <- new.env(parent = globalenv())
  sys.source(file.path(app_dir, "app/state.R"), envir = state_env)
  test_env$claim_app_confirmation <- state_env$claim_app_confirmation
  sys.source(
    file.path(app_dir, "app/server/dashboard_server.R"),
    envir = test_env
  )
  state <- state_env$create_app_state(list(), session_id = "f03-test")
  server <- function(input, output, session) {
    test_env$register_dashboard_server(
      input,
      output,
      session,
      state = state,
      context = list()
    )
  }

  shiny::testServer(
    server,
    {
      state_env$arm_app_confirmation(state, "after_clustering_navigation")
      session$setInputs(btn_after_clustering_res = 1)
      expect_identical(navigation, "res_tab")

      session$setInputs(btn_after_clustering_res = 2)
      expect_identical(navigation, "res_tab")

      state_env$arm_app_confirmation(state, "after_de_navigation")
      session$setInputs(btn_after_de_anno = 1)
      # An armed token alone is not evidence of a DE run for this dataset.
      # R06's integrated tests cover valid completion and duplicate navigation.
      expect_identical(navigation, "res_tab")

      session$setInputs(btn_after_de_anno = 2)
      expect_identical(navigation, "res_tab")
    }
  )
})


test_that("F03 destructive modal actions disable immediately and claim a token", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  dashboard <- paste(
    readLines(file.path(app_dir, "app/server/dashboard_server.R"), warn = FALSE),
    collapse = "\n"
  )
  annotation <- paste(
    readLines(file.path(app_dir, "app/server/annotation_server.R"), warn = FALSE),
    collapse = "\n"
  )

  for (key in c("bulk_clustering", "bulk_de")) {
    expect_match(
      dashboard,
      paste0('claim_app_confirmation(rv, "', key, '")'),
      fixed = TRUE
    )
    expect_match(
      dashboard,
      paste0('begin_app_action(rv, "', key, '")'),
      fixed = TRUE
    )
  }
  for (key in c("annotation_navigation", "omit_cna")) {
    expect_match(
      annotation,
      paste0('claim_app_confirmation(rv, "', key, '")'),
      fixed = TRUE
    )
  }
  expect_match(annotation, 'begin_app_action(rv, "annotation_save")', fixed = TRUE)
  expect_gte(
    lengths(regmatches(
      paste(dashboard, annotation),
      gregexpr('onclick = "this.disabled = true;"', paste(dashboard, annotation), fixed = TRUE)
    )),
    7L
  )
})


test_that("F03 long-running confirmation handlers use shared guards", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  guarded_actions <- c(
    "app/server/dashboard_server.R" = "bulk_clustering",
    "app/server/dashboard_server.R" = "bulk_de",
    "app/server/dataset_server.R" = "create_dataset",
    "app/server/cna_compute_server.R" = "cna_batch_compute",
    "app/server/cna_reset_server.R" = "cna_reset"
  )

  for (index in seq_along(guarded_actions)) {
    relative_path <- names(guarded_actions)[[index]]
    key <- guarded_actions[[index]]
    text <- paste(
      readLines(file.path(app_dir, relative_path), warn = FALSE),
      collapse = "\n"
    )
    expect_match(
      text,
      paste0('arm_app_confirmation(rv, "', key, '")'),
      fixed = TRUE,
      info = paste(relative_path, key)
    )
    expect_match(
      text,
      paste0('claim_app_confirmation(rv, "', key, '")'),
      fixed = TRUE,
      info = paste(relative_path, key)
    )
    expect_match(
      text,
      paste0('begin_app_action(rv, "', key, '")'),
      fixed = TRUE,
      info = paste(relative_path, key)
    )
  }

  shared_de_text <- paste(
    readLines(file.path(app_dir, "app/server/single_de_server.R"), warn = FALSE),
    collapse = "\n"
  )
  for (guard_function in c(
    "arm_app_confirmation(rv, action_key)",
    "claim_app_confirmation(rv, action_key)",
    "begin_app_action(rv, action_key)"
  )) {
    expect_match(shared_de_text, guard_function, fixed = TRUE)
  }
  expect_match(
    paste(readLines(file.path(app_dir, "app/server/resolution_server.R")), collapse = "\n"),
    'action_key = "single_sample_de"',
    fixed = TRUE
  )
  expect_match(
    paste(readLines(file.path(app_dir, "app/server/annotation_server.R")), collapse = "\n"),
    'action_key = "annotation_single_sample_de"',
    fixed = TRUE
  )
})


test_that("F03 Dataset Selection remains explicit-only", {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  server_files <- list.files(
    file.path(app_dir, "app", "server"),
    pattern = "[.]R$",
    full.names = TRUE
  )
  navigation_counts <- vapply(server_files, function(path) {
    sum(grepl(
      'updateNavbarPage\\(session, "main_nav", selected = "dataset_tab"\\)',
      readLines(path, warn = FALSE)
    ))
  }, integer(1))

  expect_identical(sum(navigation_counts), 2L)
  expect_identical(
    unname(navigation_counts[basename(server_files) == "app_server.R"]),
    1L
  )
  expect_identical(
    unname(navigation_counts[basename(server_files) == "dataset_server.R"]),
    1L
  )
})
