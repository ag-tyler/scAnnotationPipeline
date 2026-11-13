# App and development branch separation

Prepared on **2026-11-13**. The catalog was committed independently as
`4e357cc` on `chore/repository-cleanup-audit`. Its baseline is `ef12c9a`;
the subsequent portability fixes on local `main` at `dd6d7e3` are preserved
in both prepared versions. The catalog remains a historical inventory.

## Branch roles

| Branch | Purpose |
| --- | --- |
| `main` | Existing default branch. It has not been changed by this preparation. After review, the app-focused candidate can be merged here. |
| `chore/app-development-separation` | App-focused candidate based on `dd6d7e3`; contains the application, tests, operational documentation and supported user tools. |
| `development` | Full application snapshot plus development tools, current/future plans, historical records, catalog and legacy/reference assets. The app source and ordinary regression suite match the candidate. |
| `chore/repository-cleanup-audit` | Preserved standalone pre-cleanup catalog commit. |
| `perf/result-preserving-computation` | Existing archived experiment at `a62b241`; not merged or resumed. |

No force-push, default-branch change or merge into `main` is part of this
preparation. Publishing branches does not publish the ignored local datasets,
biological resources, environment settings or validation artifacts.

## What belongs on the app-focused branch

- `app.R`, all `app/` components, `R/_disable_autoload.R`, configuration,
  dependency metadata and all shared `util_scripts/` implementations.
- `scripts/run_app.R`, `scripts/downsample_processed_data.R`, and
  `scripts/copy_dataset_checkpoint.R`: ordinary launching and reusable input/
  presentation operations documented for users.
- `templates/dataset_config_template.yaml`, required by dataset import, plus
  the supported optional `templates/standardize_general.R` and its tests.
- `resources/metadata_extract_prompt.txt`, an optional preparation reference;
  all seven ignored configured runtime resource files remain provisioned
  separately, as before.
- The complete app regression suite and reviewed scientific/browser fixtures.
  `test-f14-interaction-performance.R` retains its two runtime performance
  contracts; its profiler-file contract moves to `tests/development/` only.
- README, User Guide, optional preparation checklist, pipeline state/logging,
  cache validity, and a concise current `docs/TESTING.md`.

## Additional assets retained on `development`

| Paths | Reason |
| --- | --- |
| All `docs/development/` | Past findings/manual evidence, current implementation and acceptance records, future proposals, the catalog, and this maintenance record. |
| `scripts/profile_interactions.R`, `scripts/profile_cna_export.R` | Development profilers rather than ordinary app startup dependencies. |
| `scripts/recover_cache_precision.R`, `scripts/recover_cache_location.R` | Explicit manual recovery/migration entrypoints. Their underlying utility implementation and all recovery/portability regression tests remain on the app branch. |
| `templates/standardize_10x.R`, `templates/standardize_10x.qmd`, `templates/standardize_undefined.qmd` | Historical/reference external preparation workflows. |
| `resources/cancer_type_markers.csv`, `resources/canonical_markers.csv`, `resources/markers_ss.csv` | Older tracked tables with no current configured consumer found. Retaining them here preserves content/provenance uncertainty without distributing them in the app-focused tree. |
| `tests/development/test-profile-interactions.R` | Preserved profiler-file contract, run explicitly from the development checkout. |

The lean branch's README/guide link to the development records and tools.
Those links become usable remotely when `development` is published. The cache
guide explicitly requires a development checkout for the manual migration CLI.
The development guide labels the old marker tables as references, not required
runtime inputs.

No ignored local file or dataset is removed. The 3.14-GiB local artifact tree is
outside branch contents and remains a separate retention decision. Historical
evidence is preserved without representing it as current release acceptance.

## Maintenance workflow

1. Create app feature/fix branches from current `main`. Include runtime changes,
   corresponding regression tests and operational documentation in the same
   focused commits. Merge those branches into `main` after review/verification.
2. Add investigations, implementation diaries, acceptance evidence and future
   proposals to `development`. Use the development index to distinguish status
   and dates; do not update historical catalog counts as if they were live.
3. Bring app changes into `development` with selected app commits. When a commit
   also touches branch-specific README/User Guide text, preserve the development
   references during conflict resolution. Do not blanket-merge the app separation
   deletion commit into `development`, since it removes the retained assets.
4. Do not merge `development` wholesale into `main`: its additional tools and
   records would return. For an experiment worth shipping, port only its focused
   runtime/test/operational-documentation changes to a new branch from `main`.
5. Compare shared runtime sources and ordinary tests, and run both the app suite
   and the separate development-tool contract before publishing updates to both
   branches. Branch-specific guides/records are expected to differ.

Keep the existing performance experiment as its own archive. Resuming it needs
a new explicit request and a fresh baseline; branch separation does not resume
or validate those deferred optimizations.

## Verification record

Preparation checks and their actual outcomes are recorded here after the
candidate has been assembled and tested. A prepared branch is not an accepted
release or a completed human/Linux scientific review.
