# ==================================================================================================
# Script: 05_utils_workflow.R
# Purpose: Collection of workflow functions.
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# 1. Environment & Packages
# --------------------------------------------------------------------------------------------------

library(docstring)

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



cluster_all_samples <- function(paths_list, config, results_dir_path, dataset_dir_path) {
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
  
  for (i in seq_along(sample_dir_paths)) {
    # Load cells table to get current sample name
    cells <- load_cells(cell_file_paths[i])
    sample_name <- unique(cells$sample)
    message('Working on sample: ', sample_name)
    
    results_list <- load_filter_cells_expmat(cell_file_paths[i], expmat_file_paths[i], 
                                             genes_file_paths[i], config)
    cells_filt <- results_list$cells_filt
    expmat_filt <- results_list$expmat_filt
    rm(results_list)
    gc()
    
    # Set sample result dir
    result_sample_dir_path <- file.path(results_dir_path, sample_name)
    dir.create(result_sample_dir_path, showWarnings = FALSE)
    
    message('PCA + UMAP')
    # Clustering
    exp_pca <- run_expmat_pca(expmat_filt, config$params$pca_nv)
    exp_umap <- run_expmat_umap(exp_pca, ncol(expmat_filt), config$params$umap$spread, 
                                config$params$umap$min_dist, config$params$seed)
    # Graph based clustering
    # Try out several resolutions and save plots
    clust_plots_sample_dir_path <- file.path(result_sample_dir_path, '1_cluster_plots')
    dir.create(clust_plots_sample_dir_path, showWarnings = FALSE)
    message('Clustering')
    for (resolution in config$params$resolutions) {
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
      cache_save_data(cells_filt, data_file_name, dataset_dir_path)
    }
    # Caching processed data for later analysis
    data_file_name <- paste0('expmat_filt_', sample_name, '.qs2')
    message('Caching: ', data_file_name)
    cache_save_data(expmat_filt, data_file_name, dataset_dir_path)
    
    message('Finished ', sample_name)
  }
}


single_de_analysis <- function(sample_idx, paths_list, dataset_config, selected_config, 
                               complete_markers, results_dir_path, dataset_dir_path) {
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
  
  cells_filt_file_name <- paste0('cells_filt_clust_res_', selected_config$resolutions[[sample_name]], 
                                 '_', sample_name, '.qs2')
  expmat_filt_file_name <- paste0('expmat_filt_', sample_name, '.qs2')
  
  if (cache_check_exists(expmat_filt_file_name, dataset_dir_path) & 
      cache_check_exists(cells_filt_file_name, dataset_dir_path)) {
    message('Loading cached files.')
    cells_filt <- cache_load_data(cells_filt_file_name, dataset_dir_path)
    expmat_filt <- cache_load_data(expmat_filt_file_name, dataset_dir_path)
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
  # Set differential expression analysis parameters
  de_parameters <- list(
    clusters = unique(cells_filt$clust),
    col_name = 'clust',
    marker_cell_type_col_name = 'cell_type',
    cluster_type_name = 'cluster' # Name of the type of clusters used (e.g. cluster or cell type)
  )
  de_parameters <- append(de_parameters, dataset_config$params$de)
  
  de_clust <- mean_diff_exp(expmat_filt, cells_filt, de_parameters)
  
  # Get list of data tables with matched marker genes per cluster
  de_clusters_list <- match_marker_genes(de_clust, complete_markers, de_parameters)
  
  # Build counts data table of marker genes found per cell
  clusters_marker_counts <- count_matched_marker_genes(de_clusters_list, complete_markers, 
                                                       de_parameters)
  
  # Plot de clusters
  # Plot stacked bar chart of counts
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
    ggplot2::ggsave(filename = score_plot_path, plot = score_plot, dpi = 300)
  }
  
  # Save the marker match tables as csv per cluster
  all_matches_path <- file.path(de_plots_dir_path, 'all_marker_matches.csv')
  all_matches <- data.table::rbindlist(de_clusters_list)
  data.table::setorder(all_matches, clust)
  data.table::fwrite(all_matches, file = all_matches_path)
  
  message('Finished ', sample_name)
}


de_analysis <- function(paths_list, dataset_config, selected_config, complete_markers,
                        results_dir_path, dataset_dir_path) {
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
  #'
  #' @return None. This function is evaluated entirely for its side effects (disk I/O).
  
  #'   in the parent/global environment, as they are not explicitly passed as arguments.
  sample_dir_paths <- paths_list$sample_dir_paths
  
  # Iterate over all samples and route them to the single analysis workflow
  for (i in seq_along(sample_dir_paths)) {
    single_de_analysis(
      sample_idx = i,
      paths_list = paths_list,
      dataset_config = dataset_config,
      selected_config = selected_config,
      complete_markers = complete_markers,
      results_dir_path = results_dir_path,
      dataset_dir_path = dataset_dir_path
    )
  }
}


cell_type_annotation_setup <- function(i, paths_list, results_dir_path, config, dataset_dir_path,
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
  #' @param config List. The general configuration object containing global application settings 
  #'   and generic parameter defaults (typically loaded from `general_config.yaml`).
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
  cells_filt_file_name <- paste0('cells_filt_clust_res_', config$selected$resolutions[[sample_name]], 
                                 '_', sample_name, '.qs2')
  expmat_filt_file_name <- paste0('expmat_filt_', sample_name, '.qs2')
  if (cache_check_exists(expmat_filt_file_name, dataset_dir_path) 
      & cache_check_exists(cells_filt_file_name, dataset_dir_path)) {
    message('Loading cached files.')
    cells_filt <- cache_load_data(cells_filt_file_name, dataset_dir_path)
    expmat_filt <- cache_load_data(expmat_filt_file_name, dataset_dir_path)
  } else {
    message('No cached files.')
    
    results_list <- load_filter_cells_expmat(cell_file_paths[i], expmat_file_paths[i], 
                                             genes_file_paths[i], config)
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
  cache_save_data(cna_mat, cna_mat_file_name, dataset_dir_path)
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


hclust_cluster_heatmap <- function(hdata, sample_name, ref_cells, chr_n, chr_lab, cells_filt,
                                   cna_plots_dir_path, dataset_dir_path) {
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
  
  hdata_cast <- data.table::dcast(hdata[, .(gene, cell_name, cna)], 
                                  gene ~ cell_name)[, magrittr::set_rownames(as.matrix(.SD), gene), 
                                                    .SDcols = -'gene']
  
  clust_hclust <- hierarchical_clustering_cna(hdata_cast, method = 'ward.D2')
  
  # Extract levels safely outside of data.table to prevent NSE scoping crashes
  ordered_cells <- clust_hclust$labels[clust_hclust$order]
  hdata[, cell_num_hclust := as.numeric(factor(cell_name, levels = ordered_cells))]
  
  hclust_file_name <- paste0('hclust_', sample_name, '.qs2')
  cache_save_data(clust_hclust, hclust_file_name, dataset_dir_path)
  
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
  
  # Add cell types bypassing data.table NSE using explicit Base R syntax:
  expdt$cell_type <- cells_filt$cell_type[match(expdt$cell_name, cells_filt$cell_name)]
  expdt <- expdt[!is.na(expdt$cell_type)]
  
  # Exclude chromosomes with too few genes:
  chr_n <- expdt[, .(n = length(unique(gene))), keyby = chr][n > 20]
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
  
  message('Run ward clustering')
  hclust_cluster_heatmap(hdata, sample_name, ref_cells, chr_n, chr_lab, cells_filt,
                         cna_plots_dir_path, dataset_dir_path)
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
  
  expdt <- data.table::melt(cna_mat, id.vars = c('gene', 'chr', 'start_pos'), variable.name = 'cell_name', 
                            value.name = 'cna', variable.factor = FALSE)
  hclust_file_name <- paste0('hclust_', sample_name, '.qs2')
  clust_hclust <- cache_load_data(hclust_file_name, dataset_dir_path)
  
  # Get the cluster definition for this specific subclone from the config
  clust_id <- selected_config$cna_ward_ref_cluster[[sample_name]][[subclone_i]]
  
  # Extract cells using the dynamic cutree method saved from the UI
  k_val <- clust_id$k
  clust_num <- clust_id$cluster
  cell_names <- names(which(stats::cutree(clust_hclust, k = k_val) == clust_num))
  
  # Genes with highest CNA values in candidate malignant cells:
  hotspot_genes <- expdt[cell_name %in% cell_names, .(m2 = mean(cna^2)), by = gene]
  hotspot_genes <- hotspot_genes[, .SD[m2 > stats::quantile(m2, 0.9), gene]]
  
  # Mean CNA profile of candidate malignant cells:
  cna_mat <- cna_mat[, magrittr::set_rownames(as.matrix(.SD), gene), 
                     .SDcols = -c('gene', 'chr', 'start_pos')]
  mal_mean <- rowMeans(cna_mat[, cell_names])
  
  # CNA signal and correlation:
  dt <- expdt[gene %in% hotspot_genes, .(cna_signal = mean(cna^2)), by = cell_name]
  dt[, cna_cor := stats::cor(cna_mat, mal_mean)[cell_name, 1]]
  
  # Assign cells as candidate malignant, reference or NA. The NA cells could include candidate malignant cells that were excluded in the above downsampling step.
  dt[, ct := ifelse(cell_name %in% cell_names, 'Candidate malignant', 
                    ifelse(cell_name %in% ref_cells[sample == sample_name, cell_name], 'Reference', 
                           as.character(NA)))]
  dt[, c('sample', 'subclone') := .(sample_name, subclone_i)]
  data.table::setcolorder(dt, c('sample', 'subclone'))
  
  signal_cor_dt_name <- paste0('cna_sig_cor_', sample_name, '_subclone_', subclone_i, '.qs2')
  cache_save_data(dt, signal_cor_dt_name, dataset_dir_path)
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
    if (cache_check_exists(sig_cor_file, dataset_dir_path)) {
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
  #' @return A named list containing five elements:
  #' \itemize{
  #'   \item \code{cells_filt}: Preview cell annotations.
  #'   \item \code{summary_heatmap}: Faceted CNA summary heatmap.
  #'   \item \code{pre_scatter_plots}: Signal/correlation plots using original annotations.
  #'   \item \code{post_scatter_plots}: Signal/correlation plots using preview CNA assignments.
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
  
  # Generate UMAP Plot with new cell_type assignments
  umap_title <- paste0('Cell types of sample: ', sample_name, ' (CNA assigned)')
  umap_plot <- plot_clusters(cells_filt_new, umap_title, x_col = umap1, y_col = umap2, cluster_col = cell_type)
  
  # 2. Load basic data and pass to the heatmap plot function
  expdt <- load_expdt_from_cna_matrix(sample_name, dataset_dir_path)
  ref_cells <- cells_filt_new[cell_type %in% selected_config$cna_ref_cells[[sample_name]]]
  summary_plot <- summary_cna_heatmap(expdt, cells_filt_new, ref_cells)
  
  # 3. Prepare Subclone Scatter Plots (Pre and Post assignment)
  thresh_list <- selected_config$cna_thresholds[[sample_name]]
  pre_scatter_plots <- list()
  post_scatter_plots <- list()
  
  for (i in seq_along(thresh_list)) {
    sig_cor_file <- paste0('cna_sig_cor_', sample_name, '_subclone_', i, '.qs2')
    if (cache_check_exists(sig_cor_file, dataset_dir_path)) {
      cna_sig_cor <- cache_load_data(sig_cor_file, dataset_dir_path)
      
      # Format threshold for plotting function
      malig_thresh <- list()
      malig_thresh[[sample_name]] <- list(thresh_list[[i]])
      
      # --- PRE-ASSIGNMENT SCATTER PLOT ---
      cna_sig_cor_pre <- data.table::copy(cna_sig_cor)
      cna_sig_cor_pre[cells_filt_orig, on = 'cell_name', ct := i.cell_type]
      
      p_pre <- cna_sig_cor_plot(cna_sig_cor_pre, sample_name, malig_thresh)
      p_pre <- p_pre + ggplot2::labs(subtitle = paste("Subclone", i, "(Original Annotations)"))
      pre_scatter_plots[[i]] <- p_pre
      
      # --- POST-ASSIGNMENT SCATTER PLOT ---
      cna_sig_cor_post <- data.table::copy(cna_sig_cor)
      cna_sig_cor_post[cells_filt_new, on = 'cell_name', ct := i.cell_type]
      
      p_post <- cna_sig_cor_plot(cna_sig_cor_post, sample_name, malig_thresh)
      p_post <- p_post + ggplot2::labs(subtitle = paste("Subclone", i, "(Final Assignment)"))
      post_scatter_plots[[i]] <- p_post
    }
  }
  
  return(list(
    cells_filt = cells_filt_new,
    summary_heatmap = summary_plot,
    pre_scatter_plots = pre_scatter_plots,
    post_scatter_plots = post_scatter_plots,
    umap_plot = umap_plot
  ))
}

batch_compute_cna_and_heatmaps <- function(paths_list, dataset_dir_path, results_dir_path, 
                                           selected_config, gene_positions) {
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
  
  sample_dirs <- paths_list$sample_dir_paths
  
  for (i in seq_along(sample_dirs)) {
    s_name <- basename(sample_dirs[i])
    
    ref_cfg <- selected_config$cna_ref_cells[[s_name]]
    mal_cfg <- selected_config$cna_pot_mal_cells[[s_name]]
    
    # 1. Check if required configurations are present
    if (is.null(ref_cfg) || length(ref_cfg) == 0 || is.null(mal_cfg) || length(mal_cfg) == 0) {
      skipped_samples <- c(skipped_samples, s_name)
      next
    }
    
    message("Batch processing CNA & Heatmaps for sample: ", s_name)
    
    # 2. Check if clustering cache exists
    cells_file <- paste0('cells_filt_clust_res_', selected_config$resolutions[[s_name]], '_', s_name, '.qs2')
    expmat_file <- paste0('expmat_filt_', s_name, '.qs2')
    
    if (!cache_check_exists(cells_file, dataset_dir_path) || !cache_check_exists(expmat_file, dataset_dir_path)) {
      message("Skipping ", s_name, ": missing cached filtering/clustering files.")
      skipped_samples <- c(skipped_samples, paste0(s_name, " (Missing Cache)"))
      next
    }
    
    cells_filt <- cache_load_data(cells_file, dataset_dir_path)
    expmat_filt <- cache_load_data(expmat_file, dataset_dir_path)
    
    cells_filt[is.na(cell_type), cell_type := 'Unassigned']
    ref_cells <- cells_filt[cell_type %in% ref_cfg]
    
    # 3. Compute CNA if missing
    cna_mat_file_name <- paste0('cna_matrix_', s_name, '.qs2')
    if (!cache_check_exists(cna_mat_file_name, dataset_dir_path)) {
      compute_cna_and_cache(expmat_filt, gene_positions, ref_cells, s_name, dataset_dir_path)
    }
    
    # 4. Generate Heatmaps
    cna_plots_dir_path <- file.path(results_dir_path, s_name, '3_cna_plots')
    dir.create(cna_plots_dir_path, showWarnings = FALSE, recursive = TRUE)
    
    cna_clustering_and_heatmaps(ref_cells, s_name, selected_config, cna_plots_dir_path, dataset_dir_path)
    
    processed_samples <- c(processed_samples, s_name)
  }
  
  return(list(processed = processed_samples, skipped = skipped_samples))
}