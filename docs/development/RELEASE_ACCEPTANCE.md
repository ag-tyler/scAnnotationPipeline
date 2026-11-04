# Release Acceptance

**Latest full manual run (completed 2026-11-03; acceptance has open failures):**
[Che2021 Colorectal manual review](CHE2021_COLORECTAL_MANUAL_REVIEW.md).
All 15 samples reached a finished scientific decision before cleanup: ten final
CNA assignments and five explicit omissions. The preserved active copy is the
finished-run reference; the current repository dataset is the destructive-test
copy after cleanup/reopen/interruption. Section 10 reconciles every sample,
reports observed durations, and separates new isolated automated checks from
manual results. Checked R03–R06, R08 and subset-clustering evidence is recorded
there. Overall acceptance remains open for interrupted-clustering recovery,
dataset-switch crashes, CNA navigation/cache guards, stale status presentation
after reopen, and long-path wrapping in snapshot review. The successful
completion-modal wrapping check does not close the separate review-modal issue.

Required fixes and their acceptance criteria are scheduled in the
[November remediation plan](CHE2021_COLORECTAL_REMEDIATION_PLAN.md).
Complete C01–C06 and the C10 verification gate before closing this review's
release acceptance; record C07–C09 usability work separately if deferred.

**C01 implementation follow-up (2026-11-03):** Dataset switching now tears down
old loaded data/confirmation tokens, validates asynchronous sample indices and
scopes CNA context to each dataset load. Synthetic server/browser checks cover
unequal sample counts, same-workspace reloads, archived-to-active transitions,
unsaved-edit protection and stale-action rejection. This addresses the recorded
dataset-switch crashes at the implementation/regression level; the original
manual failures remain in the review record. C02–C06 and C10 remain open.
Final C01 verification passed 2,549 portable and 54 browser assertions, with
zero failures/errors/test warnings/skips in the supported Windows UTF-8 locale.
The browser run includes 15 new C01 assertions and the existing 39-assertion
save/restart journey. The optional >4 GiB ZIP64 gate was not rerun.

**C02 implementation follow-up (2026-11-03):** Clustering attempts now record
execution ownership. On load, an editable dataset recovers confirmed ended
attempts as retryable failures while preserving attempt history and scientific
files. Legacy/unknown ownership requires the Start Menu's explicit Recover
Interrupted Clustering confirmation; live processes remain protected. Synthetic
workers were killed before/after cache publication, recovered and successfully
retried through all configured resolutions. Guarded server and browser recovery
checks pass; interrupted DE retry remains covered. No real dataset or user R
process was changed. C03–C06 and the C10 release gate remain open.
Final C02 verification passed 2,631 portable and 71 browser assertions with
zero failures/errors/test warnings/skips. C02 contributes 79 recovery/ownership
assertions, three DE retry regressions and 17 browser assertions. Tests used
only disposable synthetic inputs, including the forcibly stopped worker
processes; the optional >4 GiB ZIP64 gate was not enabled.

**C03 implementation follow-up (2026-11-03):** CNA analysis views now require
the current server-authorized sample/view context. Status, omitted/reset samples
and stale browser view messages cannot trigger main heatmap reads. CNA Pipeline
Status is accessible beside the sample controls; warm re-entry and k changes
reuse a bounded last-valid plot bundle. Saved sample/k decisions restore, stale
threshold/finalization actions are guarded, and reset confirmation is scoped to
the reviewed sample. Instrumented synthetic browser navigation built the main
heatmap once (one hclust and one matrix read); first entry was 2.58 s and warm
re-entry 1.20 s on 48 cells/66 genes, including browser overhead. The CNA sidebar
screenshot was refreshed and inspected. No real dataset changed; C04–C06 and
the C10 release gate remain open.
Final C03 verification passed 2,680 portable and 91 browser assertions, zero
failures/errors/test warnings/skips. This includes 49 new C03 server and 20
instrumented browser assertions. Supported Windows UTF-8 was used; the optional
>4 GiB ZIP64 gate was not enabled. Only the CNA sidebar baseline changed.

**C04 implementation follow-up (2026-11-03):** Post-reopen CNA status now
identifies the first unfinished recovery stage and refreshes archive-cleanup
reasons as prerequisites are restored. Valid configuration leads to a base CNA
compute action; later stale results cannot obscure current work. Retained
scientific records remain stale until recomputed/saved, genuine cache failures
keep their diagnosis, and untouched/omitted controls retain their exact state.
Final verification passed 2,782 portable and 104 browser assertions with zero
failures/errors/test warnings/skips, including 102 new portable and 13 browser
assertions. The browser replay uses real reopen and decision/save handlers
through final assignment and restart, with deterministic fixture publication
for numerical rebuild phases. This is synthetic recovery/status evidence;
human manual acceptance remains part of C10. The Start Menu baseline was
refreshed and visually inspected. Supported Windows UTF-8 was used; the optional
>4 GiB ZIP64 gate was not enabled. Neither real Che dataset changed.
C05/C06 and the C10 release gate remain open; C07–C09 are separate usability work.

**C05 implementation follow-up (2026-11-04):** Snapshot review now wraps the
reported COL07 PNG path and unbroken filenames inside the modal, preserving
their complete selectable text. The dialog displays the relative-path base and,
after validation, the resolved destination directory. Destination changes
invalidate review; confirmation refuses a changed resolved location. Completion
paths share the display helper. Locations remain transient and are excluded
from scientific state, events and generated provenance. Neither real Che
dataset changed. C06 and the C10 acceptance gate remain open; C07–C09 remain
separate usability work.

Final C05 verification passed 2,862 assertions in disjoint regression/focused
layout runs, zero failures/errors/test warnings/skips. This excludes
`app-ui-baseline`; the snapshot subset passed 498 assertions. C05 adds 80,
including 57 browser checks at 1280px/375px for overflow and exact text
selection, plus server checks for relative input, both Windows slash styles,
review invalidation, changed destination resolution and no copying during review. Existing
completion layout (SNP-06), source-preservation and destination-free provenance
checks pass. Supported Windows UTF-8 was used; the optional >4 GiB ZIP64 gate
was not enabled. Local diagnostic outputs are ignored in `artifacts/local-checks/`.

**C06 implementation follow-up (2026-11-04):** Snapshot rollback now completes
within the UTF-8 filename-locale scope, and standalone owned-path cleanup also
guards Unicode traversal/deletion. The caller's locale is restored on exit.
Cleanup retains exact ownership/containment/link checks, attempts the remaining
owned paths after a removal fails, and reports possible partial outputs through
the existing sanitized error/event flow. No destination is added to provenance
or state. An isolated pre-fix replay reproduced a leftover stage under C;
synthetic regression checks cover Unicode workspace/destination paths, nested
filenames, Both-mode partial publication and interruptions after either rename.
Simulated OS removal failure verifies honest failure reporting and preservation
of prior files. No real dataset changed. C01–C06 implementation is complete;
the C10 acceptance gate and C07–C09 usability work remain open.

Final C06 verification passed 3,068 assertions with zero failures/errors/test
warnings/skips, including all 704 snapshot assertions and 206 new C06 checks.
The normal test directory was run except `app-ui-baseline`; snapshot layout
browser checks are included. UTF-8 and C filename-locale cases preserve the
complete caller locale, source/prior-copy hashes and exact cleanup containment.
When removal is possible no owned partial output or Unicode workspace lock
remains. Simulated OS refusal leaves only the blocked folder, still clears
staging and emits a sanitized failure with `outputs_verified = FALSE`.
Publication fault hooks confirm the real archive workers reached the intended
failure stage. Supported Windows UTF-8 was used for the suite baseline; the
optional >4 GiB ZIP64 gate was not enabled. Diagnostics remain ignored under
`artifacts/local-checks/`. This does not close the C10 manual acceptance replay.

**C07 implementation follow-up (2026-11-04):** CNA analysis now offers Omit CNA
for This Sample beside Reset. The shared annotation/CNA confirmation flow binds
the decision to its dataset generation, selected sample, workflow and relevant
configuration. Cancel and duplicate confirmation do not mutate results;
dirty/busy/archived contexts and obsolete selections are guarded. Existing
omission behavior clears references/candidates and invalidates CNA states and
calculation caches while preserving annotation/upstream records, cell labels,
historical plots/exports and saved historical cut/threshold values. The view
returns to status, omission survives restart and ordinary batch choices exclude
explicit omissions. Complete configuration save reverses omission and requires
new computation. No real dataset changed. C08/C09 and C10 acceptance remain open.

Final C07 verification passed 3,112 regression plus 127 browser assertions, zero
failures/errors/test warnings/skips. The disjoint runs cover the complete normal
test directory. C07 contributes 44 server and 23 browser assertions for cancel,
confirm once, target/context guards, preserved upstream/other-sample state and
retained files, unavailable-cache guards, reload, batch exclusion and reversal.
The real browser journey uses malignant selection, omission, application
restart and Manual Annotation's configuration save. Existing C01–C04 browser
journeys and all screenshot baselines pass; no baseline image changed.
Supported Windows UTF-8 was used; the optional >4 GiB ZIP64 gate was not enabled.
Diagnostics remain ignored under `artifacts/local-checks/`. This does not close
the C10 human acceptance replay.

**C08 implementation follow-up (2026-11-04):** CNA cut controls now initialize
per dataset/generation/sample/base computation. Fresh samples use k = 7 within
tree bounds; current saved selections restore exact k/IDs without inheriting
another sample's edit. The navigator waits for initialization acknowledgment,
and changing k away/back clears the old selection. Heatmap reuse is retained.
Unsaved Y views start at 0.5 instead of the former data-derived maximum with a
floor of 1. Saved limits/thresholds retain their values, with expanded bounds
and finer legacy precision where needed. Tick spacing updates with linked
bounds; persistent styling suppresses fractional minor ticks. Equal-Y and
strict-X classification rules are unchanged. No real dataset changed; C09 and
the C10 human acceptance gate remain open.

Final C08 verification passed 3,151 regression plus 598 browser assertions with
zero failures/errors/test warnings/skips in combined results. The regression
and browser runs, with a focused rerun of affected C08/baseline/C03 journeys,
cover the normal test directory. C08 adds 39 portable and 471 browser assertions
for sample defaults/exact saved cuts, cut changes, saved precision/expanded
bounds, 0.5 initial views, clipping, save/reload, equal-Y/strict-X behavior and
aligned major ticks after linked updates. Multi-subclone classifications and
processed-file hashes stay unchanged. C03 retains one heavy heatmap build;
existing screenshot baselines pass without image changes. Tests used supported
Windows UTF-8 and synthetic inputs only. The optional >4 GiB ZIP64 gate was not
enabled. Diagnostics remain ignored in `artifacts/local-checks/`; C09 and C10
human acceptance remain open.

**C09 implementation follow-up (2026-11-04):** Manual Annotation now shows quiet
saved progress across configured samples and identifies pending edits separately.
Last-cluster and saved notices explicitly distinguish review/save readiness
from disk persistence. Larger body-attached dropdowns remain within viewport
space and retain Selectize search, scrolling and keyboard selection. Workspace
selection and the dashboard remind about missing optional DOI/URL metadata;
either field clears the reminder, without changing standardization or snapshot
eligibility. Archived annotation loads avoid caches and queued mutations are
rejected. No biological decisions are written by the presentation code and no
real dataset changed. C01–C09 implementation is complete; C10 human acceptance
remains open.

Final C09 verification passed 3,182 regression plus 632 browser assertions with
zero failures/errors/test warnings/skips in the combined full/focused results.
The complete normal test directory is covered; replacement C09/baseline rerun
cases are counted once. C09 adds 31 regression and 34 browser assertions covering
saved/dirty progress, rerun/reload, archived write/cache guards, optional origin,
and 600-entry vocabulary search/scroll/native keyboard selection at desktop and
narrow widths with viewport geometry checks. Protected input hashes remain
unchanged; only explicit synthetic assign/save actions write labels. Existing
missing-origin standardization and snapshot checks pass. Four reviewed UI
baselines (`01`, `02`, `04`, `06`) reflect the new feedback/reminders. An
exploratory Chrome startup failure occurred before app execution; the final
rerun executed without skips. Tests used supported Windows UTF-8; the optional
>4 GiB ZIP64 gate was not enabled. Local diagnostics remain ignored under
`artifacts/local-checks/`. This does not close C10 human acceptance.

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
annotation, and CNA analysis. It also opens the clustering checklist, verifies
default selection and all four shortcuts, checks that empty selection disables
Run, closes without computation, and verifies unchanged workflow/manifest
checksums. A reviewed sixth screenshot captures the selection dialog. Transient
notifications are awaited before screenshots to avoid timing-dependent diffs.
After the reviewed screenshots, it assigns a
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
| Clustering checklist presets, selected-only state/cache/output isolation, selected-batch progress, guarded confirmation, and preserved all/one-sample paths | `test-f09-subset-clustering.R`, `test-f09-single-sample-clustering.R`, `test-app-ui-baseline.R` |
| Compact per-subclone threshold rules, collapsed boundary guidance, and unchanged eligibility/multi-subclone/equal-Y classification | `test-f15-r08-compact-threshold-guidance.R`, `test-f11-cna-threshold-guidance.R` |
| Exact large-input metadata, legacy precision recovery, saved-label continuity across reloads and dataset switching | `test-f15-r01-cache-precision.R` |
| Persistent explicit CNA omission, reversal, mixed batch, configured readiness, and CNA-view sample switching | `test-f15-r02-cna-omission.R`, `test-f05-annotation-recovery.R` |
| Bounded CNA conversion, export progress, binary validation, interrupted export preservation and retry | `test-f15-r07-cna-export.R`, `test-f13-cna-values-export.R` |
| Optional export independent of scientific completion; warned cleanup without an export, retained old exports, and re-review when availability changes | `test-f13-cna-values-export.R`, `test-f16-dataset-storage.R` |
| Verified review snapshots: all 12 modes/options, whole processed data and plots, archived CNA provenance, scoped summaries, guarded GUI, bounded copy, rollback and destination-free logs | `test-f17-review-snapshots.R` |
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

### F17 manual acceptance (pending)

- [x] User confirmed Liu2022_Liver Both-mode creation using a relative
  destination: the dataset-specific folder and ZIP were created. The destination
  location is not retained in this record.
- [ ] Confirm the corrected completion popup wraps both full destination paths
  within the modal/window; the original manual test found clipping/overflow.
- [ ] On a safe small finished dataset, exercise folder/archive/both and both
  inclusion switches; confirm defaults, previews/warnings, progress and one-shot
  confirmation. Unfinished/busy/dirty datasets must be blocked.
- [ ] Open/extract outputs and inspect origin/README, all plots, historical
  provenance and manifest. Confirm processed cells excluded by preprocessing
  remain present, and annotation/filtering summaries use the correct scope.
- [ ] Repeat from an archived/cache-cleaned dataset, including retained optional
  CNA values and any unavailable legacy-statistics warnings.
- [ ] Check a representative full-size new dataset for actual time, available
  space, ZIP extraction and path limits; twelve large real copies are not needed.
- [ ] Confirm source scientific files/decisions/statuses remain unchanged and no
  destination is persisted in logs/config/state/generated documentation. Check
  interruption/retry and that earlier exports survive failures.

These F17 checks are new scope and are not accepted by the earlier F15 replay.
The optional large-file regression is enabled by `RUN_F17_LARGE_TESTS=true` and
uses a real entry exceeding 4 GiB; routine tests use small synthetic fixtures.

F17 verification on 2026-10-30: the final complete suite passes **2,478
assertions**, with **zero failures, test warnings or skips**, including all 39
Edge browser assertions. All twelve output-mode/inclusion combinations pass.
The separate large-file gate created and verified an actual entry exceeding
4 GiB through ZIP64, complete extraction, size checks and checksum readback.
Tests also cover successful aggregate capture in the real clustering/manual
annotation/CNA-save handlers, unknown/stale summary generations, byte-exact
processed cells/matrices, current and archived optional CNA pairs, required
retained-output damage, bounded copy progress, Unicode names and native Windows
path limits, no-heavy-I/O readiness, confirmation/dirty/busy guards, corrupt
staging, partial Both publication, no-overwrite collisions, post-rename
interrupts, source changes, destination-free logs and unavailable logging.
The Start Menu baseline was refreshed and visually reviewed; the other browser
baselines were retained. The final suite uses the supported Windows UTF-8
locale; the host's initial C locale caused two existing tooltip text checks to
fail until the test locale was set correctly. Synthetic fixtures only were
modified. F17 manual acceptance remains open.

F17 completion-layout follow-up (2026-10-30): the user confirmed creation of
the Liu2022 folder and ZIP, but reported long paths extending beyond the modal
and screen. The display fix preserves complete selectable text with wrapping.
All **392 focused F17 assertions** pass (zero failures/warnings/skips), including
**36 new layout assertions**. Edge geometry checks at 1280px and 375px confirm
that both full paths stay inside the modal/window without horizontal overflow.
The export backend is unchanged; this follow-up ran the focused gate, not a new
full-suite or real-dataset export. Manual visual confirmation remains open.

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

The F09 subset-clustering focused browser journey passes all 39 assertions,
including the existing annotation save/restart path. It runs against a disposable
synthetic app and does not invoke clustering. The dashboard and resolution
screenshots were refreshed after waiting for transient notifications, and the
new clustering-selection dialog baseline was visually reviewed. Screenshot
updates can now be limited by `UPDATE_UI_BASELINE_FILES` (comma-separated
filenames) together with the existing `UPDATE_UI_BASELINES=true` flag.

Mixed-state component tests exercise all presets, empty/invalid/duplicate
identities, fresh per-dialog inputs, archive/busy/unsaved guards, changed
dataset/sample/resolution contexts, selected-only progress, fail-fast batches,
and single-shot completion navigation. The isolation test uses real
manifest-backed CNA cache files and proves unselected state, decisions,
artifacts, and cache records/files remain identical. Multi-index workflow
coverage exercises all configured resolutions with selected-only positions.
No real dataset was read, recomputed, or changed. Manual subset acceptance
remains scheduled for the next full new-dataset review.

Final F09 gate: all 99 subset and 53 expanded F09 workflow assertions pass.
The full portable suite passes 2,039 assertions with zero failures/warnings
and one restricted-browser skip; the separately permitted focused browser
journey passes all 39 assertions. Scientific algorithms and parameters are
unchanged; no real dataset was modified during verification.

F15-R08 focused verification passes 33 new assertions plus all 42 existing F11
assertions. The visible helper is limited to three rules (at most 65 words),
with strict/equal-Y details collapsed by default (at most 100 words overall).
The actual two-subclone threshold UI retains guidance and sliders in each
card without extra signal-cache reads. Synthetic preview/save/reload tests
confirm multi-subclone retention and collisions, malignant eligibility,
Unassigned reassignment, exact equal-Y boundaries, existing Malignant labels,
and untouched untested cells. Only helper presentation changed; scientific
and slider-control code are untouched. Manual wording/layout acceptance is
recorded for the next full new-dataset review.

The complete gate after R08 passes 2,072 assertions with zero failures/warnings
and one known restricted-browser skip. All currently planned implementation
items are addressed; manual acceptance of the new-dataset run remains open.
