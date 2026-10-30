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
  "randomcoloR", "docstring", "qs2", "magrittr", "devtools", "R.utils"
))
```

The pipeline also depends on the custom `matkot` package:

```r
pak::pak("m20ty/matkot")
```

For development/testing:

```r
install.packages(c("testthat", "withr", "shinytest2"))
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
├── general\_config.yaml
├── DESCRIPTION
├── README.md
├── docs/
│   └── USER\_GUIDE.md
├── resources/
├── datasets/
├── templates/
├── util\_scripts/
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

1. loads `general\_config.yaml`;
2. sources all `.R` files in `util\_scripts/`;
3. validates and loads the required resource files;
4. creates/scans `datasets/`;
5. displays available datasets in the Dataset Selection screen.

## CNA Values Results

Finalizing a sample's CNA assignment saves its cell assignments and plots.
The summary/preview view stays open after saving so the optional export action
remains available.
The separate, optional **Export/Re-export CNA Values Table** action publishes
a reusable long-format table at `results/<sample>/3_cna_results/cna_values_<sample>.csv.gz`, with the
columns `gene`, `chr`, `start_pos`, `cell_name`, and `cna`. A neighboring
`.metadata.yaml` file records dimensions and the validated cache provenance.
The CNA summary view can export or refresh this table later without recomputing
CNA. The optimized `.qs2` cache remains authoritative and the CSV is never used
as pipeline input.

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

## Creating a Dataset

Use **Create New Dataset** in the app. A dataset is created under:

```text
datasets/<dataset\_id>/
```

with configuration files, data/result/log directories, an initialized pipeline
state, and a copy of the adaptable `templates/standardize_general.R` template
named `standardize.R`.

The standardization template must be run before the dataset can enter the downstream clustering/annotation workflow.

See [Setting Up a New Dataset](docs/USER_GUIDE.md#setting-up-a-new-dataset) and [Standardization Pipeline](docs/USER_GUIDE.md#standardization-pipeline) for details.

## Testing

The repository includes `testthat` unit, integration, regression, and golden-output tests using deterministic synthetic fixtures.

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

The test does not invoke compute, scientific-output saves, reset, or batch
actions. All state/log/cache changes occur only in its temporary synthetic
workspace. Approved platform-specific screenshots are stored under
`tests/testthat/fixtures/ui-baseline/`; platforms without a reviewed screenshot
set still run all functional browser assertions.

See the [Testing](docs/USER_GUIDE.md#testing) section for the test-file breakdown and coverage summary.

See [Release Acceptance](docs/RELEASE_ACCEPTANCE.md) for the complete portable
automated gate and scenario-to-test map.

## Repository Notes

* `datasets/` contains local runtime data and should remain outside version control.
* Most biological resource files under `resources/` are also intentionally untracked.
* `general\_config.yaml`, source code, templates, tests, documentation, and the committed CNA golden fixture are version-controlled.
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
[**docs/RELEASE\_ACCEPTANCE.md**](docs/RELEASE_ACCEPTANCE.md).

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

