# Full Manual Review — Che2021 Colorectal

**Prepared:** 2026-10-30

**Dataset:** `datasets/Che2021_Colorectal/` (not `Che2021_Colorectal_2`)

**Status:** Checklist prepared; this replay has not yet been recorded as run.

The user has already created the new dataset folder, added raw data and updated
`samples_config.yaml`. Start by confirming that preparation, then complete the
remaining setup and run the whole semi-automatic pipeline. Do not import old
caches, selected decisions or completion states just because an earlier version
of this dataset was nearly finished.

This review combines the normal scientific workflow with the remaining manual
checks from the [follow-up plan](CHE2021_COLORECTAL_2_FOLLOW_UP_PLAN.md),
[Liu2022 replay](F15_LIU2022_LIVER_MANUAL_REPLAY.md) and
[release acceptance record](RELEASE_ACCEPTANCE.md). Previous successful tests
remain historical evidence; they do not pre-check this fresh replay.

## How to use this document

- Check a checkpoint only after its expected behavior was observed. Leave a
  failure unchecked and record **FAIL** with its ID in that part's Notes.
- Use **BLOCKED**, **DEFERRED** or **N/A**, with a reason, for unexercised checks.
  A missing high-cluster-count/long-name case is a coverage gap, not a pass.
- Each major part ends with an intentionally empty **Notes** section. Add notes
  there as you go, rather than using a separate results table at the end.
- Suggested note format: `ANN-01 — FAIL — <sample> — <action> — <observed versus
  expected> — <message/log time/screenshot>`. Reuse an ID for dated retests;
  keep the original failure and the later outcome distinguishable.
- All-sample checks mean every sample in the current configuration. Targeted
  regressions need only representative samples unless their wording says otherwise.
- Do not deliberately corrupt real inputs, exhaust a disk, kill a real batch,
  erase useful annotations or change biological decisions solely to manufacture
  a test. Use a small disposable fixture/copy for those checks, or record them
  as deferred. A review snapshot excludes caches/raw inputs and is **not** a
  full workspace backup for destructive tests.
- Do not record snapshot destination locations in these notes or screenshots
  intended for sharing. Refer to the chosen destination generically; capture
  when/what/outcome instead. Redact unrelated sensitive metadata when needed.

Record run context here before starting:

- Review date(s):
- Commit/build tested:
- OS, R version and launch method:
- Configured sample count and resolutions:
- Early representative sample A (targeted reruns):
- Later sample B (DE navigation/subset checks):
- Unselected control sample C, if available:
- Scientifically suitable CNA sample(s), including a small one for reruns:
- Long-name / >10-cluster / high-`k` sample(s), if available:
- Full workspace backup verified before destructive checks (yes/no; no location):

## 1. Workspace preparation, documentation and standardization

### Checklist

- [ ] `PRE-01` Confirm the existing fresh workspace, raw inputs and configured
  sample identities match the intended Che2021 dataset. Do not recreate the
  workspace or overwrite the user's updated sample configuration.
- [ ] `PRE-02` Review `dataset_config.yaml`: dataset identity, actual sequencing
  technology, matrix scale/names, filtering, normalization, PCA/UMAP, seed,
  resolutions, marker filters and DE settings are appropriate. Record the chosen
  settings/sample count above rather than assuming the old run's values.
- [ ] `PRE-03` Add a verified publication DOI and/or dataset link in
  `project_info.source_doi` / `source_url` if known. If unknown, leave blank;
  missing origin must not prevent standardization or later snapshot creation.
- [ ] `PRE-04` From Dataset Selection, before loading standardized data, open
  Standardization Guide, the metadata prompt, the dataset checklist and User
  Guide. Verify readable content, correct source paths, copy/select controls and
  Markdown download without depending on an external file association. (R05)
- [ ] `PRE-05` Add a note/checkmark to this workspace's
  `STANDARDIZATION_CHECKLIST.md` in the editor, reopen its viewer and confirm
  persistence. The shared `docs/STANDARDIZATION_CHECKLIST.md` stays unchanged.
- [ ] `PRE-06` On two disposable setup workspaces, verify independent checklist
  copies; on a legacy scratch workspace without a checklist, explicitly create
  its copy and confirm subsequent opening never overwrites its notes. Do not
  create these test workspaces over existing scientific datasets. (R05)
- [ ] `PRE-07` Try loading this workspace before standardization is complete.
  The app gives an actionable preparation message, does not crash and does not
  treat checklist marks as completed scientific work. (R05)
- [ ] `STD-01` Adapt this dataset's `standardize.R` using the
  [standardization checklist](STANDARDIZATION_CHECKLIST.md): inspect raw layout,
  confirm counts/TPM/CPM and gene identifiers, map canonical samples and retain
  justified source annotations/metadata. Raw inputs remain unchanged.
- [ ] `STD-02` Run the complete adapted script from a clean R session. It reaches
  strict `POST-VALIDATION PASSED`, publishes the staged outputs and records
  completed standardization; errors must stop publication, not be ignored.
- [ ] `STD-03` Confirm every configured sample has its expression matrix,
  `Genes.txt` and `Cells.csv` under `processed_data/`. Matrix dimensions/order
  agree with gene and cell metadata, identifiers are valid/unique, and declared
  expression scale matches the actual values.
- [ ] `STD-04` Confirm dataset-wide `Samples.csv` matches configured samples and
  per-sample cell counts. Record pre-clustering cell counts for representative
  samples; app-filtered cells should remain in standardized data later.
- [ ] `STD-05` Inspect the resulting configuration/state/logs: no old selected
  resolutions, archived storage state or downstream completed steps have been
  silently inherited from the previous run.

### Notes — preparation and standardization


## 2. Startup, loading, dashboard and responsiveness

### Checklist

- [ ] `APP-01` Start from the repository root using
  `source("scripts/run_app.R")` in an R console, or `Rscript scripts/run_app.R`
  in a terminal. There is no reactive-session startup error or legacy autoreload
  warning in this normal launch mode; record the tested method.
- [ ] `APP-02` Load `Che2021_Colorectal`. Record initial load time. Empty/new
  caches do not produce a Dataset Storage error, and the dataset/sample list is
  correct before any computation.
- [ ] `APP-03` Check initial overview counts, expanded per-sample details, next
  actions and storage readiness against the freshly standardized state. Only
  standardization is complete; cleanup/snapshots are not yet available.
- [ ] `APP-04` As mixed states arise later, hover and keyboard-focus aggregate
  status badges. Their sample names/counts agree with the details table; a long
  list points to the full details rather than hiding affected samples. (F10)
- [ ] `APP-05` Repeated tab/menu navigation remains responsive, including at a
  narrower window size. Normal saves, cache writes and plot generation never
  cause an unexplained session restart or return to Dataset Selection.
- [ ] `APP-06` After clustering/DE outputs exist, unload/reload the unchanged
  dataset and record warm load time. Later, restart R/the app and load again.
  Saved labels/states remain valid without random stale/missing-cache warnings
  or a repeat of the old long eager-cache load. (F04/R01)
- [ ] `APP-07` Switch to another available dataset and back after saving, without
  running work on the other dataset. Che2021's labels, selections and states
  remain consistent; the other dataset's work is untouched. If no suitable
  second dataset is available, record this check as deferred.

### Notes — startup, loading and dashboard


## 3. All-sample clustering and resolution selection

### Checklist

- [ ] `CLU-01` Before clustering, open a sample's resolution grid, note its empty
  view/status, then return to Start Menu. If entry is unavailable, note that and
  retain the targeted rerun refresh check below. (R04)
- [ ] `CLU-02` Open Select Samples for Clustering. All samples are initially
  checked with correct clustering states. Check Select all / stale / incomplete
  / Clear and individual checkboxes. Initially incomplete selects not-started
  samples, stale does not invent stale samples, and Clear disables Run.
- [ ] `CLU-03` Cancel and reopen the dialog: the fresh dialog defaults to all
  samples, not a silently retained narrow selection. Selected count/names and
  downstream-impact wording reflect the actual checkboxes. (F09 subset)
- [ ] `CLU-04` Run all samples once. Overlay/console show correct `[i/N]`, sample,
  stage/resolution and elapsed time, advancing progress, one final summary and
  one completion dialog. Normal navigation is intentionally blocked during the
  synchronous operation; repeated clicks must not start duplicate work. (F07)
- [ ] `RES-01` Use the completion action to open Resolution Selection with the
  first processed sample. The previously opened grid/status updates immediately
  without selecting another sample or restarting the app. (R04)
- [ ] `RES-02` Inspect grid and individual plot views for all configured
  resolutions. The correct current sample/plots appear when switching views;
  returning from the menu retains the chosen sample without stale images.
- [ ] `RES-03` Where >10 clusters occur, labels/legends/selectors use natural
  numeric order, colours match their labels and cluster IDs are not renumbered.
  If the dataset does not exercise this case, record the gap. (F08)
- [ ] `RES-04` Review and explicitly save a resolution for every sample. The
  selected configuration and overview update; a suggested/previously selected
  radio value alone must not count as a newly saved decision.
- [ ] `RES-05` Re-enter the views and reload the dataset once. Saved resolutions,
  plots and completed clustering/resolution states persist without spurious
  invalidation. Record any first versus repeated plot-load delay.

### Notes — clustering and resolutions


## 4. Differential expression and manual annotation

### Checklist

- [ ] `DE-01` Stage the R06 navigation check: run single-sample DE from Resolution
  Selection for later sample B, open its annotation view, leave B selected with
  no unsaved edits and return to Start Menu. This also tests the existing
  Resolution Selection single-sample DE action.
- [ ] `DE-02` Run bulk DE after all resolutions are saved. Overlay/console show
  correct sample/stage progress and one completion summary. Merely completing
  the run does not silently change the prior annotation selection. (F07/R06)
- [ ] `DE-03` Check the completion dialog's review count and first ready processed
  sample needing review. Go to Manual Annotation opens that sample, rather
  than retaining later B or requiring an away-and-back selection. (R06)
- [ ] `DE-04` Inspect marker-match tables and signature-score PNGs for representative
  samples, including the longest real sample name. Full sample titles and
  separate cluster/resolution/cell-count text remain readable in the app and
  saved images; record any unexercised very-long-name case. (F08 addendum)
- [ ] `ANN-01` On a genuinely unannotated/all-unassigned sample, request Preview
  before assigning a cluster. Expect an actionable warning or valid preview,
  never an app crash or unrelated stale states. Do not erase valid source
  annotations just to create this case; use a safe fixture or note N/A. (R03)
- [ ] `ANN-02` On a suitable partially unassigned sample, assign one cluster
  without saving and preview. Remaining NA/Unassigned cells have a visible grey
  legend key; preview does not persist the edit or change upstream state. (R03)
- [ ] `ANN-03` Save that preview/annotation and inspect `2_de_plots/cell_types.png`.
  Labels, Unassigned legend and colours agree with the preview and saved
  `Cells.csv`; upstream clustering/resolution/DE stay complete. (R03/F05)
- [ ] `ANN-04` Test unsaved edits before changing sample/dataset, leaving the
  annotation view, requesting reruns and saving CNA configuration/omission.
  Save/discard/cancel guards preserve the intended edits and selection.
- [ ] `ANN-05` Save annotation before making any CNA decision on at least one
  sample. Annotation completes independently; CNA remains visibly incomplete,
  with no forced configuration and no unintended navigation jump. (F05)
- [ ] `ANN-06` Annotate/review and save every sample, using the marker evidence and
  score plots. Cluster ordering is natural and sample-specific labels do not
  leak between samples. Preserve cells excluded by app preprocessing in the
  full standardized cell tables.
- [ ] `ANN-07` Reload and restart once after saving representative annotations.
  Labels, saved resolutions and completed upstream stages persist, and no
  annotation-only save produces false stale clustering/DE. (F04/F05/R01)
- [ ] `ANN-08` Use the overview/details to account for all samples needing review,
  rather than assuming that the currently selected or last sample is the only
  outstanding one. (R06/F10)

### Notes — DE and annotation


## 5. Targeted reruns, stale recovery and batch-completion choices

Do these checks before expensive final CNA work. Keep an unselected control C
when possible; rerun only representative samples, not the full dataset merely
to reproduce a targeted defect.

### Checklist

- [ ] `RER-01` Run Clustering for One Sample on A. Every configured resolution is
  processed only for A. Its downstream decisions require review, while C's
  state, saved decisions, result/cache files and labels remain unchanged. (F09)
- [ ] `RER-02` Return directly to A's already-open resolution view. Grid, detail
  plots and status refresh without changing samples. Clustering is completed;
  the saved resolution is stale until reviewed, with past-tense wording
  (“was rerun”), not a lingering claim that it is running. (R04/F04)
- [ ] `RER-03` Save A's reviewed resolution again. Open A's Manual Annotation view
  before redoing DE: the reason should identify the required DE step. The
  selected-sample Rerun DE button is above Back to Menu and targets A only.
  After DE finishes, annotation loads for review without a sample switch. (F09/F05)
- [ ] `RER-04` Reconfirm/save A's labels as appropriate to its new clustering.
  Completed upstream stages stay valid, stale reasons clear appropriately and
  other samples remain untouched. Do not assume old cluster membership survived.
- [ ] `RER-05` Exercise the clustering checklist with a small explicit subset,
  leaving C unchecked. Processing order follows dataset order, progress uses
  the selected total, and only selected samples' outputs/downstream state change.
  Completion navigation targets the first processed sample. (F09 subset)
- [ ] `RER-06` After these reruns, check the presets again: stale resolution/DE/
  annotation alone does not enter Select stale for clustering. If genuinely stale
  clustering or failed/incomplete samples arise, verify the corresponding preset
  selects exactly those samples and not an active computation. Do not manually
  edit pipeline state to manufacture a real-dataset failure.
- [ ] `RER-07` Re-save affected resolutions and run the required DE recovery. For
  a bulk DE completion, choose Stay on Start Menu and verify selection is
  retained; in another run, use Go to Manual Annotation and verify its fresh
  first-ready target. Unsaved edits must block rerun/navigation. (R06)
- [ ] `RER-08` Restore/review/save affected annotations, then verify all samples
  are again ready for an explicit CNA decision. Empty selections, duplicate
  confirmation clicks or cancelled rerun dialogs never start extra work.

### Notes — reruns and stale recovery


## 6. CNA decisions and computation

### Checklist

- [ ] `CNA-01` For each sample, make a scientifically justified CNA decision:
  save usable reference and potentially malignant cell types, or explicitly
  Omit CNA. Missing configuration is not silently treated as omission.
- [ ] `CNA-02` Where omission is appropriate, save it and reload. Annotation stays
  complete, CNA is visibly skipped/omitted with its decision preserved, and an
  omitted sample is not offered as ordinary unfinished CNA work. (R02)
- [ ] `CNA-03` On a suitable test sample/copy, reverse an omission by saving a
  complete valid configuration. CNA becomes eligible again without reclustering
  or losing saved annotation. Restore the intended scientific decision. (R02)
- [ ] `CNA-04` A configured, annotated eligible sample is actually usable in CNA
  views/computation after reload. If preflight blocks it, the reason names the
  real missing prerequisite/population/input rather than an obsolete warning.
- [ ] `CNA-05` Compute one eligible sample through the single-sample action.
  Informative stage/sample progress remains visible; completion returns to the
  main CNA state view and marks only the appropriate steps complete.
- [ ] `CNA-06` Use the bulk CNA checklist for other eligible samples or a small
  deliberate repeat. Selected names/counts and progress are correct; omitted or
  ineligible samples have honest reasons. Batch results distinguish completed,
  skipped and failed samples rather than falsely reporting universal success.
- [ ] `CNA-07` Verify first-load and warm/re-entry behavior: existing valid CNA
  outputs can be used without unexpected recomputation, session reload or an
  avoidable repetition of the slow initial heatmap load. Record perceived delays.
- [ ] `CNA-08` If a real/safe-fixture batch contains a failed or skipped sample,
  check that later eligible CNA work can continue and retry/resume targets only
  intended unfinished work. Do not provoke numerical failure on the main data.
- [ ] `CNA-09` On a small suitable sample/copy, if exercising Reset Sample CNA,
  check the confirmation and sample scope: dependent CNA work resets, saved
  configuration/manual annotation and other samples remain. Recompute/review
  that sample normally before treating it as complete.

### Notes — CNA decisions and computation


## 7. CNA subtree selection, thresholds, final saving and optional values

### Checklist

- [ ] `SEL-01` Inspect a suitable high-`k` cut (including >10 when feasible).
  Ordered navigator positions, stable cluster IDs, colours and cell counts map
  unambiguously to the same heatmap subtrees without colour-only guessing.
  Direct highlighting inside the main heatmap is **not** required. (F12)
- [ ] `SEL-02` Select subtrees using the ordered controls and inspect the live
  confirmation. Changing `k` clears the live selection; changing back during
  editing must not silently reinterpret old IDs. Reselect explicitly.
- [ ] `SEL-03` Save a selection, leave/reopen its exact saved sample/`k`, and
  verify the matching decision restores. Inspect the saved hclust image's
  cluster bar/legend for that saved cut; no extra heatmap highlighting is expected.
- [ ] `SEL-04` Compute signal/correlation; then deliberately save a different
  subtree selection on the representative sample and recompute. Dependent
  thresholds/assignment must not reuse obsolete selection inputs.
- [ ] `SEL-05` Compare initial heatmap load with repeated `k`/selection updates.
  Navigator interaction and row/summary changes do not add a noticeable extra
  full-heatmap computation. Record timings/observations in Notes. (F12/F14)
- [ ] `THR-01` Review the three compact rules beside each subclone's sliders.
  Malignant eligibility, the Unassigned/NA grey zone and the requirement to be
  below both non-malignant thresholds for every tested subclone are clear. (R08)
- [ ] `THR-02` Expand Boundary details. Strict comparisons and equal-Y wording
  are understandable, without changing slider values, classifications or plots.
- [ ] `THR-03` Set and save `m_y == nm_y`; reload and confirm equality persists.
  Attempt `m_y < nm_y`: controls must prevent it. Shared axes/clipping indicators
  remain meaningful and do not alter the saved underlying values. (F11)
- [ ] `THR-04` Compare threshold scatter views with proposed assignments: eligible
  cells above malignant thresholds become Malignant; the grey zone becomes
  Unassigned/NA. Where multiple subclones exist, check every-subclone retention
  and overlapping malignant support (Malignant with ambiguous/NA subclone).
- [ ] `SAV-01` Open Assign & Summary. The scatter comparison, pre/post UMAPs and
  summary heatmap belong to the current sample and saved selection/thresholds.
  An unchanged preview can be reused; a changed input must not remain savable
  as if the old preview were current.
- [ ] `SAV-02` Save final CNA results. Saving completes without hanging at an
  export stage, writes final cells/plots and stays on Assign & Summary, keeping
  the preview and optional export action accessible. It does **not** automatically
  generate a values table. (R07 and save-navigation follow-up)
- [ ] `SAV-03` Reload/re-enter the finalized sample. Saved labels/subclones agree
  with the preview, plots and `Cells.csv`; completion survives without false
  upstream invalidation or a forced recomputation.
- [ ] `SAV-04` Export CNA Values Table on at least one completed sample. Progress
  shows truthful writing/validation stages and elapsed time. The `.csv.gz` and
  matching `.metadata.yaml` appear together under `3_cna_results`.
- [ ] `SAV-05` Inspect the compressed table header/a small readable sample and
  provenance: `gene`, `chr`, `start_pos`, `cell_name`, `cna` and sensible dimensions.
  Preserve chromosome strings such as `01`; do not load a huge table in full
  merely to inspect its header. The wide cache is not replaced by this table.
- [ ] `SAV-06` Re-export on the representative sample while caches remain. It
  refreshes a complete pair without recomputing CNA or changing scientific
  completion. If interrupted/retry behavior is tested, use a disposable fixture.
- [ ] `SAV-07` Keep at least one appropriate finalized sample without an optional
  export when available, for the later cleanup warning check. If only one sample
  is CNA-eligible, test the missing-export case on a safe copy instead of deleting
  the only exported result. Complete/omit CNA for every sample before continuing.

### Notes — CNA selection, thresholds and saved outputs


## 8. Finished-dataset review snapshots before cleanup

Use a representative full-size snapshot to assess real runtime/space. The
automated suite already covers all 12 combinations; there is no need to produce
twelve large real copies. Exercise other modes/options on a small safe fixture
where doing so would otherwise waste substantial time/disk space.

### Checklist

- [ ] `SNP-01` Confirm creation is available only with every sample finished
  (CNA finalized or explicitly omitted), outputs present, no unsaved edits and
  no conflicting action. Earlier incomplete/stale stages must not be bypassed.
- [ ] `SNP-02` Open Create Review Snapshot. Logs default on; existing CNA values
  default off. Folder / Compressed archive / Both and the two independent
  switches are clear. Choosing a destination does not start copying or cleanup.
- [ ] `SNP-03` Review an existing parent destination outside managed datasets;
  confirm a relative path resolves as intended. Blank/nonexistent/overlapping
  destinations fail clearly; short native Windows paths using either slash
  style are accepted. Folder selection is still text entry, not a promised
  native Browse button.
- [ ] `SNP-04` Review included relative paths, source bytes, staging/readback space
  estimate and omissions. Unknown origin/legacy statistics and requested missing,
  outdated or incomplete CNA pairs are explained and require acknowledgement;
  they must not silently trigger scientific computation.
- [ ] `SNP-05` Create Both with the default inclusion choices on the full dataset.
  Copy/verification/compression/readback progress changes truthfully with elapsed
  time. Both the uniquely named folder and matching ZIP are created only after
  verification, without overwriting a prior snapshot. Record time/size, not location.
- [ ] `SNP-06` In Review snapshot verified, both complete paths wrap inside the
  popup and remain readable/selectable, including at a narrow window width.
  They must not extend past the popup or be clipped by the screen. (F17 layout fix)
- [ ] `SNP-07` Open the folder and extract/open the ZIP. Both contain the same
  requested content: complete processed data, all ordinary plots/results,
  historical provenance, README, summary CSVs and manifest. Raw input/cache trees,
  backups and previous snapshots are absent; default omission removes recognized
  CNA-value payloads/sidecars, not ordinary CNA plots.
- [ ] `SNP-08` Check the origin README and scoped summaries against representative
  cell tables/counts/settings: all standardized cells are distinct from analyzed
  cells; Unassigned/NA, malignant/subclone and filtered-out counts are sensible.
  Cells excluded by app preprocessing remain in the copied standardized files;
  their source labels must not be described as pipeline-reviewed. Unknown history
  is unavailable/NA, not an invented zero.
- [ ] `SNP-09` Inspect manifest entries and spot-check source/copy file equality,
  including matrices/genes/final cells and alternative-resolution/diagnostic plots.
  Source scientific files/choices/statuses remain unchanged apart from permitted
  operation log appends. Frozen copied logs need not include the later success event.
- [ ] `SNP-10` On a small safe completed fixture if needed, exercise Folder-only
  and ZIP-only modes and all four logs/CNA-value toggle combinations. Available
  current pairs copy only when requested; unavailable pairs warn/omit honestly.
  Record which combinations were manually exercised versus automated-only.
- [ ] `SNP-11` Check source export events and generated README/manifest: they
  describe when/what/options/outcome but not the destination. Moving/removing an
  expendable saved copy later does not create stale/intact/exported app statuses.

### Notes — review snapshots


## 9. Cleanup, archived snapshots and explicit reopen — last

Before deletion, verify a complete recoverable workspace backup including caches,
or use an independently loadable disposable workspace. Keep dataset identity
consistent; do not casually rename only the folder and edit state to make a
copy load. Do not rely on the cache-free review snapshot as that backup.

### Checklist

- [ ] `STO-01` Verify the safety prerequisite above and identify the intended
  cleanup target. Every sample is scientifically finished; a missing optional
  CNA export alone must not block cleanup. An unfinished required stage/output
  must still block it.
- [ ] `STO-02` Review cache count/space estimate and retained outputs. Completed
  CNA samples lacking a current optional values table are named with an explicit
  warning that exporting later will require reopening/recomputation. Check this
  case on a safe copy if all main-run samples have exports.
- [ ] `STO-03` Cancel or enter a wrong confirmation first: nothing is deleted.
  Then confirm the intended dataset ID once. Only validated reconstructible
  cache artifacts are retired/removed; processed cells/matrices, final plots,
  optional values/provenance, configuration and logs remain.
- [ ] `STO-04` Reload/restart in archived mode. Scientific completion/omissions
  remain intact and editing/computation is read-only. A retained large CNA export
  must not produce the old false “retained output size changed” warning.
- [ ] `STO-05` Create a snapshot from the archived dataset, requesting an existing
  retained CNA export. The verified pair remains eligible without its retired
  cache; unknown filtering history warns rather than blocking a basic snapshot.
  Cleanup is neither repeated nor implicitly reversed by exporting. (F17)
- [ ] `STO-06` Explicitly Reopen Dataset for Editing, with the strong confirmation.
  Retained scientific results remain, but cache-dependent completed/skipped
  stages now require review/recomputation with an honest cleanup reason.
  The app must not pretend deleted caches were restored or ready for immediate use.
- [ ] `STO-07` Where testing recovery, rebuild only a small representative sample
  through the normal clustering → resolution → DE → annotation/CNA sequence.
  Other samples remain honestly stale until processed. Do not automatically
  recompute the entire dataset solely to finish this destructive test.

### Notes — cleanup, archive and reopen


## 10. Isolated failure/guard checks and final review

Use small disposable fixtures/copies for deliberate failures. If these are not
manually exercised, leave them open with a reason; existing automated evidence
is useful but must not be relabelled as a new manual pass.

### Checklist

- [ ] `ERR-01` On an isolated fixture, a clustering/DE failure reports the sample
  and last real stage, preserves earlier saved work, leaves later work not run,
  and never displays an all-success completion. Retry is possible through the
  intended guarded action; unrelated samples are unchanged.
- [ ] `ERR-02` On an isolated completed fixture, interrupt/fail optional CNA export
  and retry. Final scientific assignment remains valid, a previous complete
  pair survives and no half-published new pair is presented as current.
- [ ] `ERR-03` On an isolated snapshot fixture, test interruption or a controlled
  unwritable/insufficient-space condition without filling a real disk. No false
  successful output, damaged source, overwritten earlier copy or destination
  leak occurs; operation-owned partial work rolls back or is clearly identified.
- [ ] `ERR-04` On an isolated archived fixture, remove/change a required retained
  output and separately an optional CNA values pair. Required damage is flagged;
  optional absence is not confused with unfinished science and requested snapshot
  values warn/omit instead of causing recomputation or a false completion claim.
- [ ] `FIN-01` Account for every configured sample and its scientific decision.
  Separate the finished pre-cleanup evidence from intentionally stale post-reopen
  state; a planned reopen is not an unexpected invalidation defect.
- [ ] `FIN-02` Review logs for unexplained restarts, repeated actions, misleading
  running/stale reasons or repeated cache validation on ordinary navigation.
  Record overall responsiveness and major run/first-load/warm-load durations in
  the relevant Notes sections, without inventing a pass from missing timings.
- [ ] `FIN-03` Give every unchecked checkpoint a FAIL/BLOCKED/DEFERRED/N/A note
  where applicable, including dataset limitations such as absent high-`k`, very
  long-name, multiple-subclone or extra CNA-eligible sample coverage.
- [ ] `FIN-04` Summarize remaining defects and successful retests by checkpoint ID
  in Notes below. Only then update the follow-up plan/release acceptance; do not
  close R03–R06, R08, subset clustering or F17 merely because this file was created.

### Notes — failures and final review
