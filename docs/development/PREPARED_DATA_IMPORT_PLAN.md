# Prepared-data import and workflow entry overhaul

**Date:** 2026-11-04  
**Status:** In progress; P01-P06 and P06a implemented and verified on Windows
(latest: 2026-11-11). P06b is implemented and verified on WSL Ubuntu; P07
remains pending.

**Scope:** Replace mandatory app-directed standardization with import of an
externally prepared dataset. This document records the agreed direction and
implementation defaults. It does not close any existing release acceptance work.

## 1. Agreed behavior

Users prepare datasets with their own scripts and tools. The app begins with
prepared inputs and handles clustering, resolution selection, differential
expression, annotation, CNA, storage, and review snapshots.

- The sole user-supplied input is a prepared-data directory containing
  `Samples.csv` and one subdirectory per sample with matrix, genes, and cells.
- `Samples.csv` is the authority for sample membership and sample metadata.
  Users do not need to supply `samples_config.yaml`.
- Dataset creation selects the prepared directory, checks its structure, copies
  it into a new workspace, initializes app configuration/state, and opens it.
  No app shutdown or external processing step follows successful creation.
- Folder selection uses a platform-independent in-app browser plus a path field.
  Windows and Linux are supported. Paths refer to the machine running R.
- The README contains the complete prepared-input specification. The optional
  checklist remains in `docs/`; the app has no standardization guide tab,
  checklist viewer, or checklist-copy requirement.
- `resources/metadata_extract_prompt.txt` remains an optional helper file. Its
  contents are not displayed in the app, and its existence or usage is never a
  startup, import, processing, or validation requirement.
- New workspaces do not require or automatically receive a raw `data/`
  directory, `standardize.R`, `samples_config.yaml`, or a checklist copy.
- Structural checks run at import and on every load. They do not read expression
  matrix contents or certify scientific standardization correctness.
- Users are responsible for preparing aligned, scientifically appropriate data
  and for not replacing underlying inputs during an analysis. Replacement inputs
  belong in a new workspace. This overhaul adds no external-change monitoring,
  validation cache, or generalized data-replacement reconciliation system.
- Preparation scripts, notes, and source links are optional provenance. Snapshots
  remain available without a preparation script, checklist, or sample YAML.

## 2. Target creation journey

1. The user prepares a directory outside the app with `Samples.csv` and sample
   subdirectories. The source directory itself need not be named `processed_data`.
2. In **Create New Dataset**, the user enters a dataset name, selects that
   directory, and chooses the destination parent (default: configured datasets
   directory). No standardization-template or metadata-prompt step is shown.
3. The app checks the input structure and reports all detected issues together,
   with sample names, expected paths, and concrete corrections.
4. If valid, the app copies the source tree into the new workspace's
   `processed_data/`. It creates its analysis configuration, selections,
   persistent workflow/storage state, and runtime directories.
5. The app opens the new dataset through the same loading path used for existing
   workspaces. The user can immediately choose samples for clustering.

Copy inputs rather than move them or analyze the source directory in place:
annotation saves currently rewrite the workspace's `Cells.csv`. The original
prepared files must remain unchanged. Show the resolved source/destination and
real copy progress for large imports. Do not add an extra approval step.

The directory browser should use `shinyFiles` or an equivalent cross-platform
implementation; declare any added dependency in `DESCRIPTION` and installation
instructions. Keep direct path entry available for mounted/shared directories.
When running remotely, selection browses server-accessible paths. Browser-local
directory uploads and transferring data to a remote server are outside scope.

## 3. Prepared-input contract

### Directory and filename rules

For new imports, document this structure in the README:

```text
<prepared-directory>/
  Samples.csv
  <sample>/
    Exp_data_<matrix_state>.mtx
    Genes.txt
    Cells.csv
```

- Every `sample` in `Samples.csv` has exactly one same-named immediate directory.
  Unexpected sample directories are reported rather than silently analyzed.
- Match spelling and capitalization exactly on both operating systems. Reject
  sample names that escape a directory segment or collide under case-insensitive
  matching, so an accepted dataset remains portable to Windows and Linux.
- Use the existing supported matrix filename conventions for UMI counts, TPM,
  and CPM. For the initial implementation, require one unambiguous expression
  format across the dataset, matching the current dataset-wide `std_names` model.
  Determine the format from filenames and generate `dataset_config.yaml`
  accordingly; do not inspect matrix values to infer it. Report ambiguous or
  mixed formats with an actionable error rather than guessing.
- Existing workspaces retain their configured `std_names` filenames. This
  overhaul does not rename their scientific input files.

### Sample metadata

- `Samples.csv` is readable CSV with a header and at least one sample row.
- Read sample/patient identifiers and descriptive metadata as text, preserving
  leading zeros. Use explicit conversion only where numeric values are needed.
- `sample` is a non-empty, unique canonical identifier, never an inferred row
  number. Sample selection/order and metadata lookup use this table consistently.
- As an implementation default, retain the current documented metadata headers
  from `build_samples()` plus `n_cells`. Unknown metadata values can be blank;
  header presence does not require a clinical value to be known. Preserve extra
  user columns. List the actual headers and blank-value rules in the README.
- The user supplies `Samples.csv`, including final standardized cell counts in
  `n_cells`. The lightweight checker does not verify those counts against cells
  or matrix dimensions. The app does not regenerate or overwrite this table.
- If old sample YAML disagrees with `Samples.csv`, the CSV wins. Do not merge
  fields from YAML or silently switch metadata sources.

### Scientific requirements documented, but not audited at import

Document matrix orientation (genes by cells), positional alignment with gene and
cell files, supported expression scales, gene identifiers, dataset-wide cell ID
uniqueness, and required cell columns:
`cell_name`, `sample`, `cell_type`, `complexity`, `cell_subtype`, `patient`,
`subclone`, and `source`.

Explain optional/unknown annotation values and that `complexity` is the number
of detected genes per cell, currently calculated as the number of nonzero
matrix entries in that column. State expectations for duplicate genes,
normalization, and cell/sample metadata consistency without requiring any
particular preparation helper or script.

These are user preparation obligations. The structural checker does not read
cell/gene contents, load matrices, compare dimensions, calculate complexity,
validate biological labels, or reconstruct upstream provenance. Existing
analysis-time errors and cache safeguards remain in place.

## 4. Implementation steps

| Step | Work | Completion boundary |
| --- | --- | --- |
| P01 | Define the README input contract and shared structural checker. | One explicit contract; structured errors; no matrix/content scan. |
| P02 | Move runtime sample metadata to `Samples.csv`. | Loading, annotation, and marker selection share the CSV authority without sample YAML. |
| P03 | Implement directory selection and prepared-data creation. | A valid selected directory becomes an immediately usable, independent workspace. |
| P04 | Remove standardization and prompt UI/dependencies. | No app screen or startup dependency requires the optional preparation materials. |
| P05 | Integrate workflow state, existing workspaces, storage, and snapshots. | Imported and existing workspaces use the analysis/storage lifecycle without a preparation script or YAML requirement. |
| P06 | Update guidance and the optional metadata prompt. | Documentation and helper outputs match the actual CSV import contract. |
| P06a | Align DE/CNA computation console progress and timing with clustering. | Batch and single-sample computation report stages, step/sample elapsed time, outcomes, and batch totals without changing scientific behavior. |
| P06b | Fix cache portability when an existing workspace is copied or moved. | Valid relocated caches preserve scientific progress; changed or damaged contents still invalidate affected work. |
| P07 | Complete focused regressions, full checks, and platform acceptance. | Evidence satisfies the completion requirements in section 6. |

### Implementation progress checklist

Update this checklist when each step is implemented and its focused checks
pass. Add dated evidence below the relevant step, and leave incomplete work
unchecked. Step completion is separate from the final acceptance in section 6.

- [x] **P01:** README contract, reusable structural checker, and focused tests.
- [x] **P02:** Runtime sample metadata supplied exclusively by `Samples.csv`.
- [x] **P03:** Directory selection, independent import copy, and immediate opening.
- [x] **P04:** Standardization/prompt UI and mandatory preparation resources removed.
- [x] **P05:** Workflow state, existing workspaces, storage, and snapshots integrated.
- [x] **P06:** User guidance and optional metadata extraction prompt aligned.
- [x] **P06a:** DE/CNA console progress, step timing, and batch summaries aligned.
- [x] **P06b:** Existing-workspace relocation preserves valid caches and progress.
- [ ] **P07:** Full regression suite, browser review, and Windows/Linux acceptance.

### P01: Contract and structural checking

- Introduce a reusable checker for import and ordinary dataset loading; connect
  those application flows in P02/P03 once their metadata/import changes exist.
- Read `Samples.csv` and check the required headers, non-empty/unique safe
  sample IDs, exact folder correspondence, and required filenames.
- Required paths must resolve to readable files, not directories, and files
  must be non-empty. Do not interpret non-empty as scientifically valid.
- Collect issues into one report rather than forcing one repair per attempt.
  Use wording such as **Input structure check passed**; do not claim strict
  standardization validation.
- Run on every load. Do not introduce checksums, fingerprints, deep validation,
  or persisted validation-result caching for this feature. Existing snapshot
  checksums and scientific cache validation are separate and remain unchanged.

Likely touchpoints: `util_scripts/01_utils_io.R`,
`util_scripts/03_utils_misc.R`, and `app/server/dataset_server.R`.

**Implementation record (2026-11-04):**

- [x] Added the complete [README input contract](../../README.md#preparing-input-data),
  including metadata headers, filename conventions, sample/cell/gene alignment,
  scientific responsibilities, and the lightweight check's limits. A transition
  notice explains that the app still uses its old setup until P02-P04 land.
- [x] Added `read_prepared_samples()` in
  [01_utils_io.R](../../util_scripts/01_utils_io.R), preserving all columns as
  text, leading zeros, extra metadata, CSV quoting/newlines, UTF-8, and optional
  BOMs. Malformed record widths are rejected rather than silently shifting
  fields into implicit row names. Parse failures close their file connections.
- [x] Added `prepared_sample_columns()` and `check_prepared_data()` in
  [17_utils_prepared_data.R](../../util_scripts/17_utils_prepared_data.R).
  The result contains `valid`, structured errors with sample/path context,
  aggregate display text, parsed metadata, resolved filenames/expression type,
  and CSV-ordered paths only on success. Automatic filenames and configured
  legacy names are supported. File contents other than the sample CSV remain
  unread; inputs are unchanged and no validation cache/state is written.
- [x] Added [P01 regression tests](../../tests/testthat/test-p01-prepared-data.R)
  for valid formats, metadata preservation, malformed CSV, missing headers/rows,
  unsafe/duplicate IDs, exact capitalization, missing/extra folders, missing,
  empty, unreadable or directory-instead-of-file inputs, matrix ambiguity/mixed
  formats, legacy names, aggregate errors, and the bounded read-only scope.
- [x] Ran P01 plus existing I/O, misc/standardization, general-template,
  application bootstrap, and component tests: **485 assertions passed; zero
  failures, errors, test warnings, or skips** on Windows, R 4.5.3, with the
  `English_United States.utf8` locale. The P01 test file accounts for 104 of
  those assertions. Local runner/log/results are under
  `artifacts/local-checks/p01_check.R`, `p01_checks.log`, and
  `p01_test_results.rds` (gitignored).

Reproduce the focused selection from the repository root in R:

```r
testthat::test_dir(
  "tests/testthat",
  filter = "^(p01-prepared-data|01_utils_io|03_utils_misc|standardize-general-template|app-bootstrap|app-components)$",
  reporter = "summary"
)
```

At the P01 boundary, the checker was available when utilities were sourced but
not yet called by the dataset loader or creation handler. P02 connects loading;
creation remains P03. No Linux execution, browser import journey, full-suite
acceptance, or representative-data timing is claimed by this P01 record.

### P02: One runtime sample metadata source

- Load the authoritative table once per dataset load and keep it in session
  state with a clear name such as `samples` or `sample_metadata`.
- Remove the load-time dependency on `samples_config.yaml`, including the
  `rv$samples_config` prerequisite in annotation/CNA reference selection.
- Make marker selection, cancer-type display, sample lists, and sample lookups
  use that same table. Preserve the existing single-unambiguous-cancer-type
  marker behavior; changing marker selection policy is outside scope.
- Establish sample paths from CSV identifiers rather than independently
  enumerating directories with a potentially different order.
- Update clearing/switching behavior so metadata from the previous dataset
  cannot survive a failed load or contaminate the next workspace.

Likely touchpoints: `app/state.R`, `app/server/dataset_server.R`,
`app/server/annotation_server.R`, and component/server fixtures.

**Implementation record (2026-11-04):**

- [x] Connected the P01 structural checker to every dataset load using that
  workspace's configured filenames. Blocking failures produce a scrollable
  aggregate report and a failed-load event before dataset state is published.
  No fallback to YAML or directory-derived membership is permitted.
- [x] Store the checker-returned table as `sample_metadata` in session state.
  Reuse its CSV-ordered paths for sample selectors and analysis; remove the
  second metadata read previously used for malignant-marker selection.
- [x] Read annotation's cancer-type display from the same CSV table, with
  `Unknown` for blank metadata. Preserve the existing single-unambiguous-cancer
  marker policy, including ignoring unknown blank values.
- [x] Clear sample metadata with all dataset-owned state on dataset changes and
  before replacement loads, including unsuccessful loads. Existing unsaved-edit,
  active-action, archived-state, annotation, and CNA navigation guards remain.
- [x] Preserve review-only loading of archived workspaces with missing or damaged
  retained sample files, using valid CSV membership/metadata and recorded retired
  storage state. CSV/schema/membership errors remain blocking. Existing archive
  audits still prevent editing or unsafe exports; load events record whether
  structure passed or damaged-input archive review was allowed.
- [x] Update server/browser fixtures to supply complete authoritative CSVs and
  extend the existing dataset-transition tests with P02 behavioral coverage:
  absent/conflicting/corrupt YAML, CSV order and text preservation, one metadata
  read per load, per-sample annotation labels, missing/changed input rechecks,
  failed-load cleanup, and single/mixed/blank/unrecognized cancer-type markers.
- [x] Final focused regression selection passed **622 assertions**, with zero failures,
  errors, test warnings, or skips on Windows, R 4.5.3, UTF-8 locale. The selection
  includes P01, dataset transitions, annotation save/recovery and previews,
  bootstrap/components, and the still-supported onboarding screens. Local
  evidence: `artifacts/local-checks/p02_check.R`, `p02_focused_final_checks.log`, and
  `p02_focused_results.rds` (gitignored).
- [x] Final full regression suite passed **4,036 assertions**, with **zero
  failures, errors, test warnings, or skips**, including browser journeys and
  existing screenshot comparisons. Covered dataset switching, archived damage,
  annotation/CNA, cleanup/reopen, exports, and review snapshots. Screenshot
  baseline updates were disabled. The run used Windows, R 4.5.3, UTF-8 locale,
  and the configured Edge browser. Browser execution required running outside
  the sandbox so Windows process pipes could be created. Authoritative local
  evidence: `artifacts/local-checks/p02_full_check.R`,
  `p02_full_final_checks.log`, and `p02_full_results.rds` (gitignored).

Reproduce the final regression gate from the repository root with
`testthat::test_dir("tests/testthat", reporter = "summary")` in the configured
R/browser environment. No Linux execution or new import UI journey is claimed;
those remain later acceptance work.

Dataset creation still uses the old preparation template until P03, preparation
UI removal remains P04, and snapshot provenance requirements remain P05. This
step removes YAML from runtime loading/annotation; it does not yet remove the
snapshot YAML requirement or claim end-to-end CSV-only import acceptance. The
README transition note now reflects this implementation boundary.

### P03: Creation and copy lifecycle

- Replace the current template-selection dialog with name, source directory,
  and destination parent fields plus browse controls/path fallbacks.
- Preserve dataset-name/path validation, no-overwrite behavior, and existing
  protection against duplicate submissions or conflicting active actions.
- Validate before copying; keep an incomplete copy out of the available-dataset
  list. Handle failed/interrupted copies without opening a partial workspace or
  modifying the source. A small staging-and-publish flow is sufficient; do not
  add a resumable import subsystem or an exhaustive filesystem failure model.
- Prevent source/destination overlap that would recursively copy the import
  into itself. Cleanup must target only temporary/new paths owned by this import.
- Create the usual app-owned `cache/`, `results/`, and `logs/` directories and
  generated configuration/state. Do not copy a standardization template or
  create sample YAML, raw-data directories, or checklist copies.
- Update available choices immediately and use the common loader to open the
  created workspace without a restart. A destination outside the configured
  datasets parent must still open in the current session; document that later
  automatic discovery scans the configured datasets parent, as today.

Likely touchpoints: dataset UI/server, common loading helpers,
`templates/dataset_config_template.yaml`, `general_config.yaml`, and dependencies.

**Implementation record (2026-11-04):**

- [x] Replace template-based creation with a prepared-directory import dialog.
  Source and parent paths are editable and have an in-app directory browser
  with Go, Up, Home, Datasets, Open subdirectory, and Use this directory actions.
  The form preserves its draft while browsing, shows resolved source/workspace
  paths, downloads the README specification, and keeps validation errors visible
  for correction/retry. Full-width fields and a scrolling body keep long paths
  readable; browser controls appear near the top while browsing.
- [x] Implement binary copying and staged initialization in
  [18_utils_dataset_import.R](../../util_scripts/18_utils_dataset_import.R).
  Validate before copying, reject source/destination overlap and existing
  destinations, and reject child symbolic links that would compromise an
  independent copy. Copy in bounded chunks with actual byte/MiB and elapsed-time
  progress, check the copied structure, and publish by sibling-directory rename.
  Normal failures remove only the staging directory owned by this import.
- [x] Exclude `.prepared-import-*` staging directories from app discovery in
  `app/context.R` and session choice refreshes. A terminated process can leave
  hidden staging, which remains unavailable as a dataset; no resumable import
  or automatic cleanup of another process's staging was added. Portable dataset
  names also reject Windows device-name extensions and trailing-period aliases.
- [x] Generate analysis configuration from the existing analysis template with
  detected matrix filenames, selected state for every CSV sample, active storage
  state, and completed input readiness with `validation_scope: structure_only`.
  All analysis steps start as not started. Create no raw-data folder, sample
  YAML, preparation script, or checklist copy. Source files remain unchanged.
- [x] Extract the ordinary dataset-load handler into the shared guarded loader.
  Creation releases its action guard and opens the published workspace through
  that loader immediately. Default-parent imports remain discoverable after a
  restart; external-parent imports are registered for selection/reload only in
  the current session. Prevent session name collisions and duplicate publication;
  preserve active-action/unsaved-annotation guards and cancellation semantics.
- [x] Add [P03 tests](../../tests/testthat/test-p03-dataset-import.R) covering
  counts/TPM/CPM imports, byte-identical copying, source independence, byte
  progress, ready analysis state, rollback, overlap/no-overwrite/name guards,
  hidden staging, cancellation, retry, directory navigation, external import,
  and session reload. Update legacy creation tests to the new behavior while
  retaining older-document tests until P04.
- [x] Add a real browser journey in
  [test-app-ui-baseline.R](../../tests/testthat/test-app-ui-baseline.R): cancel
  creation, browse both paths, import without optional preparation files, open
  immediately, run real synthetic clustering, switch datasets, and reload the
  external workspace without restarting. Source hashes remain unchanged.
- [x] Update the README creation instructions and visually inspect the final
  desktop dialog/browser screenshots. Review the Dataset Selection screenshot
  change and update only `01-dataset-selection.png` to replace the obsolete
  mandatory-standardization message. Other reviewed baselines remain unchanged.

**Verification:** Final focused selection passed **653 assertions** and the
final two-browser-case rerun passed **53 assertions**, all without failures,
errors, test warnings, or skips. The complete suite first ran **4,179 assertions**
with one expected Dataset Selection baseline mismatch. After the visual baseline
review and final layout/name-validation refinements, focused and affected-browser
reruns were reconciled against the complete suite by file/test identity:
**4,181 assertions verified, zero remaining failures/errors/warnings/skips**.
This verification combines the full run and targeted follow-up; the original
full-run result is preserved alongside the final reconciled evidence.

Local, gitignored evidence lives under `artifacts/local-checks/`:
`p03_full_check.R`, `p03_full_checks.log`, `p03_full_results.rds`,
`p03_check.R`, `p03_focused_final_checks.log`, `p03_focused_results.rds`,
`p03_browser_final_check.R`, `p03_browser_final_checks.log`,
`p03_browser_final_results.rds`, `p03_verify_results.R`, and
`p03_verified_results.rds`. The browser runner derives the two selected cases
from the permanent test file and explicitly uses the reviewed fixture directory.
Final screenshots use the `p03-folder-browser-*` and `p03-import-dialog-*` names.
Browser execution required Windows pipe permissions outside the sandbox; runs
kept automatic screenshot baseline updates disabled. Windows, R 4.5.3, UTF-8
locale, and Edge were exercised. Linux execution and representative large-data
timings remain P07 acceptance work.

No dependency was added: the directory browser uses Shiny and existing R/filesystem
utilities. The analysis template remains packaged and is adapted during import;
existing dataset configuration and optional preparation templates are preserved.
Preparation guide/prompt cleanup remains P04, and snapshot YAML provenance
requirements remain P05. P03 does not close those later steps or final acceptance.

### P04: Remove preparation screens and mandatory resources

- Remove the Dataset Selection **Standardization Guide** tab and its document
  modals, download/copy actions, clipboard handlers, and creation-success
  instructions to run `standardize.R`.
- Remove the separate **Reference Data** prompt screen, Start Menu button, and
  associated navigation/show/hide/select-all handlers. It currently also displays
  the metadata extraction prompt and must not remain as a second entry point.
- Stop reading/validating the prompt file in `create_app_context()` and remove
  prompt-text plumbing through UI constructors/resources. Missing prompt,
  checklist, or template files must not prevent ordinary app startup/import.
- Remove only obsolete onboarding-specific helpers, dependencies, and resource
  registrations. Keep anything still used by other app features or retained
  optional preparation tools; do not delete dataset scripts or user notes.
- Replace obsolete user messages with prepared-input/structure-check guidance.
  The workflow overview should describe input readiness rather than instruct
  users to carry out standardization inside the app.

Likely touchpoints: `app/context.R`, `app/ui/app_ui.R`,
`app/ui/dataset_ui.R`, `app/ui/dashboard_ui.R`, `app/server/app_server.R`,
`app/server/dataset_server.R`, `app/server/dashboard_server.R`,
`util_scripts/13_utils_onboarding.R`, and `app.R`.

**Implementation record (2026-11-04):**

- [x] Simplify Dataset Selection to the prepared-data workspace card. Remove
  the Standardization Guide, checklist/Markdown modals and downloads, copy/select
  prompt controls, obsolete creation-success instructions, and their handlers.
  Keep the prepared-input README download and current import/directory browser.
- [x] Remove the Reference Data prompt screen, Start Menu Utilities card, and
  every associated show/hide/navigation/select-all handler. The analysis gene-
  clipboard feature is retained; this change removes metadata-prompt features.
- [x] Stop reading or validating the prompt in `create_app_context()`. Remove
  its resource/label/clipboard-text fields and UI constructor arguments. The
  optional `metadata_prompt` location remains documented in general configuration
  as an external aid; the key and file can both be absent at runtime.
- [x] Delete the unused onboarding utility module, its obsolete tests, the
  unused `pipeline-docs` resource registration, the `commonmark` app dependency,
  and the unused standardization-template selector setting. No dataset scripts,
  checklist notes, optional preparation templates, or prompt files were deleted.
- [x] Rename the visible readiness badge to **Prepared inputs** and align
  clustering guard messages. Keep the stored `standardization` state key and
  existing scientific statuses/dependency behavior unchanged.
- [x] Update README setup/requirements and the User Guide's setup/resource/test
  references. Optional guidance is accessed directly in the repository; broader
  preparation-document/prompt-format work remains P06.
- [x] Add [P04 regressions](../../tests/testthat/test-p04-preparation-ui.R) for
  startup without preparation files or prompt configuration, retained biological
  resource validation, complete-UI absence of old controls/content, prepared-input
  wording, import/loading, README download without a docs directory, and inert
  obsolete input IDs. Extend the browser import journey to start with neither
  prompt file nor key and check absence of both removed screen entry points.
- [x] Final focused selection passed **637 assertions**, with zero failures,
  errors, test warnings, or skips. The run covers P01/P03/P04, dataset transitions,
  app bootstrap/components, and workflow overview. Tests isolate compiler caches
  in temporary directories. Evidence: `artifacts/local-checks/p04_check.R`,
  `p04_focused_checks.log`, and `p04_focused_results.rds` (gitignored).
- [x] Visually inspect all six candidate UI references and refresh the Windows
  baselines for the simpler selection card, removed navbar/menu entry, and
  prepared-input badge. Analysis plots and controls retain their existing content.
  Candidate captures are in `artifacts/local-checks/p04-ui-review/`; review used
  `p04_browser_check.R` / `p04_browser_review_checks.log` with automatic baseline
  updates disabled. The subsequent full run verifies the reviewed references.

- [x] Final full regression suite passed **4,116 assertions**, with **zero
  failures, errors, test warnings, or skips**, including all reviewed screenshot
  comparisons and the browser import/clustering/reload journey with no prompt
  file or configuration key. Automatic baseline updates remained disabled.
  Windows, R 4.5.3, UTF-8 locale, and Edge were exercised. Browser execution used
  permissions outside the sandbox for Windows process pipes. Authoritative local
  evidence: `artifacts/local-checks/p04_full_check.R`, `p04_full_checks.log`, and
  `p04_full_results.rds` (gitignored).

Reproduce the full gate with `testthat::test_dir("tests/testthat", reporter =
"summary")` in the configured R/browser environment. Linux execution remains P07
acceptance work. Snapshot provenance still has its legacy YAML requirement until
P05; P04 does not close that step or the overall implementation acceptance.

### P05: State, existing workspaces, and review snapshots

- Retain the internal dataset-scoped `standardization` state key for this
  overhaul to avoid an unrelated state-schema migration. For new imports,
  completion means prepared inputs passed the structural check and were
  successfully installed; record that limited meaning in event/state details.
  Do not emit a misleading claim of strict scientific validation.
- Initialize every imported sample with analysis not started, and initialize
  selected/storage state through existing helpers. Clustering readiness must
  succeed immediately after successful creation.
- Load existing completed/active/archived workspaces using their `Samples.csv`
  and configured filenames, preserving saved scientific decisions, state, and
  existing cache/storage behavior. Do not reset progress on each successful
  structural check or weaken existing corrupted-state/archived-damage guards.
- Existing scripts, raw folders, YAML, and checklist notes remain untouched.
  If `Samples.csv` is missing, report that required file; do not silently fall
  back to YAML or infer metadata from directory names.
- Remove `samples_config.yaml` from the mandatory snapshot provenance list.
  Keep it, preparation scripts, and checklist notes optional when present;
  intentional absence in new workspaces should not create omission warnings.
- Preserve the authoritative `Samples.csv` in the complete `processed_data`
  snapshot tree. Preserve snapshot manifests/checksums, annotation/filtering
  summaries, cache-cleanup independence, and optional CNA export behavior.
- Record a minimal creation/import event and the structural-check scope using
  existing logging. No new provenance-input requirement or content hashing.

Likely touchpoints: `util_scripts/07_utils_state.R`,
`util_scripts/09_utils_pipeline_overview.R`, `util_scripts/11_utils_storage.R`,
`app/server/dashboard_server.R`, `app/server/snapshot_server.R`, and
`util_scripts/14_utils_snapshots.R`.

**Implementation record (2026-11-11):**

- [x] Verify the P03 import lifecycle already retains the dataset-scoped
  `standardization` key, records `prepared_data_import` and `structure_only` in
  its completion details and creation event, initializes every sample as
  `not_started`, and creates selected/storage state through existing helpers.
  Keep this behavior and the existing state schema; no additional migration or
  content validation was introduced.
- [x] Remove sample YAML from mandatory snapshot provenance in
  [14_utils_snapshots.R](../../util_scripts/14_utils_snapshots.R). Include existing
  sample YAML, `standardize.R`, and checklist notes unchanged when present;
  skip absent optional preparation files without warnings. Dataset/selected
  configuration and historical workflow state remain required. Snapshot
  manifests, checksums, complete processed inputs, summaries, and optional CNA
  rules remain intact.
- [x] Let [snapshot server arguments](../../app/server/snapshot_server.R) work
  without the optional general-config sample-YAML setting, while preserving
  configured legacy provenance paths when supplied. Replace the storage
  completion guard's obsolete standardization wording with prepared-input wording.
- [x] Extend [dataset transition coverage](../../tests/testthat/test-c01-dataset-transitions.R)
  to repeatedly switch/reload active and archived existing workspaces with
  legacy filenames and saved completed scientific decisions. Verify workflow
  steps/history, selected decisions, storage state, raw inputs, scripts, YAML,
  notes, configuration, and processed inputs remain unchanged. Retain existing
  CSV-authority, missing-CSV, failed-load, cache, and archive-damage safeguards.
- [x] Extend [snapshot coverage](../../tests/testthat/test-f17-review-snapshots.R)
  with real CSV-only import followed by deterministic completed-analysis
  fixtures. Verify immediate clustering readiness, limited-scope creation events,
  warning-free folder and ZIP snapshots before/after real cache cleanup, complete
  processed data and authoritative CSV (including leading zeros/extra metadata),
  manifest checksums, summaries, and unchanged source/state. This fixture installs
  finished synthetic results; actual clustering remains covered by the P03
  browser journey. Also test optional-provenance byte preservation and continued
  rejection of missing mandatory configuration/state.
- [x] Correct the README and User Guide's P05 transition notices and snapshot
  provenance description. Broader guidance/template/prompt alignment remains P06.

- [x] The final focused selection passed **1,300 assertions**, with zero
  failures, errors, test warnings, or skips, as a subset of the full run. It
  covers import, dataset transitions, persistent state, overview, storage, and
  snapshots. The standalone reload regression also passed after correcting its
  fixture to preserve the existing state revision rather than overwrite it.
- [x] Verify **4,251 assertions** across the full run and an isolated **39-assertion
  browser-case rerun**, with **zero remaining failures, errors, test warnings, or
  skips**. The original full run had one Start Menu screenshot mismatch confined
  to the dash in the next-attention line: changing the inherited worker locale
  changed its rendering. The rerun preserved the original Shiny worker locale
  while starting Chrome under a valid Windows locale, and all six existing
  references matched. No screenshot baseline was modified. This is reconciled
  full-run-plus-rerun evidence, rather than a claim that the original full run
  passed unchanged.

Authoritative local, gitignored evidence under `artifacts/local-checks/`:
`p05_full_check.R`, `p05_full_checks.log`, `p05_full_results.rds`,
`p05_browser_check.R`, `p05_browser_checks.log`, `p05_browser_results.rds`,
`p05_verify_results.R`, `p05_verified_checks.log`, `p05_verified_results.rds`, and
`p05_final_focused_results.rds`. The verification script replaces only the same
named browser case after asserting equal assertion counts and that no other
full-run case failed. The initial focused runner/log/results are retained too.
Windows, R 4.5.3, a UTF-8 parent session, and Edge were exercised. ZIP/browser
workers required permissions outside the sandbox for Windows process pipes;
automatic screenshot updates stayed disabled.

Reproduce the focused selection with `testthat::test_dir("tests/testthat",
filter = "^(f17-review-snapshots|f16-dataset-storage|07_utils_state|f10-pipeline-status-overview|p03-dataset-import|c01-dataset-transitions)$",
reporter = "summary")`; use `testthat::test_dir("tests/testthat", reporter =
"summary")` for the full gate in the configured R/browser environment. Keep the
browser worker locale consistent with the reviewed reference environment.
Windows-only verification does not close P07 Linux/platform acceptance or the
section 6 end-to-end acceptance checklist. Consistent worker-locale handling
remains relevant to P07's cross-platform screenshot review.

### P06: Documentation and optional preparation materials

- Rewrite README creation/setup instructions around prepared input, including
  the full contract, optional metadata fields, expression filenames, examples,
  copy semantics, platform behavior, and user responsibility for data alignment
  and replacement. Link the contract from the creation dialog without adding a
  new preparation tab.
- Align `docs/USER_GUIDE.md`, `docs/STANDARDIZATION_CHECKLIST.md`, pipeline
  state/logging references, directory diagrams, and snapshot documentation.
- Keep the checklist accessible as a file in `docs/`. Make it useful for users
  with their own scripts and clearly identify optional template/helper advice.
- Update `resources/metadata_extract_prompt.txt` to request CSV sample metadata
  with the documented headers, quoting, blank values, and one row per biological
  sample. Require no AI usage, credentials, invocation evidence, or completion
  marker. Keep conservative extraction guidance. Explain that publication cell
  counts must not substitute for standardized counts: users fill `n_cells`
  during preparation even if the optional prompt leaves that value blank.
- Existing templates/helpers may remain as optional tools. Identify their YAML
  dependency if retained; they must not be part of the required import path.
  Do not expand this work into a rewrite of every historical template.
- Add this plan to the development index. Preserve dated historical findings
  and acceptance evidence; identify superseded onboarding requirements rather
  than rewriting history as if this design were already implemented.

**Implementation record (2026-11-11):**

- [x] Align the [README](../../README.md) overview, preparation and creation
  guidance with externally prepared inputs and immediate analysis. Keep its
  complete input contract, expression filenames, CSV/blank-value rules, copy
  semantics, server-side browsing, source independence, and replacement-input
  responsibility. Add quoted-CSV/leading-zero examples and link the optional
  metadata prompt. The creation dialog's existing README download continues to
  provide the contract; no additional UI or preparation tab was needed.
- [x] Update the [User Guide](../USER_GUIDE.md): imported-workspace directory
  diagrams, CSV metadata authority, configured filenames, fresh analysis state,
  structural-check limits, and complete CSV-preserving snapshots. Move legacy
  sample-YAML and template instructions into a clearly optional helper section
  with explicit manual prerequisites and a separate preparation workspace.
- [x] Replace the [checklist](../STANDARDIZATION_CHECKLIST.md) with a general
  preparation reference usable with any scripts. Cover sample membership,
  counts, CSV quoting, scale, alignment, gene/cell IDs, scientific review,
  import, optional notes, snapshots, and replacement inputs. No script sentinel,
  YAML, strict report, checklist completion, or AI usage is an import requirement.
- [x] Rewrite the [optional prompt](../../resources/metadata_extract_prompt.txt)
  for a complete UTF-8 CSV with all 38 required headers and one row per
  biological sample. Preserve conservative patient/sample evidence, anatomical
  site, lesion size, treatment timing/modality, recurrence and site-occurrence
  distinctions. Explain quoting, blank values, text identifiers, exact sample
  mappings, and user review. Leave `n_cells` blank in extraction output and
  explicitly require users to fill final prepared counts before import; neither
  publication counts nor prompt usage validate standardization.
- [x] Align [state](../PIPELINE_STATE.md) and [logging](../PIPELINE_LOGGING.md)
  references with the retained `standardization` key, structure-only readiness,
  import/load events, unchanged progress on reload, optional legacy helper
  events, and existing archive safeguards.
- [x] Label the retained general R template as optional without changing its
  execution. Its YAML/helper dependencies and publication side effects remain
  documented. Do not rewrite historical technology-specific templates or any
  user dataset scripts/notes. Remove the obsolete documentation-only test that
  required the general checklist to prescribe that template's linear workflow;
  retain all executable template/helper safety and data-contract tests.
- [x] Identify this plan as the current onboarding direction in the development
  index and add dated supersession notices to earlier development/follow-up,
  Che2021 manual-review, and Liu2022 replay documents. Preserve their original
  findings, progress records, and outstanding release acceptance.
- [x] Focused regressions passed **495 assertions**, with **zero failures,
  errors, test warnings, or skips**, on Windows/R 4.5.3 with a UTF-8 locale.
  Coverage includes prepared-input checking, import, optional-file absence,
  bootstrap, logging/state, and executable legacy-template behavior. Local
  example checks also confirmed exact agreement between README/prompt headers
  and `prepared_sample_columns()`, then round-tripped quoted metadata, leading
  zeros, blanks, extra columns, and user-filled final counts through the real
  CSV reader and structural checker.
- [x] Check local file links and heading anchors across all changed Markdown
  documents, and review for obsolete mandatory preparation instructions outside
  explicitly historical/optional sections. `git diff --check` passes.

Reproduce focused coverage with `testthat::test_dir("tests/testthat", filter =
"^(p01-prepared-data|p03-dataset-import|p04-preparation-ui|standardize-general-template|app-bootstrap|06_utils_logging|07_utils_state)$",
reporter = "summary")`. Gitignored local evidence: `artifacts/local-checks/`
`p06_check.R`, `p06_focused_checks.log`, `p06_focused_results.rds`,
`p06_links.R`, and `p06_links.log`. This documentation/helper-comment change
introduces no runtime UI or analysis behavior; no new browser captures or
screenshot references were needed. The full suite was not rerun for P06.
The final full regression, browser/platform acceptance, Linux execution, and
representative-data timings remain P07; section 6 acceptance stays open.

### P06a: DE/CNA console progress and timing (added 2026-11-11)

- Follow clustering's sample/stage/detail console format for DE and CNA, in both
  batch and single-sample computation. Console output must work without a UI
  progress callback and must not duplicate DE messages when a batch wrapper runs it.
- Report elapsed time for completed steps, cumulative sample time, and batch
  totals with completed/failed/skipped/not-run counts. Label cache reuse, skipped
  samples, and failures accurately; do not print success for interrupted work.
- Include DE input loading, differential expression, marker matching,
  scoring/plots, and output writing; CNA preflight, matrix computation/reuse,
  matrix reshaping/cache writing, clustering/heatmaps, and signal/correlation.
- Use monotonic elapsed-time measurements at real stage boundaries. No invented
  percentages, timing thresholds, background telemetry, or new dependencies.
- Preserve existing progress-callback signatures, scientific calculations,
  outputs, cache/state rules, and error/continuation policy. Existing persistent
  event logs remain distinct from human-readable console diagnostics.
- Verify deterministic step/sample durations with a controlled clock, real
  numerical workflow regressions, and batch success/reuse/skip/failure behavior.
  Record focused tests here; final platform/full acceptance remains P07.

**Implementation record (2026-11-11):**

- [x] Add [console step timing](../../util_scripts/19_utils_console_progress.R)
  using the monotonic R elapsed-time clock. Stage starts show sample/operation,
  stage and detail; closing a stage reports its duration separately from total
  sample/operation elapsed time. Failure/skip outcomes close the active step
  without printing success, and a terminal reporter cannot emit a second outcome.
- [x] Connect standalone and batch DE in
  [05_utils_workflow.R](../../util_scripts/05_utils_workflow.R). Cover input
  loading, DE, marker matching, scoring/plotting, and output writing. Batch
  wrappers own console reporting without duplicate inner DE stage messages;
  their existing UI callback fields/fractions and fail-fast behavior remain.
- [x] Add always-on batch CNA sample boundaries, stage messages and totals,
  including skips, matrix reuse, isolated failures, not-run counts and elapsed
  time. Add the same high-level timing to single-sample CNA in
  [cna_compute_server.R](../../app/server/cna_compute_server.R). Count/report
  successful batch completion after its workflow-state callback succeeds, so a
  failed state save cannot produce a misleading completed message/count.
- [x] Time nested CNA matrix computation, reshaping/cache writing, Ward
  clustering/cache reuse, plot construction/output writing, and subclone-specific
  signal/correlation steps. Preserve calculations, output files, helper return
  values, cache rules, error classes, state transitions, and existing progress
  callback signatures. Failure/interruption cleanup reports incomplete work
  rather than success; no persistent event schema or timing store was added.
- [x] Extend the User Guide and logging reference with console examples, timing
  interpretation, nested-timer overlap, and the distinction from persistent logs.
- [x] Add [P06a regressions](../../tests/testthat/test-p06a-console-progress.R)
  for exact step versus cumulative durations with an injected clock, same-stage
  updates, terminal guards, standalone DE input failure, preserved CNA interrupt
  conditions, and callback-compatible CNA reuse/skip/failure/state-save behavior.
- [x] Final focused selection passed **668 assertions**, with **zero failures,
  errors, test warnings, or skips**, on Windows/R 4.5.3 with a UTF-8 locale.
  Coverage includes real DE/CNA/clustering helpers, golden numerical outputs,
  cache regressions, batch/progress callbacks, navigation/recovery, and application
  bootstrap/components. `git diff --check` passes. No UI layout or screenshot
  reference changed; full browser/platform acceptance remains P07.

Reproduce with `testthat::test_dir("tests/testthat", filter =
"^(p06a-console-progress|05_utils_workflow.*|02_utils_annotation.*|f07-batch-progress|m[05]-.*|f03-navigation-hardening|c04-cna-recovery-status|golden_outputs|regression_clustering|regression_cna_cache|app-bootstrap|app-components)$",
reporter = "summary")`. Gitignored local evidence:
`artifacts/local-checks/p06a_check.R`, `p06a_focused_checks.log`, and
`p06a_focused_results.rds`. The full suite and Linux execution were not rerun
for this added step; P07 and section 6 final acceptance remain open.

### P06b: Necessary fix for copied-workspace cache portability (2026-11-11)

**Status: Implemented and verified on WSL Ubuntu (2026-11-11). Final full-suite
and platform acceptance remain P07.**

WSL Ubuntu testing exposed false stale status after copying the nearly finished
`Tang2026_Colorectal` workspace from Windows into the Linux datasets directory.
Creating a fresh workspace from only its `processed_data/` and running the full
pipeline for one sample succeeded, as reported by the user. These are distinct
journeys: fresh import generates new caches, whereas copying an existing
workspace must preserve reusable caches and saved scientific progress.

**Diagnostic findings:**

- All **93 registered cache artifacts** exist and match their manifest byte
  sizes, but all 93 modification timestamps differ from the recorded values.
  `cache_check_available()` in
  [04_utils_caching.R](../../util_scripts/04_utils_caching.R) requires exact
  cache timestamp equality and therefore rejects every artifact at startup.
- Manifest source dependencies retain absolute Windows paths beginning with
  `C:/Users/p.berger/.../datasets/Tang2026_Colorectal/processed_data/`.
  The same availability check tests those original paths directly; they do not
  exist under WSL, although the corresponding files exist in the copied workspace.
  Either this path failure or the timestamp mismatch can reject a cache.
- For `CRC_N1`, the filtered-expression cache, source expression matrix, and
  gene list were checked against their recorded MD5 checksums; all three match.
  This verifies a false rejection of unchanged contents for that sample. It is
  not a full integrity or scientific validation of all 93 artifacts.
- `reconcile_pipeline_state_cache()` in
  [07_utils_state.R](../../util_scripts/07_utils_state.R) marks rejected
  clustering work stale and propagates that status downstream. The dataset
  loader persists the reconciled state. All **15 samples** now have stale
  clustering, recorded on 2026-11-11; the existing state backup still contains
  pre-load completed clustering records.
- Scientific dependency fingerprints already exclude source paths and mtimes
  to allow relocation. The startup metadata screen contradicts that intended
  behavior. Fresh imports avoid the failure by recording current Linux paths
  and timestamps when their caches are generated.

**Required implementation and recovery:**

- [x] Resolve dataset-owned source dependencies relative to the current
  workspace. Support legacy manifests containing absolute Windows or Linux
  paths without depending on the old location remaining accessible. Do not
  guess a source by basename or bind the copied workspace to another dataset.
- [x] Treat changed cache timestamps as a reason to verify integrity, rather
  than sufficient evidence of invalid contents. Verify recorded checksums
  before accepting relocated artifacts; preserve structural and scientific
  dependency validation when artifacts are consumed. Missing, changed,
  untracked, or damaged caches must still invalidate affected work.
- [x] Preserve the ordinary fast load path; keep relocation/integrity handling
  within the existing cache subsystem. This does not expand the prepared-input
  structural checker into a matrix audit, external-change monitor, or new
  validation-cache subsystem.
- [x] Provide a validated recovery path for workspaces already saved as stale
  solely because of relocation. Preserve state evidence and user decisions;
  do not blindly restore the backup or promote every stale stage to completed.
  Account for genuine upstream changes, failures, and intentional archive/reopen
  invalidation. Perform recovery checks on a disposable dataset copy first.
- [x] Add regressions for copied/moved workspaces, legacy Windows paths on
  Linux, changed timestamps with unchanged bytes, unavailable original paths,
  and genuinely missing/changed/corrupt dependencies or artifacts. Verify that
  valid saved statuses survive load and reload while genuine invalidation and
  archived-workspace behavior remain correct.
- [x] Repeat the Tang2026 copied-workspace journey on a disposable copy and
  record integrity coverage, state preservation, and any remaining limitations.
  Keep the user's successful fresh-import/single-sample report separate from
  automated regression evidence and final platform acceptance.

Likely touchpoints: `util_scripts/04_utils_caching.R`,
`util_scripts/07_utils_state.R`, `app/server/dataset_server.R`, cache/state and
dataset-transition tests, and `docs/CACHE_VALIDITY.md`.
The initial diagnostic investigation changed no code or dataset files.

**Implementation and verification record (2026-11-11):**

- [x] Resolve dataset-owned source dependencies against the current workspace,
  including legacy Windows and Linux paths. New records retain the originating
  dataset root for arbitrary internal source paths; legacy processed-data paths
  use their complete sample/file suffix rather than basename guesses. An
  accessible original cannot mask missing or changed files in the copy.
- [x] Require matching checksums when cache timestamps change or source paths
  relocate. Persist checksum-verified location metadata once during normal
  state reconciliation, under the manifest lock. Invalid records remain
  rejected; unchanged metadata retains the fast path. Scientific dependency
  fingerprints and completed statuses are not changed by this refresh.
- [x] Fix an additional portability defect discovered during recovery:
  `saveRDS(version = 2)` fingerprints included R's writer-version stamp and
  gzip's platform header. New fingerprints use uncompressed XDR with a fixed
  stamp, UTF-8 text, and a consistent dataframe representation that excludes
  data.table bookkeeping. Verify historical fingerprints using the original
  serialization profile when the current inputs reproduce them; preserve the
  existing precision-repair contract for historical fingerprints as well.
- [x] Add [explicit location recovery](../../scripts/recover_cache_location.R),
  with a read-only preview and `--apply`. Validate current scientific inputs,
  original cache checksums/structures, saved annotations and configuration,
  and the preserved state checkpoint before restoring stages through base CNA.
  For legacy cell hashes that cannot be reproduced, independently replay
  deterministic filtering and require an exact match to the saved matrix and
  clustered input rows. For legacy gene-position hashes, verify every used CNA
  coordinate and selected gene/cell against the saved matrix; reference-cell
  and upstream fingerprints must still match. Persist these verified bindings
  so subsequent dependency validation and annotation-only rewrites work.
- [x] Preserve both state generations and manifests in a dedicated
  `cache-location-recovery-*` directory before applying recovery. Normal loads
  never promote stale work. Genuine invalidation reasons, edited checkpoint
  details, changed parameters/decisions, missing/corrupt inputs, or retired
  storage block recovery. Later CNA decisions remain stale for review rather
  than being silently promoted. Completed workspaces can also be migrated
  without changing their statuses.
- [x] Add [P06b regressions](../../tests/testthat/test-p06b-cache-location.R)
  covering copied paths with spaces, both Windows slash conventions, missing
  copied inputs despite an accessible original, same-size source/cache changes,
  path traversal, metadata-only fast loading, one-time metadata refresh, reload
  preservation, historical Windows hashes, writer/attribute normalization,
  explicit recovery, genuine stale states, modified checkpoints, archives,
  annotation rewrites, deterministic replay mismatch, CNA coordinates, and
  reference changes. Focused cache/workflow/state/storage coverage passed
  **738 assertions**, with **zero failures, errors, warnings, or skips** on
  WSL Ubuntu / R 4.6.1.
- [x] Compare the finalized canonical fingerprint of the same 21,236-row cell
  table using the installed Windows R 4.5.3 and Linux R 4.6.1. Both produced
  `1041aaf8e9519e1e8f60bbe54a31c894`. This is a real cross-runtime fingerprint
  check, separate from complete Windows browser/platform acceptance.
- [x] Preview Tang recovery, then apply it to a disposable workspace with copied
  metadata and read-only-use links to scientific payloads. Repeat on the actual
  `Tang2026_Colorectal` workspace only after that check passed. Both runs restored
  **90 stage records across 15 samples**, exactly matching the pre-load checkpoint:
  all clustering/resolution/DE/annotation stages, six explicit CNA omissions,
  and nine completed base CNA computations. Deterministic filtering matched
  for all 15 samples; CNA coordinates matched for all nine computed samples.
  All **93 cache consumers** then passed full dependency validation, two reloads
  preserved progress, and before/after MD5 checks confirmed all **452 scientific
  files** (prepared inputs, cache payloads/backups, and results) were unchanged.
  State generations and manifests were retained in the dataset's recovery
  evidence directory. No PCA/UMAP rerun or scientific-output replacement occurred.

Focused checks can be reproduced with:

```r
testthat::test_dir(
  "tests/testthat",
  filter = "^(p06b-cache-location|04_utils_caching|07_utils_state|f15-r01-cache-precision|f16-dataset-storage|c04-cna-recovery-status|05_utils_workflow.*|f01-characterization)$",
  reporter = "summary"
)
```

See [cache validity and recovery guidance](../CACHE_VALIDITY.md) for the recovery
commands and limits. Gitignored evidence is in `artifacts/local-checks/`:
`p06b_focused_checks.log`, `p06b_focused_results.rds`,
`p06b_tang_preview.log`, `p06b_tang_copy_checks.log`,
`p06b_tang_recovery_checks.log`, and `p06b_tang_recovery_results.rds`.

Full-suite Linux acceptance remains open. Existing process-death recovery,
snapshot rollback/Unicode, and Windows-only `utils::shortPathName()` test failures
were reproduced against unchanged `HEAD` in an isolated checkout. Browser tests
are skipped because no Chromium browser is configured. A broader selection
excluding those three baseline-failing files passed **2,741 assertions**, with
zero failures/errors/warnings and **13 browser skips**, before the final focused
refinements. The final full-run evidence is recorded separately in
`p06b_full_final_checks.log` and `p06b_full_final_results.rds`: **3,468 assertions
passed**, **9 failed expectations and 3 errors**, **zero warnings**, and **13
browser skips**. All failures are confined to the same three baseline-failing
files (`test-c02-clustering-recovery.R`, `test-f17-review-snapshots.R`, and
`test-standardize-general-template.R`). Do not interpret P06b completion as a
passing full-suite or completed P07 platform acceptance.
`git diff --check` passes.

## 5. Verification plan

Use deterministic synthetic fixtures and temporary workspaces. Tests should
exercise the agreed behavior, not attempt to prove that every scientifically
incorrect dataset or every external modification can be detected.

| Area | Necessary or proposed checks |
| --- | --- |
| Structural checker | Valid one/multiple-sample imports; unreadable/missing/empty CSV; missing headers; no rows; blank/duplicate/unsafe IDs; exact case/folder matching; missing/extra sample directory; missing/empty required file; ambiguity in matrix naming. Errors report all relevant paths/samples. |
| Bounded validation scope | Checker succeeds without reading matrix/gene/cell contents; instrument or replace matrix readers to fail if called. Scientifically malformed non-empty contents remain outside its promise and fail later if encountered by analysis. |
| CSV authority | A dataset without sample YAML loads; conflicting old YAML cannot influence metadata; leading-zero IDs, quoted commas, blank fields, and extra columns survive. CSV sample ordering agrees with paths and annotation metadata. |
| Creation | Import creates independent copied inputs and generated app files; source is unchanged; no raw folder/script/YAML/checklist is created; cancellation makes no workspace; existing destinations are not overwritten; duplicate submissions do not create duplicate workspaces; a simulated copy failure cannot open/discover a partial dataset. |
| Immediate analysis | Create then open through the normal loader, choose clustering samples, and begin analysis without restarting R or manually repairing state/configuration. |
| UI and optional files | Standardization/prompt panels and menu actions are absent; browser/path inputs are usable; no obsolete clipboard/navigation observer remains; startup/import work with the prompt/checklist/preparation template files absent. |
| Dataset transitions | Switch between imported and existing workspaces, reload, and fail a load without carrying metadata or selections across datasets. Preserve unsaved-annotation guards and archived-state behavior. |
| Workspace relocation | Copy/move an analyzed workspace, including Windows-to-WSL legacy paths and changed timestamps. Verify unchanged caches retain progress after integrity checks; genuinely missing/changed/corrupt files still invalidate affected work. Cover recovery from previously persisted false stale status (P06b). |
| Analysis regression | On a valid small fixture, run clustering, resolution, DE, annotation save/reload, and CNA finalize or explicit omission. Saving annotations does not incorrectly invalidate clustering. |
| Console computation progress | DE/CNA batch and single-sample stages show real step/sample elapsed time; cache reuse, skips, failures and batch counts are accurate. Verify callback compatibility and no false success on interruption/state-save failure. |
| Snapshots/storage | An imported finished workspace without preparation files or YAML can create folder/ZIP snapshots containing unchanged prepared matrices/genes, current cells, and authoritative CSV; manifests verify. Existing optional preparation provenance can be retained; cleanup/reopen and required-damage guards remain correct. |
| Windows and Linux | Exercise browsing/path selection, spaces/Unicode paths, readable shared/mounted locations, import/reload, exact case matching, and destination discovery behavior. Record each platform actually exercised; a Windows-only run cannot close Linux acceptance. |
| Performance | Measure structural checking separately from copying and existing cache/state reconciliation on representative data. Confirm the checker does not scale with matrix bytes; avoid a hardware-specific hard time limit or a new performance subsystem. |

Update or replace tests that deliberately enforce the old workflow, especially
`test-f06-standardization-onboarding.R` and
`test-f15-r05-onboarding-documents.R`. Update component/bootstrap, annotation,
dataset-transition, state, storage, snapshot, and integration fixtures that
currently require sample YAML or prompt UI. Retain optional-helper tests where
the supported helper behavior remains. Review UI baseline changes visually;
do not accept every changed screenshot automatically.

Run focused tests while implementing, then the full repository suite using the
documented test command (`devtools::test()`). Run browser coverage for changed
creation/navigation paths and record manual folder-picker evidence on both
operating systems where browser automation cannot exercise the picker reliably.
Use disposable copies for any existing scientific dataset acceptance checks.
Keep local runners/logs in `artifacts/local-checks/`, not in `datasets/`.

## 6. Requirements for completed implementation

All items below must have implementation and verification evidence before this
plan is marked complete. Automated results and manual/platform acceptance must
be recorded separately, with unresolved items explicitly left open.

- [ ] A user can create and immediately analyze a dataset from only the prepared
  directory; no app restart, custom template adaptation, user-supplied sample
  YAML, prompt, or checklist usage is needed.
- [ ] Windows and Linux directory browsing/path entry and import/reload have
  been exercised successfully, including paths with spaces.
- [ ] Creation copies inputs, leaves the source unchanged, never overwrites an
  existing workspace, and does not publish a failed partial import.
- [ ] `Samples.csv` supplies all runtime sample membership/metadata consistently,
  including annotation and marker selection. Sample YAML is neither required
  nor a fallback authority.
- [ ] Shared lightweight structural checks run at creation and every load, give
  actionable aggregate errors, and do not load matrices or claim scientific
  correctness. No validation caching/change-monitoring subsystem was added.
- [ ] Matrix filename/scale handling is unambiguous and generated configuration
  points to the imported files; existing configured names remain supported.
- [ ] The app contains no standardization guide/checklist workflow or metadata
  extraction prompt screen. Missing optional preparation files cannot prevent
  startup, creation, loading, analysis, or snapshots.
- [ ] Workflow state allows clustering immediately after import and preserves
  existing scientific progress on reload. Routine annotation saves, cache
  safeguards, cleanup/reopen, and interrupted-run recovery retain their behavior.
- [ ] Existing usable workspaces load without destructive migration or changes
  to their scripts, notes, raw files, or saved scientific results.
- [x] P06b is implemented and verified: copying or moving an existing workspace
  across Windows/Linux does not mark unchanged caches and completed downstream
  work stale solely because paths or timestamps changed. Previously persisted
  false stale status has a validated recovery path; genuine invalidation remains.
- [ ] Review snapshots work without sample YAML, scripts, or checklists and
  retain complete processed data, authoritative CSV, results, summaries, and
  integrity verification before and after cache cleanup.
- [ ] README input specification, User Guide, optional checklist/prompt, and
  state/logging/snapshot documentation agree with the implementation. Users can
  prepare data without reading application internals.
- [ ] Focused regressions and the full suite pass; changed browser flows and
  screenshots are reviewed. Counts, platform coverage, timings, and remaining
  limitations are recorded without claiming unperformed tests.

The implementation record should list affected files, test commands/results,
Windows/Linux manual outcomes, representative structural-check and copy
durations, and links to evidence. The implementation records above close only
their individual progress items; end-to-end acceptance requirements remain open.
