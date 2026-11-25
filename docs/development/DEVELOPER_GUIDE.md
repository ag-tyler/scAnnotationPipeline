# Developing scAnnotationPipeline

This is the current starting point for extending or fixing the app. It lives on
`development`; both branch READMEs link here. The [development index](README.md)
separates current references, proposed work, and dated evidence. Historical plans
describe their original scope and do not by themselves authorize implementation.

## Start a change

Create app feature and fix branches from the latest `main`:

```sh
git switch main
git pull --ff-only origin main
git switch -c feature/your-change
```

Follow the [root README](../../README.md#requirements) for the R version and
dependencies. The app runs from the repository root and is not installed as a
conventional R package. For interactive work, launch it with:

```r
source("scripts/run_app.R")
```

This disables Shiny autoreload, avoiding restarts caused by the app's own state,
cache, log, and result writes. Direct IDE **Run App** launches need deliberate
autoreload configuration. Restart the app to load changed biological resources.

App startup requires the separately provisioned
[biological resources](../USER_GUIDE.md#resource-files). Automated tests instead
create synthetic resources and disposable workspaces; they do not require a
local scientific dataset. For manual work, use a disposable dataset copy and
keep original prepared inputs and completed analysis workspaces unchanged.

## Find the implementation

| Change | Starting points |
| --- | --- |
| Panel layout and controls | [`app/ui/`](../../app/ui/), composed in [`app_ui.R`](../../app/ui/app_ui.R) |
| Reactive handlers and saved actions | [`app/server/`](../../app/server/), registered in [`app_server.R`](../../app/server/app_server.R); CNA has its own stage composition |
| Per-session mutable values and action guards | [`app/state.R`](../../app/state.R), especially `create_app_state()` and the existing confirmation/action helpers |
| Startup configuration and shared resources | [`app/context.R`](../../app/context.R); keep this context separate from mutable session state |
| Calculations and reusable workflows | [`util_scripts/02_utils_annotation.R`](../../util_scripts/02_utils_annotation.R) and [`05_utils_workflow.R`](../../util_scripts/05_utils_workflow.R) |
| Prepared-data import and structural checks | [`18_utils_dataset_import.R`](../../util_scripts/18_utils_dataset_import.R) and [`17_utils_prepared_data.R`](../../util_scripts/17_utils_prepared_data.R) |
| Optional external preparation helpers | [`templates/standardize_general.R`](../../templates/standardize_general.R) and [`08_utils_standardization.R`](../../util_scripts/08_utils_standardization.R) |
| Defaults and configured paths | [`general_config.yaml`](../../general_config.yaml) and [`dataset_config_template.yaml`](../../templates/dataset_config_template.yaml) |
| Cache integrity and dependencies | [`04_utils_caching.R`](../../util_scripts/04_utils_caching.R), with stage dependency builders in `05_utils_workflow.R` |
| Workflow status and events | [`07_utils_state.R`](../../util_scripts/07_utils_state.R) and [`06_utils_logging.R`](../../util_scripts/06_utils_logging.R) |
| CNA export, storage lifecycle, and snapshots | [`10_utils_cna_export.R`](../../util_scripts/10_utils_cna_export.R), [`11_utils_storage.R`](../../util_scripts/11_utils_storage.R), and [`14_utils_snapshots.R`](../../util_scripts/14_utils_snapshots.R) |

## Prepared cells input contract

The app requires only `cell_name` and `sample` in each sample's cells file.
Keep cells in matrix-column order; identifiers are unique across the dataset
and each `sample` matches its directory and `Samples.csv` row. The full
[column reference](../USER_GUIDE.md#cellscsv) distinguishes optional metadata
from fields created during annotation and CNA. Sample-table headers remain
unchanged.

Do not add helper-only metadata requirements to app import or analysis code.
The optional standardization and downsampling helpers retain their eight-column
schema. App QC computes detected-gene counts from the matrix; `complexity` is
optional but participates in cache fingerprints when present. Preserve optional
columns when loading/saving, and initialize missing annotation columns in a
local table before assigning it to Shiny reactive state. Regressions for the
minimal input and annotation save live in `test-01_utils_io.R` and
`test-f15-r03-annotation-preview.R`.

## Add or extend a component

Follow an adjacent stage's structure before introducing another abstraction.
Keep scientific calculations in utility functions and UI/event wiring in the
app components so calculations can be tested without starting a browser.

For a new panel or handler:

1. Add its UI/server file and function, using stable input/output IDs.
2. Register new component files in the ordered `app_component_files` list in
   [`app.R`](../../app.R), before any component that depends on them. Utilities
   are sourced separately from all `.R` files in `util_scripts/`, in filename
   order. Shiny's implicit `R/` autoload is intentionally disabled.
3. Wire the panel into `build_app_ui()` and the handler into `build_app_server()`
   or the relevant existing stage composition. Server registration functions
   receive `input`, `output`, `session`, `state`, and `context`.
4. Initialize new session values in `create_app_state()`. Follow the existing
   dataset-switch/reset behavior; old sample indices, previews, or confirmations
   must not act on a newly loaded dataset.
5. Add a focused regression for the behavior, including persistence or restart
   where the change saves user decisions. Update the user-facing instructions.

## Preserve results and compatibility

- Keep plot scales, slider ranges, and other display choices separate from
  classification and scientific calculations. Restore saved numeric values
  without silently rounding or clamping them.
- When a saved decision or scientific parameter changes, check both workflow
  staleness and cache invalidation. Add new result-affecting inputs to the
  appropriate dependency fingerprint; file existence alone does not prove reuse
  is safe. Use existing cache APIs rather than deleting individual files manually.
- Persist workflow state through the existing transition and atomic-save helpers.
  Retain locks, revision checks, recoverable backups, and interrupted-work guards.
  Treat archived workspaces as read-only until explicitly reopened.
- Record completed actions, failures, and saved decisions through the existing
  event helpers. Keep logs distinct from current workflow state, and avoid large
  payloads or unnecessary absolute paths in event parameters.
- Account for existing configuration and workspace formats. Use established
  validation/recovery paths and give actionable errors; do not silently rewrite
  scientific inputs or accept an unverifiable cache.

The detailed contracts are [Pipeline State](../PIPELINE_STATE.md),
[Cache Validity](../CACHE_VALIDITY.md), and
[Pipeline Logging](../PIPELINE_LOGGING.md). Changes to numerical behavior need
explicit review and result comparisons; do not regenerate golden outputs just
to make a regression pass.

## Verify the change

Start with the relevant utility or workflow tests in `tests/testthat/`. For
example, from the repository root:

```r
testthat::test_dir("tests/testthat", filter = "^c08-cna-controls$")
```

This loads the existing source and fixture helpers. Use `shiny::testServer()`
for reactive behavior and the synthetic browser fixtures for navigation,
save/reload, or layout changes. Permanent regressions belong in `tests/testthat/`;
temporary runners, logs, screenshots, and summaries belong in ignored
`artifacts/local-checks/`. Do not use `datasets/` as a test-artifact directory.

Run the full app suite after runtime changes before finalizing the candidate:

```sh
Rscript tests/testthat.R
```

This entry point checks dependencies, browser startup, and host/worker UTF-8
before running tests. Run `Rscript scripts/check_test_setup.R` explicitly before
direct `devtools`/`testthat` calls. The bootstrap fixture is synthetic too; verify
fresh ZIP checkouts without private resources rather than relying on a configured
developer workstation. See the [setup diagnostics](../TESTING.md#check-the-setup-first).

The [Testing guide](../TESTING.md) covers browser setup, screenshot baselines,
the optional large-file test, evidence, and the latest dated verification.
Keep screenshot updates disabled during verification. For an intentional visual
change, inspect the actual images first, limit `UPDATE_UI_BASELINE_FILES` to the
approved comma-separated filenames when using `UPDATE_UI_BASELINES=true`, review
the image diff, and rerun comparisons with updates disabled. Preserve comparison
thresholds unless an independently reviewed change requires otherwise.

The [development script reference](SCRIPTS.md) describes each entry point,
its arguments, output, and workspace effects.

Development tools have separate contracts on `development`:

```r
testthat::test_file("tests/development/test-profile-interactions.R")
testthat::test_file("tests/development/test-e00-performance-harness.R")
```

The [E00 harness](../../scripts/performance/README.md) retains its original
baseline and experiment evidence. It does not establish a current app performance
baseline. E01-E08 optimization work remains deferred. The interaction profiler's
loaders can perform recovery writes; use a disposable copy when profiling.

Record tested commits, R/OS/browser versions, counts, failures, warnings, skips,
and manual observations. Separate automated verification from biological review
and human/platform acceptance; a synthetic pass does not close those checks.

## Review, publish, and maintain the branches

1. Keep runtime changes, meaningful regressions, and operational documentation
   together in focused app commits. Review and merge the feature/fix branch into
   `main` after verification.
2. Bring the relevant app commits into `development`, normally with cherry-picks.
   Preserve development-specific README/User Guide links when resolving conflicts.
   Do not merge `development` wholesale into `main`: that would bring development
   tools and records into the app distribution.
3. For an experiment worth shipping, port its reviewed runtime, test, and user
   documentation changes to a new branch from current `main`. Retaining an
   experiment on `development` does not mean it is enabled in the app.
4. Compare shared runtime sources, ordinary tests, supported user scripts, and
   configuration between the maintained branches. Extra development tools and
   records are expected to differ. Run the relevant development contracts when
   changing those tools, and verify the final app candidate before publishing.
5. Push the maintained branches after review and verification. Delete a finished
   feature branch locally and remotely only after confirming its intended work
   is retained. `main` and `development` are the long-lived branches.

Keep this guide and operational references current. Add dated investigations and
acceptance evidence to `development`; identify proposals as proposals. Preserve
historical results rather than rewriting them as current acceptance. The
[branch-separation record](BRANCH_SEPARATION.md) explains earlier decisions and
retired branches; it is not the current maintenance checklist.
