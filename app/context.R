# Immutable application configuration and resources.

create_app_context <- function(config_path = "general_config.yaml") {
  if (!file.exists(config_path)) {
    stop(
      config_path, " not found in the working directory (", getwd(), ").\n",
      "This app must be launched from its own directory — e.g. via ",
      "shiny::runApp('path/to/app'), or the RStudio 'Run App' button ",
      "with app.R open.",
      call. = FALSE
    )
  }

  config <- yaml::read_yaml(config_path)
  resources_dir_path <- config$paths$resources_dir
  resource_paths <- list(
    marker_genes = file.path(
      resources_dir_path,
      config$resource_files$marker_sets
    ),
    housekeeping_genes = file.path(
      resources_dir_path,
      config$resource_files$housekeeping_genes
    ),
    mt_genes = file.path(
      resources_dir_path,
      config$resource_files$mitochondrial_genes
    ),
    malignant_markers = file.path(
      resources_dir_path,
      config$resource_files$malignant_markers
    ),
    cancer_cell_map = file.path(
      resources_dir_path,
      config$resource_files$cancer_cell_map
    ),
    gene_positions = file.path(
      resources_dir_path,
      config$resource_files$gene_positions
    ),
    hgnc_complete_set = file.path(
      resources_dir_path,
      config$resource_files$hgnc_complete_set
    ),
    metadata_prompt = file.path(
      resources_dir_path,
      config$resource_files$metadata_prompt
    )
  )

  resource_labels <- c(
    marker_genes = "marker gene sets",
    housekeeping_genes = "housekeeping genes",
    mt_genes = "mitochondrial genes",
    malignant_markers = "malignant markers",
    cancer_cell_map = "cancer cell map",
    gene_positions = "gene positions",
    hgnc_complete_set = "HGNC complete set",
    metadata_prompt = "metadata extract prompt"
  )
  missing_names <- names(resource_paths)[
    !file.exists(unlist(resource_paths, use.names = FALSE))
  ]

  if (length(missing_names) > 0) {
    missing_lines <- paste0(
      " - ",
      resource_labels[missing_names],
      ": ",
      unlist(resource_paths[missing_names], use.names = FALSE)
    )
    stop(
      "The following resource files could not be found (check `resources_dir` in ",
      "general_config.yaml / local_config.yaml, and `resource_files` for correct filenames):\n",
      paste(missing_lines, collapse = "\n"),
      call. = FALSE
    )
  }

  marker_genes <- normalize_marker_table(
    data.table::fread(resource_paths$marker_genes),
    group_column = "cell_type",
    table_label = "Global cell-type marker resource"
  )
  marker_genes <- marker_genes[cell_type != "Malignant"]
  marker_genes[, cell_type := gsub(" ", "_", cell_type)]

  malignant_markers <- normalize_marker_table(
    data.table::fread(resource_paths$malignant_markers),
    group_column = "cancer_type",
    table_label = "Malignant marker resource"
  )
  housekeeping_genes <- data.table::fread(
    resource_paths$housekeeping_genes,
    header = FALSE
  )$V1
  mt_genes <- data.table::fread(
    resource_paths$mt_genes,
    header = FALSE
  )$V1
  cancer_cell_map <- jsonlite::read_json(resource_paths$cancer_cell_map)
  clipboard_text <- paste(
    readLines(resource_paths$metadata_prompt),
    collapse = "\n"
  )
  hgnc_complete_set <- data.table::fread(resource_paths$hgnc_complete_set)
  gene_positions <- data.table::fread(resource_paths$gene_positions)

  duplicate_ensembl_ids <- names(table(hgnc_complete_set$ensembl_gene_id))[
    table(hgnc_complete_set$ensembl_gene_id) > 1
  ]
  hgnc_complete_set <- hgnc_complete_set[
    !(ensembl_gene_id %in% duplicate_ensembl_ids)
  ]

  gene_positions[
    hgnc_complete_set,
    on = "ensembl_gene_id",
    c("symbol", "location") := .(i.symbol, i.location_sortable)
  ]
  gene_positions <- gene_positions[
    !is.na(hgnc_symbol) &
      chromosome_name %in% c(as.character(1:22), "X", "Y")
  ]
  gene_positions[
    chromosome_name %in% as.character(1:9),
    chromosome_name := paste0("0", chromosome_name)
  ]
  data.table::setkey(gene_positions, hgnc_symbol)

  dataset_base_dir <- config$paths$datasets_dir
  dir.create(dataset_base_dir, recursive = TRUE, showWarnings = FALSE)
  all_dataset_dirs <- list.dirs(dataset_base_dir, recursive = FALSE)
  available_datasets <- basename(
    all_dataset_dirs[all_dataset_dirs != dataset_base_dir]
  )

  list(
    config = config,
    paths = list(
      resources_dir = resources_dir_path,
      datasets_dir = dataset_base_dir,
      templates_dir = "templates"
    ),
    resource_paths = resource_paths,
    resources = list(
      marker_genes = marker_genes,
      malignant_markers = malignant_markers,
      housekeeping_genes = housekeeping_genes,
      mt_genes = mt_genes,
      cancer_cell_map = cancer_cell_map,
      clipboard_text = clipboard_text,
      hgnc_complete_set = hgnc_complete_set,
      gene_positions = gene_positions
    ),
    available_datasets = available_datasets,
    sample_choices = c("Please select a dataset first" = "")
  )
}
