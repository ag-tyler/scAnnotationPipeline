# Testing the application

Run the app regression suite from the repository root after installing the R
and test dependencies listed in the README:

```sh
Rscript tests/testthat.R
```

Alternatively, use `devtools::test()` from R. The project sources utility files
rather than requiring an installed package namespace. The two test helpers load
the current implementation and build deterministic synthetic inputs. No local
scientific dataset or private biological resource is required by the tests.

The suite covers import, clustering, DE, annotation, CNA, caches, relocation,
state/log recovery, exports, snapshots, storage, and the supported external
preparation/checkpoint tools. Ticket prefixes identify permanent regressions.

## Browser checks

Install `shinytest2` and configure a Chromium-based browser to run the browser
journeys included in the normal suite. To run the primary journeys separately:

```r
testthat::test_file("tests/testthat/test-app-ui-baseline.R")
```

Browser journeys construct temporary apps with synthetic resources, inputs,
state and caches. Saves, computation, reset and storage actions remain confined
to those disposable workspaces. Additional snapshot tests exercise desktop and
narrow modal layouts. A missing browser/dependency can cause browser tests to
skip; report those skips rather than claiming full browser acceptance.

Reviewed screenshots are committed under
`tests/testthat/fixtures/ui-baseline/windows-4.5/`. Functional assertions run
on other platforms too; screenshot comparisons require a reviewed platform
baseline. Do not enable `UPDATE_UI_BASELINES` during ordinary verification.
Baseline changes require inspecting the images and reviewing their Git diff.

The optional greater-than-4-GiB snapshot regression is enabled explicitly with
`RUN_F17_LARGE_TESTS=true`; ordinary verification uses smaller synthetic files.

## Recorded verification status

The full run on **2026-11-20** verified the shared app at `main` commit `435472e`
and `development` commit `fc7fb6a`, on Windows with R 4.5.3 and headless Edge
157.0.4341.60:

| Suite | Passed | Failures/errors/warnings/skips |
| --- | --- | --- |
| Full app suite, including browser journeys and screenshots | 4,451 | 0 / 0 / 0 / 0 |
| Separate development-tool contracts | 62 | 0 / 0 / 0 / 0 |
| Total | 4,513 | 0 / 0 / 0 / 0 |

The app suite took 751.67 seconds; the complete run took 777 seconds. Automatic
screenshot updates and the optional greater-than-4-GiB stress test were disabled.
The local log, result summaries, and environment record are retained in ignored
`artifacts/local-checks/full-suite-2026-11-20/`.

The earlier November 13 run had two screenshot failures, `02-start-menu.png` and
`06-clustering-sample-selection.png`. Review found only the synthetic cache-size
label changed from 12.4 KB to 13.3 KB, including the dashboard behind the modal.
The user approved those two image updates on November 20; test code and comparison
thresholds were unchanged. A focused browser rerun passed 39 assertions, followed
by the clean full run above. The
[original integration record](https://github.com/ag-tyler/scAnnotationPipeline/blob/fe23fca/docs/development/BRANCH_SEPARATION.md#final-app-focused-main-integration-and-finder-metadata-ignore-2026-11-13)
preserves the historical failures.

This is dated automated verification, not a claim about every later checkout or
completion of all human, biological, or broader platform acceptance. Application
code, tests, and fixtures are unchanged for the 1.0.0 release; version and
documentation updates do not constitute another app-suite run.

**WSL acceptance: closed on 2026-11-20 by user decision** following workstation
use. Reopen this point if an issue is reported. Detailed dataset outcomes are
not required for this closure. This acceptance is separate from the Windows
automated coverage recorded above.

## Golden outputs and evidence

`tests/testthat/fixtures/compute_cna_golden.rds` is the deliberately committed
scientific baseline. The manual generator in the same directory is for intended,
reviewed changes to scientific behavior. Do not regenerate it merely to make a
failing test pass.

Keep local runners, logs, screenshots and saved test summaries in ignored
`artifacts/local-checks/`, and keep `datasets/` for scientific workspaces. Record
the source commit, R/platform/browser versions, failures, warnings, skips and
any manual checks alongside test results. Synthetic regression checks do not
establish biological correctness or close outstanding human acceptance.

Development-only profiling contracts, dated release acceptance, investigations
and future plans are maintained on the
[`development` branch](https://github.com/ag-tyler/scAnnotationPipeline/tree/development/docs/development).
That branch's documentation index gives the separate development-tool test
command. App feature branches should start from `main`; the entire development
records branch is not intended for merging into `main`.
