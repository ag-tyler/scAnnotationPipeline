# App and development branch separation

Prepared on **2026-11-13**. The catalog was committed independently as
`4e357cc` on `chore/repository-cleanup-audit`. Its baseline is `ef12c9a`;
the subsequent portability fixes on local `main` at `dd6d7e3` are preserved
in both prepared versions. The catalog remains a historical inventory.

## Branch roles

| Branch | Purpose |
| --- | --- |
| `main` | Default branch. Only the unused marker-table removal and legacy preparation-template retirement have been published here; the app-focused separation and other cleanup candidates remain unmerged. |
| `chore/app-development-separation` | App-focused candidate `50a91af`, based on `dd6d7e3`; contains the application, tests, operational documentation and supported user tools. |
| `development` | Full application snapshot plus development tools, current/future plans, historical records, catalog and legacy/reference assets. The app source and ordinary regression suite match the candidate. |
| `chore/repository-cleanup-audit` | Original catalog remains pinned at `4e357cc`; the branch tip removes unused marker tables and retired templates, with its index linked to the original snapshot. |
| `chore/prune-unused-marker-tables` | Original deletion-only commit `9631d08`, followed by template retirement `8ddc0b3`; both are based on remote main without unrelated unpublished local main commits. |
| `chore/retire-legacy-preparation-templates` | Focused template-retirement commit `8ddc0b3`, based on remote main `9631d08`. |
| `perf/result-preserving-computation` | Archived experiment originally at `a62b241`; received the two artifact retirements and related guide cleanup described below. Experimental implementation was not changed, merged or resumed. |

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
| `tests/development/test-profile-interactions.R` | Preserved profiler-file contract, run explicitly from the development checkout. |

The lean branch's README/guide link to the development records and tools.
Those links become usable remotely when `development` is published. The cache
guide explicitly requires a development checkout for the manual migration CLI.
The unused marker tables and legacy technology-specific preparation templates
have subsequently been removed from branch tips; their original versions remain
accessible through the historical links in the cleanup records below.

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

## Unused marker-table removal across branches (2026-11-13)

After reviewing the active marker inputs and preservation options, the user
approved removal from every branch tip that still contained these three files:

- [canonical_markers.csv at the original audit commit](https://github.com/ag-tyler/scAnnotationPipeline/blob/4e357cc8d9f4de76ba174bd236f0800881e1e02b/resources/canonical_markers.csv)
- [cancer_type_markers.csv at the original audit commit](https://github.com/ag-tyler/scAnnotationPipeline/blob/4e357cc8d9f4de76ba174bd236f0800881e1e02b/resources/cancer_type_markers.csv)
- [markers_ss.csv at the original audit commit](https://github.com/ag-tyler/scAnnotationPipeline/blob/4e357cc8d9f4de76ba174bd236f0800881e1e02b/resources/markers_ss.csv)

No current app, script, template or test consumer was found, and none was
selected by resource configuration. The files total 1,125,117 working-tree bytes
(about 1.07 MiB). Removal is from current branch trees; no Git history was
rewritten or purged. Earlier audit and development commits retain the contents.

| Branch | Change |
| --- | --- |
| `chore/prune-unused-marker-tables` | `9631d08`, based on remote main `57f9998`: exactly the three file deletions. |
| Remote `main` | Advanced to the same deletion-only commit `9631d08`. The app-focused separation, neutral template and comment cleanup were not merged. |
| Local `main` | Merge `d66f9fe` retains the two original unpublished commits (`dd6d7e3`, `ef12c9a`) and incorporates the removal. Those original commits and this local merge were not published to remote main. |
| `chore/repository-cleanup-audit` | Deletion `6d4eb0f`; index update `88b005a` points to the original audit snapshot. The dated catalog and CSV inventory are unchanged. |
| `perf/result-preserving-computation` | Deletion-only commit `0e89cf7` on the archived experiment. Experimental implementation and original `a62b241` remain unchanged in history. |
| `development` | Deletion `98763d2`, followed by this documentation update. The User Guide no longer says the tables are retained; the development index links to the original audit snapshot. |
| App-focused separation and two earlier app cleanup branches | Already lacked these tables; their branch tips were left unchanged. |

Verification on Windows with R 4.5.3:

- Existing DE/marker, app bootstrap, and preparation/startup tests:
  **70 assertions passed**, zero failures/errors/warnings/skips, using an
  isolated temporary R user cache.
- The real application context loaded all seven configured biological
  resources after deletion. Its datasets path was redirected to an empty
  temporary directory, so no scientific workspace was opened.
- Hash checks preserve the configured cell-type/malignant marker tables,
  housekeeping and mitochondrial lists, cancer map, genomic positions and HGNC
  reference. Runtime code, configuration, tests and scientific fixtures were
  not edited on any affected branch.
- Per-branch diff checks restrict changes to the three deletions and the
  approved documentation updates. Earlier review branches retain their original
  tips, every local branch tip lacks the removed tables, historical source
  links remain resolvable, and the original unpublished main commits remain
  local. No force-push is used.

The full/browser suite was not rerun for deletion of unconsumed files; the
earlier screenshot findings remain as recorded. The local manifest, verification
runner, log and results are in ignored
`artifacts/local-checks/prune-unused-marker-tables/`. No dataset, configured
biological resource or ignored validation artifact was removed or published.

## Legacy preparation-template retirement (2026-11-13)

The user approved retiring the three older technology-specific workflows from
every branch that retained them, with historical versions accessible here:

- [standardize_10x.R at the original audit commit](https://github.com/ag-tyler/scAnnotationPipeline/blob/4e357cc8d9f4de76ba174bd236f0800881e1e02b/templates/standardize_10x.R)
- [standardize_10x.qmd at the original audit commit](https://github.com/ag-tyler/scAnnotationPipeline/blob/4e357cc8d9f4de76ba174bd236f0800881e1e02b/templates/standardize_10x.qmd)
- [standardize_undefined.qmd at the original audit commit](https://github.com/ag-tyler/scAnnotationPipeline/blob/4e357cc8d9f4de76ba174bd236f0800881e1e02b/templates/standardize_undefined.qmd)

No current app or test called these files, and the retained general preparation
workflow does not depend on them. Current READMEs no longer list Quarto as a
requirement for the retired templates. Current User Guides no longer advertise
their availability, list their directory entries, or list Quarto rendering as
an application test-coverage limitation. Historical plans and catalog contents
remain unchanged; their descriptions refer to the versions available then.

| Branch | Change |
| --- | --- |
| `chore/retire-legacy-preparation-templates` | `8ddc0b3`, based on remote main `9631d08`: three retired files plus focused README/User Guide cleanup. |
| Remote `main` | Advanced only to `8ddc0b3`; app separation and the earlier comment/default cleanups remain unmerged. |
| Local `main` | Merge `87f3586` preserves the three pre-existing unpublished commits and incorporates the retirement. No unpublished local commit or local merge was pushed to remote main. |
| `chore/prune-unused-marker-tables` | Fast-forwarded to `8ddc0b3`, retaining the earlier marker-table removal. |
| `chore/repository-cleanup-audit` | Retirement `e4de970`; the dated catalog and CSV inventory remain unchanged and linked through their original snapshot. |
| `perf/result-preserving-computation` | Retirement `650a72c`; only the retired files and related README/User Guide content changed, not experimental implementation. |
| `development` | Retirement `739bd46`, followed by this development-only record and retained-assets update. |
| `chore/app-development-separation` | Documentation-only `d43097e`; templates were already absent. |
| `chore/remove-obsolete-content` | Documentation-only `3ce6498`; templates were already absent. |
| `chore/neutral-template-defaults` | Documentation-only `471b966`; templates were already absent. |

Verification on Windows with R 4.5.3:

- Existing app bootstrap, prepared-input import/startup, and general preparation
  tests: **216 assertions passed**, zero failures/errors/warnings/skips, using
  an isolated temporary R user cache.
- A separate synthetic general-helper run completed staging, strict validation
  and publication after the legacy files were removed.
- Per-branch comparisons preserve `standardize_general.R`,
  `dataset_config_template.yaml`, runtime source, utilities, configuration,
  supported scripts, permanent tests and scientific fixtures exactly as they
  were before this pass. Dataset-specific preparation scripts were not touched.
- Branch-tree checks confirm that all current local/remote tips lack the three
  retired templates, active runtime resource hashes are unchanged, historical
  source links resolve, and current guides have no stale availability claims.
- Original unpublished local main commits remain reachable locally and excluded
  from the dedicated remote main update. No history rewrite or force-push was
  used. The dated catalog and original planning records were not rewritten.

The full/browser suite was not rerun for this external-template/documentation
retirement; prior screenshot findings remain as recorded. Local evidence is in
ignored `artifacts/local-checks/retire-legacy-preparation-templates/`. No dataset,
configured biological resource or ignored validation artifact was removed or
published.

## Local housekeeping and compatibility review (2026-11-13)

The user approved deleting three ignored local files from the shared workspace:

- `Rplots.pdf`: automatically generated R graphics output, 3,448 bytes.
- `tests/testthat/Rplots.pdf`: test-generated graphics output, 3,667 bytes.
- `.vscode/launch.json`: generic Node launcher scaffold, 506 bytes; it did not
  launch this R application.

The three ordinary files were confirmed ignored and inside the workspace before
deletion, and absent afterward. Only these files were removed; their combined
logical size was 7,621 bytes. R can regenerate the PDFs during ordinary plotting.
Ignored files belong to this workspace independently of the selected branch;
their deletion is not represented by a Git commit or propagated to other clones.

The documentation record is maintained on `chore/local-housekeeping`, based on
`development` at `e432d8a`, and fast-forwarded into `development`. Other branch
tips are unchanged. Runtime code, tests, configuration, resources and datasets
were not edited. No regression tests were run for this local/documentation-only
housekeeping; file-state and Git diff checks provide verification.

Compatibility and recovery implementations were reviewed and retained. Current
workspace loading still uses legacy-state inference; configured marker inputs
still use the supported `gene` column alias; precision/location recovery remains
documented and covered by regressions. Age alone does not establish that these
paths are unnecessary. No recovery tool was executed against a dataset.

## Early performance smoke/diagnostic artifact cleanup (2026-11-13)

The user approved deleting exactly six early local run directories under
`artifacts/local-checks/` after reviewing their purpose and retention limits:

| Directory | Files removed | Logical bytes removed |
| --- | ---: | ---: |
| `e00-smoke-01/` | 59 | 2,178,002 |
| `e00-smoke-02/` | 86 | 6,064,945 |
| `e00-smoke-03/` | 108 | 6,696,305 |
| `e00-smoke-04/` | 108 | 6,696,418 |
| `e00-smoke-05/` | 271 | 15,076,291 |
| `e00-diagnostic-01/` | 22 | 315,028 |
| **Total** | **654** | **37,026,989** |

This removes about 35.3 MiB of generated early-run captures, copied sources,
inputs, and diagnostics. All six directories were gitignored and carried the
`Owned disposable performance experiment` marker. Their resolved absolute
paths were checked as immediate children of the intended artifact directory
inside the workspace. The artifact root, deletion targets and descendants were
checked for reparse points/links before recursive deletion. Counts and sizes
matched the approved batch, and all six paths were absent afterward.

All `*-verified/` and `*-final/` directories were retained, including the runs
referenced by the performance plan's final evidence. Root-level logs, summaries,
consolidated evidence, other local review outputs and recent cleanup checks
were retained too. Across deletion, the retained artifact inventory matched
exactly by relative file path, size and modification time: **6,294 files,
3,348,979,707 logical bytes**. This is a metadata comparison, not a new scientific
or performance validation.

The deleted generated contents are not recoverable from Git branches; they
were never tracked or uploaded. The retained final evidence and archived
performance harness remain. No performance experiment was resumed, and neither
the dated catalog nor the historical performance plan was rewritten.

The documentation record is maintained on
`chore/prune-old-performance-smoke-artifacts`, based on `development` at
`38f78fa`, and fast-forwarded into `development`. Only this documentation record
is committed/pushed; ignored-file deletion is local to this workspace. Other
branch tips, application code, configuration, permanent tests and biological
resources are unchanged. No file under the root `datasets/` directory was
inspected or removed. Regression tests were not run for this local artifact
cleanup; containment, ownership, link, file-state and Git diff checks provide
verification.
