# Development scripts

Use a `development` checkout and run commands from the repository root with the
application's R dependencies installed. This reference covers development-only
profiling, benchmarking, and recovery tools, plus the personal cache reader
included in the 1.1.0 app release on local `main`.
Launching, downsampling, checkpoint copying, and test preflight are shared user
tools documented in the [README](../../README.md) and [Testing guide](../TESTING.md).

## Personal cache reading

[`load_dataset_cache.R`](../../scripts/load_dataset_cache.R) defines a small
reader taking one relative or absolute cache-file path:

```r
source("scripts/load_dataset_cache.R")
x <- load_cache_file("datasets/MyStudy/cache/expmat_filt_Sample_A.qs2")
class(x)
```

It returns the stored object with its classes and values preserved. Sourcing
only defines the function; reading does not change files or require a manifest.
It does not perform pipeline cache validation or recovery. See the
[User Guide example](../USER_GUIDE.md#loading-a-cache-file-for-personal-analysis).

## Profiling

| Script | Purpose and effects |
| --- | --- |
| [`profile_interactions.R`](../../scripts/profile_interactions.R) | Times interactive loading, overview/storage checks, and eligible annotation loads. Accepts an existing dataset ID or path and an iteration count; prints timings. Use a disposable workspace copy because its loaders can perform recovery writes. Annotation timing uses the configured biological resources. |
| [`profile_cna_export.R`](../../scripts/profile_cna_export.R) | Measures CNA table conversion time and allocations using synthetic data. Optional `--export` also exercises the export stages. Prints measurements and removes its temporary workspace; no biological dataset is used. |

```sh
Rscript scripts/profile_interactions.R datasets/DisposableStudyCopy 5
Rscript scripts/profile_cna_export.R 200 100
Rscript scripts/profile_cna_export.R 200 100 --export
```

The two numbers in the CNA profiler are genes and cells. Its defaults are 5000
genes and 3000 cells; smaller values are useful for a quick check.

## Computation comparisons

[`benchmark_computation.R`](../../scripts/benchmark_computation.R) runs the
retained E00 comparison harness in disposable workers and writes logs, timings,
and comparison evidence into a new output directory:

```sh
Rscript scripts/benchmark_computation.R --help
Rscript scripts/benchmark_computation.R --out artifacts/local-checks/e00-example --case synthetic --repeats 3
```

Use a different output directory for each run. The
[harness instructions](../../scripts/performance/README.md) describe cases,
policies, resource limits, and its historical baseline. Keeping this harness
does not resume the deferred E01 through E08 optimization work.

Files under `scripts/performance/` support this entry point: `harness.R`
orchestrates runs, `worker.R` executes child jobs, `workload.R` supplies fixtures
and workloads, `equivalence.R` compares results, and `contract.yaml` records the
comparison policy. Invoke the entry point rather than running these modules
individually.

## Cache recovery

Run these commands with the app stopped. Both accept a dataset directory name
under the configured datasets directory and preview changes by default:

```sh
Rscript scripts/recover_cache_precision.R MyStudy
Rscript scripts/recover_cache_location.R MyStudy
```

- [`recover_cache_precision.R`](../../scripts/recover_cache_precision.R) repairs
  legacy rounded manifest metadata after verifying the cache contents.
- [`recover_cache_location.R`](../../scripts/recover_cache_location.R) verifies
  and rebases cache metadata after a workspace move/copy, including supported
  legacy dependency recovery.

Append `--apply` to the relevant command to apply the previewed repair. Apply
creates recovery backups and updates verified metadata/state; it does not replace
scientific inputs or cache payloads. Location recovery requires the configured
biological resources. See [Cache Validity](../CACHE_VALIDITY.md#recovery-and-migration)
for recovery eligibility and state behavior.

## Focused verification

The interaction-profiler and E00 contracts are separate from the application suite:

```r
testthat::test_file("tests/development/test-profile-interactions.R")
testthat::test_file("tests/development/test-e00-performance-harness.R")
```

The personal reader is covered by `tests/testthat/test-load-dataset-cache.R`;
cache-recovery regressions are part of the ordinary app suite. Follow the
[Testing guide](../TESTING.md) for setup and the complete regression command.
