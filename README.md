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
* **Quarto** for the standardization templates
* Required R packages:

```r
install.packages(c(
  "shiny", "bslib", "shinyjs", "data.table", "yaml", "jsonlite", "DT",
  "ggplot2", "cowplot", "viridis", "Matrix", "irlba", "uwot", "Seurat",
  "stringr", "caTools", "RColorBrewer", "scales", "dbscan", "ggdendro",
  "randomcoloR", "docstring", "qs2", "magrittr", "devtools"
))
```

The pipeline also depends on the custom `matkot` package:

```r
pak::pak("m20ty/matkot")
```

For development/testing:

```r
install.packages(c("testthat", "withr"))
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

## Running the App

From the repository root:

```r
shiny::runApp(".")
```

or open `app.R` in RStudio and click **Run App**.

On startup, the app:

1. loads `general\_config.yaml`;
2. sources all `.R` files in `util\_scripts/`;
3. validates and loads the required resource files;
4. creates/scans `datasets/`;
5. displays available datasets in the Dataset Selection screen.

## Creating a Dataset

Use **Create New Dataset** in the app. A dataset is created under:

```text
datasets/<dataset\_id>/
```

with configuration files, data/result directories, and a technology-specific `standardize.qmd` template.

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

See the [Testing](docs/USER_GUIDE.md#testing) section for the test-file breakdown and coverage summary.

## Repository Notes

* `datasets/` contains local runtime data and should remain outside version control.
* Most biological resource files under `resources/` are also intentionally untracked.
* `general\_config.yaml`, source code, templates, tests, documentation, and the committed CNA golden fixture are version-controlled.
* The app uses on-disk `.qs2` caches for expensive intermediate results. Changing analysis parameters may require cache invalidation; see [Cache Behavior \& Invalidation](docs/USER_GUIDE.md#cache-behavior--invalidation).

## Documentation

The detailed documentation is maintained in:

[**docs/USER\_GUIDE.md**](docs/USER_GUIDE.md)

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

