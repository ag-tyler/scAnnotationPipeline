# ==================================================================================================
# Script: utils_annotation.R
# Purpose: Collection of functions for cell annotation.
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# 1. Environment & Packages
# --------------------------------------------------------------------------------------------------

library(docstring)


# --------------------------------------------------------------------------------------------------
# 2. Filtering & processing
# --------------------------------------------------------------------------------------------------

filter_cell_gene_count <- function(cells, expmat, min_genes = 500) {
  #' Remove cells that have less than the given minimum number of genes expressed
  #' 
  #' @param cells Cells data table
  #' @param expmat Sparse expression matrix with the cells as col names
  #' @param min_genes Minimum number of genes (default: 500)
  #' 
  #' @return Cells data table with only the cells that passed the filter
  
  cells_filt <- cells[matkot::col_nnz(expmat) >= min_genes]
  return(cells_filt)
}

log_normalize_expmat <- function(expmat, cell_names, target_sum = 1e+05, round_digits = 4) {
  #' Log transforms a sparse matrix using target_sum as factor. 
  #' 
  #' Only returns the columns that are in cell_names. uses log 2.
  #' 
  #' @param expmat Sparse expression matrix
  #' @param cell_names Character vector of cell names
  #' @param target_sum The number that each matrix col will sum up to (default: 1e+05)
  #' @param round_digits Rounds all non zero values to up to this digit (default: 4)
  #' 
  #' @return The sparse matrix transformed
  
  # Divide each value by their column total
  expmat <- matkot::to_frac(expmat[, cell_names])
  # Multiply by target_sum for normalization
  expmat <- expmat * target_sum
  # Log transform (default base 2)
  expmat <- matkot::log_transform(expmat)
  # round
  expmat <- round(expmat, round_digits)
  return(expmat)
}

gene_expr_filter <- function(expmat, target_sum = 1e+05, log2_threshold = 4) {
  #' Gives a vector of gene names that are expressed above the threshold
  #' 
  #' Checks if genes are expressed above the threshold in a log normalized expression matrix.
  #' The sparse matrix needs to have been log transformed with basis 2.
  #' 
  #' @param expmat Sparse expression matrix that is log normalized
  #' @param target_sum The value the matrix was normalized to(default: 1e+05)
  #' @param log2_threshold Threshold value in log2 format (default: 4)
  #' 
  #' @return Character vector of gene names that passed the filter
  
  expmat_antilog <- matkot::log_transform(expmat, reverse = TRUE)
  expmat_rowmeans <- Matrix::rowMeans(expmat_antilog)
  threshold_transformed <- target_sum * (2^log2_threshold - 1) / 1e+06
  genes_filt <- rownames(expmat[expmat_rowmeans >= threshold_transformed, ])
  return(genes_filt)
}



# --------------------------------------------------------------------------------------------------
# 3. Clustering
# --------------------------------------------------------------------------------------------------

run_expmat_pca <- function(expmat, nv = 50, seed = 3988) {
  #' Do pca (irlba) over the expression matrix
  #' 
  #' @param expmat Sparse expression matrix
  #' @param nv number of right singular vectors to estimate (default: 50)
  #' 
  #' @return The computed pca
  
  set.seed(seed)
  # subtract the row mean over all values
  expmat_minus_row_mean <- t(apply(expmat, 1, function(x) x - mean(x)))
  exp_pca <- irlba::irlba(expmat_minus_row_mean, nv = nv)
  return(exp_pca)
}

run_expmat_umap <- function(exp_pca, n_exp_col, spread = 5, min_dist = 0.1, seed = 3988) {
  #' Do umap on the computed pca
  #' 
  #' @param exp_pca Comuputed partial pca using irlba
  #' @param n_exp_col Number of columns of the expression matrix, the pca is based on
  #' @param spread umap spread parameter (default: 5)
  #' @param min_dist umap min_dist parameter (default: 0.1)
  #' @param seed Seed for reproducibility (default: 3988)
  #' 
  #' @return The computed umap
  
  set.seed(seed)
  n_neighbors <- max(min(100, floor(n_exp_col/100)), 15)
  exp_umap <- uwot::umap(exp_pca$v, n_neighbors = n_neighbors, spread = spread, min_dist = min_dist,
                         seed = seed)
  return(exp_umap)
}

louvain_clustering <- function(exp_pca, exp_umap, cells, resolution = 1.0, seed = 3988) {
  #' Does louvain clustering using the computed pca and updates cells with the computed umap and
  #' the computed clusters. Cells needs to have exactly the same cells as the expression matrix
  #' that was used for the pca and umap.
  #' 
  #' @param exp_pca pca of expression matrix
  #' @param exp_umap umap of expression matrix
  #' @param cells cells data table with information about each cell in sample
  #' @param resolution resolution parameter of Seurat::FindClusters (default: 1.0)
  #' 
  #' @return The updated cells data table
  
  set.seed(seed)
  neighbours <- Seurat::FindNeighbors(magrittr::set_rownames(exp_pca$v, cells$cell_name))
  clust_snn <- Seurat::FindClusters(neighbours$snn, resolution = resolution, random.seed = seed)
  cells[, c('umap1', 'umap2', 'clust') := cbind(data.table::as.data.table(exp_umap), clust_snn)]
  return(cells)
}

# --------------------------------------------------------------------------------------------------
# 3.1 Clustering plotting
# --------------------------------------------------------------------------------------------------

plot_clusters <- function(cells, title, x_col = umap1, y_col = umap2, cluster_col = clust) {
  #' Plot UMAP embedding coloured by clusters
  #' 
  #' @param cells Cells data table
  #' @param title Title of the plot
  #' @param x_col Unquoted column name for the x-axis (default: umap1)
  #' @param y_col Unquoted column name for the y-axis (default: umap2)
  #' @param cluster_col Unquoted column name for the clusters (default: clust)
  #' 
  #' @return A ggplot2 object
  
  # substitute is necessary to transition from the unquoted name to string
  n_clusters <- length(unique(cells[, eval(substitute(cluster_col))]))
  p <- ggplot2::ggplot(cells) +
    ggplot2::geom_point(ggplot2::aes(
      x = {{ x_col }},
      y = {{ y_col }},
      colour = {{ cluster_col }}
    )) +
    ggplot2::scale_colour_manual(values = randomcoloR::distinctColorPalette(n_clusters)) +
    cowplot::theme_half_open() +
    ggplot2::guides(colour = ggplot2::guide_legend(override.aes = list(size = 3.5))) +
    ggplot2::labs(title = title) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5),
      plot.background = ggplot2::element_rect(fill = 'white', color = NA)
    )
  return(p)
}


# --------------------------------------------------------------------------------------------------
# 4. Differential expression (de) analysis
# --------------------------------------------------------------------------------------------------

mean_diff_exp <- function(expmat, cells, de_parameters) {
  #' Get top differentially expressed genes per col_name
  #' 
  #' Computes the mean differential expression for each gene in the expression matrix. This is done
  #' for every unique category in the col_name column. A data table with the results is returned.
  #' 
  #' @param expmat Expression matrix
  #' @param cells Data table with cell information
  #' @param de_parameters List with set parameters for the diff. expr. analysis
  #' 
  #' @return Data table of top differentially expressed genes 
  
  col_name <- de_parameters$col_name
  num_genes <- de_parameters$num_genes
  gene_means <- Matrix::rowMeans(expmat)
  expmat_cent <- expmat - gene_means
  
  de <- cells[, {
    ranked <- utils::head(
      sort(Matrix::rowMeans(expmat_cent[, cell_name]), decreasing = TRUE),
      num_genes
    )
    list(gene = names(ranked), m = ranked)
  }, by = col_name]
  return(de)
}

match_marker_genes <- function(de, marker_gene_sets, de_parameters) {
  #' Match marker genes to the top differentially expressed genes.
  #' 
  #' @param de Differential expression analysis
  #' @param marker_gene_sets Data table with marker genes for cell types
  #' @param de_parameters List with set parameters for the diff. expr. analysis
  #' 
  #' @return List of data tables with de genes and their matched marker genes for each gene set.
  
  col_name <- de_parameters$col_name
  unique_names <- unique(de[, get(col_name)])
  de_clusters_list <- list()
  for (i in seq_along(unique_names)) {
    curr_name <- as.character(unique_names[i])
    curr_cluster <- de[get(col_name) == curr_name,]
    
    # Go through all marker gene sets to find matching genes
    marker_cell_types <- unique(marker_gene_sets$cell_type)
    for (k in seq_along(marker_cell_types)) {
      curr_cell_type <- as.character(marker_cell_types[k])
      # Get marker genes of current cell type, but only at most the top n_marker_genes
      curr_genes <- marker_gene_sets[cell_type == curr_cell_type, symbol]
      # Create search pattern with OR statements to search for marker gene occurrences
      exact_genes <- paste0("\\b", curr_genes, "\\b")
      search_pattern <- paste(exact_genes, collapse = '|')
      curr_cluster[, (curr_cell_type) := stringr::str_extract(gene, 
                                                              stringr::regex(search_pattern, 
                                                                             ignore_case = TRUE))]
    }
    de_clusters_list[[curr_name]] <- curr_cluster
  }
  return(de_clusters_list)
}

count_matched_marker_genes <- function(de_clusters_list, marker_gene_sets, de_parameters) {
  #' Count for each marker gene set cell type the number of matched genes
  #' 
  #' @param de_clusters_list List of data tables with matched marker genes for each cluster
  #' @param marker_gene_sets Data table with marker genes for cell types
  #' @param de_parameters List with set parameters for the diff. expr. analysis
  #' 
  #' @return Data table where the counts of matches for each cluster is listed 
  
  marker_col_name <- de_parameters$marker_cell_type_col_name
  n_top_genes <- de_parameters$max_match_genes
  unique_marker_names <- unique(marker_gene_sets[[marker_col_name]])
  counts_list <- lapply(de_clusters_list, function(de_cluster) {
    # For each column count found genes
    counts <- lapply(unique_marker_names, function(marker_name) {
      if (marker_name %in% colnames(de_cluster)) {
        sum(!is.na(de_cluster[[marker_name]][1:n_top_genes]))
      } else {
        0L
      }
    })
    # Name the list elements
    setNames(counts, unique_marker_names)
  })
  # combine into data table
  cell_type_counts <- data.table::rbindlist(counts_list, idcol = 'clusters')
  # Transfer names
  cell_type_counts$clusters <- names(de_clusters_list)
  return(cell_type_counts)
}


marker_genes_in_expmat_genes <- function(expmat, marker_gene_sets, n_marker_genes = 50) {
  #' Get the genes for each marker gene set that are in the sample gene set (rows of expmat).
  #' 
  #' @param expmat Expression matrix with genes as rows
  #' @param marker_gene_sets Marker genes for different cell types in data table
  #' @param n_marker_genes Max number of marker genes used from each cell type
  #' 
  #' @return A list with character vectors of genes for each cell type
  
  marker_cell_types <- unique(marker_gene_sets$cell_type)
  marker_genes_for_scores <- lapply(marker_cell_types, function(marker_cell_type){
    m_genes <- marker_gene_sets[cell_type == marker_cell_type, symbol]
    
    if (!grepl('artifact', marker_cell_type, ignore.case = TRUE)) {
      m_genes <- m_genes[seq_len(min(n_marker_genes, length(m_genes)))]
    }
    
    m_genes[m_genes %in% rownames(expmat)]
  })
  names(marker_genes_for_scores) <- marker_cell_types
  return(marker_genes_for_scores)
}

check_min_n_marker_genes <- function(marker_genes_for_scores, min_n_genes = 20) {
  #' Checks if there are cell types for which the number of marker genes available for scoring are
  #' too few. 
  #' 
  #' @param marker_genes_for_scores List of gene vectors for each cell type
  #' @param min_n_genes Number of genes that a gene vector needs to have to not be flagged 
  #' (default: 20)
  #' 
  #' @return Data table with cell type, count of genes, and n_genes_pass flag
  
  # Collect data for columns
  # cell_type
  cell_types_ <- names(marker_genes_for_scores)
  # gene_count
  gene_count_ <- unlist(lapply(marker_genes_for_scores, length))
  # n_gene_pass
  n_gene_pass_ <- gene_count_ >= min_n_genes
  
  # combine into data table
  n_marker_genes <- data.table::data.table(cell_types = cell_types_, gene_count = gene_count_, 
                               n_gene_pass = n_gene_pass_)
  return(n_marker_genes)
}

score_and_fill_cells <- function(expmat, marker_genes_for_scores, cells) {
  #' Compute signature score for each marker gene set and fill cells data table with scores.
  #' 
  #' Uses matkot::sig_score to compute the signature scores for a matrix, and for each marker gene 
  #' set. The matrix should be a sparse expression matrix that was log-normalized and ideally 
  #' low expression genes were filtered out, to reduce outlier effects.
  #' 
  #' @param expmat Sparse expression matrix (log-normalized)
  #' @param marker_genes_for_scores List of gene vectors for each cell type
  #' @param cells Cells data table
  #' 
  #' @return Cells data table with new columns for each cell type containing sig scores.
  
  
  score_vectors <- lapply(marker_genes_for_scores, function(m_genes) {
    matkot::sig_score(expmat, m_genes)
  })
  
  for (cell_type_ in names(score_vectors)) {
    cells[, (cell_type_) := score_vectors[[cell_type_]][cell_name]]
  }
  return(cells)
}



# --------------------------------------------------------------------------------------------------
# 4.1 Differential expression (de) analysis plots
# --------------------------------------------------------------------------------------------------

stacked_gene_match_count_plot <- function(marker_genes_count, de_parameters, res, seed = 3988) {
  #' Plot the number of matched marker genes in top diff. expressed gene list of each cluster.
  #' 
  #' @param marker_genes_count Data table with the counts of matched marker genes per marker gene 
  #' set and per cluster
  #' @param de_parameters List with set parameters for the diff. expr. analysis
  #' @param res The resolution used for clustering
  #' @param seed Seed to set random colors
  #' 
  #' @return The stacked bar plot with the matched marker genes counts per cluster
  
  n_top_genes <- de_parameters$max_match_genes
  cluster_name <- de_parameters$cluster_type_name
  # Reshape from wide to long
  long_cell_type_counts <- data.table::melt(marker_genes_count,
                                id.vars = 'clusters',
                                variable.name = 'cell_type',
                                value.name = 'count')
  
  plot_title <- paste0('Marker genes found per ', cluster_name, '; Top ', n_top_genes, 
                       ' genes; Res: ', res)
  
  n_cell_types <- length(unique(long_cell_type_counts$cell_type))
  set.seed(seed)
  plot_colors <- randomcoloR::distinctColorPalette(n_cell_types)
  
  gene_count_plot <- ggplot2::ggplot(long_cell_type_counts, ggplot2::aes(x = clusters, y = count, fill= cell_type)) +
    ggplot2::geom_bar(stat = 'identity', position = 'stack', color = 'black', linewidth = 0.5) +
    cowplot::theme_half_open() +
    ggplot2::labs(
      title = plot_title,
      x = 'Clusters',
      y = 'Number of marker genes',
      fill = 'Marker gene cell types'
    ) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
                   plot.background = ggplot2::element_rect(fill = 'white', color = NA)) +
    ggplot2::scale_fill_manual(values = plot_colors)
}

sig_scores_cluster_boxplot <- function(cells, marker_cell_types, marker_genes_found, cluster_name, 
                                       sample_name, resolution, seed = 3988) {
  #' Plot the signature scores for each cell type for a cluster
  #' 
  #' @param cells Cells data table with scores for each cell type stored in cols
  #' @param marker_cell_types Cell types of the marker gene sets
  #' @param marker_genes_found Data table with the number of marker genes found in sample and if 
  #' this passed the minimum required for reliable scores
  #' @param cluster_name Name of the current cluster
  #' @param sample_name This samples name
  #' @param resolution Used louvain cluster resolution
  #' @param seed Seed to set random colors
  #' 
  #' @return ggplot2 object of the scores boxplot
  
  cells_cluster <- cells[clust == cluster_name, ]
  plot_dt <- data.table::melt(
    cells_cluster,
    measure.vars = marker_cell_types,
    variable.name = 'predicted_cell_type', 
    value.name = 'score'
  )
  # Join the gene count info
  plot_dt <- merge(
    plot_dt, 
    marker_genes_found, 
    by.x = "predicted_cell_type", 
    by.y = "cell_types", 
    all.x = TRUE
  )
  
  # Force the column back to a factor using the original explicit order
  plot_dt[, predicted_cell_type := factor(predicted_cell_type, levels = marker_cell_types)]
  
  # Create a summary table for the annotations and background shading
  # This prevents ggplot from drawing thousands of overlapping text/rectangles
  anno_dt <- plot_dt[, .(
    max_score = max(score, na.rm = TRUE),
    gene_count = data.table::first(gene_count),
    n_gene_pass = data.table::first(n_gene_pass)
  ), by = predicted_cell_type]
  
  # Convert the discrete x-axis categories to numeric positions for geom_rect()
  anno_dt[, x_num := as.numeric(predicted_cell_type)]
  
  n_cell_types <- length(marker_cell_types)
  n_clust_cells <- nrow(cells[clust == cluster_name])
  
  set.seed(seed)
  plot_colors <- randomcoloR::distinctColorPalette(n_cell_types)
  
  score_plot <- ggplot2::ggplot(plot_dt, 
                                ggplot2::aes(x = predicted_cell_type, y = score)) +
    # Background shading for failed gene counts
    ggplot2::geom_rect(
      data = anno_dt[n_gene_pass == FALSE],
      ggplot2::aes(
        xmin = x_num - 0.5, 
        xmax = x_num + 0.5, 
        ymin = -Inf, 
        ymax = Inf
      ),
      fill = "pink",       # Color indicating warning/failed pass
      alpha = 0.4, 
      inherit.aes = FALSE  # Prevents scale collision
    ) +
    
    ggplot2::geom_boxplot(ggplot2::aes(fill = predicted_cell_type), outlier.size = 0.5, alpha = 0.8) +
    
    # Text labels showing the gene count on top of the columns
    ggplot2::geom_text(
      data = anno_dt,
      ggplot2::aes(x = predicted_cell_type, y = Inf, label = gene_count),
      vjust = 1.5,        
      size = 3.5,
      fontface = "bold",
      inherit.aes = FALSE
    ) +
    
    # Expand the top of the y-axis by 15% so the text isn't cut off
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.05, 0.15))) +
    
    cowplot::theme_half_open() +
    
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, vjust = 1),
      plot.background = ggplot2::element_rect(fill = "white", color = NA),
      legend.position = 'none',
      panel.grid.major.y = ggplot2::element_line(color = "grey85", linetype = "dashed")
    ) +
    
    ggplot2::labs(
      title = paste0(sample_name, ': Cluster ', cluster_name, ' scores; Res: ', resolution, 
                     '; Cells: ', n_clust_cells),
      x = 'Marker Set',
      y = 'Score'
    ) +
    ggplot2::scale_fill_manual(values = plot_colors)
  
  return(score_plot)
}

# --------------------------------------------------------------------------------------------------
# 5. copy Number Alteration (cna) analysis
# --------------------------------------------------------------------------------------------------

compute_cna <- function(expmat, gene_positions, ref_cells) {
  #' Compute Copy Number Alterations (CNA) from Gene Expression Data
  #'
  #' @description
  #' Calculates and corrects Copy Number Alteration (CNA) values from a single-cell
  #' gene expression matrix using baseline references. The function centers the expression 
  #' matrix, restricts extreme values, applies a running mean across chromosomal positions, 
  #' and performs a baseline correction using the minimum and maximum mean CNA values 
  #' derived from the provided reference cells.
  #' 
  #' @param expmat A numeric or sparse expression matrix where rows are genes and columns are cells.
  #' @param gene_positions A data table containing genomic coordinates for genes. Must include 
  #'   the columns `symbol`, `chromosome_name`, and `start_position`.
  #' @param ref_cells A data table of reference cell annotations used to establish the non-malignant 
  #'   baseline. Must contain `cell_name` and `cell_type` columns.
  #'
  #' @return A long-format data table (`expdt`) containing the corrected CNA values (`cna`) 
  #'   for each `cell_name` and `gene`, ordered by chromosome (`chr`) and starting position (`start_pos`).
  
  # Center expression matrix
  r <- Matrix::rowMeans(expmat)
  expmat_cent <- expmat - r
  
  # Compute CNA values:
  rms <- r[names(r) %in% gene_positions$symbol]
  genes_top <- utils::head(names(rms)[order(-rms)], 5000)
  
  # Prevent matrix drop collapsing
  expmat_cna <- expmat_cent[genes_top, , drop = FALSE]
  
  # Restrict range to limit influence of extreme values
  expmat_cna[expmat_cna > 3] <- 3; expmat_cna[expmat_cna < -3] <- -3 
  
  # Safely convert to data.table without keep.rownames bug
  expdt <- data.table::as.data.table(as.matrix(expmat_cna))
  expdt[, gene := genes_top]
  
  expdt <- data.table::melt(expdt, id.vars = 'gene', variable.name = 'cell_name', 
                            value.name = 'value', variable.factor = FALSE)
  
  # Safely extract coordinates explicitly using the symbol column
  expdt[, c('chr', 'start_pos') := gene_positions[expdt$gene, .(chromosome_name, start_position), on = "symbol"]]
  
  expdt <- expdt[order(chr, start_pos)]
  
  # Computing the CNA values
  # Dynamically adjust 'k' so it never exceeds the number of genes (.N) on the chromosome
  expdt[, cna := log2(caTools::runmean(2^value, k = min(100, .N))), by = .(chr, cell_name)]
  expdt[, cna := cna - median(cna, na.rm = TRUE), keyby = cell_name] 
  
  # MATHEMATICALLY IDENTICAL REPLACEMENT FOR 1ST DO.CALL:
  expdt_ref <- expdt[ref_cells, on = "cell_name", nomatch = NULL]
  ref_range <- expdt_ref[, .(mean_cna = mean(cna, na.rm = TRUE)), by = .(cell_type, gene)]
  ref_range <- ref_range[, .(mn = min(mean_cna), mx = max(mean_cna)), keyby = gene]
  
  # MATHEMATICALLY IDENTICAL REPLACEMENT FOR 2ND DO.CALL:
  expdt[ref_range, on = "gene", c("mn", "mx") := .(i.mn, i.mx)]
  expdt[, cna := ifelse(cna > mx + 0.1, cna - mx - 0.1, 
                        ifelse(cna < mn - 0.1, cna - mn + 0.1, 0))]
  expdt[, c("mn", "mx") := NULL]
  
  return(expdt)
}


hierarchical_clustering_cna <- function(hdata_cast, method = 'ward.D2') {
  #' Perform hierarchical clustering on Copy Number Alteration (CNA) profiles
  #'
  #' This function calculates a distance matrix based on (1 - Pearson correlation)
  #' between the columns (cells) of the provided CNA matrix and performs
  #' hierarchical clustering to group cells with similar alteration profiles.
  #'
  #' @param hdata_cast A numeric matrix of CNA values where rows are genes
  #'   and columns are cell names.
  #' @param method A character string specifying the agglomeration method
  #'   to be used by \code{stats::hclust} (e.g., 'ward.D2', 'complete', 'average'). 
  #'   Defaults to 'ward.D2'.
  #'
  #' @return An object of class \code{hclust} describing the clustering tree.
  
  # Calculate distance based on 1 - Pearson correlation, then cluster
  clust_hclust <- stats::hclust(stats::as.dist(1 - stats::cor(hdata_cast)), method = method)
  return(clust_hclust)
}

hdbscan_clustering_cna <- function(hdata_cast, dataset_config, n_pcs = 10, umap_neighbors = NULL, 
                                   hdbscan_minPts = 15) {
  
  if (is.null(umap_neighbors)) {
    umap_neighbors <- max(min(100, floor(ncol(hdata_cast)/100)), 15)
  }
  
  set.seed(dataset_config$params$seed)
  hdata_pca <- irlba::irlba(hdata_cast, nv = n_pcs)
  hdata_umap <- uwot::umap(hdata_pca$v, n_neighbors = umap_neighbors, 
                           spread = 5, min_dist = 0.1)
  clust_hdbscan <- dbscan::hdbscan(hdata_umap, minPts = hdbscan_minPts)
  clust_hdbscan$hc$labels <- colnames(hdata_cast)
  
  return(list(clust_hdbscan, hdata_umap))
}

umap_cna <- function(hdata_cast, dataset_config, n_pcs = 10, umap_neighbors = NULL) {
  #' Compute UMAP Embeddings from Copy Number Alteration (CNA) Profiles
  #'
  #' @description
  #' Performs dimensionality reduction on a CNA matrix to generate UMAP embeddings 
  #' for the cells. It first computes the top principal components using truncated 
  #' SVD (\code{irlba}), and then projects the resulting right singular vectors 
  #' (cell embeddings) into a 2D space using UMAP (\code{uwot}).
  #'
  #' @param hdata_cast A numeric matrix of CNA values where rows are genes
  #'   and columns are cells.
  #' @param dataset_config List. The dataset-specific configuration object containing parameters 
  #'   tailored to the currently loaded dataset (e.g., PCA dimensions, UMAP settings, and DE 
  #'   thresholds).
  #' @param n_pcs Numeric. The number of principal components to compute for the 
  #'   initial dimensionality reduction step. Defaults to 10.
  #' @param umap_neighbors Numeric or \code{NULL}. The size of the local neighborhood 
  #'   (number of nearest neighbors) used for UMAP. If \code{NULL}, it is dynamically 
  #'   calculated based on the number of cells (\code{ncol(hdata_cast)} / 100), 
  #'   bounded between a minimum of 15 and a maximum of 100.
  #'
  #' @return A numeric matrix of UMAP coordinates for the cells.
  
  if (is.null(umap_neighbors)) {
    umap_neighbors <- max(min(100, floor(ncol(hdata_cast)/100)), 15)
  }
  
  set.seed(dataset_config$params$seed)
  hdata_pca <- irlba::irlba(hdata_cast, nv = n_pcs)
  hdata_umap <- uwot::umap(hdata_pca$v, n_neighbors = umap_neighbors, 
                           spread = 5, min_dist = 0.1)
  return(hdata_umap)
}



# --------------------------------------------------------------------------------------------------
# 5.1 copy Number Alteration (cna) analysis plots
# --------------------------------------------------------------------------------------------------


dendrogram_plot <- function(hdata_clust) {
  #' Plot a Horizontal Dendrogram from Clustered CNA Data
  #'
  #' @description
  #' Generates a minimalist, horizontal dendrogram from hierarchically clustered 
  #' Copy Number Alteration (CNA) data. The resulting \code{ggplot2} object is 
  #' stripped of axes, ticks, and background, making it optimized for seamless 
  #' alignment alongside heatmaps or other single-cell visualizations.
  #'
  #' @param hdata_clust An object representing hierarchically clustered CNA data 
  #'   (typically of class \code{hclust}).
  #'
  #' @return A \code{ggplot} object containing the unannotated horizontal dendrogram.
  
  dend <- dbscan::as.dendrogram(hdata_clust)
  dend_data <- ggdendro::dendro_data(dend)$segments |> data.table::as.data.table()
  dend_plot <- ggplot2::ggplot(dend_data) +
    ggplot2::geom_segment(ggplot2::aes(x = -y, y = x, xend = -yend, yend = xend)) +
    ggplot2::scale_x_continuous(expand = c(0, 0)) +
    ggplot2::scale_y_continuous(expand = c(0, 0.5)) +
    ggplot2::theme(axis.text = ggplot2::element_blank(), axis.ticks = ggplot2::element_blank(), 
                   axis.ticks.length = ggplot2::unit(0, 'pt'), 
                   axis.title = ggplot2::element_blank(),
                   panel.background = ggplot2::element_rect(fill = NA), 
                   plot.margin = ggplot2::unit(c(5.5, 0, 5.5, 5.5), 'pt'))
  
  return(dend_plot)
}


cna_heatmap <- function(hdata, ref_cells, chr_n, chr_lab, cell_num) {
  #' Plot an Inferred CNA Heatmap
  #'
  #' @description
  #' Generates a comprehensive, heavily customized \code{ggplot2} heatmap of inferred 
  #' Copy Number Alterations (CNA). The plot uses a raster geometry for efficient rendering 
  #' of large single-cell datasets, applies a divergent Red-Blue color scale centered at zero, 
  #' and overlays vertical lines to clearly demarcate chromosome boundaries.
  #'
  #' @param hdata A \code{data.frame} or \code{data.table} in long format containing the 
  #'   CNA data to be plotted. Expected to have at least three columns: \code{gene} (x-axis), 
  #'   \code{cell_num} (y-axis), and \code{cna} (fill value).
  #' @param ref_cells A \code{data.table} of reference cell annotations. Must contain a 
  #'   \code{cell_type} column, which is used to generate the plot's subtitle summarizing 
  #'   the reference baseline.
  #' @param chr_n A \code{data.table} containing the number of genes per chromosome. 
  #'   Expected to have columns \code{chr} (chromosome name) and \code{n} (gene count). 
  #'   Used to calculate the intercepts for the vertical chromosome boundary lines.
  #' @param chr_lab A named character vector used to position and format chromosome labels 
  #'   on the x-axis. The values represent the display names (e.g., "1", "2", "X"), and 
  #'   the names correspond to the specific gene symbols at the midpoint of each chromosome.
  #'
  #' @return A \code{ggplot} object representing the annotated CNA heatmap.
  
  htmp <- ggplot2::ggplot(hdata) +
    ggplot2::geom_raster(ggplot2::aes(x = gene, y = {{ cell_num }}, fill = cna)) +
    ggplot2::geom_vline(ggplot2::aes(xintercept = xi), 
                        data = data.table::data.table(xi = chr_n[1:(.N - 1), 
                                                     cumsum(n) + 0.5]), linewidth = 0.3) +
    ggplot2::scale_fill_gradientn(colours = rev(RColorBrewer::brewer.pal(11, 'RdBu')), 
                                  limits = c(-1, 1), breaks = c(-1, 0, 1), oob = scales::squish) +
    ggplot2::scale_x_discrete(expand = c(0, 0), breaks = names(chr_lab), labels = chr_lab) +
    ggplot2::scale_y_continuous(expand = c(0, 0)) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(size = 12), 
                   axis.text.y.left = ggplot2::element_blank(),
                   axis.text.y.right = ggplot2::element_text(angle = -90, hjust = 0.5, size = 14), 
                   axis.ticks = ggplot2::element_blank(), axis.ticks.length = ggplot2::unit(0, 'pt'),
                   axis.title.x = ggplot2::element_text(size = 14), 
                   axis.title.y.left = ggplot2::element_blank(), 
                   axis.title.y.right = ggplot2::element_text(size = 14),
                   legend.title = ggplot2::element_text(size = 12, margin = ggplot2::margin(b = 6)), 
                   legend.text = ggplot2::element_text(size = 10), legend.justification = c(0.5, 0),
                   panel.border = ggplot2::element_rect(fill = NA, colour = 'black', linewidth = 0.5), 
                   plot.title = ggplot2::element_text(size = 14, face = 'bold'),
                   plot.subtitle = ggplot2::element_text(size = 12), 
                   plot.margin = ggplot2::unit(c(5.5, 5.5, 5.5, 0), 'pt')) +
    ggplot2::guides(fill = ggplot2::guide_colourbar(barwidth = ggplot2::unit(15, 'pt'), 
                                                    barheight = ggplot2::unit(70, 'pt'), 
                                                    ticks.colour = 'black', frame.colour = 'black')) +
    ggplot2::labs(
      x = 'Chromosome', y = 'Cells', fill = 'Inferred CNA\n(log2 ratio)',
      subtitle = paste0('Reference: ', ref_cells[, paste(unique(cell_type), collapse = ', ')])
    )
  
  return(htmp)
}


cluster_or_cell_type_bar_plot <- function(hdata_cells, fill_col_name, legend_title, 
                                          custom_colors = NULL) {
  #' Create a Vertical Annotation Bar Plot for Cells
  #'
  #' @description
  #' Generates a vertical strip plot (using \code{ggplot2::geom_tile}) to visualize 
  #' categorical cell metadata, such as cluster assignments or cell types. This is 
  #' typically used as a side-bar annotation alongside cell-ordered heatmaps. 
  #' If no custom colors are provided, it automatically generates a distinct palette.
  #'
  #' @param hdata_cells A \code{data.frame} or \code{data.table} containing cell metadata. 
  #'   Must include a \code{cell_num} column (defining the y-axis position/order) and 
  #'   the column specified by \code{fill_col_name}.
  #' @param fill_col_name A character string specifying the column in \code{hdata_cells} 
  #'   to use for coloring the tiles (e.g., 'cluster' or 'cell_type').
  #' @param legend_title A character string to be used as the title for the fill legend.
  #' @param custom_colors An optional vector of colors (hex codes or names) mapped to 
  #'   the unique values in the fill column. If \code{NULL} (default), a palette is 
  #'   dynamically generated using \code{randomcoloR::distinctColorPalette()}.
  #'
  #' @return A \code{ggplot} object representing the vertical annotation bar.
  
  unique_vals <- unique(hdata_cells[[fill_col_name]])
  n_colors <- length(unique_vals)
  
  # Fallback to the default if no custom colors are provided
  if (is.null(custom_colors)) {
    custom_colors <- randomcoloR::distinctColorPalette(n_colors)
  }
  
  ggplot2::ggplot(hdata_cells) +
    # Use .data[[ ]] to map the string, and wrap in as.character() for both cases
    ggplot2::geom_tile(ggplot2::aes(x = 0, y = cell_num, fill = as.character(.data[[fill_col_name]]))) +
    ggplot2::scale_x_discrete(expand = c(0, 0)) +
    ggplot2::scale_y_continuous(expand = c(0, 0)) +
    ggplot2::scale_fill_manual(values = custom_colors) +
    ggplot2::theme(
      axis.text = ggplot2::element_blank(), 
      axis.ticks = ggplot2::element_blank(), 
      axis.ticks.length = ggplot2::unit(0, 'pt'), 
      axis.title = ggplot2::element_blank(),
      panel.border = ggplot2::element_rect(fill = NA, colour = 'black', linewidth = 0.5), 
      plot.margin = ggplot2::unit(c(5.5, 0, 5.5, 0), 'pt')
    ) +
    ggplot2::labs(fill = legend_title)
}


combine_cna_plots <- function(method = c("ward", "hdbscan"), 
                              htmp, 
                              cell_type_bar, 
                              clust_bar = NULL, 
                              dendrogram = NULL) {
  #' Combine CNA Heatmap and Annotation Plots
  #'
  #' @description
  #' Assembles a final composite plot consisting of a main Copy Number Alteration 
  #' (CNA) heatmap alongside corresponding vertical annotation bars (cell type, cluster) 
  #' and/or a dendrogram. The layout dynamically adjusts based on the chosen clustering 
  #' \code{method}. The function automatically extracts the legends from the individual 
  #' plots, stacks them vertically on the right, and perfectly aligns the main plot 
  #' panels horizontally.
  #'
  #' @param method A character string specifying the clustering context, which dictates 
  #'   the layout of the grid. Must be either \code{"ward"} or \code{"hdbscan"}.
  #' @param htmp A \code{ggplot} object representing the main CNA heatmap.
  #' @param cell_type_bar A \code{ggplot} object representing the cell type vertical 
  #'   annotation bar (e.g., generated by \code{cluster_or_cell_type_bar_plot}).
  #' @param clust_bar An optional \code{ggplot} object representing the cluster 
  #'   assignment vertical annotation bar. Required if \code{method = "hdbscan"}.
  #' @param dendrogram An optional \code{ggplot} object representing the hierarchical 
  #'   clustering dendrogram. Required if \code{method = "ward"}.
  #'
  #' @return A composite \code{ggplot} (via \code{cowplot::plot_grid}) object containing 
  #'   the aligned and assembled layout.
  
  method <- match.arg(method)
  remove_leg <- ggplot2::theme(legend.position = "none")
  
  if (method == "ward") {
    
    if (is.null(dendrogram)) stop("Ward method requires a dendrogram.")
    
    # NEW: Check if we provided a clust_bar for dynamic k-cluster splitting
    if (!is.null(clust_bar)) {
      legend_list <- list(
        cowplot::get_legend(cell_type_bar),
        cowplot::get_legend(clust_bar),
        cowplot::get_legend(htmp)
      )
      stacked_legends <- cowplot::plot_grid(plotlist = legend_list, ncol = 1, align = "v")
      
      final_plot <- cowplot::plot_grid(
        dendrogram, 
        cell_type_bar + remove_leg, 
        clust_bar + remove_leg,      # Inject the cutree cluster bar here!
        htmp + remove_leg, 
        stacked_legends,
        nrow = 1, align = 'h', axis = 'tb',
        rel_widths = c(0.20, 0.03, 0.03, 1, 0.15) # Squeezed slightly to fit the new bar
      )
      
    } else {
      # Standard Ward Layout (No cluster bar)
      legend_list <- list(
        cowplot::get_legend(cell_type_bar),
        cowplot::get_legend(htmp)
      )
      stacked_legends <- cowplot::plot_grid(plotlist = legend_list, ncol = 1, align = "v")
      
      final_plot <- cowplot::plot_grid(
        dendrogram, 
        cell_type_bar + remove_leg, 
        htmp + remove_leg, 
        stacked_legends,
        nrow = 1, align = 'h', axis = 'tb',
        rel_widths = c(0.25, 0.03, 1, 0.15) 
      )
    }
    
  } else if (method == "hdbscan") {
    
    if (is.null(clust_bar)) stop("HDBSCAN method requires a clust_bar.")
    
    legend_list <- list(
      cowplot::get_legend(cell_type_bar),
      cowplot::get_legend(clust_bar),
      cowplot::get_legend(htmp)
    )
    
    stacked_legends <- cowplot::plot_grid(plotlist = legend_list, ncol = 1, align = "v")
    
    final_plot <- cowplot::plot_grid(
      cell_type_bar + remove_leg, 
      clust_bar + remove_leg, 
      htmp + remove_leg, 
      stacked_legends,
      nrow = 1, align = 'h', axis = 'tb',
      rel_widths = c(0.03, 0.03, 1, 0.2)
    )
  }
  
  return(final_plot)
}

cna_sig_cor_plot <- function(cna_sig_cor, sample_name, malig_thresh = NULL, y_max = NULL) {
  #' Scatter Plot of CNA Correlation vs. CNA Signal
  #'
  #' @description
  #' Generates a scatter plot visualizing the Copy Number Alteration (CNA) correlation 
  #' against the CNA signal for a specific sample. Each point represents a cell, 
  #' colored by its assigned cell type (`ct`). If malignancy thresholds are 
  #' provided, dashed lines are drawn to demarcate the boundaries typically used 
  #' to separate normal from malignant cell populations.
  #'
  #' @param cna_sig_cor A `data.table` or `data.frame` containing the calculated 
  #'   CNA metrics. Must include the columns `sample`, `cna_cor`, 
  #'   `cna_signal`, and `ct` (cell type).
  #' @param sample_name A character string representing the sample to plot. Used to 
  #'   subset the data and as the plot title.
  #' @param malig_thresh An optional nested list containing malignancy threshold coordinates. 
  #'   If provided, it must be structured such that `malig_thresh[[sample_name]][[1]]` 
  #'   returns a named numeric vector containing `'nm_x'`, `'m_x'`, `'nm_y'`, 
  #'   and `'m_y'`. Defaults to `NULL`.
  #' @param y_max Max value for y-axis scaling.
  #'
  #' @return A `ggplot` object representing the scatter plot.
  
  sig_cor_plot <- ggplot2::ggplot(cna_sig_cor[sample == sample_name]) +
    ggplot2::geom_point(ggplot2::aes(x = cna_cor, y = cna_signal, colour = ct)) +
    # Increased axis tick frequency for easier threshold selection
    ggplot2::scale_x_continuous(breaks = seq(-1, 1, by = 0.1)) +
    ggplot2::scale_y_continuous(breaks = seq(0, max(cna_sig_cor$cna_signal, na.rm = TRUE) + 0.1, by = 0.1)) +
    ggplot2::labs(colour = NULL, x = 'CNA correlation', y = 'CNA signal', title = sample_name) +
    ggplot2::theme_test()
  
  if (!is.null(malig_thresh)) {
    t_vals <- unlist(malig_thresh[[sample_name]][[1]])
    
    m_x <- t_vals['m_x']
    m_y <- t_vals['m_y']
    nm_x <- t_vals['nm_x']
    nm_y <- t_vals['nm_y']
    
    sig_cor_plot <- sig_cor_plot +
      ggplot2::geom_vline(xintercept = m_x, linetype = 'dashed', color = 'red') +
      ggplot2::geom_hline(yintercept = m_y, linetype = 'dashed', color = 'red') +
      ggplot2::geom_vline(xintercept = nm_x, linetype = 'dashed', color = 'blue') +
      ggplot2::geom_hline(yintercept = nm_y, linetype = 'dashed', color = 'blue')
  }
  
  if (!is.null(y_max)) {
    sig_cor_plot <- sig_cor_plot + ggplot2::coord_cartesian(ylim = c(0, y_max))
  }
  
  return(sig_cor_plot)
}

summary_cna_heatmap <- function(expdt, cells_filt, ref_cells) {
  #' Plot a Faceted Summary Heatmap of Inferred CNA
  #'
  #' @description
  #' Generates a faceted \code{ggplot2} heatmap summarizing Copy Number Alterations (CNA) 
  #' across different cell categories. Automatically handles chromosome label mapping, 
  #' cell categorization, gene factoring, and cell downsampling.
  #'
  #' @param expdt A \code{data.table} in long format containing the raw CNA data.
  #' @param cells_filt A \code{data.table} of cell annotations, including the newly assigned 
  #'   \code{cell_type} and \code{subclone} columns.
  #' @param ref_cells A \code{data.table} of reference cell annotations used for the subtitle.
  #'
  #' @return A \code{ggplot} object representing the faceted summary CNA heatmap.
  
  # 1. Exclude chromosomes with too few genes
  chr_n <- expdt[, .(n = length(unique(gene))), keyby = chr][n > 20]
  expdt <- expdt[chr %in% chr_n$chr] 
  
  # 2. X-axis coordinates for labels
  chr_lab <- c('01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12', '14', '16', '17', '18', '19', '20', '22', 'X')
  chr_lab <- unique(expdt[, .(gene, chr)])[,
                                           {inds <- chr_n[, floor(cumsum(n) - n/2)[chr %in% chr_lab]]; setNames(gsub('^0', '', chr[inds]), as.character(gene)[inds])}
  ] 
  
  # 3. Merge cell assignments
  expdt[cells_filt, on = 'cell_name', c('cell_type', 'subclone') := .(i.cell_type, i.subclone)]
  expdt <- expdt[!is.na(cell_type)]
  
  # 4. Factor gene to preserve genomic order (Crucial step to prevent alphabetical sorting!)
  expdt[, gene := factor(gene, levels = unique(gene))]
  
  # 5. Create plotting categories
  expdt[, categ := ifelse(!(cell_type %in% c('Malignant', 'Unassigned', '')), 'Non-malignant', cell_type)]
  expdt[categ == 'Malignant', categ := if (length(unique(subclone)) > 1) {
    ifelse(is.na(subclone), 
           paste0(categ, '\n(No subclone)'), 
           paste0(categ, '\n(subclone ', subclone, ')'))
  } else {
    categ
  }]
  expdt[, categ := factor(categ, levels = c('Non-malignant', 'Unassigned', sort(unique(categ[!(categ %in% c('Non-malignant', 'Unassigned'))]))))]
  
  # 6. Downsample cells (max 200 per category, grouped strictly by final 'categ')
  set.seed(42) 
  cells_sample <- expdt[
    !is.na(cell_type) & cell_type != '',
    .SD[sample(1:.N, min(.N, 200), replace = FALSE)],
    by = categ
  ]$cell_name
  
  # 7. Generate Plot
  summary_cna_plot <- ggplot2::ggplot(expdt[cell_name %in% cells_sample]) +
    ggplot2::geom_raster(ggplot2::aes(x = gene, y = cell_name, fill = cna)) +
    ggplot2::facet_grid(rows = ggplot2::vars(categ), scales = 'free_y', space = 'free_y') +
    ggplot2::geom_vline(ggplot2::aes(xintercept = xi), 
                        data = data.table::data.table(xi = chr_n[1:(.N - 1), cumsum(n) + 0.5]), 
                        linewidth = 0.3) +
    ggplot2::scale_fill_gradientn(colours = rev(RColorBrewer::brewer.pal(11, 'RdBu')), 
                                  limits = c(-1, 1), breaks = c(-1, 0, 1), oob = scales::squish) +
    ggplot2::scale_x_discrete(expand = c(0, 0), breaks = names(chr_lab), labels = chr_lab) +
    ggplot2::scale_y_discrete(expand = c(0, 0)) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(size = 12), 
                   axis.text.y.left = ggplot2::element_blank(),
                   axis.text.y.right = ggplot2::element_text(angle = -90, hjust = 0.5, size = 14), 
                   axis.ticks = ggplot2::element_blank(), axis.ticks.length = ggplot2::unit(0, 'pt'),
                   axis.title.x = ggplot2::element_text(size = 14), 
                   axis.title.y.left = ggplot2::element_blank(), 
                   axis.title.y.right = ggplot2::element_text(size = 14),
                   legend.title = ggplot2::element_text(size = 12, margin = ggplot2::margin(b = 6)), 
                   legend.text = ggplot2::element_text(size = 10), legend.justification = c(0.5, 0),
                   panel.border = ggplot2::element_rect(fill = NA, colour = 'black', linewidth = 0.5), 
                   plot.title = ggplot2::element_text(size = 14, face = 'bold'),
                   plot.subtitle = ggplot2::element_text(size = 12), 
                   strip.background = ggplot2::element_rect(fill = NA), 
                   strip.text.y = ggplot2::element_text(angle = 0, hjust = 0),
                   strip.clip = "off",                                    
                   panel.spacing.y = ggplot2::unit(1.0, "lines"))+
    ggplot2::guides(fill = ggplot2::guide_colourbar(barwidth = ggplot2::unit(15, 'pt'), 
                                                    barheight = ggplot2::unit(70, 'pt'), 
                                                    ticks.colour = 'black', frame.colour = 'black')) +
    ggplot2::labs(
      x = 'Chromosome', y = 'Cells', fill = 'Inferred CNA\n(log2 ratio)',
      subtitle = paste0('Reference: ', ref_cells[, paste(unique(cell_type), collapse = ', ')])
    )
  
  return(summary_cna_plot)
}






