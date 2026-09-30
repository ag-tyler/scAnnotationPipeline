# scAnnotationPipeline User Guide

This guide contains the detailed operational and technical documentation for `scAnnotationPipeline`.

For installation and a concise project overview, see the repository **[README](../README.md)**.

## Table of Contents

- [Repository Structure](#repository-structure)
- [Configuration](#configuration)
- [Resource Files](#resource-files)
- [Setting Up a New Dataset](#setting-up-a-new-dataset)
  - [`dataset_config.yaml`](#dataset_configyaml)
  - [`samples_config.yaml`](#samples_configyaml)
  - [`selected_config.yaml`](#selected_configyaml)
- [Standardization Pipeline](#standardization-pipeline)
- [Running the Analysis Pipeline](#running-the-analysis-pipeline)
- [Testing](#testing)
  - [Running the tests](#running-the-tests)
  - [Test structure](#test-structure)
  - [Coverage summary](#coverage-summary)
  - [Golden fixtures](#golden-fixtures)
- [Pipeline Assumptions](#pipeline-assumptions)
- [Cache Behavior & Invalidation](#cache-behavior--invalidation)
- [Known Limitations](#known-limitations)

---

## Repository Structure

The application root contains the Shiny app, configuration, resources, datasets, templates, utility scripts, documentation, and tests:

```text
scAnnotationPipeline/
├── app.R                              # Main Shiny application
├── .gitignore
├── general_config.yaml                # Shared application configuration
├── DESCRIPTION
├── README.md
│
├── docs/
│   └── USER_GUIDE.md
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

The repository root is also the application working root. `app.R` expects `general_config.yaml`, `resources/`, `datasets/`, `templates/`, and `util_scripts/` at these relative locations.

`resources/` is part of the repository structure, but most biological resource files are intentionally untracked.

`datasets/` also lives inside the application root, but contains local data, caches, and generated results and should remain gitignored.

Everything in `util_scripts/` is sourced automatically when the app starts.

### Dataset layout

Each dataset lives under:

```text
datasets/<dataset_id>/
```

and is expected to contain:

```text
datasets/<dataset_id>/
├── dataset_config.yaml
├── samples_config.yaml
├── selected_config.yaml
├── standardize.qmd
├── cache/
├── data/
├── processed_data/
│   └── <sample_name>/
│       ├── Exp_data_<matrix_state>.mtx
│       ├── Genes.txt
│       └── Cells.csv
└── results/
    └── <sample_name>/
        ├── 1_cluster_plots/
        ├── 2_de_plots/
        └── 3_cna_plots/
```

The matrix filename depends on `std_names.expmat` in `dataset_config.yaml`.

---

## Configuration

### `general_config.yaml`

`general_config.yaml` is tracked in the repository and contains shared, machine-independent application settings.

The app is designed around repository-relative paths:

```yaml
paths:
  resources_dir: "resources"
  datasets_dir: "datasets"
```

The remaining configuration sections define expected filenames, standard dataset subdirectories, and available standardization templates.

| Key | Purpose |
|---|---|
| `paths.resources_dir` | Resource directory relative to the application root |
| `paths.datasets_dir` | Dataset directory relative to the application root |
| `resource_files.*` | Expected filenames inside `resources/` |
| `dataset_paths.*` | Standard subdirectories inside each dataset (`data`, `processed_data`, `results`) |
| `config_files.*` | Standard configuration filenames |
| `standardization_pipelines` | Available standardization templates, currently `10x` and `undefined` |

The intended standard values for the two top-level directories are `resources` and `datasets`.

---

## Resource Files

The pipeline expects biological/reference data under:

```text
resources/
```

Expected filenames are configured under `resource_files` in `general_config.yaml`.

Only `metadata_extract_prompt.txt` is currently intended to be tracked with the repository. The remaining resource files must be obtained/generated separately and placed into `resources/`.

All required files are validated at app startup. Missing resources cause startup to stop with an explicit list of missing paths.

| Config key | Default filename | Tracked? | Purpose / expected format |
|---|---|---:|---|
| `metadata_prompt` | `metadata_extract_prompt.txt` | Yes | Plain-text prompt displayed in the Reference Data tab |
| `hgnc_complete_set` | `hgnc_complete_set.txt` | No | HGNC reference used for Ensembl→symbol and genomic-location mapping; requires fields including `ensembl_gene_id`, `symbol`, and location information |
| `gene_positions` | `gene_positions_biomaRt_0626.csv` | No | Genomic positions for CNA ordering; requires `ensembl_gene_id`, `chromosome_name`, `start_position`, `hgnc_symbol` |
| `marker_sets` | `global_cell_type_markers.csv` | No | Marker sets used for DE matching/signature scoring; columns include `cell_type`, gene symbol, `combined` |
| `malignant_markers` | `malignant_markers.csv` | No | Cancer-type-specific malignant markers; columns include `cancer_type`, `symbol`, `combined` |
| `housekeeping_genes` | `housekeeping_genes.txt` | No | One housekeeping gene symbol per line |
| `mitochondrial_genes` | `mt_genes.txt` | No | One mitochondrial gene symbol per line |
| `cancer_cell_map` | `cancer_cell_map.json` | No | Maps sample cancer types to malignant-marker acronyms and display cell types |

A `cancer_cell_map.json` follows this general structure:

```json
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

The untracked resource files should be listed in `.gitignore`, for example:

```gitignore
resources/hgnc_complete_set.txt
resources/gene_positions_biomaRt_0626.csv
resources/global_cell_type_markers.csv
resources/malignant_markers.csv
resources/housekeeping_genes.txt
resources/mt_genes.txt
resources/cancer_cell_map.json
```

---

## Setting Up a New Dataset

Use **Create New Dataset** from the app's Dataset Selection screen.

A new dataset is created under:

```text
datasets/<dataset_id>/
```

and initialized with the standard subdirectories, configuration files, and the matching `standardize_<technology>.qmd` template copied to:

```text
standardize.qmd
```

The standard workflow is:

1. create the dataset in the app;
2. add raw data to `data/`;
3. fill in `samples_config.yaml`;
4. run/edit `standardize.qmd`;
5. validate the standardized output;
6. load the dataset in the app;
7. run clustering → DE → annotation → CNA.

### `dataset_config.yaml`

This file is copied from:

```text
templates/dataset_config_template.yaml
```

Important fields include:

- `project_info.dataset_id`
- `project_info.technology`
- `std_names.*`
- `marker_filter_params.*`
- `params.min_genes`
- `params.target_sum`
- `params.log2_expr_threshold`
- `params.pca_nv`
- `params.seed`
- `params.resolutions`
- `params.umap.*`
- `params.de.*`

`std_names.*` defines the standardized files expected by the downstream pipeline.

`std_names.expmat` is updated during standardization according to the detected/selected matrix state.

### `samples_config.yaml`

This file must be completed before standardization can run.

Every sample requires a non-empty `id`. The required metadata keys are:

```text
id, technology, cancer_type, patient, histology, site, sample_type,
sample_primary_met, disease_extent, diagnosis_recurrence, instance_at_site,
treated_naive, age, sex, grade, AJCC_stage, AJCC_T, AJCC_N, AJCC_M, size,
smoking_status, PY, KI67, genetic_hormonal_features, chemotherapy_exposed,
chemotherapy_response, targeted_rx_exposed, targeted_rx_response,
post_sampling_rx_exposed, post_sampling_rx_response,
time_end_of_rx_to_sampling, ET_exposed, ET_response, ICB_exposed,
ICB_response, PFS_DFS, OS
```

The keys must exist even when some values are unknown/blank. This is enforced by `prevalidate_setup()`.

For malignant-marker matching, `cancer_type` should exactly match a key under `cancer_types` in `cancer_cell_map.json`.

For example:

```text
Breast Cancer
```

rather than:

```text
Breast
```

The current annotation logic applies a cancer-type-specific malignant marker set only when the dataset has one unambiguous cancer type across its samples.

### `selected_config.yaml`

This file is initialized automatically and populated by the app.

It stores state such as:

- selected clustering resolutions;
- CNA reference cell types;
- potentially malignant cell types;
- selected malignant CNA subclusters;
- CNA thresholds.

It normally should not be edited manually.

---

## Standardization Pipeline

Before a dataset can enter the main Shiny analysis workflow, its raw data must be transformed into the standardized per-sample format.

Per sample, the output includes:

```text
Exp_data_<matrix_state>.mtx
Genes.txt
Cells.csv
```

The dataset also receives a dataset-wide:

```text
Samples.csv
```

The source templates are:

```text
templates/standardize_10x.qmd
templates/standardize_undefined.qmd
```

When a dataset is created, the matching template is copied into the dataset as:

```text
standardize.qmd
```

### Template workflow

The templates follow the same overall structure:

1. **Path definitions**
   - application root;
   - dataset directory;
   - resources directory.
2. **Pre-validation**
   - checks `samples_config.yaml`;
   - hard-stops on structurally invalid setup.
3. **Data ingestion**
   - `10x`: reads/extracts the relevant barcode, feature, and matrix files and maps raw samples to configured sample IDs;
   - `undefined`: provides a skeleton for custom loading/splitting logic.
4. **Matrix inspection and `matrix_state`**
   - inspect matrix values;
   - determine whether the input represents UMI counts, CPM, TPM, etc.;
   - set the corresponding state.
5. **Standardization**
   - map genes to HGNC symbols where needed;
   - construct standardized cell metadata;
   - write expression, gene, and cell files.
6. **Finalize configuration**
   - create/update `Samples.csv`;
   - initialize `selected_config.yaml`;
   - update the standardized expression-matrix filename.
7. **Post-validation**
   - verify expected files;
   - verify matrix/metadata dimensions;
   - check cell-name uniqueness;
   - print pass/warning output.

Examples of standardized expression matrix names are:

```text
Exp_data_UMIcounts.mtx
Exp_data_CPM.mtx
Exp_data_TPM.mtx
```

Render `standardize.qmd` in RStudio or run:

```bash
quarto render standardize.qmd
```

from inside the dataset directory.

---

## Running the Analysis Pipeline

Launch the app from the repository root:

```r
shiny::runApp(".")
```

The main workflow is:

```text
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

### Pre-processing and clustering

The pipeline loads standardized expression/cell/gene data, applies filtering and normalization, performs PCA and UMAP, and runs Louvain clustering across configured resolutions.

Clustering results and filtered matrices are cached on disk, and UMAP plots are written to the dataset results directories.

### Resolution selection

Choose one resolution per sample. The selected resolutions are stored in `selected_config.yaml` and used by downstream DE/annotation/CNA workflows.

### Differential expression

For each selected clustering result, the pipeline:

- ranks genes per cluster;
- retains the configured number of DE genes;
- compares DE genes with marker sets;
- counts marker matches over the configured top-N DE positions;
- calculates signature scores;
- writes marker-match tables and diagnostic plots.

### Manual annotation

The annotation interface loads cached clustered cells together with DE marker matches/signature scores so clusters can be assigned final cell types.

Saved annotations update the corresponding `Cells.csv`.

### CNA analysis

The CNA workflow:

1. selects reference and potentially malignant cell types;
2. computes inferred CNA profiles;
3. clusters candidate malignant/unassigned cells;
4. identifies malignant subclone candidates;
5. computes CNA signal/correlation metrics;
6. applies user-selected malignant/non-malignant thresholds;
7. previews the final assignments;
8. saves malignant assignments and diagnostic plots.

A cell satisfying malignant thresholds for exactly one subclone receives that subclone ID.

A cell satisfying malignant thresholds for more than one subclone remains:

```text
cell_type = "Malignant"
subclone = NA
```

because malignancy is supported but the subclone assignment is ambiguous.

---

## Testing

The repository includes a `testthat` suite for utility functions and the main non-interactive workflow paths.

The project deliberately uses a package-lite layout: application functions remain under `util_scripts/`, and `tests/testthat/helper-source.R` sources those same real scripts into the test environment.

Synthetic test data are built in `tests/testthat/helper-fixtures.R`; routine tests do not depend on real biological datasets.

### Running the tests

From the repository root:

```r
devtools::test()
```

or:

```bash
Rscript tests/testthat.R
```

A clean test run should finish with zero failures and zero unexpected warnings/skips.

Some tests deliberately exercise validation/error/warning paths. Those conditions are captured by expectations and therefore should not appear as uncaught suite warnings.

### Test structure

| Test file | Main responsibility |
|---|---|
| `test-01_utils_io.R` | Required-file handling and loading of genes, sparse matrices, cell/sample metadata, and related I/O |
| `test-02_utils_annotation.R` | Filtering, normalization, PCA/UMAP/Louvain helpers, and core annotation utilities |
| `test-02_utils_annotation_de.R` | DE ranking, `num_genes`, exact marker matching, `max_match_genes`, marker filtering, minimum-marker checks, signature-score alignment |
| `test-02_utils_annotation_cna.R` | CNA-specific helpers including hierarchical clustering, CNA UMAP/HDBSCAN behavior, and plot construction |
| `test-03_utils_misc.R` | Dataset-name sanitization, duplicate sparse rows, Ensembl-symbol mapping, configuration setup, sample/cell construction, pre/post-validation |
| `test-04_utils_caching.R` | Cache creation, `.qs2` round trips, existence checks, missing-cache errors, and clearing |
| `test-05_utils_workflow.R` | DE workflow orchestration, cached DE outputs, multi-sample routing, annotation setup |
| `test-05_utils_workflow_clustering.R` | End-to-end clustering orchestration, clustering caches, generated plots |
| `test-05_utils_workflow_cna.R` | CNA thresholds, collision behavior, signal/correlation, batch branches, heatmap/clustering integration, preview behavior |
| `test-golden_outputs.R` | Deterministic `compute_cna()` golden regression baseline |
| `test-regression_clustering.R` | Preprocessing → PCA → UMAP → Louvain integration/regression behavior |
| `test-regression_cna_cache.R` | CNA compute/cache/load round trip and missing-cache behavior |

The helper files have distinct roles:

- `helper-source.R` sources the real utility scripts;
- `helper-fixtures.R` builds deterministic synthetic matrices, metadata, configurations, and CNA inputs;
- temporary directories isolate cache/result/file-I/O tests from real datasets.

### Coverage summary

The suite emphasizes **behavioral and workflow coverage** rather than maximizing a numeric line-coverage percentage.

Coverage is strongest in:

- **I/O and validation**: required files, standardized input loading, metadata creation, dataset-name validation, configuration pre-validation, dimension mismatch and duplicate-cell checks.
- **Preprocessing and clustering**: cell filtering, normalization, gene filtering, PCA, UMAP, Louvain clustering, clustering caches, and plot side effects.
- **Differential expression and annotation**: DE ranking, configurable `num_genes`, configurable `max_match_genes`, exact marker matching, marker availability/minimum-marker logic, signature-score alignment, workflow outputs, annotation setup.
- **Caching**: creation, persistence, retrieval, missing-cache behavior, clearing, and CNA cache round trips.
- **CNA analysis**: deterministic CNA arithmetic, hierarchical/HDBSCAN/UMAP helpers, signal/correlation, malignant/non-malignant/gray-zone threshold behavior, multi-subclone collisions, batch branches, heatmap/clustering outputs, and non-mutating preview behavior.
- **Regression protection**: deterministic golden baseline, clustering integration/regression tests, and CNA cache integration/regression tests.

No numeric line/branch coverage percentage is currently claimed or enforced.

Areas intentionally not exhaustively covered include:

- the Shiny reactive/UI layer itself;
- pixel-identical plot snapshots;
- Quarto rendering across every platform;
- every possible real biological dataset/resource combination.

Plot tests generally validate construction/buildability and workflow side effects rather than rendered pixels.

### Golden fixtures

`compute_cna()` has a committed golden baseline:

```text
tests/testthat/fixtures/compute_cna_golden.rds
```

Regenerate it only when an intentional numerical change to `compute_cna()` has been reviewed.

From the repository root:

```bash
Rscript tests/testthat/fixtures/generate_golden_fixtures.R
```

Do **not** regenerate it simply to make a failing regression test pass.

If `.gitignore` contains:

```gitignore
*.rds
```

retain the committed golden fixture explicitly:

```gitignore
!tests/testthat/fixtures/compute_cna_golden.rds
```

---

## Pipeline Assumptions

The pipeline assumes:

- **The raw expression matrix is not already log-normalized.** Downstream normalization occurs inside the analysis pipeline. Feeding already log-transformed values may result in unintended double transformation.
- **Cell names are unique within a sample.**
- **Ensembl gene IDs are unique within the raw gene list.** Duplicate gene symbols are allowed because gene-symbol mapping can be reconstructed from Ensembl IDs.
- **Sample directory names under `processed_data/` are canonical sample identifiers** and should match sample `id` values in `samples_config.yaml`.
- **`samples_config.yaml` is structurally complete before standardization.**
- **The generic marker set excludes `Malignant`.** Malignant marker handling is performed separately through `malignant_markers.csv` and `cancer_cell_map.json`.
- **Required resources exist under `resources/`.**
- **The app is launched from the repository root.**

---

## Cache Behavior & Invalidation

The app stores expensive intermediate objects as `.qs2` files under:

```text
datasets/<dataset_id>/cache/
```

Cached objects include filtered/normalized expression matrices, clustered cells, CNA matrices, hierarchical clustering objects, and CNA signal/correlation tables.

### Important limitation

Cache filenames do not encode every analysis parameter.

Changing parameters such as:

```text
params.min_genes
params.target_sum
params.pca_nv
params.seed
params.resolutions
params.umap.*
marker_filter_params.*
```

does not necessarily invalidate existing cached results automatically.

### Clustering or normalization parameters changed

Delete the affected dataset cache and rerun **Run Clustering for all Resolutions**.

Generated result plots should also be regenerated where appropriate.

### Marker sets or marker filtering changed

Marker sets are rebuilt when the dataset is loaded. Reload the dataset so `complete_markers` is regenerated.

### Redoing CNA for one sample

Prefer the in-app **Reset Sample CNA** function.

It removes/clears the relevant:

```text
cna_matrix_*
hclust_*
cna_sig_cor_*_subclone_*
```

cache files and associated CNA state/results while reverting saved malignant assignments to the pre-CNA manual annotations.

This avoids leaving cache files, plots, configuration, and cell metadata out of sync.

### Changing malignant subclone selections

Saving a new malignant-subclone selection clears stale threshold configuration and dependent subclone outputs automatically.

### Other good practices

- Back up important `processed_data/<sample>/Cells.csv` files before large annotation changes.
- Keep the entire `datasets/` directory out of Git.
- Keep unredistributable/large resource files out of Git.
- Ignore generated `.rds` files unless they are intentional regression baselines.
- Keep source code, templates, configuration, tests, documentation, and intentional golden fixtures version-controlled.

---

## Known Limitations

- Most biological resource files are not distributed with the repository and must be obtained/generated separately.
- The `undefined` standardization template is intentionally a skeleton; custom import and sample-splitting logic is required for unsupported input layouts.
- The Shiny reactive/UI layer is not currently covered by a dedicated browser-level integration test suite.
- Cached results are not automatically invalidated for every analysis-parameter change.
- Real-world biological inputs can expose cases not represented by the deterministic synthetic test fixtures.

---

[Back to README](../README.md)
