# Full Manual Review — Che2021 Colorectal

**Prepared:** 2026-10-30

**Dataset:** `datasets/Che2021_Colorectal/` (not `Che2021_Colorectal_2`)

**Status (2026-11-03):** Manual review finished; scientific run completed, but
release acceptance has outstanding failures. Additional isolated automated
checks and the consolidated outcome are recorded in section 10 below.

The completed, unarchived workspace preserved in Windows Documents is the
scientific reference for this review (pipeline revision 236, storage `active`).
The repository's current dataset is the later destructive-test workspace
(revision 260 when inspected): reopened after cleanup, mostly stale, with
interrupted clustering attempts. Do not use its status as the finished-run
result or restore it over the preserved copy. Both were inspected read-only.

The original instruction was to review a fresh dataset folder with raw data and
updated `samples_config.yaml`, without importing older caches or decisions.
That replay is now complete. The instructions/checkpoints below document the
review protocol; they are not a request to rerun the preserved scientific data.

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

- Review date(s): 2026-11-03; workspace created 2026-10-30.
- Commit/build tested: current inspected HEAD `5d59635955e89387b8f10beed62914dc631e1296`;
  the manual session logs do not record a commit, so exact manual-build identity
  cannot be independently established. Supplemental tests use this HEAD plus
  the review-specific test additions.
- OS, R version and launch method: Windows, R 4.5.3, Shiny 1.14.0,
  autoreload FALSE (logs). Normal console launch checked by reviewer;
  source-versus-terminal method not recorded. Supplemental checks: Rscript.
- Configured sample count and resolutions: 15; 0.1, 0.5, 1.0, 1.5.
  Counts/10x; min_genes 500, target_sum 100000, log2_expr_threshold 4,
  PCA 50, seed 3988; UMAP spread 5, min_dist 0.1.
- Early representative sample A (targeted reruns): COL07_liver_metastasis (logs).
- Later sample B (DE navigation/subset checks): COL07_primary_CRC was run
  singly before bulk DE; subset clustering used COL07_liver_metastasis and
  COL12_blood (logs).
- Unselected control sample C, if available: exact manually inspected control
  not recorded; other samples were outside the logged two-sample rerun.
- Scientifically suitable CNA sample(s), including a small one for reruns:
  ten finalized samples below; COL12_liver_metastasis has 2,759 analyzed cells.
- Long-name / >10-cluster / high-`k` sample(s), if available: RES-03/SEL-01
  checked by reviewer, exact >10 example/k not recorded. Real sample names
  include COL07_liver_metastasis; artificially very-long-name coverage deferred.
  Two subclones are recorded for COL07_primary_CRC and COL16_primary_CRC.
- Full workspace backup verified before destructive checks (yes/no; no location):
  reviewer checked STO-01; independent inspection found the preserved active
  workspace with cache tree and completed state. Full cache integrity/restore
  was not independently exercised during this supplemental review.

## 1. Workspace preparation, documentation and standardization

### Checklist

- [x] `PRE-01` Confirm the existing fresh workspace, raw inputs and configured
  sample identities match the intended Che2021 dataset. Do not recreate the
  workspace or overwrite the user's updated sample configuration.
- [x] `PRE-02` Review `dataset_config.yaml`: dataset identity, actual sequencing
  technology, matrix scale/names, filtering, normalization, PCA/UMAP, seed,
  resolutions, marker filters and DE settings are appropriate. Record the chosen
  settings/sample count above rather than assuming the old run's values.
- [x] `PRE-03` Add a verified publication DOI and/or dataset link in
  `project_info.source_doi` / `source_url` if known. If unknown, leave blank;
  missing origin must not prevent standardization or later snapshot creation.
- [x] `PRE-04` From Dataset Selection, before loading standardized data, open
  Standardization Guide, the metadata prompt, the dataset checklist and User
  Guide. Verify readable content, correct source paths, copy/select controls and
  Markdown download without depending on an external file association. (R05)
- [x] `PRE-05` Add a note/checkmark to this workspace's
  `STANDARDIZATION_CHECKLIST.md` in the editor, reopen its viewer and confirm
  persistence. The shared `docs/STANDARDIZATION_CHECKLIST.md` stays unchanged.
- [x] `PRE-06` On two disposable setup workspaces, verify independent checklist
  copies; on a legacy scratch workspace without a checklist, explicitly create
  its copy and confirm subsequent opening never overwrites its notes. Do not
  create these test workspaces over existing scientific datasets. (R05)
- [x] `PRE-07` Try loading this workspace before standardization is complete.
  The app gives an actionable preparation message, does not crash and does not
  treat checklist marks as completed scientific work. (R05)
- [x] `STD-01` Adapt this dataset's `standardize.R` using the
  [standardization checklist](STANDARDIZATION_CHECKLIST.md): inspect raw layout,
  confirm counts/TPM/CPM and gene identifiers, map canonical samples and retain
  justified source annotations/metadata. Raw inputs remain unchanged.
- [x] `STD-02` Run the complete adapted script from a clean R session. It reaches
  strict `POST-VALIDATION PASSED`, publishes the staged outputs and records
  completed standardization; errors must stop publication, not be ignored.
- [x] `STD-03` Confirm every configured sample has its expression matrix,
  `Genes.txt` and `Cells.csv` under `processed_data/`. Matrix dimensions/order
  agree with gene and cell metadata, identifiers are valid/unique, and declared
  expression scale matches the actual values.
- [x] `STD-04` Confirm dataset-wide `Samples.csv` matches configured samples and
  per-sample cell counts. Record pre-clustering cell counts for representative
  samples; app-filtered cells should remain in standardized data later.
- [x] `STD-05` Inspect the resulting configuration/state/logs: no old selected
  resolutions, archived storage state or downstream completed steps have been
  silently inherited from the previous run.

### Notes — preparation and standardization

- PRE-03: somewhere, maybe in the standardization checklist or at dataset status, needs to be a reminder to fill out source_doi and _url.

## 2. Startup, loading, dashboard and responsiveness

### Checklist

- [x] `APP-01` Start from the repository root using
  `source("scripts/run_app.R")` in an R console, or `Rscript scripts/run_app.R`
  in a terminal. There is no reactive-session startup error or legacy autoreload
  warning in this normal launch mode; record the tested method.
- [x] `APP-02` Load `Che2021_Colorectal`. Record initial load time. Empty/new
  caches do not produce a Dataset Storage error, and the dataset/sample list is
  correct before any computation.
- [x] `APP-03` Check initial overview counts, expanded per-sample details, next
  actions and storage readiness against the freshly standardized state. Only
  standardization is complete; cleanup/snapshots are not yet available.
- [x] `APP-04` As mixed states arise later, hover and keyboard-focus aggregate
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

- APP-02 load under a second
- APP-05 — FAIL — dataset switching produced the crashes recorded under
  ANN-07/STO-04; ordinary navigation was generally usable, but no crash-free
  responsiveness pass is justified. Narrow-window navigation coverage is
  DEFERRED beyond the reviewer's checked snapshot-modal layout test.
- APP-06 — DEFERRED (full checkpoint) — after restart, the reviewer observed
  correct labels/status and a 1–2 s Che load. Warm reload evidence is positive;
  no instrumented complete cold/warm timing comparison was recorded.
- APP-07 — FAIL, partial recovery — switching to Liu2022 triggered annotation
  indexing errors; fresh restart subsequently loaded both datasets. Later
  Che reloads passed, but the switching failure has no confirmed fix/retest.

## 3. All-sample clustering and resolution selection

### Checklist

- [x] `CLU-01` Before clustering, open a sample's resolution grid, note its empty
  view/status, then return to Start Menu. If entry is unavailable, note that and
  retain the targeted rerun refresh check below. (R04)
- [x] `CLU-02` Open Select Samples for Clustering. All samples are initially
  checked with correct clustering states. Check Select all / stale / incomplete
  / Clear and individual checkboxes. Initially incomplete selects not-started
  samples, stale does not invent stale samples, and Clear disables Run.
- [x] `CLU-03` Cancel and reopen the dialog: the fresh dialog defaults to all
  samples, not a silently retained narrow selection. Selected count/names and
  downstream-impact wording reflect the actual checkboxes. (F09 subset)
- [x] `CLU-04` Run all samples once. Overlay/console show correct `[i/N]`, sample,
  stage/resolution and elapsed time, advancing progress, one final summary and
  one completion dialog. Normal navigation is intentionally blocked during the
  synchronous operation; repeated clicks must not start duplicate work. (F07)
- [x] `RES-01` Use the completion action to open Resolution Selection with the
  first processed sample. The previously opened grid/status updates immediately
  without selecting another sample or restarting the app. (R04)
- [x] `RES-02` Inspect grid and individual plot views for all configured
  resolutions. The correct current sample/plots appear when switching views;
  returning from the menu retains the chosen sample without stale images.
- [x] `RES-03` Where >10 clusters occur, labels/legends/selectors use natural
  numeric order, colours match their labels and cluster IDs are not renumbered.
  If the dataset does not exercise this case, record the gap. (F08)
- [x] `RES-04` Review and explicitly save a resolution for every sample. The
  selected configuration and overview update; a suggested/previously selected
  radio value alone must not count as a newly saved decision.
- [x] `RES-05` Re-enter the views and reload the dataset once. Saved resolutions,
  plots and completed clustering/resolution states persist without spurious
  invalidation. Record any first versus repeated plot-load delay.

### Notes — clustering and resolutions


## 4. Differential expression and manual annotation

### Checklist

- [x] `DE-01` Stage the R06 navigation check: run single-sample DE from Resolution
  Selection for later sample B, open its annotation view, leave B selected with
  no unsaved edits and return to Start Menu. This also tests the existing
  Resolution Selection single-sample DE action.
- [x] `DE-02` Run bulk DE after all resolutions are saved. Overlay/console show
  correct sample/stage progress and one completion summary. Merely completing
  the run does not silently change the prior annotation selection. (F07/R06)
- [x] `DE-03` Check the completion dialog's review count and first ready processed
  sample needing review. Go to Manual Annotation opens that sample, rather
  than retaining later B or requiring an away-and-back selection. (R06)
- [x] `DE-04` Inspect marker-match tables and signature-score PNGs for representative
  samples, including the longest real sample name. Full sample titles and
  separate cluster/resolution/cell-count text remain readable in the app and
  saved images; record any unexercised very-long-name case. (F08 addendum)
- [x] `ANN-01` On a genuinely unannotated/all-unassigned sample, request Preview
  before assigning a cluster. Expect an actionable warning or valid preview,
  never an app crash or unrelated stale states. Do not erase valid source
  annotations just to create this case; use a safe fixture or note N/A. (R03)
- [x] `ANN-02` On a suitable partially unassigned sample, assign one cluster
  without saving and preview. Remaining NA/Unassigned cells have a visible grey
  legend key; preview does not persist the edit or change upstream state. (R03)
- [x] `ANN-03` Save that preview/annotation and inspect `2_de_plots/cell_types.png`.
  Labels, Unassigned legend and colours agree with the preview and saved
  `Cells.csv`; upstream clustering/resolution/DE stay complete. (R03/F05)
- [x] `ANN-04` Test unsaved edits before changing sample/dataset, leaving the
  annotation view, requesting reruns and saving CNA configuration/omission.
  Save/discard/cancel guards preserve the intended edits and selection.
- [x] `ANN-05` Save annotation before making any CNA decision on at least one
  sample. Annotation completes independently; CNA remains visibly incomplete,
  with no forced configuration and no unintended navigation jump. (F05)
- [x] `ANN-06` Annotate/review and save every sample, using the marker evidence and
  score plots. Cluster ordering is natural and sample-specific labels do not
  leak between samples. Preserve cells excluded by app preprocessing in the
  full standardized cell tables.
- [ ] `ANN-07` Reload and restart once after saving representative annotations.
  Labels, saved resolutions and completed upstream stages persist, and no
  annotation-only save produces false stale clustering/DE. (F04/F05/R01)
- [x] `ANN-08` Use the overview/details to account for all samples needing review,
  rather than assuming that the currently selected or last sample is the only
  outstanding one. (R06/F10)

### Notes — DE and annotation

- Not sure if its worth, but would be nice to somehow have way for the user to get progression updates during manual annotation. It should not be too in your face, but give an idea of how much is done. Also make the all annotations finished for sample popup different color so its clear that the sample annotation is finished.
- Also not necessily a must and rather low priority, but could the drop-down menu for cell types (maybe samples and others were it fits too) be made longer so no scrolling in the drop-down menu is necessary?
- ANN-07: Tried to change dataset, loading Liu2022_Liver, change again, and load Che2021. When trying to load Liu2022 this error occured:
Warning: Error in [[: subscript out of bounds
  99: <Anonymous>
  98: basename
  97: <reactive:annotation_load_trigger> [app/server/annotation_server.R#372]
  75: annotation_load_trigger
  74: eval_tidy
  73: eventFunc
  60: observeEvent(annotation_load_trigger())
  59: contextFunc
  58: env$runWith
  45: ctx$run
  44: run
  25: flushCallback
  24: FUN
  23: lapply
  22: ctx$executeFlushCallbacks
  21: .getReactiveEnvironment()$flush
  20: flushReact
  19: serviceApp
  12: shiny::runApp
  11: eval [scripts/run_app.R#20]
  10: eval
   9: eval
   8: eval
   7: eval.parent
   6: local
   5: eval [scripts/run_app.R#8]
   4: eval
   2: original_source
   1: source [<text>#151]
   After restart Liu2022_Liver could be loaded succesfully. Che2021 could also be loaded succesfully, which took around 1-2 seconds. The statuses were still correct and de annotation seemed to have saved correctly.
- ANN-07 — FAIL, partial recovery — the full switch/reload path failed as
  above. Saved annotations and upstream state survived a fresh restart;
  this successful recovery does not close the navigation crash.
## 5. Targeted reruns, stale recovery and batch-completion choices

Do these checks before expensive final CNA work. Keep an unselected control C
when possible; rerun only representative samples, not the full dataset merely
to reproduce a targeted defect.

### Checklist

- [x] `RER-01` Run Clustering for One Sample on A. Every configured resolution is
  processed only for A. Its downstream decisions require review, while C's
  state, saved decisions, result/cache files and labels remain unchanged. (F09)
- [x] `RER-02` Return directly to A's already-open resolution view. Grid, detail
  plots and status refresh without changing samples. Clustering is completed;
  the saved resolution is stale until reviewed, with past-tense wording
  (“was rerun”), not a lingering claim that it is running. (R04/F04)
- [x] `RER-03` Save A's reviewed resolution again. Open A's Manual Annotation view
  before redoing DE: the reason should identify the required DE step. The
  selected-sample Rerun DE button is above Back to Menu and targets A only.
  After DE finishes, annotation loads for review without a sample switch. (F09/F05)
- [x] `RER-04` Reconfirm/save A's labels as appropriate to its new clustering.
  Completed upstream stages stay valid, stale reasons clear appropriately and
  other samples remain untouched. Do not assume old cluster membership survived.
- [x] `RER-05` Exercise the clustering checklist with a small explicit subset,
  leaving C unchecked. Processing order follows dataset order, progress uses
  the selected total, and only selected samples' outputs/downstream state change.
  Completion navigation targets the first processed sample. (F09 subset)
- [x] `RER-06` After these reruns, check the presets again: stale resolution/DE/
  annotation alone does not enter Select stale for clustering. If genuinely stale
  clustering or failed/incomplete samples arise, verify the corresponding preset
  selects exactly those samples and not an active computation. Do not manually
  edit pipeline state to manufacture a real-dataset failure.
- [x] `RER-07` Re-save affected resolutions and run the required DE recovery. For
  a bulk DE completion, choose Stay on Start Menu and verify selection is
  retained; in another run, use Go to Manual Annotation and verify its fresh
  first-ready target. Unsaved edits must block rerun/navigation. (R06)
- [x] `RER-08` Restore/review/save affected annotations, then verify all samples
  are again ready for an explicit CNA decision. Empty selections, duplicate
  confirmation clicks or cancelled rerun dialogs never start extra work.

### Notes — reruns and stale recovery
- After the checks changed dataset and reloaded Che2021 without issues.

## 6. CNA decisions and computation

### Checklist

- [x] `CNA-01` For each sample, make a scientifically justified CNA decision:
  save usable reference and potentially malignant cell types, or explicitly
  Omit CNA. Missing configuration is not silently treated as omission.
- [x] `CNA-02` Where omission is appropriate, save it and reload. Annotation stays
  complete, CNA is visibly skipped/omitted with its decision preserved, and an
  omitted sample is not offered as ordinary unfinished CNA work. (R02)
- [x] `CNA-03` On a suitable test sample/copy, reverse an omission by saving a
  complete valid configuration. CNA becomes eligible again without reclustering
  or losing saved annotation. Restore the intended scientific decision. (R02)
- [x] `CNA-04` A configured, annotated eligible sample is actually usable in CNA
  views/computation after reload. If preflight blocks it, the reason names the
  real missing prerequisite/population/input rather than an obsolete warning.
- [x] `CNA-05` Compute one eligible sample through the single-sample action.
  Informative stage/sample progress remains visible; completion returns to the
  main CNA state view and marks only the appropriate steps complete.
- [x] `CNA-06` Use the bulk CNA checklist for other eligible samples or a small
  deliberate repeat. Selected names/counts and progress are correct; omitted or
  ineligible samples have honest reasons. Batch results distinguish completed,
  skipped and failed samples rather than falsely reporting universal success.
- [x] `CNA-07` Verify first-load and warm/re-entry behavior: existing valid CNA
  outputs can be used without unexpected recomputation, session reload or an
  avoidable repetition of the slow initial heatmap load. Record perceived delays.
- [x] `CNA-08` If a real/safe-fixture batch contains a failed or skipped sample,
  check that later eligible CNA work can continue and retry/resume targets only
  intended unfinished work. Do not provoke numerical failure on the main data.
- [x] `CNA-09` On a small suitable sample/copy, if exercising Reset Sample CNA,
  check the confirmation and sample scope: dependent CNA work resets, saved
  configuration/manual annotation and other samples remain. Recompute/review
  that sample normally before treating it as complete.

### Notes — CNA decisions and computation

- The cna analysis misses a button to return to its main menu where the status info is shown. At the moment when one sample is selected and the view is on the mal. clusters selection screen, changing to another sample results in a long loading process because of the big heatmaps. When next sample is loaded it starts on its status view, but its malignant clusters heatmap is already loaded, this is not necessarily helpful and could waste time. I think its probably difficult to stop this dynamic loading when switching sample during mal. cluster selection, but a knowledgable user with the ability to change the current samples view the to cna pipeline status could prevent this extra loading. The button would also be good if the user at any point wants to check the status. This extra loading does not happen if the next selected sample omits cna or has no cna computed yet.
- Error occured during the following steps. From loaded samples mal. cluster selection -> Next sample, which had cna omitted. From its cna status view -> selected another sample -> Reset CNA -> Selected previous cna computed sample and mal. cluster selection -> heatmap loaded -> Selected reset cna sample. The following errors occured when selecting omitted cna sample or reset cna sample when view was on mal cluster selection view:
Warning: Error in : Expected cached file not found: 'hclust_COL12_liver_metastasis.qs2'. Earlier work may be incomplete or invalidated.
  198: stop
  197: cache_load_data [util_scripts/04_utils_caching.R#732]
  196: <reactive:cna_static_plots> [app/server/cna_cluster_server.R#51]
  174: cna_static_plots
  173: <reactive:cna_cluster_identity> [app/server/cna_cluster_server.R#122]
  151: cna_cluster_identity
  150: <reactive:cluster_ui_model> [app/server/cna_cluster_server.R#128]
  128: cluster_ui_model
  127: renderUI [app/server/cna_cluster_server.R#156]
  126: func
  110: output$cna_cluster_navigator_ui
   12: shiny::runApp
   11: eval [scripts/run_app.R#20]
   10: eval
    9: eval
    8: eval
    7: eval.parent
    6: local
    5: eval [scripts/run_app.R#8]
    4: eval
    2: original_source
    1: source [<text>#151]
Warning: Error in : Expected cached file not found: 'hclust_COL12_liver_metastasis.qs2'. Earlier work may be incomplete or invalidated.
  198: stop
  197: cache_load_data [util_scripts/04_utils_caching.R#732]
  196: <reactive:cna_static_plots> [app/server/cna_cluster_server.R#51]
  174: cna_static_plots
  173: <reactive:cna_cluster_identity> [app/server/cna_cluster_server.R#122]
  151: cna_cluster_identity
  150: <reactive:cluster_ui_model> [app/server/cna_cluster_server.R#128]
  128: cluster_ui_model
  127: renderUI [app/server/cna_cluster_server.R#156]
  126: func
  110: output$cna_cluster_navigator_ui
   12: shiny::runApp
   11: eval [scripts/run_app.R#20]
   10: eval
    9: eval
    8: eval
    7: eval.parent
    6: local
    5: eval [scripts/run_app.R#8]
    4: eval
    2: original_source
    1: source [<text>#151]
The errors did not stop the app.


## 7. CNA subtree selection, thresholds, final saving and optional values

### Checklist

- [x] `SEL-01` Inspect a suitable high-`k` cut (including >10 when feasible).
  Ordered navigator positions, stable cluster IDs, colours and cell counts map
  unambiguously to the same heatmap subtrees without colour-only guessing.
  Direct highlighting inside the main heatmap is **not** required. (F12)
- [x] `SEL-02` Select subtrees using the ordered controls and inspect the live
  confirmation. Changing `k` clears the live selection; changing back during
  editing must not silently reinterpret old IDs. Reselect explicitly.
- [x] `SEL-03` Save a selection, leave/reopen its exact saved sample/`k`, and
  verify the matching decision restores. Inspect the saved hclust image's
  cluster bar/legend for that saved cut; no extra heatmap highlighting is expected.
- [x] `SEL-04` Compute signal/correlation; then deliberately save a different
  subtree selection on the representative sample and recompute. Dependent
  thresholds/assignment must not reuse obsolete selection inputs.
- [x] `SEL-05` Compare initial heatmap load with repeated `k`/selection updates.
  Navigator interaction and row/summary changes do not add a noticeable extra
  full-heatmap computation. Record timings/observations in Notes. (F12/F14)
- [x] `THR-01` Review the three compact rules beside each subclone's sliders.
  Malignant eligibility, the Unassigned/NA grey zone and the requirement to be
  below both non-malignant thresholds for every tested subclone are clear. (R08)
- [x] `THR-02` Expand Boundary details. Strict comparisons and equal-Y wording
  are understandable, without changing slider values, classifications or plots.
- [x] `THR-03` Set and save `m_y == nm_y`; reload and confirm equality persists.
  Attempt `m_y < nm_y`: controls must prevent it. Shared axes/clipping indicators
  remain meaningful and do not alter the saved underlying values. (F11)
- [x] `THR-04` Compare threshold scatter views with proposed assignments: eligible
  cells above malignant thresholds become Malignant; the grey zone becomes
  Unassigned/NA. Where multiple subclones exist, check every-subclone retention
  and overlapping malignant support (Malignant with ambiguous/NA subclone).
- [x] `SAV-01` Open Assign & Summary. The scatter comparison, pre/post UMAPs and
  summary heatmap belong to the current sample and saved selection/thresholds.
  An unchanged preview can be reused; a changed input must not remain savable
  as if the old preview were current.
- [x] `SAV-02` Save final CNA results. Saving completes without hanging at an
  export stage, writes final cells/plots and stays on Assign & Summary, keeping
  the preview and optional export action accessible. It does **not** automatically
  generate a values table. (R07 and save-navigation follow-up)
- [x] `SAV-03` Reload/re-enter the finalized sample. Saved labels/subclones agree
  with the preview, plots and `Cells.csv`; completion survives without false
  upstream invalidation or a forced recomputation.
- [x] `SAV-04` Export CNA Values Table on at least one completed sample. Progress
  shows truthful writing/validation stages and elapsed time. The `.csv.gz` and
  matching `.metadata.yaml` appear together under `3_cna_results`.
- [x] `SAV-05` Inspect the compressed table header/a small readable sample and
  provenance: `gene`, `chr`, `start_pos`, `cell_name`, `cna` and sensible dimensions.
  Preserve chromosome strings such as `01`; do not load a huge table in full
  merely to inspect its header. The wide cache is not replaced by this table.
- [x] `SAV-06` Re-export on the representative sample while caches remain. It
  refreshes a complete pair without recomputing CNA or changing scientific
  completion. If interrupted/retry behavior is tested, use a disposable fixture.
- [x] `SAV-07` Keep at least one appropriate finalized sample without an optional
  export when available, for the later cleanup warning check. If only one sample
  is CNA-eligible, test the missing-export case on a safe copy instead of deleting
  the only exported result. Complete/omit CNA for every sample before continuing.

### Notes — CNA selection, thresholds and saved outputs

- An observed behaviour during cna mal cluster selection is that the next sampls heatmap takes the k from the previous selection as the k for its first heatmap computation. Could argue that it should always start with 7 when no selection was saved before. When going back to a sample where clusters were already selected, than it switches correctly to the used k for the selection.
- What is the logic for deciding the Y-axis maximum when openning threshold selection? I would rather it starts always at a lower value like 0.4 or 0.5 since nearly always I select around this value, and rather have the warning that is already there for when values are clipped.
- Another small issue, is the threshold selection scales, they should have ticks and labels for the possible values. At the moment they can be different, e.g. i can show a tick at 0.41 for m_x even though only 0.4 or 0.45 are possible selections. It does not need ticks for every possible step, but ideally all ticks are possible steps.
- There should be an option to omit cna during the cna analysis, if the sample is deemed as not possible. e.g. a heatmap could show no clear malignant cluster. At the moment the user would need to remember the sample and go back to manual annotation to omit cna. The button could be above the 'Reset Sample CNA' button

## 8. Finished-dataset review snapshots before cleanup

Use a representative full-size snapshot to assess real runtime/space. The
automated suite already covers all 12 combinations; there is no need to produce
twelve large real copies. Exercise other modes/options on a small safe fixture
where doing so would otherwise waste substantial time/disk space.

### Checklist

- [x] `SNP-01` Confirm creation is available only with every sample finished
  (CNA finalized or explicitly omitted), outputs present, no unsaved edits and
  no conflicting action. Earlier incomplete/stale stages must not be bypassed.
- [x] `SNP-02` Open Create Review Snapshot. Logs default on; existing CNA values
  default off. Folder / Compressed archive / Both and the two independent
  switches are clear. Choosing a destination does not start copying or cleanup.
- [x] `SNP-03` Review an existing parent destination outside managed datasets;
  confirm a relative path resolves as intended. Blank/nonexistent/overlapping
  destinations fail clearly; short native Windows paths using either slash
  style are accepted. Folder selection is still text entry, not a promised
  native Browse button.
- [x] `SNP-04` Review included relative paths, source bytes, staging/readback space
  estimate and omissions. Unknown origin/legacy statistics and requested missing,
  outdated or incomplete CNA pairs are explained and require acknowledgement;
  they must not silently trigger scientific computation.
- [x] `SNP-05` Create Both with the default inclusion choices on the full dataset.
  Copy/verification/compression/readback progress changes truthfully with elapsed
  time. Both the uniquely named folder and matching ZIP are created only after
  verification, without overwriting a prior snapshot. Record time/size, not location.
- [x] `SNP-06` In Review snapshot verified, both complete paths wrap inside the
  popup and remain readable/selectable, including at a narrow window width.
  They must not extend past the popup or be clipped by the screen. (F17 layout fix)
- [x] `SNP-07` Open the folder and extract/open the ZIP. Both contain the same
  requested content: complete processed data, all ordinary plots/results,
  historical provenance, README, summary CSVs and manifest. Raw input/cache trees,
  backups and previous snapshots are absent; default omission removes recognized
  CNA-value payloads/sidecars, not ordinary CNA plots.
- [x] `SNP-08` Check the origin README and scoped summaries against representative
  cell tables/counts/settings: all standardized cells are distinct from analyzed
  cells; Unassigned/NA, malignant/subclone and filtered-out counts are sensible.
  Cells excluded by app preprocessing remain in the copied standardized files;
  their source labels must not be described as pipeline-reviewed. Unknown history
  is unavailable/NA, not an invented zero.
- [x] `SNP-09` Inspect manifest entries and spot-check source/copy file equality,
  including matrices/genes/final cells and alternative-resolution/diagnostic plots.
  Source scientific files/choices/statuses remain unchanged apart from permitted
  operation log appends. Frozen copied logs need not include the later success event.
- [x] `SNP-10` On a small safe completed fixture if needed, exercise Folder-only
  and ZIP-only modes and all four logs/CNA-value toggle combinations. Available
  current pairs copy only when requested; unavailable pairs warn/omit honestly.
  Record which combinations were manually exercised versus automated-only.
- [x] `SNP-11` Check source export events and generated README/manifest: they
  describe when/what/options/outcome but not the destination. Moving/removing an
  expendable saved copy later does not create stale/intact/exported app statuses.

### Notes — review snapshots

- Writing a relative path would be easier if somewhere the current path would be written.
- SNP-04: Some file paths that are too long clip over the border. e.g. "results/COL07_liver_metastasis/3_cna_plots/cna_threshold_unscaled_selection_subclone_1_COL07_liver_metastasis.png"

## 9. Cleanup, archived snapshots and explicit reopen — last

Before deletion, verify a complete recoverable workspace backup including caches,
or use an independently loadable disposable workspace. Keep dataset identity
consistent; do not casually rename only the folder and edit state to make a
copy load. Do not rely on the cache-free review snapshot as that backup.

### Checklist

- [x] `STO-01` Verify the safety prerequisite above and identify the intended
  cleanup target. Every sample is scientifically finished; a missing optional
  CNA export alone must not block cleanup. An unfinished required stage/output
  must still block it.
- [x] `STO-02` Review cache count/space estimate and retained outputs. Completed
  CNA samples lacking a current optional values table are named with an explicit
  warning that exporting later will require reopening/recomputation. Check this
  case on a safe copy if all main-run samples have exports.
- [x] `STO-03` Cancel or enter a wrong confirmation first: nothing is deleted.
  Then confirm the intended dataset ID once. Only validated reconstructible
  cache artifacts are retired/removed; processed cells/matrices, final plots,
  optional values/provenance, configuration and logs remain.
- [ ] `STO-04` Reload/restart in archived mode. Scientific completion/omissions
  remain intact and editing/computation is read-only. A retained large CNA export
  must not produce the old false “retained output size changed” warning.
- [x] `STO-05` Create a snapshot from the archived dataset, requesting an existing
  retained CNA export. The verified pair remains eligible without its retired
  cache; unknown filtering history warns rather than blocking a basic snapshot.
  Cleanup is neither repeated nor implicitly reversed by exporting. (F17)
- [x] `STO-06` Explicitly Reopen Dataset for Editing, with the strong confirmation.
  Retained scientific results remain, but cache-dependent completed/skipped
  stages now require review/recomputation with an honest cleanup reason.
  The app must not pretend deleted caches were restored or ready for immediate use.
- [ ] `STO-07` Where testing recovery, rebuild only a small representative sample
  through the normal clustering → resolution → DE → annotation/CNA sequence.
  Other samples remain honestly stale until processed. Do not automatically
  recompute the entire dataset solely to finish this destructive test.

### Notes — cleanup, archive and reopen

- STO-04: After archiving, tried to load different dataset resulted in following error and app crash:
Warning: Error in : Unknown or missing sample for step 'annotation'.
  88: stop
  87: get_pipeline_step [util_scripts/07_utils_state.R#300]
  86: cna_sample_preflight [util_scripts/05_utils_workflow.R#1873]
  85: <reactive:cna_status_preflight> [app/server/cna_status_server.R#21]
  63: cna_status_preflight
  62: observe [app/server/cna_status_server.R#189]
  61: <observer>
  12: shiny::runApp
  11: eval [scripts/run_app.R#20]
  10: eval
   9: eval
   8: eval
   7: eval.parent
   6: local
   5: eval [scripts/run_app.R#8]
   4: eval
   2: original_source
   1: source [<text>#151]
Warning: Error in [[: subscript out of bounds
  99: <Anonymous>
  98: basename [app/server/annotation_server.R#372]
  97: <reactive:annotation_load_trigger> [app/server/annotation_server.R#372]
  75: annotation_load_trigger
  74: eval_tidy
  73: eventFunc
  60: observeEvent(annotation_load_trigger())
  59: contextFunc
  58: env$runWith
  45: ctx$run
  44: run
  25: flushCallback
  24: FUN
  23: lapply
  22: ctx$executeFlushCallbacks
  21: .getReactiveEnvironment()$flush
  20: flushReact
  19: serviceApp
  12: shiny::runApp
  11: eval [scripts/run_app.R#20]
  10: eval
   9: eval
   8: eval
   7: eval.parent
   6: local
   5: eval [scripts/run_app.R#8]
   4: eval
   2: original_source
   1: source [<text>#151]

  After crash and restart, dataset could still be correctly loaded and archival state still correctly shown.
- STO-07: After CNA configuration was complete, the CNA analysis status still read stale for the sample, so not clearly visible for user which samples cna analysis is incomplete, as this should be correct status. CNA analysis could be done normally, just the status on main menu is wrong.
- STO-04 — FAIL, partial recovery — archived state survived restart and was
  reloaded as archived in the log at 15:25:42Z; dataset-switch crashes above
  remain unresolved. Large-output size precision has supplemental synthetic
  coverage; it was not independently rechecked against a retained large real
  export in an archived GUI session.
- STO-07 — FAIL (status presentation), recovery computation completed — logs
  show COL07_primary_CRC rebuilt after reopen through clustering, resolution,
  DE, annotation/configuration, CNA computation, thresholds and final assignment
  (16:08:31Z). Other samples honestly remained stale. The main-menu stale
  wording after new configuration was reported incorrect. Later deliberately
  interrupted runs are separate ERR-01 evidence.

## 10. Isolated failure/guard checks and final review

Use small disposable fixtures/copies for deliberate failures. If these are not
manually exercised, leave them open with a reason; existing automated evidence
is useful but must not be relabelled as a new manual pass.

### Checklist

- [ ] `ERR-01` On an isolated fixture, a clustering/DE failure reports the sample
  and last real stage, preserves earlier saved work, leaves later work not run,
  and never displays an all-success completion. Retry is possible through the
  intended guarded action; unrelated samples are unchanged.
- [x] `ERR-02` On an isolated completed fixture, interrupt/fail optional CNA export
  and retry. Final scientific assignment remains valid, a previous complete
  pair survives and no half-published new pair is presented as current.
- [x] `ERR-03` On an isolated snapshot fixture, test interruption or a controlled
  unwritable/insufficient-space condition without filling a real disk. No false
  successful output, damaged source, overwritten earlier copy or destination
  leak occurs; operation-owned partial work rolls back or is clearly identified.
- [ ] `ERR-04` On an isolated archived fixture, remove/change a required retained
  output and separately an optional CNA values pair. Required damage is flagged;
  optional absence is not confused with unfinished science and requested snapshot
  values warn/omit instead of causing recomputation or a false completion claim.
- [x] `FIN-01` Account for every configured sample and its scientific decision.
  Separate the finished pre-cleanup evidence from intentionally stale post-reopen
  state; a planned reopen is not an unexpected invalidation defect.
- [x] `FIN-02` Review logs for unexplained restarts, repeated actions, misleading
  running/stale reasons or repeated cache validation on ordinary navigation.
  Record overall responsiveness and major run/first-load/warm-load durations in
  the relevant Notes sections, without inventing a pass from missing timings.
- [x] `FIN-03` Give every unchecked checkpoint a FAIL/BLOCKED/DEFERRED/N/A note
  where applicable, including dataset limitations such as absent high-`k`, very
  long-name, multiple-subclone or extra CNA-eligible sample coverage.
- [x] `FIN-04` Summarize remaining defects and successful retests by checkpoint ID
  in Notes below. Only then update the follow-up plan/release acceptance; do not
  close R03–R06, R08, subset clustering or F17 merely because this file was created.

### Notes — failures and final review

- ERR-01: After interrupting clustering of one sample by stopping app and restarting app its status shows In progress. This status, while not necessarily wrong, it stops any try to restart the clustering for this sample. This makes the sample unable to be preprocessed correctly and needs to be fixed. This error does not happen when DE analysis is in progress, because it was interrupted. It can be restarted without a problem.

- ERR-01 — FAIL (manual interruption/restart); PASS (supplemental automated
  caught-error path). At inspection the destructive-test copy still records
  COL12_primary_CRC and COL12_liver_metastasis clustering as `in_progress`.
  COL12_primary_CRC started at 16:16:34Z, followed by a new session at
  16:17:20Z without a completion/failure event. COL12_liver_metastasis has a
  later unfinished attempt at 16:30:09Z. DE interruption/restart succeeded
  at 16:23–16:24Z. F07 tests verify failed DE sample/last-stage reporting and
  no later work; F09 tests verify failure notifications, no success navigation,
  preserved unrelated work and a fresh guarded clustering retry. A new retry
  assertion supplements the existing synthetic batch test. These caught-error
  passes do not exercise or repair process-death recovery.
- ERR-02 — reviewer marked complete; supplemental F13/R07 interruption,
  rollback, first-publication and retry tests pass. The real log records two
  writing interruptions at 16:28:40Z and 16:29:39Z with no later successful
  retry in that log; successful real export preceded them at 16:09:49Z.
  Do not describe those two interrupted attempts as successful re-exports.
- ERR-03 — reviewer marked complete; supplemental snapshot tests exercise
  controlled failure/interruption and publication rollback. ZIP testing needed
  execution outside the sandbox because processx pipe creation was denied.
  A separate Unicode rollback limitation under a fallback C locale is recorded
  below; the general guard successes do not erase that failure.
- ERR-04 — PASS (new isolated automated coverage); DEFERRED (manual archived
  GUI check). Four independent archived synthetic workspaces exercise removal
  and modification of required Cells.csv and optional CNA CSV separately.
  Required damage is detected and blocks inventory creation. Optional damage
  leaves science/snapshot readiness complete, warns, excludes the pair, requires
  acknowledgement, and then allows a verified snapshot without recreating
  caches. Persisted scientific state is unchanged. The checkbox remains open
  because this was automated fixture execution, not a new manual GUI pass.
- FIN-01 — independently reconciled all 15 configured samples against the
  preserved pre-cleanup state and standardized Cells.csv row counts. There are
  **140,281 standardized cells, 131,782 analyzed cells and 8,499 filtered-out
  cells**. Ten samples have final CNA assignments (8,856 recorded malignant
  analyzed cells altogether); five have explicit CNA omissions. These are
  saved workflow results, not a fresh biological validation of the labels.
  The later destructive-test copy's COL07_primary_CRC rerun has different
  assignments and must not be substituted into this finished-run summary.

| Sample | Standardized cells | Analyzed cells | Final CNA decision | Malignant cells | Subclones |
| --- | ---: | ---: | --- | ---: | ---: |
| COL07_liver_metastasis | 16,100 | 14,678 | Finalized | 1,693 | 1 |
| COL07_primary_CRC | 17,000 | 15,075 | Finalized | 4,022 | 2 |
| COL12_blood | 12,400 | 12,393 | Omitted | N/A | N/A |
| COL12_liver_metastasis | 3,160 | 2,759 | Finalized | 340 | 1 |
| COL12_primary_CRC | 10,750 | 9,975 | Finalized | 158 | 1 |
| COL15_liver_metastasis | 9,700 | 9,105 | Finalized | 847 | 1 |
| COL15_primary_CRC | 4,250 | 3,695 | Finalized | 504 | 1 |
| COL16_liver_metastasis | 8,200 | 7,983 | Finalized | 159 | 1 |
| COL16_primary_CRC | 6,000 | 5,161 | Finalized | 881 | 2 |
| COL17_blood | 6,700 | 6,688 | Omitted | N/A | N/A |
| COL17_liver_metastasis | 10,000 | 9,617 | Omitted | N/A | N/A |
| COL17_primary_CRC | 9,035 | 8,550 | Omitted | N/A | N/A |
| COL18_blood | 7,850 | 7,845 | Omitted | N/A | N/A |
| COL18_liver_metastasis | 10,436 | 10,163 | Finalized | 136 | 1 |
| COL18_primary_CRC | 8,700 | 8,095 | Finalized | 116 | 1 |

- FIN-02 — log review completed, with failures retained. No recorded automatic
  cache reconciliation occurred on inspected ordinary loads
  (`caches_reconciled: []`); that alone does not prove absence of repeated
  validation or heatmap work. Session-start events exist, but logs do not
  capture the GUI stack traces or reliably distinguish a deliberate restart
  from a crash. The reviewer's crash reports remain primary evidence.
  Deliberate reruns/export retries are distinguishable from duplicate actions;
  no unexplained duplicate computation was established from this log review.
  Full-size first/warm heatmap timings were not recorded. Reported unnecessary
  heatmap loading remains a performance concern, not a measured regression.

| Operation | Observed duration / size | Evidence |
| --- | --- | --- |
| Initial dataset load | under 1 s | Reviewer observation APP-02 |
| Restart/warm dataset load | approximately 1–2 s | Reviewer observation ANN-07 |
| Initial all-sample clustering | 20 min 21.8 s | 09:48:38.830–10:09:00.624Z |
| Initial bulk DE | 6 min 23.2 s | 10:15:57.708–10:22:20.956Z |
| Two-sample clustering subset | 3 min 41.2 s | 12:41:10.269–12:44:51.504Z |
| Bulk CNA | 21 min 50.5 s | 13:08:11.255–13:30:01.756Z; 11 processed, 4 skipped at that time |
| Snapshot Both, logs on / values off | 7 min 16.33 s; 447 files, 2,518,316,000 payload bytes | Verified completion event |
| Snapshot Folder, logs on / values on | 53.96 s; 449 files, 3,425,312,290 payload bytes | One CNA pair included |
| Snapshot ZIP, logs off / values off | 7 min 47.42 s; 443 files, 2,518,036,484 payload bytes | Verified completion event |
| Archived snapshot Folder, logs on / values off | 45.75 s; 447 files | Verified completion event |
| Cleanup | 3.63 s; 132 cache files, 1,053,845,279 bytes recovered | 15:24:01.506–15:24:05.136Z |

  Times ending in Z are UTC log timestamps. Payload sizes are source content
  bytes, not measured ZIP sizes or peak space. Bulk CNA's 11/4 split preceded
  the final 10/5 decisions: COL17_primary_CRC was subsequently omitted.
- FIN-03 — all eight remaining unchecked checkpoints are accounted for:
  APP-05 FAIL; APP-06 DEFERRED with partial reload evidence; APP-07 FAIL;
  ANN-07 FAIL with successful restart recovery; STO-04 FAIL with archived
  restart recovery; STO-07 FAIL for status despite completed small recovery;
  ERR-01 FAIL for interrupted clustering; ERR-04 manual DEFERRED with new
  automated PASS. Exact high-k examples, very-long-name coverage, fully
  instrumented load/heatmap timings, and the identity of manually inspected
  unselected control C remain DEFERRED/unrecorded. Multiple-subclone and
  multiple eligible-CNA-sample coverage are present. The source record checks
  SNP-10; the log independently establishes the three real mode/toggle
  combinations above, not a manual pass of all twelve combinations. All twelve
  are exercised by the automated snapshot suite.
- FIN-04 — overall outcome: **the scientific workflow completed, but release
  acceptance is not clean**. Successful manual coverage includes fresh setup,
  standardization, all-sample clustering/resolutions/DE/annotation, targeted
  reruns, CNA omission/reversal/computation/selection/thresholds/final saving,
  optional export, review snapshots, cleanup and explicit reopen. R03, R04,
  R05, R06, R08 and subset clustering have checked manual evidence in their
  respective stages; this does not imply adjacent navigation/recovery defects
  are resolved. F17's normal creation/content/modal review was successful,
  while the review-path wrapping issue and supplemental locale limitation
  remain open.

  Supplemental execution record (2026-11-03, R 4.5.3):

  - F07/F09/F16/F17 focused run: 681/682 assertions passed, zero errors/test
    warnings/skips after permitting ZIP worker execution. The one failure was
    Unicode staging-directory rollback in the fallback C locale; inherited
    `LC_ALL=C.UTF-8` is unsupported by this Windows R and emitted startup locale
    warnings. The initial sandbox-only run could not create processx pipes;
    those archive errors are execution restrictions, not scientific failures.
  - F17 rerun using `English_United States.utf8`: **382/382 assertions passed**,
    zero failures/errors/test warnings/skips. This includes all twelve
    mode/toggle combinations and **26 new ERR-04 assertions**. The C-locale
    leftover staging directory is a separately reproduced limitation; no
    fallback-locale application fix was made.
  - Updated F09 subset failure/retry plus F13/R07 export checks:
    **214/214 assertions passed**, zero failures/errors/test warnings/skips.
    Four added retry assertions verify a fresh guarded retry and unrelated-state
    preservation. Counts overlap the broader run and must not be added as
    distinct suite coverage.
  - These are targeted supplemental checks, not a rerun of the full portable
    suite, a browser journey, or a new >4 GiB ZIP64 gate. Synthetic workspaces
    were used throughout; the preserved and destructive-test real datasets
    were read only. Test additions are in
    `tests/testthat/test-f09-subset-clustering.R` and
    `tests/testthat/test-f17-review-snapshots.R`.

| Priority | Checkpoints | Remaining defect / action |
| --- | --- | --- |
| High | ERR-01 | Recover interrupted clustering on a new session so it can be retried; persisted `in_progress` currently blocks the sample. |
| High | APP-05/07, ANN-07, STO-04 | Guard dataset transitions against stale annotation indices and CNA sample identities; both crashed the app. Restart is recovery, not a fix. |
| Medium | CNA-07/09 | Guard malignant-cluster reactives for omitted/reset samples; navigation requests missing hclust caches and emits errors. Add an accessible return to CNA status and assess eager heatmap loading. |
| Medium | STO-07 | Refresh the main-menu CNA status/reason after post-reopen configuration; successful computation remained possible despite misleading stale display. |
| Medium | SNP-04 | Wrap long included-file paths inside snapshot review; the completion-modal wrapping test SNP-06 passed separately. |
| Follow-up | ERR-03 / F17 supplemental | Under the fallback C locale, controlled failure can leave a Unicode staging directory. Supported Windows UTF-8 rollback passes; retain the fallback limitation until fixed or explicitly scoped out. |
| Follow-up | SEL-02/03, THR-01–04, CNA-02 | Review cross-sample default k, initial Y maximum, ticks aligned to selectable threshold increments, and omission from within CNA analysis. These are usability requests, not established scientific-output failures. |
| Low | PRE-03, ANN-06/08, SNP-03 | Add source-metadata reminders, quiet annotation progress/completion feedback, longer dropdowns where suitable, and relative-path base guidance. |

  No application fixes or scientific reruns were performed as part of this
  supplemental review. Follow-up/release records point here and retain the
  unresolved acceptance items.

**C01 implementation follow-up — 2026-11-03:** The dataset-switch causes recorded
under APP-05/07, ANN-07 and STO-04 now have guarded dataset teardown/publication,
validated sample indexing and dataset/generation-scoped CNA context. New
synthetic server and browser regression coverage exercises stale indices,
unequal sample counts, same-workspace reload, annotation discard, CNA views,
archived switching and obsolete confirmation rejection. Synthetic scientific
files remain unchanged across read-only switches; the existing annotation
save/restart browser journey also passes. This is implementation verification,
not a fresh manual pass on the preserved Che workspace. Original failures and
checkboxes are retained; see C01 in the
[remediation plan](CHE2021_COLORECTAL_REMEDIATION_PLAN.md). Other C tasks remain
open, including interrupted clustering (C02) and the remaining CNA navigation
and post-reopen status work (C03/C04). No real dataset was modified.
Final verification: 2,549 portable plus 54 browser assertions passed with zero
failures/errors/test warnings/skips, including 44 C01 server and 15 new C01
browser assertions. The original manual failures remain distinguishable from
these synthetic implementation retests.

**C02 implementation follow-up — 2026-11-03:** ERR-01's interrupted-clustering
failure now has execution-owner tracking, conservative automatic recovery for
confirmed ended attempts, and explicit guarded recovery for legacy/unknown
records. Recovery marks the attempt failed/retryable, preserves its attempt
history and existing scientific artifacts, and keeps downstream decisions
requiring review. Another viewer's reload cannot release a known live run.
The current destructive-test workspace's older ownerless attempts require
Start Menu → Recover Interrupted Clustering and confirmation that their prior
computation has stopped; they were not repaired during implementation.

Disposable process-death tests covered interruption before cache publication
and after a resolution output was published, then real retries across all
configured resolutions. Server/browser tests cover confirmation, scopes,
duplicate actions, live-owner/revision/dataset/archive/unsaved/busy guards,
restart recovery and unchanged standardized cell labels. Interrupted DE retry
continues to work. Original manual failure notes and ERR-01's unchecked box
remain historical evidence; this is synthetic implementation verification.
No real dataset or user R process was modified or terminated. See C02 in the
[remediation plan](CHE2021_COLORECTAL_REMEDIATION_PLAN.md).

Final C02 verification: 2,631 portable plus 71 browser assertions passed, zero
failures/errors/test warnings/skips. This includes 79 recovery/ownership checks,
three DE retry assertions and 17 new browser assertions. Synthetic retries
completed all configured resolutions without changing standardized cell
labels. C03–C10 remain open.

**C03 implementation follow-up — 2026-11-03:** The CNA-07/09 navigation errors
and eager main-heatmap loading now have server-authorized sample/view guards.
CNA Pipeline Status is accessible beside the sample controls. Changing sample
returns to status before analysis outputs can read caches; omitted/reset or
incomplete samples and stale browser view events cannot load a main heatmap.
Threshold/summary views are similarly lazy, stale threshold/finalization saves
are blocked, and reset confirmation is bound to the reviewed sample.

Synthetic server/browser tests reproduced computed → omitted → reset →
computed navigation and saved sample/k restoration without missing-cache
errors. Instrumentation of the disposable browser app recorded one hclust
read, one CNA matrix read and one main heatmap build across status/warm re-entry
and k changes. First entry took 2.58 s; warm re-entry took 1.20 s, including
browser overhead on 48 cells/66 genes. These are not full Che timing estimates.
Only the last valid static plot bundle is retained, so visiting another sample
and actually building its heatmap can replace it. The updated sidebar screenshot
was visually inspected. No real dataset was used or modified.

Final C03 verification: 2,680 portable plus 91 browser assertions passed, zero
failures/errors/test warnings/skips, including 49 new server and 20 browser
assertions. Original manual failure notes remain historical evidence; C04–C10
remain open. See C03 in the
[remediation plan](CHE2021_COLORECTAL_REMEDIATION_PLAN.md).

**C04 implementation follow-up — 2026-11-03:** STO-07 now has synthetic
recovery/status regression coverage. After archive/reopen and upstream recovery,
saving valid CNA configuration displays the current base CNA compute action.
Archive-cleanup reasons advance through the remaining work; later retained
stale results no longer hide the first unfinished CNA stage. Scientific records
remain stale until recomputed/saved. Genuine cache failures keep their diagnosis,
untouched controls retain their exact reopened state, and omissions remain
distinct from missing configuration.

Final C04 verification passed 2,782 portable plus 104 browser assertions with
zero failures/errors/test warnings/skips, including 102 new portable and 13
browser assertions. Real synthetic archive/reopen and GUI decision/save handlers
were replayed through final assignment and restart; numerical rebuild phases
republished deterministic tiny fixture inputs. This does not claim a new
scientific recalculation or human manual acceptance pass. The updated Start Menu
screenshot was visually inspected. Neither real Che dataset was modified.
Original manual failure notes remain historical evidence. C05–C10, including
the final acceptance replay, remain open. See C04 in the
[remediation plan](CHE2021_COLORECTAL_REMEDIATION_PLAN.md).
