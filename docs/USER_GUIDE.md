# scAnnotationPipeline User Guide

This guide contains the detailed operational and technical documentation for `scAnnotationPipeline`.

For installation and a concise project overview, see the repository **[README](../README.md)**.

## Table of Contents

- [Repository Structure](#repository-structure)
- [Configuration](#configuration)
- [Resource Files](#resource-files)
- [Setting Up a New Dataset](#setting-up-a-new-dataset)
  - [`dataset_config.yaml`](#dataset_configyaml)
  - [`Samples.csv`](#samplescsv)
  - [`selected_config.yaml`](#selected_configyaml)
- [Optional Preparation Helpers](#optional-preparation-helpers)
- [Running the Analysis Pipeline](#running-the-analysis-pipeline)
- [Pipeline Event Logs](#pipeline-event-logs)
- [Pipeline State](#pipeline-state)
  - [Archiving a finished dataset](#archiving-a-finished-dataset)
  - [Creating a review snapshot](#creating-a-review-snapshot)
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

The application root contains the Shiny app, configuration, resources, datasets,
templates, utility scripts, documentation, and tests. This is a representative
layout; the test and utility listings are not exhaustive:

```text
scAnnotationPipeline/
├── app.R                              # Bootstrap entry point
├── app/                               # Context, state, UI and server components
├── R/                                 # Disables implicit Shiny autoload
├── .gitignore
├── general_config.yaml                # Shared application configuration
├── DESCRIPTION
├── README.md
│
├── docs/
│   ├── PIPELINE_LOGGING.md
│   ├── PIPELINE_STATE.md
│   ├── CACHE_VALIDITY.md
│   ├── STANDARDIZATION_CHECKLIST.md
│   ├── TESTING.md                      # Current verification instructions
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
│       ├── selected_config.yaml
│       ├── pipeline_state.yaml
│       ├── storage_state.yaml
│       ├── cache/
│       ├── processed_data/
│       ├── results/
│       └── logs/
│
├── templates/
│   ├── dataset_config_template.yaml
│   └── standardize_general.R            # optional preparation tool
│
├── scripts/
│   ├── run_app.R
│   ├── downsample_processed_data.R
│   └── copy_dataset_checkpoint.R
│
├── util_scripts/
│   ├── 01_utils_io.R
│   ├── 02_utils_annotation.R
│   ├── 03_utils_misc.R
│   ├── 04_utils_caching.R
│   ├── 05_utils_workflow.R
│   ├── 06_utils_logging.R
│   └── 07_utils_state.R
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
        ├── test-06_utils_logging.R
        ├── test-07_utils_state.R
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

The default workspace location is:

```text
datasets/<dataset_id>/
```

New imports can use another parent; those external paths remain registered only
for the current session. A new imported workspace contains:

```text
datasets/<dataset_id>/
├── dataset_config.yaml
├── selected_config.yaml
├── pipeline_state.yaml
├── storage_state.yaml
├── cache/
├── processed_data/
│   ├── Samples.csv
│   └── <sample_name>/
│       ├── Exp_data_<matrix_state>.mtx
│       ├── Genes.txt
│       └── Cells.csv
├── results/
│   └── <sample_name>/
│       ├── 1_cluster_plots/
│       ├── 2_de_plots/
│       ├── 3_cna_plots/
│       └── 3_cna_results/              # Optional CNA values exports
└── logs/
    ├── pipeline_events.jsonl
    └── pipeline.log
```

The matrix filename depends on `std_names.expmat` in `dataset_config.yaml`.
The paths shown use the default configuration. `storage_state.yaml` is
initialized when needed, and archived datasets intentionally have no `cache/`.
New imports initialize workflow/storage state immediately. Existing workspaces
may also contain raw `data/`, `samples_config.yaml`, `standardize.R`, and checklist
notes. These are optional preparation provenance, left untouched on load; new
imports do not generate them.

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

The remaining configuration sections define filenames and dataset subdirectories.
Legacy raw-data and sample-YAML paths support optional preparation helpers; they
are not required user inputs for app import or loading. The dataset analysis
template remains required by import; preparation script templates are optional.

| Key | Purpose |
|---|---|
| `paths.resources_dir` | Resource directory relative to the application root |
| `paths.datasets_dir` | Dataset directory relative to the application root |
| `resource_files.*` | Expected filenames inside `resources/` |
| `dataset_paths.*` | Workspace subdirectories (`processed_data`, `results`, `logs`); raw `data` is optional helper input |
| `config_files.*` | Standard configuration filenames |

The intended standard values for the two top-level directories are `resources` and `datasets`.

---

## Resource Files

The pipeline expects biological/reference data under:

```text
resources/
```

Expected filenames are configured under `resource_files` in `general_config.yaml`.

Only `metadata_extract_prompt.txt` is currently intended to be tracked with the repository. The remaining resource files must be obtained/generated separately and placed into `resources/`.

Biological resource files are validated at app startup. Missing required resources
stop startup with an explicit list of paths. The metadata extraction prompt is
an optional external aid; its file and configuration key are not read by the app.

| Config key | Default filename | Tracked? | Purpose / expected format |
|---|---|---:|---|
| `metadata_prompt` | `metadata_extract_prompt.txt` | Yes | Optional external metadata-extraction aid; not displayed or required by the app |
| `hgnc_complete_set` | `hgnc_complete_set.txt` | No | HGNC reference used for Ensembl→symbol and genomic-location mapping; requires fields including `ensembl_gene_id`, `symbol`, and location information |
| `gene_positions` | `gene_positions_biomaRt_0626.csv` | No | Genomic positions for CNA ordering; requires `ensembl_gene_id`, `chromosome_name`, `start_position`, `hgnc_symbol` |
| `marker_sets` | `global_cell_type_markers.csv` | No | Marker sets used for DE matching/signature scoring; required columns: `cell_type`, `symbol` (or legacy `gene`), `combined` |
| `malignant_markers` | `malignant_markers.csv` | No | Cancer-type-specific malignant markers; required columns: `cancer_type`, `symbol` (or legacy `gene`), `combined` |
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

Prepare the sample directories and authoritative `Samples.csv` using your own
scripts. The complete format is documented in the
[README input specification](../README.md#preparing-input-data).

Use **Create New Dataset**, enter a dataset name, and select the prepared-data
directory and an existing workspace parent. Browse folders using the in-app
directory browser or enter paths directly. Paths refer to the machine running R,
including when the app is hosted remotely. Review the resolved paths and select
**Create Dataset**. Structural errors remain visible for correction and retry.

The app copies the prepared files, generates its configuration/state, and opens
the workspace ready for clustering. Originals stay unchanged; existing
workspaces are not overwritten. No app restart, raw-data folder, preparation
script, sample YAML, or checklist is required for creation or analysis.

The default parent is the configured `paths.datasets_dir` (normally `datasets/`),
which supports discovery after a restart. Imports under another existing parent
open immediately and remain selectable in the current session; those external
locations are not saved to application configuration.

Preparation references remain optional files in `docs/`, `templates/`, and
`resources/`. Open the checklist directly from `docs/` when useful. The app has
no standardization/checklist tab, Markdown viewer, metadata-prompt screen, or
checklist-copy action. Existing dataset scripts and checklist notes are retained.

After loading, use the Start Menu's prepared-input readiness and analysis
progress overview. Structural checks do not audit expression values, dimensions,
or gene/cell alignment; those remain preparation responsibilities. Review
snapshots also work without sample YAML, preparation scripts, or checklist files.

### `dataset_config.yaml`

This file is copied from:

```text
templates/dataset_config_template.yaml
```

The shared template leaves `project_info.dataset_id` and
`project_info.technology` blank. New-dataset import sets the dataset ID from the
new workspace name and derives technology from `Samples.csv`, leaving it blank
when technologies are mixed or unknown.

For an optional manual preparation workspace, set `project_info.dataset_id` to
the preparation folder name and fill `project_info.technology` if known in your
copied configuration before running the helper. The template does not require
a `raw_files` section.

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

Workspace selection and the dashboard show an optional reminder when neither
`project_info.source_doi` nor `project_info.source_url` is recorded. Add either
field to `dataset_config.yaml` and reload to clear it. Missing origin does not
prevent import, analysis or review-snapshot creation.

`std_names.*` defines the standardized files expected by the downstream pipeline.

Import detects the matrix scale from the supported filenames and initializes
`std_names` accordingly. Existing workspaces keep their configured filenames.

### `Samples.csv`

The user supplies this authoritative sample table inside the prepared directory.
See the [README contract](../README.md#sample-metadata-samplescsv) for every
required header, blank-value rules, and CSV quoting examples. Include `n_cells`
from final prepared cell tables, even when using publication metadata gathered
with the optional prompt. Other unknown metadata values can be blank.

Sample membership, order, annotation metadata, and marker selection all use this
table. The app reads columns as text, preserving leading zeros and extra fields.
It never regenerates the CSV from YAML or merges conflicting YAML metadata.
Missing CSV is an actionable load error even if legacy sample YAML is present.

For malignant-marker matching, `cancer_type` should exactly match a key under `cancer_types` in `cancer_cell_map.json`.

For example:

```text
Breast Cancer
```

rather than:

```text
Breast
```

The current annotation logic applies a cancer-type-specific malignant marker set
only when the CSV has one unambiguous known cancer type across its samples.
Blank values do not create an additional cancer type. A mixed or unrecognized
type does not cause the app to guess a marker set.

### `selected_config.yaml`

This file is initialized automatically and populated by the app.

It stores state such as:

- selected clustering resolutions;
- CNA reference cell types;
- potentially malignant cell types;
- selected malignant CNA subclusters;
- CNA thresholds;
- per-sample notes shared across resolution, annotation, and CNA screens.

It normally should not be edited manually.

---

## Optional Preparation Helpers

Prepare data using the [README contract](../README.md#preparing-input-data) and
your own scripts. The [Standardization Checklist](STANDARDIZATION_CHECKLIST.md)
is an optional reference for checking alignment and metadata; it is not an app
workflow or required completion record.

The optional [metadata prompt](../resources/metadata_extract_prompt.txt) drafts
publication metadata as CSV, not YAML. Review its membership, IDs, and clinical
assignments yourself; the prompt leaves `n_cells` blank. Fill that column from
your final prepared cell tables before import. Neither prompt usage nor a
publication count substitutes for data preparation.

### samples_config.yaml

The retained R preparation helpers use this legacy YAML as their source of
sample metadata. The app's import, loading, analysis, and snapshots do not
require it. For those helpers only, supply a `samples:` list with one entry per
sample, a non-empty unique `sample` key (not `id`), and the metadata keys listed
in the README header except `n_cells`. Include unknown keys with blank values.
The helpers calculate `n_cells` from their final cell tables and write
`Samples.csv`. These YAML requirements belong to helper prevalidation,
`prevalidate_setup()`, rather than ordinary dataset loading.

### Using the retained general R template

`templates/standardize_general.R` remains available if you prefer its workflow.
The app does not copy it, prepare its prerequisites, or ask users to run it.

The general template expects a preparation workspace under the configured
datasets directory. With default configuration, set it up yourself as:

```text
datasets/<preparation_name>/
  dataset_config.yaml     # copy/adapt templates/dataset_config_template.yaml
  samples_config.yaml     # helper-only sample metadata described above
  standardize.R           # manually copy templates/standardize_general.R
  data/                   # raw sources if your code uses the helper's default
```

This is a preparation workspace, separate from the new analysis workspace you
will import into. Keep original raw files unchanged. If general configuration
uses non-default directories/filenames, follow those configured paths.

1. Set `settings$dataset_name` to that preparation folder name, choose
   `UMIcounts`, `TPM`, or `CPM`, and use `app_folder_path = NULL` for automatic
   app-root discovery or supply the intended root explicitly.
2. Keep `reset_selected_config = FALSE`. Complete the linear `BEGIN USER CODE`
   region: load your raw data, map sample/gene IDs, split samples, and construct
   `sample_input` with `expmat`, `genes`, `cells`, and optional keyed
   `cell_metadata`. Call `prepare_standardized_sample()` and
   `register_standardized_sample()` for each configured sample.
3. Review the helper transformations: unmapped gene rows are removed, duplicate
   mapped symbols are summed, optional cell metadata is aligned by `cell_name`,
   sample/patient/source fields are set from YAML, and complexity is calculated
   as nonzero genes per cell. Confirm these choices fit your dataset.
4. Change the saved script's `RUN_STANDARDIZATION <- FALSE` to
   `RUN_STANDARDIZATION <- TRUE`, then run the entire file from a clean R
   session. Setting the flag only in the console is insufficient because the
   script assigns it again when sourced.
5. The helper builds `Samples.csv`, deeply validates its staged output with
   `strict = TRUE`, and publishes `processed_data/` only after
   `POST-VALIDATION PASSED`. Correct failures in your input/mapping code and
   rerun. It also updates that preparation workspace's configuration, selected
   state when absent/reset, workflow state, and logs.
6. Select the finished preparation workspace's `processed_data/` as the source
   for **Create New Dataset**, with a distinct analysis-workspace name/path.
   Import copies only that prepared tree and initializes fresh analysis state;
   it does not import the helper workspace's logs, scripts, or saved decisions.

Do not rerun preparation helpers against an analysis workspace to replace
inputs partway through analysis. Prepare replacement data separately and create
a new imported workspace. Users with their own scripts need none of the
template's YAML, helper calls, strict report, or script sentinel.

---

## Running the Analysis Pipeline

Launch the app from the repository root using the R/Positron console:

```r
source("scripts/run_app.R")
```

This launcher sets `options(shiny.autoreload = FALSE)` before Shiny starts.
Use it for normal pipeline work because the app writes logs, workflow state,
caches, configuration, and plots inside the repository while it runs. With an
IDE development watcher enabled, those expected writes can otherwise cause a
full session reload and return the app to Dataset Selection. No `watcher`
package installation is needed for this launch method.

Direct `shiny::runApp(".")` or IDE **Run App** launches are intended only for
developers who deliberately configure autoreload behavior.

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

**Select Samples for Clustering** opens a checklist with each sample's current
clustering status. All samples are checked initially. Use **Select all**,
**Select stale**, **Select incomplete**, or **Clear**, then adjust individual
checkboxes. Select stale uses only the clustering stage; stale resolution,
DE, annotation, or CNA alone does not request reclustering. Select incomplete
selects clustering `not_started`, `failed`, and `stale` states, excluding active
computations. Any other sample can still be checked manually for an intentional
rerun, except one already running clustering.

Review the selected names/count and downstream-impact message before pressing
**Run clustering for N selected samples**. The action is disabled for an empty
or invalid selection, an archived dataset, another active application action,
or unsaved annotation edits. Dataset, sample identities and resolutions are
checked again before execution. The app processes only the checked samples,
in dataset order, at every configured resolution. Unchecked samples' state,
saved decisions, plots, and cache artifacts are unchanged.

During bulk clustering, an in-app progress overlay reports the current sample
position, sample name, and real processing stage (input filtering, PCA/UMAP,
filtered-expression caching, or the current resolution's clustering/plot/cache
work). The console prints matching sample boundaries, elapsed time, and a final
batch summary. The operation remains synchronous and intentionally has no
misleading Cancel control.

Progress counts only the selected samples. Successful completion lists those
samples; **Go to Resolution Selection** preselects the first processed one for
explicit resolution review/save. Staying on the menu does not change selection.
If a sample fails, the batch remains fail-fast: earlier selected work stays
saved, later work is not run, and unselected work is untouched.

Cluster labels are displayed in natural numeric order throughout resolution
plots, DE summaries, and manual annotation. For example, a 13-cluster result is
shown as `0, 1, 2, ..., 10, 11, 12`, while nonnumeric labels use a stable lexical
order. This is display-only: saved cluster identifiers are not rewritten, and
plot colours are explicitly keyed to their labels.

The Start Menu also provides a secondary **Run Clustering for One Sample**
action for intentional targeted reruns. Select the sample in the confirmation
dialog; the app recomputes all configured resolutions using the same workflow
and progress display as bulk clustering. The selected sample's saved resolution,
DE, annotation, and CNA stages become stale, while other samples remain
unchanged. After completion, continue directly to Resolution Selection with the
processed sample preselected and save its resolution again.

If clustering was interrupted, reload the dataset. The app automatically marks
the attempt failed and retryable when it can verify that its recorded local
execution ended. For older or unverifiable records, use **Recover Interrupted
Clustering** on the Start Menu after confirming the original run has stopped.
Recovery preserves files and attempt history; it does not complete the analysis.
Then rerun the affected samples using the selection checklist. See
[Interrupted clustering](PIPELINE_STATE.md#interrupted-clustering) for details.

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

Bulk differential expression uses the same progress format as clustering. Its
stages distinguish clustered-input/cache loading, DE calculation, marker
matching, scoring/plot generation, and output writing. If either bulk workflow
fails, the notification and structured event identify the sample and last real
stage reached; processing remains fail-fast.

Batch and single-sample DE print sample/stage progress in the R console. Stage
completion lines show both the completed step's duration and cumulative sample
time, measured in elapsed seconds. For example:

```text
[2/3] sample_B | DE | marker_matching | completed | step 1.8s | elapsed 14.2s
```

Single-sample and batch CNA use the same convention for preflight, matrix
computation/cache reuse, and heatmaps. Nested CNA messages name matrix
computation/reshaping/cache writing, Ward clustering, plot construction/writing,
and signal/correlation steps (including the subclone). Cache hits are labeled
as reuse; skips/failures name their outcome instead of claiming completion.
DE and CNA batch summaries include completed, failed, skipped, not-run counts,
and total elapsed time. DE remains fail-fast; batch CNA isolates computation
failures and continues with other samples.

Step durations are reported when a stage finishes or fails, rather than as a
live countdown. Nested timers measure their own operation and overlap the outer
sample/batch timer; do not add them together as independent durations. These
console diagnostics do not add records to persistent event logs or alter
scientific results, caches, or workflow decisions.

On successful DE completion, the dialog reports how many processed samples
still need annotation review and names the first one ready to open, in
processing order. **Go to Manual Annotation** selects that sample rather than
retaining a later sample from the previous review. Completion itself and
**Stay on Start Menu** do not change the selection. The target is checked
again when clicked; if no processed sample currently needs/can enter review,
the current selection is kept with a pipeline-overview cue.

Save or discard unsaved annotation edits before starting bulk DE. The app
checks again at confirmation and refuses completion-navigation jumps while
edits are unsaved. The Start Menu overview remains the complete per-sample
status list. Targeted single-sample DE keeps its existing selected-sample
behavior.

Each per-cluster signature-score PNG displays the complete sample identifier in
a dedicated title, hard-wrapped every 60 characters when needed. Cluster,
resolution, and cell count are kept together in a separate subtitle. These
plots are exported at an explicit 9 x 7 inches and 300 DPI; their existing
`<cluster>.png` filenames remain unchanged for Manual Annotation.

### Manual annotation

The annotation interface loads cached clustered cells together with DE marker matches/signature scores so clusters can be assigned final cell types.

Saved annotations update the corresponding `Cells.csv`. Annotation saving is
independent of the later CNA decision: save the cell types first, then either
save a complete reference/candidate CNA configuration or use **Omit CNA for
This Sample**. Omission is explicit and reversible by saving a complete CNA
configuration later.

The progress strip counts samples with saved, currently valid annotations.
Pending edits are shown separately and do not advance saved progress. A last-
cluster notice means review/preview/save is next; **Sample annotation saved**
confirms persistence. Rerunning upstream work can reduce the saved count until
annotations are reviewed and saved again. Archived datasets show read-only
progress and reject annotation writes.

Annotation dropdowns retain search, keyboard selection and scrolling. Their
expanded menus fit available viewport space, including narrow windows and long
cell-type vocabularies.

If clustering or DE was rerun, a stale annotation can be reopened once DE is
complete. The currently selected sample is retried automatically when its DE
state becomes ready; changing the sample dropdown away and back is not needed.
Saved labels are reused only when their cell identifiers align with the current
clustering cache. CNA configuration and omission are blocked while annotation
edits remain unsaved.

If the selected sample still needs DE after a targeted clustering rerun, use
**Rerun DE for Selected Sample** at the bottom of the Manual Annotation sidebar.
It runs the same guarded single-sample DE workflow available in Resolution
Selection and keeps the current sample selected, allowing annotation to load as
soon as DE completes. Save or discard any unsaved annotation edits first.

### CNA analysis

Use **Omit CNA for This Sample** beside **Reset Sample CNA** to omit the
selected CNA sample from any analysis view. Confirmation names that sample
and explains that CNA decisions/calculation caches are invalidated while saved
annotations, cell labels and historical plots/exports remain. This differs
from Reset, which removes CNA plots and restores pre-CNA labels. Save or discard
annotation edits first; omission is unavailable for archived datasets or while
another operation runs. Cancel leaves the sample unchanged.

Omitted samples return to CNA Pipeline Status, survive reload and are excluded
from the ordinary batch sample list. To include one again, save a complete
reference/candidate configuration in Manual Annotation and recompute CNA;
previous computation/assignment statuses are not restored automatically.

The CNA workflow is guarded by the persisted pipeline state and a shared
sample preflight. Preflight verifies that manual annotation and CNA
configuration are saved, reference and candidate populations are usable,
cached cells align with expression data, expression values are finite, and
enough genes have genomic positions. An ineligible sample is blocked or
skipped with an actionable reason instead of entering a numerical failure.

1. Select reference and potentially malignant cell types. If CNA is genuinely
   not applicable, save an explicit omission; missing configuration remains
   incomplete rather than being treated as skipped.
2. Compute inferred CNA profiles for one sample or a selected batch. Batch runs
   preflight samples independently, continue after per-sample failures, report
   completed/skipped/failed groups, and can resume only unfinished samples.
3. Cluster candidate malignant/unassigned cells. Canonical zero-padded cluster
   IDs are shared by the heatmap legend, selector, configuration, and preview,
   including runs with more than ten clusters. A sample without a saved cut
   starts at k = 7, capped by its tree size. A saved current cut restores its
   exact k and cluster IDs; larger saved cuts expand the control range. Changing
   k clears the selection, including when changing back, so IDs from different
   cuts are never reused implicitly. Switching samples restores that sample's
   saved cut or fresh default, rather than another sample's unsaved edit.
4. Select malignant subclone candidates and compute CNA signal/correlation
   metrics. Progress reports the current stage and real sample/subclone counts.
5. Choose malignant/non-malignant thresholds on one shared y-axis. An unsaved
   view starts at 0.5; a saved view restores its display maximum. The available
   plot-axis range accounts for the data and saved thresholds. Y-threshold
   sliders normally extend to 1.0, independently of signal outliers and plot
   scale, and expand to keep higher saved thresholds representable. Their
   existing linked bounds still enforce the threshold ordering. Display
   clipping is indicated and never changes
   assignments. Default threshold increments are 0.05 for X and 0.01 for Y;
   saved values retain finer precision when necessary. Ticks mark selectable
   increments and stay aligned as linked bounds change.
6. Open **Assign & Summary**. A current fingerprinted preview is generated or
   safely reused automatically, defaults to the scatter comparison, and also
   provides the summary heatmap plus saved pre-CNA and proposed post-CNA UMAPs.
7. Save only while the preview fingerprint still matches the current inputs.
   Use **Reset Sample CNA** before deliberately rerunning a sample; this removes
   dependent CNA artifacts and resets downstream state. Saved reference and
   potentially malignant cell-type settings remain; saved Ward cluster
   selections and thresholds are cleared.

A cell satisfying malignant thresholds for exactly one subclone receives that subclone ID.

Each threshold card keeps three short rules visible: above both malignant
thresholds, configured potentially malignant or Unassigned/NA cells become
Malignant; below both non-malignant thresholds for every tested subclone, cells
retain their prior annotation; other tested, non-Malignant cells become
Unassigned/NA. **Boundary details** expands the strict comparison and equal-Y
explanation. A cell exactly on a shared Y boundary meets neither Y condition
for that subclone. Expanding this note changes no slider values or assignments.

A cell satisfying malignant thresholds for more than one subclone remains:

```text
cell_type = "Malignant"
subclone = NA
```

because malignancy is supported but the subclone assignment is ambiguous.

---

## Pipeline Event Logs

Each dataset has an append-only event history under `logs/`. The structured
`pipeline_events.jsonl` file records stage starts, completions, saved decisions,
failures, skips, and cache reuse/invalidation. The companion `pipeline.log` is
formatted for quick human inspection.

Events include their UTC timestamp, dataset, optional sample, stage, event
type, outcome, relevant parameters, and an actionable reason for failures or
skips. They deliberately exclude expression matrices and cell-level data.

See [Pipeline Event Logging](PIPELINE_LOGGING.md) for the schema, event catalog,
and R reader API.

---

## Pipeline State

Each dataset has a versioned `pipeline_state.yaml` containing the latest
dataset- and sample-level workflow statuses. The UI uses it for badges,
prerequisite guards, repeated-run attempts, and dependency-driven stale flags;
the presence of one cache file is not treated as proof of completion.

This current-state document is intentionally separate from
`selected_config.yaml` and the append-only event logs. See
[Pipeline State](PIPELINE_STATE.md) for status meanings, dependencies, legacy
migration, and recovery behavior.

The retained dataset key `standardization` appears as **Prepared inputs**. For
imports it records successful structural checking and installation, with
`validation_scope: structure_only`; it does not assert scientific validation.
Sample analysis starts at `not_started`, and reloads preserve scientific progress.

### Archiving a finished dataset

The Start Menu includes a **Dataset Storage** card. Once all samples are
finished and their durable outputs are verified, choose **Review Dataset
Cleanup** to see the exact cache file count, estimated space recovery, retained
files, and any remaining requirements. Cleanup requires typing the dataset ID.

The action removes only reconstructible files under that dataset's `cache/`.
It retains processed data, final `Cells.csv` files, result tables and plots,
configuration, logs, pipeline state, and any reusable CNA values exports.
A sample where the user explicitly chose **Omit CNA** is considered finished.
CNA values-table export is optional: finalization saves assignments and plots,
and **Export/Re-export CNA Values Table** creates the table separately.

Missing or outdated values exports do not block cleanup. The storage card and
cleanup confirmation list the affected completed CNA samples and warn that,
after removing caches, exporting their values later requires reopening the
dataset and recomputing CNA. Existing exports remain in results, including
older exports; cleanup never deletes them. Scientific completion statuses do
not depend on whether the optional table was exported.

After cleanup, the dataset is an archived, read-only result set and the pipeline
overview keeps its scientific completion statuses. If a retained output later
goes missing or changes size, the storage card reports archive damage. Use
**Reopen Dataset for Editing** only when recomputation is intended: archived
results remain, but the deleted caches cannot be restored and affected stages
are marked stale.

---

### Creating a review snapshot

Use **Start Menu → Dataset Storage → Create Review Snapshot** after every
sample has completed clustering, resolution, DE and annotation, with CNA either
finalized or explicitly omitted. Required standardized inputs, annotation plots
and final outputs must still exist. Save/discard edits and finish running work
first. The card shows only whether creation is possible, not whether a previous
copy exists. Finished active and cache-cleaned/archived datasets are supported;
copying never cleans caches, reopens a dataset or changes scientific statuses.

1. Enter an **existing destination directory outside the app-managed datasets
   directory**. Use a reasonably short path, especially on Windows. Relative
   destinations start from the directory shown in the dialog (normally the
   application root).
2. Choose **Folder**, **Compressed archive (.zip)** or **Both**. Both produces
   identical scientific contents in an independent folder and ZIP.
3. Choose **Include logs** (default on) and **Include existing CNA values**
   (default off). These are the only content choices; all ordinary plots remain.
4. Click **Review Contents**. Check the resolved destination directory, included
   relative paths, omissions, source bytes and the conservative extra-space
   estimate, then acknowledge warnings. Long paths wrap and remain fully
   selectable. Changing the destination requires another review.
5. Click **Create Verified Snapshot**. Progress reports copy bytes, verification,
   compression/readback and elapsed time. Wait for **Review snapshot verified**.

The output contains:

- `processed_data/`: the complete standardized input tree, byte-for-byte,
  including cells filtered out during app preprocessing. Cells removed before
  standardization cannot be recovered. Files are not reconstructed from caches.
  The authoritative `Samples.csv` is included unchanged, alongside current
  `Cells.csv` files and prepared matrices/genes.
- `results/`: all ordinary results and plots, including alternatives/diagnostics.
  Only recognized optional CNA-values payloads and matching sidecars follow the
  CNA-values switch; no scientific computation is started.
- Optional `logs/`, including existing text and structured event logs. They
  capture the export-start point; the final success event is in the source logs.
- `provenance/`: historical dataset/selected configuration and pipeline state,
  plus sample YAML and preparation script/checklist when present. Absent optional
  preparation files do not produce warnings. This state is not live
  cache evidence and must not be treated as an active app workspace.
- `README.md`, `annotation_summary.csv`, `filtering_summary.csv` and
  `snapshot_manifest.yaml` (relative paths, sizes and MD5 checksums, excluding
  the manifest itself). MD5 detects accidental corruption, not malicious edits.

Raw data, caches, backups, temporary/lock files, machine-specific configuration
and prior snapshots are excluded. The package is not a full backup, anonymized
data or a resumable workspace. Exact cached UMAP coordinates/cluster membership
are not exported as new per-cell tables. Existing historical paths in source
scripts/configs/logs are not rewritten.

Annotation counts distinguish **all standardized cells** (possibly unreviewed
source labels) from **pipeline-analyzed cells**, including Unassigned/NA and
subclones. New successful clustering and annotation/CNA saves retain small
versioned aggregate statistics. Filtering counts describe app preprocessing,
not earlier standardization. For legacy, failed/stale or changed generations
without reliable statistics, `NA` and warnings mean **unavailable**, not zero.
Missing aggregate history does not block a snapshot or trigger matrix loading.

To supply dataset origin, optionally add these fields to `dataset_config.yaml`:

```yaml
project_info:
  dataset_id: "Your_Dataset"
  technology: "10x"
  source_doi: "10.1234/example"
  source_url: "https://example.org/dataset"
```

The README uses the supplied DOI/link without online lookup. Missing origin
information is reported as “not provided”; editing these descriptive fields
does not invalidate scientific caches.

When CNA values are requested, only complete exports with matching content and
current provenance are copied. After cleanup, verified retained-output evidence
can establish eligibility without retired caches. Missing, outdated, partial or
unverifiable pairs are omitted with sample-specific warnings to acknowledge.
Explicitly omitted-CNA samples need no values table. Export CNA values separately
before cleanup if you want them; snapshots never recompute or refresh them.

Copying uses bounded binary blocks. ZIP creation runs in a worker, and archives
are fully extracted/read back and checksummed before publication. Reserve about
one payload copy for Folder and up to three payload copies for Archive/Both
during staging/verification, plus metadata overhead; compression savings are not
assumed. Native Windows R/library path limits still apply: oversized paths are
rejected with a request for a shorter destination/name, not silently truncated.
Folder names are unique and existing outputs are never overwritten.

Ordinary errors or R interrupts roll back only this operation's new staging and
partial publication; the source and previous copies stay intact. Unicode cleanup
uses UTF-8 filename handling and then restores the session's previous locale.
If an OS error prevents removal, the app reports that cleanup could not be
completed and partial outputs may remain; inspect the chosen destination before
retrying. A forced OS/R
process termination can leave hidden `.review-snapshot-*` staging directories;
these are not successful exports. Inspect only the known destination if recovery
is needed. Do not manually delete source/cache directories to resolve an export.

The destination appears only in the transient dialog. Export logs record when,
what, options/counts/bytes and outcome, without the destination. No saved-copy
registry, ongoing audit or exported/current/outdated pipeline status is created;
moving or deleting a copy later does not affect the app.

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

For the latest recorded verification and its two known screenshot failures,
see [Recorded verification status](TESTING.md#recorded-verification-status).

Some tests deliberately exercise validation/error/warning paths. Those conditions are captured by expectations and therefore should not appear as uncaught suite warnings.

### Development profiling

The optional interaction and synthetic CNA-export profilers are maintained with
the [development tools](https://github.com/ag-tyler/scAnnotationPipeline/tree/development/scripts).
Use a development checkout and follow each script's usage instructions. App
runtime performance regression tests remain in the ordinary test suite;
the separate profiler contract is documented in the
[development index](https://github.com/ag-tyler/scAnnotationPipeline/blob/development/docs/development/README.md).

### Test structure

| Test file | Main responsibility |
|---|---|
| `test-01_utils_io.R` | Required-file handling and loading of genes, sparse matrices, cell/sample metadata, and related I/O |
| `test-02_utils_annotation.R` | Filtering, normalization, PCA/UMAP/Louvain helpers, and core annotation utilities |
| `test-02_utils_annotation_de.R` | DE ranking, `num_genes`, exact marker matching, `max_match_genes`, marker filtering, minimum-marker checks, signature-score alignment |
| `test-02_utils_annotation_cna.R` | CNA-specific helpers including hierarchical clustering, CNA UMAP/HDBSCAN behavior, and plot construction |
| `test-03_utils_misc.R` | Dataset-name sanitization, duplicate sparse rows, Ensembl-symbol mapping, configuration setup, sample/cell construction, pre/post-validation |
| `test-04_utils_caching.R` | Manifest persistence, dependency matching, structural validity, atomic replacement, recovery, invalidation, and clearing |
| `test-05_utils_workflow.R` | DE workflow orchestration, cached DE outputs, multi-sample routing, annotation setup |
| `test-05_utils_workflow_clustering.R` | End-to-end clustering orchestration, clustering caches, generated plots |
| `test-05_utils_workflow_cna.R` | CNA thresholds, collision behavior, signal/correlation, batch branches, heatmap/clustering integration, preview behavior |
| `test-05_utils_workflow_cna_preflight.R` | CNA eligibility, persisted omission, reference/candidate counts, finite inputs, and positioned-gene requirements |
| `test-06_utils_logging.R` | Structured/readable event persistence, append behavior, required failure/skip reasons, state-derived dataset IDs, malformed-log errors |
| `test-07_utils_state.R` | State schema and transitions, prerequisites, staleness, revisions, atomic persistence, backup recovery, legacy migration, and sample reconciliation |
| `test-app-bootstrap.R` | Clean Shiny package-directory startup and application assembly |
| `test-app-components.R` | Component graph, workflow guards/events, annotation behavior, batch/progress/threshold/preview integration |
| `test-app-ui-baseline.R` | Edge/Chromium browser navigation and synthetic workflow mutations, plus screenshot comparisons where a reviewed platform baseline exists |
| `test-golden_outputs.R` | Deterministic `compute_cna()` golden regression baseline |
| `test-m0-cna-characterization.R` | Regression coverage for formerly exposed CNA numerical/cache failures |
| `test-m5-cna-batch.R` | Mixed-validity batch isolation, subsets, progress, and retry behavior |
| `test-f07-batch-progress.R` | Shared clustering/DE progress contract, monotonic fractions, Shiny formatting, and failure-stage reporting |
| `test-p06a-console-progress.R` | Deterministic step/sample timing, terminal outcomes, standalone DE failure, CNA reuse/skips/isolated failures, and completion-state failure totals |
| `test-f08-natural-cluster-ordering.R` | Numeric-aware 13-cluster ordering across UMAP legends/colours, DE axes/lists, and annotation controls; long DE score-plot titles and explicit export dimensions |
| `test-f09-single-sample-clustering.R` | Targeted clustering index/resolution coverage, sample-scoped state/cache invalidation, failure isolation, duplicate guards, completion navigation, and shared targeted-DE recovery from Manual Annotation |
| `test-regression_clustering.R` | Preprocessing → PCA → UMAP → Louvain integration/regression behavior |
| `test-regression_cna_cache.R` | CNA compute/cache/load round trip and missing-cache behavior |
| `test-standardize-general-template.R` | Optional general-template safety, alignment, duplicate-gene preservation, and staged publication |
| `test-p04-preparation-ui.R` | No preparation UI or startup dependency; optional-file absence, required biological resources, import, loading, and README download |
| `test-c01-*` through `test-c04-*` | Dataset transitions, interrupted-clustering recovery, CNA navigation, and post-reopen status |
| `test-c07-*` through `test-c09-*` | CNA omission, cut/threshold controls, annotation feedback, and source reminders |
| `test-f16-dataset-storage.R` | Dataset cleanup, archive audit, and reopening |
| `test-f17-*` | Review snapshots, completion/review layouts, and snapshot rollback |
| `test-t23-release-integration.R` | Multi-sample strict validation plus cache/state/log restart and recovery contracts |

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
- **Application/browser behavior**: clean app assembly, explicit component
  integration, navigation, interrupted-run recovery, selected-sample clustering,
  annotation saves, CNA computation/configuration/reset, optional export,
  omission, review snapshots, cleanup/reopen, and tolerant reviewed screenshot
  comparisons on platforms with an approved baseline and a configured Chromium
  browser.

No numeric line/branch coverage percentage is currently claimed or enforced.

Areas intentionally not exhaustively covered include:

- full biological acceptance through the browser: journeys use disposable
  synthetic workspaces, and the archive/reopen replay republishes deterministic
  numerical fixtures between real GUI decisions and saves;
- pixel-identical plot snapshots (browser screenshots use a small comparison
  threshold to tolerate platform rendering differences);
- every possible real biological dataset/resource combination.

Plot tests generally validate construction/buildability and workflow side effects rather than rendered pixels.

For the current portable gate, browser prerequisites and fixture policy, see
[Testing the application](TESTING.md). Dated scenario/acceptance records and
remaining human review are preserved on the
[development branch](https://github.com/ag-tyler/scAnnotationPipeline/blob/development/docs/development/RELEASE_ACCEPTANCE.md).

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

- **Prepared expression values are not log-transformed.** Downstream normalization occurs inside the analysis pipeline. Feeding already log-transformed values may result in unintended double transformation.
- **Cell names are unique across the entire dataset.** Prefix or suffix raw
  barcodes deterministically when samples reuse them.
- **Standardized gene symbols are non-empty and unique per sample.** Map raw
  identifiers and sum duplicate mapped gene rows during your preparation.
- **Sample directory names under `processed_data/` are canonical sample identifiers**
  and exactly match `sample` values in authoritative `Samples.csv`.
- **Prepared cells and genes align positionally with matrix columns and rows.**
  Users verify scientific alignment, counts, and metadata. The import/load check
  reads only sample metadata and filesystem structure, not matrix/gene/cell contents.
- **Underlying inputs are not replaced during analysis.** Import replacement
  inputs into a new workspace. There is no input-replacement monitoring or
  validation-result cache.
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

Each cache is registered in `cache_manifest.yaml` with a checksum, structural
validation summary, and dependency fingerprint. The app reuses an artifact only
when the file and its relevant inputs, parameters, upstream cache versions, and
saved decisions still match. See [Cache Validity and Invalidation](CACHE_VALIDITY.md)
for the complete contract and legacy-cache migration behavior.

### Clustering or normalization parameters changed

Use **Select Samples for Clustering**, checking the samples affected by the
parameter change (or all samples for a dataset-wide change). New clustering artifacts replace
their previous versions atomically and are registered with the current input and
parameter fingerprints.

Changed saved resolutions, annotations, CNA configuration, and malignant-cluster
selections automatically invalidate their dependent CNA cache families.

### Marker sets or marker filtering changed

Biological resource files are read when the app starts. After editing a marker
resource file, stop and restart the app, then load the dataset. Reloading a
dataset in the same app session does not reread those files.

Dataset-specific `marker_filter_params` are applied when the dataset is loaded;
after changing those settings, reload the dataset to rebuild `complete_markers`.
Rebuilding marker sets does not rerun differential expression or replace saved
marker-match results. Rerun the affected DE analysis and review downstream
annotations/results before relying on them.

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
- The optional general standardization template requires dataset-specific import and
  sample-splitting logic in one linear `BEGIN USER CODE` region plus user settings.
- Browser coverage uses a temporary synthetic workspace to verify application
  startup, navigation, and workflow mutations. It does not replace manual review
  of real biological results or platform-specific filesystem behavior.
- Cache fingerprints cover the pipeline inputs, parameters, upstream artifacts,
  and saved decisions documented in [Cache Validity and Invalidation](CACHE_VALIDITY.md);
  newly introduced parameters must be added to the relevant dependency family.
- Real-world biological inputs can expose cases not represented by the deterministic synthetic test fixtures.

---

[Back to README](../README.md)
