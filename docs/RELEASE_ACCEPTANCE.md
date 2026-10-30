# Release Acceptance

This document defines the portable Milestone 7 release gate. Every automated
check uses committed code/fixtures or deterministic synthetic data generated in
a temporary directory. No named local dataset, private biological resource, or
pre-existing runtime output is required.

## Automated gate

Run from a fresh repository clone after installing the project and test
dependencies:

```bash
Rscript tests/testthat.R
```

The suite covers utility, workflow, integration, regression, recovery, and
golden-output behavior. Tests that need a dataset build it from deterministic
synthetic inputs and isolate all generated files in temporary directories.

## Portable browser baseline

When `shinytest2`, `qs2`, and a Chromium-based browser are available, the normal
test command also runs the browser journey. It can be run by itself with:

```r
testthat::test_file("tests/testthat/test-app-ui-baseline.R")
```

The test constructs a temporary application containing:

- minimal synthetic marker, gene-position, HGNC, and cancer-map resources;
- one standardized 48-cell, 66-gene sample;
- manifest-backed filtered-expression and clustering caches;
- deterministic clustering and DE plots;
- selected decisions and a valid persisted pipeline state.

It visits dataset selection, dashboard, resolution selection, manual
annotation, and CNA analysis. After the reviewed screenshots, it assigns a
previously unassigned cluster, saves the annotation, verifies the standardized
cell table, manifest-backed clustering cache, and pipeline state, restarts the
temporary app, and confirms that the saved annotation is restored in the UI.
This is a real browser-driven write, but it is confined to the disposable
synthetic workspace. Screenshot comparison uses a small threshold so harmless
font and antialiasing differences do not cause pixel-perfect failures. All
functional browser assertions run on every supported platform. Screenshot
comparison is additionally enforced when a reviewed baseline exists for that
platform; the repository currently includes the Windows/R 4.5 baseline. The
test does not invoke expensive scientific compute, reset, cleanup, or batch
mutations. Its app, dataset, logs, state, caches, and results are deleted with
the temporary test directory.

If the browser or browser-test dependency is unavailable, only this browser
test is skipped; all non-browser release tests remain runnable.

## Acceptance scenario map

| Scenario | Primary evidence |
|---|---|
| Modular launch and preserved main screens | `test-app-bootstrap.R`, `test-app-components.R`, `test-app-ui-baseline.R` |
| Strict canonical `sample` configuration and malformed standardized data | `test-03_utils_misc.R`, `test-standardize-general-template.R` |
| Multi-sample standardization plus restart continuity | `test-t23-release-integration.R` |
| First-sample parameters and marker schemas | `test-05_utils_workflow.R`, component tests |
| Unsaved annotation edits, navigation, CNA omission, and notes | `test-app-components.R`, `test-03_utils_misc.R` |
| Browser-driven annotation save and restart continuity | `test-app-ui-baseline.R` |
| Safe unannotated preview, partial Unassigned legends, preview no-write behavior, and saved-PNG consistency | `test-f15-r03-annotation-preview.R` |
| Same-sample resolution grid/detail refresh after bulk/targeted clustering, stable tabs, and no unrelated PNG reads | `test-f15-r04-resolution-refresh.R` |
| In-app setup documents, Markdown downloads, independent workspace checklists, preserved notes, and safe creation paths | `test-f15-r05-onboarding-documents.R`, `test-f06-standardization-onboarding.R` |
| Explicit DE completion review selection, scoped processing order, fresh targets, and unsaved-edit/obsolete-action guards | `test-f15-r06-de-review-navigation.R`, `test-f03-navigation-hardening.R` |
| Exact large-input metadata, legacy precision recovery, saved-label continuity across reloads and dataset switching | `test-f15-r01-cache-precision.R` |
| Persistent explicit CNA omission, reversal, mixed batch, configured readiness, and CNA-view sample switching | `test-f15-r02-cna-omission.R`, `test-f05-annotation-recovery.R` |
| Bounded CNA conversion, export progress, binary validation, interrupted export preservation and retry | `test-f15-r07-cna-export.R`, `test-f13-cna-values-export.R` |
| Optional export independent of scientific completion; warned cleanup without an export, retained old exports, and re-review when availability changes | `test-f13-cna-values-export.R`, `test-f16-dataset-storage.R` |
| Persistent status, repeated attempts, append-only logs, and recovery | `test-06_utils_logging.R`, `test-07_utils_state.R`, `test-t23-release-integration.R` |
| Stale/corrupt/partial cache rejection and recovery | `test-04_utils_caching.R`, `test-regression_cna_cache.R`, state reconciliation tests |
| CNA eligibility and numerical edge cases | `test-05_utils_workflow_cna_preflight.R`, `test-m0-cna-characterization.R` |
| Mixed-validity batch, subsets, progress, and retry | `test-m5-cna-batch.R`, `test-05_utils_workflow_cna.R` |
| More than ten clusters, threshold equivalence, and current previews | annotation/CNA utility tests and component tests |
| Legacy state/config/cache behavior | synthetic migration, reconciliation, invalidation, and recovery tests |

## Scope boundary

The automated gate establishes software behavior and reproducibility without
assuming access to any particular biological dataset. A project may separately
perform scientific review on data it is licensed to use, but such a review is
not a repository test and is not required for another user to validate the app.

## Verification record

On 2026-10-21 under Windows and R 4.5.3, `Rscript tests/testthat.R` passed 818
assertions with zero failures, warnings, or skips. This total includes all 21
synthetic Edge assertions and five reviewed screenshot comparisons. No local
dataset or untracked biological resource was accessed.

The F01 follow-up run on 2026-10-21 passed 843 assertions with zero failures
or warnings. One browser-baseline test was skipped because Chromium could not
obtain a local process pipe/port in the restricted test environment; all
non-browser tests, including the new session and stale-state characterizations,
passed.

After the F02 stable-launch policy was added, the same full-suite command passed
854 assertions with zero failures or warnings after correcting the startup
session diagnostic to isolate its reads from reactive state. The browser
baseline was again the only skip for the same restricted-environment Chromium
startup failure.

After F03 navigation and duplicate-action hardening, the full suite passed 894
assertions with zero failures or warnings. Direct Shiny server tests verified
that clustering and DE completion dialogs navigate once and ignore a repeated
event. The browser baseline remained the only restricted-environment skip.

For F15 on 2026-10-28, the focused browser journey passed all 27 assertions,
including a real annotation save, durable-table/cache/state checks, application
restart, and UI reload. The current Dataset Selection and Start Menu screenshots
were reviewed and refreshed for Windows/R 4.5. The complete portable suite then
passed 1,456 assertions with zero failures or warnings; its single browser test
was skipped on that invocation because the restricted environment denied the
new Chromium process pipe/port after the focused browser run.

F15-R01 verification on 2026-10-28 passed all 60 new cache-precision/recovery
assertions. The full portable gate passed 1,524 assertions with zero failures
or warnings and the known restricted-Chromium skip. An initial attempt under
the shell's unsupported Windows `C.UTF-8` locale produced two unrelated tooltip
failures; clearing the inherited locale overrides restored R's normal UTF-8
Windows locale and the complete gate passed. Real-dataset inspection and the
explicit recovery preview remained read-only; applying the recovery and manual
reload confirmation remain pending.

F15-R02 verification on 2026-10-28 passed 53 focused omission/readiness/server
assertions. The full suite passed 1,580 assertions with zero failures/warnings
and the known restricted-Chromium skip. Read-only preflight verified HCC3's
saved CNA configuration is eligible and all eight explicit Liu2022 omissions
reconcile to skipped computation. The user confirmed R01's correct dataset
states; manual confirmation of the updated CNA view/computation remains pending.

F15-R07 verification on 2026-10-30 passed all 49 focused export assertions and
the full portable suite (1,629 passed, zero failures/warnings, one restricted
Chromium skip). Coverage includes bounded conversion allocation, exact values,
monotonic progress, binary gzip validation, interrupted publication and retry,
and retained assignment state in the Shiny server. A portable synthetic export
at HCC3's dimensions (5,000 genes × 14,872 cells; 74,360,000 rows) completed in
54.4 seconds and published a 633.8 MiB gzip CSV with current provenance. Real
HCC3 assignments/plots were inspected read-only and remain saved; the missing
export's manual retry and final storage acceptance are still pending.

The optional-export policy update on 2026-10-30 passed the full portable suite
with 1,658 assertions, zero failures/warnings, and the restricted-Chromium skip.
Finalization no longer invokes export. Server/lifecycle regressions verify
cleanup remains available without a current table, the recomputation warning
appears before confirmation, existing exports are retained/audited, and newly
missing exports after review require a fresh warning. Dataset cleanup in the
manual F15 run no longer depends on opting into values export; required final
scientific outputs and archive safeguards remain mandatory.

The CNA save-navigation update on 2026-10-30 passed the full suite with 1,667
assertions, zero failures/warnings, and the restricted-Chromium skip. The
integrated status/summary server regression verifies that final assignment
completion preserves the summary view and preview, refreshes status/provenance,
does not invoke optional export or recompute plots, and still clears the
preview when upstream thresholds change.

The 2026-10-30 cleanup manual follow-up exposed rounded byte counts in
`storage_state.yaml` for the large retained CNA CSV. Storage-state writes now
preserve full numeric precision; legacy size mismatches are accepted only when
they match the old rounding and the retained checksum verifies unchanged
content. A read-only deep audit of Liu2022's archived backup verifies all 32
retained outputs. The user reports cleanup and explicit reopen otherwise work,
with the intended stale-on-reopen transition, and has checked off the CNA and
storage-lifecycle manual scenarios. Existing dataset state/results were not
modified during diagnosis or verification.

This storage-precision fix passes all 121 storage assertions and the full
portable suite (1,680 assertions, zero failures/warnings, one restricted-browser
skip). Genuine changed/deleted content remains rejected, while checksum-proven
legacy rounding no longer produces an archive-damage warning.

F15-R03 verification on 2026-10-30 passes all 76 annotation-preview assertions
and the full portable suite (1,756 assertions, zero failures/warnings, one
restricted-Chromium skip). Tests reproduce the all-missing label case, cover
unavailable inputs and deferred plot errors with same-session retry, retain
all cells and a grey Unassigned key for partial annotations, and compare the
actual saved PNG with the preview. Preview leaves persisted workflow state,
configuration, cell data, caches, and manifests unchanged. Targeted manual
confirmation of warning/legend/save behavior remains pending; original replay
notes and real dataset files are untouched.

The user subsequently restored the pre-cleanup dataset/caches and confirmed
Unassigned appears in the new preview plot legends. Manual verification of
the unannotated-preview crash fix is deferred to the next full run on a new
dataset; it remains covered by the automated R03 tests.

F15-R04 verification on 2026-10-30 passes all 37 focused assertions. Integrated
dashboard/resolution server tests reproduce the stale empty/already-open PNG
case, then verify both bulk and targeted clustering refresh the same sample's
grid/detail image content without rebuilding tabs. Coverage includes saved
resolution/stale-review statuses, no idle/unrelated PNG checks, view re-entry,
removed/restored plots, and result-root changes with identical sample names.
The clustering backend is synthetic; no real dataset/cache was changed.
Targeted manual confirmation remains pending.

The complete portable gate after R04 passes 1,793 assertions with zero
failures/warnings and the known restricted-Chromium skip.

The user deferred R04 manual confirmation to the next full app review; the
targeted checklist remains open rather than being treated as accepted.

F15-R05 verification on 2026-10-30 passes all 77 focused assertions and the
full portable suite (1,870 assertions, zero failures/warnings, one known
restricted-Chromium skip). Real dataset-server handlers create two independent
synthetic workspace checklists; tests verify UTF-8 notes and the shared template
stay intact, downloads remain bound to the open document, existing workspaces
opt into copies explicitly, and missing documentation/unsafe paths fail clearly.
The tests also cover plain-text renderer fallback, pre-standardization loading
guards, another creation parent directory, and the corrected Windows new-path
normalization. No private resources or real datasets were modified. Manual
visual/access confirmation is recorded for the next full review.

The user subsequently confirmed that both document buttons open the correct
popups. Complete R05 acceptance, including downloads and independent workspace
checklists, remains scheduled for the next new-dataset review.

F15-R06 verification on 2026-10-30 passes all 64 focused assertions and the full
portable suite (1,934 assertions, zero failures/warnings, one known restricted-
Chromium skip). Completion navigation selects the first processed sample ready
for required annotation review only when the user clicks through. Tests cover
full/non-prefix subset order, untouched unrelated work, fresh targets, retained
selection with no ready target, unsaved-edit protection at request/confirmation/
navigation, missing run context, failure/retry, duplicate clicks, and dataset
switches. Selection itself leaves persisted workflow state unchanged and does
not load scientific caches; computation scope/single-sample DE behavior are
unchanged. Manual acceptance is recorded for the next full new-dataset review.
