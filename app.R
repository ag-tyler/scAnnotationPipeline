# ==================================================================================================
# Script: app.R
# Purpose: Shiny App for scRNA-seq cancer dateset cell type annotation
# ==================================================================================================

library(shiny)
library(data.table)
library(bslib)
library(shinyjs)

# ==================================================================================================
# 0. GLOBAL SETUP & ENVIRONMENT
# ==================================================================================================

# 1. Load general config
if (!file.exists('general_config.yaml')) {
  stop(
    "general_config.yaml not found in the working directory (", getwd(), ").\n",
    "This app must be launched from its own directory — e.g. via shiny::runApp('path/to/app'), ",
    "or the RStudio 'Run App' button with app.R open.",
    call. = FALSE
  )
}
config <- yaml::read_yaml('general_config.yaml')

# 2. Source utility scripts
sources_path <- 'util_scripts/'

if (!dir.exists(sources_path)) {
  stop("Utility scripts folder not found at '", sources_path, 
       "'. Make sure app.R is launched from the app's root directory.", call. = FALSE)
}

r_files <- list.files(sources_path, pattern = '\\.R$', full.names = TRUE)

if (length(r_files) == 0) {
  stop("No .R files found in '", sources_path, "'. Utility functions could not be loaded.", 
       call. = FALSE)
}

invisible(lapply(r_files, source))

# 3. Setup Generic Paths
resources_dir_path <- config$paths$resources_dir
marker_sets_path <- file.path(resources_dir_path, config$resource_files$marker_sets)
housekeeping_genes_path <- file.path(resources_dir_path, config$resource_files$housekeeping_genes)
mito_genes_path <- file.path(resources_dir_path, config$resource_files$mitochondrial_genes)
malignant_markers_path <- file.path(resources_dir_path, config$resource_files$malignant_markers)
cancer_cell_map_path <- file.path(resources_dir_path, config$resource_files$cancer_cell_map)
gene_positions_path <- file.path(resources_dir_path, config$resource_files$gene_positions)
hgnc_complete_set_path <- file.path(resources_dir_path, config$resource_files$hgnc_complete_set)
metadata_prompt_path <- file.path(resources_dir_path, config$resource_files$metadata_prompt)

# Validate all resource paths up front, so one failed check gives one clear message
# instead of bailing out partway through with the rest of the state half-loaded.
resource_checks <- list(
  "marker gene sets"       = marker_sets_path,
  "housekeeping genes"     = housekeeping_genes_path,
  "mitochondrial genes"    = mito_genes_path,
  "malignant markers"      = malignant_markers_path,
  "cancer cell map"        = cancer_cell_map_path,
  "gene positions"         = gene_positions_path,
  "HGNC complete set"      = hgnc_complete_set_path,
  "metadata extract prompt"= metadata_prompt_path
)

missing <- resource_checks[!file.exists(unlist(resource_checks))]

if (length(missing) > 0) {
  stop(
    "The following resource files could not be found (check `resources_dir` in ",
    "general_config.yaml / local_config.yaml, and `resource_files` for correct filenames):\n",
    paste0(" - ", names(missing), ": ", unlist(missing), collapse = "\n"),
    call. = FALSE
  )
}

# Now safe to load
marker_genes <- fread(marker_sets_path)
malignant_markers <- fread(malignant_markers_path)
housekeeping_genes <- fread(housekeeping_genes_path, header = FALSE)$V1
mt_genes <- fread(mito_genes_path, header = FALSE)$V1
cancer_cell_map <- jsonlite::read_json(cancer_cell_map_path)
clipboard_text <- paste(readLines(metadata_prompt_path), collapse = "\n")
hgnc_complete_set <- data.table::fread(hgnc_complete_set_path)
gene_positions <- data.table::fread(gene_positions_path)

dataset_base_dir <- config$paths$datasets_dir
dir.create(dataset_base_dir, recursive = TRUE, showWarnings = FALSE) # Ensure it exists

# Scan for available datasets on startup
all_dataset_dirs <- list.dirs(dataset_base_dir, recursive = FALSE)
available_datasets <- basename(all_dataset_dirs[all_dataset_dirs != dataset_base_dir])

# Drop malignant cell type & format
marker_genes <- marker_genes[cell_type != 'Malignant', ]
marker_genes[, cell_type := gsub(" ", "_", cell_type)]

gene_positions_path <- file.path(resources_dir_path, config$resource_files$gene_positions)
hgnc_complete_set_path <- file.path(resources_dir_path, config$resource_files$hgnc_complete_set)

# Remove repeated Ensembl IDs:
hgnc_complete_set <- hgnc_complete_set[!(ensembl_gene_id %in% names(table(ensembl_gene_id))[table(ensembl_gene_id) > 1])]

# SAFELY CREATE 'symbol' AND 'location' WITHOUT DO.CALL
gene_positions[hgnc_complete_set, on = "ensembl_gene_id", 
               c('symbol', 'location') := .(i.symbol, i.location_sortable)]

gene_positions <- gene_positions[!is.na(hgnc_symbol) & chromosome_name %in% c(as.character(1:22), 'X', 'Y')]
gene_positions[chromosome_name %in% as.character(1:9), chromosome_name := paste0("0", chromosome_name)]

data.table::setkey(gene_positions, hgnc_symbol)

# Provide placeholder choices for UI before dataset loads
sample_choices <- c("Please select a dataset first" = "")

# ==================================================================================================
# 1. UI DEFINITION
# ==================================================================================================

ui <- page_navbar(
  id = "main_nav",
  title = "scRNA-seq Annotation Pipeline",
  theme = bs_theme(version = 5, bootswatch = "flatly", primary = "#2c3e50"),
  header = tagList(
    useShinyjs()
  ),
  
  # ------------------------------------------------------------------------------------------------
  # TAB 0: DATASET SELECTION (Shown on launch)
  # ------------------------------------------------------------------------------------------------
  nav_panel(
    title = "Dataset Selection",
    value = "dataset_tab",
    div(class = "container mt-5", style = "max-width: 800px;",
        h2("Initialize Pipeline", class = "mb-4 text-center"),
        card(
          card_header(h4("Select Workspace", class = "mb-0 text-center")),
          card_body(
            p("Please select a dataset folder to load its configurations and processed data.", class = "text-muted"),
            selectInput("dataset_choice", "Available Datasets:", choices = available_datasets, width = "100%"),
            actionButton("btn_load_dataset", "Load Dataset", icon = icon("folder-open"), 
                         class = "btn-primary btn-lg w-100 mt-3"),
            actionButton("btn_create_dataset_ui", "Create New Dataset", icon = icon("folder-plus"), 
                         class = "btn-success btn-lg w-100 mt-2")
          )
        )
    )
  ),
  
  
  
  # ------------------------------------------------------------------------------------------------
  # TAB 1: START MENU
  # ------------------------------------------------------------------------------------------------
  nav_panel(
    title = "Start Menu", 
    value = "menu_tab",
    
    div(class = "container mt-5", style = "max-width: 800px;",
        h2("Pipeline Dashboard", class = "mb-4 text-center"),
        
        # New Button to change workspace
        actionButton("btn_change_dataset", "Change Dataset", icon = icon("exchange-alt"), 
                     class = "btn-outline-primary btn-lg w-100 mb-4"),
        
        card(
          card_header(h4("Utilities", class = "mb-0")),
          card_body(
            p("View and extract metadata prompt:"),
            actionButton("btn_copy_info", "Go to Reference Data", 
                         icon = icon("file-alt"), class = "btn-outline-secondary w-100")
          )
        ),
        
        card(
          card_header(h4("Pre-Processing & Clustering", class = "mb-0")),
          card_body(
            p("Runs PCA, UMAP, and Louvain clustering across all predefined resolutions for all samples."),
            actionButton("btn_run_clustering", "Run Clustering for all Resolutions", 
                         icon = icon("cogs"), class = "btn-primary btn-lg w-100")
          )
        ),
        
        card(
          card_header(h4("Resolution Selection", class = "mb-0")),
          card_body(
            p("Review UMAP plots for each sample and select the most biologically relevant clustering resolution."),
            actionButton("btn_go_res", "Go to Resolution Selection", 
                         icon = icon("search"), class = "btn-info btn-lg w-100")
          )
        ),
        
        card(
          card_header(h4("Differential Expression (DE)", class = "mb-0")),
          card_body(
            p("Runs differential expression analysis. ", 
              strong("Requires a resolution to be selected for all samples.")),
            actionButton("btn_run_de", "Run Differential Expression Analysis", 
                         icon = icon("chart-bar"), class = "btn-warning btn-lg w-100")
          )
        ),
        
        card(
          card_header(h4("Manual Cell Type Annotation", class = "mb-0")),
          card_body(
            p("Assign final cell identities based on DE marker matches and signature scores."),
            actionButton("btn_go_anno", "Go to Manual Annotation", 
                         icon = icon("edit"), class = "btn-success btn-lg w-100")
          )
        ),
        
        card(
          card_header(h4("Copy Number Alteration (CNA)", class = "mb-0")),
          card_body(
            p("Run the CNA pipeline: compute CNA signals, select malignant clusters, and assign malignant cells."),
            actionButton("btn_go_cna", "Go to CNA Analysis", 
                         icon = icon("dna"), class = "btn-danger btn-lg w-100")
          )
        )
    )
  ),
  
  # ------------------------------------------------------------------------------------------------
  # TAB 1.5: REFERENCE DATA DISPLAY
  # ------------------------------------------------------------------------------------------------
  nav_panel(
    title = "Reference Data",
    value = "clipboard_tab",
    
    div(class = "container mt-5", style = "max-width: 800px;",
        h3("Metadata Extraction Prompt", class = "mb-3"),
        
        div(class = "alert alert-info",
            icon("info-circle"), " Click 'Select All Text' below, then manually copy (Ctrl+C / Cmd+C)."
        ),
        
        actionButton("btn_select_all", "Select All Text", 
                     icon = icon("check-square"), class = "btn-primary mb-3"),
        
        tags$textarea(id = "prompt_text_area", 
                      class = "form-control mb-4", 
                      style = "height: 50vh; font-family: monospace; resize: vertical;", 
                      readonly = TRUE, 
                      clipboard_text),
        
        actionButton("btn_back_menu_3", "Back to Menu", class = "btn-secondary w-100")
    )
  ),
  
  # ------------------------------------------------------------------------------------------------
  # TAB 2: RESOLUTION SELECTION
  # ------------------------------------------------------------------------------------------------
  nav_panel(
    title = "Resolution Selection", 
    value = "res_tab",
    
    page_sidebar(
      sidebar = sidebar(
        title = "Selection Controls",
        selectInput("res_sample_idx", "1. Select Sample:", choices = sample_choices),
        uiOutput("res_status_badge"),
        hr(),
        uiOutput("res_radio_ui"),
        actionButton("btn_save_res", "Save Resolution", class = "btn-success w-100"),
        hr(),
        
        h6("Targeted Reanalysis", class = "mt-2"),
        actionButton("btn_rerun_single_de", "Rerun DE for Sample", 
                     icon = icon("sync"), class = "btn-warning w-100"),
        hr(),
        
        actionButton("btn_back_menu_1", "Back to Menu", class = "btn-secondary w-100")
      ),
      h3(textOutput("res_header_text")),
      p("Click through the tabs below to view each resolution in full detail."),
      uiOutput("res_plots_tabs")
    )
  ),
  
  # ------------------------------------------------------------------------------------------------
  # TAB 3: MANUAL ANNOTATION
  # ------------------------------------------------------------------------------------------------
  nav_panel(
    title = "Manual Annotation", 
    value = "anno_tab",
    
    page_sidebar(
      sidebar = sidebar(
        title = "Annotation Controls",
        
        selectInput("sample_idx", "1. Select Sample:", choices = sample_choices, selected = sample_choices[1]),
        uiOutput("anno_status_badge"),
        actionButton("btn_anno_next", "Next Sample", class = "btn-secondary btn-sm w-100 mt-2"),
        hr(),
        
        uiOutput("cluster_selector"),
        uiOutput("current_cluster_annotation"),
        actionButton("btn_cluster_next", "Next Cluster", class = "btn-secondary btn-sm w-100 mt-2"), 
        hr(),
        
        h5("3. Assign Cell Type"),
        uiOutput("cell_type_input_ui"),
        actionButton("assign_btn", "Assign to Cluster", class = "btn-primary w-100"),
        hr(),
        
        h5("4. Finalize Annotation"),
        actionButton("preview_btn", "1. Preview Annotated Plot", class = "btn-info w-100"),
        br(),
        actionButton("save_btn", "2. Save Annotations to Disk", class = "btn-success w-100"),
        hr(),
        
        h5("5. CNA Configuration"),
        uiOutput("ref_cell_selector"),
        uiOutput("pot_mal_cell_selector"),
        actionButton("btn_save_refs", "Save CNA Config", class = "btn-warning w-100"),
        hr(),
        
        actionButton("btn_back_menu_2", "Back to Menu", class = "btn-secondary w-100")
      ),
      navset_card_underline(
        nav_panel("Cluster Exploration", 
                  fluidRow(
                    column(6, h4("UMAP Reference"), imageOutput("umap_ref_plot", height = "auto")),
                    column(6, h4("Cluster Score Boxplot"), imageOutput("cluster_boxplot", height = "auto"))
                  )
        ),
        nav_panel("DE Marker Matches", 
                  h4("Matched Marker Genes for Selected Cluster"),
                  DT::DTOutput("marker_table")
        ),
        nav_panel("Final Annotation Preview", 
                  h4("Annotated UMAP"),
                  p("Click 'Preview Annotated Plot' to render this view before saving."),
                  plotOutput("final_umap_plot", height = "600px")
        )
      )
    )
  ),
  
  # ------------------------------------------------------------------------------------------------
  # TAB 4: CNA ANALYSIS
  # ------------------------------------------------------------------------------------------------
  nav_panel(
    title = "CNA Analysis", 
    value = "cna_tab",
    
    page_sidebar(
      sidebar = sidebar(
        title = "CNA Pipeline Controls",
        
        # 1. Sample Selection
        selectInput("cna_sample_idx", "1. Select Sample:", choices = sample_choices),
        actionButton("btn_cna_next", "Next Sample", class = "btn-secondary btn-sm w-100 mt-2"),
        hr(),
        
        # 2. Pipeline Action Buttons
        h5("Pipeline Steps", class = "mb-3"),
        
        actionButton("btn_cna_compute_heatmaps", "1. Compute CNA & Heatmaps", 
                     class = "btn-primary w-100 mb-2"),
        
        actionButton("btn_cna_batch_compute", "Batch Compute (All Samples)", 
                     icon = icon("layer-group"), class = "btn-outline-primary btn-sm w-100 mb-2"),
        
        actionButton("btn_cna_go_malig_clust", "2. Select Malignant Clusters", 
                     class = "btn-info w-100 mb-2"),
        
        actionButton("btn_cna_compute_sig_cor", "3. Compute Signal & Cor", 
                     class = "btn-primary w-100 mb-2"),
        
        actionButton("btn_cna_go_thresholds", "4. Select Thresholds", 
                     class = "btn-info w-100 mb-2"),
        
        actionButton("btn_cna_go_summary", "5. Assign & Summary", 
                     class = "btn-warning w-100 mb-2"),
        
        hr(),
        actionButton("btn_cna_reset", "Reset Sample CNA", 
                     icon = icon("trash-alt"), class = "btn-danger w-100 mb-2"),
        actionButton("btn_cna_back_menu", "Back to Menu", class = "btn-secondary w-100")
      ),
      
      # Main Body: Dynamic views based on the active step
      navset_hidden(
        id = "cna_main_views",
        
        # View 1: Default / Welcome View
        nav_panel("cna_view_default",
                  div(class = "container mt-5 text-center",
                      h3(textOutput("cna_header_text")),
                      p("Select a sample from the sidebar to check the cache status.", class = "text-muted"),
                      uiOutput("cna_status_ui")
                  )
        ),
        
        # View 2: Malignant Cluster Selection
        nav_panel("cna_view_select_malignant",
                  h3("2. Select Malignant Clusters"),
                  p("Adjust the slider to split the tree into 'k' clusters. The heatmap will update to visually separate or color these clusters. Select the malignant ones below."),
                  
                  fluidRow(
                    column(3,
                           card(
                             card_header("Cluster Settings"),
                             card_body(
                               sliderInput("cna_k_clusters", "Number of Clusters (k):", min = 2, max = 20, value = 7, step = 1),
                               hr(),
                               
                               helpText("Use the dropdown menu below to select one or more clusters that exhibit clear malignant copy number alterations (amplifications/deletions)."),
                               
                               selectizeInput("cna_selected_clusters", 
                                              label = "Select Malignant Subclones:", 
                                              choices = NULL, 
                                              multiple = TRUE,
                                              options = list(placeholder = "e.g., 2, 4")),
                               hr(),
                               actionButton("btn_cna_save_malignant", "Save Clusters", icon = icon("cogs"), class = "btn-success w-100")
                             )
                           )
                    ),
                    column(9,
                           # A tall output is necessary for a heatmap with thousands of cells
                           plotOutput("cna_combined_heatmap_plot", height = "850px")
                    )
                  )
        ),
        
        # View 3: Threshold Selection
        nav_panel("cna_view_thresholds",
                  h3("Malignant Threshold Selection"),
                  p("Adjust the malignant and non-malignant thresholds for each subclone using the tabs below."),
                  # This UI output will dynamically generate tabs for each subclone
                  uiOutput("cna_dynamic_thresholds_ui")
        ),
        
        # View 4: Summary Heatmap & Previews
        nav_panel("cna_view_summary",
                  h3("CNA Summary & Final Assignment"),
                  p("Click 'Preview' to generate the plots. Use the tabs below to switch between the visualisations. Once satisfied, click 'Finalize & Save'."),
                  
                  # Place the buttons side-by-side
                  fluidRow(
                    column(6, 
                           actionButton("btn_cna_preview_summary", "1. Preview Assignments & Plots", 
                                        icon = icon("eye"), class = "btn-info w-100 mb-3")
                    ),
                    column(6, 
                           shinyjs::disabled(
                             actionButton("btn_cna_save_summary", "2. Finalize & Save CNA Analysis", 
                                          icon = icon("save"), class = "btn-success w-100 mb-3")
                           )
                    )
                  ),
                  
                  # Tabbed Plot Area
                  navset_card_underline(
                    id = "cna_preview_tabs",
                    
                    nav_panel("Scatter Plots", 
                              br(),
                              uiOutput("cna_preview_scatter_ui")
                    ),
                    
                    nav_panel("UMAP Projection", 
                              br(),
                              plotOutput("cna_preview_umap", height = "600px")
                    ),
                    
                    nav_panel("Summary Heatmap", 
                              br(),
                              plotOutput("cna_preview_heatmap", height = "700px")
                    )
                  )
        )
        
      )
    )
  )
  
)

# ==================================================================================================
# 2. SERVER LOGIC
# ==================================================================================================

server <- function(input, output, session) {
  
  # Hide main tabs on startup to force dataset selection
  nav_hide("main_nav", target = "menu_tab")
  nav_hide("main_nav", target = "clipboard_tab")
  nav_hide("main_nav", target = "res_tab")
  nav_hide("main_nav", target = "anno_tab")
  nav_hide("main_nav", target = "cna_tab")
  updateNavbarPage(session, "main_nav", selected = "dataset_tab")
  
  # --- State Management ---
  rv <- reactiveValues(
    # Resources
    gene_positions = gene_positions,
    cancer_cell_map = cancer_cell_map,
    clipboard_text = clipboard_text,
    
    # Core Configurations
    paths_list = NULL,
    dataset_config = NULL,
    samples_config = NULL,
    live_selected_config = NULL, 
    complete_markers = NULL,
    results_dir_path = NULL,
    selected_config_path = NULL,
    dataset_dir_path = NULL, 
    config = NULL,           
    
    # Active State
    cells_filt = NULL,
    all_matches = NULL,
    cells_raw = NULL,
    sample_name = NULL,
    res = NULL,
    final_plot = NULL
  )
  
  # ================================================================================================
  # DATASET LOADING LOGIC
  # ================================================================================================
  
  observeEvent(input$btn_load_dataset, {
    req(input$dataset_choice)
    dataset_name <- input$dataset_choice
    
    id <- showNotification(paste("Loading workspace:", dataset_name), duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    dataset_dir_path <- file.path(config$paths$datasets_dir, dataset_name)
    
    # 1. Verify Dataset Files
    dataset_config_path <- file.path(dataset_dir_path, config$config_files$dataset)
    samples_config_path <- file.path(dataset_dir_path, config$config_files$samples)
    selected_config_path <- file.path(dataset_dir_path, config$config_files$selected)
    
    if (!file.exists(dataset_config_path)) {
      showNotification("Configuration file missing for this dataset. Aborting load.", type = "error", duration = 8)
      return()
    }
    
    # 2. Parse Configs
    dataset_config <- yaml::read_yaml(dataset_config_path)
    samples_config <- tryCatch(yaml::read_yaml(samples_config_path), error = function(e) list())
    
    if (file.exists(selected_config_path)) {
      selected_config <- yaml::read_yaml(selected_config_path)
    } else {
      # Initialize empty state if it's a new dataset
      selected_config <- list(resolutions = list(), cna_ref_cells = list(), cna_pot_mal_cells = list())
    }
    
    # 3. Setup Paths specific to dataset
    processed_dir_path <- file.path(dataset_dir_path, config$dataset_paths$processed_dir)
    
    if (!dir.exists(processed_dir_path)) {
      showNotification(
        paste0("Processed data folder not found: ", processed_dir_path, 
               ". Run the standardization pipeline (standardize.qmd) for this dataset first."), 
        type = "error", duration = 10
      )
      return()
    }
    
    sample_dir_paths <- list.dirs(processed_dir_path, recursive = FALSE)
    
    if (length(sample_dir_paths) == 0) {
      showNotification(
        "No sample folders found in processed_data/. Run standardize.qmd before loading this dataset.", 
        type = "error", duration = 10
      )
      return()
    }
    
    results_dir_path <- file.path(dataset_dir_path, config$dataset_paths$results_dir)
    
    dir.create(results_dir_path, showWarnings = FALSE)
    
    # Gather sample paths
    sample_dir_paths <- list.dirs(processed_dir_path, recursive = FALSE)
    cell_file_paths <- file.path(sample_dir_paths, dataset_config$std_names$cells)
    expmat_file_paths <- file.path(sample_dir_paths, dataset_config$std_names$expmat)
    genes_file_paths <- file.path(sample_dir_paths, dataset_config$std_names$genes)
    
    paths_list <- list(
      sample_dir_paths = sample_dir_paths,
      cell_file_paths = cell_file_paths,
      expmat_file_paths = expmat_file_paths,
      genes_file_paths = genes_file_paths
    )
    
    # 4. Generate Dataset-Specific Marker Filters
    complete_markers <- marker_genes[, {
      n_passing <- sum(combined > dataset_config$marker_filter_params$cell_type$min_score)
      n_keep <- max(dataset_config$marker_filter_params$cell_type$min_genes, 
                    min(n_passing, dataset_config$marker_filter_params$cell_type$max_genes))
      head(.SD, n_keep)
    }, by = cell_type]
    
    setnames(complete_markers, old = 'gene', new = 'symbol', skip_absent = TRUE)
    
    complete_markers <- complete_markers[, .(cell_type, symbol)]
    housekeeping_genes_dt <- data.table(cell_type = 'Housekeeping_artifact', symbol = housekeeping_genes)
    mt_genes_dt <- data.table(cell_type = 'Mito_artifact', symbol = mt_genes)
    complete_markers <- rbindlist(list(complete_markers, housekeeping_genes_dt, mt_genes_dt))
    
    # Attempt to load samples for utilities if present
    samples_path <- file.path(processed_dir_path, dataset_config$std_names$samples)
    samples <- tryCatch(load_samples(samples_path), error = function(e) NULL)
    
    # Select malignant markers depending on dataset cancer type, skip if markers not available
    if (!is.null(samples) && "cancer_type" %in% names(samples)) {
      
      cancer_type <- unique(na.omit(samples$cancer_type))
      
      if (length(cancer_type) == 1 && cancer_type %in% names(cancer_cell_map$cancer_types)) {
        
        tryCatch({
          cancer_type_acronym <- cancer_cell_map$cancer_types[[cancer_type]]
          cancer_cell_type <- cancer_cell_map$cell_types[[cancer_type_acronym]]
          
          if (is.null(cancer_cell_type)) {
            stop("cancer_cell_map$cell_types has no entry for acronym: ", cancer_type_acronym)
          }
          
          filtered_malignant_markers <- malignant_markers[, {
            n_passing <- sum(combined > dataset_config$marker_filter_params$cancer_type$min_score)
            n_keep <- max(dataset_config$marker_filter_params$cancer_type$min_genes, 
                          min(n_passing, dataset_config$marker_filter_params$cancer_type$max_genes))
            head(.SD, n_keep)
          }, by = cancer_type]
          
          if (cancer_type_acronym == 'HNSCC') {
            n_hnscc_genes <- dataset_config$marker_filter_params$cancer_type$min_genes
            cancer_type_markers <- filtered_malignant_markers[
              cancer_type %in% c("HNSCC_HPV-neg", "HNSCC_HPV-pos"), 
              head(.SD, n_hnscc_genes),
              by = cancer_type
            ][, cancer_type := "HNSCC"]
          } else {
            cancer_type_markers <- filtered_malignant_markers[cancer_type == cancer_type_acronym, ]
          }
          
          setnames(cancer_type_markers, old = 'cancer_type', new = 'cell_type')
          cancer_type_markers[, cell_type := cancer_cell_type]
          cancer_type_markers <- cancer_type_markers[, .(cell_type, symbol)]  # match complete_markers' schema
          
          complete_markers <- rbindlist(list(complete_markers, cancer_type_markers))
          
        }, error = function(e) {
          warning("Could not add cancer-type-specific malignant markers: ", e$message, call. = FALSE)
        })
      }
    }
    
    # 5. Populate Reactive State
    rv$paths_list <- paths_list
    rv$dataset_config <- dataset_config
    rv$samples_config <- samples_config
    rv$live_selected_config <- selected_config
    rv$results_dir_path <- results_dir_path
    rv$selected_config_path <- selected_config_path
    rv$complete_markers <- complete_markers
    rv$dataset_dir_path <- dataset_dir_path
    
    # Update config with the selected configs and store it
    local_config <- config
    local_config$selected <- selected_config
    rv$config <- local_config
    
    # 6. Update UI Dropdowns
    s_choices <- setNames(
      seq_along(paths_list$sample_dir_paths), 
      basename(paths_list$sample_dir_paths)
    )
    updateSelectInput(session, "res_sample_idx", choices = s_choices)
    updateSelectInput(session, "sample_idx", choices = s_choices)
    
    # 7. Reveal App Tabs & Jump to Dashboard
    nav_show("main_nav", target = "menu_tab")
    nav_show("main_nav", target = "clipboard_tab")
    nav_show("main_nav", target = "res_tab")
    nav_show("main_nav", target = "anno_tab")
    nav_show("main_nav", target = "cna_tab")
    nav_hide("main_nav", target = "dataset_tab")
    updateNavbarPage(session, "main_nav", selected = "menu_tab")
    
    showNotification("Dataset loaded successfully!", type = "default")
  })
  
  observeEvent(input$btn_change_dataset, {
    # Allow user to swap datasets - reveal selection UI
    nav_show("main_nav", target = "dataset_tab")
    nav_hide("main_nav", target = "menu_tab")
    nav_hide("main_nav", target = "clipboard_tab")
    nav_hide("main_nav", target = "res_tab")
    nav_hide("main_nav", target = "anno_tab")
    updateNavbarPage(session, "main_nav", selected = "dataset_tab")
  })
  
  observeEvent(input$btn_create_dataset_ui, {
    showModal(modalDialog(
      title = "Create New Dataset Workspace",
      textInput("new_ds_name", "Dataset Name (Folder Name):", placeholder = "e.g., Pancreas_Dataset_02"),
      textInput("new_ds_location", "Location (Parent Directory):", value = dataset_base_dir),
      selectInput("new_ds_tech", "Technology:", choices = config$standardization_pipelines),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("btn_confirm_create_ds", "Create Dataset", class = "btn-primary")
      )
    ))
  })
  
  observeEvent(input$btn_confirm_create_ds, {
    req(input$new_ds_name, input$new_ds_location, input$new_ds_tech)
    
    parent_dir <- trimws(input$new_ds_location)
    
    # Validate the name — stop with a clear notification instead of a raw error
    ds_name <- tryCatch(
      sanitize_dataset_name(input$new_ds_name),
      error = function(e) {
        showNotification(e$message, type = "error", duration = 8)
        NULL
      }
    )
    req(ds_name)  # halts here if sanitize_dataset_name() failed above
    
    new_ds_path <- file.path(parent_dir, ds_name)
    
    # Belt-and-suspenders: confirm the resolved path still lives under parent_dir.
    # normalizePath(mustWork=FALSE) resolves '.', symlinks, etc. without requiring 
    # the path to exist yet.
    resolved_new_path <- normalizePath(new_ds_path, mustWork = FALSE)
    resolved_parent   <- normalizePath(parent_dir, mustWork = FALSE)
    
    if (!startsWith(resolved_new_path, resolved_parent)) {
      showNotification("Invalid dataset location — path escapes the parent directory.", 
                       type = "error", duration = 8)
      return()
    }
    
    # 1. Validation (existing check, now after the safety checks above)
    if (dir.exists(new_ds_path)) {
      showNotification("A dataset with this name already exists at this location.", type = "error")
      return()
    }
    
    template_path <- "templates/dataset_config_template.yaml"
    if (!file.exists(template_path)) {
      showNotification("dataset_config_template.yaml not found in the template folder!", type = "error")
      return()
    }
    
    # 2. Create Directory Structure
    dir.create(new_ds_path, recursive = TRUE, showWarnings = FALSE)
    subfolders <- c("cache", "data", "processed_data", "results")
    lapply(subfolders, function(f) dir.create(file.path(new_ds_path, f), showWarnings = FALSE))
    
    # 3. Handle dataset_config.yaml 
    ds_config <- yaml::read_yaml(template_path)
    
    # Write the technology choice (including 'Undefined') to the config
    ds_config$project_info$dataset_id <- ds_name
    ds_config$project_info$technology <- input$new_ds_tech
    ds_config$raw_files$type <- input$new_ds_tech
    yaml::write_yaml(ds_config, file.path(new_ds_path, config$config_files$dataset))
    
    # 4. Handle samples_config.yaml 
    samples_config <- list(
      samples = list(
        list(
          id = "", technology = input$new_ds_tech, cancer_type = "", patient = "", histology = "",
          site = "", sample_type = "", sample_primary_met = "", disease_extent = "", diagnosis_recurrence = "",
          instance_at_site = "", treated_naive = "", age = "", sex = "", grade = "", AJCC_stage = "",
          AJCC_T = "", AJCC_N = "", AJCC_M = "", size = "", smoking_status = "", PY = "", KI67 = "",
          genetic_hormonal_features = "", chemotherapy_exposed = "", chemotherapy_response = "",
          targeted_rx_exposed = "", targeted_rx_response = "", post_sampling_rx_exposed = "",
          post_sampling_rx_response = "", time_end_of_rx_to_sampling = "", ET_exposed = "",
          ET_response = "", ICB_exposed = "", ICB_response = "", PFS_DFS = "", OS = ""
        )
      )
    )
    yaml::write_yaml(samples_config, file.path(new_ds_path, config$config_files$samples))
    
    # 5. Handle selected_config.yaml 
    selected_config <- list(
      resolutions = list(), cna_ref_cells = list(), cna_pot_mal_cells = list(),
      cna_ward_ref_cluster = list(), cna_thresholds = list()
    )
    yaml::write_yaml(selected_config, file.path(new_ds_path, config$config_files$selected))
    
    # 6. Copy the Standardization Quarto Template
    # Map the technology to the correct template file
    tech_template_name <- paste0("standardize_", input$new_ds_tech, ".qmd")
    qmd_template_path <- paste0("templates/", tech_template_name)
    
    if (file.exists(qmd_template_path)) {
      file.copy(from = qmd_template_path, 
                to = file.path(new_ds_path, "standardize.qmd"))
    } else {
      showNotification(paste("Warning: Template", tech_template_name, "not found. No standardization script copied."), type = "warning", duration = 8)
    }
    
    # 7. Update UI and Close
    all_dataset_dirs <- list.dirs(parent_dir, recursive = FALSE)
    updated_datasets <- basename(all_dataset_dirs[all_dataset_dirs != dataset_base_dir])
    
    available_datasets <<- updated_datasets 
    updateSelectInput(session, "dataset_choice", choices = updated_datasets, selected = ds_name)
    
    removeModal()
    showNotification(paste("Dataset", ds_name, "initialized successfully!"), type = "message")
  })
  
  # ================================================================================================
  # MENU NAVIGATION & PIPELINE TRIGGERS
  # ================================================================================================
  
  observeEvent(input$btn_go_res, { updateNavbarPage(session, "main_nav", selected = "res_tab") })
  observeEvent(input$btn_go_anno, { updateNavbarPage(session, "main_nav", selected = "anno_tab") })
  observeEvent(input$btn_back_menu_1, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_back_menu_2, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_copy_info, { updateNavbarPage(session, "main_nav", selected = "clipboard_tab") })
  observeEvent(input$btn_back_menu_3, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_go_cna, { updateNavbarPage(session, "main_nav", selected = "cna_tab") })
  
  observeEvent(input$btn_select_all, {
    runjs("document.getElementById('prompt_text_area').select();")
  })
  
  observeEvent(input$btn_run_clustering, {
    req(rv$paths_list)
    showModal(modalDialog(
      title = "Confirm Clustering",
      "Are you sure you want to run the clustering pipeline? This process takes a significant amount of time and will lock the application until finished.",
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_run_clustering", "Yes, Run Clustering", class = "btn-danger")
      )
    ))
  })
  
  observeEvent(input$confirm_run_clustering, {
    removeModal()
    id <- showNotification("Running clustering pipeline. This may take a while. Check R console...", 
                           duration = NULL, type = "warning")
    cluster_all_samples(rv$paths_list, rv$dataset_config, rv$results_dir_path, rv$dataset_dir_path)
    removeNotification(id)
    showNotification("Clustering complete!", type = "message")
  })
  
  observeEvent(input$btn_run_de, {
    req(rv$paths_list)
    expected_samples <- basename(rv$paths_list$sample_dir_paths)
    
    unpicked_samples <- expected_samples[sapply(expected_samples, function(s) {
      res <- rv$live_selected_config$resolutions[[s]]
      is.null(res) || res == 0 || res == 0.0
    })]
    
    if (length(unpicked_samples) > 0) {
      msg <- paste("Cannot run DE! Missing resolutions for:", paste(unpicked_samples, collapse = ", "))
      showNotification(msg, type = "error", duration = 10)
    } else {
      showModal(modalDialog(
        title = "Confirm DE Analysis",
        "Are you sure you want to run the Differential Expression analysis? This process is computationally heavy and will lock the application.",
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton("confirm_run_de", "Yes, Run DE Analysis", class = "btn-danger")
        )
      ))
    }
  })
  
  observeEvent(input$confirm_run_de, {
    removeModal()
    id <- showNotification("Running DE analysis. Check R console...", duration = NULL, type = "warning")
    de_analysis(rv$paths_list, rv$dataset_config, rv$live_selected_config, rv$complete_markers, 
                rv$results_dir_path, rv$dataset_dir_path)
    removeNotification(id)
    showNotification("Differential Expression Analysis complete!", type = "message")
  })
  
  
  
  
  # ================================================================================================
  # RESOLUTION SELECTION LOGIC
  # ================================================================================================
  
  output$res_status_badge <- renderUI({
    req(rv$paths_list, input$res_sample_idx)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    
    current_val <- rv$live_selected_config$resolutions[[s_name]]
    
    if (is.null(current_val) || current_val == 0 || current_val == 0.0) {
      tags$div(class = "badge bg-warning text-dark w-100 py-2 mt-2", 
               style = "font-size: 14px; white-space: normal;",
               icon("exclamation-circle"), " Status: Unselected")
    } else {
      tags$div(class = "badge bg-success w-100 py-2 mt-2", 
               style = "font-size: 14px; white-space: normal;",
               icon("check-circle"), paste(" Status: Saved (Res:", current_val, ")"))
    }
  })
  
  output$res_header_text <- renderText({
    req(rv$paths_list, input$res_sample_idx)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    paste("Resolution Plots for:", s_name)
  })
  
  output$res_radio_ui <- renderUI({
    req(rv$paths_list, rv$dataset_config, input$res_sample_idx)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    
    current_val <- rv$live_selected_config$resolutions[[s_name]]
    if (is.null(current_val) || current_val == 0.0) current_val <- rv$dataset_config$params$resolutions[1]
    
    radioButtons("selected_res", "2. Choose Best Resolution:", 
                 choices = rv$dataset_config$params$resolutions, 
                 selected = current_val)
  })
  
  output$res_plots_tabs <- renderUI({
    req(rv$paths_list, rv$dataset_config, input$res_sample_idx)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    resolutions <- rv$dataset_config$params$resolutions
    
    grid_cols <- lapply(resolutions, function(res) {
      grid_output_id <- paste0("img_grid_", s_name, "_", res)
      
      local({
        local_res <- res
        local_s_name <- s_name
        output[[grid_output_id]] <- renderImage({
          plot_path <- file.path(rv$results_dir_path, local_s_name, '1_cluster_plots', 
                                 paste0('clusters_plot_', local_s_name, '_res_', local_res, '.png'))
          
          if(!file.exists(plot_path)) return(list(src = "", alt = "Plot not found."))
          
          list(src = plot_path, width = "100%", style = "max-height: 35vh; object-fit: contain;", alt = paste("Grid Res:", local_res))
        }, deleteFile = FALSE)
      })
      
      column(6, h5(paste("Resolution:", res), class = "text-center mt-3"), imageOutput(grid_output_id, height = "auto"))
    })
    
    grid_tab <- nav_panel(
      title = "Grid View (All)",
      fluidRow(tagList(grid_cols))
    )
    
    individual_tabs <- lapply(resolutions, function(res) {
      tab_output_id <- paste0("img_tab_", s_name, "_", res)
      
      local({
        local_res <- res
        local_s_name <- s_name
        output[[tab_output_id]] <- renderImage({
          plot_path <- file.path(rv$results_dir_path, local_s_name, '1_cluster_plots', 
                                 paste0('clusters_plot_', local_s_name, '_res_', local_res, '.png'))
          
          if(!file.exists(plot_path)) return(list(src = "", alt = "Plot not found."))
          
          list(src = plot_path, width = "100%", style = "max-height: 70vh; object-fit: contain;", alt = paste("Tab Res:", local_res))
        }, deleteFile = FALSE)
      })
      
      nav_panel(
        title = paste("Res:", res),
        div(class = "mt-3 text-center", imageOutput(tab_output_id, height = "auto"))
      )
    })
    
    all_tabs <- c(list(grid_tab), individual_tabs)
    do.call(navset_card_underline, all_tabs)
  })
  
  observeEvent(input$btn_save_res, {
    req(rv$paths_list, input$res_sample_idx, input$selected_res)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    
    rv$live_selected_config$resolutions[[s_name]] <- as.numeric(input$selected_res)
    
    # Update Global copy for utils and save to disk
    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)
    
    showNotification(paste("Resolution", input$selected_res, "saved for", s_name), type = "message")
    
    total_samples <- length(rv$paths_list$sample_dir_paths)
    if (idx < total_samples) {
      updateSelectInput(session, "res_sample_idx", selected = idx + 1)
    } else {
      showNotification("All samples reviewed! You can now run DE Analysis.", type = "message", duration = 8)
    }
  })
  
  observeEvent(input$btn_rerun_single_de, {
    req(rv$paths_list, input$res_sample_idx)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    
    current_val <- rv$live_selected_config$resolutions[[s_name]]
    
    if (is.null(current_val) || current_val == 0 || current_val == 0.0) {
      showNotification(paste("Cannot run DE! Please save a resolution for", s_name, "first."), type = "error")
    } else {
      showModal(modalDialog(
        title = "Confirm Single Sample DE",
        paste0("Are you sure you want to rerun the Differential Expression analysis for '", s_name, "'? This will lock the application until finished."),
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          actionButton("confirm_run_single_de", "Yes, Rerun DE", class = "btn-danger")
        )
      ))
    }
  })
  
  observeEvent(input$confirm_run_single_de, {
    removeModal()
    req(rv$paths_list, rv$dataset_config, rv$complete_markers)
    idx <- as.numeric(input$res_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    
    id <- showNotification(paste("Running DE analysis for", s_name, "- Check R console..."), duration = NULL, type = "warning")
    
    tryCatch({
      single_de_analysis(
        sample_idx = idx,
        paths_list = rv$paths_list,
        dataset_config = rv$dataset_config,
        selected_config = rv$live_selected_config,
        complete_markers = rv$complete_markers,
        results_dir_path = rv$results_dir_path,
        dataset_dir_path = rv$dataset_dir_path
      )
      showNotification(paste("Differential Expression Analysis complete for", s_name, "!"), type = "message")
    }, error = function(e) {
      showNotification(paste("Error running DE:", e$message), type = "error", duration = 10)
    }, finally = {
      removeNotification(id)
    })
  })
  
  # ================================================================================================
  # MANUAL ANNOTATION LOGIC
  # ================================================================================================
  
  observeEvent(input$btn_anno_next, {
    req(rv$paths_list, input$sample_idx)
    idx <- as.numeric(input$sample_idx)
    total_samples <- length(rv$paths_list$sample_dir_paths)
    if (idx < total_samples) {
      updateSelectInput(session, "sample_idx", selected = idx + 1)
    } else {
      showNotification("This is the last sample in the dataset.", type = "message")
    }
  })
  
  observeEvent(input$btn_cluster_next, {
    req(rv$cells_filt, input$cluster)
    
    clusters <- unique(as.character(rv$cells_filt$clust))
    clusters <- clusters[order(as.numeric(clusters))]
    
    curr_idx <- which(clusters == input$cluster)
    if (length(curr_idx) > 0 && curr_idx < length(clusters)) {
      next_cluster <- clusters[curr_idx + 1]
      updateSelectInput(session, "cluster", selected = next_cluster)
    } else {
      showNotification("This is the last cluster for this sample.", type = "message")
    }
  })
  
  output$anno_status_badge <- renderUI({
    req(rv$sample_name)
    refs <- rv$live_selected_config$cna_ref_cells[[rv$sample_name]]
    pot_mal <- rv$live_selected_config$cna_pot_mal_cells[[rv$sample_name]]
    
    missing_config <- c()
    if (is.null(refs) || length(refs) == 0) missing_config <- c(missing_config, "Refs")
    if (is.null(pot_mal) || length(pot_mal) == 0) missing_config <- c(missing_config, "Malig")
    
    if (length(missing_config) > 0) {
      tags$div(class = "badge bg-warning text-dark w-100 py-2 mt-2", 
               style = "font-size: 14px; white-space: normal;",
               icon("exclamation-circle"), paste(" CNA Config Missing:", paste(missing_config, collapse = ", ")))
    } else {
      tags$div(class = "badge bg-success w-100 py-2 mt-2", 
               style = "font-size: 14px; white-space: normal;",
               icon("check-circle"), paste(" CNA Configured for:", rv$sample_name))
    }
  })
  
  output$ref_cell_selector <- renderUI({
    req(rv$cells_filt, rv$sample_name, rv$samples_config)
    
    current_types <- unique(rv$cells_filt$cell_type)
    current_types <- current_types[!is.na(current_types) & current_types != "NA"]
    current_types <- gsub("\\s*\\(.*\\)", "", current_types) 
    current_types <- unique(current_types)
    
    samples_list <- rv$samples_config$samples
    matching_sample <- Filter(function(x) x$id == rv$sample_name, samples_list)
    
    cancer_type <- "Unknown"
    if (length(matching_sample) > 0) {
      cancer_type <- matching_sample[[1]]$cancer_type
    }
    
    tagList(
      tags$div(
        style = "margin-bottom: 10px; padding: 5px; background-color: #f8f9fa; border-radius: 4px; border: 1px solid #dee2e6;",
        tags$span("Cancer Type: ", style = "font-weight: bold; color: #6c757d;"),
        tags$span(cancer_type, style = "font-weight: bold; color: #2c3e50;")
      ),
      selectizeInput("cna_refs_input", "Select Ref Cell Types:",
                     choices = current_types,
                     selected = rv$live_selected_config$cna_ref_cells[[rv$sample_name]],
                     multiple = TRUE, 
                     options = list(placeholder = 'Select annotated types...'))
    )
  })
  
  output$pot_mal_cell_selector <- renderUI({
    req(rv$cells_filt, rv$sample_name, rv$complete_markers)
    
    # 1. Grab currently annotated cell types
    current_types <- unique(rv$cells_filt$cell_type)
    current_types <- current_types[!is.na(current_types) & current_types != "NA"]
    
    # 2. Grab standard marker cell types
    marker_types <- unique(rv$complete_markers$cell_type)
    
    # 3. Combine and clean
    all_choices <- unique(c(current_types, marker_types))
    all_choices <- gsub("\\s*\\(.*\\)", "", all_choices) 
    all_choices <- unique(all_choices)
    
    selectizeInput("cna_pot_mal_input", "Select Potentially Malig. Types:",
                   choices = all_choices,
                   selected = rv$live_selected_config$cna_pot_mal_cells[[rv$sample_name]],
                   multiple = TRUE, 
                   options = list(create = TRUE, placeholder = 'Select or type new...'))
  })
  
  observeEvent(input$btn_save_refs, {
    req(rv$sample_name)
    
    selected_refs <- input$cna_refs_input
    if (is.null(selected_refs)) selected_refs <- list() 
    
    selected_pot_mal <- input$cna_pot_mal_input
    if (is.null(selected_pot_mal)) selected_pot_mal <- list()
    
    rv$live_selected_config$cna_ref_cells[[rv$sample_name]] <- selected_refs
    rv$live_selected_config$cna_pot_mal_cells[[rv$sample_name]] <- selected_pot_mal
    
    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)
    
    showNotification(paste("CNA Configuration saved for", rv$sample_name), type = "message")
  })
  
  observeEvent(input$sample_idx, {
    req(rv$paths_list, input$sample_idx)
    idx <- as.numeric(input$sample_idx)
    
    cells_file <- rv$paths_list$cell_file_paths[idx]
    if (!file.exists(cells_file)) return()
    
    id <- showNotification("Loading annotation data...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    rv$final_plot <- NULL 
    rv$cells_raw <- load_cells(cells_file)
    rv$sample_name <- unique(rv$cells_raw$sample)
    rv$res <- rv$live_selected_config$resolutions[[rv$sample_name]]
    
    tryCatch({
      results_list <- cell_type_annotation_setup(idx, rv$paths_list, rv$results_dir_path, 
                                                 rv$config, rv$dataset_dir_path, rv$complete_markers,
                                                 dataset_config = rv$dataset_config,
                                                 selected_config = rv$live_selected_config)
      rv$cells_filt <- results_list$cells_filt
      rv$all_matches <- results_list$all_matches
      
      if ("cell_type" %in% names(rv$cells_raw)) {
        rv$cells_filt[rv$cells_raw, on = 'cell_name', cell_type := i.cell_type]
      } else if (!"cell_type" %in% names(rv$cells_filt)) {
        rv$cells_filt[, cell_type := NA_character_]
      }
    }, error = function(e) {
      message("Error loading annotation setup: ", e$message) 
      showNotification("Could not load DE data. Did you run the DE Analysis step?", type = "error")
    })
  })
  
  output$cluster_selector <- renderUI({
    req(rv$cells_filt)
    clusters <- unique(as.character(rv$cells_filt$clust))
    clusters <- clusters[order(as.numeric(clusters))]
    selectInput("cluster", "2. Select Cluster:", choices = clusters)
  })
  
  # Render dynamically based on selected dataset marker filters
  output$cell_type_input_ui <- renderUI({
    req(rv$complete_markers)
    selectizeInput("cell_type_input", "Cell Type:", 
                   choices = c("NA", unique(rv$complete_markers$cell_type)), 
                   options = list(create = TRUE, placeholder = 'Select or type new...'))
  })
  
  output$current_cluster_annotation <- renderUI({
    req(rv$cells_filt, input$cluster)
    curr_anno <- unique(rv$cells_filt[clust == input$cluster]$cell_type)
    curr_anno <- curr_anno[!is.na(curr_anno) & curr_anno != "NA"]
    
    if (length(curr_anno) == 0) {
      tags$div(class = "text-muted mt-1 mb-2", style = "font-size: 14px;", 
               icon("circle-info"), " Current: ", tags$em("Unassigned"))
    } else {
      tags$div(class = "text-primary fw-bold mt-1 mb-2", style = "font-size: 14px;", 
               icon("tag"), paste(" Current:", paste(curr_anno, collapse = ", ")))
    }
  })
  
  output$umap_ref_plot <- renderImage({
    req(rv$sample_name, rv$res, rv$results_dir_path)
    plot_name <- paste0('clusters_plot_', rv$sample_name, '_res_', rv$res, '.png')
    plot_path <- file.path(rv$results_dir_path, rv$sample_name, '1_cluster_plots', plot_name)
    if(!file.exists(plot_path)) return(list(src=""))
    list(src = plot_path, width = "100%", height = "auto", alt = "Pre-computed UMAP")
  }, deleteFile = FALSE)
  
  output$cluster_boxplot <- renderImage({
    req(rv$sample_name, input$cluster, rv$results_dir_path)
    plot_path <- file.path(rv$results_dir_path, rv$sample_name, '2_de_plots', paste0(input$cluster, '.png'))
    if(!file.exists(plot_path)) return(list(src=""))
    list(src = plot_path, width = "100%", height = "auto", alt = "Cluster Boxplot")
  }, deleteFile = FALSE)
  
  output$marker_table <- DT::renderDT({
    req(rv$all_matches, input$cluster)
    dt_subset <- rv$all_matches[clust == input$cluster]
    
    col_name <- ifelse("symbol" %in% names(dt_subset), "symbol", "gene")
    target_col_idx <- which(names(dt_subset) == col_name) - 1
    
    DT::datatable(dt_subset, 
                  extensions = 'Buttons', 
                  class = 'cell-border stripe hover', 
                  options = list(
                    pageLength = 50, 
                    scrollX = TRUE,
                    dom = 'Bplfrtip', 
                    buttons = list(
                      list(
                        extend = 'copy',
                        text = '<i class="fa fa-clipboard"></i> Copy Genes',
                        title = "",   
                        header = FALSE, 
                        exportOptions = list(
                          modifier = list(page = "all"),
                          columns = target_col_idx
                        )
                      )
                    )
                  ), 
                  rownames = FALSE,
                  escape = FALSE)
    
  }, server = FALSE) 
  
  observeEvent(input$assign_btn, {
    req(rv$cells_filt, input$cluster, input$cell_type_input)
    curr_annotation <- ifelse(input$cell_type_input == "NA", NA_character_, input$cell_type_input)
    
    tmp <- data.table::copy(rv$cells_filt)
    tmp[clust == input$cluster, cell_type := curr_annotation]
    rv$cells_filt <- tmp
    
    showNotification(paste0("Assigned '", curr_annotation, "' to cluster ", input$cluster), type = "message")
    
    clusters <- unique(as.character(rv$cells_filt$clust))
    clusters <- clusters[order(as.numeric(clusters))]
    
    curr_idx <- which(clusters == input$cluster)
    
    if (length(curr_idx) > 0 && curr_idx < length(clusters)) {
      next_cluster <- clusters[curr_idx + 1]
      updateSelectInput(session, "cluster", selected = next_cluster)
    } else {
      showNotification("All clusters annotated! You can now preview and save.", type = "message", duration = 5)
    }
  })
  
  observeEvent(input$preview_btn, {
    req(rv$cells_filt, rv$sample_name, rv$res)
    id <- showNotification("Generating preview plot...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    plot_title <- paste0('Cell types of sample: ', rv$sample_name, '; res=', rv$res)
    rv$final_plot <- plot_clusters(rv$cells_filt, plot_title, x_col = umap1, y_col = umap2, cluster_col = cell_type)
    output$final_umap_plot <- renderPlot({ rv$final_plot })
  })
  
  observeEvent(input$save_btn, {
    req(rv$paths_list, rv$cells_filt, rv$cells_raw, rv$sample_name, rv$res, rv$results_dir_path)
    id <- showNotification("Saving annotations and plot to disk...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    idx <- as.numeric(input$sample_idx)
    de_plots_dir_path <- file.path(rv$results_dir_path, rv$sample_name, '2_de_plots')
    
    if (!is.null(rv$final_plot)) {
      clust_plot_path <- file.path(de_plots_dir_path, 'cell_types.png')
      ggplot2::ggsave(clust_plot_path, plot = rv$final_plot, width = 8, height = 6)
    }
    
    # --- NEW FIX: Force memory reallocation with copy() ---
    cells_to_save <- data.table::copy(rv$cells_filt)
    cells_to_save[, cell_type_pre_cna := cell_type]
    
    # 1. Save to raw Cells.csv (Using the safe, copied object)
    rv$cells_raw[cells_to_save, on = 'cell_name', cell_type := i.cell_type]
    rv$cells_raw[cells_to_save, on = 'cell_name', cell_type_pre_cna := i.cell_type_pre_cna]
    data.table::fwrite(rv$cells_raw, file = rv$paths_list$cell_file_paths[idx])
    
    # 2. Sync with the cache
    cells_file <- paste0('cells_filt_clust_res_', rv$res, '_', rv$sample_name, '.qs2')
    cache_save_data(cells_to_save, cells_file, rv$dataset_dir_path)
    
    # Update the active session memory so it doesn't complain later
    rv$cells_filt <- cells_to_save
    
    showNotification("Successfully saved annotations to disk!", type = "default")
  })
  
  # ================================================================================================
  # CNA ANALYSIS LOGIC
  # ================================================================================================
  
  # Populate Sample Dropdown when Dataset Loads
  observe({
    req(rv$paths_list)
    s_choices <- setNames(
      seq_along(rv$paths_list$sample_dir_paths), 
      basename(rv$paths_list$sample_dir_paths)
    )
    updateSelectInput(session, "cna_sample_idx", choices = s_choices)
  })
  
  # Basic Navigation between main views
  observeEvent(input$btn_cna_back_menu, { updateNavbarPage(session, "main_nav", selected = "menu_tab") })
  observeEvent(input$btn_cna_go_malig_clust, { nav_select("cna_main_views", "cna_view_select_malignant") })
  observeEvent(input$btn_cna_go_thresholds, { nav_select("cna_main_views", "cna_view_thresholds") })
  observeEvent(input$btn_cna_go_summary, { nav_select("cna_main_views", "cna_view_summary") })
  
  output$cna_header_text <- renderText({
    req(rv$paths_list, input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    paste("CNA Analysis:", s_name)
  })
  
  # Monitor cache and config to enable/disable pipeline buttons
  observeEvent(input$cna_sample_idx, {
    req(rv$paths_list, input$cna_sample_idx)
    idx <- as.numeric(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    
    # 0. Start by disabling steps 2 through 5 and resetting the view
    nav_select("cna_main_views", "cna_view_default")
    shinyjs::disable("btn_cna_go_malig_clust")
    shinyjs::disable("btn_cna_compute_sig_cor")
    shinyjs::disable("btn_cna_go_thresholds")
    shinyjs::disable("btn_cna_go_summary")
    
    shinyjs::disable("btn_cna_save_summary")
    rv$cna_preview_res <- NULL
    output$cna_preview_scatter_ui <- renderUI({ NULL })
    output$cna_preview_umap <- renderPlot({ NULL })
    output$cna_preview_heatmap <- renderPlot({ NULL })
    
    # We will build an HTML status string to show the user what is done
    status_html <- c("<strong>Pipeline Status:</strong><ul class='list-group mt-2 text-start'>")
    
    # 1. Check if CNA and Heatmaps are computed (Step 1)
    # We look for the hclust cache file as an indicator
    hclust_file <- paste0('hclust_', s_name, '.qs2')
    step1_done <- cache_check_exists(hclust_file, rv$dataset_dir_path)
    
    if (step1_done) {
      shinyjs::enable("btn_cna_go_malig_clust")
      status_html <- c(status_html, "<li class='list-group-item list-group-item-success'>1. Base CNA & Heatmaps: Complete</li>")
    } else {
      status_html <- c(status_html, "<li class='list-group-item list-group-item-warning'>1. Base CNA & Heatmaps: Pending</li>")
    }
    
    # 2. Check if Malignant Clusters are selected (Step 2)
    ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
    step2_done <- step1_done && !is.null(ward_refs) && length(ward_refs) > 0
    
    if (step2_done) {
      shinyjs::enable("btn_cna_compute_sig_cor")
      
      saved_k <- ward_refs[[1]]$k
      saved_clusters <- sapply(ward_refs, function(x) as.character(x$cluster))
      
      updateSliderInput(session, "cna_k_clusters", value = saved_k)
      updateSelectizeInput(session, "cna_selected_clusters", 
                           choices = as.character(1:saved_k),
                           selected = saved_clusters)
      
      status_html <- c(status_html, "<li class='list-group-item list-group-item-success'>2. Cluster Selection: Complete</li>")
    } else {
      updateSelectizeInput(session, "cna_selected_clusters", selected = character(0))
      status_html <- c(status_html, "<li class='list-group-item list-group-item-warning'>2. Cluster Selection: Pending</li>")
    }
    
    # 3. Check if Signal & Cor are computed (Step 3)
    # Check if subclone 1 exists as a baseline
    sig_cor_file <- paste0('cna_sig_cor_', s_name, '_subclone_1.qs2')
    step3_done <- step2_done && cache_check_exists(sig_cor_file, rv$dataset_dir_path)
    
    if (step3_done) {
      shinyjs::enable("btn_cna_go_thresholds")
      status_html <- c(status_html, "<li class='list-group-item list-group-item-success'>3. Signal & Correlation: Complete</li>")
    } else {
      status_html <- c(status_html, "<li class='list-group-item list-group-item-warning'>3. Signal & Correlation: Pending</li>")
    }
    
    # 4. Check if Thresholds are saved (Step 4)
    thresholds <- rv$live_selected_config$cna_thresholds[[s_name]]
    step4_done <- step3_done && !is.null(thresholds) && length(thresholds) > 0
    
    if (step4_done) {
      shinyjs::enable("btn_cna_go_summary")
      
      
      status_html <- c(status_html, "<li class='list-group-item list-group-item-success'>4. Malignant Thresholds: Saved</li>")
    } else {
      status_html <- c(status_html, "<li class='list-group-item list-group-item-warning'>4. Malignant Thresholds: Pending</li>")
    }
    # Step 4 (Thresholds) and 5 (Summary) state logic can be expanded here once we define where 
    # the thresholds are stored (e.g., config file or another qs2 object).
    
    status_html <- c(status_html, "</ul>")
    
    output$cna_status_ui <- renderUI({
      HTML(paste(status_html, collapse = ""))
    })
  })
  
  # Next Sample Button Logic for CNA
  observeEvent(input$btn_cna_next, {
    req(rv$paths_list, input$cna_sample_idx)
    idx <- as.numeric(input$cna_sample_idx)
    total_samples <- length(rv$paths_list$sample_dir_paths)
    
    if (idx < total_samples) {
      updateSelectInput(session, "cna_sample_idx", selected = idx + 1)
    } else {
      showNotification("This is the last sample in the dataset.", type = "message")
    }
  })
  
  # ================================================================================================
  # CNA PIPELINE EXECUTION
  # ================================================================================================
  
  # --- STEP 1: Compute CNA & Heatmaps ---
  observeEvent(input$btn_cna_compute_heatmaps, {
    req(input$cna_sample_idx, rv$paths_list)
    idx <- as.numeric(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[idx]
    
    id <- showNotification("Computing CNA and Heatmaps. Check R console...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    # Load filtered data from cache
    cells_file <- paste0('cells_filt_clust_res_', rv$live_selected_config$resolutions[[s_name]], '_', s_name, '.qs2')
    expmat_file <- paste0('expmat_filt_', s_name, '.qs2')
    
    cells_filt <- cache_load_data(cells_file, rv$dataset_dir_path)
    expmat_filt <- cache_load_data(expmat_file, rv$dataset_dir_path)
    
    # Prepare reference cells
    cells_filt[is.na(cell_type), cell_type := 'Unassigned']
    ref_cells <- cells_filt[cell_type %in% rv$live_selected_config$cna_ref_cells[[s_name]]]
    
    # Compute CNA
    cna_mat_file_name <- paste0('cna_matrix_', s_name, '.qs2')
    if (!cache_check_exists(cna_mat_file_name, rv$dataset_dir_path)) {
      compute_cna_and_cache(expmat_filt, rv$gene_positions, ref_cells, s_name, rv$dataset_dir_path)
    }
    
    # Compute Heatmaps
    cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
    dir.create(cna_plots_dir_path, showWarnings = FALSE)
    
    cna_clustering_and_heatmaps(ref_cells, s_name, rv$live_selected_config, cna_plots_dir_path,
                                rv$dataset_dir_path)
    
    showNotification("CNA and Heatmaps computed successfully!", type = "default")
    shinyjs::enable("btn_cna_go_malig_clust")
    
    # Trigger UI update by moving to the next tab
    nav_select("cna_main_views", "cna_view_select_malignant")
  })
  
  # --- STEP 1b: Batch Compute CNA & Heatmaps ---
  observeEvent(input$btn_cna_batch_compute, {
    req(rv$paths_list)
    showModal(modalDialog(
      title = "Confirm Batch CNA Computation",
      "Are you sure you want to run the CNA and Heatmap pipeline for ALL valid samples? This process takes a significant amount of time and will lock the application.",
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_cna_batch", "Yes, Run Batch", class = "btn-danger")
      )
    ))
  })
  
  observeEvent(input$confirm_cna_batch, {
    removeModal()
    id <- showNotification("Running Batch CNA Computation. Check R console...", duration = NULL, type = "warning")
    
    # Run backend logic
    res <- batch_compute_cna_and_heatmaps(
      paths_list = rv$paths_list,
      dataset_dir_path = rv$dataset_dir_path,
      results_dir_path = rv$results_dir_path,
      selected_config = rv$live_selected_config,
      gene_positions = rv$gene_positions
    )
    
    removeNotification(id)
    
    # Report results to user
    msg <- paste0("Batch Complete!\nProcessed: ", length(res$processed), " samples\nSkipped: ", length(res$skipped), " samples")
    showNotification(msg, type = "message", duration = 15)
    
    # If the currently selected sample in the UI was just processed, unlock Step 2 automatically
    current_s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    if (current_s_name %in% res$processed) {
      shinyjs::enable("btn_cna_go_malig_clust")
      nav_select("cna_main_views", "cna_view_select_malignant")
    }
  })
  
  # --- STEP 2: MALIGNANT CLUSTER SELECTION (CUTREE METHOD) ---
  
  # 1. Update the dropdown choices automatically based on the k-slider
  observeEvent(input$cna_k_clusters, {
    updateSelectizeInput(session, "cna_selected_clusters", choices = as.character(1:input$cna_k_clusters))
  })
  
  # 2. Debounce the slider so it only triggers 800ms AFTER the user stops dragging
  k_debounced <- debounce(reactive({ input$cna_k_clusters }), millis = 800)
  
  # 3. Cache the heavy static plots (Only runs ONCE per sample)
  cna_static_plots <- reactive({
    req(input$cna_sample_idx, rv$paths_list)
    
    # 1. CRITICAL FIX: Get the correct sample name specifically for the CNA tab!
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    
    # 2. ISOLATE the config to completely prevent reactive invalidation loops
    cfg <- isolate(rv$live_selected_config)
    req(cfg)
    
    id <- showNotification("Generating main heatmap (this only happens once per sample)...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    hclust_file_name <- paste0('hclust_', s_name, '.qs2') 
    cells_file_name <- paste0('cells_filt_clust_res_', cfg$resolutions[[s_name]], '_', s_name, '.qs2')
    req(cache_check_exists(hclust_file_name, rv$dataset_dir_path))
    
    clust_hclust <- cache_load_data(hclust_file_name, rv$dataset_dir_path)
    cells_filt <- cache_load_data(cells_file_name, rv$dataset_dir_path)
    
    # Revert to pre-CNA manual annotations before generating the plot
    if ("cell_type_pre_cna" %in% names(cells_filt)) {
      cells_filt[, cell_type := cell_type_pre_cna]
    }
    cells_filt[is.na(cell_type), cell_type := 'Unassigned']
    
    expdt <- load_expdt_from_cna_matrix(s_name, rv$dataset_dir_path)
    
    ref_cells <- cells_filt[cell_type %in% cfg$cna_ref_cells[[s_name]]]
    
    # Safely merge bypassing data.table NSE
    expdt$cell_type <- cells_filt$cell_type[match(expdt$cell_name, cells_filt$cell_name)]
    expdt <- expdt[!is.na(expdt$cell_type)]
    
    chr_n <- expdt[, .(n = length(unique(gene))), keyby = chr][n > 20]
    expdt <- expdt[chr %in% chr_n$chr]
    
    chr_lab <- c('01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12', '14', '16', 
                 '17', '18', '19', '20', '22', 'X')
    chr_lab <- unique(expdt[, .(gene, chr)])[,{
      inds <- chr_n[, floor(cumsum(n) - n/2)[chr %in% chr_lab]]; 
      setNames(gsub('^0', '', chr[inds]), as.character(gene)[inds])
    }]
    
    hdata <- data.table::copy(expdt[cell_type == 'Unassigned' | cell_type %in% cfg$cna_pot_mal_cells[[s_name]]])
    ordered_cells <- clust_hclust$labels[clust_hclust$order]
    hdata[, cell_num_hclust := as.numeric(factor(cell_name, levels = ordered_cells))]
    hdata[, gene := factor(gene, levels = unique(gene))]
    
    hdata_hclust_cells <- with(clust_hclust, data.table::data.table(
      cell_name = labels, cell_num = order(order)
    ))
    
    # Safely merge bypassing data.table NSE
    hdata_hclust_cells$cell_type <- cells_filt$cell_type[match(hdata_hclust_cells$cell_name, cells_filt$cell_name)]
    
    # GENERATE THE HEAVY PLOTS ONCE
    dend_p <- dendrogram_plot(clust_hclust) 
    htmp_p <- cna_heatmap(hdata, ref_cells, chr_n, chr_lab, hdata$cell_num_hclust)
    cell_type_p <- cluster_or_cell_type_bar_plot(hdata_hclust_cells, 'cell_type', 'Cell Type')
    
    # Extract legends BEFORE removing them
    htmp_leg <- cowplot::get_legend(htmp_p)
    cell_type_leg <- cowplot::get_legend(cell_type_p)
    
    # Strip themes and convert to static gtables (grobs)
    remove_leg <- ggplot2::theme(legend.position = "none")
    
    dend_grob <- ggplot2::ggplotGrob(dend_p) 
    htmp_grob <- ggplot2::ggplotGrob(htmp_p + remove_leg)
    cell_type_grob <- ggplot2::ggplotGrob(cell_type_p + remove_leg)
    
    # Return them as a list to be reused
    return(list(
      dend_grob = dend_grob,
      htmp_grob = htmp_grob,
      cell_type_grob = cell_type_grob,
      htmp_leg = htmp_leg,
      cell_type_leg = cell_type_leg,
      hdata_cells = hdata_hclust_cells,
      hc = clust_hclust
    ))
  })
  
  # 4. Fast Plot Renderer (Only triggers when the debounced slider updates)
  output$cna_combined_heatmap_plot <- renderPlot({
    # Use the debounced value instead of the raw input!
    k_val <- k_debounced() 
    req(k_val)
    
    # Grab the pre-computed static plots
    static <- cna_static_plots()
    req(static)
    
    # 1. Cut the tree instantly
    cell_clusters <- cutree(static$hc, k = k_val)
    
    # 2. Update the cluster assignments
    # We MUST use copy() here so we don't permanently modify the cached reactive data
    hdata_cells_k <- data.table::copy(static$hdata_cells)
    hdata_cells_k[, k_cluster := as.character(cell_clusters[cell_name])]
    
    # 3. Build only the NEW k-cluster bar (takes < 0.1 seconds)
    k_colors <- viridis::viridis(k_val, option = "turbo")
    names(k_colors) <- as.character(1:k_val)
    
    clust_p <- cluster_or_cell_type_bar_plot(hdata_cells_k, "k_cluster", "Cluster (k)", custom_colors = k_colors)
    
    # 4. Extract its legend and convert to grob
    clust_leg <- cowplot::get_legend(clust_p)
    remove_leg <- ggplot2::theme(legend.position = "none")
    clust_grob <- ggplot2::ggplotGrob(clust_p + remove_leg)
    
    # 5. Stack legends vertically
    stacked_legends <- cowplot::plot_grid(
      static$cell_type_leg,
      clust_leg,
      static$htmp_leg,
      ncol = 1, align = "v"
    )
    
    # 6. Assemble the final plot using the cached grobs!
    cowplot::plot_grid(
      static$dend_grob, 
      static$cell_type_grob, 
      clust_grob, 
      static$htmp_grob, 
      stacked_legends,
      nrow = 1, align = 'h', axis = 'tb',
      rel_widths = c(0.20, 0.03, 0.03, 1, 0.15)
    )
  })
  
  # 5. Save Selection 
  observeEvent(input$btn_cna_save_malignant, {
    # 1. Provide an explicit, visible warning if no clusters are selected
    if (is.null(input$cna_selected_clusters) || length(input$cna_selected_clusters) == 0) {
      showNotification("Please select at least one Malignant Subclone from the dropdown before saving.", 
                       type = "warning", duration = 5)
      return()
    }
    
    # 2. Make sure the dataset variables are available
    req(input$cna_sample_idx, input$cna_k_clusters, rv$paths_list, rv$live_selected_config)
    
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    
    # 3. Save as a structured, named list for the backend
    subclones <- lapply(input$cna_selected_clusters, function(cl) {
      list(method = 'cutree', k = as.numeric(input$cna_k_clusters), cluster = as.numeric(cl))
    })
    
    rv$live_selected_config$cna_ward_ref_cluster[[s_name]] <- subclones
    # --- NEW CLEANUP LOGIC ---
    # 1. Clear old thresholds from the active config to prevent UI mismatches
    rv$live_selected_config$cna_thresholds[[s_name]] <- NULL
    
    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)
    
    # 2. Delete old subclone plots
    cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
    if (dir.exists(cna_plots_dir_path)) {
      old_plots <- list.files(cna_plots_dir_path, 
                              pattern = paste0("subclone_.*_", s_name, "\\.png$"), 
                              full.names = TRUE)
      if (length(old_plots) > 0) file.remove(old_plots)
    }
    
    # 3. Delete old subclone cache files
    cache_dir <- file.path(rv$dataset_dir_path, "cache")
    old_cache <- list.files(cache_dir, 
                            pattern = paste0("^cna_sig_cor_", s_name, "_subclone_.*\\.qs2$"), 
                            full.names = TRUE)
    if (length(old_cache) > 0) file.remove(old_cache)
    # -------------------------
    
    id_plot <- showNotification("Saving k-clusters plot to disk...", duration = NULL, type = "message")
    
    # Define k_val right here so it is always available to cutree()
    k_val <- as.numeric(input$cna_k_clusters)
    
    # Grab the cached static grobs and rebuild the exact plot from the UI
    static <- isolate(cna_static_plots())
    if (!is.null(static)) {
      cell_clusters <- cutree(static$hc, k = k_val)
      hdata_cells_k <- data.table::copy(static$hdata_cells)
      hdata_cells_k[, k_cluster := as.character(cell_clusters[cell_name])]
      
      k_colors <- viridis::viridis(k_val, option = "turbo")
      names(k_colors) <- as.character(1:k_val)
      
      clust_p <- cluster_or_cell_type_bar_plot(hdata_cells_k, "k_cluster", "Cluster (k)", custom_colors = k_colors)
      clust_leg <- cowplot::get_legend(clust_p)
      remove_leg <- ggplot2::theme(legend.position = "none")
      clust_grob <- ggplot2::ggplotGrob(clust_p + remove_leg)
      
      stacked_legends <- cowplot::plot_grid(
        static$cell_type_leg,
        clust_leg,
        static$htmp_leg,
        ncol = 1, align = "v"
      )
      
      final_plot <- cowplot::plot_grid(
        static$dend_grob, 
        static$cell_type_grob, 
        clust_grob, 
        static$htmp_grob, 
        stacked_legends,
        nrow = 1, align = 'h', axis = 'tb',
        rel_widths = c(0.20, 0.03, 0.03, 1, 0.15)
      )
      
      cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
      dir.create(cna_plots_dir_path, showWarnings = FALSE, recursive = TRUE)
      
      plot_path <- file.path(cna_plots_dir_path, paste0('hclust_k_', k_val, '_clusters_', s_name, '.png'))
      ggplot2::ggsave(plot_path, plot = final_plot, width = 300, height = 400, units = 'mm', bg = "white")
    }
    removeNotification(id_plot)
    
    showNotification("Malignant clusters saved! Ready to compute signal/correlation.", type = "message")
    
    # 4. Enable Step 3 computation button (make sure this ID matches your actual UI button for Step 3!)
    shinyjs::enable("btn_cna_compute_sig_cor")
  })
  
  # --- STEP 3: Compute Signal & Correlation ---
  observeEvent(input$btn_cna_compute_sig_cor, {
    req(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    
    id <- showNotification("Computing Signal and Correlation...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    cells_file <- paste0('cells_filt_clust_res_', rv$live_selected_config$resolutions[[s_name]], '_', s_name, '.qs2')
    cells_filt <- cache_load_data(cells_file, rv$dataset_dir_path)
    cells_filt[is.na(cell_type), cell_type := 'Unassigned']
    ref_cells <- cells_filt[cell_type %in% rv$live_selected_config$cna_ref_cells[[s_name]]]
    
    ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
    for (i in seq_along(ward_refs)) {
      compute_signal_cor_cna(s_name, i, ref_cells, rv$live_selected_config, rv$dataset_dir_path)
    }
    
    showNotification("Signal and Correlation computed!", type = "default")
    shinyjs::enable("btn_cna_go_thresholds")
    nav_select("cna_main_views", "cna_view_thresholds")
  })
  
  # --- STEP 4: Render Dynamic Threshold UI & Plots ---
  
  # 1. Dynamically generate the UI (Tabs + Sliders + Plot Output)
  output$cna_dynamic_thresholds_ui <- renderUI({
    req(input$cna_sample_idx, rv$paths_list, rv$live_selected_config)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
    
    if (length(ward_refs) == 0) return(h5("No malignant clusters selected yet.", class = "text-danger"))
    
    # Check if thresholds already exist in config to pre-fill sliders
    existing_thresh <- rv$live_selected_config$cna_thresholds[[s_name]]
    
    # Generate a UI tab for each subclone
    tabs <- lapply(seq_along(ward_refs), function(i) {
      
      def_ymax <- if(length(existing_thresh) >= i && !is.null(existing_thresh[[i]]$y_max)) existing_thresh[[i]]$y_max else 1.0
      # Determine default slider values (prefill if saved, otherwise default)
      def_mx <- if(length(existing_thresh) >= i && !is.null(existing_thresh[[i]]$m_x)) existing_thresh[[i]]$m_x else 0.5
      def_my <- if(length(existing_thresh) >= i && !is.null(existing_thresh[[i]]$m_y)) existing_thresh[[i]]$m_y else 0.16
      def_nmx <- if(length(existing_thresh) >= i && !is.null(existing_thresh[[i]]$nm_x)) existing_thresh[[i]]$nm_x else 0.3
      def_nmy <- if(length(existing_thresh) >= i && !is.null(existing_thresh[[i]]$nm_y)) existing_thresh[[i]]$nm_y else 0.15
      
      nav_panel(
        title = paste("Subclone", i),
        fluidRow(
          column(8, plotOutput(paste0("cna_sig_cor_plot_", i), height = "500px")),
          column(4,
                 card(
                   card_header(paste("Set Thresholds - Subclone", i)),
                   card_body(
                     selectInput(paste0("cna_step_size_", i), "Y-Axis Precision:", 
                                 choices = c("0.05" = 0.05, "0.01" = 0.01, "0.005" = 0.005, "0.001" = 0.001), selected = "0.01"),
                     sliderInput(paste0("cna_ymax_", i), "Y-Axis Max Limit:", min = 0.1, max = 3.0, value = def_ymax, step = 0.1),
                     hr(),
                     sliderInput(paste0("cna_thresh_mx_", i), "Malignant X (m_x):", min = -1, max = 1, value = def_mx, step = 0.05),
                     sliderInput(paste0("cna_thresh_my_", i), "Malignant Y (m_y):", min = 0, max = 1, value = def_my, step = 0.01),
                     sliderInput(paste0("cna_thresh_nmx_", i), "Non-Malignant X (nm_x):", min = -1, max = 1, value = def_nmx, step = 0.05),
                     sliderInput(paste0("cna_thresh_nmy_", i), "Non-Malignant Y (nm_y):", min = 0, max = 1, value = def_nmy, step = 0.01)
                   )
                 )
          )
        )
      )
    })
    
    # Wrap tabs and add the unified save button at the bottom
    tagList(
      do.call(navset_card_underline, tabs),
      br(),
      actionButton("btn_cna_save_thresholds", "Save All Thresholds", class = "btn-success btn-lg w-100")
    )
  })
  
  # 2. Dynamically render the plots for each subclone
  observe({
    req(input$cna_sample_idx, rv$paths_list, rv$live_selected_config)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
    
    if (length(ward_refs) > 0) {
      lapply(seq_along(ward_refs), function(i) {
        output[[paste0("cna_sig_cor_plot_", i)]] <- renderPlot({
          # React to the dynamically generated sliders
          mx <- input[[paste0("cna_thresh_mx_", i)]]
          my <- input[[paste0("cna_thresh_my_", i)]]
          nmx <- input[[paste0("cna_thresh_nmx_", i)]]
          nmy <- input[[paste0("cna_thresh_nmy_", i)]]
          ymax <- input[[paste0("cna_ymax_", i)]] # --- NEW: Capture y_max input ---
          
          # Only render if sliders have initialized (added ymax check)
          req(!is.null(mx), !is.null(my), !is.null(nmx), !is.null(nmy), !is.null(ymax))
          
          sig_cor_file <- paste0('cna_sig_cor_', s_name, '_subclone_', i, '.qs2')
          if (!cache_check_exists(sig_cor_file, rv$dataset_dir_path)) return(NULL)
          
          cna_sig_cor <- cache_load_data(sig_cor_file, rv$dataset_dir_path)
          
          malig_thresh <- list()
          malig_thresh[[s_name]] <- list(c(m_x = mx, m_y = my, nm_x = nmx, nm_y = nmy))
          
          # --- NEW: Pass ymax to the plotting function ---
          p <- cna_sig_cor_plot(cna_sig_cor, s_name, malig_thresh, y_max = ymax)
          
          k_val <- ward_refs[[i]]$k
          c_id <- ward_refs[[i]]$cluster
          
          p + ggplot2::labs(
            title = paste0(s_name, " - Subclone ", i),
            subtitle = paste0("Source: k-clusters (k=", k_val, "), Cluster ID: ", c_id)
          )
        })
      })
    }
  })
  
  lapply(1:15, function(i) {
    
    # Update slider precision when dropdown changes
    observeEvent(input[[paste0("cna_step_size_", i)]], {
      req(input[[paste0("cna_step_size_", i)]])
      step_val <- as.numeric(input[[paste0("cna_step_size_", i)]])
      updateSliderInput(session, paste0("cna_thresh_my_", i), step = step_val)
      updateSliderInput(session, paste0("cna_thresh_nmy_", i), step = step_val)
    })
    
    # --- X-Axis Thresholds (Step size: 0.05) ---
    
    # As Non-Malignant X moves, push the floor of Malignant X up
    observeEvent(input[[paste0("cna_thresh_nmx_", i)]], {
      req(input[[paste0("cna_thresh_nmx_", i)]])
      updateSliderInput(session, paste0("cna_thresh_mx_", i), 
                        min = input[[paste0("cna_thresh_nmx_", i)]] + 0.05)
    })
    
    # As Malignant X moves, push the ceiling of Non-Malignant X down
    observeEvent(input[[paste0("cna_thresh_mx_", i)]], {
      req(input[[paste0("cna_thresh_mx_", i)]])
      updateSliderInput(session, paste0("cna_thresh_nmx_", i), 
                        max = input[[paste0("cna_thresh_mx_", i)]] - 0.05)
    })
    
    # --- Y-Axis Thresholds ---
    
    # As Non-Malignant Y moves, push the floor of Malignant Y up
    observeEvent(input[[paste0("cna_thresh_nmy_", i)]], {
      req(input[[paste0("cna_thresh_nmy_", i)]], input[[paste0("cna_step_size_", i)]])
      step_val <- as.numeric(input[[paste0("cna_step_size_", i)]])
      updateSliderInput(session, paste0("cna_thresh_my_", i), 
                        min = input[[paste0("cna_thresh_nmy_", i)]] + step_val)
    })
    
    # As Malignant Y moves, push the ceiling of Non-Malignant Y down
    observeEvent(input[[paste0("cna_thresh_my_", i)]], {
      req(input[[paste0("cna_thresh_my_", i)]], input[[paste0("cna_step_size_", i)]])
      step_val <- as.numeric(input[[paste0("cna_step_size_", i)]])
      updateSliderInput(session, paste0("cna_thresh_nmy_", i), 
                        max = input[[paste0("cna_thresh_my_", i)]] - step_val)
    })
  })
  
  # 3. Save all dynamic thresholds to config AND save plots
  observeEvent(input$btn_cna_save_thresholds, {
    req(input$cna_sample_idx, rv$paths_list)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    ward_refs <- rv$live_selected_config$cna_ward_ref_cluster[[s_name]]
    n_subclones <- length(ward_refs)
    
    thresh_list <- list()
    has_error <- FALSE
    
    for (i in seq_len(n_subclones)) {
      m_x <- input[[paste0("cna_thresh_mx_", i)]]
      m_y <- input[[paste0("cna_thresh_my_", i)]]
      nm_x <- input[[paste0("cna_thresh_nmx_", i)]]
      nm_y <- input[[paste0("cna_thresh_nmy_", i)]]
      
      # Safety Check
      if (is.null(m_x) || m_x < nm_x || m_y < nm_y) {
        showNotification(paste("Error in Subclone", i, ": Malignant thresholds (m_x, m_y) must be >= Non-Malignant thresholds (nm_x, nm_y)."), 
                         type = "error", duration = 8)
        has_error <- TRUE
      }
      
      y_max <- input[[paste0("cna_ymax_", i)]]
      thresh_list[[i]] <- list(m_x = m_x, m_y = m_y, nm_x = nm_x, nm_y = nm_y, y_max = y_max)
    }
    
    if (has_error) return()
    
    id <- showNotification("Saving thresholds and plots to disk...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    # --- 1. Save Config ---
    rv$live_selected_config$cna_thresholds[[s_name]] <- thresh_list
    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)
    
    # --- 2. Save Plots ---
    cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
    dir.create(cna_plots_dir_path, showWarnings = FALSE, recursive = TRUE)
    
    for (i in seq_len(n_subclones)) {
      sig_cor_file <- paste0('cna_sig_cor_', s_name, '_subclone_', i, '.qs2')
      if (cache_check_exists(sig_cor_file, rv$dataset_dir_path)) {
        cna_sig_cor <- cache_load_data(sig_cor_file, rv$dataset_dir_path)
        
        malig_thresh <- list()
        malig_thresh[[s_name]] <- list(thresh_list[[i]])
        
        # Generate the plot exactly as it looks in the UI
        p_unscaled <- cna_sig_cor_plot(cna_sig_cor, s_name, malig_thresh, y_max = NULL)
        p_scaled <- cna_sig_cor_plot(cna_sig_cor, s_name, malig_thresh, y_max = y_max)
        
        k_val <- ward_refs[[i]]$k
        c_id <- ward_refs[[i]]$cluster
        
        p_unscaled <- p_unscaled + ggplot2::labs(
          title = paste0(s_name, " - Subclone ", i),
          subtitle = paste0("Source: k-clusters (k=", k_val, "), Cluster ID: ", c_id, " | Threshold Selection | Unscaled")
        )
        
        p_scaled <- p_scaled + ggplot2::labs(
          title = paste0(s_name, " - Subclone ", i),
          subtitle = paste0("Source: k-clusters (k=", k_val, "), Cluster ID: ", c_id, " | Threshold Selection | Scaled to ", y_max)
        )
        
        plot_unscaled_title <- paste0('cna_threshold_unscaled_selection_subclone_', i, '_', s_name, '.png')
        plot_unscaled_path <- file.path(cna_plots_dir_path, plot_unscaled_title)
        ggplot2::ggsave(plot_unscaled_path, plot = p_unscaled, width = 7, height = 5, bg = 'white')
        
        plot_scaled_title <- paste0('cna_threshold_scaled_selection_subclone_', i, '_', s_name, '.png')
        plot_scaled_path <- file.path(cna_plots_dir_path, plot_scaled_title)
        ggplot2::ggsave(plot_scaled_path, plot = p_scaled, width = 7, height = 5, bg = 'white')
        
      }
    }
    
    showNotification("All thresholds and plots saved successfully!", type = "message")
    
    # Enable the final step and switch view
    shinyjs::enable("btn_cna_go_summary")
    nav_select("cna_main_views", "cna_view_summary")
  })
  
  
  # --- STEP 5: PREVIEW ASSIGNMENTS & SUMMARY ---
  observeEvent(input$btn_cna_preview_summary, {
    req(input$cna_sample_idx)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    
    id <- showNotification("Generating previews. Please wait...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    # Store preview results in rv so we can save them later without recomputing
    rv$cna_preview_res <- preview_cna_summary(
      sample_name = s_name, 
      dataset_dir_path = rv$dataset_dir_path, 
      selected_config = rv$live_selected_config
    )
    
    # 1. Render Scatter Plots dynamically (Side-by-side: Original vs New)
    output$cna_preview_scatter_ui <- renderUI({
      plot_output_list <- lapply(seq_along(rv$cna_preview_res$pre_scatter_plots), function(i) {
        pre_name <- paste0("cna_preview_scatter_pre_", i)
        post_name <- paste0("cna_preview_scatter_post_", i)
        
        fluidRow(
          column(12, h4(paste("Subclone", i, "Comparisons"), class = "mt-3 text-center fw-bold")),
          column(6, plotOutput(pre_name, height = "450px")),
          column(6, plotOutput(post_name, height = "450px")),
          column(12, hr())
        )
      })
      do.call(tagList, plot_output_list)
    })
    
    # Wire the specific renderPlot functions for both lists
    lapply(seq_along(rv$cna_preview_res$pre_scatter_plots), function(i) {
      local({
        local_i <- i
        
        output[[paste0("cna_preview_scatter_pre_", local_i)]] <- renderPlot({
          # Silently halt if this plot index no longer exists in the new data
          req(local_i <= length(rv$cna_preview_res$pre_scatter_plots))
          rv$cna_preview_res$pre_scatter_plots[[local_i]]
        })
        
        output[[paste0("cna_preview_scatter_post_", local_i)]] <- renderPlot({
          # Silently halt if this plot index no longer exists in the new data
          req(local_i <= length(rv$cna_preview_res$post_scatter_plots))
          rv$cna_preview_res$post_scatter_plots[[local_i]]
        })
      })
    })
    
    # 2. Render UMAP Plot
    output$cna_preview_umap <- renderPlot({ rv$cna_preview_res$umap_plot })
    
    # 3. Render Summary Heatmap
    output$cna_preview_heatmap <- renderPlot({ rv$cna_preview_res$summary_heatmap })
    
    # Enable the finalization button
    shinyjs::enable("btn_cna_save_summary")
  })
  
  
  # --- STEP 6: FINALIZE & SAVE ---
  observeEvent(input$btn_cna_save_summary, {
    req(input$cna_sample_idx, rv$cna_preview_res)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    
    id <- showNotification("Saving cell assignments and plots to disk...", duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    # NEW: Create a copy of the preview data and revert 'Unassigned' back to standard NA
    cells_to_save <- data.table::copy(rv$cna_preview_res$cells_filt)
    cells_to_save[cell_type == 'Unassigned', cell_type := NA_character_]
    
    # 1. Save updated cell labels to cache
    cells_file <- paste0('cells_filt_clust_res_', rv$live_selected_config$resolutions[[s_name]], '_', s_name, '.qs2')
    cache_save_data(cells_to_save, cells_file, rv$dataset_dir_path)
    
    # 2. Sync with the raw Cells.csv so Manual Annotation sees these updates
    cells_raw_path <- rv$paths_list$cell_file_paths[as.numeric(input$cna_sample_idx)]
    cells_raw <- load_cells(cells_raw_path)
    
    # Force the subclone column to integer to prevent logical coercion warnings
    if ("subclone" %in% names(cells_raw)) {
      cells_raw[, subclone := as.integer(subclone)]
    }
    
    cells_raw[cells_to_save, on = 'cell_name', 
              c('cell_type', 'subclone') := .(i.cell_type, i.subclone)]
    fwrite(cells_raw, file = cells_raw_path)
    
    # 3. Save Plots
    cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
    
    # Save Heatmap
    ggplot2::ggsave(file.path(cna_plots_dir_path, paste0('cna_summary_heatmap_', s_name, '.png')), 
                    plot = rv$cna_preview_res$summary_heatmap, width = 300, height = 400, units = 'mm', 
                    dpi = 300, bg = "white")
    
    # Save UMAP
    ggplot2::ggsave(file.path(cna_plots_dir_path, paste0('cna_umap_assigned_', s_name, '.png')), 
                    plot = rv$cna_preview_res$umap_plot, width = 300, height = 400, units = 'mm', bg = "white")
    
    # Save Scatter Plots (Pre and Post)
    for (i in seq_along(rv$cna_preview_res$pre_scatter_plots)) {
      ggplot2::ggsave(file.path(cna_plots_dir_path, paste0('cna_assignments_subclone_', i, '_original_', s_name, '.png')), 
                      plot = rv$cna_preview_res$pre_scatter_plots[[i]], width = 7, height = 5, bg = "white")
      
      ggplot2::ggsave(file.path(cna_plots_dir_path, paste0('cna_assignments_subclone_', i, '_final_', s_name, '.png')), 
                      plot = rv$cna_preview_res$post_scatter_plots[[i]], width = 7, height = 5, bg = "white")
    }
    
    showNotification("CNA Analysis Complete! Results saved successfully.", type = "default")
    
    # Force the dropdown observer to re-evaluate and update the status menu
    shinyjs::runjs(paste0("$('#cna_sample_idx').trigger('change');"))
  })
  
  # --- STEP 7: RESET SAMPLE CNA ---
  observeEvent(input$btn_cna_reset, {
    req(input$cna_sample_idx, rv$paths_list)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    
    showModal(modalDialog(
      title = "Confirm CNA Reset",
      paste("Are you sure you want to reset the CNA analysis for '", s_name, "'? This will delete the cached CNA matrix, clustering, and thresholds. It will also revert any assigned malignant cells back to their manual annotations."),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_cna_reset", "Yes, Reset", class = "btn-danger")
      )
    ))
  })
  
  observeEvent(input$confirm_cna_reset, {
    removeModal()
    req(input$cna_sample_idx, rv$paths_list, rv$live_selected_config)
    s_name <- basename(rv$paths_list$sample_dir_paths)[as.numeric(input$cna_sample_idx)]
    
    id <- showNotification(paste("Resetting CNA pipeline for", s_name, "..."), duration = NULL, type = "message")
    on.exit(removeNotification(id), add = TRUE)
    
    # 1. Clear Configuration
    rv$live_selected_config$cna_ward_ref_cluster[[s_name]] <- NULL
    rv$live_selected_config$cna_thresholds[[s_name]] <- NULL
    
    rv$config$selected <- rv$live_selected_config
    yaml::write_yaml(rv$live_selected_config, rv$selected_config_path)
    
    # 2. Delete Cached Files
    cache_dir <- setup_cache_dir(rv$dataset_dir_path)
    
    files_to_delete <- c(
      file.path(cache_dir, paste0('cna_matrix_', s_name, '.qs2')),
      file.path(cache_dir, paste0('hclust_', s_name, '.qs2'))
    )
    
    # Find all dynamic subclone signal/cor files
    sig_cor_files <- list.files(cache_dir, pattern = paste0('^cna_sig_cor_', s_name, '_subclone_.*\\.qs2$'), full.names = TRUE)
    files_to_delete <- c(files_to_delete, sig_cor_files)
    
    existing <- files_to_delete[file.exists(files_to_delete)]
    ok <- file.remove(existing)
    if (!all(ok)) {
      warning('Could not delete: ', paste(existing[!ok], collapse = ', '),
              ' — file may be locked. Close any programs/previews touching the cache folder and retry.')
    }
    
    # 3. Delete Plots
    cna_plots_dir_path <- file.path(rv$results_dir_path, s_name, '3_cna_plots')
    if (dir.exists(cna_plots_dir_path)) {
      unlink(cna_plots_dir_path, recursive = TRUE)
    }
    
    # 4. Revert Cell Assignments (if Step 5 was saved previously)
    cells_file <- paste0('cells_filt_clust_res_', rv$live_selected_config$resolutions[[s_name]], '_', s_name, '.qs2')
    if (cache_check_exists(cells_file, rv$dataset_dir_path)) {
      cells_filt <- cache_load_data(cells_file, rv$dataset_dir_path)
      
      # If cell_type_pre_cna exists, restore it so we don't lose manual annotations
      if ("cell_type_pre_cna" %in% names(cells_filt)) {
        cells_filt[, cell_type := cell_type_pre_cna]
        cells_filt[, subclone := NA_integer_]
        cache_save_data(cells_filt, cells_file, rv$dataset_dir_path)
      }
    }
    
    # Revert the raw CSV as well
    cells_raw_path <- rv$paths_list$cell_file_paths[as.numeric(input$cna_sample_idx)]
    if (file.exists(cells_raw_path)) {
      cells_raw <- data.table::fread(cells_raw_path)
      if ("cell_type_pre_cna" %in% names(cells_raw)) {
        cells_raw[, cell_type := cell_type_pre_cna]
        cells_raw[, subclone := NA_integer_]
        data.table::fwrite(cells_raw, file = cells_raw_path)
      }
    }
    
    # 5. Refresh UI
    showNotification("Sample CNA reset successfully.", type = "default")
    
    # Force the main panel back to the default pipeline status view
    nav_select("cna_main_views", "cna_view_default")
    
    # Force Shiny to re-trigger the sample selection observer (even though the value hasn't changed)
    shinyjs::runjs("Shiny.setInputValue('cna_sample_idx', $('#cna_sample_idx').val(), {priority: 'event'});")
  })
  
}

shinyApp(ui = ui, server = server)