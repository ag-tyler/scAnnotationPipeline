# Dataset configuration and annotation usability development plan

**Date:** 2026-11-25

**Status:** Complete; DC01 through DC06 and DC08 implemented and accepted on 2026-11-25.

**Creation-dialog follow-up:** Implemented and automatically verified on 2026-11-25.

**Required branch:** `development`.

Improve dataset creation and configuration so users can supply their own matrix
filenames, retain their configured settings, optionally record dataset sources,
and understand the marker-count warning in cluster score plots. Remove the
unused dataset-level technology field while keeping sample metadata intact.

Before final integration, add a convenient script for loading selected cache
objects into an R session for personal analysis.

All work covered by this plan, including implementation, tests, and documentation,
must be done on `development`. This instruction overrides the Developer Guide's
default of starting app feature branches from `main`. Do not switch to `main`,
create a feature branch from it, or merge or publish these changes as part of
this work.

## Agreed scope

- Make `templates/dataset_config_template.yaml` the canonical definition of
  dataset configuration keys and defaults. New workspaces inherit its settings;
  existing workspaces use their own `dataset_config.yaml`.
- Honor `std_names.expmat`, `std_names.genes`, `std_names.cells`, and
  `std_names.samples` throughout preparation, import, loading, and relevant tools.
  Do not silently replace these values with detected or generated names.
- Prefill these four names from the template in a collapsed **Input filenames**
  section above **Source information (optional)** during dataset creation. Save
  user edits only in the new workspace, without changing the shared template.
- Allow arbitrary configured Matrix Market filenames, including `expression.mtx`.
  Dataset creation/import must not infer, require, or validate counts/TPM/CPM
  state. The shared structural checker used during loading must also accept
  filenames without an expression-state designation.
- Keep matrix-state guidance and checks in the optional preparation script,
  standardization template, and preparation checklist. These are independent of
  the matrix filename and are not prerequisites for creating a dataset.
- Offer DOI and database URL inputs inside a compact disclosure, collapsed by
  default, in the dataset creation dialog. Both fields are optional.
- Remove `project_info.technology` from the template and its automatic population
  from `Samples.csv`. Keep sample-level `technology` in the authoritative CSV.
- Explain the pink/red background shading and marker counts in Cluster Score
  Boxplot using the configured minimum, which defaults to 20.
- Provide a sourceable cache-loading script for personal R analysis that accepts
  one relative or absolute file path and returns the stored R object.

Scientific normalization, clustering, scoring, and CNA algorithms are outside
this change. Matrix format, row/column alignment, and suitable untransformed
expression values remain preparation responsibilities; arbitrary filenames do
not expand the supported data formats.

This plan supersedes the fixed matrix filenames and inferred matrix-state
requirements in the [prepared-data import plan](PREPARED_DATA_IMPORT_PLAN.md).
That plan's copy isolation, structural validation, sample metadata authority,
and recovery behavior still apply.

## Behavior before implementation

| Area | Behavior at planning | Starting points |
| --- | --- | --- |
| Dataset configuration | Analysis and marker-filter settings are consumed, but import replaces `std_names` and preparation forces the matrix filename from `matrix_state`. | `templates/dataset_config_template.yaml`, `util_scripts/18_utils_dataset_import.R`, `util_scripts/08_utils_standardization.R` |
| Structural checks | New import recognizes three fixed matrix filenames. Configured filenames must still declare counts, TPM, or CPM. Only sample CSV contents and required file structure are checked. | `util_scripts/17_utils_prepared_data.R` |
| Matrix state | Does not select an analysis path. It affects filename restrictions, preparation integer validation, and state/log provenance. | `util_scripts/03_utils_misc.R`, `util_scripts/08_utils_standardization.R`, `util_scripts/18_utils_dataset_import.R` |
| Normalization | All inputs use the same column-total normalization and log transformation. | `log_normalize_expmat()` in `util_scripts/02_utils_annotation.R`, called from `util_scripts/05_utils_workflow.R` |
| Source metadata | Template fields, missing-origin reminders, and review snapshot output already exist. Creation has no source inputs. | `app/ui/dataset_ui.R`, `app/server/dataset_server.R`, `util_scripts/09_utils_pipeline_overview.R`, `util_scripts/14_utils_snapshots.R` |
| Technology | Import writes a unique CSV technology, or an empty string. There is no runtime consumer of the dataset-level value. | `util_scripts/18_utils_dataset_import.R` |
| Score plots | Available marker counts are compared with `params.de.min_marker_found`. Failed sets receive pink background shading; box fills identify marker sets. The app displays saved PNGs. | `util_scripts/02_utils_annotation.R`, `util_scripts/05_utils_workflow.R`, `app/ui/annotation_ui.R`, `app/server/annotation_server.R` |
| Downsampling | Recognizes the same three matrix names and ties its integer check to the counts filename. | `scripts/downsample_processed_data.R` |

## Implementation order

The configuration contract comes first because filename handling, metadata
creation, and threshold text depend on it. Add focused regressions with each
phase; the final phase checks the combined workflow and documentation.

Task identifiers stay stable. The addition DC08 runs before the final
DC06 integration gate; the completed DC01 through DC05 tasks are not renumbered.

| Order | Task | Dependency | Completion gate |
| --- | --- | --- | --- |
| 1 | DC01 Configuration authority completed | None | Keys, defaults, and workspace ownership verified by focused regressions. |
| 2 | DC02 Configured filenames without matrix-state checks completed | DC01 | Custom filenames verified through creation, reload, preparation, downsampling, and checkpoint copying. |
| 3 | DC03 Remove dataset technology completed | DC01 | New configurations omit the redundant field; sample metadata and legacy loading verified. |
| 4 | DC04 Optional source inputs completed | DC01 and DC03 | Optional inputs persist through creation, retry, reload, and snapshots; keyboard and responsive layout verified. |
| 5 | DC05 Explain marker-count shading completed | DC01 | Numerical PNG captions, threshold boundaries, and existing image preservation verified; the duplicate UI reminder was removed in the follow-up. |
| 6 | DC08 Load caches for personal analysis completed | Existing qs2 file format | Relative/full paths, stored classes and values, clear errors, and unchanged files verified. |
| 7 | DC06 Integration and documentation completed | DC01 through DC05, DC08 | Automated verification completed; user manual acceptance recorded; final full-run repeat explicitly waived. |

## DC01 Configuration authority

Keep the existing configuration key names. Making the template canonical means
that users can change its values and have those values honored; it does not mean
supporting arbitrary renamed YAML keys. Preserve the distinction between a
template for future datasets and a workspace's saved configuration.

| Configuration | Authority and consumers |
| --- | --- |
| `project_info.dataset_id` | Set to the new workspace name during import; used for dataset identity and logs. |
| `project_info.source_doi` and `source_url` | Optional dataset provenance, consumed by reminders and review snapshots. |
| `std_names.*` | Filenames used for prepared files, validation, copying checks, loading, and supporting tools. |
| `marker_filter_params.cell_type.*` and `cancer_type.*` | Marker selection when loading a dataset. |
| `params.min_genes`, `target_sum`, `log2_expr_threshold` | Filtering and normalization. |
| `params.pca_nv`, `seed`, `resolutions`, `umap.*` | PCA, clustering, UMAP, and applicable seeded operations. |
| `params.max_marker_genes` | Maximum marker genes used for signature scoring. |
| `params.de.num_genes`, `max_match_genes`, `min_marker_found` | DE selection, marker matching, and low-marker shading. |

Implementation and acceptance:

- [x] Confirm each retained template setting reaches its intended consumer;
  identify any additional hardcoded override before changing behavior.
- [x] Read the configuration template before checking import inputs, so the
  checker receives the configured filenames from the start.
- [x] Preserve template analysis and marker-filter settings when creating a
  workspace. Document dataset identity and user-entered origin as creation-time
  values rather than accidental overrides.
- [x] Use one effective filename configuration for source checks, copied-data
  checks, saved YAML, path construction, and subsequent loading.
- [x] Preserve each existing workspace's saved configuration. Changing the
  template must not modify existing datasets or rename their files.
- [x] Verify non-default analysis settings survive creation and reload. Reload
  configuration and rerun affected stages when applying analysis changes; honor
  existing cache dependency and workflow staleness mechanisms.

### DC01 implementation and audit findings

Import reads the template once before checking source inputs. The creation-dialog
follow-up allows explicit `std_names` overrides for this new workspace; otherwise
the template names apply. Source and copied-data checks share the same effective
names. The saved configuration keeps
those names and all template analysis/marker-filter values. Missing or mismatched
configured filenames fail explicitly instead of triggering autodetection. Loading
already reads the workspace configuration and does not merge later template edits.

The consumer audit confirmed filtering, normalization, marker filtering, DE,
resolution, and transcriptome UMAP settings are connected to their configuration
values. It also found that PCA and score-plot palette calls omitted `params.seed`.
Both now receive it. PCA uses the configured seed in batch clustering and the
selected-resolution workflow. Default seed `3988` preserves existing behavior;
older custom-seed clustering caches fail dependency validation when consumed and
must be recomputed. Compatible default-seed caches keep their existing fingerprint.

The preparation filename override and technology aggregation found during DC01
are resolved in DC02 and DC03 below. Import intentionally sets dataset identity from the new
workspace name and continues removing the obsolete `raw_files` section. Origin
values already supplied in the template survive import; the DC04 creation inputs
prefill these values and let the user override or clear them.
The `params.umap` settings apply to transcriptome UMAP; CNA embedding retains its
separate existing defaults.

## DC02 Configured filenames without matrix-state checks

Use configured filenames directly rather than discovering a matrix by looking
for counts/TPM/CPM substrings. A dataset uses one configured matrix filename
across its sample folders, matching the existing dataset-wide `std_names` model.
Keep the current default filename if useful for compatibility; its spelling must
not imply a required naming convention.

Implementation and acceptance:

- [x] Remove fixed matrix-name matching and expression-state inference from the
  structural import/load checker. Pass explicit configured names from callers;
  align standalone checker defaults with the template.
- [x] Remove `unknown_expression_type` rejection from this structural path.
  Import must not inspect matrix values, require a state selection, enforce
  integer counts, or check scale consistency.
- [x] Keep structural checks: portable distinct basenames, required readable
  non-empty files, valid sample CSV headers, and exact sample-folder membership
  and order. Require the configured file in each sample; report missing names
  as filename errors rather than mixed matrix states.
- [x] Stop recording a filename-inferred expression state for new structural
  imports. Omit that detail or represent it as unspecified without blocking
  creation. Continue accepting historical state/log records containing it.
- [x] Stop generating or overwriting `std_names.expmat` from preparation
  `matrix_state`. Preparation writes the configured filename.
- [x] Keep explicit preparation `matrix_state` and its integer-count checks.
  Supply that state independently to strict postvalidation, so arbitrary names
  neither disable preparation checks nor force filename inference.
- [x] Update downsampling to accept configured names and remove its dependence
  on the three canonical names. If an optional counts check is retained for this
  external tool, select it explicitly rather than from the filename.
- [x] Review checkpoint, cache recovery, and profiling tools for consistent use
  of workspace `std_names`; avoid introducing template defaults over saved names.
- [x] Verify creation and reload using `expression.mtx`, renamed gene/cell files,
  and a renamed sample CSV after changing the template accordingly.
- [x] Verify legacy configured names still load, sources remain byte-identical,
  copied files retain their names, and no automatic rename or migration occurs.
- [x] Verify extra matrix-like files do not trigger state inference or ambiguity
  when the configured filename already identifies the required input.
- [x] Preserve tests proving that creation reads only the sample CSV and does
  not parse matrix, gene, or cell contents. Test preparation validation separately.

Primary tests: `test-p01-prepared-data.R`, `test-p03-dataset-import.R`,
`test-c01-dataset-transitions.R`, `test-03_utils_misc.R`,
`test-standardize-general-template.R`, `test-downsample-processed-data.R`,
and `test-copy-dataset-checkpoint.R` under `tests/testthat/`.

### DC02 implementation and compatibility

The shared structure checker requires the configured matrix, gene, cell, and
sample CSV names. It no longer detects matrix state, chooses among conventional
names, or rejects additional matrices. Standalone checks without `std_names` read
the current template by finding the application root above the working directory;
workspace callers continue supplying their saved configuration. The compatibility
result field `expression_type` remains present as `NA_character_`, and new import
provenance omits it. Existing state/log details are retained without becoming
matrix-state requirements.

Preparation initialization and publication preserve `std_names.expmat`. The
general template passes its explicit `matrix_state` to strict postvalidation,
which checks integer counts independently of the filename. Legacy preparation
callers that omit this new argument can still infer state from conventional
filenames; this compatibility path is not used by creation or loading.

Downsampling accepts an explicit `std_names` list and preserves it in output.
Its standalone defaults remain the conventional names shown in its settings;
copy names from the source workspace or import template when needed. Optional
`matrix_state = NULL` performs no state-specific check; an explicit `UMIcounts`
declaration enables integer validation. Finite values, non-negativity, and
alignment remain preparation checks. Filename validation also prevents a custom
sample CSV name from colliding with `downsampling_report.csv`.

Checkpoint, cache-recovery, interaction-profiling, and real-data performance
extraction paths already use saved `std_names` and need no filename rewrite.
The checkpoint regression now exercises all four custom names and verifies that
copied caches still validate after moving the original workspace. No scientific
datasets, historical preparation scripts, or stored results were migrated.

## DC03 Remove dataset technology

Sample-level technology in the sample CSV remains authoritative, including for
datasets with multiple technologies. Existing YAML containing the redundant
dataset-level field remains loadable; there is no bulk cleanup of saved datasets.

- [x] Remove `project_info.technology` and its explanatory comment from the
  dataset configuration template.
- [x] Remove the import code that aggregates `Samples.csv` technology and writes
  the dataset-level value. Ensure newly generated configurations omit it.
- [x] Replace the existing import test expectation for automatic technology
  population with checks for omission and preservation of CSV metadata.
- [x] Cover both single-technology and mixed-technology sample tables, and
  compatibility with an older saved configuration containing the field.
- [x] Remove obsolete manual setup instructions for dataset-level technology.

### DC03 implementation and compatibility

The template no longer includes `project_info.technology`, and import no longer
aggregates technology from the sample table. Creation also removes this obsolete
key if supplied by an older template, so newly generated configurations omit it.
The sample CSV's required `technology` header, values, row order, and copied
bytes are preserved for single-technology, mixed-technology, and unknown entries.

Dataset loading continues to accept and retain an existing saved technology
field without rewriting the configuration or CSV. The sample table remains
authoritative even when its values differ from that legacy summary. Current
setup instructions now describe sample-level technology only; historical
documentation and legacy fixtures remain intact.

## DC04 Optional source inputs

Add a disclosure labelled **Source information (optional)** to the creation
dialog, collapsed by default. Expanding it reveals two text inputs with one
sentence of help each:

| Saved field | Input label | Help sentence |
| --- | --- | --- |
| `project_info.source_doi` | Paper DOI | DOI of the paper describing the dataset. |
| `project_info.source_url` | Database URL | URL of the dataset's database entry. |

Implementation and acceptance:

- [x] Implement the compact disclosure in `app/ui/dataset_ui.R`, using an
  existing component or native disclosure without adding a package dependency.
- [x] Pass both inputs through `app/server/dataset_server.R` to
  `import_prepared_dataset()` as optional arguments. Existing non-UI callers
  remain compatible.
- [x] Trim surrounding whitespace and save supplied values under `project_info`.
  Blank inputs remain empty strings; either field alone is sufficient.
- [x] Keep input drafts through a failed import and retry. The disclosure must
  not create an extra creation step or confirmation requirement.
- [x] Avoid required-format checks, network lookups, or DOI/URL resolution as
  creation gates. Missing origin continues to use the existing reminder behavior.
- [x] Verify neither field, DOI only, URL only, and both fields through creation
  and reload; confirm source metadata reaches existing review snapshot output.
- [x] Check that the collapsed dialog stays compact and the expanded fields are
  readable and accessible by keyboard.

Primary tests: `test-p03-dataset-import.R`, `test-p04-preparation-ui.R`,
`test-c09-annotation-feedback.R`, and `test-f17-review-snapshots.R`.

### DC04 implementation and compatibility

The creation dialog uses native `details` and `summary` elements for **Source
information (optional)**, collapsed by default. Its labelled Paper DOI and
Database URL inputs include the agreed help sentences. Source values from the
template prefill the form. The existing error report updates without rebuilding
the dialog, retaining input drafts for retry.

The import function appends optional `source_doi` and `source_url` arguments
after its existing parameters. Omitted arguments (`NULL`) preserve template
values for existing non-UI callers. Supplied text is trimmed; explicit empty or
whitespace-only inputs save empty strings and clear template defaults. Neither
field triggers a format check, network request, or extra confirmation. Existing
missing-origin reminders and snapshot consumers continue using `project_info`.

Focused tests cover all four DOI/URL combinations through creation and reload,
clearing template defaults, accepting unverified text, and retry persistence.
Real imported source arguments also reach folder and ZIP snapshot READMEs before
and after cache cleanup. An isolated browser test of the actual dialog component
verifies native Enter activation, Tab navigation, preservation across collapse
and expansion, and layout at widths 1280 and 375. Screenshots of the collapsed
and expanded layouts were visually reviewed; no screenshot baselines changed.

## DC05 Explain marker-count shading

The warning represents marker genes available for scoring in the filtered sample
matrix, not the number of DE matches in an individual cluster. The threshold is
`params.de.min_marker_found`, default 20. A count strictly below the threshold is
flagged; a count equal to it passes. Box fill colors identify marker sets, so
describe the warning as background shading rather than red box fills.

Use this explanation, substituting the actual threshold when known:

> Red shading indicates fewer than 20 marker genes available for this cell type
> in the sample. Scores based on fewer markers may be noisier; consider this
> when annotating. Numbers above the boxes show the available marker counts.

- [x] Keep the explanation in the plot image only. The later user-requested
  follow-up removes the duplicate reminder below the plot from the annotation UI.
- [x] Include the explanation in newly generated score PNGs, using the threshold
  passed from the scoring workflow rather than an independent hardcoded 20.
- [x] Keep captions readable in the saved image and app layout without clipping
  axis labels or marker counts.
- [x] Verify counts below, equal to, and above the minimum, including a
  non-default minimum. Preserve scoring and the existing shading rule.
- [x] Handle previously generated PNGs without automatically rerunning DE or
  overwriting results. Preserve their existing contents rather than claiming
  the current YAML threshold produced the image. Regeneration adds the numerical caption.

Primary tests: `test-02_utils_annotation_de.R`,
`test-f08-natural-cluster-ordering.R`, and the relevant annotation UI coverage.

### DC05 implementation and compatibility

`signature_score_marker_note()` supplies the plot-caption explanation of red
shading, noisier scores, and available-marker counts. A user-requested follow-up
removes the duplicate note and pink swatch below the plot in the annotation UI.
The explanation is now displayed inside the saved image only. Older images
retain their existing contents until explicitly regenerated.

The scoring workflow passes `params.de.min_marker_found` to each new plot through
an appended optional argument. PNG captions state that generation threshold,
wrap to the existing 9 by 7 inch canvas, and use left-aligned readable text.
Existing callers that omit the argument receive a generic caption. Scoring,
marker counts, background shading rules, plot filenames, and export dimensions
remain unchanged. Regeneration through the existing DE controls adds the numeric
caption; loading an older image performs no regeneration or overwrite.

Regression coverage checks counts 19/20/21 and 6/7/8 against minima 20 and 7,
verifies the configured minimum reaches workflow-generated images, and renders
a legacy PNG with a different current YAML threshold without changing its bytes.
A long-sample-name image with threshold 10 was exported and visually inspected:
the title, count labels, axes, and caption remain visible without clipping.
The User Guide now explains sample-level marker availability, equality at the
threshold, and how to regenerate captions.

The later 2026-11-25 presentation follow-up removes only the duplicate UI
paragraph and swatch. The original reviewed Manual Annotation screenshot
baseline was restored, and the focused plot/annotation regressions passed
226 assertions with zero failures, errors, warnings, or skips. The full suite
and browser journeys were not rerun; see the
[testing record](../TESTING.md#recorded-verification-status).

## DC08 Load caches for personal analysis

The standalone script `scripts/load_dataset_cache.R` loads one cache file into
an ordinary R session using only its relative or absolute path.
No dataset/sample selectors, artifact-family options, resolution
selection, or inventory interface are needed.

Usage:

```r
source("scripts/load_dataset_cache.R")
expression <- load_cache_file("datasets/MyStudy/cache/expmat_filt_Sample_A.qs2")
cells <- load_cache_file("C:/analysis/MyStudy/cache/cells_filt_clust_res_0.5_Sample_A.qs2")
class(expression)
class(cells)
```

Use `qs2::qs_read(path)` and return its object directly, without wrapping it in
a list or changing its values. A qs2 file stores the serialized R object,
including its classes, attributes, and structure. The reader restores the type
from the file contents, not by interpreting the filename. Sparse matrices stay
sparse, data tables retain their classes, and clustering trees retain `hclust`.
Required class packages must be installed when using their methods.

This is a convenience reader for personal use, separate from pipeline cache
validation and recovery. It needs no dataset configuration or manifest and does
not certify that a file matches the current analysis parameters. Do not change
the app's existing cache loader or recovery behavior. Reading a personal cache
file must not rewrite files, restore backups, create directories, or start Shiny.

Implementation and acceptance:

- [x] Add a sourceable script defining `load_cache_file(path)` with a single
  relative or absolute path argument. Sourcing it must not load a file or launch
  the app; callers assign the returned object themselves.
- [x] Check that the requested path is a readable file and provide a clear
  missing-package or read-error message. Load qs2 content without filename-based
  guesses, conversion, or manifest requirements.
- [x] Verify relative and absolute paths, paths containing spaces, preservation
  of sparse-matrix/table/tree classes and values, and errors for missing or
  unreadable/corrupt files. Confirm that loading does not change source files.
- [x] Add a short usage example to the README and User Guide, explaining that
  object types are restored from serialization and that pipeline validation
  remains a separate operation.
- [x] Record implementation and focused verification before starting DC06.

The script defines only `load_cache_file(path)`, checks path usability and the
`qs2` dependency, and returns `qs2::qs_read()` directly with a contextual read-error
message. It makes no changes to the application's cache loader. Focused tests
verify relative/full paths, spaces, arbitrary filenames, sparse-matrix/table/tree
classes and exact stored values, missing/unreadable/corrupt inputs, and an absent
package. Source hashes and directory membership remain unchanged. A separate
fresh R process verified that the helper works without Shiny or app utilities.

## DC06 Integration and documentation

Begin after DC08 is resolved as well as DC01 through DC05.

- [x] Run focused regressions as each phase completes, then the application
  regression suite from the repository root with `Rscript tests/testthat.R`.
- [x] Manually create and reload a disposable dataset using custom configured
  filenames and optional source metadata; verify sample order and source files.
- [x] Open an existing workspace containing legacy filenames and dataset-level
  technology. Verify loading, annotation navigation, and review snapshots.
- [x] Inspect the source disclosure and marker explanation in the app. Inspect
  a newly generated score PNG with a non-default threshold.
- [x] Exercise the DC08 personal cache-loading example in a fresh R session.
- [x] Update `README.md`, `docs/USER_GUIDE.md`,
  `docs/STANDARDIZATION_CHECKLIST.md`, and template comments. Explain configured
  filenames, creation without matrix-state checks, preparation-only state checks,
  optional paper/database origin, sample-level technology, and the personal
  cache-loading workflow.
- [x] Mark superseded naming/state requirements in the earlier import plan;
  preserve its dated evidence and unrelated acceptance items.
- [x] Update UI baselines only for intentional reviewed presentation changes,
  following `docs/TESTING.md`.
- [x] Record test commands, outcomes, manual evidence, and commit references below
  and tick completed tasks. Keep unrelated acceptance work separate.

## Progress record

Checked tasks have completed implementation and focused verification. Complete
a phase only after its behavior and verification are recorded.

| Date | Task | Change or verification | Evidence | Remaining work |
| --- | --- | --- | --- | --- |
| 2026-11-25 | Planning | Agreed scope and implementation order recorded. Current branch is `development`. | This plan | DC01 through DC06 |
| 2026-11-25 | DC01 complete | Template filenames are authoritative throughout import and reload. Analysis/marker defaults and existing workspace configurations are preserved. Configured PCA/palette seeds are forwarded, with compatibility checks for previous clustering caches. | Focused nine-file regression run passed on Windows with R 4.5.3; command below. | DC02 through DC06 |
| 2026-11-25 | DC02 complete | Creation/loading accept arbitrary configured matrix names without state inference. Preparation and downsampling retain independent explicit checks; custom names survive creation, reload, publication, and checkpoint copying. | Four utility files and six integration files passed on Windows with R 4.5.3; commands below. | DC03 through DC06 |
| 2026-11-25 | DC03 complete | Removed the template field and automatic technology aggregation. New imports omit the obsolete key even from older templates; sample CSV metadata and existing saved configurations remain unchanged. | Three focused regression files passed on Windows with R 4.5.3; command below. | DC04 through DC06 |
| 2026-11-25 | DC04 complete | Added compact optional source inputs, template prefills, trimmed persistence, and draft retention. Verified source propagation to review snapshots and keyboard/narrow-screen operation. | Six focused test files passed on Windows with R 4.5.3, including headless Edge; commands below. | DC05 and DC06 |
| 2026-11-25 | DC05 complete | Added the shared marker-warning explanation, UI swatch, and generation-threshold PNG captions. Preserved shading/scoring rules and existing images. | Five focused regression files passed on Windows with R 4.5.3; long-title PNG visually reviewed; command below. | DC06 |
| 2026-11-25 | DC08 added | Planned a simple sourceable cache reader taking one relative or absolute file path. Object-class preservation verified with qs2 round trips; implementation remains pending. | This scope addition | DC08, then DC06 |
| 2026-11-25 | DC08 complete | Added the path-only `load_cache_file()` helper and usage documentation. Verified preserved object classes/values, error messages, unchanged files, and independent use in a fresh R session. | 28 focused assertions and standalone smoke check passed on Windows with R 4.5.3; commands below. | DC06 |
| 2026-11-25 | Filename follow-up and automated verification | Added prefilled per-dataset filename inputs without template writes. Completed the full app/development suites; reviewed one intentional marker-note screenshot update and passed the browser-file rerun. | 4,860 verified app assertions plus 62 development-tool assertions; [dated record](../TESTING.md#development-configuration-and-annotation-changes--2026-11-25). | User manual acceptance; DC06 remains open |
| 2026-11-25 | DC06 complete; manual acceptance | User reported manual testing finished and all working. The annotation type fix and plot-only reminder follow-up passed focused checks; user explicitly waived another full suite. | [Acceptance and testing record](../TESTING.md#recorded-verification-status); working tree based on `6d5e626`, with final changes not yet committed. | Main promotion is prepared separately; no remaining plan acceptance work |

### DC01 verification

Run from the repository root with the installed R executable. This run used
`LC_CTYPE=English_United States.utf8` after clearing incompatible inherited
`LC_ALL`, `LC_CTYPE`, and `LANG` values for the test process only.

```r
source("scripts/check_test_setup.R", encoding = "UTF-8")
check_test_setup(browser = FALSE)
testthat::test_dir(
  "tests/testthat",
  filter = paste0(
    "^(p01-prepared-data|p03-dataset-import|p04-preparation-ui|05_utils_workflow|",
    "f09-single-sample-clustering|c01-dataset-transitions|f17-review-snapshots|",
    "marker-selection|f15-r01-cache-precision)$"
  ),
  reporter = "summary"
)
```

Result: preflight and all nine selected test files passed. New coverage includes
all four configured input filenames, non-default analysis/marker settings through
creation and reload, template changes during copying, template changes after
creation, mismatch rejection without fallback, source byte preservation, and
custom PCA/palette seeds. Browser acceptance and the full suite remain DC06.

### DC02 verification

Using the same process-local Windows UTF-8 settings as DC01, run the two focused
groups from the repository root:

```r
testthat::test_dir(
  "tests/testthat",
  filter = "^(p01-prepared-data|03_utils_misc|standardize-general-template|downsample-processed-data)$",
  reporter = "summary"
)
source("scripts/check_test_setup.R", encoding = "UTF-8")
check_test_setup(browser = FALSE)
testthat::test_dir(
  "tests/testthat",
  filter = paste0(
    "^(p03-dataset-import|c01-dataset-transitions|copy-dataset-checkpoint|",
    "p06b-cache-location|t23-release-integration|f17-review-snapshots)$"
  ),
  reporter = "summary"
)
```

Result: preflight and all ten selected files passed. Coverage includes generic
and legacy names, fractional matrices and unused alternative matrices during
creation/reload, omission of inferred import state, retention of historical
state, preparation checks with explicit state, configured filenames through
staging/publication and downsampling, unchanged source bytes, and independent
checkpoint caches. Full-suite and browser acceptance remain DC06.

### DC03 verification

With the same process-local Windows UTF-8 settings as earlier phases, run:

```r
Sys.setenv(R_USER_CACHE_DIR = tempdir())
testthat::test_dir(
  "tests/testthat",
  filter = "^(p03-dataset-import|p04-preparation-ui|c01-dataset-transitions)$",
  reporter = "summary"
)
```

All three files passed. The initial UI run reported a Sass cache permission
warning; rerunning that group with the temporary cache above passed without
warnings. New coverage verifies omission from new configurations, preservation
of single/mixed/blank CSV technology values and bytes, and repeated legacy loads
without changing saved configuration or sample metadata. Full-suite and browser
acceptance remain DC06.

### DC04 verification

Using the same process-local Windows UTF-8 settings as earlier phases, run:

```r
Sys.setenv(R_USER_CACHE_DIR = tempdir())
source("scripts/check_test_setup.R", encoding = "UTF-8")
check_test_setup()
testthat::test_dir(
  "tests/testthat",
  filter = "^(p03-dataset-import|p04-preparation-ui|c09-annotation-feedback|app-components)$",
  reporter = "summary"
)
testthat::test_dir("tests/testthat", filter = "^f17-review-snapshots$", reporter = "summary")
testthat::test_dir("tests/testthat", filter = "^dc04-source-layout$", reporter = "summary")
```

Result: all six selected files passed, including 32 browser assertions. The
snapshot and browser groups require permission to launch their ZIP/R/browser
workers; the snapshot group passed when rerun with those permissions. The browser
test waits for the modal focus handoff and dispatches the complete native Enter
key sequence. Optional `DC04_ARTIFACT_DIR` captures uniquely named screenshots;
reviewed local artifacts are under `artifacts/local-checks/dc04/`. Full-suite and
complete application browser journeys remain DC06.

### DC05 verification

Using the same process-local Windows UTF-8 settings as earlier phases, run:

```r
Sys.setenv(R_USER_CACHE_DIR = tempdir())
testthat::test_dir(
  "tests/testthat",
  filter = paste0(
    "^(02_utils_annotation_de|05_utils_workflow|f08-natural-cluster-ordering|",
    "c01-dataset-transitions|app-components)$"
  ),
  reporter = "summary"
)
```

Result: all five selected files passed. Coverage includes numerical and generic
captions, below/equal/above boundary behavior, configured threshold propagation,
export rendering, and unchanged legacy PNG bytes without a DE rerun. Set optional
`DC05_ARTIFACT_DIR` to an existing directory to retain the long-title caption
image; the reviewed local artifact is under `artifacts/local-checks/dc05/`.
Full-suite and complete application browser acceptance remain DC06.

### DC08 verification

Using the same process-local Windows UTF-8 settings as earlier phases, run:

```r
Sys.setenv(R_USER_CACHE_DIR = tempdir())
testthat::test_dir("tests/testthat", filter = "^load-dataset-cache$", reporter = "summary")
```

All 28 assertions passed across the three focused tests. A separate fresh
`Rscript` process also passed this standalone check without sourcing app helpers:

```r
source("scripts/load_dataset_cache.R")
path <- tempfile(fileext = ".qs2")
expected <- list(ids = c("001", "002"), values = c(1.23456789012345, NA_real_))
qs2::qs_save(expected, path)
stopifnot(identical(load_cache_file(path), expected))
stopifnot(!("shiny" %in% loadedNamespaces()))
```

README, User Guide, and Cache Validity documentation now distinguish personal
reading from the app's existing validation/recovery path. DC06 remains the final
integration gate.

## Creation-dialog filename follow-up — 2026-11-25

Users should not need to edit a tracked template to import differently named
files. This addition changes filename entry without changing configuration keys,
prepared file formats, matrix-state policy, or existing workspace ownership.

- [x] Add a native disclosure, collapsed by default, above source information.
  Include expression matrix, gene list, cell metadata, and sample metadata
  filename fields, prefilled from the configuration template.
- [x] Pass edited names to import before source checking; reuse the same names
  for copied-data checks and save them in the new dataset configuration only.
- [x] Keep filename edits after errors for correction/retry and reuse saved
  workspace names on subsequent loading.
- [x] Add regression cases for template prefills, disclosure order, keyboard and
  narrow-screen use, edits through retry/reload, preserved template/source bytes,
  and rejection of blank, unsafe, duplicate, or missing filenames.
- [x] Update README, User Guide, preparation checklist, testing coverage notes,
  and unreleased change notes to describe the creation inputs.
- [x] Run the changed regressions and full automated suites after testing resumes.
- [x] Human acceptance completed by the user on 2026-11-25; DC06 is complete.

Implementation: `dataset_import_dialog()` accepts filename defaults;
`register_dataset_server()` reads them when opening the dialog and forwards the
four input values. `import_prepared_dataset(..., std_names = NULL)` uses template
defaults when omitted and applies explicit overrides before the first structural
check. Validation retains distinct portable-basename requirements and does not
infer matrix state. No code writes back to the template.

Verification status: the resumed full app suite and separate development-tool
contracts completed on 2026-11-25. The only initial failure was the expected
Manual Annotation screenshot change from the marker explanation. After reviewing
and replacing that one baseline, all 700 assertions in the browser-file rerun
passed with screenshot updates disabled and the existing threshold unchanged.
Final verified coverage is 4,860 app assertions and 62 development-tool assertions,
with no unresolved failures, errors, warnings, or skips. These totals replace the
initial browser-file results rather than counting repeated assertions twice.
The filename follow-up's four tests passed 76, 26, 9, and 7 assertions for browser
layout, edit/retry/reload, invalid overrides, and prefilled disclosure layout.

The [dated testing record](../TESTING.md#development-configuration-and-annotation-changes--2026-11-25)
contains commands, timings, and limitations. Raw full-run and browser-rerun logs,
source hashes, screenshots, and result summaries are in ignored
`artifacts/local-checks/full-suite-2026-11-25-resumed/` and
`artifacts/local-checks/full-suite-2026-11-25-baseline-rerun/`. The preceding
`full-suite-2026-11-25/` run was interrupted at the user's request and is not a
completed verification. The optional greater-than-4-GiB stress test was disabled.
The user subsequently completed manual testing on 2026-11-25 and explicitly
waived another full run after the two focused annotation follow-ups. DC06 and
this plan are complete. Main-branch promotion remains a separate action.
