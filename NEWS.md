# Release notes

## 1.1.2 — 2026-11-25

- Load cells files without an initial `cell_type` column without warnings,
  while preserving annotation columns as text when present.
- Fix manual annotation failing with `i (20) is outside the range of items [1,3]`
  when the input contains only `cell_name` and `sample`. Initialize missing
  annotations in a local table before storing it in Shiny's reactive state.
- Clarify the app's required cells columns and optional metadata. QC calculates
  detected-gene counts from the matrix; a supplied `complexity` column is used
  in cache fingerprints, not cell filtering.

Restart the app and reload the dataset to use these fixes. Existing clustering
can be reused; annotation saves add `cell_type` and `cell_type_pre_cna`.

Focused verification passed 197 assertions across 21 tests, with zero failures,
errors, test warnings, or skips, including a two-column annotation load/assign/save
regression. No full suite or browser journey was rerun. See the
[testing record](docs/TESTING.md#recorded-verification-status).

## 1.1.1 — 2026-11-25

- Reject prepared samples whose gene count differs from matrix rows or whose
  cell metadata row count differs from matrix columns during creation/loading.
  Read only matrix header dimensions and gene/cell record counts; expression
  state, matrix values, identifier checks, and sample-reported counts remain
  outside this validation.

Focused verification passed 674 assertions across 53 tests, with zero failures,
errors, warnings, or skips. See the [testing record](docs/TESTING.md#recorded-verification-status).

## 1.1.0 — 2026-11-25

- Fix manual annotation saves when an existing `cell_type_pre_cna` CSV column
  is entirely blank. Keep pre-CNA labels as text during loading and before save
  joins, preventing logical coercion and missing labels in the saved CSV.
- Treat the dataset configuration template's filenames and analysis settings as
  the defaults for new workspaces; keep saved workspace configurations
  authoritative on reload, including configured PCA and plot-palette seeds.
- Accept any configured Matrix Market filename. Dataset creation and loading
  check input structure without inferring or validating counts/TPM/CPM state.
  Optional preparation tools retain explicit expression-state checks. Input
  matrices must never contain log-transformed data: filtering always performs
  normalization and log transformation, which cannot currently be disabled.
- Add collapsed **Input filenames** fields above the source inputs during
  dataset creation. Prefill all four names from the template and save edits
  only in the new dataset configuration, leaving the shared template unchanged.
- Add collapsed optional Paper DOI and Database URL inputs during dataset
  creation. Store these in the dataset configuration for source reminders and
  review snapshots. Remove redundant dataset-level technology from new
  configurations; preserve sample metadata and support older configurations.
- Explain low-marker red shading in Cluster Score Boxplots and include the
  generation threshold in newly generated plot captions. Show the explanation
  inside the plot image without a duplicate reminder below it. Existing plot
  files remain unchanged.
- Add the standalone path-based `load_cache_file()` helper for personal analysis
  and a short [development-script reference](https://github.com/ag-tyler/scAnnotationPipeline/blob/development/docs/development/SCRIPTS.md).

Existing workspaces retain their saved filenames and settings. Earlier
clustering caches made with a non-default PCA seed require recomputation when
dependency validation rejects them; default-seed caches remain compatible.
For an affected blank `cell_type_pre_cna` column, restart the app, reopen the
dataset, and save annotations again. Dataset files are not repaired automatically.

Automated verification and user-reported manual acceptance are complete.
The full run and browser-baseline rerun verified 4,860 app assertions and
62 development-tool assertions. The two later annotation changes each passed
their focused checks; the user accepted those results and explicitly waived
another full run. See the [testing record](docs/TESTING.md#recorded-verification-status)
for the separate phases and counts.

## 1.0.1 — 2026-11-20

- Sort cell-type and cancer-type marker groups by descending `combined` score
  before applying the existing minimum/maximum counts and soft score cutoff.
  Previously unsorted tables may select different markers and change downstream
  DE/signature evidence. Existing saved outputs are not recomputed automatically;
  rerun affected DE and review annotations when adopting the corrected selection.
- Load app components and utilities explicitly as UTF-8, preserving Unicode UI
  text across character locales; correct the start-menu screenshot baseline.
- Make ordinary tests self-contained for GitHub ZIP downloads, with synthetic
  biological resources and a read-only dependency, browser, and host/worker UTF-8
  preflight. Real app startup still requires all seven biological resources.
- Document resource formats, uses, alternate filenames, HGNC/BioMart downloads,
  artifact gene lists, and cancer-cell mapping. Move demonstration preparation
  to the end of the input-preparation section and ignore local `snapshots/` and
  `dataset_preprocessing/` directories.

## 1.0.0 — 2026-11-20

Initial stable release of the prepared single-cell RNA-seq cancer analysis app.

- Import prepared datasets and run clustering, differential-expression analysis,
  manual cell-type annotation, and CNA analysis.
- Preserve workflow status, event history, and validated caches, with recovery
  support for interrupted work and relocated workspaces.
- Export CNA values, create folder/ZIP review snapshots, and archive or reopen
  completed datasets.
- Use compact Y-threshold sliders with a normal maximum of 1.0; higher saved
  thresholds retain their precision and remain representable.
- Include a stable launcher, optional preparation/downsampling/checkpoint tools,
  and current user documentation. Development tools and instructions remain on
  the `development` branch, linked from the README.
- License the project under MIT, with copyright held by Michael Tyler and
  Georg-Speyer-Haus.

Verification on November 20 passed **4,451 app assertions** and **62 separate
development-tool assertions**, with zero failures, errors, warnings, or skips.
The run used Windows, R 4.5.3, and headless Edge 157.0.4341.60, including browser
journeys and screenshot comparisons. WSL acceptance is closed by user decision
and can be reopened if an issue appears. See the [testing record](docs/TESTING.md).

Scientific datasets and most biological resources are supplied separately. The
optional greater-than-4-GiB stress test was not enabled. Further performance
optimization remains deferred. Release preparation changes only version metadata
and documentation; application code and tests match the verified source.
