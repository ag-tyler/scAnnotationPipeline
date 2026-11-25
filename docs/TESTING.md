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

Configuration regressions also cover custom filenames without matrix-state
checks during creation/loading, template settings and saved-workspace authority,
optional source metadata, and legacy technology fields. Browser checks exercise
the collapsed filename/source inputs and their keyboard/narrow-screen behavior. Plot
checks cover minimum-marker shading/captions and preservation of existing images;
standalone cache-reader tests check restored classes/values and unchanged files.

On `development`, run the separate development-tool contracts as well:

```r
testthat::test_file("tests/development/test-profile-interactions.R")
testthat::test_file("tests/development/test-e00-performance-harness.R")
```

The E00 contract uses synthetic cache workers and a pinned historical Git
baseline. It requires a checkout with that history; the ordinary application
suite also supports ZIP downloads. See the
[development-script reference](https://github.com/ag-tyler/scAnnotationPipeline/blob/development/docs/development/SCRIPTS.md) for tool usage and effects.
Automated verification does not close the dataset plan's manual acceptance
checks; record those separately after human review.

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

### 1.1.2 reduced cells metadata and annotation initialization — 2026-11-25

Fixed the loader warning when `cell_type` is absent and reproduced the exact
manual annotation failure `i (20) is outside the range of items [1,3]` using
cells supplied with only `cell_name` and `sample`. The annotation server now
prepares missing labels in a local copy before storing the completed table in
Shiny's reactive state.

Focused verification passed **197 assertions across 21 tests**, with zero
failures, errors, test warnings, or skips:

```r
testthat::test_dir("tests/testthat", filter =
  "^(01_utils_io|05_utils_workflow|f05-annotation-recovery|f15-r03-annotation-preview)$")
```

New regressions verify warning-free two-column loading, numeric-looking IDs,
preserved row order and input bytes, and optional pre-CNA labels without an
initial `cell_type`. The Shiny server test uses the real annotation setup and
clustered cache, initializes missing labels, assigns a cell type, and saves
`cell_type` and `cell_type_pre_cna` without adding unused metadata columns.
Existing DE, annotation recovery, preview, and save tests also passed.

These focused checks are the verification basis for 1.1.2. No full suite,
browser journey, or complete two-column CNA pipeline was run, and no new manual
acceptance is claimed. Only version metadata and release/input documentation
changed after the passing test run.

### 1.1.1 prepared-input dimension checks — 2026-11-25

Creation and loading now compare gene entries with matrix rows and cell metadata
data rows with matrix columns for every sample. Matrix reads stop after the
Matrix Market dimension header; metadata is counted without loading full cell
tables. Mismatches report the sample, file, and both counts. Unreadable dimension
headers/counts are reported rather than silently skipping the comparison.
Expression-state/value checks, identifier checks, and comparisons against
`Samples.csv.n_cells` were not added.

Focused verification passed **674 assertions across 53 tests**, with zero
failures, errors, warnings, or skips (64.17 seconds):

```r
testthat::test_dir("tests/testthat", filter =
  "^(p01-prepared-data|p03-dataset-import|p04-preparation-ui|c01-dataset-transitions)$")
```

New coverage includes mismatches across samples and both dimensions in one
sample, custom filenames, header-only cell CSVs, quoted multiline cell fields,
coordinate/array matrix headers, and reporting unreadable dimension headers.
Creation rejects mismatches before copying; copied-data dimension failures roll
back staging; existing dataset loads are blocked with the aggregate report.
Matching datasets, original-file hashes, and the existing annotation/archived
file-review behavior remain covered. Fixtures with an unreadable matrix body
but valid dimensions demonstrate that matrix values are not parsed. Separate
counting smoke checks passed for CRLF files without final newlines.

Logs/results are retained in ignored
`artifacts/local-checks/prepared-dimensions-2026-11-25/`. No full suite or browser
journeys were rerun. These focused checks are the verification basis for the
1.1.1 patch release. Only version metadata and release documentation changed
after testing. The completed 1.1.0 manual acceptance below describes the
preceding release; no new manual acceptance is claimed for 1.1.1.

### 1.1.0 acceptance complete — 2026-11-25

**Automated and manual verification are complete for this release candidate.**
The user reported: "I finished the manual testing. All seems to work."
This closes the dataset-configuration plan's DC06 manual acceptance on
2026-11-25, including the final annotation-save fix and removal of the duplicate
plot reminder. Manual acceptance is user-reported; the agent did not repeat it.

| Verification phase | Result |
| --- | --- |
| Full app run plus reviewed browser-baseline rerun | 4,860 verified app assertions; no unresolved failures/errors/warnings/skips |
| Separate development-tool contracts | 62 assertions passed; zero failures/errors/warnings/skips |
| Later annotation column-type fix | 226 focused assertions passed; read-only reproduction verified all 1,500 Test labels |
| Later duplicate-reminder removal | 226 focused assertions passed; UI syntax checked; original reviewed baseline restored |
| Final manual acceptance | Completed by the user; no failures reported |

Counts are recorded per phase and must not be added as unique coverage. The
initial full run had one intentional screenshot mismatch, resolved by review
and the successful browser-file rerun. The later type fix and UI simplification
were verified with focused checks, as detailed below. The user explicitly stated
that "another full test suite is not necessary" for those two changes. This
release uses that accepted verification sequence; no additional full run or
browser journey was performed after the two follow-ups. The optional
greater-than-4-GiB stress test was not enabled.

Version metadata and release documentation were then prepared as **1.1.0**.
The app-focused main candidate is prepared separately from development-only
assets. This acceptance record does not imply that `main` was updated, tagged,
or published; see the release preparation record on `development`.

### Plot explanation shown once — 2026-11-25

Removed the separate marker-count reminder below the Manual Annotation score
image at the user's request. The explanation in generated plot captions remains.
Restored the original reviewed `04-manual-annotation.png` baseline without the
extra UI paragraph; its archived copy was verified against the committed Git
blob before replacement. No scientific dataset or saved plot was changed.

Focused checks passed **226 assertions across 21 tests** (47 score-plot/DE and
179 annotation/transition assertions), with zero failures, errors, warnings, or
skips. The annotation UI also passed a syntax check. Only these files were run:

```r
testthat::test_dir("tests/testthat", filter = "^(02_utils_annotation_de|c01-dataset-transitions)$")
```

Logs and results are in ignored
`artifacts/local-checks/plot-caption-only-2026-11-25/`. The full suite and browser
journeys were not rerun for this presentation change; earlier browser evidence
below describes the preceding UI.

### Manual annotation blank-column fix — 2026-11-25

This follow-up fixes saving text annotations into an existing all-blank
`cell_type_pre_cna` column, which CSV inference previously loaded as logical.
`load_cells()` now declares the optional column as character when present;
manual save also converts an existing in-memory column before the update join.
Absent columns remain optional, and unrelated metadata keeps its original types.

**Focused verification only, as requested by the user:**

| Test file | Passed assertions | Failures / errors / warnings / skips |
| --- | --- | --- |
| `test-01_utils_io.R` | 43 | 0 / 0 / 0 / 0 |
| `test-c01-dataset-transitions.R` | 183 | 0 / 0 / 0 / 0 |
| Total | 226 | 0 / 0 / 0 / 0 |

The loader cases cover absent, blank, populated, numeric-looking, and
logical-looking labels without changing source files. Server regressions invoke
the real save handler for blank/absent/populated columns and a table already
loaded with a logical column. They verify CSV/cache agreement, joins by cell ID
with reordered analyzed cells, preservation of excluded cells and other metadata,
and repeated saves without warnings.

Commands from the repository root, with the Windows UTF-8 settings above:

```r
testthat::test_dir("tests/testthat", filter = "^(01_utils_io|c01-dataset-transitions)$")
testthat::test_dir("tests/testthat", filter = "^c01-dataset-transitions$")
```

The first run passed the loader file but exposed a setup assertion in the new
already-loaded-logical scenario: assigning scalar `NA` had retained the existing
character type. The fixture was corrected to use inferred CSV loading to recreate
the old in-memory state, and only the affected server test file was rerun. The
table above combines that successful rerun with the passing loader file.

A separate read-only reproduction using `Test`'s CSV and resolution-0.5 cache
updated all 1,500 pre-CNA labels correctly in memory, with zero warnings and
unchanged source hashes. No real dataset was saved or repaired automatically.
Restart the app, reopen the dataset, and save annotations again to populate a
previously affected CSV column.

Local logs/results are retained in ignored
`artifacts/local-checks/annotation-save-types-2026-11-25/` and
`artifacts/local-checks/annotation-save-types-2026-11-25-retry/`.
The full app suite, browser journeys, and development-tool contracts were not
rerun for this fix. Their earlier results below describe the preceding source.

### Development configuration and annotation changes — 2026-11-25

Verified the `development` working tree based on commit `6d5e626`, including
uncommitted DC01–DC05/DC08 changes and the creation-dialog filename inputs, on
Windows 11 with R 4.5.3 and headless Edge 158.0.4370.33. Dependency, host/worker
UTF-8, and actual browser startup checks passed. Tests used disposable synthetic
workspaces rather than scientific datasets.

| Run | Passed assertions | Failures | Errors / warnings / skips |
| --- | --- | --- | --- |
| Full app suite through `tests/testthat.R` | 4,859 | 1 | 0 / 0 / 0 |
| Separate development-tool contracts | 62 | 0 | 0 / 0 / 0 |
| Browser-file rerun after reviewed baseline correction | 700 | 0 | 0 / 0 / 0 |

The sole initial failure was the expected addition of the marker-count
explanation below the Cluster Score Boxplot. Visual and pixel review confirmed
that `04-manual-annotation.png` changed only in that explanation area; the other
five screenshots were byte-for-byte identical. Only that baseline was replaced.
The entire `test-app-ui-baseline.R` file then passed against fresh screenshots
with automatic updates disabled and the comparison threshold unchanged at 5.
All six fresh screenshots matched their baselines byte-for-byte.

Replacing the original browser-file results with the successful rerun gives
**4,860 verified app assertions across 421 tests**, plus **62 development-tool
assertions across 8 tests**: **4,922 assertions**, with no unresolved failures,
errors, warnings, or skips. This combines the full run and the affected-file
rerun; it does not claim a second clean invocation of the entire app suite or
double-count repeated browser assertions. No runtime or test code changed
between runs; source hashes differ only for the reviewed screenshot baseline,
excluding ignored generated `Rplots.pdf` files.

The full app run took 701.67 seconds, development contracts 19.28 seconds, and
the browser rerun 354.10 seconds. Commands, after the process-local Windows
UTF-8 setup described above, were:

```r
source("tests/testthat.R", encoding = "UTF-8")
testthat::test_dir("tests/development")
testthat::test_dir("tests/testthat", filter = "^app-ui-baseline$")
```

The filename follow-up includes 76 browser-layout assertions, 26 assertions for
edited names through validation retry/reload with unchanged template/source
bytes, 9 assertions for invalid overrides, and 7 for prefilled disclosure layout.
These are included in the app totals, not additional counts.

Logs, source hashes, environment details, screenshots, and raw/combined result
summaries are retained in ignored
`artifacts/local-checks/full-suite-2026-11-25-resumed/` and
`artifacts/local-checks/full-suite-2026-11-25-baseline-rerun/`. The earlier
`full-suite-2026-11-25/` run was interrupted at the user's request and is not a
completed verification. The opt-in greater-than-4-GiB stress test was disabled.
Manual dataset acceptance was pending at this stage and was subsequently closed
by the user on 2026-11-25; see the 1.1.0 acceptance record above.

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
