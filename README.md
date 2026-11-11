# scAnnotationPipeline

A Shiny application for standardizing, clustering, differential-expression analysis, manual cell-type annotation, and copy-number alteration (CNA) analysis of single-cell RNA-seq cancer datasets.

The pipeline guides a dataset through:

1. **Standardization** – convert raw input into a consistent per-sample format.
2. **Clustering** – PCA → UMAP → Louvain clustering across multiple resolutions.
3. **Resolution selection** – choose the clustering resolution used downstream.
4. **Differential expression** – rank genes per cluster and compare them with known marker sets.
5. **Manual annotation** – assign cell types using DE marker matches and signature scores.
6. **CNA analysis** – infer copy-number alterations and classify malignant cells/subclones.

For detailed information about dataset setup, configuration, standardization, resource files, testing, cache behavior, and CNA analysis, see the [**User Guide**](docs/USER_GUIDE.md).

## Requirements

* **R ≥ 4.5.2**
* **Quarto** only if using the historical/reference `.qmd` templates
* Required R packages:

```r
install.packages(c(
  "shiny", "bslib", "shinyjs", "data.table", "yaml", "jsonlite", "DT",
  "ggplot2", "cowplot", "viridis", "Matrix", "irlba", "uwot", "Seurat",
  "stringr", "caTools", "RColorBrewer", "scales", "dbscan", "ggdendro",
  "randomcoloR", "docstring", "qs2", "magrittr", "R.utils",
  "zip", "processx", "R6", "ps", "fs"
))
```

The pipeline also depends on the custom `matkot` package:

```r
install.packages("pak")
pak::pak("m20ty/matkot")
```

For development/testing:

```r
install.packages(c("devtools", "testthat", "withr", "shinytest2"))
```

## Installation

Clone the repository and enter the application directory:

```bash
git clone <your-repo-url>
cd <repo-folder>
```

Add the required untracked biological resource files to the existing `resources/` directory. See the [Resource Files](docs/USER_GUIDE.md#resource-files) section of the User Guide for the expected files and formats.

The standard directory layout is:

```text
scAnnotationPipeline/
├── app.R
├── general_config.yaml
├── DESCRIPTION
├── README.md
├── docs/
│   ├── USER_GUIDE.md
│   └── development/          # Plans, manual replays and release acceptance
├── resources/
├── datasets/
├── templates/
├── util_scripts/
└── tests/
```

The app is designed to run from the repository root. `resources/` and `datasets/` are relative to that root.

### Application structure

`app.R` is the thin entry point. It sources utilities and an explicit component
manifest, constructs the immutable application context, and assembles the UI and
server. Application-specific code is grouped under `app/`:

- `app/context.R` loads configuration and immutable biological resources.
- `app/state.R` creates the flat per-session reactive state.
- `app/ui/` contains the dataset, dashboard, resolution, annotation, and CNA
  panels plus their top-level composition.
- `app/server/` contains matching stage registration functions; CNA handlers are
  further separated into status, computation, cluster, threshold, summary, and
  reset stages.

The files are sourced only by the ordered manifest in `app.R`; Shiny's implicit
package-directory autoload remains disabled.

## Running the App

From the repository root, use the stable launcher in the R/Positron console:

```r
source("scripts/run_app.R")
```

The launcher disables Shiny autoreload before starting the app. This is the
recommended mode because the pipeline intentionally writes logs, state, cache,
configuration, and result files below the application directory; an IDE
development watcher can otherwise treat those writes as a reason to restart
the session.

For code-development sessions, `shiny::runApp(".")` or the IDE's **Run App**
button can still be used, but the developer is responsible for disabling or
configuring autoreload. Ordinary pipeline runs do not require the optional
`watcher` package.

On startup, the app:

1. sources all `.R` utilities in `util_scripts/` and the application components;
2. reads `general_config.yaml`;
3. validates and loads the required resource files;
4. creates/scans the configured datasets directory (default `datasets/`);
5. displays available datasets in the Dataset Selection screen.

## CNA Values Results

Finalizing a sample's CNA assignment saves its cell assignments and plots.
The summary/preview view stays open after saving so the optional export action
remains available.
The separate, optional **Export/Re-export CNA Values Table** action publishes
a reusable long-format table at `results/<sample>/3_cna_results/cna_values_<sample>.csv.gz`, with the
columns `gene`, `chr`, `start_pos`, `cell_name`, and `cna`. A neighboring
`.metadata.yaml` file records dimensions and the validated cache provenance.
The CNA summary view can export or refresh this table while the required caches
remain current, without recomputing CNA. The optimized `.qs2` cache remains
authoritative and the CSV is never used as pipeline input. `R.utils` supports
reading gzip-compressed tables with `data.table::fread()`.

Large exports report writing and validation progress with elapsed time. If an
export fails or is interrupted after assignments were saved, use **Export/Re-export
CNA Values Table** in the summary view to retry. Saved assignments remain valid;
the table and provenance are published together after validation, and a prior
complete export is retained if the new attempt fails before publication.

Dataset cleanup is allowed without these optional exports. Before cache removal,
the app lists completed CNA samples without a current values table and warns
that exporting their values later will require reopening the dataset and
recomputing CNA. Existing exports are retained.

To preserve chromosome strings such as `01`, import the compressed CSV with:

```r
cna_values <- data.table::fread(
  "results/<sample>/3_cna_results/cna_values_<sample>.csv.gz",
  colClasses = list(character = c("gene", "chr", "cell_name"))
)
```

## Review Snapshots

After every sample is finished (CNA finalized or explicitly omitted), use
**Start Menu → Dataset Storage → Create Review Snapshot**. Choose an existing
destination outside the app-managed datasets directory and **Folder**,
**Compressed archive (.zip)** or **Both**. Logs default on; existing CNA values
default off. Review the contents/space estimate and acknowledge any omissions.

Snapshots preserve complete standardized processed data, including cells
excluded during app preprocessing, all ordinary results/plots, historical
configuration, a README, scoped annotation/filtering summaries, and a checksum
manifest. They work before or after cache cleanup. No CNA values are computed
by copying. Older datasets can have unavailable aggregate statistics.

Optional `project_info.source_doi` and `source_url` fields in
`dataset_config.yaml` are included in the README. No destination is saved or
tracked, and scientific statuses do not change. A snapshot is not a raw-data
backup, an anonymized dataset or a resumable app workspace. See the
[User Guide](docs/USER_GUIDE.md#creating-a-review-snapshot) for verification,
space/path constraints and manual checks.

## Preparing input data

This is the prepared-input contract for the new import workflow tracked in the
[prepared-data import plan](docs/development/PREPARED_DATA_IMPORT_PLAN.md).
P01 provides the contract and reusable structure checker; P02 connects it to
dataset loading; P03 imports prepared data and opens the resulting workspace.
Sample membership, order, and metadata come exclusively from the sample CSV.
P04 removes preparation guide/prompt screens and their startup dependencies.
Snapshot provenance requirements are still being updated in P05.

Prepare data with your own scripts and tools. The input is a directory containing
the authoritative `Samples.csv` and one immediate subdirectory per sample:

```text
<prepared-directory>/
  Samples.csv
  sample_01/
    Exp_data_UMIcounts.mtx
    Genes.txt
    Cells.csv
  sample_02/
    Exp_data_UMIcounts.mtx
    Genes.txt
    Cells.csv
```

The selected directory need not itself be named `processed_data`. Its sample
folders must match the `sample` column exactly, including capitalization, with
no additional sample folders. Use unique sample identifiers that differ by more
than capitalization. Identifiers cannot contain surrounding whitespace, a
trailing period, path separators, control characters, or Windows-invalid
characters (`< > : " | ? *`). Do not use `.`/`..` or Windows device names such as
`CON`, `NUL`, `COM1`, or `LPT1`, including names such as `CON.txt`.

Use exactly one of these matrix filenames in every sample folder, with the
same filename/scale throughout the dataset:

| Filename | Expression values |
| --- | --- |
| `Exp_data_UMIcounts.mtx` | Untransformed, finite, non-negative integer counts |
| `Exp_data_TPM.mtx` | Finite, non-negative TPM values, not log-transformed |
| `Exp_data_CPM.mtx` | Finite, non-negative CPM values, not log-transformed |

Multiple supported matrices in one sample or mixed scales between samples are
ambiguous and rejected by the structure checker. Existing workspaces can retain
their configured `std_names` filenames; new inputs use the names above.
Prepared input contents must be ordinary files and directories. Resolve child
symbolic links into copied files/directories before importing, so the workspace
does not depend on linked source data.

### Sample metadata: Samples.csv

Supply CSV with a header and at least one sample row, using UTF-8 for non-ASCII
text. Every column below is required, but unknown metadata values may be blank.
`sample` must always be non-empty and unique. Supply `n_cells` as the final
standardized cell count for that sample, rather than a count from a publication.
The structure checker checks header presence, not cell-count values.

```text
sample,technology,cancer_type,patient,histology,site,sample_type,
sample_primary_met,disease_extent,diagnosis_recurrence,instance_at_site,
treated_naive,age,sex,grade,AJCC_stage,AJCC_T,AJCC_N,AJCC_M,size,
smoking_status,PY,KI67,genetic_hormonal_features,chemotherapy_exposed,
chemotherapy_response,targeted_rx_exposed,targeted_rx_response,
post_sampling_rx_exposed,post_sampling_rx_response,time_end_of_rx_to_sampling,
ET_exposed,ET_response,ICB_exposed,ICB_response,PFS_DFS,OS,n_cells
```

The header list is wrapped here for readability; write it as one CSV record.
Column order is unrestricted, headers must be unique and use the spelling shown,
and additional user columns are preserved. Quote values containing commas,
double quotes, or newlines using normal CSV quoting. For example, a site value
can be `"Colon, ascending"`, and a quote within a quoted field is doubled.

All columns are read as text, preserving identifiers such as `001` and `0007`.
Empty fields represent unknown values; literal `NA` is text. CSV row order
determines sample order. `Samples.csv` is the runtime metadata authority,
including when an older `samples_config.yaml` disagrees. Users do not need to
provide that YAML to load a standardized workspace. Cancer type names used for
marker matching must match the resource vocabulary (for example,
`Colorectal Cancer`); unknown values can be blank.

### Matrix, gene, and cell alignment

These preparation requirements are the user's responsibility:

- Write each expression matrix in Matrix Market format with genes as rows and
  cells as columns. Do not log-transform it; the app performs its downstream
  normalization and transformation.
- `Genes.txt` contains one non-empty, unique gene symbol per line, without a
  header. Its line order matches matrix row order. Map identifiers to the gene
  symbols used by the app's biological resources; combine duplicate mapped
  symbols by summing their expression rows before exporting.
- `Cells.csv` has one row per matrix column, in exactly that column order, and
  includes `cell_name`, `sample`, `cell_type`, `complexity`, `cell_subtype`,
  `patient`, `subclone`, and `source`. Extra columns are permitted.
- `cell_name` is non-empty and unique across the entire dataset; prefix reused
  barcodes with their sample ID. Every cell's `sample` matches its directory.
- `complexity` is the number of detected genes (nonzero matrix values) for that
  cell, not its total count. Supply a finite, non-negative value for every cell.
- Unknown annotations (`cell_type`, `cell_subtype`, `subclone`) may be blank.
  `patient` holds the patient identifier, and `source` the anatomical sample
  site; keep these consistent with sample metadata when known.

The lightweight **input structure check** reads only the sample CSV and checks
headers, identifiers, exact folder membership, expected filenames, readability,
and non-empty files. It does not read matrices, genes, or cells, compare their
dimensions/order, verify counts/complexity, or establish scientific correctness.
Correctly named non-empty files can therefore pass while containing invalid
data. Existing analysis-time errors and scientific cache checks remain separate.
Archived workspaces with damaged retained sample files remain available for
read-only review when their sample CSV is valid. Existing archive audits still
block editing and unsafe exports.

Preparation scripts, raw data, the checklist in `docs/`, and the optional metadata
extraction prompt in `resources/` are not part of the new required input. Users
may use any preparation workflow. Keep original prepared files: the import flow
will copy them into a workspace, where annotation saves can update `Cells.csv`.
Create a new workspace for replacement inputs rather than replacing underlying
data partway through analysis.

The reusable checker can be called from an R session after sourcing the app
utilities: `check_prepared_data(path)` returns `valid`, an aggregate `message`,
structured `errors` (`code`, `sample`, `path`, `message`), text `samples`, detected
`std_names`/`expression_type`, and `paths_list` in CSV order only on success.
For an existing workspace, pass its filename list as `std_names`. The checker
does not write files, update workflow state, or cache a validation result.

## Creating a Dataset

1. Prepare a directory following the [input specification](#preparing-input-data).
2. Select **Create New Dataset**, enter a dataset name, and select the prepared
   directory and an existing workspace parent directory.
3. Use **Browse** to navigate directories, or enter paths directly. The in-app
   browser supports going to a path, opening a subdirectory, moving up, and
   returning to Home or Datasets. **Use this directory** updates the chosen
   field without resetting the rest of the form.
4. Review the resolved source and workspace paths, then select **Create Dataset**.
   The app checks structure, shows any problems together in the creation dialog,
   and copies the inputs with byte/elapsed-time progress. Correct errors and retry
   without filling the whole form again. **Cancel** creates no workspace.
5. The app opens the completed workspace immediately. Use **Select Samples for
   Clustering** to begin analysis; no app shutdown or standardization script is
   required.

Paths refer to the machine running R, on both Windows and Linux. For a remotely
hosted app, first make the prepared files accessible on the server (for example,
through a mounted directory); this browser does not upload files from a separate
client computer.

The workspace is created at `<parent>/<dataset_name>/`, containing a copied
`processed_data/`, generated analysis/selection/workflow/storage configuration,
and `cache/`, `results/`, and `logs/`. Initial input readiness records a structural
check, with analysis stages not started. The app does not create `data/`,
`standardize.R`, `samples_config.yaml`, or a checklist copy. It never overwrites
an existing workspace or moves the original inputs. A failed copy is not
published; interrupted staging directories are excluded from dataset discovery.

Use the configured datasets directory (default `datasets/`) as the parent for
discovery after restarting the app. An import under another parent opens
immediately and stays selectable for the current session; that external path is
not saved to application configuration. Dataset names must be distinct among
the workspaces available in that session.

The checklist in `docs/`, preparation templates, and metadata extraction prompt
in `resources/` are optional files for use outside the app. No prompt, checklist,
or preparation-template usage is required for startup, import, or analysis.
The app has no standardization guide or metadata-prompt screen. Review snapshots
still have their legacy sample-YAML provenance requirement until P05.

For an existing dataset, load it and follow the Start Menu's pipeline overview.
Use **Select Samples for Clustering** to rerun only the required samples.
If a stopped run still appears in progress, follow
[interrupted-clustering recovery](docs/PIPELINE_STATE.md#interrupted-clustering).
Save annotations explicitly; pending edits are not counted as saved progress.
CNA can be explicitly omitted per sample. Cleanup and reopening are separate
storage actions; see [Pipeline State](docs/PIPELINE_STATE.md#archived-datasets).

## Testing

The repository includes `testthat` unit, integration, regression, and golden-output tests using deterministic synthetic fixtures.

Keep permanent regression tests in `tests/testthat/`. One-off local validation
runners, diagnostic scripts, logs and generated result files belong in
`artifacts/local-checks/`, which is gitignored. Run these local scripts from the
repository root; keep `datasets/` for scientific workspaces and their runtime
data.

Run the complete test suite from the repository root:

```r
devtools::test()
```

or:

```bash
Rscript tests/testthat.R
```

The suite focuses on behavioral/workflow coverage across I/O, validation, preprocessing, clustering, differential expression, annotation, caching, CNA analysis, and regression protection.

The browser baseline uses `shinytest2` with a configured Chromium-based browser.
It creates a deterministic synthetic dataset, resources, caches, and workflow
state inside a temporary app directory, so it does not require or modify any
local dataset. It is skipped only when the browser/testing dependency is
unavailable. To run it explicitly from R:

```r
testthat::test_file("tests/testthat/test-app-ui-baseline.R")
```

Browser journeys exercise recovery, computation, saves and reset only in
disposable synthetic workspaces. The archive/reopen status replay republishes
deterministic numerical fixtures between real GUI decisions and saves. All
state/log/cache changes stay in these temporary workspaces. Approved
platform-specific screenshots are stored under
`tests/testthat/fixtures/ui-baseline/`; platforms without a reviewed screenshot
set still run all functional browser assertions.

See the [Testing](docs/USER_GUIDE.md#testing) section for the test-file breakdown and coverage summary.

See [Release Acceptance](docs/development/RELEASE_ACCEPTANCE.md) for the complete portable
automated gate and scenario-to-test map.

Development plans and manual review/replay records are indexed in
[Development Documentation](docs/development/README.md).

## Repository Notes

* `datasets/` contains local runtime data and should remain outside version control.
* Most biological resource files under `resources/` are also intentionally untracked.
* `general_config.yaml`, source code, templates, tests, documentation, and the committed CNA golden fixture are version-controlled.
* The app uses validated, dependency-aware `.qs2` caches for expensive intermediate results; see [Cache Validity and Invalidation](docs/CACHE_VALIDITY.md).

## Documentation

The detailed documentation is maintained in:

[**docs/USER\_GUIDE.md**](docs/USER_GUIDE.md)

The latest per-step workflow-state contract is described in
[**docs/PIPELINE\_STATE.md**](docs/PIPELINE_STATE.md), while the complete
append-only processing history is described in
[**docs/PIPELINE\_LOGGING.md**](docs/PIPELINE_LOGGING.md). Cache manifests,
dependency fingerprints, recovery, and migration are described in
[**docs/CACHE\_VALIDITY.md**](docs/CACHE_VALIDITY.md). The reproducible release
gate is described in
[**Release Acceptance**](docs/development/RELEASE_ACCEPTANCE.md).

It covers:

* repository and dataset structure;
* configuration;
* biological resource files;
* dataset creation;
* standardization;
* the analysis workflow;
* testing and coverage;
* cache invalidation;
* pipeline assumptions;
* known limitations.

