# F15 Manual Replay — Liu2022 Liver

Use this checklist for the final full-dataset replay on `Liu2022_Liver` (9
configured samples). Record defects with the sample, stage, visible message,
and relevant lines from `datasets/Liu2022_Liver/logs/`.

**Latest status (2026-10-30):** The user has marked the CNA and storage-lifecycle
checklists complete, including optional export/re-export, cleanup, archived
reload, and reopen. Cleanup with the HCC3 export present produced a false
retained-file size warning, now traced to rounded storage metadata and fixed.
Reopen correctly makes cache-dependent stages stale. Earlier notes preserve
the initial defects and each subsequent implementation/retest result.

## Start and load

- [x] Start from the repository root with `Rscript scripts/run_app.R`.
- [x] Confirm there is no legacy autoreload warning and the session remains
  stable while files are written.
- [x] Select `Liu2022_Liver`, run standardization if needed, and load it.
- [x] Record the first-load time. Reopen the unchanged dataset later and record
  the reload time; it should not eagerly deserialize every cache.
- [x] Check the Start Menu overview, sample details, status tooltips, next
  action, and Dataset Storage card.
- [x] Switch repeatedly between visible tabs and confirm navigation remains
  responsive and never jumps to Dataset Selection unexpectedly.

## Clustering and resolution

- [x] Run bulk clustering. Confirm the overlay reports `[i/9]`, current sample,
  truthful stages, monotonic progress, and one final summary/dialog.
- [x] Confirm completion opens Resolution Selection and all configured
  resolutions (`0.1`, `0.5`, `1.0`, `1.5`) are available for every sample.
- [x] Review/save resolutions and confirm cluster identifiers use natural
  numeric order, including any sample with more than 10 clusters.
- [x] Rerun clustering for one selected sample from the Start Menu. Confirm no
  other sample changes, downstream state for that sample becomes stale, and
  completion opens that sample in Resolution Selection.
- [x] Confirm the stale resolution reason says clustering *was rerun*, then
  review and save the resolution again.

## Differential expression and annotation

- [x] Run bulk DE. Confirm the same progress behavior and one completion
  dialog, followed by Manual Annotation.
- [x] For the single rerun sample, confirm stale annotation opens without first
  selecting another sample and its reason reflects the completed rerun.
- [x] Use “Rerun DE for Selected Sample” from Manual Annotation and confirm the
  targeted path works.
- [x] Inspect a long DE score-plot title: the full sample identifier and cell
  count/metadata must remain readable.
- [x] Annotate and save all samples. Confirm natural cluster order and that
  saving does not make clustering, resolution, or DE stale.
- [x] For at least one appropriate sample, save annotation before CNA
  configuration and confirm this is allowed and CNA remains visibly incomplete.
- [x] Reload the dataset and confirm saved annotations and valid upstream stages
  persist.
- [x] Explicitly omit CNA for a sample where it is scientifically unwarranted;
  reload and confirm the distinct omitted state persists. Reverse the omission
  with a saved CNA configuration if that sample will later enter CNA.

## CNA

- [x] Save reference and potentially malignant cell types for each applicable
  sample; confirm no navigation jump occurs.
- [x] Compute CNA for HCC3 through both single-sample and bulk actions
  (confirmed working on 2026-10-30).
- [x] Change `k`, save a cluster selection, and compute signal; then save a
  different selection and recompute signal (confirmed working on 2026-10-30).
- [x] On a high-cluster-count sample, use the subtree navigator. Confirm stable
  IDs, top-to-bottom/left-to-right ordering, hover/selection details, saved
  configuration, and downstream views identify the same cells without relying
  on colour alone.
- [x] Exercise threshold selection, including equal Y thresholds
  (`m_y == nm_y`); controls work correctly (2026-10-30).
- [x] After final saving succeeds, confirm threshold preview and final
  assignment agree, and explicitly verify `m_y < nm_y` remains prevented.
- [x] Finalize CNA and confirm assignments/plots are saved without automatically
  exporting the values table.
- [x] If choosing optional export, confirm the gzip CSV and provenance YAML appear under the
  sample’s `3_cna_results` directory and contain `gene`, `chr`, `start_pos`,
  `cell_name`, and `cna`.
- [x] Optionally use manual CNA re-export and confirm it does not recompute CNA.
- [x] Continue until every sample is either fully complete or has an explicit,
  justified CNA omission.

## Storage lifecycle — last, on a safe copy

- [x] Copy the finished dataset workspace and load the copy before testing
  cleanup. Do not use the only working copy for this destructive acceptance
  check.
- [x] Confirm Dataset Storage reports ready and review the exact cache inventory
  and retained-output checks before confirmation.
- [x] For completed CNA samples without current values exports on the safe copy,
  confirm cleanup is enabled and review the affected-sample warning explaining
  that exporting later will require reopening and recomputing CNA.
- [x] Run cleanup with the typed dataset confirmation. Confirm only
  reconstructible caches are retired and final plots/tables/exports remain.
- [x] Reload the archived copy: completed scientific work and archived storage
  state remain visible, while compute/edit tabs are unavailable.
- [x] Reopen the archived copy with the strong confirmation. Confirm retained
  results remain and cache-dependent stages explicitly require recomputation.

## Initial result record — 2026-10-28

This table preserves the original observations. See the dated follow-ups for
subsequent fixes and successful retests; an initial “Unable” result does not
describe the latest HCC3 computation/selection/threshold result.

2026-10-28: The first load after standardization exposed an empty-cache error
in the Dataset Storage card (`invalid argument type` in
`dataset_cache_inventory()`). Fixed the inventory to retain typed file metadata
when there are no entries. Regression coverage now checks absent/empty cache
directories and cleanup readiness before clustering; all 86 storage assertions
pass. Restart and dataset-load confirmation remain pending manual review.

| Check | Result | Notes / sample / log reference |
| --- | --- | --- |
| Standardization | Finished | The two buttons don't work to open standardization checklist and user guide. How should they work? A small issue is the conceptual missalignment of having a checklist for all dataset standardization, that needs to be reset after every dataset standardization. Maybe the checklist should also be copied over into each dataset and can be used by User. |
| Stable launch and navigation | Finished |  | 
| Initial load and unchanged reload | Finished | Launch under 1 second before any computation steps. Around 1 sec after clustering and de computation done.|
| Bulk and single-sample clustering | Finished |Bulk computation worked correctly. After opening the resolution selection the view was not updated from the time it was opened before the clustering was started, meaning it showed that no plots were there and the state still said that resolution not started. When opening a single plot view, which was never opened before, the correct plot loaded, but when going back to the Grid view the plots were still not loaded. This was fixed by selecting another sample and than going back to the first sample.|
| Resolution and stale wording | Finished | |
| Bulk and targeted DE | Finished | |
| Annotation save and reload | Finished | Error when trying to preview a sample with no saved annotation. Better to get warning and not show preview than to crash app. The error resulted in having stale states for nearly all samples that were not yet manually annotated, even for clustering. Not clear why some were stale and others not. Also some were stale in clustering, resolution, and de, but not in manual annotation, and a few were in all, except for the last cna status check. Maybe a button to rerun clustering for all stale samples would be good? I reran bulk clustering. Something good is that the resolution picking is easy, since the previously selected resolution is already selected and only the save res button needs to be pressed. The preview plot doesn't show NA/Unassigned in legend. Its also not on the saved plot. After the bulk de was done and the view was switched to manual annotation, it did not start on first sample again, could lead to forgetting to annotate a sample (Could be fine since states are there to shield from this). After doing all but one samples annotation, switched to and back from different dataset, this resulted in seemingly random stale and completed states for the samples. The correct labeling did not persist. The ones labeled as stale are shown stale at every status except for cna analysis. One weird status change was that clustering and resolution were shown as finished, as was annotation, but cna config not, even though cna omit was selected previously. There was also a sample where the status states still showed correctly. |
| CNA omission/configuration | Finished | |
| CNA compute, subtree selection, thresholds | Finished | Even though one sample (HCC3) had the configs selected for cna, its status check did not show them and thus cna computation could not be done.|
| CNA values export and re-export | Finished | |
| Safe-copy cleanup, reload, and reopen | Finished | After app restart, stale status error occured again. Seems to always be same samples. Still correct: Blood, HCC1, IT; Stale: Rest|

## Follow-up — F15-R01 (2026-10-28)

The original observations above are preserved. Investigation confirmed that
YAML rounded expression-file byte counts in the manifest for exactly the six
affected samples. The writer now preserves full precision; annotation-only
saves retain their scientific fingerprint, and equal-content backup recovery
updates file metadata correctly.

Read-only checks verified all 45 cache checksums and their input checksums.
Saved annotations agree with the selected caches for all nine samples when
blank CSV labels are normalized to unassigned. Recovery preview validated 30
manifest corrections and 30 prior state records; no dataset changes have been
applied. See the development plan's F15-R01 recovery instructions and
`scripts/recover_cache_precision.R` for preview and explicit application with
the app stopped. After recovery, confirm two reloads plus dataset switching
retain clustering/resolution/DE/annotation validity. R02 still owns CNA omission
state and full readiness acceptance; the remaining manual checks are pending.

Verification: all 60 focused R01 assertions pass; the full portable suite passes
1,524 assertions with zero failures/warnings and one restricted-browser skip.

## Follow-up — R01 confirmation and R02 (2026-10-28)

The user confirms that the app now shows the correct Liu2022 dataset states.
The original test observations above remain the evidence from the first run.

R02 now preserves explicit omissions through save, batch preflight, reload,
dataset switching, and cache reconciliation. Omitted samples show a dedicated
explanation without missing-configuration/cache warnings; saving a new CNA
configuration reverses the omission and returns computation to `not_started`.
Genuine upstream changes still invalidate prior decisions normally.

A read-only HCC3 preflight recognizes Macrophage/Hepatocyte configuration and
reports eligible: 279 reference cells, 75 configured candidates plus 474
unassigned cells, and 5,346 positioned genes. All eight intentionally omitted
samples reconcile to skipped computation in memory. Dataset state/configuration
was not edited during diagnosis, and no CNA computation was launched.

Manual follow-up pending: restart/load Liu2022, check omission wording and
HCC3 eligibility in the CNA view, then resume the outstanding CNA checks.

Verification: 53 focused R02 assertions pass; the full portable suite passes
1,580 assertions with zero failures/warnings and one restricted-browser skip.

## Follow-up — HCC3 CNA manual testing (2026-10-30)

| Check | Result | User observation / remaining scope |
| --- | --- | --- |
| Single and bulk CNA computation | Passed on HCC3 | Both computation entry points work correctly; the earlier readiness blocker no longer prevents HCC3 computation. |
| Cluster selection and signal recomputation | Passed on HCC3 | Changing `k`, saving a selection, computing signal, saving a different selection, and recomputing signal all work correctly. A specific high-cluster-count readability/stress test is not separately confirmed. |
| Threshold selection | Passed on HCC3 | Threshold controls work correctly, including equal Y values. Comparison with final saved assignment remains pending because finalization did not finish. |
| Threshold explanation | Low-priority improvement requested | Make the classification explanation more compact while preserving the current classification rules. No classification change was requested. |
| Save CNA results / exporting | Blocked — F15-R07 | The process appeared to run indefinitely: the user waited at least five minutes with the progress bar still at the first exporting stage, then stopped it. The cause and whether work was progressing internally are not yet established. |
| Export files, final assignment, manual re-export | Unverified | Successful publication and consistency of the final results were not confirmed after the interrupted save. |
| Safe-copy cleanup, archived reload, and reopen | Unverified | Finalization must complete before the finished-dataset storage lifecycle can be accepted. |

The follow-up plan records the save/export stall as the next P0 blocker
(F15-R07) and the compact helper text as an optional wording task (F15-R08).
No diagnosis, export repair, or new automated verification is claimed by this
manual report. R02's HCC3 computation path is manually confirmed; the omitted
samples' UI/reload behavior has not been explicitly reconfirmed in this update.

## Follow-up — R07 implementation (2026-10-30)

Read-only inspection confirms that the interrupted HCC3 run saved its final
cell assignments and plots (`cna_assignment` completed at
`2026-10-30T09:25:00.594Z`), but no values CSV/provenance was published.

The exporter was copying the entire CNA table for each 25-cell chunk and
showing a fixed 10% progress value until completion. It now selects the chunk
before conversion, reports stage/chunk/row progress and elapsed time, and uses
bounded gzip binary reads for exact header/record-count validation. Publication
of the CSV/provenance pair remains atomic. Errors identify their stage, and
interruptions retain saved assignments, clean temporary files, preserve any
prior complete export, and support independent export retry. Assignment-save
completion is now logged before export starts.

A synthetic test at HCC3's dimensions (5,000 genes × 14,872 cells) publishes
74,360,000 rows in 54.4 seconds, yielding a 633.8 MiB gzip CSV whose metadata
reports current. This is automated performance evidence, not a manual HCC3
export result or guaranteed runtime. Actual dataset files were not changed.

**Manual retry pending:** Restart, open HCC3's Assign & Summary view, and use
**Export/Re-export CNA Values Table**. Check progress advances during writing
and validation, the CSV/provenance become current, and assignments/plots remain
correct after reload. Do not rerun CNA solely to retry this export. Continue
safe-copy storage acceptance only after final outputs are verified.

Verification: 49 focused R07 assertions and the full suite pass (1,629
assertions, zero failures/warnings, one restricted-browser skip). Interruption
checks include stopping between CSV/provenance publication renames: an old
complete pair is restored, or a first export leaves no partial final files.

## Follow-up — Optional CNA values export (2026-10-30)

At the user's request, values-table export is now optional. Finalization saves
assignments and plots only; **Export/Re-export CNA Values Table** remains the
separate action for users who want a reusable table. Export absence or failure
does not change scientific completion.

Cleanup can proceed for finished samples without current CNA values exports.
Before confirmation, the storage card/dialog identifies affected samples and
warns that exporting their current values after cache removal would require
reopening the dataset and recomputing CNA. Existing exports, including older
ones, are retained. The warning is stored with the archive record, and changed
export availability after review requires a fresh warning before deletion.

The earlier export retry instructions remain useful if export is desired, but
the retry is not a prerequisite for manual cleanup acceptance. Required final
scientific outputs and all cache-retirement safeguards still apply. No real
dataset cleanup was performed during this change.

Verification: the full suite passes 1,658 assertions with zero failures/warnings
and one restricted-browser skip, including actual server finalization without
export and warned cleanup of a synthetic finished sample without a CSV.

## Follow-up — Keep the CNA preview open after saving (2026-10-30)

The user requested that final CNA saving stay on Assign & Summary, where
optional export is available. The status observer previously navigated to the
main CNA view and cleared the preview on every pipeline-state update, including
successful final assignment saving.

Status-only assignment updates now preserve the current preview and view.
The save handler no longer retriggers sample selection, and it updates preview
provenance for its own saved cell-cache checksum without recalculating plots.
Status badges still refresh. Changing the sample, dataset, upstream workflow,
or relevant CNA configuration still resets the view and invalidates old previews.

The integrated server regression registers both CNA status and summary
handlers, saves final assignments, and checks that the completed status updates
without navigation or preview clearing. Refresh reuses the saved preview, while
a subsequent threshold change still clears it. Manual follow-up: save HCC3
from the preview, confirm the view stays open, then optionally export values
without navigating back into summary.

Verification: 1,667 assertions pass in the full portable suite, with zero
failures/warnings and the known restricted-browser skip. Both the actual
status and summary server components are exercised together by the save test.

## Follow-up — Cleanup/reopen and retained-output warning (2026-10-30)

The user completed cleanup with HCC3's values table exported. Cleanup otherwise
appeared correct, but the app reported:

> One or more retained outputs are missing or changed: results/HCC3/3_cna_results/cna_values_HCC3.csv.gz: retained output size changed.

The user then reopened the dataset and confirmed the expected transition to
stale workflow stages. Logs confirm cleanup completed, the archived dataset
was reloaded, and explicit reopen completed. The checklist above now records
the user's completed CNA/export and storage-lifecycle checks; the warning is
the additional defect found during that otherwise successful run.

**Confirmed false positive:** Read-only comparison found that the storage
record rounded the export size to 921480780 bytes, while the actual file is
921480775 bytes. The recorded and actual MD5 checksums match exactly. The
values table was not damaged or changed by cleanup.

**Fix:** Storage-state YAML now uses full numeric precision for retained-file
sizes and recovered-space totals. For older rounded records, the audit accepts
the exact old rounding representation only when the retained file's checksum
also matches. Real missing files, changed content, or unexplained size
differences still fail the audit. No existing state file or result was edited,
and the user's intentional reopened/stale workflow state was preserved.

Read-only verification against the real archived state backup now checks all
32 retained outputs, including checksums, with no issues. Regression coverage
uses a large temporary file to verify precise persistence, legacy compatibility
without state mutation, and rejection of changed/deleted content. Manual
confirmation of the corrected warning display remains pending; repeating CNA
computation solely to repair this warning is unnecessary.

Verification: the full portable suite passes 1,680 assertions with zero
failures/warnings and the known restricted-browser skip; all 121 focused
storage assertions pass, including the new large-file/legacy audit regression.

## Follow-up — R03 annotation preview and Unassigned legend (2026-10-30)

The unannotated preview failure was reproduced with synthetic cells: all
missing labels leave zero colour categories and the palette generator throws
an error. Missing labels are also excluded from the old explicit legend breaks
in partial annotations. R01 separately established the rounded-cache-metadata
cause of the later stale-state split; preview was not shown to cause those
state changes.

Preview now warns without navigating when annotation data is unavailable or
no cell types have been assigned. Unsaved partial annotations can be previewed.
Plot construction and deferred build failures are caught, any old preview is
cleared, and retry works in the same session. Missing/blank/literal NA and
explicit Unassigned values become a single grey Unassigned category only in
the plotting copy, not in saved scientific labels. The saved annotation PNG
uses the same legend-bearing plot as the preview.

All 76 new regression assertions pass, including actual PNG comparison,
session survival/retry, all-cell retention, and unchanged persisted state,
configuration, cell data, cache artifacts, and manifests after preview. The
full suite passes 1,756 assertions with zero failures/warnings and the known
restricted-browser skip. No real dataset files were changed.

Targeted manual confirmation is still pending (the original completed replay
and notes above are preserved):

- [ ] Request preview before assigning any cluster: see an actionable warning
  and retain a usable session.
- [ ] Assign one cluster without saving, then preview: remaining cells and
  the legend show grey Unassigned.
- [ ] Save that annotation and check `2_de_plots/cell_types.png` has the same
  legend; clustering, resolution, and DE remain valid after saving/reload.

**Manual update (2026-10-30):** The user restored the dataset to its
pre-cleanup state, including caches, and confirms Unassigned appears in the
new annotation/DE preview plot legends. The unannotated-preview crash check
has not been exercised manually; it is deferred to the next full app test on
a new dataset. This does not imply that the other targeted checks above have
all been repeated. No dataset restoration was performed by the agent.

