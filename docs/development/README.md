# Development documentation

Implementation plans, manual review/replay evidence and release acceptance
records live here. Start with the [Developer Guide](DEVELOPER_GUIDE.md) for current
instructions. Historical findings remain separate from implementation verification
and final acceptance.

## Current instructions

- [Developer Guide](DEVELOPER_GUIDE.md) — setup, architecture, result-preservation
  rules, verification, and maintenance of `main` and `development`.
- [Testing](../TESTING.md) — test commands, browser/fixture policy, and the latest
  dated automated verification.

User-facing guides and runtime references remain in the parent directory:
[User Guide](../USER_GUIDE.md),
[Standardization Checklist](../STANDARDIZATION_CHECKLIST.md),
[Pipeline State](../PIPELINE_STATE.md),
[Pipeline Logging](../PIPELINE_LOGGING.md) and
[Cache Validity](../CACHE_VALIDITY.md).

Run app regression tests with `Rscript tests/testthat.R`. Development-tool
contracts are maintained separately on this branch:

```r
testthat::test_file("tests/development/test-profile-interactions.R")
testthat::test_file("tests/development/test-e00-performance-harness.R")
```

The E00 contract includes independent synthetic cache workers. Its pinned
historical baseline supports reproducing the original experiment; it is not a
current app performance baseline or evidence that deferred optimizations shipped.

## Plans and remaining work

Read the dated status in each plan before treating a task as outstanding or
starting implementation. A plan is not the current runtime specification.

- [Deferred computation performance plan](RESULT_PRESERVING_PERFORMANCE_PLAN.md) —
  proposed result-preserving optimizations and historical E00 evidence; work
  deferred 2026-11-13. The E00 tools and original experiment history are retained
  on `development`; see the [harness instructions](../../scripts/performance/README.md).
- [Prepared-data import and workflow entry plan](PREPARED_DATA_IMPORT_PLAN.md) —
  current workflow direction; supersedes earlier mandatory template, sample-YAML,
  checklist, and prompt-screen onboarding requirements in historical plans.
## Historical records

- [Branch-separation and cleanup history](BRANCH_SEPARATION.md) — dated decisions,
  retired branches, and verification evidence. Use the Developer Guide for the
  current maintenance workflow.
- [Repository file catalog and cleanup assessment](https://github.com/ag-tyler/scAnnotationPipeline/blob/4e357cc8d9f4de76ba174bd236f0800881e1e02b/docs/development/REPOSITORY_FILE_CATALOG.md) —
  pre-cleanup usage evidence, file inventory, and cleanup candidates; excludes
  `datasets/`. The original snapshot keeps historical file references available.
- [Original development plan](scAnnotationPipeline_Development_Plan.md)
- [Che2021 Colorectal follow-up plan](CHE2021_COLORECTAL_2_FOLLOW_UP_PLAN.md)
- [Che2021 Colorectal remediation plan](CHE2021_COLORECTAL_REMEDIATION_PLAN.md)
- [C10 verification and remaining human acceptance](CHE2021_COLORECTAL_C10_VERIFICATION.md)
- [Che2021 Colorectal manual review](CHE2021_COLORECTAL_MANUAL_REVIEW.md)
- [Liu2022 Liver manual replay](F15_LIU2022_LIVER_MANUAL_REPLAY.md)
- [Dated release acceptance](RELEASE_ACCEPTANCE.md)

The catalog is a dated baseline, not a live manifest. The subsequent cache
portability work and branch-separation changes are described in the import plan
and separation record. Historical test counts and failed human-review checkboxes
are retained as evidence; current automated results are in the Testing guide.
