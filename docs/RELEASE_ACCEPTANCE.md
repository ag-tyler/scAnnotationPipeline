# Release Acceptance

This document defines the portable Milestone 7 release gate. Every automated
check uses committed code/fixtures or deterministic synthetic data generated in
a temporary directory. No named local dataset, private biological resource, or
pre-existing runtime output is required.

## Automated gate

Run from a fresh repository clone after installing the project and test
dependencies:

```bash
Rscript tests/testthat.R
```

The suite covers utility, workflow, integration, regression, recovery, and
golden-output behavior. Tests that need a dataset build it from deterministic
synthetic inputs and isolate all generated files in temporary directories.

## Portable browser baseline

When `shinytest2`, `qs2`, and a Chromium-based browser are available, the normal
test command also runs the browser journey. It can be run by itself with:

```r
testthat::test_file("tests/testthat/test-app-ui-baseline.R")
```

The test constructs a temporary application containing:

- minimal synthetic marker, gene-position, HGNC, and cancer-map resources;
- one standardized 48-cell, 66-gene sample;
- manifest-backed filtered-expression and clustering caches;
- deterministic clustering and DE plots;
- selected decisions and a valid persisted pipeline state.

It then visits dataset selection, dashboard, resolution selection, manual
annotation, and CNA analysis. Screenshot comparison uses a small threshold so
harmless font and antialiasing differences do not cause pixel-perfect failures.
All functional browser assertions run on every supported platform. Screenshot
comparison is additionally enforced when a reviewed baseline exists for that
platform; the repository currently includes the Windows/R 4.5 baseline.
The test does not invoke compute, save, reset, or batch mutations through the
browser. Its app, dataset, logs, state, caches, and results are deleted with the
temporary test directory.

If the browser or browser-test dependency is unavailable, only this browser
test is skipped; all non-browser release tests remain runnable.

## Acceptance scenario map

| Scenario | Primary evidence |
|---|---|
| Modular launch and preserved main screens | `test-app-bootstrap.R`, `test-app-components.R`, `test-app-ui-baseline.R` |
| Strict canonical `sample` configuration and malformed standardized data | `test-03_utils_misc.R`, `test-standardize-general-template.R` |
| Multi-sample standardization plus restart continuity | `test-t23-release-integration.R` |
| First-sample parameters and marker schemas | `test-05_utils_workflow.R`, component tests |
| Unsaved annotation edits, navigation, CNA omission, and notes | `test-app-components.R`, `test-03_utils_misc.R` |
| Persistent status, repeated attempts, append-only logs, and recovery | `test-06_utils_logging.R`, `test-07_utils_state.R`, `test-t23-release-integration.R` |
| Stale/corrupt/partial cache rejection and recovery | `test-04_utils_caching.R`, `test-regression_cna_cache.R`, state reconciliation tests |
| CNA eligibility and numerical edge cases | `test-05_utils_workflow_cna_preflight.R`, `test-m0-cna-characterization.R` |
| Mixed-validity batch, subsets, progress, and retry | `test-m5-cna-batch.R`, `test-05_utils_workflow_cna.R` |
| More than ten clusters, threshold equivalence, and current previews | annotation/CNA utility tests and component tests |
| Legacy state/config/cache behavior | synthetic migration, reconciliation, invalidation, and recovery tests |

## Scope boundary

The automated gate establishes software behavior and reproducibility without
assuming access to any particular biological dataset. A project may separately
perform scientific review on data it is licensed to use, but such a review is
not a repository test and is not required for another user to validate the app.

## Verification record

On 2026-10-21 under Windows and R 4.5.3, `Rscript tests/testthat.R` passed 818
assertions with zero failures, warnings, or skips. This total includes all 21
synthetic Edge assertions and five reviewed screenshot comparisons. No local
dataset or untracked biological resource was accessed.

The F01 follow-up run on 2026-10-21 passed 843 assertions with zero failures
or warnings. One browser-baseline test was skipped because Chromium could not
obtain a local process pipe/port in the restricted test environment; all
non-browser tests, including the new session and stale-state characterizations,
passed.

After the F02 stable-launch policy was added, the same full-suite command passed
854 assertions with zero failures or warnings after correcting the startup
session diagnostic to isolate its reads from reactive state. The browser
baseline was again the only skip for the same restricted-environment Chromium
startup failure.

After F03 navigation and duplicate-action hardening, the full suite passed 894
assertions with zero failures or warnings. Direct Shiny server tests verified
that clustering and DE completion dialogs navigate once and ignore a repeated
event. The browser baseline remained the only restricted-environment skip.
