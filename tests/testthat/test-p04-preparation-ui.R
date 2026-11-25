suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(shinyjs)
})

make_p04_context_fixture <- function(root) {
  app <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
  config <- yaml::read_yaml(file.path(app, "general_config.yaml"))
  config$paths$resources_dir <- file.path(root, "resources")
  config$paths$datasets_dir <- file.path(root, "datasets")
  config$resource_files$metadata_prompt <- NULL
  resources <- config$paths$resources_dir
  dir.create(resources)
  data.table::fwrite(data.table::data.table(cell_type = "T cell", gene = "G1",
    specificity = 0.9, sensitivity = 0.8, combined = 2), file.path(resources, config$resource_files$marker_sets))
  data.table::fwrite(data.table::data.table(cancer_type = "SYN", gene = "G2",
    specificity = 0.9, sensitivity = 0.8, combined = 2), file.path(resources, config$resource_files$malignant_markers))
  writeLines("G1", file.path(resources, config$resource_files$housekeeping_genes))
  writeLines("G2", file.path(resources, config$resource_files$mitochondrial_genes))
  jsonlite::write_json(list(cancer_types = list("Synthetic Cancer" = "SYN"),
    cell_types = list(SYN = "Epithelial")), file.path(resources, config$resource_files$cancer_cell_map), auto_unbox = TRUE)
  data.table::fwrite(data.table::data.table(hgnc_symbol = c("G1", "G2"),
    ensembl_gene_id = c("ENSG1", "ENSG2"), chromosome_name = c("1", "X"),
    start_position = c(100, 200), end_position = c(150, 250)),
    file.path(resources, config$resource_files$gene_positions))
  data.table::fwrite(data.table::data.table(ensembl_gene_id = c("ENSG1", "ENSG2"),
    symbol = c("G1", "G2"), location_sortable = c("1p1", "2p1")),
    file.path(resources, config$resource_files$hgnc_complete_set))
  config_path <- file.path(root, "general_config.yaml")
  yaml::write_yaml(config, config_path)
  env <- new.env(parent = environment())
  for (component in c("app/context.R", "app/state.R", "app/ui/dataset_ui.R",
    "app/ui/dashboard_ui.R", "app/ui/resolution_ui.R", "app/ui/annotation_ui.R",
    "app/ui/cna_ui.R", "app/ui/app_ui.R", "app/server/dataset_server.R",
    "app/server/dashboard_server.R")) sys.source(file.path(app, component), env)
  context <- env$create_app_context(config_path)
  context$paths$docs_dir <- file.path(root, "docs")
  context$paths$templates_dir <- file.path(root, "templates")
  dir.create(context$paths$templates_dir)
  file.copy(file.path(app, "templates", "dataset_config_template.yaml"), context$paths$templates_dir)
  file.copy(file.path(app, "README.md"), file.path(root, "README.md"))
  list(env = env, context = context, config_path = config_path)
}

test_that("P04 startup requires biological resources but no preparation files or prompt key", {
  root <- withr::local_tempdir()
  fixture <- make_p04_context_fixture(root)
  context <- fixture$context
  expect_false(file.exists(file.path(root, "resources", "metadata_extract_prompt.txt")))
  expect_false(dir.exists(context$paths$docs_dir))
  expect_false(file.exists(file.path(context$paths$templates_dir, "standardize_general.R")))
  expect_false("metadata_prompt" %in% names(context$resource_paths))
  expect_false("clipboard_text" %in% names(context$resources))
  expect_true(all(c("marker_genes", "malignant_markers", "gene_positions") %in% names(context$resources)))
  unlink(context$resource_paths$marker_genes)
  expect_error(fixture$env$create_app_context(fixture$config_path), "marker gene sets", fixed = TRUE)
})

test_that("P04 the complete UI exposes prepared import without guide or prompt entry points", {
  fixture <- make_p04_context_fixture(withr::local_tempdir())
  context <- fixture$context
  # Old callers can carry extra resource fields without making them visible.
  context$resources$clipboard_text <- "P04_OPTIONAL_PROMPT_SENTINEL"
  html <- as.character(fixture$env$build_app_ui(context))
  for (text in c("Standardization Guide", "Reference Data", "Metadata Extraction Prompt",
    "P04_OPTIONAL_PROMPT_SENTINEL", "btn_copy_info", "clipboard_tab", "standardization_prompt_text",
    "btn_view_standardization_checklist", "btn_create_dataset_checklist", "dataset_setup_view")) {
    expect_false(grepl(text, html, fixed = TRUE), info = text)
  }
  expect_match(html, "btn_create_dataset_ui", fixed = TRUE)
  expect_match(html, "btn_run_clustering", fixed = TRUE)
  state <- transition_pipeline_step(new_pipeline_state("Prepared", "sample1"),
    "standardization", "completed", force = TRUE)
  overview <- as.character(fixture$env$pipeline_status_overview_ui(summarize_pipeline_overview(state)))
  expect_match(overview, "Prepared inputs:", fixed = TRUE)
  expect_false(grepl("Standardization:", overview, fixed = TRUE))
})

test_that("creation filenames are collapsed above source information with configured defaults", {
  fixture <- make_p04_context_fixture(withr::local_tempdir())
  filenames <- list(expmat = "expression.mtx", genes = "symbols.txt",
    cells = "cell metadata.csv", samples = "sample metadata.csv")
  dialog <- fixture$env$dataset_import_dialog(tempdir(), std_names = filenames)
  query <- htmltools::tagQuery(dialog)$find("#new_ds_filenames")
  disclosure <- query$selectedTags()[[1]]
  expect_identical(disclosure$name, "details")
  expect_null(disclosure$attribs$open)
  for (key in names(filenames)) {
    field <- query$find(paste0("#new_ds_std_", key))$selectedTags()[[1]]
    expect_identical(field$attribs$value, filenames[[key]])
  }
  html <- as.character(dialog)
  expect_lt(regexpr('id="new_ds_filenames"', html, fixed = TRUE)[[1]],
    regexpr('id="new_ds_origin"', html, fixed = TRUE)[[1]])
})

test_that("DC04 source disclosure is collapsed and describes both optional inputs", {
  fixture <- make_p04_context_fixture(withr::local_tempdir())
  origin <- list(source_doi = "10.1234/template", source_url = "https://example.org/database")
  dialog <- fixture$env$dataset_import_dialog(tempdir(), project_info = origin)
  query <- htmltools::tagQuery(dialog)$find("#new_ds_origin")
  disclosure <- query$selectedTags()[[1]]
  expect_identical(disclosure$name, "details")
  expect_null(disclosure$attribs$open)
  expect_identical(query$find("#new_ds_source_doi")$selectedTags()[[1]]$attribs$value, origin$source_doi)
  expect_identical(query$find("#new_ds_source_url")$selectedTags()[[1]]$attribs$value, origin$source_url)
  html <- as.character(dialog)
  for (text in c("Source information (optional)", "Paper DOI", "Database URL",
    "DOI of the paper describing the dataset.", "URL of the dataset's database entry.")) {
    expect_match(html, text, fixed = TRUE)
  }
})

test_that("P04 import, spec download, and loading work without preparation materials", {
  root <- withr::local_tempdir()
  fixture <- make_p04_context_fixture(root)
  env <- fixture$env
  context <- fixture$context
  source <- file.path(root, "prepared")
  dir.create(source)
  write_mini_sample(source, "sample1", n_genes = 12, n_cells = 8)
  metadata <- build_samples("sample1")
  metadata$n_cells <- 8L
  data.table::fwrite(metadata, file.path(source, "Samples.csv"))
  state <- env$create_app_state(context)
  navigation <- character()
  env$nav_show <- env$nav_hide <- env$removeNotification <- env$removeModal <- function(...) invisible(NULL)
  env$showNotification <- function(...) "notification"
  env$updateNavbarPage <- function(session, inputId, selected, ...) navigation <<- c(navigation, selected)
  server <- function(input, output, session) {
    env$register_dataset_server(input, output, session, state, context)
    env$register_dashboard_server(input, output, session, state, context)
  }
  shiny::testServer(server, {
    session$setInputs(btn_create_dataset_ui = 1, new_ds_name = "Prepared",
      new_ds_source = source, new_ds_location = context$paths$datasets_dir)
    downloaded <- output$download_input_specification
    expect_true(any(grepl("Preparing input data", readLines(downloaded), fixed = TRUE)))
    session$setInputs(btn_confirm_create_ds = 1)
    expect_identical(basename(state$dataset_dir_path), "Prepared")
    expect_true(pipeline_step_readiness(state$pipeline_state, "clustering", "sample1")$ready)
    expect_false(file.exists(file.path(state$dataset_dir_path, "STANDARDIZATION_CHECKLIST.md")))
    before <- navigation
    # Removed input IDs cannot navigate to dead tabs, copy text, or create notes.
    session$setInputs(btn_copy_info = 1, btn_select_all = 1, btn_back_menu_3 = 1,
      btn_view_standardization_checklist = 1, btn_create_dataset_checklist = 1,
      btn_open_standardization_guide = 1, btn_copy_standardization_prompt = 1)
    expect_identical(navigation, before)
    expect_false(file.exists(file.path(state$dataset_dir_path, "STANDARDIZATION_CHECKLIST.md")))
    session$setInputs(btn_change_dataset = 1)
    expect_null(state$sample_metadata)
    session$setInputs(dataset_choice = "Prepared", btn_load_dataset = 1)
    expect_identical(state$sample_metadata$sample, "sample1")
  })
})
