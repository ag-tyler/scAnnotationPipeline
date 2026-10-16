# Pipeline Event Logging

The application keeps a persistent event history inside each dataset workspace.
It records processing actions and saved user decisions independently of the R
console and Shiny notifications.

## Files

Events are written under:

```text
datasets/<dataset_id>/logs/
├── pipeline_events.jsonl
└── pipeline.log
```

`pipeline_events.jsonl` is the canonical structured history. Each line is one
complete JSON object, so new events can be appended without rewriting older
history. `pipeline.log` contains the same events in a compact, human-readable
form for quick inspection.

Existing dataset workspaces receive the `logs/` directory automatically when
their first event is written. Newly created workspaces contain it from the
start.

## Event schema

| Field | Required | Meaning |
| --- | --- | --- |
| `schema_version` | yes | Integer version of the event contract |
| `timestamp` | yes | UTC ISO 8601 time with milliseconds |
| `dataset` | yes | Canonical dataset identifier |
| `sample` | no | Canonical sample identifier for sample-specific events |
| `stage` | yes | Pipeline area such as `clustering`, `annotation`, or `cna` |
| `event_type` | yes | Stable machine-readable action name |
| `outcome` | yes | Result such as `started`, `completed`, `saved`, `failed`, `skipped`, `reused`, or `invalidated` |
| `parameters` | yes | Named object containing relevant settings or summary counts; empty when none apply |
| `reason` | conditional | Actionable explanation; mandatory for `failed` and `skipped` events |

Example:

```json
{"schema_version":1,"timestamp":"2026-10-14T12:34:56.000Z","dataset":"Example_Dataset","sample":"sample1","stage":"resolution","event_type":"resolution_saved","outcome":"saved","parameters":{"resolution":0.5},"reason":null}
```

## Recorded events

The initial event catalog includes:

| Stage | Event types |
| --- | --- |
| Dataset | `workspace_created`, `dataset_load` |
| Standardization | `standardization_validated` |
| Clustering | `clustering_run` |
| Resolution | `resolution_saved` |
| Differential expression | `de_run`, `single_sample_de` |
| Annotation | `annotation_changed`, `annotations_saved` |
| CNA configuration | `cna_configuration_saved` |
| CNA analysis | `cna_compute`, `cna_batch_compute`, `malignant_clusters_saved`, `cna_signal_correlation`, `cna_thresholds_saved`, `cna_assignments_saved`, `cna_reset` |
| Cache | `cna_matrix_cache`, `cna_signal_cache`, `cna_cache` |

Long-running operations emit `started` followed by `completed` or `failed`.
Batch CNA also records sample-specific `completed` and `skipped` outcomes.
Saved decisions record the parameters needed to understand what changed.

## Reading events in R

The logging helpers are sourced with the other utilities:

```r
events <- read_pipeline_events("datasets/Example_Dataset")
events[[length(events)]]
```

Use `log_pipeline_event()` when failure to write the event should stop the
caller. Application handlers normally use `record_state_event()`, which emits a
warning rather than invalidating already-saved scientific output if logging
itself fails.

## Logging policy

- Record stage boundaries, persisted user decisions, cache reuse/invalidation,
  skips, and failures.
- Include settings or summary counts needed to reproduce or explain an action.
- Give an actionable reason for every failure or skip.
- Do not log expression matrices, individual cell records, secrets, or
  unnecessary absolute paths.
- Do not edit or truncate the JSON Lines file during normal operation.
- Treat the structured log as history, not as the source of current workflow
  state. Milestone 3 step-state files are defined separately by T09.
