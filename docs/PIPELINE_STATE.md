# Pipeline State

The application stores the latest workflow status for each dataset in
`datasets/<dataset_id>/pipeline_state.yaml`. This file is separate from both
`selected_config.yaml` and the append-only event logs:

- `pipeline_state.yaml` answers **what is the current status?**
- `selected_config.yaml` stores current user selections.
- `logs/pipeline_events.jsonl` and `logs/pipeline.log` preserve **what happened
  over time?**

The state file must not be edited while the app is running.

## Statuses

| Status | Meaning |
| --- | --- |
| `not_started` | No attempt or saved decision has been recorded. |
| `in_progress` | The current attempt started but has not reached an outcome. |
| `incomplete` | Required input or output is missing; `reason` explains what is needed. |
| `completed` | The step reached its defined completion boundary. |
| `skipped` | The step was explicitly or validly excluded; `reason` explains why. |
| `failed` | The latest attempt failed; `reason` contains the error. |
| `stale` | Previously valid work was invalidated by an upstream change. |

Missing prerequisites are `incomplete`, not `skipped`. A `skipped` state is
reserved for an explicit decision or validated exclusion.

## Tracked steps

`standardization` is dataset-scoped. These steps are tracked per sample:

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

## Reset and repeated work

- Repeating clustering, DE, or a CNA computation creates a new attempt and
  marks applicable downstream completed work stale.
- Changed resolution, annotations, CNA configuration, malignant clusters, or
  thresholds propagate staleness only when the saved value changed.
- Resetting CNA preserves `cna_configuration` and returns `cna_compute` through
  `cna_assignment` to `not_started`.
- Event logs remain append-only; state updates never replace prior log lines.

The implementation and unit tests are in `util_scripts/07_utils_state.R` and
`tests/testthat/test-07_utils_state.R`.

## Archived datasets

The Start Menu's **Dataset Storage** card can archive a fully finished dataset
after it verifies durable final outputs for every sample. Explicit user CNA
omission is a valid terminal branch; completed CNA requires a current reusable
CNA values export. Cleanup retires only the dataset `cache/` directory and
leaves scientific statuses and final outputs unchanged.

`storage_state.yaml` records this separate lifecycle atomically as `active`,
`cleaning`, `cleanup_failed`, or `archived`. Archived datasets skip cache
reconciliation and are read-only. **Reopen Dataset for Editing** preserves the
results, creates a fresh cache directory, and marks previously completed or
skipped cache-dependent sample steps stale so recomputation is explicit.
