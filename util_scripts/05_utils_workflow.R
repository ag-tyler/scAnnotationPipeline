# ==================================================================================================
# Script: 05_utils_workflow.R
# Purpose: Collection of workflow functions.
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# 1. Environment & Packages
# --------------------------------------------------------------------------------------------------

library(docstring)


# Cache dependency builders ---------------------------------------------------

.cache_config_values <- function(config, parameter_names) {
  params <- config$params
  if (is.null(params) || !all(parameter_names %in% names(params))) return(NULL)
  params[parameter_names]
}


filter_cache_dependencies <- function(paths_list, sample_idx, config) {
  parameters <- .cache_config_values(
    config,
    c("min_genes", "target_sum", "log2_expr_threshold")
  )
  if (is.null(parameters)) return(NULL)
  cell_input <- data.table::fread(
    paths_list$cell_file_paths[[sample_idx]],
    showProgress = FALSE
  )
  cell_input <- as.data.frame(cell_input[, intersect(
    c("cell_name", "sample", "complexity"),
    names(cell_input)
  ), with = FALSE])
  cache_dependency_spec(
    files = c(
      expression = paths_list$expmat_file_paths[[sample_idx]],
      genes = paths_list$genes_file_paths[[sample_idx]]
    ),
    values = list(
      cells_input = cell_input,
      filter_parameters = parameters,
      implementation = "filter-v1"
    )
  )
}


clustering_cache_dependencies <- function(paths_list, sample_idx, config, resolution) {
  parameters <- .cache_config_values(
    config,
    c(
      "min_genes", "target_sum", "log2_expr_threshold", "pca_nv",
      "seed", "umap"
    )
  )
  if (is.null(parameters)) return(NULL)
  cell_input <- data.table::fread(
    paths_list$cell_file_paths[[sample_idx]],
    showProgress = FALSE
  )
  cell_input <- as.data.frame(cell_input[, intersect(
    c("cell_name", "sample", "complexity"),
    names(cell_input)
  ), with = FALSE])
  cache_dependency_spec(
    files = c(
      expression = paths_list$expmat_file_paths[[sample_idx]],
      genes = paths_list$genes_file_paths[[sample_idx]]
    ),
    values = list(
      cells_input = cell_input,
      clustering_parameters = parameters,
      resolution = as.numeric(resolution),
      implementation = "pca-umap-louvain-v1"
    )
  )
}


.cache_artifacts_if_registered <- function(filenames, dataset_dir_path) {
  manifest <- load_cache_manifest(dataset_dir_path)
  filenames[filenames %in% names(manifest$artifacts)]
}


cna_matrix_cache_dependencies <- function(
  sample_name,
  dataset_dir_path,
  gene_positions,
  ref_cells,
  resolution = NULL
) {
  upstream <- c(
    paste0("expmat_filt_", sample_name, ".qs2"),
    if (!is.null(resolution)) {
      paste0("cells_filt_clust_res_", resolution, "_", sample_name, ".qs2")
    } else character()
  )
  upstream <- .cache_artifacts_if_registered(upstream, dataset_dir_path)
  ref_identity <- as.data.frame(ref_cells)[, intersect(
    c("sample", "cell_name", "cell_type"),
    names(ref_cells)
  ), drop = FALSE]
  if ("cell_name" %in% names(ref_identity)) {
    ref_identity <- ref_identity[order(ref_identity$cell_name), , drop = FALSE]
  }
  cache_dependency_spec(
    values = list(
      gene_positions = gene_positions,
      reference_cells = ref_identity,
      implementation = "cna-matrix-v1"
    ),
    artifacts = upstream,
    dataset_dir_path = dataset_dir_path
  )
}


cna_hclust_cache_dependencies <- function(sample_name, dataset_dir_path, selected_config) {
  cells_filename <- paste0(
    "cells_filt_clust_res_", selected_config$resolutions[[sample_name]],
    "_", sample_name, ".qs2"
  )
  cells_input <- tryCatch(
    cache_load_data(cells_filename, dataset_dir_path, recover = FALSE),
    error = function(error) NULL
  )
  if (!is.null(cells_input)) {
    cells_input <- as.data.frame(cells_input)
    annotation_column <- if ("cell_type_pre_cna" %in% names(cells_input)) {
      "cell_type_pre_cna"
    } else "cell_type"
    cells_input <- cells_input[, intersect(
      c("cell_name", "sample", annotation_column),
      names(cells_input)
    ), drop = FALSE]
    names(cells_input)[names(cells_input) == annotation_column] <- "manual_cell_type"
    if ("cell_name" %in% names(cells_input)) {
      cells_input <- cells_input[order(cells_input$cell_name), , drop = FALSE]
    }
  }
  upstream <- .cache_artifacts_if_registered(
    paste0("cna_matrix_", sample_name, ".qs2"),
    dataset_dir_path
  )
  cache_dependency_spec(
    values = list(
      manually_annotated_cells = cells_input,
      potentially_malignant_cell_types = sort(as.character(
        selected_config$cna_pot_mal_cells[[sample_name]]
      )),
      implementation = "ward-d2-v1"
    ),
    artifacts = upstream,
    dataset_dir_path = dataset_dir_path
  )
}


cna_signal_cache_dependencies <- function(
  sample_name,
  subclone_i,
  ref_cells,
  selected_config,
  dataset_dir_path
) {
  upstream <- .cache_artifacts_if_registered(
    c(
      paste0("cna_matrix_", sample_name, ".qs2"),
      paste0("hclust_", sample_name, ".qs2")
    ),
    dataset_dir_path
  )
  ref_names <- sort(as.character(ref_cells$cell_name))
  cache_dependency_spec(
    values = list(
      cluster_selection = selected_config$cna_ward_ref_cluster[[sample_name]][[subclone_i]],
      reference_cells = ref_names,
      implementation = "cna-signal-correlation-v1"
    ),
    artifacts = upstream,
    dataset_dir_path = dataset_dir_path
  )
}

# --------------------------------------------------------------------------------------------------
# 2. Sample loading, filtering & clustering
# --------------------------------------------------------------------------------------------------


load_filter_cells_expmat <- function(cells_path, expmat_path, genes_path, config) {
  #' Load, Filter, and Normalize Single-Cell Expression Data
  #'
  #' A high-level workflow function that orchestrates the initial data ingestion and 
  #' Quality Control (QC) for a single-cell dataset. It loads raw matrices and metadata, 
  #' removes empty genes, filters cells based on minimum gene thresholds, applies 
  #' log-normalization, and filters genes by expression levels.
  #'
  #' @param cells_path Character. File path to the cell metadata (expected to contain a `cell_name` column).
  #' @param expmat_path Character. File path to the raw expression matrix.
  #' @param genes_path Character. File path to the gene list/names.
  #' @param config List. A configuration object containing workflow parameters. Expected to contain 
  #'   `config$params$min_genes`, `config$params$target_sum`, and `config$params$log2_expr_threshold`.
  #' @return A named list containing two objects: 
  #'   \itemize{
  #'     \item \code{cells_filt}: The filtered cell metadata dataframe.
  #'     \item \code{expmat_filt}: The filtered and log-normalized sparse expression matrix.
  #'   }
  required_params <- c("min_genes", "target_sum", "log2_expr_threshold")
  missing_params <- required_params[vapply(required_params, function(param) {
    value <- config$params[[param]]
    is.null(value) || length(value) != 1L || is.na(value) || !is.numeric(value) || !is.finite(value)
  }, logical(1))]
  if (length(missing_params) > 0L) {
    stop(
      "Dataset configuration requires finite numeric params: ",
      paste(missing_params, collapse = ", "), ". ",
      "Pass dataset_config.yaml settings to load_filter_cells_expmat().",
      call. = FALSE
    )
  }

  # Load files
  cells <- load_cells(cells_path)
  expmat <- load_expmat(expmat_path)
  genes <- load_genes(genes_path)
  
  
  # Prepare data
  rownames(expmat) <- genes
  colnames(expmat) <- cells$cell_name
  
  
  # Filtering
  # Remove empty and na genes
  expmat <- expmat[genes != '', ]; genes <- genes[genes != '']
  cells_filt <- filter_cell_gene_count(cells, expmat, config$params$min_genes)
  
  if (nrow(cells_filt) == 0) {
    stop(
      "No cells in '", cells_path, "' pass the min_genes filter (min_genes = ",
      config$params$min_genes, "). This usually means the standardized expression matrix ",
      "for this sample is empty/misaligned, or min_genes is too strict for this dataset. ",
      "Check Cells.csv 'complexity' values and the dimensions of the .mtx file for this sample.",
      call. = FALSE
    )
  }
  
  expmat_filt <- log_normalize_expmat(expmat, cells_filt$cell_name, config$params$target_sum)
  genes_filt <- gene_expr_filter(expmat_filt, config$params$target_sum, 
                                 config$params$log2_expr_threshold)
  expmat_filt <- expmat_filt[genes_filt, ]
  
  # Create list to return filtered objects
  return_list <- list(
    cells_filt = cells_filt,
    expmat_filt = expmat_filt
  )
  
  return(return_list)
}


pca_umap_louvain <- function(expmat_filt, cells_filt, dataset_config, selected_config, sample_name) {
  #' Perform Dimensionality Reduction and Clustering
  #'
  #' A high-level workflow function that executes the core analytical steps on a filtered 
  #' single-cell dataset. It calculates Principal Components (PCA), generates UMAP embeddings 
  #' for visualization, and identifies cell clusters using the Louvain algorithm at a 
  #' sample-specific resolution.
  #'
  #' @param expmat_filt Matrix/dgCMatrix. The fully filtered and normalized expression matrix.
  #' @param cells_filt Data.frame. The filtered cell metadata.
  #' @param dataset_config List. A configuration object containing core pipeline parameters. 
  #'   Expected to contain PCA settings (`dataset_config$params$pca_nv`), UMAP settings 
  #'   (`dataset_config$params$umap$spread`, `dataset_config$params$umap$min_dist`), and 
  #'   a random seed (`dataset_config$params$seed`).
  #' @param selected_config List. A configuration object containing user-selected or 
  #'   sample-specific settings. Expected to contain a list of sample-specific clustering 
  #'   resolutions (`selected_config$resolutions`).
  #' @param sample_name Character. The identifier for the current sample, used to look up 
  #'   the specific Louvain resolution in the `selected_config` list.
  #'
  #' @return Data.frame. The updated `cells_filt` metadata, now enriched with UMAP coordinates 
  #'   and Louvain cluster assignments.
  
  message('PCA + UMAP')
  # Clustering
  exp_pca <- run_expmat_pca(expmat_filt, dataset_config$params$pca_nv)
  exp_umap <- run_expmat_umap(exp_pca, ncol(expmat_filt), dataset_config$params$umap$spread, 
                              dataset_config$params$umap$min_dist, dataset_config$params$seed)
  message('Louvain clustering with res: ', selected_config$resolutions[[sample_name]])
  cells_filt <- louvain_clustering(exp_pca, exp_umap, cells_filt, 
                                   selected_config$resolutions[[sample_name]], 
                                   dataset_config$params$seed)
  
  return(cells_filt)
}





# --------------------------------------------------------------------------------------------------
# 3. Resolution finding, Diff expr. Analysis, Load annotation setup
# --------------------------------------------------------------------------------------------------



report_batch_progress <- function(
  progress_callback,
  operation,
  sample_name,
  sample_index,
  sample_total,
  stage,
  detail,
  sample_fraction,
  outcome = NULL,
  elapsed_seconds = NULL
) {
  sample_fraction <- max(0, min(1, as.numeric(sample_fraction)))
  fraction <- ((sample_index - 1) + sample_fraction) / sample_total

  message(
    "[", sample_index, "/", sample_total, "] ", sample_name,
    " | ", stage, " | ", detail,
    if (!is.null(elapsed_seconds)) {
      paste0(" | elapsed ", sprintf("%.1f", elapsed_seconds), "s")
    } else {
      ""
    }
  )

  if (is.function(progress_callback)) {
    progress_callback(
      operation = operation,
      sample_name = sample_name,
      sample_index = sample_index,
      sample_total = sample_total,
      stage = stage,
      detail = detail,
      outcome = outcome,
      fraction = fraction,
      elapsed_seconds = elapsed_seconds
    )
  }

  invisible(fraction)
}


cluster_all_samples <- function(
  paths_list,
  config,
  results_dir_path,
  dataset_dir_path,
  state_callback = NULL,
  progress_callback = NULL
) {
  #' Batch Process and Cluster Multiple Single-Cell Samples
  #'
  #' A top-level orchestration function that iterates over a list of sample paths. 
  #' For each sample, it executes the full preprocessing pipeline: data loading, 
  #' filtering, dimensionality reduction (PCA/UMAP), and Louvain clustering across 
  #' a defined set of resolutions. 
  #' 
  #' @param paths_list List. A named list containing parallel character vectors of file paths. 
  #'   Expected to contain: `sample_dir_paths`, `cell_file_paths`, `expmat_file_paths`, 
  #'   and `genes_file_paths`. All vectors must be of the same length.
  #' @param config List. A configuration object containing pipeline parameters. Expected to 
  #'   contain PCA/UMAP settings (`config$params`), a random seed (`config$params$seed`), 
  #'   and a vector of clustering resolutions to test (`config$params$resolutions`).
  #' @param results_dir_path Character. The absolute path to the directory where analysis results, 
  #'   plots, and summaries are saved for the current dataset.
  #' @param dataset_dir_path Character. The absolute path to the root directory of the current 
  #'   dataset, used primarily for locating and managing the `cache` subdirectory.
  #' @param state_callback Optional function called when each sample enters a workflow state.
  #' @param progress_callback Optional function receiving the shared batch-progress contract:
  #'   operation, sample identity and position, stage/detail, terminal outcome, overall fraction,
  #'   and elapsed seconds.
  #'
  #' @return None. This function is evaluated for its side effects (disk I/O).
  #'
  #' @section Side Effects:
  #' \itemize{
  #'   \item Creates a specific result directory for each sample.
  #'   \item Generates and saves UMAP plot PNGs for every requested clustering resolution.
  #'   \item Caches the filtered cell metadata (`cells_filt`) at each resolution using `qs2`.
  #'   \item Caches the final filtered expression matrix (`expmat_filt`) using `qs2`.
  #' }
  
  sample_dir_paths <- paths_list$sample_dir_paths
  cell_file_paths <- paths_list$cell_file_paths
  expmat_file_paths <- paths_list$expmat_file_paths
  genes_file_paths <- paths_list$genes_file_paths
  
  sample_total <- length(sample_dir_paths)
  batch_started_at <- proc.time()[["elapsed"]]
  completed_count <- 0L
  failed_count <- 0L
  on.exit({
    elapsed <- proc.time()[["elapsed"]] - batch_started_at
    message(
      "Clustering batch finished: completed=", completed_count,
      ", failed=", failed_count,
      ", skipped=0, not_run=", sample_total - completed_count - failed_count,
      ", elapsed=", sprintf("%.1f", elapsed), "s"
    )
  }, add = TRUE)

  for (i in seq_along(sample_dir_paths)) {
    sample_name <- basename(sample_dir_paths[[i]])
    sample_started_at <- proc.time()[["elapsed"]]
    sample_fraction <- 0
    sample_stage <- "starting"
    message(strrep("#", 80))
    message("[", i, "/", sample_total, "] Starting sample ", sample_name)
    report <- function(stage, detail, fraction, outcome = NULL) {
      sample_fraction <<- fraction
      sample_stage <<- stage
      report_batch_progress(
        progress_callback = progress_callback,
        operation = "clustering",
        sample_name = sample_name,
        sample_index = i,
        sample_total = sample_total,
        stage = stage,
        detail = detail,
        sample_fraction = fraction,
        outcome = outcome,
        elapsed_seconds = proc.time()[["elapsed"]] - sample_started_at
      )
    }

    tryCatch({
      report("loading_filtering", "Loading and filtering standardized inputs", 0.05)
      cells <- load_cells(cell_file_paths[i])
      loaded_sample_name <- unique(cells$sample)
      if (length(loaded_sample_name) == 1L && !is.na(loaded_sample_name)) {
        sample_name <- loaded_sample_name
      }
      if (is.function(state_callback)) {
        state_callback(sample_name, "in_progress")
      }
      results_list <- load_filter_cells_expmat(cell_file_paths[i], expmat_file_paths[i],
                                               genes_file_paths[i], config)
      cells_filt <- results_list$cells_filt
      expmat_filt <- results_list$expmat_filt
      rm(results_list)
      gc()

      # Set sample result dir
      result_sample_dir_path <- file.path(results_dir_path, sample_name)
      dir.create(result_sample_dir_path, showWarnings = FALSE)

      report("pca_umap", "Computing PCA and UMAP", 0.25)
      # Clustering
      exp_pca <- run_expmat_pca(expmat_filt, config$params$pca_nv)
      exp_umap <- run_expmat_umap(exp_pca, ncol(expmat_filt), config$params$umap$spread,
                                  config$params$umap$min_dist, config$params$seed)

      # Persist the filtered matrix before the resolution-specific artifacts.
      # Each artifact is registered only after serialization and validation.
      expmat_file_name <- paste0('expmat_filt_', sample_name, '.qs2')
      report("filtered_cache", "Caching the filtered expression matrix", 0.45)
      message('Caching: ', expmat_file_name)
      cache_save_data(
        expmat_filt,
        expmat_file_name,
        dataset_dir_path,
        dependencies = filter_cache_dependencies(paths_list, i, config),
        producer = "cluster_all_samples/filter"
      )

      # Graph based clustering
      # Try out several resolutions and save plots
      clust_plots_sample_dir_path <- file.path(result_sample_dir_path, '1_cluster_plots')
      dir.create(clust_plots_sample_dir_path, showWarnings = FALSE)
      message('Clustering')
      resolution_total <- length(config$params$resolutions)
      for (resolution_index in seq_along(config$params$resolutions)) {
        resolution <- config$params$resolutions[[resolution_index]]
        resolution_start <- 0.45 + 0.5 * (resolution_index - 1) / resolution_total
        report(
          "resolution",
          paste0(
            "Clustering, plotting, and caching resolution ", resolution,
            " (", resolution_index, " of ", resolution_total, ")"
          ),
          resolution_start
        )
        cells_filt <- louvain_clustering(exp_pca, exp_umap, cells_filt, resolution,
                                         config$params$seed)
        # Plotting
        plot_title <- paste0('Cluster of sample: ', sample_name, '; res=', resolution)
        clust_plot <- plot_clusters(cells_filt, plot_title, x_col = umap1, y_col = umap2,
                                    cluster_col = clust)
        # Save plot
        clust_plot_title <- paste0('clusters_plot_', sample_name, '_res_', resolution, '.png')
        clust_plot_path <- file.path(clust_plots_sample_dir_path, clust_plot_title)
        ggplot2::ggsave(filename = clust_plot_path, plot = clust_plot)

        # Caching processed data for later analysis
        data_file_name <- paste0('cells_filt_clust_res_', resolution, '_', sample_name, '.qs2')
        message('Caching: ', data_file_name)
        cache_save_data(
          cells_filt,
          data_file_name,
          dataset_dir_path,
          dependencies = clustering_cache_dependencies(paths_list, i, config, resolution),
          producer = "cluster_all_samples/clustering"
        )
        report(
          "resolution_complete",
          paste0("Resolution ", resolution, " complete"),
          0.45 + 0.5 * resolution_index / resolution_total
        )
      }

      if (is.function(state_callback)) {
        state_callback(
          sample_name,
          "completed",
          details = list(resolutions = config$params$resolutions)
        )
      }
      completed_count <- completed_count + 1L
      report("completed", "Clustering outputs complete", 1, outcome = "completed")
      message('Finished ', sample_name)
      message(strrep("#", 80))
    }, error = function(error) {
      failed_count <<- failed_count + 1L
      if (is.function(state_callback)) {
        state_callback(sample_name, "failed", reason = conditionMessage(error))
      }
      failed_stage <- sample_stage
      report(
        failed_stage,
        paste0("Failed during ", failed_stage, ": ", conditionMessage(error)),
        sample_fraction,
        outcome = "failed"
      )
      message(strrep("#", 80))
      stop(error)
    })
  }
}


single_de_analysis <- function(sample_idx, paths_list, dataset_config, selected_config, 
                               complete_markers, results_dir_path, dataset_dir_path,
                               progress_callback = NULL) {
  #' Perform Differential Expression Analysis and Marker Scoring for a Single Sample
  #'
  #' @param sample_idx Integer. The index of the sample to process within the paths_list.
  #' @param paths_list List. A named list containing parallel character vectors of file paths. 
  #' @param dataset_config List. A configuration object containing core pipeline parameters. 
  #' @param selected_config List. A configuration object containing user-selected or 
  #'   sample-specific settings. 
  #' @param complete_markers Data.frame/List. A reference dataset containing known marker 
  #'   genes to map against the DE results.
  #' @param results_dir_path Character. The absolute path to the directory where analysis results, 
  #'   plots, and summaries are saved for the current dataset.
  #' @param dataset_dir_path Character. The absolute path to the root directory of the current 
  #'   dataset, used primarily for locating and managing the `cache` subdirectory.
  #' @param progress_callback Optional per-sample function receiving stage, detail, and the
  #'   within-sample fraction. The batch wrapper maps this to the shared progress contract.
  #'
  #' @return None. Evaluated entirely for its side effects (disk I/O).
  
  # Extract paths for this specific sample
  cell_file_path <- paths_list$cell_file_paths[sample_idx]
  expmat_file_path <- paths_list$expmat_file_paths[sample_idx]
  genes_file_path <- paths_list$genes_file_paths[sample_idx]
  
  # Load cells table to get current sample name
  cells <- load_cells(cell_file_path)
  sample_name <- unique(cells$sample)
  message('Working on sample: ', sample_name)
  if (is.function(progress_callback)) {
    progress_callback(
      "input_loading",
      "Loading validated clustered inputs and caches",
      0.05
    )
  }
  
  cells_filt_file_name <- paste0('cells_filt_clust_res_', selected_config$resolutions[[sample_name]], 
                                 '_', sample_name, '.qs2')
  expmat_filt_file_name <- paste0('expmat_filt_', sample_name, '.qs2')
  filter_dependencies <- filter_cache_dependencies(paths_list, sample_idx, dataset_config)
  cluster_dependencies <- clustering_cache_dependencies(
    paths_list,
    sample_idx,
    dataset_config,
    selected_config$resolutions[[sample_name]]
  )
  
  if (cache_check_valid(expmat_filt_file_name, dataset_dir_path, filter_dependencies) &
      cache_check_valid(cells_filt_file_name, dataset_dir_path, cluster_dependencies)) {
    message('Loading cached files.')
    cells_filt <- cache_load_data(
      cells_filt_file_name,
      dataset_dir_path,
      dependencies = cluster_dependencies
    )
    expmat_filt <- cache_load_data(
      expmat_filt_file_name,
      dataset_dir_path,
      dependencies = filter_dependencies
    )
  } else {
    message('No cached files.')
    
    results_list <- load_filter_cells_expmat(cell_file_path, expmat_file_path, 
                                             genes_file_path, dataset_config)
    cells_filt <- results_list$cells_filt
    expmat_filt <- results_list$expmat_filt
    rm(results_list)
    gc()
    
    cells_filt <- pca_umap_louvain(expmat_filt, cells_filt, dataset_config, selected_config, 
                                   sample_name)
  }
  
  # Set sample result dir
  result_sample_dir_path <- file.path(results_dir_path, sample_name)
  dir.create(result_sample_dir_path, showWarnings = FALSE)
  
  message('Starting differential expression analysis')
  if (is.function(progress_callback)) {
    progress_callback(
      "differential_expression",
      "Calculating cluster differential expression",
      0.25
    )
  }
  # Set differential expression analysis parameters
  de_parameters <- list(
    clusters = natural_cluster_order(cells_filt$clust),
    col_name = 'clust',
    marker_cell_type_col_name = 'cell_type',
    cluster_type_name = 'cluster' # Name of the type of clusters used (e.g. cluster or cell type)
  )
  de_parameters <- append(de_parameters, dataset_config$params$de)
  
  de_clust <- mean_diff_exp(expmat_filt, cells_filt, de_parameters)
  
  # Get list of data tables with matched marker genes per cluster
  if (is.function(progress_callback)) {
    progress_callback(
      "marker_matching",
      "Matching differential-expression genes to marker sets",
      0.5
    )
  }
  de_clusters_list <- match_marker_genes(de_clust, complete_markers, de_parameters)
  
  # Build counts data table of marker genes found per cell
  clusters_marker_counts <- count_matched_marker_genes(de_clusters_list, complete_markers, 
                                                       de_parameters)
  
  # Plot de clusters
  # Plot stacked bar chart of counts
  if (is.function(progress_callback)) {
    progress_callback(
      "scoring_plotting",
      "Scoring cells and generating marker plots",
      0.7
    )
  }
  gene_count_plot <- stacked_gene_match_count_plot(clusters_marker_counts, de_parameters, 
                                                   selected_config$resolutions[[sample_name]])
  
  # Save bar chart plots
  de_plots_dir_path <- file.path(result_sample_dir_path, '2_de_plots')
  dir.create(de_plots_dir_path, showWarnings = FALSE)
  
  # stacked bar chart plot
  gene_count_plot_title <- paste0(
    'top_', de_parameters$max_match_genes,
    '_unannotated_gene_count_plot.png'
  )
  gene_count_plot_path <- file.path(de_plots_dir_path, gene_count_plot_title)
  ggplot2::ggsave(filename = gene_count_plot_path, plot = gene_count_plot)
  
  # Plot boxplot of score distributions of cluster
  marker_genes_for_scores <- marker_genes_in_expmat_genes(expmat_filt, complete_markers, 
                                                          dataset_config$params$max_marker_genes)
  
  marker_genes_found <- check_min_n_marker_genes(marker_genes_for_scores, 
                                                 de_parameters$min_marker_found)
  
  cells_scores <- score_and_fill_cells(expmat_filt, marker_genes_for_scores, cells_filt)
  
  marker_cell_types <- names(marker_genes_for_scores)
  for (curr_cluster in de_parameters$clusters) {
    score_plot <- sig_scores_cluster_boxplot(cells_scores, marker_cell_types, marker_genes_found, 
                                             curr_cluster, sample_name, 
                                             selected_config$resolutions[[sample_name]])
    
    score_plot_path <- file.path(de_plots_dir_path, paste0(curr_cluster, '.png'))
    save_signature_score_plot(score_plot, score_plot_path)
  }
  
  # Save the marker match tables as csv per cluster
  if (is.function(progress_callback)) {
    progress_callback(
      "output_writing",
      "Writing marker-match tables and final outputs",
      0.9
    )
  }
  all_matches_path <- file.path(de_plots_dir_path, 'all_marker_matches.csv')
  all_matches <- data.table::rbindlist(de_clusters_list)
  cluster_levels <- natural_cluster_order(all_matches$clust)
  all_matches[, cluster_display_order := match(as.character(clust), cluster_levels)]
  data.table::setorder(all_matches, cluster_display_order)
  all_matches[, cluster_display_order := NULL]
  data.table::fwrite(all_matches, file = all_matches_path)
  
  message('Finished ', sample_name)
}


de_analysis <- function(
  paths_list,
  dataset_config,
  selected_config,
  complete_markers,
  results_dir_path,
  dataset_dir_path,
  state_callback = NULL,
  progress_callback = NULL
) {
  #' Perform Differential Expression Analysis and Marker Scoring
  #'
  #' A high-level workflow function that iterates over multiple single-cell samples to 
  #' perform Differential Expression (DE) analysis on previously identified clusters. 
  #'
  #' @param paths_list List. A named list containing parallel character vectors of file paths. 
  #'   Expected to contain: `sample_dir_paths`, `cell_file_paths`, `expmat_file_paths`, 
  #'   and `genes_file_paths`.
  #' @param dataset_config List. A configuration object containing core pipeline parameters. 
  #'   Expected to contain DE parameters (`dataset_config$params$de`) and threshold 
  #'   settings (`dataset_config$params$max_marker_genes`).
  #' @param selected_config List. A configuration object containing user-selected or 
  #'   sample-specific settings. Expected to contain sample-specific clustering resolutions 
  #'   (`selected_config$resolutions`).
  #' @param complete_markers Data.frame/List. A reference dataset containing known marker 
  #'   genes associated with specific cell types to map against the DE results.
  #' @param results_dir_path Character. The absolute path to the directory where analysis results, 
  #'   plots, and summaries are saved for the current dataset.
  #' @param dataset_dir_path Character. The absolute path to the root directory of the current 
  #'   dataset, used primarily for locating and managing the `cache` subdirectory.
  #' @param state_callback Optional function called when each sample enters a workflow state.
  #' @param progress_callback Optional function receiving the shared batch-progress contract:
  #'   operation, sample identity and position, stage/detail, terminal outcome, overall fraction,
  #'   and elapsed seconds.
  #'
  #' @return None. This function is evaluated entirely for its side effects (disk I/O).
  
  #'   in the parent/global environment, as they are not explicitly passed as arguments.
  sample_dir_paths <- paths_list$sample_dir_paths
  
  sample_total <- length(sample_dir_paths)
  batch_started_at <- proc.time()[["elapsed"]]
  completed_count <- 0L
  failed_count <- 0L
  on.exit({
    elapsed <- proc.time()[["elapsed"]] - batch_started_at
    message(
      "Differential-expression batch finished: completed=", completed_count,
      ", failed=", failed_count,
      ", skipped=0, not_run=", sample_total - completed_count - failed_count,
      ", elapsed=", sprintf("%.1f", elapsed), "s"
    )
  }, add = TRUE)

  # Iterate over all samples and route them to the single analysis workflow
  for (i in seq_along(sample_dir_paths)) {
    sample_name <- basename(sample_dir_paths[[i]])
    sample_started_at <- proc.time()[["elapsed"]]
    sample_fraction <- 0
    sample_stage <- "starting"
    message(strrep("#", 80))
    message("[", i, "/", sample_total, "] Starting sample ", sample_name)
    report <- function(stage, detail, fraction, outcome = NULL) {
      sample_fraction <<- fraction
      sample_stage <<- stage
      report_batch_progress(
        progress_callback = progress_callback,
        operation = "differential_expression",
        sample_name = sample_name,
        sample_index = i,
        sample_total = sample_total,
        stage = stage,
        detail = detail,
        sample_fraction = fraction,
        outcome = outcome,
        elapsed_seconds = proc.time()[["elapsed"]] - sample_started_at
      )
    }
    if (is.function(state_callback)) state_callback(sample_name, "in_progress")
    tryCatch({
      single_de_analysis(
        sample_idx = i,
        paths_list = paths_list,
        dataset_config = dataset_config,
        selected_config = selected_config,
        complete_markers = complete_markers,
        results_dir_path = results_dir_path,
        dataset_dir_path = dataset_dir_path,
        progress_callback = report
      )
      if (is.function(state_callback)) {
        state_callback(
          sample_name,
          "completed",
          details = list(resolution = selected_config$resolutions[[sample_name]])
        )
      }
      completed_count <- completed_count + 1L
      report("completed", "Differential-expression outputs complete", 1, outcome = "completed")
      message(strrep("#", 80))
    }, error = function(error) {
      failed_count <<- failed_count + 1L
      if (is.function(state_callback)) {
        state_callback(sample_name, "failed", reason = conditionMessage(error))
      }
      failed_stage <- sample_stage
      report(
        failed_stage,
        paste0("Failed during ", failed_stage, ": ", conditionMessage(error)),
        sample_fraction,
        outcome = "failed"
      )
      message(strrep("#", 80))
      stop(error)
    })
  }
}


cell_type_annotation_setup <- function(i, paths_list, results_dir_path, dataset_dir_path,
                                       complete_markers, dataset_config, selected_config) {
  #' Setup Data for Manual Cell Type Annotation
  #'
  #' A helper workflow function designed to retrieve the essential datasets required for 
  #' manual cell type annotation of a specific sample. It fetches the clustered cell metadata 
  #' (`cells_filt`) from the cache (or computes it if missing) and loads the pre-computed 
  #' differential expression marker matches (`all_matches`) generated by the `de_analysis` step.
  #'
  #' @param i Numeric/Integer. The index of the specific sample to process within the `paths_list` arrays.
  #' @param paths_list List. A named list containing parallel character vectors of file paths. 
  #'   Expected to contain: `sample_dir_paths`, `cell_file_paths`, `expmat_file_paths`, 
  #'   and `genes_file_paths`.
  #' @param results_dir_path Character. The base directory path where the pipeline's sample-specific 
  #'   result folders are stored.
  #' @param dataset_dir_path Character. The absolute path to the root directory of the current 
  #'   dataset, used primarily for locating and managing the `cache` subdirectory.
  #' @param complete_markers data.table. A reference table containing filtered marker genes and 
  #'   their corresponding cell types, used to map and score clusters during manual annotation. 
  #' @param dataset_config List. A configuration object containing core pipeline parameters. 
  #' @param selected_config List. A configuration object containing user-selected or 
  #'   sample-specific settings. 
  #'
  #' @return A named list containing two objects required for manual annotation: 
  #'   \itemize{
  #'     \item \code{cells_filt}: Data.frame. The fully filtered and clustered cell metadata.
  #'     \item \code{all_matches}: Data.table. The differential expression marker matches per cluster.
  #'   }
  
  sample_dir_paths <- paths_list$sample_dir_paths
  cell_file_paths <- paths_list$cell_file_paths
  expmat_file_paths <- paths_list$expmat_file_paths
  genes_file_paths <- paths_list$genes_file_paths
  
  # Load cells table to get current sample name
  cells <- load_cells(cell_file_paths[i])
  sample_name <- unique(cells$sample)
  message('Working on sample: ', sample_name)
  selected_resolution <- selected_config$resolutions[[sample_name]]
  if (
    is.null(selected_resolution) || length(selected_resolution) != 1L ||
      is.na(selected_resolution) || !is.numeric(selected_resolution) ||
      !is.finite(selected_resolution) || selected_resolution == 0
  ) {
    stop(
      "No valid clustering resolution is configured for sample '", sample_name, "'.",
      call. = FALSE
    )
  }
  cells_filt_file_name <- paste0('cells_filt_clust_res_', selected_resolution,
                                 '_', sample_name, '.qs2')
  expmat_filt_file_name <- paste0('expmat_filt_', sample_name, '.qs2')
  filter_dependencies <- filter_cache_dependencies(paths_list, i, dataset_config)
  cluster_dependencies <- clustering_cache_dependencies(
    paths_list,
    i,
    dataset_config,
    selected_config$resolutions[[sample_name]]
  )
  if (cache_check_valid(expmat_filt_file_name, dataset_dir_path, filter_dependencies)
      & cache_check_valid(cells_filt_file_name, dataset_dir_path, cluster_dependencies)) {
    message('Loading cached files.')
    cells_filt <- cache_load_data(
      cells_filt_file_name,
      dataset_dir_path,
      dependencies = cluster_dependencies
    )
    expmat_filt <- cache_load_data(
      expmat_filt_file_name,
      dataset_dir_path,
      dependencies = filter_dependencies
    )
  } else {
    message('No cached files.')
    
    results_list <- load_filter_cells_expmat(cell_file_paths[i], expmat_file_paths[i],
                                             genes_file_paths[i], dataset_config)
    cells_filt <- results_list$cells_filt
    expmat_filt <- results_list$expmat_filt
    rm(results_list)
    gc()
    
    cells_filt <- pca_umap_louvain(expmat_filt, cells_filt, dataset_config, selected_config, 
                                   sample_name)
  }
  
  # Set differential expression analysis parameters
  message('Starting differential expression analysis')
  # Set differential expression analysis parameters
  result_sample_dir_path <- file.path(results_dir_path, sample_name)
  de_plots_dir_path <- file.path(result_sample_dir_path, '2_de_plots')
  all_matches_path <- file.path(de_plots_dir_path, 'all_marker_matches.csv')
  all_matches <- data.table::fread(
    all_matches_path,
    colClasses = list(
      character = unique(complete_markers$cell_type)
    ),
    na.strings = ""
  )
  
  return_list <- list(
    cells_filt = cells_filt,
    all_matches = all_matches
  )
  
  return(return_list)
}



compute_cna_and_cache <- function(expmat, gene_positions, ref_cells, sample_name, dataset_dir_path) {
  #' Compute and Cache Copy Number Alteration (CNA) Matrix
  #'
  #' @description
  #' This function acts as a wrapper to first compute the Copy Number Alteration (CNA) 
  #' values from a gene expression matrix using \code{compute_cna()}. It then reshapes 
  #' the resulting long-format data into a wide matrix (genes by cells, rounded to 
  #' 4 decimal places), sorts the genes by genomic coordinates, and saves the matrix 
  #' to disk as a highly compressed \code{.qs2} file using \code{cache_save_data()}.
  #'
  #' @param expmat A numeric or sparse matrix of gene expression values, where rows are 
  #'   genes and columns are cells.
  #' @param gene_positions A \code{data.table} keyed by gene symbol, containing 
  #'   \code{symbol}, \code{chromosome_name}, and \code{start_position}.
  #' @param ref_cells A \code{data.table} containing reference cell annotations, 
  #'   including \code{cell_name} and \code{cell_type}.
  #' @param sample_name A character string representing the name of the sample. 
  #'   Used to construct the output filename (e.g., 'cna_matrix_{sample_name}.qs2').
  #' @param dataset_dir_path Character. The absolute path to the root directory of the current 
  #'   dataset, used primarily for locating and managing the `cache` subdirectory.
  #'
  #'
  #' @return None. The function saves the serialized CNA matrix to disk.
  
  expdt <- compute_cna(expmat, gene_positions, ref_cells)
  
  # Save CNA matrix:
  cna_mat <- data.table::dcast(
    expdt[, .(gene, chr, start_pos, cell_name, cna = round(cna, 4))],
    gene + chr + start_pos ~ cell_name
  )[order(chr, start_pos)]
  
  cna_mat_file_name <- paste0('cna_matrix_', sample_name, '.qs2')
  cache_save_data(
    cna_mat,
    cna_mat_file_name,
    dataset_dir_path,
    dependencies = cna_matrix_cache_dependencies(
      sample_name,
      dataset_dir_path,
      gene_positions,
      ref_cells
    ),
    producer = "compute_cna_and_cache"
  )
}


load_expdt_from_cna_matrix <- function(sample_name, dataset_dir_path) {
  #' Load and Melt Cached Copy Number Alteration (CNA) Matrix
  #'
  #' @description
  #' Retrieves a previously computed and cached CNA matrix from disk for a given 
  #' sample. It then converts (melts) the wide-format matrix back into a long-format 
  #' \code{data.table} suitable for downstream analysis. This is the companion 
  #' function to \code{compute_cna_and_cache()}.
  #'
  #' @param sample_name A character string representing the name of the sample. 
  #'   Used to locate the cached file (e.g., 'cna_matrix_{sample_name}.qs2').
  #' @param dataset_dir_path Character. The absolute path to the root directory of the current 
  #'   dataset, used primarily for locating and managing the `cache` subdirectory.
  #'
  #' @return A long-format \code{data.table} containing the columns \code{gene}, 
  #'   \code{chr}, \code{start_pos}, \code{cell_name}, and \code{cna}.
  
  cna_mat_file_name <- paste0('cna_matrix_', sample_name, '.qs2')
  cna_mat <- cache_load_data(cna_mat_file_name, dataset_dir_path)
  
  expdt <- data.table::melt(cna_mat, id.vars = c('gene', 'chr', 'start_pos'), variable.name = 'cell_name', 
                            value.name = 'cna', variable.factor = FALSE)
  return(expdt)
}


hclust_cluster_heatmap <- function(
  hdata,
  sample_name,
  ref_cells,
  chr_n,
  chr_lab,
  cells_filt,
  cna_plots_dir_path,
  dataset_dir_path,
  dependencies = NULL
) {
  #' Generate and Save Hierarchical Clustering CNA Heatmap
  #'
  #' @description
  #' Executes the full hierarchical clustering pipeline for a specific sample. 
  #' It reshapes the long-format CNA data, performs Ward.D2 clustering, caches 
  #' the clustering result, generates a dendrogram, a CNA heatmap, and a cell-type 
  #' annotation bar. Finally, it combines these elements and saves the composite 
  #' plot to disk as a PNG.
  #'
  #' @param hdata A \code{data.table} in long format containing \code{gene}, 
  #'   \code{cell_name}, and \code{cna} columns for the cells to be clustered.
  #' @param sample_name A character string representing the sample name.
  #' @param ref_cells A \code{data.table} of reference cells.
  #' @param chr_n A \code{data.table} containing chromosome gene counts 
  #'   (columns \code{chr} and \code{n}).
  #' @param chr_lab A named character vector for x-axis chromosome labels, 
  #'   where values are chromosome names and names are the center gene symbols.
  #' @param cells_filt A \code{data.table} containing cell metadata, specifically 
  #'   \code{cell_name} and \code{cell_type}.
  #' @param cna_plots_dir_path Path to the directory where the final plot is saved.
  #' @param dataset_dir_path Character. The absolute path to the root directory of the current 
  #'   dataset, used primarily for locating and managing the `cache` subdirectory.
  #'
  #' @return None. Saves the clustering object to cache and the plot to disk.
  
  required_hdata_columns <- c("gene", "cell_name", "cna")
  missing_hdata_columns <- setdiff(required_hdata_columns, names(hdata))
  if (length(missing_hdata_columns) > 0L) {
    cna_abort(paste(
      "CNA heatmap data are missing required columns:",
      paste(missing_hdata_columns, collapse = ", ")
    ))
  }
  if (nrow(hdata) == 0L || length(unique(hdata$gene)) == 0L) {
    cna_abort(
      "No candidate CNA values are available for the heatmap.",
      class = "cna_ineligible_error"
    )
  }
  candidate_cells <- unique(as.character(hdata$cell_name))
  if (length(candidate_cells) < 2L) {
    cna_abort(
      "CNA heatmap clustering requires at least two candidate cells.",
      class = "cna_ineligible_error"
    )
  }
  if (any(!is.finite(hdata$cna))) {
    cna_abort("CNA heatmap data contain non-finite values.")
  }

  hdata_cast <- data.table::dcast(hdata[, .(gene, cell_name, cna)],
                                  gene ~ cell_name)[, magrittr::set_rownames(as.matrix(.SD), gene), 
                                                    .SDcols = -'gene']
  if (any(!is.finite(hdata_cast))) {
    cna_abort("CNA heatmap casting produced missing or non-finite values.")
  }
  hclust_file_name <- paste0('hclust_', sample_name, '.qs2')
  if (cache_check_valid(hclust_file_name, dataset_dir_path, dependencies)) {
    clust_hclust <- cache_load_data(
      hclust_file_name,
      dataset_dir_path,
      dependencies = dependencies
    )
    if (!setequal(clust_hclust$labels, colnames(hdata_cast))) {
      cache_invalidate_artifacts(hclust_file_name, dataset_dir_path)
      clust_hclust <- hierarchical_clustering_cna(hdata_cast, method = 'ward.D2')
      cache_save_data(
        clust_hclust,
        hclust_file_name,
        dataset_dir_path,
        dependencies = dependencies,
        producer = "hclust_cluster_heatmap"
      )
    }
  } else {
    clust_hclust <- hierarchical_clustering_cna(hdata_cast, method = 'ward.D2')
    cache_save_data(
      clust_hclust,
      hclust_file_name,
      dataset_dir_path,
      dependencies = dependencies,
      producer = "hclust_cluster_heatmap"
    )
  }
  
  # Extract levels safely outside of data.table to prevent NSE scoping crashes
  ordered_cells <- clust_hclust$labels[clust_hclust$order]
  hdata[, cell_num_hclust := as.numeric(factor(cell_name, levels = ordered_cells))]
  
  hdata[, gene := factor(gene, levels = unique(gene))]
  
  # Dendrogram
  dend_hclust_plot <- dendrogram_plot(clust_hclust)
  
  htmp_hclust <- cna_heatmap(hdata, ref_cells, chr_n, chr_lab, cell_num_hclust)
  
  # Hclust: dend, cell_types bar, heatmap, legend with cell types and cna 
  hdata_hclust_cells <- with(clust_hclust, data.table::data.table(cell_name = labels, 
                                                                  cell_num = order(order)))
  # Safely merge bypassing NSE
  hdata_hclust_cells$cell_type <- cells_filt$cell_type[match(hdata_hclust_cells$cell_name, cells_filt$cell_name)]
  bar_cell_type_hclust <- cluster_or_cell_type_bar_plot(hdata_hclust_cells, 'cell_type', 'Cell Type')
  
  
  combined_hclust_plot <- combine_cna_plots('ward', htmp_hclust, bar_cell_type_hclust, NULL, 
                                            dend_hclust_plot)
  # Save final plots
  combined_hclust_plot_path <- file.path(cna_plots_dir_path, 'hclust.png')
  ggplot2::ggsave(combined_hclust_plot_path, combined_hclust_plot, width = 300, height = 400, 
                  units = 'mm', bg = 'white')
}


cna_clustering_and_heatmaps <- function(ref_cells, sample_name, selected_config, cna_plots_dir_path,
                                        dataset_dir_path) {
  #' Master Orchestration for CNA Clustering and Heatmap Generation
  #'
  #' @description
  #' Acts as the main wrapper to prepare data for clustering and visualization. 
  #' It loads cached cell metadata and the computed CNA matrix, annotates cell types, 
  #' filters out chromosomes with insufficient genes, computes chromosome label 
  #' coordinates for the x-axis, and subsets the data to potentially malignant 
  #' or unassigned cells. Finally, it passes the prepared data to 
  #' \code{hclust_cluster_heatmap()}.
  #'
  #' @param ref_cells A \code{data.table} containing reference cell annotations.
  #' @param sample_name A character string specifying the sample to process.
  #' @param selected_config A configuration list containing clustering resolutions 
  #'   (\code{resolutions[[sample_name]]}) and lists of potentially malignant cells 
  #'   (\code{cna_pot_mal_cells[[sample_name]]}).
  #' @param cna_plots_dir_path Path to the directory where the final plots will be saved.
  #' @param dataset_dir_path Character. The absolute path to the root directory of the current 
  #'   dataset, used primarily for locating and managing the `cache` subdirectory.
  #'
  #' @return None. Triggers the clustering pipeline and plot saving.  
  
  
  cells_filt_file_name <- paste0('cells_filt_clust_res_', selected_config$resolutions[[sample_name]], 
                                 '_', sample_name, '.qs2')
  cells_filt <- cache_load_data(cells_filt_file_name, dataset_dir_path)
  
  if ("cell_type_pre_cna" %in% names(cells_filt)) {
    cells_filt[, cell_type := cell_type_pre_cna]
  }
  cells_filt[is.na(cell_type), cell_type := 'Unassigned']
  
  expdt <- load_expdt_from_cna_matrix(sample_name, dataset_dir_path)
  required_expdt_columns <- c("gene", "chr", "start_pos", "cell_name", "cna")
  missing_expdt_columns <- setdiff(required_expdt_columns, names(expdt))
  if (length(missing_expdt_columns) > 0L || nrow(expdt) == 0L) {
    cna_abort("The cached CNA matrix is empty or missing required columns.")
  }
  if (any(!is.finite(expdt$cna))) {
    cna_abort("The cached CNA matrix contains non-finite values.")
  }
  
  # Add cell types bypassing data.table NSE using explicit Base R syntax:
  expdt$cell_type <- cells_filt$cell_type[match(expdt$cell_name, cells_filt$cell_name)]
  expdt <- expdt[!is.na(expdt$cell_type)]
  
  # Exclude chromosomes with too few genes:
  chr_n <- expdt[, .(n = length(unique(gene))), keyby = chr][n > 20]
  if (nrow(chr_n) == 0L) {
    cna_abort(
      "No chromosome has more than 20 positioned genes; CNA heatmaps are not applicable.",
      class = "cna_ineligible_error"
    )
  }
  expdt <- expdt[chr %in% chr_n$chr]
  
  # Get x coordinates for axis labels:
  chr_lab <- c('01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12', '14', '16', 
               '17', '18', '19', '20', '22', 'X')
  chr_lab <- unique(expdt[, .(gene, chr)])[,{
    inds <- chr_n[, floor(cumsum(n) - n/2)[chr %in% chr_lab]]; 
    setNames(gsub('^0', '', chr[inds]), as.character(gene)[inds])
  }
  ]
  
  # Heatmap data:
  hdata <- data.table::copy(expdt[cell_type == 'Unassigned' 
                                  | cell_type %in% selected_config$cna_pot_mal_cells[[sample_name]]])
  if (length(unique(hdata$cell_name)) < 2L) {
    cna_abort(
      "Fewer than two potentially malignant or unassigned cells remain for CNA heatmap clustering.",
      class = "cna_ineligible_error"
    )
  }
  
  message('Run ward clustering')
  hclust_cluster_heatmap(
    hdata,
    sample_name,
    ref_cells,
    chr_n,
    chr_lab,
    cells_filt,
    cna_plots_dir_path,
    dataset_dir_path,
    dependencies = cna_hclust_cache_dependencies(
      sample_name,
      dataset_dir_path,
      selected_config
    )
  )
}


compute_signal_cor_cna <- function(sample_name, subclone_i, ref_cells, selected_config, 
                                   dataset_dir_path) {
  #' Compute Copy Number Alteration (CNA) Signal and Correlation Metrics
  #'
  #' @description
  #' Calculates two key metrics for evaluating cell malignancy: the "CNA signal" 
  #' (mean squared CNA value across hotspot genes) and the "CNA correlation" 
  #' (Pearson correlation of a cell's profile against the mean candidate malignant profile). 
  #' It identifies candidate malignant cells by extracting a specific cluster using a 
  #' predefined `k` cut on the hierarchical clustering dendrogram. The resulting metrics 
  #' and cell type assignments ('Candidate malignant', 'Reference', or NA) are cached to disk.
  #'
  #' @param sample_name A character string representing the sample name to be processed.
  #' @param subclone_i A numeric or character identifier for the specific subclone 
  #'   being evaluated. Used for labeling the data, extracting the cluster config, 
  #'   and naming the output file.
  #' @param ref_cells A \code{data.table} containing reference cell annotations, 
  #'   used to identify normal reference cells for plotting and downstream analysis.
  #' @param selected_config A \code{list} containing user-selected configurations. 
  #'   Specifically requires \code{cna_ward_ref_cluster[[sample_name]][[subclone_i]]} 
  #'   to provide the \code{k} (total number of clusters) and \code{cluster} (target 
  #'   malignant cluster index) parameters.
  #' @param dataset_dir_path Character. The absolute path to the root directory of the current 
  #'   dataset, used primarily for locating and managing the `cache` subdirectory.
  #'
  #' @return None. Saves a \code{data.table} containing the calculated metrics 
  #'   to the cache directory as a \code{.qs2} file.
  
  cna_mat_file_name <- paste0('cna_matrix_', sample_name, '.qs2')
  cna_mat <- cache_load_data(cna_mat_file_name, dataset_dir_path)
  if (!all(c("gene", "chr", "start_pos") %in% names(cna_mat)) || nrow(cna_mat) == 0L) {
    cna_abort("The cached CNA matrix is empty or has an invalid schema.")
  }
  
  expdt <- data.table::melt(cna_mat, id.vars = c('gene', 'chr', 'start_pos'), variable.name = 'cell_name', 
                            value.name = 'cna', variable.factor = FALSE)
  hclust_file_name <- paste0('hclust_', sample_name, '.qs2')
  clust_hclust <- cache_load_data(hclust_file_name, dataset_dir_path)
  
  # Get the cluster definition for this specific subclone from the config
  clust_id <- selected_config$cna_ward_ref_cluster[[sample_name]][[subclone_i]]
  if (is.null(clust_id$k) || is.null(clust_id$cluster)) {
    cna_abort("The selected CNA subclone is missing k or cluster settings.")
  }
  
  # Extract cells using the dynamic cutree method saved from the UI
  k_val <- clust_id$k
  clust_num <- clust_id$cluster
  if (
    length(k_val) != 1L || !is.numeric(k_val) || !is.finite(k_val) ||
      k_val < 2L || k_val > length(clust_hclust$labels)
  ) {
    cna_abort("The selected CNA cluster count k is outside the valid range.")
  }
  if (
    length(clust_num) != 1L || !is.numeric(clust_num) || !is.finite(clust_num) ||
      clust_num < 1L || clust_num > k_val
  ) {
    cna_abort("The selected malignant cluster identifier is outside the valid range.")
  }
  cell_names <- names(which(stats::cutree(clust_hclust, k = k_val) == clust_num))
  if (length(cell_names) == 0L) {
    cna_abort(
      "The selected malignant subclone contains no cells.",
      class = "cna_ineligible_error"
    )
  }
  
  # Genes with highest CNA values in candidate malignant cells:
  hotspot_genes <- expdt[cell_name %in% cell_names, .(m2 = mean(cna^2)), by = gene]
  if (nrow(hotspot_genes) == 0L || any(!is.finite(hotspot_genes$m2))) {
    cna_abort("The selected malignant subclone has no finite CNA signal values.")
  }
  hotspot_cutoff <- stats::quantile(hotspot_genes$m2, 0.9, na.rm = TRUE)
  hotspot_genes <- hotspot_genes[m2 > hotspot_cutoff, gene]
  if (length(hotspot_genes) == 0L) {
    cna_abort(
      "No hotspot genes exceed the CNA signal cutoff for the selected subclone.",
      class = "cna_ineligible_error"
    )
  }
  
  # Mean CNA profile of candidate malignant cells:
  cna_mat <- cna_mat[, magrittr::set_rownames(as.matrix(.SD), gene), 
                     .SDcols = -c('gene', 'chr', 'start_pos')]
  mal_mean <- rowMeans(cna_mat[, cell_names, drop = FALSE])
  mal_sd <- stats::sd(mal_mean)
  if (
    length(mal_mean) < 2L || any(!is.finite(mal_mean)) ||
      !is.finite(mal_sd) || mal_sd == 0
  ) {
    cna_abort("The malignant mean CNA profile is non-finite or has zero variance.")
  }
  
  # CNA signal and correlation:
  dt <- expdt[gene %in% hotspot_genes, .(cna_signal = mean(cna^2)), by = cell_name]
  correlations <- suppressWarnings(stats::cor(cna_mat, mal_mean))
  correlations <- correlations[, 1]
  if (any(!is.finite(correlations))) {
    bad_cells <- names(correlations)[!is.finite(correlations)]
    cna_abort(paste0(
      "CNA correlation is undefined for ", length(bad_cells),
      " cell(s), usually because their CNA profiles have zero variance."
    ))
  }
  dt[, cna_cor := correlations[cell_name]]
  if (nrow(dt) == 0L || any(!is.finite(dt$cna_signal)) || any(!is.finite(dt$cna_cor))) {
    cna_abort("CNA signal/correlation output is empty or non-finite.")
  }
  
  # Assign cells as candidate malignant, reference or NA. The NA cells could include candidate malignant cells that were excluded in the above downsampling step.
  dt[, ct := ifelse(cell_name %in% cell_names, 'Candidate malignant', 
                    ifelse(cell_name %in% ref_cells[sample == sample_name, cell_name], 'Reference', 
                           as.character(NA)))]
  dt[, c('sample', 'subclone') := .(sample_name, subclone_i)]
  data.table::setcolorder(dt, c('sample', 'subclone'))
  
  signal_cor_dt_name <- paste0('cna_sig_cor_', sample_name, '_subclone_', subclone_i, '.qs2')
  cache_save_data(
    dt,
    signal_cor_dt_name,
    dataset_dir_path,
    dependencies = cna_signal_cache_dependencies(
      sample_name,
      subclone_i,
      ref_cells,
      selected_config,
      dataset_dir_path
    ),
    producer = "compute_signal_cor_cna"
  )
}


cna_signal_axis_summary <- function(
  signal_tables,
  saved_thresholds = NULL,
  minimum_limit = 1,
  increment = 0.1
) {
  if (!is.list(signal_tables)) signal_tables <- list(signal_tables)
  signal_values <- unlist(lapply(signal_tables, function(x) {
    if (is.null(x) || !"cna_signal" %in% names(x)) return(numeric())
    as.numeric(x$cna_signal)
  }), use.names = FALSE)
  signal_values <- signal_values[is.finite(signal_values)]
  data_max <- if (length(signal_values) == 0L) 0 else max(signal_values)

  saved_limits <- unlist(lapply(saved_thresholds, function(x) x$y_max), use.names = FALSE)
  saved_limits <- suppressWarnings(as.numeric(saved_limits))
  saved_limits <- saved_limits[is.finite(saved_limits) & saved_limits > 0]
  saved_y_thresholds <- unlist(lapply(saved_thresholds, function(x) {
    c(x$m_y, x$nm_y)
  }), use.names = FALSE)
  saved_y_thresholds <- suppressWarnings(as.numeric(saved_y_thresholds))
  saved_y_thresholds <- saved_y_thresholds[
    is.finite(saved_y_thresholds) & saved_y_thresholds >= 0
  ]

  minimum_limit <- as.numeric(minimum_limit)
  increment <- as.numeric(increment)
  if (
    length(minimum_limit) != 1L || !is.finite(minimum_limit) || minimum_limit <= 0 ||
      length(increment) != 1L || !is.finite(increment) || increment <= 0
  ) {
    stop("CNA y-axis limits and increments must be positive finite numbers.", call. = FALSE)
  }

  recommended <- max(minimum_limit, ceiling(data_max / increment) * increment)
  selected <- if (length(saved_limits) == 0L) recommended else max(saved_limits)
  control_max <- max(3, recommended, selected, saved_y_thresholds, na.rm = TRUE)
  list(
    data_max = data_max,
    recommended = recommended,
    selected = selected,
    control_max = ceiling(control_max / increment) * increment
  )
}


apply_cna_thresholds <- function(sample_name, dataset_dir_path, selected_config, save = FALSE) {
  #' Apply Malignancy Thresholds and Assign Subclones
  #'
  #' @description 
  #' Evaluates cell-level Copy Number Alteration (CNA) signal and correlation metrics 
  #' against user-defined boundaries to definitively classify cells as 'Malignant' 
  #' (with a specific subclone ID) or 'Unassigned'. 
  #'
  #' @details
  #' This function applies strict rules to update the \code{cell_type} and \code{subclone} 
  #' classifications within the cached \code{cells_filt} data:
  #' \enumerate{
  #'   \item \strong{Threshold Evaluation:} For each defined subclone, the function identifies 
  #'         cells that exceed the malignant thresholds (\code{m_x}, \code{m_y}) and those that 
  #'         fall safely below the non-malignant thresholds (\code{nm_x}, \code{nm_y}).
  #'  \item \strong{Malignant Assignment & Collision Handling:} Only cell types explicitly
  #'         designated as potentially malignant are eligible to become 'Malignant'.
  #'         If a cell passes the malignant thresholds for exactly one subclone, it receives
  #'         that subclone's ID. If a cell passes the thresholds for multiple subclones,
  #'         it remains classified as 'Malignant' but its subclone is set to NA because the
  #'         specific subclone assignment is ambiguous.
  #'   \item \strong{Intermediate Zone Handling:} Any cell that was evaluated for CNA metrics 
  #'         (\code{tested_cells}) but was not classified as 'Malignant' is checked against the 
  #'         non-malignant thresholds. If it does not safely fall below the non-malignant 
  #'         boundaries for \emph{all} subclones, it is caught in the "gray zone" and overwritten 
  #'         as 'Unassigned'.
  #' }
  #'
  #' @param sample_name Character. The identifier for the sample being processed (e.g., 'P01').
  #' @param dataset_dir_path Character. The root directory path of the current dataset, used 
  #'   to locate cached \code{.qs2} files.
  #' @param selected_config List. The global configuration list. Must contain:
  #'   \itemize{
  #'     \item \code{resolutions[[sample_name]]}: Used to locate the correct \code{cells_filt} cache.
  #'     \item \code{cna_pot_mal_cells[[sample_name]]}: Character vector of cell types allowed to become Malignant.
  #'     \item \code{cna_thresholds[[sample_name]]}: A list of subclone threshold lists containing \code{m_x}, \code{m_y}, \code{nm_x}, and \code{nm_y}.
  #'   }
  #' @param save Logical. If \code{TRUE}, the updated \code{cells_filt} is immediately saved back 
  #'   to the cache on disk. Defaults to \code{FALSE} (useful for in-memory previews).
  #'
  #' @return A \code{data.table} (\code{cells_filt}) containing the updated cell annotations. 
  #'   The \code{cell_type} column will reflect the new 'Malignant' or 'Unassigned' states where applicable, 
  #'   and a new \code{subclone} column (\code{integer}) will contain the assigned subclone ID 
  #'   (or \code{NA} for non-malignant/unassigned cells).
  
  cells_file <- paste0('cells_filt_clust_res_', selected_config$resolutions[[sample_name]], '_', sample_name, '.qs2')
  cells_filt <- cache_load_data(cells_file, dataset_dir_path)
  
  if ("cell_type_pre_cna" %in% names(cells_filt)) {
    cells_filt[, cell_type := cell_type_pre_cna]
  }
  cells_filt[is.na(cell_type), cell_type := 'Unassigned']
  
  pot_mal_cells <- selected_config$cna_pot_mal_cells[[sample_name]]
  thresh_list <- selected_config$cna_thresholds[[sample_name]]
  
  # FIX 1: Explicitly remove the column if it exists to reset its internal type to integer
  if ("subclone" %in% names(cells_filt)) {
    cells_filt[, subclone := NULL]
  }
  cells_filt[, subclone := NA_integer_]
  
  # 1. Isolate cells that pass thresholds for each subclone
  subclones <- list()
  nonmalig_lists <- list()
  tested_cells <- character()
  
  for (i in seq_along(thresh_list)) {
    sig_cor_file <- paste0('cna_sig_cor_', sample_name, '_subclone_', i, '.qs2')
    if (cache_check_valid(sig_cor_file, dataset_dir_path)) {
      cna_sig_cor <- cache_load_data(sig_cor_file, dataset_dir_path)
      tested_cells <- unique(c(tested_cells, cna_sig_cor$cell_name))
      
      t_vals <- thresh_list[[i]]
      
      # Cells passing malignant thresholds
      subclones[[i]] <- cna_sig_cor[cna_cor > t_vals$m_x & cna_signal > t_vals$m_y, cell_name]
      
      # Cells passing non-malignant thresholds
      nonmalig_lists[[i]] <- cna_sig_cor[cna_cor < t_vals$nm_x & cna_signal < t_vals$nm_y, cell_name]
    }
  }
  
  allowed_types <- c(pot_mal_cells, 'Unassigned')
  
  # 2: Vectorized subclone assignment (No more 'by = cell_name' looping)
  if (length(subclones) == 1) {
    cells_filt[cell_type %in% allowed_types & cell_name %in% subclones[[1]], 
               c('cell_type', 'subclone') := list('Malignant', 1L)]
  } else if (length(subclones) > 1) {
    
    # Pre-calculate cells that passed ANY threshold and those that collided
    all_passing_cells <- unlist(subclones)
    collision_cells <- unique(all_passing_cells[duplicated(all_passing_cells)])
    
    # Assign unique subclones
    for (i in seq_along(subclones)) {
      valid_cells <- setdiff(subclones[[i]], collision_cells)
      
      cells_filt[
        cell_type %in% allowed_types & cell_name %in% valid_cells,
        c('cell_type', 'subclone') := list('Malignant', as.integer(i))
      ]
    }
    
    # Handle collisions: Always Malignant, but drop the specific subclone assignment
    if (length(collision_cells) > 0) {
      cells_filt[
        cell_type %in% allowed_types & cell_name %in% collision_cells,
        c('cell_type', 'subclone') := list('Malignant', NA_integer_)
      ]
    }
  }
  
  # 3. Mark as Unassigned those tested cells which are not Malignant and which do not fall below the thresholds for non-malignant cells:
  if (length(nonmalig_lists) > 0) {
    cells_filt[cell_name %in% tested_cells & cell_type != 'Malignant' & !(cell_name %in% Reduce(intersect, nonmalig_lists)), 
               cell_type := 'Unassigned']
  }
  
  if (save) {
    cache_save_data(cells_filt, cells_file, dataset_dir_path)
  }
  
  return(cells_filt)
}


cna_preview_fingerprint <- function(sample_name, dataset_dir_path, selected_config) {
  resolution <- selected_config$resolutions[[sample_name]]
  thresholds <- selected_config$cna_thresholds[[sample_name]]
  artifacts <- c(
    paste0('cells_filt_clust_res_', resolution, '_', sample_name, '.qs2'),
    paste0('cna_matrix_', sample_name, '.qs2'),
    paste0('cna_sig_cor_', sample_name, '_subclone_', seq_along(thresholds), '.qs2')
  )
  dependencies <- cache_dependency_spec(
    values = list(
      resolution = resolution,
      thresholds = thresholds,
      reference_types = selected_config$cna_ref_cells[[sample_name]],
      candidate_types = selected_config$cna_pot_mal_cells[[sample_name]],
      cluster_selection = selected_config$cna_ward_ref_cluster[[sample_name]]
    ),
    artifacts = artifacts,
    dataset_dir_path = dataset_dir_path
  )
  cache_dependency_fingerprint(dependencies)
}


preview_cna_summary <- function(sample_name, dataset_dir_path, selected_config) {
  #' Generate CNA Summary Previews (In-Memory)
  #'
  #' @description 
  #' Safely applies malignancy thresholds to classify cells and generates a comprehensive suite 
  #' of preview visualizations (UMAP, summary heatmap, and scatter plots) without modifying 
  #' the cached files on disk. This acts as a dry-run for the final step of the CNA pipeline.
  #'
  #' @details
  #' This wrapper function performs the following steps in memory:
  #' \enumerate{
  #'   \item Calls \code{apply_cna_thresholds()} with \code{save = FALSE} to temporarily label 
  #'         cells as 'Malignant', 'Unassigned', or leave them as their original non-malignant type.
  #'   \item Generates a UMAP projection colored by these new final assignments.
  #'   \item Loads the raw CNA matrix, excludes chromosomes with fewer than 20 genes, calculates 
  #'         genomic label coordinates, and organizes cells into sorted categories.
  #'   \item Downsamples the dataset (maximum of 200 cells per category using a fixed seed) to 
  #'         ensure rapid rendering, and generates a faceted summary heatmap.
  #'   \item Iterates through all defined subclones to generate signal vs. correlation scatter 
  #'         plots, re-colored with the updated cell assignments.
  #' }
  #'
  #' @param sample_name Character. The identifier for the sample being processed (e.g., 'P01').
  #' @param dataset_dir_path Character. The root directory path of the current dataset, used 
  #'   to locate cached \code{.qs2} data files.
  #' @param selected_config List. The globally selected configuration list containing user-defined 
  #'   parameters such as clustering resolutions, CNA reference cells, potentially malignant 
  #'   cells, and the malignancy thresholds.
  #'
  #' @return A named list containing six elements:
  #' \itemize{
  #'   \item \code{cells_filt}: Preview cell annotations.
  #'   \item \code{summary_heatmap}: Faceted CNA summary heatmap.
  #'   \item \code{pre_scatter_plots}: Signal/correlation plots using original annotations.
  #'   \item \code{post_scatter_plots}: Signal/correlation plots using preview CNA assignments.
  #'   \item \code{pre_umap_plot}: UMAP colored by saved pre-CNA annotations.
  #'   \item \code{umap_plot}: UMAP colored by preview CNA assignments.
  #' }
  #' 
  #' @seealso \code{\link{apply_cna_thresholds}}, \code{\link{summary_cna_heatmap}}, 
  #' \code{\link{cna_sig_cor_plot}}, \code{\link{plot_clusters}}
  
  # Load original cells_filt to get the pre-assignment annotations
  cells_file <- paste0('cells_filt_clust_res_', selected_config$resolutions[[sample_name]], '_', sample_name, '.qs2')
  cells_filt_orig <- cache_load_data(cells_file, dataset_dir_path)
  
  if ("cell_type_pre_cna" %in% names(cells_filt_orig)) {
    cells_filt_orig[, cell_type := cell_type_pre_cna]
  }
  
  cells_filt_orig[is.na(cell_type), cell_type := 'Unassigned']
  
  # 1. Update Cell Assignments (In memory, no save)
  cells_filt_new <- apply_cna_thresholds(sample_name, dataset_dir_path, selected_config, save = FALSE)
  
  # Generate before/after UMAP plots from the same saved embedding.
  pre_umap_plot <- plot_clusters(
    cells_filt_orig,
    paste0('Cell types of sample: ', sample_name),
    subtitle = 'Saved annotation before CNA assignment',
    x_col = umap1,
    y_col = umap2,
    cluster_col = cell_type
  )
  umap_plot <- plot_clusters(
    cells_filt_new,
    paste0('Cell types of sample: ', sample_name),
    subtitle = 'Preview after CNA assignment',
    x_col = umap1,
    y_col = umap2,
    cluster_col = cell_type
  )
  
  # 2. Load basic data and pass to the heatmap plot function
  expdt <- load_expdt_from_cna_matrix(sample_name, dataset_dir_path)
  ref_cells <- cells_filt_new[cell_type %in% selected_config$cna_ref_cells[[sample_name]]]
  summary_plot <- summary_cna_heatmap(expdt, cells_filt_new, ref_cells)
  
  # 3. Prepare Subclone Scatter Plots (Pre and Post assignment)
  thresh_list <- selected_config$cna_thresholds[[sample_name]]
  pre_scatter_plots <- list()
  post_scatter_plots <- list()
  signal_tables <- lapply(seq_along(thresh_list), function(i) {
    sig_cor_file <- paste0('cna_sig_cor_', sample_name, '_subclone_', i, '.qs2')
    if (!cache_check_valid(sig_cor_file, dataset_dir_path)) return(NULL)
    cache_load_data(sig_cor_file, dataset_dir_path)
  })
  axis <- cna_signal_axis_summary(signal_tables, saved_thresholds = thresh_list)
  shared_y_max <- axis$selected
  clip_caption <- if (shared_y_max < axis$data_max) {
    paste0(
      'Shared y-axis 0–', shared_y_max,
      '; values above the limit are visually clipped but remain in assignment calculations.'
    )
  } else {
    paste0('Shared y-axis 0–', shared_y_max, '.')
  }
  ward_refs <- selected_config$cna_ward_ref_cluster[[sample_name]]
  
  for (i in seq_along(thresh_list)) {
    if (!is.null(signal_tables[[i]])) {
      cna_sig_cor <- signal_tables[[i]]
      
      # Format threshold for plotting function
      malig_thresh <- list()
      malig_thresh[[sample_name]] <- list(thresh_list[[i]])
      
      # --- PRE-ASSIGNMENT SCATTER PLOT ---
      cna_sig_cor_pre <- data.table::copy(cna_sig_cor)
      cna_sig_cor_pre[cells_filt_orig, on = 'cell_name', ct := i.cell_type]
      
      cluster_label <- cna_cluster_labels(ward_refs[[i]]$cluster, ward_refs[[i]]$k)
      p_pre <- cna_sig_cor_plot(
        cna_sig_cor_pre,
        sample_name,
        malig_thresh,
        y_max = shared_y_max
      )
      p_pre <- p_pre + ggplot2::labs(
        subtitle = paste("Subclone", i, "—", cluster_label, "(Original Annotations)"),
        caption = clip_caption
      )
      pre_scatter_plots[[i]] <- p_pre
      
      # --- POST-ASSIGNMENT SCATTER PLOT ---
      cna_sig_cor_post <- data.table::copy(cna_sig_cor)
      cna_sig_cor_post[cells_filt_new, on = 'cell_name', ct := i.cell_type]
      
      p_post <- cna_sig_cor_plot(
        cna_sig_cor_post,
        sample_name,
        malig_thresh,
        y_max = shared_y_max
      )
      p_post <- p_post + ggplot2::labs(
        subtitle = paste("Subclone", i, "—", cluster_label, "(Preview Assignment)"),
        caption = clip_caption
      )
      post_scatter_plots[[i]] <- p_post
    }
  }
  
  return(list(
    cells_filt = cells_filt_new,
    summary_heatmap = summary_plot,
    pre_scatter_plots = pre_scatter_plots,
    post_scatter_plots = post_scatter_plots,
    pre_umap_plot = pre_umap_plot,
    umap_plot = umap_plot
  ))
}

cna_sample_preflight <- function(
  sample_name,
  selected_config,
  dataset_dir_path,
  gene_positions = NULL,
  pipeline_state = NULL,
  validate_expression = TRUE,
  minimum_reference_cells = 2L,
  minimum_candidate_cells = 2L,
  minimum_positioned_genes = 21L
) {
  #' Check whether one sample is ready and suitable for CNA analysis
  #'
  #' @return A structured list with `eligible`, `status`, `reasons`, `counts`,
  #'   and (when requested and valid) the loaded `cells`, `expmat`, and
  #'   `ref_cells`. Status is one of `eligible`, `incomplete`, `ineligible`,
  #'   `invalid`, or `omitted`.
  reasons <- character()
  categories <- character()
  add_reason <- function(category, reason) {
    categories <<- c(categories, category)
    reasons <<- c(reasons, reason)
  }
  counts <- list(
    total = NA_integer_,
    annotated = NA_integer_,
    unassigned = NA_integer_,
    configured_candidate = NA_integer_,
    candidate_total = NA_integer_,
    reference = NA_integer_,
    matrix_cells = NA_integer_,
    positioned_genes = NA_integer_
  )

  if (!is.null(pipeline_state)) {
    annotation_record <- get_pipeline_step(pipeline_state, "annotation", sample_name)
    configuration_record <- get_pipeline_step(
      pipeline_state,
      "cna_configuration",
      sample_name
    )
    if (!identical(annotation_record$status, "completed")) {
      add_reason(
        "incomplete",
        paste0("Annotation is ", annotation_record$status, "; save annotations first.")
      )
    }
    if (identical(configuration_record$status, "skipped")) {
      add_reason(
        "omitted",
        paste0(
          "CNA was explicitly omitted",
          if (!is.null(configuration_record$reason)) {
            paste0(": ", configuration_record$reason)
          } else "."
        )
      )
    } else if (!identical(configuration_record$status, "completed")) {
      add_reason(
        "incomplete",
        paste0(
          "CNA configuration is ", configuration_record$status,
          "; save reference and potentially malignant cell types first."
        )
      )
    }
  }

  resolution <- selected_config$resolutions[[sample_name]]
  if (
    is.null(resolution) || length(resolution) != 1L ||
      is.na(resolution) || !is.numeric(resolution) ||
      !is.finite(resolution) || resolution == 0
  ) {
    add_reason("incomplete", "No valid clustering resolution is saved.")
  }
  reference_types <- unique(as.character(
    selected_config$cna_ref_cells[[sample_name]]
  ))
  reference_types <- reference_types[
    !is.na(reference_types) & nzchar(trimws(reference_types))
  ]
  candidate_types <- unique(as.character(
    selected_config$cna_pot_mal_cells[[sample_name]]
  ))
  candidate_types <- candidate_types[
    !is.na(candidate_types) & nzchar(trimws(candidate_types))
  ]
  if (length(reference_types) == 0L) {
    add_reason("incomplete", "Reference cell types are not configured.")
  }
  if (length(candidate_types) == 0L) {
    add_reason("incomplete", "Potentially malignant cell types are not configured.")
  }

  cells_file <- if (
    length(resolution) == 1L && is.numeric(resolution) &&
      !is.na(resolution) && is.finite(resolution)
  ) {
    paste0("cells_filt_clust_res_", resolution, "_", sample_name, ".qs2")
  } else {
    NULL
  }
  expmat_file <- paste0("expmat_filt_", sample_name, ".qs2")
  cells_valid <- !is.null(cells_file) && isTRUE(tryCatch(
    cache_check_valid(cells_file, dataset_dir_path),
    error = function(error) FALSE
  ))
  expmat_valid <- isTRUE(tryCatch(
    cache_check_valid(expmat_file, dataset_dir_path),
    error = function(error) FALSE
  ))
  if (!cells_valid) {
    add_reason("incomplete", "The filtered clustering cell cache is missing or invalid.")
  }
  if (!expmat_valid) {
    add_reason("incomplete", "The filtered expression cache is missing or invalid.")
  }

  cells <- NULL
  expmat <- NULL
  ref_cells <- NULL
  if (cells_valid) {
    cells <- tryCatch(
      data.table::as.data.table(cache_load_data(cells_file, dataset_dir_path)),
      error = identity
    )
    if (inherits(cells, "error")) {
      add_reason("invalid", paste("Cell cache could not be loaded:", conditionMessage(cells)))
      cells <- NULL
    } else {
      required_cell_columns <- c("cell_name", "cell_type")
      missing_cell_columns <- setdiff(required_cell_columns, names(cells))
      if (length(missing_cell_columns) > 0L) {
        add_reason(
          "invalid",
          paste(
            "Cell cache is missing required columns:",
            paste(missing_cell_columns, collapse = ", ")
          )
        )
      } else {
        cell_types <- if ("cell_type_pre_cna" %in% names(cells)) {
          as.character(cells$cell_type_pre_cna)
        } else {
          as.character(cells$cell_type)
        }
        unassigned <- is.na(cell_types) | trimws(cell_types) %in% c("", "NA", "Unassigned")
        normalized_types <- cell_types
        normalized_types[unassigned] <- "Unassigned"
        cells[, cell_type := normalized_types]

        reference_mask <- normalized_types %in% reference_types
        configured_candidate_mask <- normalized_types %in% candidate_types
        candidate_mask <- (configured_candidate_mask | unassigned) & !reference_mask
        counts$total <- nrow(cells)
        counts$unassigned <- sum(unassigned)
        counts$annotated <- counts$total - counts$unassigned
        counts$reference <- sum(reference_mask)
        counts$configured_candidate <- sum(configured_candidate_mask & !reference_mask)
        counts$candidate_total <- sum(candidate_mask)
        ref_cells <- cells[reference_mask]

        if (length(reference_types) > 0L && counts$reference < minimum_reference_cells) {
          add_reason(
            "ineligible",
            paste0(
              "Only ", counts$reference, " reference cells match the configured types; at least ",
              minimum_reference_cells, " are required."
            )
          )
        }
        if (length(candidate_types) > 0L && counts$candidate_total < minimum_candidate_cells) {
          add_reason(
            "ineligible",
            paste0(
              "Only ", counts$candidate_total,
              " potentially malignant or unassigned cells are available; at least ",
              minimum_candidate_cells, " are required for clustering."
            )
          )
        }
      }
    }
  }

  if (validate_expression && expmat_valid) {
    expmat <- tryCatch(cache_load_data(expmat_file, dataset_dir_path), error = identity)
    if (inherits(expmat, "error")) {
      add_reason("invalid", paste("Expression cache could not be loaded:", conditionMessage(expmat)))
      expmat <- NULL
    } else {
      matrix_values <- if (inherits(expmat, "sparseMatrix")) expmat@x else as.vector(expmat)
      counts$matrix_cells <- ncol(expmat)
      if (!is.numeric(matrix_values) || any(!is.finite(matrix_values))) {
        add_reason("invalid", "The filtered expression matrix contains non-finite or non-numeric values.")
      }
      if (is.null(rownames(expmat)) || is.null(colnames(expmat))) {
        add_reason("invalid", "The filtered expression matrix must have gene and cell names.")
      } else if (!is.null(cells) && "cell_name" %in% names(cells)) {
        missing_matrix_cells <- setdiff(cells$cell_name, colnames(expmat))
        if (length(missing_matrix_cells) > 0L) {
          add_reason(
            "invalid",
            paste0(
              length(missing_matrix_cells),
              " annotated cells are absent from the filtered expression matrix."
            )
          )
        }
      }
      if (!is.null(gene_positions) && !is.null(rownames(expmat))) {
        position_symbols <- as.character(gene_positions$symbol)
        counts$positioned_genes <- sum(rownames(expmat) %in% position_symbols)
        if (counts$positioned_genes < minimum_positioned_genes) {
          add_reason(
            "ineligible",
            paste0(
              "Only ", counts$positioned_genes,
              " expression genes have genomic positions; at least ",
              minimum_positioned_genes, " are required."
            )
          )
        }
      }
    }
  }

  status <- if (length(reasons) == 0L) {
    "eligible"
  } else if ("omitted" %in% categories) {
    "omitted"
  } else if ("incomplete" %in% categories) {
    "incomplete"
  } else if ("invalid" %in% categories) {
    "invalid"
  } else {
    "ineligible"
  }

  structure(
    list(
      eligible = identical(status, "eligible"),
      status = status,
      reasons = unique(reasons),
      reason = if (length(reasons) == 0L) NULL else paste(unique(reasons), collapse = " "),
      counts = counts,
      reference_types = reference_types,
      candidate_types = candidate_types,
      cells_file = cells_file,
      expmat_file = expmat_file,
      cells = cells,
      expmat = expmat,
      ref_cells = ref_cells
    ),
    class = c("cna_preflight", "list")
  )
}


batch_compute_cna_and_heatmaps <- function(
  paths_list,
  dataset_dir_path,
  results_dir_path,
  selected_config,
  gene_positions,
  state_callback = NULL,
  progress_callback = NULL,
  sample_names = NULL,
  pipeline_state = NULL
) {
  #' Batch Compute CNA and Heatmaps for All Valid Samples
  #'
  #' @description Iterates over all samples in the dataset. Checks if both 
  #' `cna_ref_cells` and `cna_pot_mal_cells` are configured. If they are, 
  #' computes the CNA matrix (if not already cached) and generates the clustering heatmaps.
  #'
  #' @param paths_list List. Contains dataset paths.
  #' @param dataset_dir_path Character. Path to the dataset directory.
  #' @param results_dir_path Character. Path to the results directory.
  #' @param selected_config List. The current active configuration.
  #' @param gene_positions Data.table. Genomic positions of genes.
  #' 
  #' @return A list containing `processed` (character vector of processed sample names) 
  #' and `skipped` (character vector of skipped sample names).
  
  processed_samples <- character()
  skipped_samples <- character()
  failed_samples <- character()
  preflight_results <- list()
  
  sample_dirs <- paths_list$sample_dir_paths
  available_samples <- basename(sample_dirs)
  if (is.null(sample_names)) sample_names <- available_samples
  sample_names <- unique(as.character(sample_names))
  unknown_samples <- setdiff(sample_names, available_samples)
  if (length(unknown_samples) > 0L) {
    stop(
      "Unknown batch CNA samples: ", paste(unknown_samples, collapse = ", "),
      call. = FALSE
    )
  }
  sample_dirs <- sample_dirs[available_samples %in% sample_names]
  sample_total <- length(sample_dirs)

  report_progress <- function(sample_name, sample_index, stage, detail = NULL) {
    if (!is.function(progress_callback)) return(invisible(NULL))
    progress_callback(
      sample_name = sample_name,
      sample_index = sample_index,
      sample_total = sample_total,
      stage = stage,
      detail = detail
    )
    invisible(NULL)
  }
  
  for (i in seq_along(sample_dirs)) {
    s_name <- basename(sample_dirs[i])
    report_progress(s_name, i, "preflight", "Checking CNA eligibility")
    
    preflight <- cna_sample_preflight(
      s_name,
      selected_config,
      dataset_dir_path,
      gene_positions = gene_positions,
      pipeline_state = pipeline_state,
      validate_expression = TRUE
    )
    preflight_results[[s_name]] <- preflight

    # 1. Skip samples that are unfinished, invalid, or analytically ineligible.
    if (!isTRUE(preflight$eligible)) {
      configuration_missing <- any(grepl("not configured", preflight$reasons))
      missing_cache <- !configuration_missing && any(grepl(
        "cache is missing or invalid",
        preflight$reasons
      ))
      skip_label <- if (missing_cache) paste0(s_name, " (Missing Cache)") else s_name
      skipped_samples <- c(skipped_samples, skip_label)
      if (is.function(state_callback)) {
        state_callback(
          s_name,
          if (preflight$status %in% c("ineligible", "omitted")) "skipped" else "incomplete",
          reason = preflight$reason,
          details = list(preflight_status = preflight$status, counts = preflight$counts)
        )
      }
      report_progress(s_name, i, "skipped", preflight$reason)
      next
    }
    
    message("Batch processing CNA & Heatmaps for sample: ", s_name)
    
    if (is.function(state_callback)) state_callback(s_name, "in_progress")
    tryCatch({
      cells_filt <- preflight$cells
      expmat_filt <- preflight$expmat
      ref_cells <- preflight$ref_cells

      # 3. Compute CNA if missing
      cna_mat_file_name <- paste0('cna_matrix_', s_name, '.qs2')
      cna_dependencies <- cna_matrix_cache_dependencies(
        s_name,
        dataset_dir_path,
        gene_positions,
        ref_cells
      )
      if (!cache_check_valid(cna_mat_file_name, dataset_dir_path, cna_dependencies)) {
        report_progress(s_name, i, "cna_matrix", "Computing CNA matrix")
        cache_invalidate_sample(
          s_name,
          dataset_dir_path,
          artifact_types = c("cna_matrix", "cna_hclust", "cna_signal_correlation")
        )
        compute_cna_and_cache(expmat_filt, gene_positions, ref_cells, s_name, dataset_dir_path)
      } else {
        report_progress(s_name, i, "cna_matrix", "Reusing validated CNA matrix")
      }

      # 4. Generate Heatmaps
      report_progress(s_name, i, "heatmaps", "Generating CNA clustering and heatmaps")
      cna_plots_dir_path <- file.path(results_dir_path, s_name, '3_cna_plots')
      dir.create(cna_plots_dir_path, showWarnings = FALSE, recursive = TRUE)

      cna_clustering_and_heatmaps(ref_cells, s_name, selected_config, cna_plots_dir_path, dataset_dir_path)

      processed_samples <- c(processed_samples, s_name)
      report_progress(s_name, i, "completed", "CNA and heatmaps complete")
      if (is.function(state_callback)) {
        state_callback(
          s_name,
          "completed",
          details = list(reference_cell_count = nrow(ref_cells), batch = TRUE)
        )
      }
    }, error = function(error) {
      failed_samples[[s_name]] <<- conditionMessage(error)
      report_progress(s_name, i, "failed", conditionMessage(error))
      if (is.function(state_callback)) {
        state_callback(s_name, "failed", reason = conditionMessage(error))
      }
      message("CNA batch failed for ", s_name, ": ", conditionMessage(error))
    })
  }
  
  return(list(
    processed = processed_samples,
    skipped = skipped_samples,
    failed = failed_samples,
    preflight = preflight_results
  ))
}
