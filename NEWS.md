# Release notes

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
