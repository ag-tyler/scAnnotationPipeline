test_that("R05 workspace checklist copies are independent and never reset existing notes", {
  root <- withr::local_tempdir()
  template <- testthat::test_path("..", "..", "docs", "STANDARDIZATION_CHECKLIST.md")
  original_hash <- tools::md5sum(template)
  workspaces <- file.path(root, c("Dataset One", "Dataset Two"))
  invisible(lapply(workspaces, dir.create))
  first <- ensure_dataset_standardization_checklist(workspaces[1], template)
  second <- ensure_dataset_standardization_checklist(workspaces[2], template)
  expect_true(first$created)
  expect_true(second$created)
  expect_identical(unname(tools::md5sum(first$path)), unname(original_hash))
  expect_identical(unname(tools::md5sum(second$path)), unname(original_hash))
  notes <- c("# Dataset One", "- [x] Raw inputs inspected", "Patient notes: Müller, αβ")
  writeLines(enc2utf8(notes), first$path, useBytes = TRUE)
  edited_hash <- tools::md5sum(first$path)
  again <- ensure_dataset_standardization_checklist(workspaces[1], template)
  expect_false(again$created)
  expect_identical(tools::md5sum(first$path), edited_hash)
  expect_identical(readLines(first$path, encoding = "UTF-8"), notes)
  expect_identical(unname(tools::md5sum(second$path)), unname(original_hash))
  expect_identical(tools::md5sum(template), original_hash)
  # Preserving an existing copy does not require the shared source to exist.
  expect_false(ensure_dataset_standardization_checklist(workspaces[1], "missing-template")$created)
  expect_error(ensure_dataset_standardization_checklist(file.path(root, "missing"), template), "Workspace directory")
  third <- file.path(root, "Dataset Three")
  dir.create(third)
  expect_error(ensure_dataset_standardization_checklist(third, "missing-template"), "Restore this repository file")
  expect_false(file.exists(file.path(third, "STANDARDIZATION_CHECKLIST.md")))
  dir.create(file.path(third, "STANDARDIZATION_CHECKLIST.md"))
  expect_error(ensure_dataset_standardization_checklist(third, template), "directory, not a Markdown file")
  blocked <- ensure_dataset_standardization_checklist
  copy_env <- new.env(parent = environment(blocked))
  copy_env$file.copy <- function(...) FALSE
  environment(blocked) <- copy_env
  fourth <- file.path(root, "Dataset Four")
  dir.create(fourth)
  expect_error(blocked(fourth, template), "Check write permissions")
  expect_false(file.exists(file.path(fourth, "STANDARDIZATION_CHECKLIST.md")))
})

test_that("R05 document selection is read-only and renders Markdown with editor/download fallbacks", {
  suppressPackageStartupMessages(library(shiny))
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  docs_dir <- file.path(app_dir, "docs")
  workspace <- withr::local_tempdir()
  document <- read_standardization_document("checklist", docs_dir, workspace)
  expect_true(document$is_template)
  expect_identical(document$dataset_dir, workspace)
  expect_false(file.exists(file.path(workspace, "STANDARDIZATION_CHECKLIST.md")))
  env <- new.env(parent = environment())
  sys.source(file.path(app_dir, "app/ui/dataset_ui.R"), env)
  html <- as.character(env$standardization_document_modal(document))
  expect_match(html, "<h1>Standardization Checklist</h1>", fixed = TRUE)
  expect_match(html, 'type="checkbox"', fixed = TRUE)
  expect_match(html, "btn_create_dataset_checklist", fixed = TRUE)
  expect_match(html, document$path, fixed = TRUE)
  expect_match(html, "download_standardization_document", fixed = TRUE)
  expect_false(grepl('href="pipeline-docs/', html, fixed = TRUE))
  ensure_dataset_standardization_checklist(workspace, document$path)
  local <- read_standardization_document("checklist", docs_dir, workspace)
  expect_false(local$is_template)
  expect_identical(local$path, normalizePath(file.path(workspace, "STANDARDIZATION_CHECKLIST.md"), winslash = "/"))
  expect_false(grepl("btn_create_dataset_checklist", as.character(env$standardization_document_modal(local)), fixed = TRUE))
  guide <- read_standardization_document("user_guide", docs_dir)
  expect_identical(guide$display_lines[1], "## Setting Up a New Dataset")
  expect_false("## Standardization Pipeline" %in% guide$display_lines)
  expect_true("## Standardization Pipeline" %in% guide$lines)
  expect_match(as.character(env$standardization_document_modal(guide)), "<h2>Setting Up a New Dataset</h2>", fixed = TRUE)
  expect_error(read_standardization_document("checklist", file.path(workspace, "missing")), "Restore the file")
  expect_error(read_standardization_document("user_guide", file.path(workspace, "missing")), "USER_GUIDE.md")
  # A renderer failure still exposes readable source text and the file/download.
  env$HTML <- function(...) stop("synthetic renderer failure")
  fallback <- as.character(env$standardization_document_modal(guide))
  expect_match(fallback, "<pre>## Setting Up a New Dataset", fixed = TRUE)
  expect_match(fallback, "download_standardization_document", fixed = TRUE)
  bad_docs <- withr::local_tempdir()
  writeLines("# No setup section", file.path(bad_docs, "USER_GUIDE.md"))
  expect_error(read_standardization_document("user_guide", bad_docs), "Open the full guide in your editor")
})

make_r05_dataset_fixture <- function(root) {
  app_dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  docs_dir <- file.path(root, "docs")
  dir.create(docs_dir)
  file.copy(file.path(app_dir, "docs", c("STANDARDIZATION_CHECKLIST.md", "USER_GUIDE.md")), docs_dir)
  datasets_dir <- file.path(root, "datasets")
  dir.create(datasets_dir)
  config <- yaml::read_yaml(file.path(app_dir, "general_config.yaml"))
  config$paths$datasets_dir <- datasets_dir
  context <- list(
    config = config,
    resources = list(),
    paths = list(datasets_dir = datasets_dir, templates_dir = file.path(app_dir, "templates"), docs_dir = docs_dir),
    available_datasets = character()
  )
  env <- new.env(parent = environment())
  env$modals <- list()
  env$notifications <- character()
  env$showModal <- function(ui, ...) {
    env$modals <- c(env$modals, list(as.character(ui)))
  }
  env$removeModal <- function(...) invisible(NULL)
  env$showNotification <- function(ui, ...) {
    env$notifications <- c(env$notifications, as.character(ui))
    "notification"
  }
  env$record_pipeline_event <- function(...) invisible(NULL)
  env$nav_select <- function(...) invisible(NULL)
  sys.source(file.path(app_dir, "app/state.R"), env)
  sys.source(file.path(app_dir, "app/ui/dataset_ui.R"), env)
  sys.source(file.path(app_dir, "app/server/dataset_server.R"), env)
  state <- env$create_app_state(list(), session_id = "r05-onboarding")
  env$state <- state
  env$context <- context
  env$server <- function(input, output, session) {
    env$register_dataset_server(input, output, session, state, context)
  }
  env
}

test_that("R05 actual workspace creation publishes separate checklists and immediate document access", {
  suppressPackageStartupMessages(library(shiny))
  suppressPackageStartupMessages(library(bslib))
  root <- withr::local_tempdir()
  fixture <- make_r05_dataset_fixture(root)
  datasets_dir <- fixture$context$paths$datasets_dir
  source_path <- file.path(fixture$context$paths$docs_dir, "STANDARDIZATION_CHECKLIST.md")
  source_hash <- tools::md5sum(source_path)
  shiny::testServer(fixture$server, {
    for (i in 1:2) {
      name <- c("Dataset One", "Dataset Two")[i]
      session$setInputs(btn_create_dataset_ui = i)
      session$setInputs(new_ds_name = name, new_ds_location = datasets_dir, new_ds_tech = "general", btn_confirm_create_ds = i)
      checklist <- file.path(datasets_dir, name, "STANDARDIZATION_CHECKLIST.md")
      expect_true(file.exists(checklist), info = paste(fixture$notifications, collapse = "; "))
      expect_identical(unname(tools::md5sum(checklist)), unname(source_hash))
      expect_match(tail(fixture$modals, 1)[[1]], "btn_open_created_checklist", fixed = TRUE)
      session$setInputs(btn_open_created_checklist = i)
      expect_match(tail(fixture$modals, 1)[[1]], normalizePath(checklist, winslash = "/"), fixed = TRUE)
    }
    first <- file.path(datasets_dir, "Dataset One", "STANDARDIZATION_CHECKLIST.md")
    writeLines(c("# Custom checklist", "- [x] Dataset One notes"), first)
    session$setInputs(dataset_choice = "Dataset One", btn_view_standardization_checklist = 1)
    expect_match(tail(fixture$modals, 1)[[1]], "Dataset One notes", fixed = TRUE)
    expect_match(tail(fixture$modals, 1)[[1]], 'checked=""', fixed = TRUE)
    # Download targets the document in the open modal, not a later selection.
    session$setInputs(dataset_choice = "Dataset Two")
    downloaded <- output$download_standardization_document
    expect_identical(readLines(downloaded), readLines(first))
    session$setInputs(btn_view_standardization_checklist = 2)
    expect_false(grepl("Dataset One notes", tail(fixture$modals, 1)[[1]], fixed = TRUE))
    expect_identical(tools::md5sum(source_path), source_hash)
    expect_null(fixture$state$pipeline_state)
    # Documentation is usable before standardization/loading a dataset.
    session$setInputs(btn_view_setup_guide = 1)
    expect_match(tail(fixture$modals, 1)[[1]], "<h2>Setting Up a New Dataset</h2>", fixed = TRUE)
    session$setInputs(btn_load_dataset = 1)
    expect_true(any(grepl("No sample folders found", fixture$notifications, fixed = TRUE)))
    expect_null(fixture$state$pipeline_state)
    external_parent <- file.path(root, "Another parent")
    dir.create(external_parent)
    session$setInputs(btn_create_dataset_ui = 3)
    session$setInputs(new_ds_name = "External", new_ds_location = external_parent, btn_confirm_create_ds = 3)
    session$setInputs(dataset_choice = "External", btn_view_standardization_checklist = 3)
    expect_match(
      tail(fixture$modals, 1)[[1]],
      normalizePath(file.path(external_parent, "External", "STANDARDIZATION_CHECKLIST.md"), winslash = "/"),
      fixed = TRUE
    )
  })
})

test_that("R05 older workspaces opt into copies without overwriting notes or workflow state", {
  suppressPackageStartupMessages(library(shiny))
  suppressPackageStartupMessages(library(bslib))
  root <- withr::local_tempdir()
  fixture <- make_r05_dataset_fixture(root)
  workspace <- file.path(fixture$context$paths$datasets_dir, "Existing")
  dir.create(workspace)
  checklist <- file.path(workspace, "STANDARDIZATION_CHECKLIST.md")
  state_path <- file.path(workspace, "pipeline_state.yaml")
  save_pipeline_state_at_path(new_pipeline_state("Existing", "sample1"), state_path)
  state_hash <- tools::md5sum(state_path)
  shiny::testServer(fixture$server, {
    session$setInputs(dataset_choice = "Existing", btn_view_standardization_checklist = 1)
    expect_false(file.exists(checklist))
    expect_match(tail(fixture$modals, 1)[[1]], "btn_create_dataset_checklist", fixed = TRUE)
    session$setInputs(btn_create_dataset_checklist = 1)
    expect_true(file.exists(checklist))
    expect_false(grepl("btn_create_dataset_checklist", tail(fixture$modals, 1)[[1]], fixed = TRUE))
    writeLines(c("# My notes", "- [x] Preserve me"), checklist)
    notes_hash <- tools::md5sum(checklist)
    session$setInputs(btn_create_dataset_checklist = 2)
    expect_identical(tools::md5sum(checklist), notes_hash)
    expect_identical(tools::md5sum(state_path), state_hash)
    expect_match(tail(fixture$modals, 1)[[1]], "Preserve me", fixed = TRUE)
    # Switching the selected dataset after opening a modal cannot redirect its
    # create-copy action to another workspace.
    dir.create(file.path(fixture$context$paths$datasets_dir, "Other"))
    session$setInputs(dataset_choice = "Other", btn_view_standardization_checklist = 2)
    session$setInputs(dataset_choice = "Existing", btn_create_dataset_checklist = 3)
    expect_true(file.exists(file.path(fixture$context$paths$datasets_dir, "Other", "STANDARDIZATION_CHECKLIST.md")))
    expect_identical(tools::md5sum(checklist), notes_hash)
    expect_null(fixture$state$pipeline_state)
    count <- length(fixture$modals)
    session$setInputs(dataset_choice = "../escape", btn_view_standardization_checklist = 3)
    expect_length(fixture$modals, count)
    expect_true(any(grepl("path separators", fixture$notifications, fixed = TRUE)))
    session$setInputs(dataset_choice = "Missing", btn_view_standardization_checklist = 4)
    expect_true(any(grepl("Selected workspace not found", fixture$notifications, fixed = TRUE)))
    unlink(file.path(fixture$context$paths$docs_dir, "USER_GUIDE.md"))
    session$setInputs(btn_view_setup_guide = 1)
    expect_true(any(grepl("Documentation is missing", fixture$notifications, fixed = TRUE)))
    expect_false(isTRUE(session$isClosed()))
  })
})

test_that("R05 missing templates and unsafe creation requests stop before creating workspaces", {
  suppressPackageStartupMessages(library(shiny))
  suppressPackageStartupMessages(library(bslib))
  root <- withr::local_tempdir()
  fixture <- make_r05_dataset_fixture(root)
  datasets_dir <- fixture$context$paths$datasets_dir
  shiny::testServer(fixture$server, {
    session$setInputs(btn_view_standardization_checklist = 1)
    expect_match(tail(fixture$modals, 1)[[1]], "Select or create a workspace", fixed = TRUE)
    session$setInputs(btn_create_dataset_ui = 1)
    session$setInputs(new_ds_name = "../Escape", new_ds_location = datasets_dir, new_ds_tech = "general", btn_confirm_create_ds = 1)
    expect_true(any(grepl("path separators", fixture$notifications, fixed = TRUE)))
    expect_false(dir.exists(file.path(root, "Escape")))
    session$setInputs(new_ds_name = "MissingParent", new_ds_location = file.path(root, "NoParent"), btn_confirm_create_ds = 2)
    expect_true(any(grepl("existing parent directory", fixture$notifications, fixed = TRUE)))
    expect_false(dir.exists(file.path(root, "NoParent")))
    unlink(file.path(fixture$context$paths$docs_dir, "STANDARDIZATION_CHECKLIST.md"))
    session$setInputs(new_ds_name = "NoChecklist", new_ds_location = datasets_dir, btn_confirm_create_ds = 3)
    expect_true(any(grepl("Restore this file before creating", fixture$notifications, fixed = TRUE)))
    expect_false(dir.exists(file.path(datasets_dir, "NoChecklist")))
  })
})
