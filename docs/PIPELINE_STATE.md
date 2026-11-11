# Pipeline State

The application stores the latest workflow status for each dataset in
`datasets/<dataset_id>/pipeline_state.yaml`. This file is separate from both
`selected_config.yaml` and the append-only event logs:

- `pipeline_state.yaml` answers **what is the current status?**
- `selected_config.yaml` stores current user selections.
- `logs/pipeline_events.jsonl` and `logs/pipeline.log` preserve **what happened
  over time?**

Use the app's save, reset, rerun, and recovery actions rather than editing the
state file manually.

## Statuses

| Status | Meaning |
| --- | --- |
| `not_started` | No attempt or saved decision has been recorded. |
| `in_progress` | An attempt started without a recorded outcome; it may still be running or require interrupted-work recovery. |
| `incomplete` | Required input or output is missing; `reason` explains what is needed. |
| `completed` | The step reached its defined completion boundary. |
| `skipped` | The step was explicitly or validly excluded; `reason` explains why. |
| `failed` | The latest attempt failed; `reason` contains the error. |
| `stale` | Previously valid work was invalidated by an upstream change. |

Missing prerequisites are `incomplete`, not `skipped`. A `skipped` state is
reserved for an explicit decision or validated exclusion.

## Tracked steps

`standardization` is the retained dataset-scoped key, displayed as **Prepared
inputs**. For imported data, `completed` means that the prepared directory
passed the lightweight input structure check and was successfully installed in
the workspace. Its details include `provenance: prepared_data_import` and
`validation_scope: structure_only`. This does not certify expression values,
matrix/metadata alignment, or biological correctness. The user prepares those
inputs before import; no sample YAML, script, checklist, or prompt usage is
required. See the [input specification](../README.md#preparing-input-data).

New imports initialize each sample step to `not_started`, selected decisions
through existing defaults, and storage as `active`; clustering is immediately
ready. A successful structure check on reload does not reset existing workflow
progress or turn stale scientific results into completed work. Older helper-run
and inferred records retain their historical meaning and provenance.

These steps are tracked per sample:

1. `clustering`
2. `resolution`
3. `differential_expression`
4. `annotation`
5. `cna_configuration`
6. `cna_compute`
7. `cna_cluster_selection`
8. `cna_signal_correlation`
9. `cna_thresholds`
10. `cna_assignment`

Each record contains its status, attempt number, timestamps, an optional
reason, and small reproducibility details. Large matrices and cell-level data
are never stored in the state document.

## Dependencies and stale results

```text
standardization
  -> clustering -> resolution -> differential_expression -> annotation
                                                        -> cna_configuration
annotation + cna_configuration
  -> cna_compute -> cna_cluster_selection
  -> cna_signal_correlation -> cna_thresholds -> cna_assignment
```

Changing an upstream selection marks only previously completed or skipped
downstream steps as `stale`. Changing one sample's resolution therefore marks
only that sample's DE, annotation, and CNA states stale. Saving the same value
again does not stale downstream work.

Pipeline state tracks logical validity. Cache fingerprints are handled by the
cache manifest, while intentional post-completion cleanup is tracked separately
in `storage_state.yaml`.

## Persistence and recovery

State writes are serialized with a short-lived dataset lock and use a
same-directory temporary file. A successful write increments `revision` and
retains the preceding document as `pipeline_state.yaml.bak`. A stale caller
cannot overwrite a newer revision.

If the primary file is corrupt or missing and the backup validates, the loader
restores the backup and warns. If neither copy validates, dataset loading stops
with an actionable error instead of inferring a misleading status.

When an older dataset has no state file, the app performs a conservative
one-time inference from required configuration and artifacts. Inferred records
contain `details.provenance: legacy_inference`; ambiguous partial outputs are
marked `incomplete`.

Loading uses the authoritative `processed_data/Samples.csv` and the workspace's
configured filenames. Legacy sample YAML is neither a metadata fallback nor a
requirement. Missing CSV blocks loading with a required-file error. Existing
preparation scripts, raw folders, YAML, notes, and saved scientific decisions
are preserved. Structural rechecks do not rewrite the sample CSV or create a
validation cache. Prepare replacement inputs in a new imported workspace;
external input replacement during analysis is not a supported workflow.

## Reset and repeated work

- Repeating clustering, DE, or a CNA computation creates a new attempt and
  marks applicable downstream completed work stale.
- Changed resolution, annotations, CNA configuration, malignant clusters, or
  thresholds propagate staleness only when the saved value changed.
- Resetting CNA preserves `cna_configuration` and returns `cna_compute` through
  `cna_assignment` to `not_started`.
- Event logs remain append-only; state updates never replace prior log lines.

Explicitly omitting CNA is a saved terminal decision and excludes that sample
from ordinary batch CNA computation. Historical downstream records can remain
stale; the overview recognizes the omission without treating those records as
current scientific results. Omission retains saved cell labels, plots, and
exports. Reset CNA instead restores pre-CNA manual labels where available and
removes CNA caches and plots; existing values exports may then be outdated.
To resume an omitted sample, save a valid CNA configuration and complete the
required downstream stages again.

### Interrupted clustering

On load, the app automatically recovers an unfinished clustering attempt when
it can verify that its recorded local execution has ended. For older or
unverifiable execution records, use **Recover Interrupted Clustering** on the
Start Menu, confirm that the previous run has stopped, and enter the dataset
identifier. Recovery is blocked when the recorded execution is still live.
It marks the interrupted attempt failed and retryable, preserving its files and
attempt history. Rerun the affected samples at all configured resolutions with
**Select Samples for Clustering**. Do not delete caches or edit YAML to unlock
an interrupted attempt.

The implementation and unit tests are in `util_scripts/07_utils_state.R` and
`tests/testthat/test-07_utils_state.R`.

## Archived datasets

The Start Menu's **Dataset Storage** card can archive a fully finished dataset
after it verifies durable final outputs for every sample. Explicit user CNA
omission is a valid terminal branch. CNA values exports are optional; missing
or outdated exports warn but do not block cleanup. Cleanup retires only the
dataset `cache/` directory and leaves scientific statuses and final outputs
unchanged.

`storage_state.yaml` records this separate lifecycle atomically as `active`,
`cleaning`, `cleanup_failed`, or `archived`. Archived datasets skip cache
reconciliation and are read-only. **Reopen Dataset for Editing** preserves the
results, creates a fresh cache directory, and marks previously completed or
skipped cache-dependent sample steps stale so recomputation is explicit.
The overview derives the next actionable step from the remaining prerequisites;
after those prerequisites are rebuilt, it directs you to unfinished CNA work.
This guidance does not turn historical stale records into completed results.

Archived workspaces with damaged retained sample files can still open for
read-only review when their sample CSV and recorded retired-storage state are
valid. The archive audits continue to block editing and unsafe exports. Review
snapshots work before/after cleanup without preparation scripts, sample YAML,
or checklist files; they include authoritative CSV and complete processed data,
plus optional preparation provenance when present. See the
[snapshot guide](USER_GUIDE.md#creating-a-review-snapshot).
