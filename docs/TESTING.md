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

The full app suite recorded on **2026-11-13** at integration commit `be1d546`
ran on Windows with R 4.5.3 and headless Edge 157.0.4341.46: **4,434 passed and
2 failed out of 4,436 expectations**, with zero errors, warnings, or skips
(674.05 seconds). The optional greater-than-4-GiB test and screenshot updates
were disabled.

The two known failures are the `02-start-menu.png` and
`06-clustering-sample-selection.png` comparisons in the baseline navigation
journey. Their failure messages and comparison scores match the earlier
separation verification. This is not a fully green release gate. Screenshot
baseline review and outstanding human/Linux acceptance remain open; do not
update images or thresholds merely to suppress these failures.

This is a dated result, not a claim about every subsequent checkout. The
[integration verification record](https://github.com/ag-tyler/scAnnotationPipeline/blob/fe23fca/docs/development/BRANCH_SEPARATION.md#final-app-focused-main-integration-and-finder-metadata-ignore-2026-11-13)
preserves its context and evidence. Documentation-only updates do not constitute
a new app-suite run.

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
