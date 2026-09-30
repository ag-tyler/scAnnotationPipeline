# scRNA-seq Annotation Pipeline

A Shiny application for standardizing, clustering, differential-expression analysis, manual cell-type annotation, and copy-number alteration (CNA) analysis of single-cell RNA-seq cancer datasets.

The app walks a dataset through:

1.  **Standardization** (Quarto template) – convert raw data into a strict per-sample format.
2.  **Clustering** – PCA → UMAP → Louvain clustering across several resolutions.
3.  **Resolution selection** – choose the clustering resolution to use for each sample.
4.  **Differential expression (DE)** – rank genes per cluster and compare them with known marker sets.
5.  **Manual annotation** – assign cell types to clusters using DE marker matches and signature scores.
6.  **CNA analysis** – infer copy-number alterations and classify malignant cells and subclones.

------------------------------------------------------------------------

## Table of Contents

-   [Requirements](#requirements)
-   [Repository Structure](#repository-structure)
-   [Installation](#installation)
-   [Configuration](#configuration)
    -   [`general_config.yaml`](#general_configyaml)
-   [Resource Files](#resource-files)
-   [Setting Up a New Dataset](#setting-up-a-new-dataset)
-   [Standardization Pipeline](#standardization-pipeline)
-   [Running the App](#running-the-app)
-   [Testing](#testing)
    -   [Running the tests](#running-the-tests)
    -   [Test structure](#test-structure)
    -   [Coverage summary](#coverage-summary)
    -   [Golden fixtures](#golden-fixtures)
-   [Pipeline Assumptions](#pipeline-assumptions)
-   [Best Practices & Cache Invalidation](#best-practices--cache-invalidation)
-   [Known Limitations](#known-limitations)

------------------------------------------------------------------------

## Requirements {#requirements}

-   **R** ≥ 4.5.2 (developed/tested against this version)
-   **Quarto** for the `standardize_10x.qmd` / `standardize_undefined.qmd` templates. Install it from [quarto.org](https://quarto.org/docs/get-started/), or run the template chunks interactively in RStudio without rendering.
-   The required R packages:

``` r
install.packages(c(
  "shiny", "bslib", "shinyjs", "data.table", "yaml", "jsonlite", "DT",
  "ggplot2", "cowplot", "viridis", "Matrix", "irlba", "uwot", "Seurat",
  "stringr", "caTools", "RColorBrewer", "scales", "dbscan", "ggdendro",
  "randomcoloR", "docstring", "qs2", "magrittr", "devtools"
))
```

The pipeline also depends on the custom `matkot` package:

``` r
devtools::install_github("m20ty/matkot")
```

`matkot` provides several helper functions used throughout the pipeline, including `col_nnz`, `to_frac`, `log_transform`, and `sig_score`.

For development and testing, also install:

``` r
install.packages(c("testthat", "withr"))
```

`DESCRIPTION` declares `testthat` and `withr` as test/development dependencies.

The application itself is run directly with:

``` r
shiny::runApp(".")
```

It is not intended to be installed and used as a conventional R package.

------------------------------------------------------------------------

## Repository Structure {#repository-structure}

``` text
scAnnotationPipeline/
├── app.R                              # Main Shiny application
├── .gitignore
├── general_config.yaml                # Shared application configuration
├── DESCRIPTION
├── README.md
│
├── resources/
│   ├── metadata_extract_prompt.txt    # tracked
│   ├── hgnc_complete_set.txt          # NOT tracked
│   ├── gene_positions_biomaRt_0626.csv
│   ├── global_cell_type_markers.csv
│   ├── malignant_markers.csv
│   ├── housekeeping_genes.txt
│   ├── mt_genes.txt
│   └── cancer_cell_map.json
│
├── datasets/                          # local runtime data; gitignored
│   └── <dataset_id>/
│       ├── dataset_config.yaml
│       ├── samples_config.yaml
│       ├── selected_config.yaml
│       ├── standardize.qmd
│       ├── cache/
│       ├── data/
│       ├── processed_data/
│       └── results/
│
├── templates/
│   ├── dataset_config_template.yaml
│   ├── standardize_10x.qmd
│   └── standardize_undefined.qmd
│
├── util_scripts/
│   ├── 01_utils_io.R
│   ├── 02_utils_annotation.R
│   ├── 03_utils_misc.R
│   ├── 04_utils_caching.R
│   └── 05_utils_workflow.R
│
└── tests/
    ├── testthat.R
    └── testthat/
        ├── helper-source.R
        ├── helper-fixtures.R
        ├── test-01_utils_io.R
        ├── test-02_utils_annotation.R
        ├── test-02_utils_annotation_de.R
        ├── test-02_utils_annotation_cna.R
        ├── test-03_utils_misc.R
        ├── test-04_utils_caching.R
        ├── test-05_utils_workflow.R
        ├── test-05_utils_workflow_clustering.R
        ├── test-05_utils_workflow_cna.R
        ├── test-golden_outputs.R
        ├── test-regression_clustering.R
        ├── test-regression_cna_cache.R
        └── fixtures/
            ├── compute_cna_golden.rds
            └── generate_golden_fixtures.R
```

The application directory is the root of the entire setup. `app.R`, `general_config.yaml`, `resources/`, `datasets/`, `templates/`, and `util_scripts/` are all expected relative to this root.

The `resources/` folder is part of the repository structure. Only `metadata_extract_prompt.txt` is currently tracked. The remaining biological resource files must be added locally and are excluded from Git.

The `datasets/` directory also lives inside the application root, but its contents are local runtime data and should remain gitignored. `app.R` creates the directory automatically if it does not yet exist.

`app.R` expects `templates/dataset_config_template.yaml` and `templates/standardize_<technology>.qmd` at exactly those relative paths when a new dataset is created.

Everything in `util_scripts/` is sourced automatically at startup. New utility scripts can therefore be added as additional `.R` files without adding explicit `source()` calls to `app.R`.

### Dataset layout

Each dataset lives under:

``` text
datasets/<dataset_id>/
```

A dataset is expected to have the following structure:

``` text
datasets/<dataset_id>/
├── dataset_config.yaml
├── samples_config.yaml
├── selected_config.yaml
├── standardize.qmd
├── cache/
├── data/
├── processed_data/
│   └── <sample_name>/
│       ├── Exp_data_UMIcounts.mtx
│       ├── Genes.txt
│       └── Cells.csv
└── results/
    └── <sample_name>/
        ├── 1_cluster_plots/
        ├── 2_de_plots/
        └── 3_cna_plots/
```

The exact expression-matrix filename depends on `std_names.expmat` in the dataset configuration. For example, a raw UMI-count matrix may be stored as:

``` text
Exp_data_UMIcounts.mtx
```

The **Create New Dataset** function initializes the dataset directory and its standard subdirectories, creates the three YAML configuration files, and copies the matching standardization template to the dataset as `standardize.qmd`.

------------------------------------------------------------------------

## Installation {#installation}

1.  Clone the repository:

``` bash
git clone <your-repo-url>
cd <repo-folder>
```

2.  Install R ≥ 4.5.2, Quarto, and the R packages listed under [Requirements](#requirements).

3.  Add the required untracked [resource files](#resource-files) to the existing `resources/` directory.

4.  Launch the app from the repository root:

``` r
shiny::runApp(".")
```

No machine-specific application path configuration is required. The app uses the repository root as its working root, with:

``` text
resources/
datasets/
templates/
util_scripts/
```

located relative to it.

------------------------------------------------------------------------

## Configuration {#configuration}

### `general_config.yaml`

`general_config.yaml` is tracked in the repository and contains shared, machine-independent application settings.

The application assumes that it is launched from the repository root. The resource and dataset directories therefore use paths relative to that root.

The path configuration is:

``` yaml
paths:
  resources_dir: "resources"
  datasets_dir: "datasets"
```

The remaining sections define filenames and standard directory names used by the pipeline.

| Key | Purpose |
|----|----|
| `paths.resources_dir` | Resource directory relative to the application root; normally `resources` |
| `paths.datasets_dir` | Dataset directory relative to the application root; normally `datasets` |
| `resource_files.*` | Expected filenames inside `resources/` |
| `dataset_paths.*` | Standard subdirectories inside each dataset (`data`, `processed_data`, `results`) |
| `config_files.*` | Standard configuration filenames (`dataset_config.yaml`, `samples_config.yaml`, `selected_config.yaml`) |
| `standardization_pipelines` | Available standardization templates, currently `10x` and `undefined` |

The expected directory structure is part of the application design. In normal use, the `resources_dir` and `datasets_dir` values should not need to be changed.

------------------------------------------------------------------------

## Resource Files {#resource-files}

The pipeline expects its biological/reference files inside:

``` text
resources/
```

The expected filenames are defined under `resource_files` in `general_config.yaml`.

Only `metadata_extract_prompt.txt` is currently committed to the repository. The remaining files must be obtained or generated separately and placed into `resources/`.

All required files are checked when `app.R` starts. If any are missing, startup stops and reports which files could not be found.

| Config key | Default filename | Tracked in repo? | What it is | Format / expected columns | Source |
|----|----|----|----|----|----|
| `metadata_prompt` | `metadata_extract_prompt.txt` | ✅ Yes | Prompt shown in the app's Reference Data tab for metadata extraction from papers/GEO records | Plain text | Custom |
| `hgnc_complete_set` | `hgnc_complete_set.txt` | ❌ No | Complete HGNC gene-symbol reference used to map Ensembl IDs and resolve chromosomal positions | Tab-delimited; must contain `ensembl_gene_id`, `symbol`, and the fields used for genomic location mapping | [HGNC](https://www.genenames.org/download/statistics-and-files/) / Ensembl BioMart |
| `gene_positions` | `gene_positions_biomaRt_0626.csv` | ❌ No | Per-gene genomic coordinates used for CNA ordering | Must contain `ensembl_gene_id`, `chromosome_name`, `start_position`, `hgnc_symbol` | Generated with [`biomaRt`](https://bioconductor.org/packages/release/bioc/html/biomaRt.html) |
| `marker_sets` | `global_cell_type_markers.csv` | ❌ No | Marker-gene sets used for DE matching and signature scoring | Columns include `cell_type`, `gene`/`symbol`, and `combined` | [3CA — Curated Cancer Cell Atlas](https://www.weizmann.ac.il/sites/3CA/) |
| `malignant_markers` | `malignant_markers.csv` | ❌ No | Cancer-type-specific malignant-cell markers | Columns include `cancer_type`, `symbol`, and `combined` | Same marker-source family as `marker_sets` |
| `housekeeping_genes` | `housekeeping_genes.txt` | ❌ No | Housekeeping-gene list used as an artifact marker set | One gene symbol per line, no header | Curated |
| `mitochondrial_genes` | `mt_genes.txt` | ❌ No | Mitochondrial-gene list used as an artifact marker set | One gene symbol per line, no header | Curated |
| `cancer_cell_map` | `cancer_cell_map.json` | ❌ No | Maps sample cancer types to malignant-marker acronyms and display cell types | JSON with `cancer_types` and `cell_types` top-level keys | Custom |

For example:

``` json
{
  "cancer_types": {
    "Breast Cancer": "Breast",
    "Head and Neck Squamous Cell Carcinoma": "HNSCC"
  },
  "cell_types": {
    "Breast": "Epithelial",
    "HNSCC": "Epithelial"
  }
}
```

The untracked resource files should be excluded in `.gitignore`, for example:

``` gitignore
resources/hgnc_complete_set.txt
resources/gene_positions_biomaRt_0626.csv
resources/global_cell_type_markers.csv
resources/malignant_markers.csv
resources/housekeeping_genes.txt
resources/mt_genes.txt
resources/cancer_cell_map.json
```

------------------------------------------------------------------------

## Setting Up a New Dataset {#setting-up-a-new-dataset}

The simplest method is to click **Create New Dataset** on the application's Dataset Selection screen.

The app initializes a new dataset under the configured `datasets/` directory and creates:

``` text
datasets/<dataset_id>/
├── cache/
├── data/
├── processed_data/
├── results/
├── dataset_config.yaml
├── samples_config.yaml
├── selected_config.yaml
└── standardize.qmd
```

The copied `standardize.qmd` is selected according to the technology chosen when the dataset is created.

### `dataset_config.yaml`

This file is copied from:

``` text
templates/dataset_config_template.yaml
```

Important fields include:

-   `project_info.dataset_id` – dataset identifier.
-   `project_info.technology` – selected input technology.
-   `std_names.*` – standardized filenames expected by the downstream pipeline.
-   `marker_filter_params.*` – marker filtering thresholds.
-   `params.min_genes` – minimum detected genes per cell.
-   `params.target_sum` – normalization target.
-   `params.log2_expr_threshold` – expression-based gene filter.
-   `params.pca_nv` – number of PCA components.
-   `params.seed` – random seed used by stochastic pipeline steps.
-   `params.resolutions` – Louvain resolutions to evaluate.
-   `params.umap.*` – UMAP settings.
-   `params.de.*` – differential-expression and marker-matching settings.

`std_names.expmat` is updated during standardization according to the selected matrix state.

### `samples_config.yaml`

This file must be filled in before standardization can run.

Every sample requires a non-empty `id`. The following metadata fields must also exist, although their values may be left blank when unknown:

``` text
id, technology, cancer_type, patient, histology, site, sample_type,
sample_primary_met, disease_extent, diagnosis_recurrence, instance_at_site,
treated_naive, age, sex, grade, AJCC_stage, AJCC_T, AJCC_N, AJCC_M, size,
smoking_status, PY, KI67, genetic_hormonal_features, chemotherapy_exposed,
chemotherapy_response, targeted_rx_exposed, targeted_rx_response,
post_sampling_rx_exposed, post_sampling_rx_response,
time_end_of_rx_to_sampling, ET_exposed, ET_response, ICB_exposed,
ICB_response, PFS_DFS, OS
```

This structure is enforced by `prevalidate_setup()`.

If malignant-marker matching is required, `cancer_type` should exactly match a key under `cancer_types` in `cancer_cell_map.json`.

For example:

``` text
Breast Cancer
```

rather than:

``` text
Breast
```

The current annotation setup applies a cancer-type-specific malignant marker set only when the dataset contains one unambiguous cancer type across its samples.

### `selected_config.yaml`

This file is initialized automatically and populated as the user progresses through the app.

It stores state such as:

-   selected clustering resolutions;
-   CNA reference cell types;
-   potentially malignant cell types;
-   selected malignant CNA subclusters;
-   CNA thresholds.

It normally should not be edited manually.

------------------------------------------------------------------------

## Standardization Pipeline {#standardization-pipeline}

Before a dataset can be loaded into the main analysis workflow, its raw data must be converted to the standardized per-sample format expected by the app.

For each sample, this includes:

``` text
Exp_data_<matrix_state>.mtx
Genes.txt
Cells.csv
```

and the dataset receives a dataset-wide:

``` text
Samples.csv
```

The standardization workflow is provided by the `standardize.qmd` file copied into each new dataset.

The source template is selected from:

``` text
templates/standardize_10x.qmd
templates/standardize_undefined.qmd
```

depending on the chosen technology.

Both templates currently use explicit path variables near the beginning of the document:

``` r
app_folder_path <- "/path/to/scAnnotationPipeline"

dataset_dir_path <- file.path(
  app_folder_path,
  "datasets",
  "<dataset_id>"
)

resources_path <- file.path(
  app_folder_path,
  "resources"
)
```

These variables point the standalone Quarto standardization workflow back to the application code, the current dataset, and the resource files.

The standardization templates follow the same overall structure:

1.  **Path definitions** – define the application root, current dataset, and resource paths.
2.  **Pre-validation** – verify that `samples_config.yaml` is populated correctly.
3.  **Data ingestion**
    -   `10x`: extract/read the raw 10x files and pair barcode, feature, and matrix files with samples.
    -   `undefined`: provide custom import/splitting logic for other input formats.
4.  **Matrix inspection and `matrix_state`**
    -   inspect the raw matrix;
    -   identify whether values represent UMI counts, CPM, TPM, etc.;
    -   set the appropriate `matrix_state`.
5.  **Standardization**
    -   map genes to HGNC symbols;
    -   generate standardized cell metadata;
    -   write expression matrices, gene files, and cell files.
6.  **Finalize configuration**
    -   write dataset-wide sample metadata;
    -   initialize/update `selected_config.yaml`.
7.  **Post-validation**
    -   verify expected files;
    -   check matrix dimensions;
    -   check metadata dimensions;
    -   verify unique cell names;
    -   report validation warnings/errors.

The matrix state determines the standardized matrix filename. For example:

``` text
Exp_data_UMIcounts.mtx
Exp_data_CPM.mtx
Exp_data_TPM.mtx
```

The selected filename is written back to `dataset_config.yaml`.

Render the document in RStudio or run:

``` bash
quarto render standardize.qmd
```

from inside the dataset directory.

------------------------------------------------------------------------

## Running the App {#running-the-app}

The app must be launched from the repository root — the directory containing:

``` text
app.R
general_config.yaml
resources/
datasets/
templates/
util_scripts/
```

For example:

``` r
shiny::runApp(".")
```

or open `app.R` in RStudio and click **Run App**.

Launching from another working directory is not supported because several application components deliberately use repository-relative paths.

On startup, the app:

1.  Loads `general_config.yaml`.
2.  Sources every `.R` file in `util_scripts/`.
3.  Resolves and validates all expected files under `resources/`.
4.  Creates `datasets/` if necessary.
5.  Scans `datasets/` for available dataset workspaces.
6.  Displays them in the Dataset Selection screen.

The main workflow is:

``` text
Dataset Selection
        ↓
Start Menu
        ↓
Pre-Processing & Clustering
        ↓
Resolution Selection
        ↓
Differential Expression
        ↓
Manual Annotation
        ↓
CNA Analysis
```

------------------------------------------------------------------------

## Testing {#testing}

The repository contains a `testthat` suite covering utility functions and the main non-interactive workflow paths.

Synthetic fixtures are generated in:

``` text
tests/testthat/helper-fixtures.R
```

so routine tests do not require the large untracked resource files or real biological datasets.

This repository deliberately uses a **package-lite** layout. Application functions remain under:

``` text
util_scripts/
```

rather than a conventional package `R/` directory.

`app.R` sources these scripts during application startup, while:

``` text
tests/testthat/helper-source.R
```

sources the same scripts into the test environment.

This ensures that the tests exercise the same utility functions used by the application.

### Running the tests {#running-the-tests}

From the repository root, the recommended command is:

``` r
devtools::test()
```

The standalone runner can also be used:

``` bash
Rscript tests/testthat.R
```

A successful complete run should end with:

-   zero failures;
-   zero unexpected warnings;
-   zero unexpected skips.

Some tests deliberately exercise validation paths that produce warnings or diagnostic output. Those conditions are captured by the tests and should therefore not appear as uncaught warnings in the final test summary.

Several integration tests require runtime analysis packages such as:

-   `matkot`;
-   `irlba`;
-   `uwot`;
-   `Seurat`;
-   `qs2`;
-   `dbscan`;
-   plotting dependencies.

Tests that depend on optional packages use `skip_if_not_installed()` where appropriate.

### Test structure {#test-structure}

| Test file | Main responsibility |
|----|----|
| `test-01_utils_io.R` | Required-file handling and loading of genes, sparse expression matrices, cell/sample metadata, and related I/O |
| `test-02_utils_annotation.R` | Cell/gene filtering, normalization, PCA/UMAP/Louvain helpers, and core annotation utilities |
| `test-02_utils_annotation_de.R` | DE ranking, configurable `num_genes`, exact marker matching, `max_match_genes`, marker filtering, minimum-marker checks, and signature-score alignment |
| `test-02_utils_annotation_cna.R` | CNA-specific helpers including hierarchical clustering, CNA UMAP/HDBSCAN behavior, and plot construction |
| `test-03_utils_misc.R` | Dataset-name sanitization, duplicate sparse rows, Ensembl-symbol mapping, configuration initialization, sample/cell construction, pre-validation, and post-standardization validation |
| `test-04_utils_caching.R` | Cache directory creation, `.qs2` save/load round trips, existence checks, missing-cache errors, and cache clearing |
| `test-05_utils_workflow.R` | DE workflow orchestration, cached DE outputs, multi-sample routing, and manual-annotation setup |
| `test-05_utils_workflow_clustering.R` | End-to-end clustering orchestration, clustering caches, and generated clustering plots |
| `test-05_utils_workflow_cna.R` | CNA thresholds, collision behavior, signal/correlation computation, batch processing, heatmap/clustering integration, and preview behavior |
| `test-golden_outputs.R` | Regression comparison against the deterministic `compute_cna()` golden baseline |
| `test-regression_clustering.R` | End-to-end preprocessing → PCA → UMAP → Louvain regression test |
| `test-regression_cna_cache.R` | CNA compute/cache/load round trip and missing-cache behavior |

The helper files have distinct roles:

-   `helper-source.R` loads the real application utility scripts into the test environment.
-   `helper-fixtures.R` constructs deterministic synthetic expression matrices, metadata, sample directories, mappings, configurations, and CNA fixtures.
-   Temporary directories are used for cache, output, and file-I/O tests so the suite does not modify real datasets.

### Coverage summary {#coverage-summary}

The test strategy emphasizes **behavioral and workflow coverage** rather than maximizing a line-coverage percentage.

Coverage is strongest in the following areas.

#### I/O and validation

Tests cover:

-   required input-file handling;
-   expression-matrix loading;
-   gene/cell/sample metadata loading;
-   dataset-name sanitization;
-   standardization pre-validation;
-   dimension mismatch detection;
-   duplicate-cell detection;
-   missing standardized files.

#### Preprocessing and clustering

Tests cover:

-   cell filtering;
-   normalization;
-   expression-based gene filtering;
-   PCA;
-   UMAP;
-   Louvain clustering;
-   clustering workflow orchestration;
-   clustering cache generation;
-   expected plot side effects.

The regression tests avoid depending on unstable exact UMAP coordinates or exact Louvain labels where those values may vary across library versions.

#### Differential expression and annotation

Tests cover:

-   ranked DE genes;
-   configurable DE output depth through `num_genes`;
-   configurable marker-matching depth through `max_match_genes`;
-   exact marker matching;
-   marker-set filtering;
-   marker availability checks;
-   minimum-marker requirements;
-   signature-score alignment by cell name;
-   DE output creation;
-   annotation setup from cached results.

#### Caching

Tests cover:

-   cache creation;
-   persistence;
-   retrieval;
-   cache existence checks;
-   missing-cache errors;
-   cache clearing;
-   CNA matrix cache round trips.

#### CNA analysis

Tests cover:

-   deterministic CNA arithmetic;
-   hierarchical CNA clustering;
-   HDBSCAN/UMAP CNA helper behavior;
-   signal/correlation computation;
-   malignant threshold assignment;
-   non-malignant threshold assignment;
-   gray-zone assignment;
-   multi-subclone collisions;
-   batch CNA processing branches;
-   clustering/heatmap output;
-   CNA preview generation;
-   verification that preview assignments are not persisted.

A cell that satisfies malignant thresholds for multiple subclones remains:

``` text
cell_type = "Malignant"
subclone = NA
```

because the malignant state is known but the specific subclone is ambiguous.

#### Regression protection

The suite includes:

-   a deterministic golden baseline for `compute_cna()`;
-   clustering integration/regression tests;
-   CNA cache integration/regression tests;
-   workflow-level tests protecting important file/cache side effects.

No numeric line or branch coverage percentage is currently enforced.

The goal is instead to protect the biologically and operationally important contracts of the pipeline.

Areas intentionally not exhaustively tested include:

-   the Shiny reactive/UI layer itself;
-   pixel-identical plot snapshots;
-   Quarto rendering across all operating systems;
-   every possible real biological dataset;
-   every possible version combination of external analysis packages.

Plot tests generally validate that plots can be constructed and built successfully, and that expected workflow output files are produced, rather than comparing rendered pixels.

### Golden fixtures {#golden-fixtures}

`compute_cna()` has a committed golden regression fixture:

``` text
tests/testthat/fixtures/compute_cna_golden.rds
```

The fixture should only be regenerated when a numerical change to `compute_cna()` is intentional and has been reviewed.

From the repository root:

``` bash
Rscript tests/testthat/fixtures/generate_golden_fixtures.R
```

Do **not** regenerate the golden file simply to make a failing test pass.

First determine why the output changed, then inspect the change before committing the refreshed fixture.

If `.gitignore` contains a general rule such as:

\`\`\`gitignore
