# Che2021 Colorectal — November review remediation plan

**Date:** 2026-11-03

**Status:** C01–C05 implemented with synthetic regression/browser coverage;
C06–C09 remain planned and C10 release acceptance remains open.

**Evidence:** [Completed manual review](CHE2021_COLORECTAL_MANUAL_REVIEW.md),
especially stage notes and section 10. This plan extends the
[original follow-up plan](CHE2021_COLORECTAL_2_FOLLOW_UP_PLAN.md).

The scientific replay finished: 15 samples, ten finalized CNA analyses and five
explicit omissions. Remaining work concerns runtime recovery, navigation,
status accuracy, snapshot handling and usability. Preserve the successful
scientific behavior and the checked R03–R06, R08 and subset-clustering results.

## Scope and execution order

| ID | Priority | Deliverable | Review checkpoints | Depends on |
| --- | --- | --- | --- | --- |
| C01 | P0 | Safe dataset transitions across annotation and CNA | APP-05/07, ANN-07, STO-04 | — |
| C02 | P0 | Retry after interrupted clustering and restart | ERR-01 | — |
| C03 | P1 | Guard CNA views and avoid unnecessary heatmap loading | CNA-07/09 | C01 |
| C04 | P1 | Accurate CNA status after explicit reopen/recovery | STO-07 | C01/C02 |
| C05 | P1 | Contained snapshot-review paths and clear relative-path base | SNP-03/04/06 | — |
| C06 | P1 | Unicode-safe snapshot rollback under fallback locales | ERR-03, supplemental F17 | — |
| C07 | P2 | Explicit CNA omission from within CNA analysis | CNA-01/02, ANN-04 | C01/C03/C04 |
| C08 | P2 | Sample-specific CNA defaults and accurate threshold ticks | SEL-02/03, THR-01–04 | C03 |
| C09 | P2 | Annotation progress, dropdowns and source reminders | PRE-03, ANN-06/08 | C01 |
| C10 | Gate | Focused acceptance replay and release record | APP-06, ERR-04, FIN-02–04 | C01–C06 |

P0 blocks normal use; P1 is required before closing this review's release
acceptance; P2 is a separate usability follow-up. C10 must explicitly list any
deferred P2 work rather than imply it was delivered. Implement C01/C02 first,
then C03/C04, then C05/C06. Finish the required acceptance replay before
expanding optional improvements. Each task records implementation separately
from the final release acceptance gate.

## C01 — Dataset-switch crashes

- [x] Implement and verify on synthetic workspaces (2026-11-03).

**Evidence:** Annotation indexing failed when switching to Liu2022. Switching
after archive cleanup also triggered CNA preflight for an unknown sample and
crashed. Restart restored loadability but did not fix the transition.

**Inspect:** `app/server/dataset_server.R`, `app/state.R`,
`app/server/annotation_server.R`, `app/server/cna_status_server.R`, and shared
CNA sample/context helpers. Reported stack frames identify likely entry points;
the exact reactive ordering still needs reproduction.

**Change:** Establish a coherent unloaded/loading/ready context. Invalidate old
sample selections and loaded-sample identities before dependent observers can
use new paths/state. Resolve samples only against the current dataset and
validate index type, length and bounds before indexing. Treat transition-time
absence as a waiting/unavailable UI state. Retain explicit errors for genuinely
inconsistent ready datasets. Preserve save/discard/cancel guards and reject
obsolete completion/confirmation actions from the previous dataset.

**Acceptance:** Synthetic Shiny server tests and a focused browser journey
switch between different sample counts/orders, including an old index outside
the new range. Cover switching from annotation, CNA status, malignant selection
and an archived dataset. No uncaught error, stale cache read, cross-dataset
write, inherited sample label or lost unsaved edit. Repeat switching and restart
after saving; both datasets' persisted scientific records remain unchanged.

**Implementation record (2026-11-03):** Dataset teardown clears loaded
annotation/preview data and confirmation tokens before exposing another
workspace. Sample controls are frozen during publication, cleared on unload,
and initialized explicitly on load. A transient generation identifies a fresh
load even when the same workspace/sample names are reused. Switching/loading
refuses unsaved annotations and active actions; failed loads leave an unloaded
context instead of retaining data from the previous dataset.

Annotation, resolution and CNA handlers share bounds/type validation for
browser sample indices. Annotation lookup waits until its tab is active and
annotation saving verifies that the loaded sample matches the selected path.
CNA preflight, navigation identity and cached selection context are scoped to
the loaded dataset/generation. Heatmap reads require a current completed base
computation and non-retired storage; unrelated assignment saves do not reload
the heavy plot.

**Regression evidence:** `test-c01-dataset-transitions.R` covers different
sample counts/order, stale/malformed indices, same-workspace reload,
archived-to-active transitions, old completion/reset tokens, busy/dirty guards,
failed-load recovery, unchanged scientific-file hashes, and CNA cache-read
counts across dataset changes versus downstream saves. The browser journey in
`test-app-ui-baseline.R` exercises real asynchronous select updates, leaving
annotation with discard, CNA status/malignant view, archive switching, and
returning to annotation. Its existing save/restart journey remains covered.
These are synthetic checks; the original real-data failures remain historical
evidence and no new real Che/Liu GUI replay is claimed. C03's status-return
action/lazy view loading and C04's post-reopen status semantics remain open.

**Final verification:** 2,549 portable assertions plus 54 browser assertions
passed, zero failures/errors/test warnings/skips. These disjoint runs cover the
complete test directory, with browser tests run separately to allow local
Shiny/Chromium worker access. C01 contributes 44 server assertions and 15 new
browser assertions; the other 39 browser assertions include saved annotation
and app-restart persistence. R 4.5.3 used the supported Windows
`English_United States.utf8` locale. The separate optional >4 GiB ZIP64 gate
was not enabled. `git diff --check` passed. Tests use disposable synthetic
workspaces; neither real dataset was altered.

## C02 — Interrupted clustering cannot be retried

- [x] Implement and verify on disposable workspaces (2026-11-03).

**Evidence:** App termination leaves clustering `in_progress` across restart;
the guarded clustering action then rejects that sample. Existing caught-error
tests and the new guarded-retry assertions pass, but do not model process death.

**Inspect:** `util_scripts/07_utils_state.R`, workflow/action ownership and
clustering handlers in `app/server/dashboard_server.R`, plus dataset loading.

**Change:** Distinguish a live owned computation from an abandoned persisted
attempt. Reconcile an abandoned attempt to an existing retryable failure or
incomplete state, with a clear interruption reason and preserved attempt
history. Determine ownership from the application's actual execution model;
dataset reload or a second viewer alone must not declare a live job abandoned.
If ownership cannot be established safely, expose an explicit guarded recovery
action rather than silently clearing the busy state. Do not mark partial
outputs complete, promote orphan caches, or overwrite final cell annotations
merely to unlock retry. Preserve appropriate downstream review requirements.

**Acceptance:** On a disposable workspace, stop the process during clustering,
restart and load. The affected sample is retryable, with an honest message;
unrelated samples and earlier valid artifacts remain unchanged. A normal retry
completes every configured resolution once. Cover subset fail-fast behavior,
duplicate clicks, live-job protection, interruption before/after output writes,
and successful DE interruption/retry as a regression. No real dataset is killed
or edited to manufacture this test.

**Implementation record (2026-11-03):** New single/subset/bulk clustering runs
persist an execution token, session identity, host, PID and process creation
time with each attempt. Live invocation tokens are shared across sessions in
the application's R process and released on normal return, error or interrupt.
Process identity includes creation time to distinguish PID reuse. Another
viewer's reload cannot declare a live invocation abandoned. A running foreign
process is treated conservatively as live; remote, missing or malformed owner
metadata is unknown and is never recovered silently.

Loading an editable dataset automatically changes a confirmed ended attempt
from `in_progress` to retryable `failed`, retaining its attempt/start metadata
and a per-attempt recovery history. Downstream decisions remain stale with an
interruption/retry reason. Recovery uses the existing atomic state writer and
revision conflict checks; it does not validate/promote partial caches, restore
outputs or change scientific files. Archived datasets are excluded.

For legacy/unknown records, Start Menu → **Recover Interrupted Clustering**
offers explicit sample selection, confirmation that the old computation has
stopped, and exact dataset-ID confirmation. It refuses live owners, changed
dataset/state contexts, archived storage, active actions and unsaved edits.
Confirmation is consumed once; recovery only unlocks the selected attempts.
Retry uses the normal guarded clustering actions. A still-active foreign R
process must be stopped before recovery can proceed safely.

**Regression evidence:** `test-c02-clustering-recovery.R` starts test-owned R
workers running the actual clustering workflow, pauses before cache writes and
after the first resolution cache/plot is published, and forcibly terminates
only those workers. Recovery preserves source/cell/cache/plot hashes and the
unselected control, does not claim completion, and leaves attempt 1 recorded.
A real retry visits every configured resolution once and completes attempt 2.
Additional tests cover shared live tokens, PID reuse, malformed/remote/legacy
owners, repeated recovery history, idempotence and revision conflicts.

The F09 server tests cover scoped legacy recovery, wrong/missing confirmation,
duplicate clicks, live ownership appearing after review, archive/busy/dirty/
dataset/revision guards, and one guarded retry. Interrupted DE remains
retryable independently. The browser journey exercises legacy recovery,
confirmation, real tiny-sample clustering, completion navigation and automatic
recovery on restart. Existing C01 switching and save/restart checks remain
covered. No real dataset or user-owned R process was modified or terminated.

**Final verification:** 2,631 portable assertions plus 71 browser assertions
passed, zero failures/errors/test warnings/skips. These disjoint runs cover the
complete normal test directory. C02 adds 79 ownership/recovery/workflow/guard
assertions, three interrupted-DE retry assertions, and 17 browser assertions.
Actual worker termination occurred in both pre-publication and post-resolution
cases; retries used real clustering on tiny synthetic inputs. Verification used
R 4.5.3 and `English_United States.utf8`; process/browser/ZIP workers needed
local process-pipe access. The optional >4 GiB ZIP64 gate was not enabled.
`git diff --check` passed. C03–C10 remain open.

## C03 — CNA cache guards and navigation

- [x] Implement and verify on disposable workspaces (2026-11-03).

**Evidence:** Switching from malignant selection to omitted/reset samples
requests a missing `hclust` cache. Eligible sample switches can load a large
heatmap before the destination status view is useful. The reviewer requested
an accessible return to CNA pipeline status.

**Inspect:** `app/server/cna_server.R`, `cna_cluster_server.R`,
`cna_status_server.R`, `cna_reset_server.R`, and `app/ui/cna_ui.R`.

**Change:** Gate cache-dependent reactives on current dataset/sample identity,
stage readiness and the active view. Invalidate the old view context before
loading a new sample. Omitted/reset/incomplete samples should show the real
status and next action without requesting unavailable caches. Add a return to
CNA status action from analysis views; returning there should not load the main
heatmap. Reuse valid heatmap work for lightweight k/selection changes.

**Acceptance:** Reproduce computed → omitted → reset → computed navigation
from the review. No missing-cache error or heatmap request for unavailable
samples. Instrument cache/heatmap calls to verify that entering status performs
no large heatmap computation; measure first load and warm re-entry separately.
Saved sample-specific selections restore and unsaved-change guards still work.

**Implementation record (2026-11-03):** CNA Pipeline Status is available beside
the sample controls, above the pipeline-step buttons. Dataset/sample/upstream
context changes reset the server's authoritative view to status before
dependent output work runs. Analysis cache consumers require both that current
server context and the matching browser view, current sample/generation,
completed prerequisites, non-retired storage and a non-omitted CNA decision.
Old browser view messages cannot authorize work for a newly selected sample.

Main heatmap preparation remains separate from these view guards, so returning
to status and reopening does not invalidate the expensive plot. Only the last
valid static plot bundle is retained: k/selection edits and visits to samples
whose heatmaps are never requested reuse it. Opening a different computed
sample can replace that bundle; this is bounded reuse, not unlimited per-sample
plot storage. Base-computation identity, configuration and dataset generation
prevent reuse after invalidation/recomputation. Navigator editing context clears
on sample changes even when the intervening sample has no plot, allowing saved
sample/k selections to restore without inheriting another sample's live input.

Threshold outputs and automatic summary previews wait for the correct analysis
view. Old dynamic threshold renderers also verify their captured sample and
generation. Hidden/stale threshold/finalization save actions are rejected.
Reset returns to status before deleting artifacts, binds confirmation to the
reviewed dataset/generation/sample and refuses changed selection, archived,
busy or unsaved-annotation contexts. These guards do not change thresholds,
classifications, upstream scientific state semantics or C04's open status issue.

**Regression evidence:** `test-c03-cna-navigation.R` forces hidden outputs to
evaluate across computed → omitted → reset → computed navigation, verifies
zero unavailable/main-cache reads from status, one heavy plot build across
warm re-entry and k changes, explicit entry for a different eligible sample,
lazy signal tables, saved selection restoration, stale-summary-message guards,
unsaved protection and stale save/reset rejection. Read-only navigation retains
scientific-file hashes. The browser journey uses real tiny CNA caches/plots
and instruments only its disposable app: one hclust read, one CNA matrix read,
and one main heatmap build across the sequence. First entry took **2.58 s** and
warm re-entry **1.20 s**, including browser interaction/render/idle overhead on
48 cells and 66 genes. These are synthetic observations, not full Che timings.

Only the CNA sidebar screenshot was refreshed and visually inspected; the
status button is visible above the fold at the tested desktop size. Original
manual error notes remain historical evidence. Neither real dataset was used
or modified; C04–C10 remain open.

**Final verification:** 2,680 portable assertions and 91 browser assertions
passed, zero failures/errors/test warnings/skips. C03 contributes 49 server
assertions and 20 instrumented browser assertions. These disjoint runs cover
the complete normal test directory; existing C01/C02 recovery/navigation,
annotation save/restart, threshold classification and final-save/export checks
remain covered. R 4.5.3 used `English_United States.utf8` with permitted local
process/browser/ZIP workers. The optional >4 GiB ZIP64 gate was not enabled.
`git diff --check` passed. Only
`tests/testthat/fixtures/ui-baseline/windows-4.5/05-cna-analysis.png` changed
among the reviewed screenshot baselines.

## C04 — Post-reopen CNA status

- [x] Implement and verify on synthetic workspaces (2026-11-03).

**Evidence:** After rebuilding a sample and saving valid CNA configuration, the
main menu retained an obsolete stale display even though CNA could run.

**Inspect:** Shared state/readiness derivation in `util_scripts/07_utils_state.R`
and `05_utils_workflow.R`, dashboard status, and CNA configuration/save handlers.

**Change:** Trace whether the wrong display comes from state transitions,
retained reasons or a stale reactive summary. Derive the next required step
from current prerequisites. Once upstream recovery is complete, show CNA as
needing computation/review with the current reason; obsolete cleanup wording
must not imply the newly saved configuration is invalid. A genuinely stale
retained result may remain stale until recomputed: do not force completion to
improve the display. Other samples stay stale after reopen.

**Acceptance:** Archive and explicitly reopen a completed synthetic workspace.
Rebuild one sample through configuration, computation and final assignment.
Dashboard/detail/CNA status agree at every step; reload preserves their meaning.
The unprocessed control stays honestly stale and explicit omission stays
distinct from missing configuration. Include a focused manual recovery replay.

**Implementation record (2026-11-03):** Archive-cleanup stale reasons now
advance with the sample's first unfinished recovery stage, both on persisted
updates and on reload. Once valid CNA configuration is saved, the dashboard
requests base CNA computation instead of retaining the obsolete instruction to
rerun clustering. Subsequent actions advance through malignant-cluster review,
signal/correlation, thresholds and final assignment. The overview follows the
first unfinished CNA stage, so later retained stale results or old failures
cannot hide an active computation or the current review decision.

Ready cleanup-stale results display as requiring computation/review in the
overview; their underlying scientific records remain stale until actually
recomputed or saved. Genuine cache-validation failures retain their diagnosis.
Untouched samples retain their exact reopened state, and explicit omissions
remain distinct from missing configuration. Overview derivation adds no I/O.

**Verification:** 2,782 portable and 104 browser assertions passed with zero
failures/errors/test warnings/skips. C04 adds 102 portable assertions and 13
browser assertions. Actual synthetic archive/reopen, stage-by-stage status,
reload idempotence, unchanged controls/retained output hashes, omission and
cache-failure diagnoses are covered. The browser replay uses real reopen,
resolution, annotation, CNA configuration, malignant-selection, threshold and
final-save handlers through application restart. Numerical rebuild phases
republish deterministic tiny fixture inputs; this verifies recovery/status,
not a new scientific recalculation or a human manual acceptance replay.
The Start Menu screenshot was refreshed and visually inspected. Tests used
R 4.5.3 with supported Windows UTF-8; the optional >4 GiB ZIP64 gate was not
enabled. Local scripts/logs/results stay in ignored `artifacts/local-checks/`.
Neither real Che dataset was modified. C05–C10 remain open, including the final
C10 acceptance replay.

## C05 — Snapshot review layout and destination guidance

- [x] Implement and verify on synthetic workspaces (2026-11-04).

**Evidence:** Included relative paths overflow the review modal; the separate
completion-modal wrapping check passed. Relative destinations lack clear base
directory guidance.

**Inspect:** Snapshot review rendering in `app/server/storage_server.R` and
related UI/styles. Reuse the successful completion-path wrapping approach where
appropriate without changing path values.

**Change:** Wrap long paths inside the review container at desktop and narrow
widths, retaining complete selectable text. Show the current base directory and
resolved destination in the local review UI before copying. Keep destination
locations out of persisted application logs, source metadata and generated
snapshot provenance.

**Acceptance:** Real browser geometry checks with the reported long PNG path,
an unbroken filename and narrow modal: no path/modal/document horizontal
overflow or clipping; copy/select yields the original path. Both slash styles
and relative paths still validate, invalid/overlapping destinations still fail,
and opening the review never starts copying. Retest SNP-06 and destination-free
logging/provenance; screenshots shared for review must omit private locations.

**Implementation record (2026-11-04):** Review and completion paths share one
display helper that wraps at any character without inserting, truncating or
interpreting path text as HTML. Included files remain inside their list and
modal. The review dialog shows the current working directory as the base for
relative input, then the validated absolute destination after Review Contents.
Changing input clears the reviewed destination. Confirmation validates that the
resolved destination still matches the reviewed location before publishing.
These locations exist only in the transient review, never in stored scientific
state, events or generated snapshot provenance.

**Verification:** 2,862 assertions passed across the regression run and a
corrected focused layout rerun, with zero failures/errors/test warnings/skips
in the combined results. This covers the normal test directory except
`app-ui-baseline`, whose larger navigation journeys were not rerun for C05.
The snapshot subset contributes 498 assertions; C05 adds 80 assertions,
including 57 real-browser checks of the complete production review modal at
1280px and 375px. The reported COL07 PNG path, an unbroken filename, relative
base and resolved destination fit without path/modal/document horizontal
overflow; selecting each path returns its original text. Existing completion
layout checks (SNP-06) pass with the shared helper.

Real server-handler tests verify no copying on review, both Windows slash
styles and relative input, rejection of invalid/overlapping destinations,
review invalidation and refusal when a relative destination resolves elsewhere.
Existing source-preservation and destination-free events/README/manifest tests
pass. Tests used R 4.5.3 with supported Windows UTF-8 and disposable synthetic
inputs only; neither real Che dataset changed. Local scripts/logs/results are
ignored under `artifacts/local-checks/`. The optional >4 GiB ZIP64 gate was not
enabled. C06–C10, including the final acceptance replay, remain open.

## C06 — Snapshot rollback and Unicode

- [ ] Implement and verify.

**Evidence:** Under the shell's unsupported `LC_ALL=C.UTF-8` setting, Windows R
fell back to the C locale and a controlled Unicode-path failure left an owned
staging directory. All 382 snapshot assertions pass with
`English_United States.utf8`; that does not close the fallback behavior.

**Inspect:** Locale scoping, path enumeration, owned-path verification and
rollback ordering in `util_scripts/14_utils_snapshots.R`.

**Change:** Make owned staging enumeration/removal safe for Unicode throughout
failure and interruption handling, including after caller-locale restoration.
Preserve the caller's locale on every exit. Retain strict ownership/containment
checks and never broaden deletion to a destination parent. If an OS error
prevents rollback, report remaining owned partial work accurately through the
existing local error flow without leaking destinations into provenance/logs.

**Acceptance:** Run controlled interruption/failure in both supported UTF-8 and
fallback C locales with Unicode names and nested long paths. Verify no false
success, no owned leftovers when removal is possible, no overwritten earlier
snapshot, unchanged source hashes and restored locale. Cover Both-mode partial
publication and post-rename interruption. ZIP worker permission errors must be
identified separately from application failures.

## Optional usability follow-up

### C07 — Omit CNA from the analysis views

- [ ] Implement and verify.

Add an explicit Omit CNA action near Reset Sample CNA, using the existing
omission decision/state workflow and unsaved-edit guards. Explain the affected
sample and invalidation of existing CNA decisions before confirmation. Keep
annotation and upstream results intact; preserve the existing policy for
retained historical outputs. Returning to status must not load unavailable
caches. Test cancel, confirm once, reload, exclusion from ordinary unfinished
CNA batches, and reversal through a complete valid configuration.

### C08 — Sample-specific defaults and threshold controls

- [ ] Implement and verify.

For a sample without a saved cut, initialize k to 7 within the valid range;
restore a saved sample's exact k and selection. Never inherit the previous
sample's unsaved k or reinterpret saved cluster IDs. Test switches in both
directions and changing k away/back during editing.

Document the current Y-axis maximum calculation before changing it. Use 0.5
as the proposed initial display maximum for an unsaved threshold group, while
preserving saved display limits and every persisted scientific threshold. When
needed, enlarge the control range to keep existing thresholds representable;
keep clipping indicators truthful. This is a display default, not a change to
malignant/non-malignant threshold values or classification rules. Align ticks
with selectable slider increments. Test equal Y thresholds, X constraints,
reload, multi-subclone classification and clipped views with identical saved
scientific assignments.

### C09 — Annotation feedback and setup reminders

- [ ] Implement and verify.

Show quiet progress based on saved annotation completion across configured
samples, with the current sample's unsaved state clearly distinguished. Make
the sample-complete notification visually distinct and textually explicit.
Increase dropdown height where it helps, bounded by the viewport; retain search,
scrolling and keyboard access for large vocabularies. Add a nonblocking reminder
for missing source DOI/URL in setup/status. Missing origin must still permit
standardization and snapshots. Verify counts after save/rerun/reload and keep
archived views read-only. These UI changes must not write biological decisions.

## C10 — Verification and acceptance gate

- [ ] Complete after C01–C06; record outcomes individually.

1. Add reproductions/regressions with each fix. Build on the existing F03/F09,
   F10/F14, F16/F17, state and CNA-preflight tests. Existing ERR-04's 26
   assertions and caught-error retry coverage remain regression evidence, not
   substitutes for process-death or browser tests.
2. Run focused checks, then the complete portable suite on the final required
   changes. Run browser checks for dataset transitions and modal layout with
   appropriate worker/browser access. Record locale, failures and skips; do not
   sum overlapping test counts as distinct coverage.
3. Perform a focused manual journey on synthetic/disposable workspaces:
   saved annotation → switch/restart; interrupted clustering → retry; computed
   CNA → omitted/reset; archive → reopen → one-sample recovery; snapshot review
   at narrow width and Unicode rollback. Inspect required damage and optional
   export damage separately in an archived GUI fixture for remaining ERR-04
   manual coverage. Do not rerun all real biological samples for acceptance.
4. Record cold/warm load and heatmap observations, exact sample/k and name
   cases, unselected-control preservation, and every deferred check. APP-06
   needs a measured reload/restart comparison; do not invent missing timings.
5. Update the manual review, original follow-up tracker and release acceptance
   record with each fixed checkpoint's evidence and remaining limitations.
   Close the required gate only after C01–C06 pass. Document P2 deferrals
   explicitly and keep historical failures/recovery distinguishable from fixes.

The completed active workspace in Windows Documents remains the scientific
reference. The repository dataset is a destructive-test artifact; its stale or
in-progress states are evidence, not permission to repair its files silently.
Do not modify, restore, rename or replace either real workspace as part of
these tests. Use disposable fixtures/copies for failure injection and recovery.
