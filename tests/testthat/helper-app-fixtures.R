# Shared synthetic app fixtures for bootstrap and browser tests.
# No local biological resources or scientific datasets are read.
write_ui_fixture_plot <- function(path, title, subtitle) {
  grDevices::png(path, width = 900, height = 650, res = 120)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mar = c(4, 4, 4, 1))
  graphics::plot(
    cos(seq(0, 2 * pi, length.out = 48)),
    sin(seq(0, 2 * pi, length.out = 48)),
    col = rep(c("#2C7BB6", "#FDAE61", "#1A9641"), each = 16),
    pch = 19,
    xlab = "UMAP 1",
    ylab = "UMAP 2",
    main = title,
    sub = subtitle
  )
}

make_portable_ui_fixture <- function(app_dir, dataset_name = "Synthetic_Demo") {
  config <- yaml::read_yaml(file.path(app_dir, "general_config.yaml"))
  resources_dir <- file.path(app_dir, config$paths$resources_dir)
  datasets_dir <- file.path(app_dir, config$paths$datasets_dir)
  dataset_dir <- file.path(datasets_dir, dataset_name)
  sample_name <- "Synthetic_sample"
  processed_dir <- file.path(dataset_dir, config$dataset_paths$processed_dir)
  sample_dir <- file.path(processed_dir, sample_name)
  results_dir <- file.path(dataset_dir, config$dataset_paths$results_dir)
  cluster_plots_dir <- file.path(results_dir, sample_name, "1_cluster_plots")
  de_plots_dir <- file.path(results_dir, sample_name, "2_de_plots")
  dir.create(resources_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(sample_dir, recursive = TRUE)
  dir.create(cluster_plots_dir, recursive = TRUE)
  dir.create(de_plots_dir, recursive = TRUE)

  genes <- sprintf("GENE%03d", seq_len(66))
  ensembl_ids <- sprintf("ENSG%011d", seq_along(genes))
  # Include a sex chromosome so reference labels remain text when read back.
  chromosomes <- rep(c("1", "2", "X"), each = 22)
  data.table::fwrite(
    data.table::data.table(
      cell_type = rep(c("B cell", "Epithelial"), each = 8),
      gene = genes[1:16],
      specificity = 0.9,
      sensitivity = 0.8,
      combined = 2
    ),
    file.path(resources_dir, config$resource_files$marker_sets)
  )
  data.table::fwrite(
    data.table::data.table(
      cancer_type = "SYN",
      gene = genes[17:24],
      specificity = 0.9,
      sensitivity = 0.8,
      combined = 2
    ),
    file.path(resources_dir, config$resource_files$malignant_markers)
  )
  writeLines(
    genes[25:27],
    file.path(resources_dir, config$resource_files$housekeeping_genes)
  )
  writeLines(
    genes[28:30],
    file.path(resources_dir, config$resource_files$mitochondrial_genes)
  )
  jsonlite::write_json(
    list(
      cancer_types = list("Synthetic Cancer" = "SYN"),
      cell_types = list(SYN = "Epithelial")
    ),
    file.path(resources_dir, config$resource_files$cancer_cell_map),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  data.table::fwrite(
    data.table::data.table(
      hgnc_symbol = genes,
      ensembl_gene_id = ensembl_ids,
      chromosome_name = chromosomes,
      start_position = rep(seq(1e6, by = 1e6, length.out = 22), 3),
      end_position = rep(seq(1e6, by = 1e6, length.out = 22), 3) + 1000
    ),
    file.path(resources_dir, config$resource_files$gene_positions),
    sep = "\t"
  )
  data.table::fwrite(
    data.table::data.table(
      ensembl_gene_id = ensembl_ids,
      symbol = genes,
      location_sortable = paste0(chromosomes, "p", seq_along(genes))
    ),
    file.path(resources_dir, config$resource_files$hgnc_complete_set),
    sep = "\t"
  )
  writeLines(
    "Synthetic metadata prompt used by the portable UI test.",
    file.path(resources_dir, config$resource_files$metadata_prompt)
  )

  dataset_config <- list(
    project_info = list(dataset_id = dataset_name, technology = "synthetic"),
    std_names = list(
      expmat = "Exp_data_UMIcounts.mtx",
      genes = "Genes.txt",
      cells = "Cells.csv",
      samples = "Samples.csv"
    ),
    raw_files = list(type = "synthetic"),
    marker_filter_params = list(
      cell_type = list(min_score = 1, min_genes = 2, max_genes = 8),
      cancer_type = list(min_score = 1, min_genes = 2, max_genes = 8)
    ),
    params = list(
      min_genes = 1,
      target_sum = 10000,
      log2_expr_threshold = 0,
      max_marker_genes = 8,
      pca_nv = 5,
      seed = 3988,
      resolutions = c(0.5, 1),
      umap = list(spread = 2, min_dist = 0.1),
      de = list(
        num_genes = 20,
        max_match_genes = 10,
        min_marker_found = 2
      )
    )
  )
  yaml::write_yaml(
    dataset_config,
    file.path(dataset_dir, config$config_files$dataset)
  )
  sample_entry <- make_valid_sample_entry(sample_name)
  sample_entry$technology <- "Synthetic counts"
  sample_entry$cancer_type <- "Synthetic Cancer"
  sample_entry$patient <- "synthetic_subject"
  sample_entry$sample_type <- "tumor"
  yaml::write_yaml(
    list(samples = list(sample_entry)),
    file.path(dataset_dir, config$config_files$samples)
  )

  set.seed(3988)
  cell_names <- sprintf("synthetic_cell_%03d", seq_len(48))
  counts <- matrix(
    stats::rpois(length(genes) * length(cell_names), lambda = 5),
    nrow = length(genes),
    dimnames = list(genes, cell_names)
  )
  counts <- methods::as(Matrix::Matrix(counts, sparse = TRUE), "CsparseMatrix")
  cell_types <- rep(c("B_cell", "Epithelial", NA_character_), each = 16)
  cells <- data.table::data.table(
    cell_name = cell_names,
    sample = sample_name,
    cell_type = cell_types,
    complexity = as.numeric(Matrix::colSums(counts != 0)),
    cell_subtype = NA_character_,
    patient = "synthetic_subject",
    subclone = NA_character_,
    source = "synthetic",
    cell_type_pre_cna = cell_types
  )
  Matrix::writeMM(counts, file.path(sample_dir, dataset_config$std_names$expmat))
  writeLines(genes, file.path(sample_dir, dataset_config$std_names$genes))
  data.table::fwrite(cells, file.path(sample_dir, dataset_config$std_names$cells))
  sample_metadata <- data.table::as.data.table(sample_entry)
  sample_metadata$n_cells <- length(cell_names)
  data.table::fwrite(sample_metadata, file.path(processed_dir, dataset_config$std_names$samples))

  selected_config <- setup_selected_config(sample_name)
  selected_config$resolutions[[sample_name]] <- 0.5
  selected_config$cna_ref_cells[[sample_name]] <- "B_cell"
  selected_config$cna_pot_mal_cells[[sample_name]] <- "Epithelial"
  selected_config$sample_notes[[sample_name]] <- "Portable synthetic UI fixture"
  yaml::write_yaml(
    selected_config,
    file.path(dataset_dir, config$config_files$selected)
  )

  clustered_cells <- data.table::copy(cells)
  clustered_cells[, `:=`(
    umap1 = cos(seq(0, 2 * pi, length.out = .N)),
    umap2 = sin(seq(0, 2 * pi, length.out = .N)),
    clust = rep(1:3, each = 16)
  )]
  paths_list <- list(
    sample_dir_paths = sample_dir,
    cell_file_paths = file.path(sample_dir, dataset_config$std_names$cells),
    expmat_file_paths = file.path(sample_dir, dataset_config$std_names$expmat),
    genes_file_paths = file.path(sample_dir, dataset_config$std_names$genes)
  )
  cache_save_data(
    counts,
    paste0("expmat_filt_", sample_name, ".qs2"),
    dataset_dir,
    dependencies = filter_cache_dependencies(paths_list, 1, dataset_config),
    producer = "portable-ui-fixture"
  )
  for (resolution in dataset_config$params$resolutions) {
    cache_save_data(
      clustered_cells,
      paste0("cells_filt_clust_res_", resolution, "_", sample_name, ".qs2"),
      dataset_dir,
      dependencies = clustering_cache_dependencies(
        paths_list,
        1,
        dataset_config,
        resolution
      ),
      producer = "portable-ui-fixture"
    )
    write_ui_fixture_plot(
      file.path(
        cluster_plots_dir,
        paste0("clusters_plot_", sample_name, "_res_", resolution, ".png")
      ),
      paste("Synthetic clusters at resolution", resolution),
      "Portable UI regression fixture"
    )
  }
  write_ui_fixture_plot(
    file.path(de_plots_dir, "1.png"),
    "Synthetic cluster marker scores",
    "Cluster 1"
  )
  write_ui_fixture_plot(
    file.path(de_plots_dir, "top_20_unannotated_gene_count_plot.png"),
    "Synthetic differential expression summary",
    "Portable UI regression fixture"
  )
  data.table::fwrite(
    data.table::data.table(
      clust = rep(1:3, each = 4),
      symbol = genes[1:12],
      avg_log2FC = seq(2, 0.9, length.out = 12),
      p_val_adj = 0.001,
      B_cell = rep(c("match", NA_character_), 6),
      Epithelial = rep(c(NA_character_, "match"), 6),
      Housekeeping_artifact = NA_character_,
      Mito_artifact = NA_character_
    ),
    file.path(de_plots_dir, "all_marker_matches.csv")
  )

  timestamp <- as.POSIXct("2026-10-16 12:00:00", tz = "UTC")
  pipeline_state <- new_pipeline_state(dataset_name, sample_name, timestamp)
  pipeline_state <- transition_pipeline_step(
    pipeline_state,
    "standardization",
    "completed",
    details = list(sample_count = 1L),
    timestamp = timestamp + 1
  )
  for (step in c(
    "clustering", "resolution", "differential_expression", "annotation",
    "cna_configuration"
  )) {
    pipeline_state <- transition_pipeline_step(
      pipeline_state,
      step,
      "completed",
      sample = sample_name,
      force = TRUE,
      timestamp = timestamp + match(step, PIPELINE_SAMPLE_STEPS)
    )
  }
  save_pipeline_state_atomic(
    pipeline_state,
    dataset_dir,
    state_filename = config$config_files$state,
    timestamp = timestamp + 20
  )

  invisible(dataset_name)
}

make_ui_baseline_app <- function(source_app_dir, .local_envir = parent.frame()) {
  test_app_dir <- withr::local_tempdir(
    pattern = "scannotation-ui-",
    .local_envir = .local_envir
  )
  dir.create(file.path(test_app_dir, "util_scripts"))
  dir.create(file.path(test_app_dir, "app"))
  dir.create(file.path(test_app_dir, "templates"))
  dir.create(file.path(test_app_dir, "R"))
  file.copy(file.path(source_app_dir, "DESCRIPTION"), file.path(test_app_dir, "DESCRIPTION"))
  file.copy(file.path(source_app_dir, "R", "_disable_autoload.R"), file.path(test_app_dir, "R", "_disable_autoload.R"))

  file.copy(
    file.path(source_app_dir, "app.R"),
    file.path(test_app_dir, "app.R")
  )
  file.copy(file.path(source_app_dir, "README.md"), file.path(test_app_dir, "README.md"))
  file.copy(
    list.files(
      file.path(source_app_dir, "util_scripts"),
      pattern = "[.]R$",
      full.names = TRUE
    ),
    file.path(test_app_dir, "util_scripts")
  )

  component_root <- file.path(source_app_dir, "app")
  component_files <- list.files(
    component_root,
    pattern = "[.]R$",
    recursive = TRUE,
    full.names = TRUE
  )
  component_relative_paths <- substring(
    component_files,
    nchar(component_root) + 2L
  )
  component_destinations <- file.path(
    test_app_dir,
    "app",
    component_relative_paths
  )
  invisible(lapply(
    unique(dirname(component_destinations)),
    dir.create,
    recursive = TRUE,
    showWarnings = FALSE
  ))
  file.copy(component_files, component_destinations)

  file.copy(
    list.files(
      file.path(source_app_dir, "templates"),
      full.names = TRUE
    ),
    file.path(test_app_dir, "templates")
  )

  config <- yaml::read_yaml(file.path(source_app_dir, "general_config.yaml"))
  yaml::write_yaml(config, file.path(test_app_dir, "general_config.yaml"))
  make_portable_ui_fixture(test_app_dir)

  test_app_dir
}
