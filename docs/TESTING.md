# Testing the application

## Check the setup first

Extract the GitHub ZIP or clone the repository, then open an R session or terminal
in the **application root**: the directory containing `app.R`, `DESCRIPTION`,
`general_config.yaml`, and `tests/`. A ZIP directory may be named
`scAnnotationPipeline-main`; its name does not matter. No `.git` directory is
required for the ordinary app suite.

Install the R and test dependencies in the [README](../README.md#requirements),
including the custom `matkot` package. Then run:

```sh
Rscript scripts/check_test_setup.R
```

The read-only preflight checks the root, required R/package versions, host UTF-8,
an independent R worker's UTF-8 startup, browser discovery, and an actual headless
browser connection. Errors name the missing dependency or setting before a long
test run starts. Nothing is installed automatically and no locale settings,
scientific resources, or datasets are changed.

**Biological resources are required to run the real app, but not the tests.**
Bootstrap and browser tests create disposable apps with synthetic resources and
inputs. The preflight reports how many of the seven configured biological files
are available as information; missing private files do not block synthetic tests.
See the [resource specification](USER_GUIDE.md#resource-files) before launching
the real app. You do not need to launch it before testing a fresh ZIP checkout.

For diagnostics limited to non-browser testing, use
`Rscript scripts/check_test_setup.R --no-browser`. That does not establish browser
acceptance; the ordinary full-suite command checks the browser too.

## Run the tests

From the application root:

```sh
Rscript tests/testthat.R
```

This entry point runs the preflight automatically before the suite. To use R:

```r
source("tests/testthat.R", encoding = "UTF-8")
```

Alternatively, run the preflight explicitly before using `devtools::test()` or
direct `testthat` commands, which bypass the entry point's setup check:

```r
source("scripts/check_test_setup.R", encoding = "UTF-8")
check_test_setup()
devtools::test()
```

The project sources utility files
rather than requiring an installed package namespace. Shared test helpers load
the current implementation, build deterministic inputs, and assemble isolated
synthetic apps. No local
scientific dataset or private biological resource is required by the tests.

The suite covers import, clustering, DE, annotation, CNA, caches, relocation,
state/log recovery, exports, snapshots, storage, and the supported external
preparation/checkpoint tools. Ticket prefixes identify permanent regressions.

## Browser checks

Install `shinytest2` and its `chromote` dependency, and provide Chrome, Chromium,
or Edge. Automatic discovery may work; inspect `chromote::find_chrome()` or the
preflight output. If needed, set `CHROMOTE_CHROME` to the executable's full path.
For example, in the **same PowerShell session** that starts R:

```powershell
$env:CHROMOTE_CHROME = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
Rscript scripts/check_test_setup.R
```

On Linux/WSL, a typical example is
`export CHROMOTE_CHROME=/usr/bin/chromium`; use the actual installed path. In an
existing R session, `Sys.setenv(CHROMOTE_CHROME = "...")` affects that session and
its children, not a separate terminal. The preflight also checks whether the
browser can start, so a discovered path alone is not sufficient.

After the preflight, run the primary journeys separately with:

```r
testthat::test_dir("tests/testthat", filter = "^app-ui-baseline$")
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

## UTF-8 and child-process settings

Check `Sys.getlocale("LC_CTYPE")` and `l10n_info()[["UTF-8"]]`. Browser apps run in
separate R processes, so the preflight checks an independent worker as well as
the parent. Changing the parent's locale alone does not fix incompatible inherited
environment variables. The diagnostic prints inherited `LC_*`, `LANG`, and
`LANGUAGE` settings and reports worker startup warnings.

On Windows, use a supported Windows UTF-8 locale. Remove incompatible Unix locale
overrides from the environment or startup files and restart R. For example, in
PowerShell before starting R:

```powershell
Remove-Item Env:LC_ALL, Env:LC_CTYPE, Env:LANG -ErrorAction SilentlyContinue
$env:LC_CTYPE = 'English_United States.utf8'
Rscript scripts/check_test_setup.R
```

Use an installed locale appropriate to the machine. In an existing Windows R
session, `Sys.setlocale("LC_CTYPE", "English_United States.utf8")` changes the
parent; `Sys.setenv(LC_CTYPE = Sys.getlocale("LC_CTYPE"))` passes that choice to
children once incompatible `LC_ALL` overrides have been removed. Do not set the
Linux `C.UTF-8` name unconditionally on Windows.

On Linux/WSL, inspect `locale -a` and choose an installed UTF-8 locale. Where
`C.UTF-8` is available, an example is:

```sh
LC_ALL=C.UTF-8 Rscript scripts/check_test_setup.R
LC_ALL=C.UTF-8 Rscript tests/testthat.R
```

App utility/component files are parsed explicitly as UTF-8, preserving Unicode
UI text even under a `C` character locale. The suite still requires a UTF-8 test
environment for portable subprocess, path, and screenshot behavior. Dashboard
browser tests assert the intended em dash as text before comparing screenshots;
a matching image alone is not proof that its characters are correct.

## Recorded verification status

### 1.0.1 release gate

The app-focused 1.0.1 candidate passed **4,488 app assertions** on
2026-11-20, with **zero failures, errors, warnings, or skips**. The full ordinary
suite ran through `tests/testthat.R` in a disposable ZIP-equivalent copy,
without Git metadata, biological resource files, scientific datasets, or
development-only tools. Dependency, host/worker UTF-8, and actual browser
startup checks passed before the suite. The run used Windows, R 4.5.3, and
headless Edge 157.0.4341.60, including functional browser journeys and
screenshot comparisons (801.63 seconds).

The gate includes unsorted-marker selection regressions, UTF-8 bootstrap and
dashboard text checks, and fresh-ZIP test preflight. Screenshot updates were
disabled; the promoted start-menu baseline is the reviewed UTF-8 correction.
The optional greater-than-4-GiB stress test was not enabled. This run does not
repeat the closed WSL dataset acceptance or claim validation of every
biological dataset.

Local logs, source hashes, environment details, and assertion summaries are
retained in ignored `artifacts/local-checks/promote-1.0.1/`. The app fixes,
ordinary tests, preflight, user documentation, and version metadata are
promoted to `main`; development-only assets stay on `development`. The
original `v1.0.0` tag remains unchanged.

### 1.0.0 release gate

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

### Development follow-up: fresh-ZIP setup and UTF-8

The development follow-up on **2026-11-20** passed **4,466 app assertions** and
**62 separate development-tool assertions**: **4,528 total**, with zero failures,
errors, warnings, or skips (732.75 seconds, including development-tool checks).
The app suite ran through `tests/testthat.R`, including its automatic preflight,
in a disposable ZIP-equivalent copy with **no `.git` directory, no private
biological resources, and no scientific datasets**. The preflight reported 0/7
app resource files present and successfully checked a separate R worker and
headless Edge. Development-only E00 tests ran separately from the Git checkout
because their historical baseline requires Git history.

This run used Windows R 4.5.3 and Edge 157.0.4341.60 with normal supported UTF-8
settings, without the old Windows-incompatible `LC_ALL=C.UTF-8` override.
Screenshot updates and the optional greater-than-4-GiB stress test were disabled.
An independent `C`-locale bootstrap regression and a browser text assertion
verify that the dashboard separator is U+2014 before screenshot comparison.
The corrected `02-start-menu.png` was visually reviewed; the other five baseline
images were byte-for-byte unchanged. Comparison thresholds were not changed.

The local snapshot manifest, log, and result summaries are retained under ignored
`artifacts/local-checks/test-preflight-dev/`. This was the development verification
before promotion to `main` in 1.0.1; the original `v1.0.0` tag remains unchanged.

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
