# Development documentation

Implementation plans, manual review/replay evidence and release acceptance
records live here. Historical findings remain separate from implementation
verification and final acceptance.

- [Repository file catalog and cleanup assessment](REPOSITORY_FILE_CATALOG.md) —
  pre-cleanup usage evidence, file inventory, and cleanup candidates; excludes
  `datasets/`.
- [Original development plan](scAnnotationPipeline_Development_Plan.md)
- [Deferred computation performance plan](RESULT_PRESERVING_PERFORMANCE_PLAN.md) —
  proposed result-preserving optimizations and historical E00 evidence; work
  deferred 2026-11-13, with experimental code retained on its archived branch.
- [Prepared-data import and workflow entry plan](PREPARED_DATA_IMPORT_PLAN.md) —
  current workflow direction; supersedes earlier mandatory template, sample-YAML,
  checklist, and prompt-screen onboarding requirements in historical plans.
- [Che2021 Colorectal follow-up plan](CHE2021_COLORECTAL_2_FOLLOW_UP_PLAN.md)
- [Che2021 Colorectal remediation plan](CHE2021_COLORECTAL_REMEDIATION_PLAN.md)
- [C10 verification and remaining human acceptance](CHE2021_COLORECTAL_C10_VERIFICATION.md)
- [Che2021 Colorectal manual review](CHE2021_COLORECTAL_MANUAL_REVIEW.md)
- [Liu2022 Liver manual replay](F15_LIU2022_LIVER_MANUAL_REPLAY.md)
- [Release acceptance](RELEASE_ACCEPTANCE.md)

User-facing guides and runtime references remain in the parent directory:
[User Guide](../USER_GUIDE.md),
[Standardization Checklist](../STANDARDIZATION_CHECKLIST.md),
[Pipeline State](../PIPELINE_STATE.md),
[Pipeline Logging](../PIPELINE_LOGGING.md) and
[Cache Validity](../CACHE_VALIDITY.md).
