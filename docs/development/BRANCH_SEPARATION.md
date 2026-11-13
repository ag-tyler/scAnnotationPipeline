# App and development branch separation

Prepared on **2026-11-13**. The catalog was committed independently as
`4e357cc` on `chore/repository-cleanup-audit`. Its baseline is `ef12c9a`;
the subsequent portability fixes on local `main` at `dd6d7e3` are preserved
in both prepared versions. The catalog remains a historical inventory.

## Branch roles

| Branch | Purpose |
| --- | --- |
| `main` | Existing default branch. It has not been changed by this preparation. After review, the app-focused candidate can be merged here. |
| `chore/app-development-separation` | App-focused candidate `50a91af`, based on `dd6d7e3`; contains the application, tests, operational documentation and supported user tools. |
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

The standalone catalog commit `4e357cc` was pushed to
`origin/chore/repository-cleanup-audit`. The app-focused candidate is `50a91af`.
The two prepared branches preserve the local `main` baseline at `dd6d7e3`;
preparation does not update local or remote `main`.

| Check | Actual result |
| --- | --- |
| Shared runtime and ordinary tests | Exact Git comparison between candidate and development passed for `app.R`, `app/`, `util_scripts/`, `R/`, configuration/dependency metadata, all three retained scripts, both retained templates, `tests/testthat.R`, and all `tests/testthat/` files. Runtime sources and user tools also match pre-separation `main`. |
| Asset retention | All 20 tracked files removed relative to pre-separation `main` exist on `development`. Catalog/record/development-test files are additional development-only assets. |
| App tree | 130 tracked files versus 149 on pre-separation `main`; Git blob content totals 2,003,568 versus 3,742,210 bytes. This measures the checked-out tracked tree; Git history has not been pruned. |
| Static checks | All 110 app-candidate R files parsed; all seven configured local biological resources remained present. Seven app Markdown documents passed 57 local link/heading checks; development-branch link targets were verified in the development Git tree. |
| Development-tool contract | `testthat::test_file("tests/development/test-profile-interactions.R")`: 6 passed, zero failures/errors/warnings/skips. |
| Complete app suite | **4,434 passed, 2 failed out of 4,436 expectations**, zero errors/warnings/skips; 808.9 seconds. Includes browser/layout, scientific/workflow, snapshot/storage, cache portability and reusable-tool tests. |

The full suite ran on Windows with R 4.5.3 and headless Microsoft Edge
157.0.4341.46, using the existing Windows screenshot-worker locale setup.
`UPDATE_UI_BASELINES` was false; the optional greater-than-4-GiB test was not
enabled. An initial vanilla R launch needed an explicit installed Edge path,
and browser process pipes required running the harness outside the sandbox.
Those environment issues were resolved before the complete run above.

The two failures are screenshot comparisons in the baseline navigation journey:
`02-start-menu.png` and `06-clustering-sample-selection.png`. Visual inspection
of the Start Menu comparison shows cache size **13.3 KB** in the current app
versus **12.4 KB** in the stored baseline. No runtime implementation, image,
comparison threshold, or scientific fixture was changed for the separation.

A control replay of the same original browser journey against an untouched Git
archive of `main` at `dd6d7e3` reproduced **the same two screenshot failures**:
37 passed out of 39 expectations, with zero errors/warnings/skips. Both screenshot
comparison scores also matched the candidate's results. The setup functions,
journey, image baselines and thresholds were retained unchanged; other browser
journeys were omitted from this focused control. This establishes existing
baseline drift on `main`, rather than a difference introduced by separation.

Local runners, full logs, result summaries and the two captured candidate
screenshots are retained in ignored `artifacts/local-checks/branch-separation/`.
The control archive contains only tracked main files, and all browser datasets/
resources are generated synthetic fixtures. No local scientific workspace or
ignored resource was deleted or published.

This preparation is **not a green release gate**. Resolving/reviewing screenshot
baseline drift is separate from approving the branch separation. Existing human
and Linux scientific acceptance items remain open.

## Obsolete-content cleanup (2026-11-13)

The first cleanup pass was approved before editing and limited to four files:

- `tests/testthat/helper-source.R`: removed the repeated utility-loading
  explanation while retaining the package-loading explanation and executable code.
- `util_scripts/03_utils_misc.R`: removed the machine-specific `local_config.yaml`
  claim; retained the Windows-reserved-name validation and its explanation.
- `app/context.R`: the missing-resource diagnostic now names the actual
  `config_path`, instead of implying an automatic `local_config.yaml` override.
- `util_scripts/17_utils_prepared_data.R`: describes the existing import/load
  workflows rather than calling them forthcoming.

Commit `382ca34` on `chore/remove-obsolete-content` starts from the app-focused
candidate `50a91af`. It was cherry-picked onto `development` as `d26e3b1`.
The shared app source and ordinary test files match between these two updated
branches. The original separation candidate, `main`, audit branch and archived
performance branch were not changed by this pass. Configuration defaults,
scientific parameters, resource loading and compatibility behavior were retained.

Verification on Windows with R 4.5.3:

- Existing `app-bootstrap`, `p01-prepared-data` and `p04-preparation-ui` tests:
  **145 assertions passed**, zero failures/errors/warnings/skips. The run used an
  isolated temporary R user cache.
- Parsed executable expressions remained identical to the app-focused base in
  all three comment-only files; `app/context.R` also parsed successfully.
- A synthetic configuration with a custom filename produced an error naming
  that file and the missing resources, without creating a dataset directory.
- Git diff checks passed. The full/browser suite was not rerun for this narrow
  comment/diagnostic change; the earlier screenshot findings remain as recorded.

The local runner, log and result summary are in ignored
`artifacts/local-checks/obsolete-content-cleanup/`. The catalog remains a dated
pre-cleanup snapshot; no dataset or biological resource was edited.

## Neutral template defaults (2026-11-13)

The second cleanup pass was approved before editing and changed the shared
dataset template and its User Guide explanation:

- `project_info.dataset_id` is blank instead of `Werba2023_Pancreas`.
- `project_info.technology` is blank instead of `10x`.
- Comments explain import population and manual preparation metadata.
- The unused `raw_files: type: 10x` default block and its heading were removed.
- The guide explains that import fills metadata from the workspace name and
  `Samples.csv`, while optional manual preparation uses explicitly supplied
  project metadata in the copied configuration.

Commit `407b93a` on `chore/neutral-template-defaults` starts from the previous
cleanup branch at `382ca34`, retaining that work. It was cherry-picked onto
`development` as `5892cfb`. A separate development-only record commit documents
the results here. Earlier review branches, `main`, the audit branch and the
performance archive remain unchanged by this pass.

Verification on Windows with R 4.5.3:

- Existing `p03-dataset-import` and `standardize-general-template` tests:
  **175 assertions passed**, zero failures/errors/warnings/skips, using an
  isolated temporary R user cache.
- Parsed YAML comparison confirms that only the two project metadata defaults
  and the removed `raw_files` field differ. Scientific parameters, marker
  thresholds, standardized filenames and optional source fields are identical.
- Synthetic imports supplied the new workspace ID correctly and handled
  uniform, mixed and unknown technologies as before. A separate legacy-template
  import confirmed that the unchanged import code still overwrites historical
  metadata and removes an older template's `raw_files` field.
- An adapted copy of the neutral template, with explicit manual project
  metadata and no `raw_files`, completed the preparation helper's staging,
  strict validation and publication lifecycle successfully.
- Runtime code and permanent tests were not edited. Shared runtime, templates
  and ordinary tests match between the new cleanup branch and development.
  Git diff checks passed.

The full/browser suite was not rerun for this template/documentation change;
earlier screenshot findings remain as recorded. Local verification output is
in ignored `artifacts/local-checks/neutral-template-defaults/`. No existing
dataset configuration, scientific workspace or biological resource was edited.
