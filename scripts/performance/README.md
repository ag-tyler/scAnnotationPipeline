# Computation comparison harness (E00)

Development tool for the [performance plan](../../docs/development/RESULT_PRESERVING_PERFORMANCE_PLAN.md).
The app does not source this directory. No production algorithm is changed.

Run from the repository root with the application's R library available:

```sh
Rscript scripts/benchmark_computation.R --out artifacts/local-checks/e00-example --repeats 3
Rscript scripts/benchmark_computation.R --out artifacts/local-checks/e00-boundaries-example --case boundaries --repeats 3
Rscript scripts/benchmark_computation.R --out artifacts/local-checks/e00-tang-example --case tang --dataset datasets/Tang2026_Colorectal --sample CRC_T1 --cell-limit 128 --repeats 3
```

Use a **new output directory for each invocation**. Output inside the repository
is restricted to ignored `artifacts/local-checks/`; original dataset directories
are protected. External disposable directories are also supported. No directory
is overwritten or automatically deleted. A failed run retains its logs and files.

The default profile is `all`: actual batch clustering at every configured
resolution, DE, CNA/heatmap/Ward, two or saved subclone signal/correlation
calculations, final threshold application, and independent cache safety controls.
`--profile clustering` omits DE/CNA. `--profile cache` runs only the safety controls.
Every profile exercises valid, missing, corrupt, stale-dependency and recoverable
backup caches. These controls are small correctness probes, not representative
large-cache I/O benchmarks. Recovery produces an expected, compared warning.
An `all` run fails if CNA, signals or final-assignment coverage cannot complete.

## Reference, inputs and reproducibility

`contract.yaml` pins the original main commit, tolerances and default exact
comparison. Git archive exports its `util_scripts/`; separate copies of the
working tree's utility R files become the candidate. Git refs are never moved.
Each experiment freezes the harness, contract and one input RDS, records source
checksums and the working-tree diff, then uses independent empty dataset/cache
workspaces for each role and repeat. The candidate cannot reuse baseline caches.

Fixtures include a deterministic 420-gene/64-cell case and a 5,020-gene/64-cell
case with exact expression ties and chromosomes containing 99, 100 and 101 genes
around the smoothing-window size. Both have multiple resolutions, reference
types and subclones. The existing golden and characterization tests supply
additional arithmetic, degenerate and invalid-input coverage.

Tang extraction reads the prepared matrix and a checksum-verified selected
clustering cache directly. It never invokes recovery or writes in the original
dataset. Source input, configuration, annotation-cache/manifest and resource
checksums are verified before/after extraction and at experiment completion.
The deterministic subset samples cell types in round-robin order and restores
the original cell order. The saved pre-CNA annotations and configured reference/
candidate populations are retained. Gene-position resources follow app context
preparation; markers use an explicitly recorded resource-derived top-30 panel.
When saved Ward selections are absent, fixed diagnostic k=2 cuts/thresholds are
used in the copy. These are **not biological decisions or full app replay**.

`--cell-limit 0` requests the entire sample; do this deliberately with a suitable
budget. Subsets do not establish full-size performance, large-neighbor behavior
or full Ward scalability. The harness reads the source MatrixMarket file once
during parent preparation even for subsets, then freezes the reduced input.

## Observation and measurement boundaries

Each repeat runs four fresh R processes: captured baseline/candidate and
uninstrumented baseline/candidate. Role order alternates across repeats. Capture
processes temporarily wrap utility/namespace functions to save native scientific
objects, count graph builds, cache deserializations/validation/loads and table
reshapes, and record inclusive stage timings. Bindings are restored before exit.
These probes exist only in disposable workers.

Measurement processes run untouched functions and namespaces. Their timed region
starts after package loading, input reading and workspace preparation, and ends
after the workload and cache controls. PNG generation and normal production cache
writes remain included. Scientific artifact collection and the additional full
DE-ranking diagnostic happen afterward. Exact capture-versus-measure comparisons
check cache scientific payloads, input/decision identity, final assignments,
coverage and warnings. Capture-only native PCA, graph, unrounded CNA and plotting
inputs are compared between roles and baseline repeats.

`setup_seconds` records worker setup separately; experiment preparation time
includes parent source-data extraction and input freezing. Capture adjusted time
subtracts artifact serialization only: wrapper/memory overhead remains, so use
the **measure** rows for performance comparisons. Stage timings are inclusive;
do not sum nested stages. Zero counters in measure rows mean probes were disabled;
use capture rows to compare operation counts. Cache controls also report load time per scenario,
excluding fixture construction, in `cache_control_load_seconds`.

Peak memory covers the fresh worker lifetime, including package loading, input
and setup, through the workload end. Windows native peak working set is reported
where available; sampled RSS at approximately 100 ms is also recorded. On Linux
the sampled peak can miss brief allocations. Parent extraction RAM and
post-workload comparison/diagnostic allocations are outside this measure.
`--timeout-seconds 900` and `--max-memory-gb 12` bound each owned child process;
parent extraction has a conservative raw-file-size estimate guard, not an OS
memory limit. Only owned processes are terminated on failure.

R/platform, package versions, BLAS/LAPACK, locale, thread settings, parameters and
input identity must match between roles. OS file caches are **not** flushed.
For performance acceptance, run on an otherwise idle machine and compare repeated
measure rows against variability; record other activity. Parallel independent
case runs are acceptable for equivalence checks, not speedup claims.

## Scientific gates and output

`--policy exact` is mandatory for baseline repeatability and reuse-only E01-E03.
It requires identical cell/gene order, metadata, rankings, graphs, numeric values,
partitions/IDs, rounded CNA, Ward trees, decisions and final assignments.
`--policy numerical` is an explicit option for later arithmetic experiments:
unrounded CNA/DE errors at most `1e-8`; PCA singular-value relative error at most
`1e-6` and cell-subspace principal angle at most `1e-3` radians; rigid-aligned UMAP
RMS at most 1% and p99 at most 5% of baseline RMS radius, with mean 15-neighbor
overlap at least 99% on up to 128 deterministic anchors. Maximum displacement
and minimum overlap are also reported. No scale/warping alignment is allowed.
Every numeric entry is checked; only the UMAP neighborhood diagnostic uses anchors.

Approximation never permits identity, ranking, graph topology, partition, saved
cluster-ID, rounded-CNA or final-call changes. The actual independently generated
downstream outputs must pass; alignment never changes production inputs.
Missing artifacts, changed coverage/environment/warnings or invalid cache reuse
fail comparisons. Baseline repeats and capture-versus-measure remain exact even
when candidate arithmetic uses the numerical policy. Unit tests deliberately
perturb values, partitions/labels, row order, ranks, UMAP scale/outliers, PCA,
rounded CNA, threshold assignments and unsafe cache outcomes.

Retain the entire experiment directory as evidence:

| File | Purpose |
| --- | --- |
| `SUMMARY.txt`, `summary.rds` | Pass/fail, completed coverage and subset/full-size label |
| `comparisons.json`, `comparisons.rds` | Per-artifact metrics for paired roles, observer controls and baseline repeats |
| `measurements.csv`, `measurement_medians.csv` | All-run metrics and uninstrumented timing/memory medians |
| `experiment.rds`, `contract.yaml` | Frozen protocol, source/input provenance and preparation time |
| `baseline-source/`, `candidate-source/`, `harness/`, `input.rds` | Independent source snapshots and shared frozen input |
| Per-worker `result.rds`, `stdout.log`, `stderr.log` | Environment, stage timings/counters, cache controls and diagnostics |
| Per-worker `artifact_*.rds`, `dataset/` | Scientific payloads, caches and generated outputs |

An A/A pass establishes reproducibility and detector behavior. It provides no
speedup claim and does not authorize adoption of any optimization or a merge.
