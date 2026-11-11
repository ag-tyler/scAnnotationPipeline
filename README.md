# scAnnotationPipeline

A Shiny application for clustering, differential-expression analysis, manual cell-type annotation, and copy-number alteration (CNA) analysis of prepared single-cell RNA-seq cancer datasets.

The pipeline guides a dataset through:

1. **Import prepared data** – copy an externally prepared directory into an independent workspace and open it immediately.
2. **Clustering** – PCA → UMAP → Louvain clustering across multiple resolutions.
3. **Resolution selection** – choose the clustering resolution used downstream.
4. **Differential expression** – rank genes per cluster and compare them with known marker sets.
5. **Manual annotation** – assign cell types using DE marker matches and signature scores.
6. **CNA analysis** – infer copy-number alterations and classify malignant cells/subclones.

Prepare data with your own tools using the [input specification](#preparing-input-data). The [optional checklist](docs/STANDARDIZATION_CHECKLIST.md) helps with preparation questions. For configuration, resources, analysis, testing, and optional preparation helpers, see the [**User Guide**](docs/USER_GUIDE.md).

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

Prepare inputs before creating a dataset in the app. Use any scripts or tools
that produce the files specified below. Sample membership, order, and metadata
come exclusively from `Samples.csv`; preparation scripts and sample YAML are
optional. Import checks structure and opens a copied workspace for analysis.

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

### Preparing a smaller demonstration dataset

Use `scripts/downsample_processed_data.R` to create a separate import-ready
subset from an existing `processed_data` directory. From the repository root:

```r
source("scripts/downsample_processed_data.R")
downsample_processed_data(
  input_dir = "datasets/Tang2026_Colorectal/processed_data",
  output_dir = "datasets/Tang2026_Colorectal_demo_input",
  n_cells = 3000,
  samples = c("CRC_T3", "CRC_LM3"), # NULL includes every sample
  stratify_by = "cell_type",
  min_genes = 500,
  reset_annotations = TRUE,
  seed = 3988
)
```

Alternatively, edit the `settings` list at the top of the script and run
`Rscript scripts/downsample_processed_data.R`, or source it and call
`do.call(downsample_processed_data, settings)`.

The cell cap applies **per sample after filtering**. Smaller samples retain all
eligible cells. The default filter matches the app's default minimum of 500
expressed genes; set `min_genes = 0` to sample all input cells. Counts and genes
are preserved, with matrix columns and cell rows kept in their original order.
Each selected sample gets a folder and a matching `Samples.csv` row with its
updated `n_cells`; other sample metadata is retained. A root-level
`downsampling_report.csv` records input/eligible/output counts and settings.

Sampling allocates cells proportionally to existing cell types, then randomly
samples without replacement within each type. Integer rounding can omit rare
types; there is no minimum quota or deliberate enrichment. Set `stratify_by =
NULL` for uniform sampling or supply multiple column names for finer strata.
Blank labels form their own stratum. Selection is reproducible for the same
input order, sample selection, settings and seed.

After sampling, annotation reset blanks `cell_type`, `cell_subtype`, `subclone`
and `cell_type_pre_cna` where present, and removes prior `clust`, `umap1` and
`umap2` columns. Extend `annotation_columns` to include any additional annotation
fields in your input. Set `reset_annotations = FALSE` to retain them. No caches,
workflow state or results are copied. The input is unchanged, existing output
folders are refused, and failed runs do not publish partial datasets. Import
the output folder using the app's new-dataset workflow.

### Saving resumable presentation checkpoints

After saving edits, finishing all computations and **stopping the app**, use
`scripts/copy_dataset_checkpoint.R` to preserve an active workspace at its
current pipeline stage:

```r
source("scripts/copy_dataset_checkpoint.R")
copy_dataset_checkpoint(
  source_dir = "datasets/Tang_Demo_Working",
  output_dir = "datasets/Tang_Demo_01_Clustered"
)
```

Run from the repository root, or supply `app_dir` explicitly. Alternatively,
edit `checkpoint_settings` at the top of the script and run
`Rscript scripts/copy_dataset_checkpoint.R`. The output folder name becomes
the new dataset ID. Choose a new destination every time; existing folders and
destinations nested inside the source are refused.

The script copies the entire workspace, including processed inputs, results,
caches, recovery backups, notes and logs. It updates dataset IDs in configuration
and state, redirects cache input paths to the copy, and adjusts recorded file
timestamps to the destination filesystem's actual precision. Scientific cache
fingerprints, sample IDs, saved decisions and pipeline statuses remain unchanged.
Historical logs and preparation scripts keep their original contents and paths.
A `checkpoint_copy.yaml` records the new workspace's origin and verification.

Before publishing the destination, it verifies copied file checksums, reads and
structurally validates caches one at a time, checks their recorded file/upstream
dependencies, and checks that the app's workflow reconciliation would not make
completed stages stale. It also verifies that the source remained unchanged.
This is an integrity/resume check, not a new scientific analysis or a guarantee
that different app versions/resources will produce identical results. The source
is never repaired or changed. Invalid/stale caches, running stages, links,
temporary operation files, and archived or mid-cleanup sources are rejected.

For this showcase, preserve checkpoints after clustering, DE, base CNA, and
finalization. Continue in a working copy and keep master checkpoints untouched;
use another copy of the finished master to demonstrate cleanup. Every sample
in the finished version must have CNA finalized or explicitly omitted.

If transferring a workspace between computers, copy its complete folder first
and then run this script on the destination computer to create the usable
checkpoint. Standardized expression/gene dependencies are automatically mapped
from old Windows or macOS paths. For other recorded internal file dependencies,
provide `original_source_dir = "C:/old/location/OriginalDataset"` (the old path
does not need to exist). Content checks still apply. Reopen the app and select
the new checkpoint; verify the intended screens on the presentation Mac.

These are resumable **workspace copies**. The app's **Review Snapshot** export
is a separate feature and deliberately excludes resumable caches.

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

For example, the following valid CSV records illustrate leading zeros, a quoted
anatomical site, an unknown value, and an extra user column. Include the other
required columns from the header list above in your actual file:

```csv
sample,patient,site,n_cells,extra_note
sample_01,0007,"Colon, ascending",1200,"Source calls this ""primary"""
sample_02,0007,,950,
```

The optional [metadata extraction prompt](resources/metadata_extract_prompt.txt)
can help gather publication metadata. It returns a draft CSV with `n_cells`
blank; fill that column from your final prepared cell tables before importing.
Review the draft against the source and your actual sample membership. Neither
AI use nor a prompt completion record is required.

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

For example, a source path could be `C:/data/Study prepared` on Windows or
`/home/user/data/Study prepared` on Linux. Spaces are supported. Use a path that
exists on the R host; a Windows client path does not identify files on a remote
Linux server.

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
also work without sample YAML, preparation scripts, or checklist files; existing
preparation provenance is included when available, without warnings for absence.

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
* prepared inputs and optional standardization helpers;
* the analysis workflow;
* testing and coverage;
* cache invalidation;
* pipeline assumptions;
* known limitations.

