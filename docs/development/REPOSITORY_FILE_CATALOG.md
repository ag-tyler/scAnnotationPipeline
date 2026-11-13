# Repository file catalog and cleanup assessment

Audit date: **2026-11-13**. Branch: `chore/repository-cleanup-audit`.
Baseline: `ef12c9a` (the `main` HEAD when this branch was created).

This is a pre-cleanup inventory. No existing source, resource, template, test,
or generated output was moved, deleted, or repaired. `datasets/` was excluded
from enumeration and content inspection. Git internals were excluded from the
file inventory. Local environment settings were inventoried without reading
their contents.

The companion [file inventory CSV](REPOSITORY_FILE_INVENTORY.csv) contains one
row for each of the **158 existing files outside `artifacts/`**, including
ignored resources and local settings: path, Git status, bytes, text-line count
where applicable, role, purpose, usage evidence, and cleanup guidance. These two
new audit documents are excluded from the baseline counts. Generated artifact
trees are assessed by run/family below rather than treated as thousands of
independent application files.

The development documentation index links to this catalog. Its inventory row
records the index's size before that navigation-only addition.

## How to interpret usage

| Classification | Meaning |
| --- | --- |
| Runtime | Explicitly sourced, called, or read by the current application; some files are needed only for a particular action. |
| Optional tool | Reusable manual workflow outside the app; absence from app startup does not make it obsolete. |
| Migration | Explicit repair of a particular historical defect; retain or archive deliberately. |
| Development | Profiling, test infrastructure, regression protection, or current developer guidance. |
| Historical/reference | Earlier workflows, experiments, plans, or evidence retained for context. |
| No current consumer found | No current source/configuration/template/test consumer was found; this is a cleanup candidate, not proof that external users never use it. |
| Local/generated | Machine settings, incidental plots, validation logs, or disposable run outputs. |

Evidence comes from the explicit manifest in [app.R](../../app.R), utility
autoloading, configured resource paths, function call sites, tests, documentation,
Git tracking/ignore rules, and relevant Git history. Filename searches alone
would miss dynamically loaded utilities and resources. References in plans or
tests are distinguished from runtime consumers. No access-frequency or external
script audit was attempted; a last commit date is not a last-use date.

## Repository overview

Counts and bytes below describe the working tree **before adding this audit**.
Sizes are logical file lengths, not allocated disk space.

| Location | Tracked files | Local files present | Bytes present | Role |
| --- | ---: | ---: | ---: | --- |
| Repository root | 6 | 8 | 36,004 | Entrypoint, configuration, package/tooling metadata, README; two ignored local files. |
| `app/` | 23 | 23 | 276,260 | Explicitly registered Shiny UI/server/context/state components. |
| `util_scripts/` | 18 | 18 | 441,308 | Shared implementation, automatically sourced in sorted filename order. |
| `R/` | 1 | 1 | 283 | Shiny autoload sentinel. |
| `scripts/` | 6 | 6 | 44,229 | Launcher, reusable manual tools, profilers, historical repair CLI. |
| `templates/` | 5 | 5 | 56,178 | One active import configuration template and four external preparation templates. |
| `resources/` | 4 | 11 | 19,773,306 | Seven ignored runtime references, one optional prompt, three older tracked marker tables. |
| `tests/` | 69 | 70 | 1,076,225 | Permanent regression suite and fixtures; one ignored plot. |
| `docs/` | 15 | 15 | 654,529 | User/runtime contracts, development plans, acceptance records. |
| `.vscode/` | 0 | 1 | 506 | Ignored editor launch settings. |
| `artifacts/local-checks/` | 0 | 6,770 | 3,375,614,732 | Ignored validation/evidence trees, about 3.14 GiB. |
| **Total, excluding `datasets/` and `.git/`** | **147** | **6,928** | **3,397,973,560** | Includes generated copies; they are not additional live source modules. |

The initial working tree had no tracked changes or non-ignored untracked files.
The seven ignored runtime resources were all present. `local_config.yaml` was
absent. No applicable `AGENTS.md` was found in the repository or its ancestors.

## `scripts/`: individual assessment

All six scripts are tracked. They are entrypoints for explicit use; the app
does not automatically source this directory.

| File | Bytes / lines | Classification and purpose | Current usage evidence | Cleanup guidance |
| --- | ---: | --- | --- | --- |
| [run_app.R](../../scripts/run_app.R) | 751 / 21 | Runtime launcher. Disables Shiny autoreload and starts the app from the repository root. | Recommended in `README.md` and `DESCRIPTION`; `app/context.R` includes it in startup instructions. | Keep at its documented path. This is ordinary user-facing operation. |
| [downsample_processed_data.R](../../scripts/downsample_processed_data.R) | 13,118 / 227 | Optional reusable tool. Produces an independent import-ready subset with stratified/uniform sampling, filtering, annotation reset, and a report. | README instructions; `test-downsample-processed-data.R`. Tang demonstration settings are editable defaults, not the only supported dataset. | Keep; a demonstration-oriented default does not make the implementation a one-off script. Direct `Rscript` execution uses settings; sourcing defines the function without executing the copy. |
| [copy_dataset_checkpoint.R](../../scripts/copy_dataset_checkpoint.R) | 18,972 / 338 | Optional reusable tool. Copies an active workspace into a verified resumable checkpoint, remapping IDs/cache dependencies. | README instructions; `test-copy-dataset-checkpoint.R`; explicitly sources six shared utility files into a private environment. | Keep. This differs from the app's non-resumable Review Snapshot. Direct execution uses editable presentation defaults; sourcing only defines the function/settings. |
| [profile_interactions.R](../../scripts/profile_interactions.R) | 6,391 / 188 | Development profiler for Start Menu, storage readiness, CNA preflight, and annotation-loading paths on an existing workspace. | User Guide profiling section; `test-f14-interaction-performance.R` explicitly requires this file and checks its profiling contract. | Retain or relocate with documentation/tests updated together. Default target `Che2021_Colorectal_2` is historical, but a dataset ID/path and iteration count can be supplied. Not executed during this audit. |
| [profile_cna_export.R](../../scripts/profile_cna_export.R) | 3,390 / 62 | Development profiler using disposable synthetic CNA data. Compares conversion allocations/timing; `--export` also profiles publication. | F15/R07 evidence in `CHE2021_COLORECTAL_2_FOLLOW_UP_PLAN.md`; uses live export/cache helpers. | Retain as a reusable benchmark or group with development tools. No biological dataset is required; temporary files are generated when run. Not a startup dependency. |
| [recover_cache_precision.R](../../scripts/recover_cache_precision.R) | 1,607 / 27 | Migration CLI for the specific F15-R01 YAML/cache precision defect. Preview by default; `--apply` invokes repair. | Calls `recover_dataset_cache_precision()` in utility 12; follow-up plan and Liu2022 replay describe its use. The helper is regression tested. | Candidate for a clearly labeled migration area. Keep until legacy recovery support is deliberately retired; it is not routine analysis or an automatically applied fix. |

The two presentation tools last changed in `92f662e` (2026-11-11); the launcher
in `d4c6b71` (2026-10-21); the interaction profiler in `ae15924` (2026-10-28);
the export profiler and recovery CLI in `1203822` (2026-10-30).

## `templates/`: individual assessment

All five files are tracked. Prepared input import has replaced mandatory
in-app standardization. This directory still contains one required runtime
asset, so it cannot be removed wholesale.

| File | Bytes / lines | Classification and purpose | Current usage evidence | Cleanup guidance |
| --- | ---: | --- | --- | --- |
| [dataset_config_template.yaml](../../templates/dataset_config_template.yaml) | 1,011 / 44 | Runtime asset for **Create Dataset**. Supplies analysis defaults and standardized filenames. | `app/server/dataset_server.R` passes this path to `import_prepared_dataset()`; utility 18 reads it and errors if it is absent. Import, transition, snapshot and browser tests also use it. | Keep. The example `Werba2023_Pancreas` ID, `technology: 10x`, and `raw_files` section are historical defaults worth reviewing; import overwrites ID/technology/raw-input settings from the checked source. Preserve the analysis defaults during any later restructuring. |
| [standardize_general.R](../../templates/standardize_general.R) | 10,655 / 285 | Optional, maintained external preparation helper. User supplies ingestion code; helper validates/stages/publishes standardized data. `RUN_STANDARDIZATION <- FALSE` guards execution. | User Guide documents it; `test-standardize-general-template.R` exercises its workflow and utility 08. No current app creation/startup consumer. | Keep as an optional preparation tool. Requires a manually prepared workspace/configuration and helper-only sample YAML; it is not a ready-to-run imported-workspace script. Last updated 2026-11-11. |
| [standardize_10x.R](../../templates/standardize_10x.R) | 26,927 / 953 | Historical/reference 10x preparation workflow: raw archive mapping, manual sample matching, matrix inspection, HGNC mapping and output writing. | Current guide labels older technology-specific templates historical/reference; development plan records prior changes. No current runtime caller. | Candidate for a legacy/reference subfolder, with references updated. Requires adapted paths/settings and pre-existing YAML; begins by clearing the R session and is not guarded like the general template. Not executed or certified against current inputs. |
| [standardize_10x.qmd](../../templates/standardize_10x.qmd) | 10,033 / 268 | Historical/reference Quarto version of the 10x workflow. | Generic historical-template documentation and old development records; no current runtime caller. | Candidate for archival alongside the old R version. Quarto is only needed if a user chooses this workflow. Similar purpose does not establish exact equivalence to the R script. |
| [standardize_undefined.qmd](../../templates/standardize_undefined.qmd) | 7,552 / 194 | Historical/reference Quarto scaffold for custom technologies, with user-supplied ingestion and saving code. | Historical-template guidance; no current runtime caller. | Candidate for archival. Its introduction still says `Samples.txt`, although the current contract is `Samples.csv`; this is documentation drift, not evidence that a text sample file is supported. |

The three technology-specific templates last changed in `2476ea1`
(2026-10-14). The configuration template last changed in `3e42734`
(2026-10-30). Their ages alone do not determine whether they can be removed.

## `resources/`: individual assessment

Runtime resource selection is controlled by `general_config.yaml`, not by
reading every file in this directory. `create_app_context()` validates the
presence of **seven** configured biological files, loads them, normalizes marker
columns, and constructs the gene-position/HGNC mapping. All seven are ignored
local inputs and are **not distributed by Git**.

| File | Git / bytes | Contents observed | Classification and consumer | Cleanup guidance |
| --- | ---: | --- | --- | --- |
| [global_cell_type_markers.csv](../../resources/global_cell_type_markers.csv) | Ignored / 98,457 | 2,723 rows; `cell_type,gene,specificity,sensitivity,combined`. | Runtime `marker_sets`; context normalizes `gene` to the marker schema, excludes the generic Malignant group, and supplies DE matching/signature scoring. | Keep/provision independently of Git. Not replaced by `canonical_markers.csv` or `markers_ss.csv`. |
| [malignant_markers.csv](../../resources/malignant_markers.csv) | Ignored / 151,661 | 4,392 rows; `cancer_type,gene,specificity,sensitivity,combined`. | Runtime `malignant_markers`; context normalizes it, and dataset setup selects cancer-specific markers using the map. | Keep. The similarly named tracked cancer marker table is not the configured input. |
| [housekeeping_genes.txt](../../resources/housekeeping_genes.txt) | Ignored / 703 | 98 gene entries, no header. | Runtime `housekeeping_genes`; loaded into context, used for housekeeping artifact signatures. | Keep. |
| [mt_genes.txt](../../resources/mt_genes.txt) | Ignored / 94 | 13 gene entries, no header. | Runtime `mitochondrial_genes`; loaded into context, used for mitochondrial artifact signatures. | Keep. |
| [cancer_cell_map.json](../../resources/cancer_cell_map.json) | Ignored / 746 | JSON objects `cancer_types` and `cell_types`. | Runtime `cancer_cell_map`; translates sample cancer types to marker acronyms and malignant display cell types. | Keep. |
| [gene_positions_biomaRt_0626.csv](../../resources/gene_positions_biomaRt_0626.csv) | Ignored / 1,373,237 | 26,775 rows; 5 fields including HGNC symbol, Ensembl ID, chromosome and start/end coordinates. Despite `.csv`, the local file is whitespace-delimited, with quoted headers. | Runtime `gene_positions`; `fread()` detects the delimiter; context joins HGNC locations and prepares chromosome ordering for CNA. | Keep. A filename cleanup must update configuration and preserve parsing/content; do not assume comma separation from its suffix. |
| [hgnc_complete_set.txt](../../resources/hgnc_complete_set.txt) | Ignored / 17,011,954 | 44,934 rows; 54 columns, including `ensembl_gene_id`, `symbol`, `location_sortable`. | Runtime `hgnc_complete_set`; context removes ambiguous duplicate Ensembl IDs and joins genomic locations. Also used by optional preparation helpers. | Keep. Largest live resource, about 16.2 MiB; its size is not generated waste. |
| [metadata_extract_prompt.txt](../../resources/metadata_extract_prompt.txt) | Tracked / 11,337 | 174 lines. External AI prompt drafting `Samples.csv`, leaving `n_cells` for the preparer. | Optional preparation reference. README/User Guide link it; `metadata_prompt` remains an optional config entry, explicitly not read/displayed/executed by the app. Preparation-UI tests confirm startup without it. | Keep as an optional aid or relocate with links/config/tests reviewed. Neither a runtime dependency nor an app-side AI integration. Last changed 2026-11-11. |
| [cancer_type_markers.csv](../../resources/cancer_type_markers.csv) | Tracked / 194,196 | 5,334 rows; `cancer_type,gene,specificity,sensitivity,combined`. | **No current consumer found.** Not selected by configuration; no literal filename reference found in current code, templates, tests, or docs before this audit. | Strong archive/removal candidate after external preparation workflows are considered. Different row count from `malignant_markers.csv`; not demonstrated to be a duplicate or interchangeable. |
| [canonical_markers.csv](../../resources/canonical_markers.csv) | Tracked / 1,344 | 81 rows; `cell_type,gene`. | **No current consumer found.** Not configured or directly referenced. | Strong archive/removal candidate. Lacks the scored-marker schema of the configured runtime tables; do not substitute it. |
| [markers_ss.csv](../../resources/markers_ss.csv) | Tracked / 929,577 | 17,442 rows; `cell_type,symbol,m1,m2`. | **No current consumer found.** Not configured or directly referenced. | Strong archive/removal candidate; appears to be a separate signature/score table, but origin and external consumers are unverified. |

The three unreferenced tracked tables entered Git in the initial commit
`6457de8` (2026-09-30) and have no later content commits. Their combined size is
**1,125,117 bytes (about 1.07 MiB)**. A search of non-resource files in that
initial commit also found no literal filename references; this does not prove
how they were produced or whether external scripts use them. No provenance,
licensing, or biological equivalence claim is inferred from their names.

## Remaining application and project files

The CSV gives an individual row for every file in these groups.

| File/group | Role and dependency evidence | Assessment |
| --- | --- | --- |
| `app.R` | Attaches Shiny/data.table/bslib/shinyjs; sources every utility `.R`, then an explicit 23-component manifest; builds context, UI and server. | Runtime; keep. Moving utilities or components requires changing bootstrap/test assumptions. |
| `app/context.R`, `app/state.R` | Immutable configuration/resources and per-session mutable reactive state. | Runtime; keep. |
| `app/ui/app_ui.R`, `dataset_ui.R`, `dashboard_ui.R`, `resolution_ui.R`, `annotation_ui.R`, `cna_ui.R` | Main UI composition plus five workflow panels. All explicitly listed by `app.R`. | Runtime; keep all six. |
| `app/server/app_server.R` | Composes dataset/dashboard/storage/snapshot/resolution/annotation/CNA registrations. | Runtime; keep. |
| `app/server/dataset_server.R`, `dashboard_server.R` | Workspace discovery/import/loading and Start Menu/clustering controls. | Runtime; keep. |
| `app/server/storage_server.R`, `snapshot_server.R` | Dataset archive/reopen and review-snapshot actions. | Runtime; keep. |
| `app/server/single_de_server.R` | Shared single-sample DE server helpers consumed by analysis registrations. | Runtime; keep; not dead simply because it is not a top-level registration in `app_server.R`. |
| `app/server/resolution_server.R`, `annotation_server.R` | Resolution/DE review and manual annotation. | Runtime; keep. |
| `app/server/cna_server.R` | Composes CNA handlers. | Runtime; keep. |
| `app/server/cna_status_server.R`, `cna_compute_server.R`, `cna_cluster_server.R`, `cna_threshold_server.R`, `cna_summary_server.R`, `cna_reset_server.R` | Status/preflight, computation, clustering/navigation, thresholds, final assignment/export, and resets. | Runtime; keep all six; separate files represent distinct registrations. |
| `util_scripts/01_utils_io.R` | Reads samples/cells/matrices/genes and checks required files. | Runtime shared implementation. |
| `util_scripts/02_utils_annotation.R` | Filtering/normalization, PCA/UMAP/Louvain, DE/marker matching, annotation plots, CNA calculations/plots. | Runtime scientific implementation. |
| `util_scripts/03_utils_misc.R` | Marker normalization, metadata construction, configuration reconciliation, preparation validation, and shared helpers. | Runtime plus external preparation support. |
| `util_scripts/04_utils_caching.R` | Cache manifests, fingerprints, locking, dependency validation and recovery. | Runtime persistence contract. |
| `util_scripts/05_utils_workflow.R` | Clustering/DE/CNA orchestration, dependency builders, preflight and progress. | Runtime workflow implementation. |
| `util_scripts/06_utils_logging.R` | Structured persistent append-only events. | Runtime workflow logging. |
| `util_scripts/07_utils_state.R` | Persistent dataset/sample statuses, reconciliation, transitions and readiness. | Runtime state contract. |
| `util_scripts/08_utils_standardization.R` | Validation, mapping, staging and publication for the optional general preparation template. | Optional preparation implementation, **autoloaded** at app/test startup. Its lifecycle functions have no normal app UI caller; preserve template/tests if reorganizing it. |
| `util_scripts/09_utils_pipeline_overview.R` | Read-only aggregate progress and next-action summaries. | Runtime Start Menu/annotation feedback. |
| `util_scripts/10_utils_cna_export.R` | Validated, provenance-linked CNA long-table exports. | Runtime optional export action; also used by export profiler. |
| `util_scripts/11_utils_storage.R` | Post-completion cache retirement, archive audits and reopen lifecycle. | Runtime storage actions; also used by checkpoint tool. |
| `util_scripts/12_utils_cache_precision_recovery.R` | Explicit repair for the historical F15-R01 precision defect. | Migration implementation, **autoloaded**, but not invoked during normal loading. CLI and regression tests consume it. |
| `util_scripts/14_utils_snapshots.R` | Review snapshot validation, inventory, copy/archive publication and rollback. | Runtime snapshots. Numbering gap at 13 is not evidence of a missing dependency. |
| `util_scripts/15_utils_app_selection.R` | Browser selection/index validation, annotation dropdown behavior and CNA view guards. | Runtime cross-view/session protection. |
| `util_scripts/16_utils_clustering_recovery.R` | Tracks execution ownership and safely reconciles interrupted clustering. | Runtime recovery; distinct from the one-time precision migration. |
| `util_scripts/17_utils_prepared_data.R` | Lightweight prepared-input structure/metadata checks. | Runtime import/load; also manual checkpoint validation. |
| `util_scripts/18_utils_dataset_import.R` | Independent staged input copying and fresh workspace configuration/state. | Runtime Create Dataset. |
| `util_scripts/19_utils_console_progress.R` | Step/cumulative console timing without scientific state changes. | Runtime DE/CNA diagnostics. |
| `R/_disable_autoload.R` | Comment-only sentinel disables Shiny's implicit package-directory autoload. | Runtime bootstrap mechanism; keep despite having no functions. Bootstrap test explicitly protects it. |
| `general_config.yaml` | Resource/dataset paths and filenames; read by context, tools and preparation helpers. | Runtime shared configuration. `metadata_prompt` is optional; legacy raw/sample-YAML keys also serve retained tools. |
| `DESCRIPTION` | R version/dependencies, remote `matkot` dependency, testthat settings, devtools metadata. | Required project tooling metadata; describes a sourced app, not a normally installed package. References a missing `LICENSE` file (follow-up below). |
| `.gitignore` | Excludes datasets, private/local config, generated plots/RDS, seven runtime resources, editor settings and local-check evidence; explicitly retains golden fixture. | Keep; protects both local data and deliberate fixture tracking. |
| `.Rbuildignore` | Excludes R project/session files from package builds. | Tooling configuration; normal package builds are not the supported launch path. |
| `README.md` | Installation, launch, input contract, manual tools, tests and documentation entrypoint. | Current user/developer guidance. |
| `.Renviron` | Ignored local R environment file; contents intentionally not read. | Local settings; not a cleanup candidate based on this audit. |
| `.vscode/launch.json` | Ignored generic Node launch configuration using the current file. | Local editor artifact; no application consumer found. Candidate to remove/reset locally if no longer useful. |
| `Rplots.pdf`, `tests/testthat/Rplots.pdf` | Ignored incidental R plot outputs. | Generated output candidates; neither is the committed browser/golden baseline. |

## Documentation catalog

All 15 baseline documentation files are tracked and read as human guidance,
not loaded to implement the current UI.

| File | Current purpose / lifetime |
| --- | --- |
| `docs/USER_GUIDE.md` | Current operations/configuration/resource/helper/test reference; reconcile the tracking statement noted below. |
| `docs/CACHE_VALIDITY.md` | Current cache dependency, invalidation, recovery and migration contract. |
| `docs/PIPELINE_STATE.md` | Current workflow statuses, readiness, recovery and archive/reopen semantics. |
| `docs/PIPELINE_LOGGING.md` | Current persistent event/log format and behavior. |
| `docs/STANDARDIZATION_CHECKLIST.md` | Optional external preparation reference; not displayed, copied or enforced by the app. |
| `docs/development/README.md` | Index separating current guidance and historical development/acceptance records. |
| `docs/development/PREPARED_DATA_IMPORT_PLAN.md` | Current workflow direction and P01-P07 implementation/acceptance record; supersedes mandatory template/YAML/checklist/prompt onboarding. Some human/Linux acceptance remains separate from automated Windows evidence. |
| `docs/development/RELEASE_ACCEPTANCE.md` | Release scenarios, gate instructions and dated verification history. Preserve unresolved human acceptance and distinguish it from later automated results. |
| `docs/development/scAnnotationPipeline_Development_Plan.md` | Original roadmap plus implementation history. Historical requirements must be read with later prepared-import changes. |
| `docs/development/CHE2021_COLORECTAL_2_FOLLOW_UP_PLAN.md` | Earlier follow-up investigation/implementation evidence, including profilers and precision recovery. |
| `docs/development/CHE2021_COLORECTAL_REMEDIATION_PLAN.md` | C01-C10 remediation work and acceptance criteria following manual review. |
| `docs/development/CHE2021_COLORECTAL_C10_VERIFICATION.md` | Final C10 automated/visual evidence and remaining human review checklist. |
| `docs/development/CHE2021_COLORECTAL_MANUAL_REVIEW.md` | Dataset-specific dated manual run/failure evidence; not an executable workflow. |
| `docs/development/F15_LIU2022_LIVER_MANUAL_REPLAY.md` | Dataset-specific F15/R01 manual replay/recovery evidence. |
| `docs/development/RESULT_PRESERVING_PERFORMANCE_PLAN.md` | **Closed/deferred on 2026-11-13**. Preserves proposed optimizations and historical E00 evidence; experiment implementation is on `perf/result-preserving-computation` at `a62b241`, not this branch's runtime. Keep this distinction if archiving local E00 files. |

## Tests and fixtures

All test files are development consumers, not runtime startup dependencies.
`tests/testthat.R` calls `testthat::test_dir()`, which discovers the **58**
`test-*.R` files and loads the two helpers. Individual test names and the first
behavior tested are recorded in the CSV; ticket-like prefixes describe permanent
regressions and do not mean the files were one-off scripts.

| Files | Purpose and preservation requirement |
| --- | --- |
| `tests/testthat.R` | Supported suite runner for this sourced application. |
| `tests/testthat/helper-source.R` | Reproduces utility autoload and data.table attachment in the test environment. Contains a duplicated explanatory comment block, a minor later cleanup candidate. |
| `tests/testthat/helper-fixtures.R` | Deterministic synthetic scientific/workspace fixtures. |
| `test-01_utils_io.R`, `test-02_utils_annotation*.R`, `test-03_utils_misc.R`, `test-04_utils_caching.R`, `test-05_utils_workflow*.R`, `test-06_utils_logging.R`, `test-07_utils_state.R` | Core unit/workflow tests. |
| `test-app-bootstrap.R`, `test-app-components.R`, `test-app-ui-baseline.R` | Assembly/component contracts and disposable browser journeys/screenshots. Browser availability can affect suite skips. |
| `test-c*.R`, `test-f*.R`, `test-m*.R`, `test-p*.R`, `test-t23-release-integration.R` | Permanent feature, recovery, state, archive, import, navigation, snapshot and integration regressions. C05/C06 protections also live in snapshot tests; not every ticket needs its own filename. |
| `test-copy-dataset-checkpoint.R`, `test-downsample-processed-data.R`, `test-standardize-general-template.R` | Regression coverage for optional external tools/templates. Keep with the tools even though app startup does not call them. |
| `test-regression_clustering.R`, `test-regression_cna_cache.R`, `test-golden_outputs.R` | End-to-end scientific/cache regression protection and stored numerical baseline comparison. |
| `tests/testthat/fixtures/generate_golden_fixtures.R` | Explicit manual maintenance utility; intentionally regenerates the scientific baseline. Not a normal suite step and not run during this audit. |
| `tests/testthat/fixtures/compute_cna_golden.rds` | Deliberately tracked scientific expected output; exception to the general RDS ignore rule. Keep. |
| `tests/testthat/fixtures/ui-baseline/windows-4.5/01-dataset-selection.png` through `06-clustering-sample-selection.png` | Six deliberately tracked reviewed browser baselines, including Start Menu, resolution, annotation and CNA panels. Keep; not interchangeable with ignored review screenshots. |

## `artifacts/local-checks/`: one-time work and generated evidence

The entire tree is ignored and outside current application/test autoloading.
Its own README identifies review/remediation runners and diagnostic outputs as
one-off work. Local runners can depend on historical code, mutate baselines,
or read scientific inputs when explicitly rerun; none was executed for this
audit. Artifact scripts were inspected selectively to establish their purpose,
and every nested file was counted/sized. Binary captures, copied source trees,
logs and scientific subsets were not individually validated.

There are **6,495 files in 17 subdirectories**, plus **275 root-level files**
(42,395,883 bytes) grouped by name/purpose below.

| Subdirectory | Files | Bytes | Purpose / lifetime |
| --- | ---: | ---: | --- |
| `e00-boundaries-final/` | 715 | 368,962,201 | Archived performance-equivalence boundary run captures/source copies. |
| `e00-boundaries-verified/` | 718 | 369,431,369 | Earlier verified boundary run evidence. |
| `e00-diagnostic-01/` | 22 | 315,028 | Early E00 diagnostic output. |
| `e00-smoke-01/` | 59 | 2,178,002 | Early E00 smoke run. |
| `e00-smoke-02/` | 86 | 6,064,945 | Early E00 smoke run. |
| `e00-smoke-03/` | 108 | 6,696,305 | Early E00 smoke run. |
| `e00-smoke-04/` | 108 | 6,696,418 | Early E00 smoke run. |
| `e00-smoke-05/` | 271 | 15,076,291 | Later E00 smoke run. |
| `e00-synthetic-final/` | 715 | 41,713,189 | Synthetic E00 final captures/comparisons. |
| `e00-synthetic-verified/` | 718 | 42,181,141 | Earlier verified synthetic captures. |
| `e00-tang-lm1-final/` | 730 | 604,489,371 | Dataset-derived E00 input/captures, copied baseline/candidate sources, metrics and comparisons. |
| `e00-tang-lm3-final/` | 742 | 647,267,789 | Dataset-derived E00 final run evidence. |
| `e00-tang-t1-final/` | 751 | 547,219,498 | Dataset-derived E00 final run evidence. |
| `e00-tang-t1-verified/` | 730 | 547,809,139 | Earlier verified dataset-derived E00 run evidence. |
| `p04-ui-review/` | 6 | 405,924 | Review screenshots; separate from committed approved baselines. |
| `Tang-downsample-594c16493620/` | 8 | 126,205,505 | Demo-tool smoke-test output: prepared subset, sample metadata and downsampling report. Generated scientific data, not merely logs. |
| `tang-standardization/` | 8 | 506,734 | Dataset-specific preparation investigation: inspection/verification scripts, paper/supplement excerpts, figure and user-code notes. |

| Root-level family | Files | Purpose / lifetime |
| --- | ---: | --- |
| `c01_*` to `c04_*` | 45 | Dataset-transition, clustering-recovery, CNA navigation/status validation runners, summaries and logs. |
| `c05_*`, `c06_*` | 23 | Snapshot layout/rollback validation, original reproducers and summaries. |
| `c07_*`, `c08_*`, `c09_*`, `c10_*` | 81 | CNA omission/controls, annotation feedback, final acceptance, screenshots, traces and saved results. |
| `e00_*` | 16 | Deferred experiment checks, final verification, logs and evidence CSV. `e00_verify_final.R` refers to `scripts/performance/`, absent from this branch; its context is the archived experiment branch. |
| `p01_*`, `p02_*`, `p03_*`, `p04_*`, `p05_*`, `p06_*`, `p06a_*`, `p07_*` | 89 | Prepared-data/import/UI/provenance/docs/console-progress and Windows acceptance checks. Includes ad hoc source-edit scripts and selected browser tests; permanent tests already live under `tests/`. |
| `review_*` | 14 | Ad hoc review/retry/archive/snapshot UTF-8 checks and evidence. |
| `run-checkpoint-tests.R`, `run-downsample-tests.R`, `smoke-downsample-tang.R` | 3 | One-off wrappers around permanent tests and a real-input demo smoke check. |
| `README.md`, `optional_changed.png`, `optional_missing.png`, `user-docs-audit.R` | 4 | Artifact instructions, old optional-provenance screenshots, and a focused historical documentation/template test runner. |

E00 directories alone account for **3,206,100,686 bytes (about 2.99 GiB)**.
They offer the largest potential disk-space reduction, but contain the local
captures underlying preserved experiment evidence. Archiving them requires a
decision about evidence retention; the archived Git branch preserves harness
code, not necessarily these local generated captures. Similar directory names
do not establish redundant byte-identical contents.

## Cleanup candidates and follow-up order

These are recommendations for later implementation, not changes made by this
audit.

| Priority | Candidate | Evidence / condition before changing it |
| --- | --- | --- |
| 1 | Reconcile resource documentation. | User Guide currently says only the metadata prompt is intended to be tracked; Git tracks three additional marker tables. Decide their fate, then make documentation match the actual distribution. |
| 1 | Review the three unconsumed tracked marker tables. | No current app/tool/test/config filename consumer found; schemas/row counts differ from live references. Archive/remove only with the external-use uncertainty understood. Keep all seven configured ignored resources. |
| 1 | Choose retention for local E00 evidence and older validation outputs. | Most disk usage is outside Git. Preserve required captures/reports externally before dropping local trees; respect the deferred experiment status. |
| 2 | Separate migration/profiling entrypoints from everyday tools. | `recover_cache_precision.R` is historical repair; profilers are development tools. Relocation requires references and F14 file-contract tests to follow. No need to remove reusable demonstration/checkpoint tools. |
| 2 | Group historical preparation templates. | Three older technology-specific templates are outside current app onboarding; retain supported `standardize_general.R` and active import YAML. Update reference paths and clarify historical limitations. |
| 2 | Revisit legacy import-template/config fields. | YAML still contains an example dataset ID/10x/raw-data fields. Import already replaces these where appropriate; review retained manual-helper assumptions before simplifying defaults. |
| 2 | Resolve stale `local_config.yaml` messaging. | Context actually calls `yaml::read_yaml(config_path)` with default `general_config.yaml`; no automatic local override reader was found. Error text mentions `local_config.yaml`, and a utility comment assumes its presence. Preserve any chosen override behavior explicitly if adding it later. |
| 2 | Resolve `DESCRIPTION`'s `License: file LICENSE`. | No tracked or local root `LICENSE` exists. Determine the intended license before adding/changing legal text. |
| 3 | Remove incidental plot outputs and unused local editor launch settings. | Ignored `Rplots.pdf` files and generic Node launch config have no application role. These are local housekeeping, not source simplification. |
| 3 | Trim duplicated comments and improve guide navigation. | `helper-source.R` repeats a comment block; dated plans/gates can be indexed more clearly. Preserve permanent regression coverage and historical acceptance distinctions. |

No dependency lockfile or tracked CI configuration was found. This is useful
reproducibility context, not evidence that package dependencies or tests can be
deleted. No dependency-installation or licensing changes were attempted.

## Verification and limits

- Enumerated tracked files with `git ls-files`, local/ignored files with a
  directory walk that pruned root `datasets/` and `.git/`, and ignore rules with
  Git. Counted all artifact descendants without running their scripts.
- Inspected bootstrap, context, configuration, server registrations, utility
  functions, all six script entrypoints, all five templates, resource headers,
  test discovery/fixtures, guide/plan records and relevant Git history.
- Searched current code/configuration/templates/tests/docs for consumers;
  additionally searched local artifact text for older resource filename uses.
  The three unconfigured tracked marker filenames had no consumers found.
- Parsed **113 `.R` files** across `app.R`, `R/`, `app/`, `util_scripts/`,
  `scripts/`, `templates/` and `tests/` with R 4.5.3: **zero parse failures**.
  Parsed general/template YAML and checked all seven configured biological
  resources for readability and required fields; marker normalization and map
  JSON shape also passed. Quarto documents were inspected, not rendered.
- The R process emitted Windows locale startup warnings for inherited
  `C.UTF-8` locale categories; the read-only checks completed successfully.
- This was a structural/usage audit, not a fresh scientific, browser, complete
  regression-suite or release-acceptance run. The app was not started, optional
  tools/migrations were not executed, golden fixtures were not regenerated,
  and dataset contents were not read. Resource shape checks do not establish
  biological correctness or provenance.

The CSV uses paths relative to the repository root. Empty line counts indicate
binary files or deliberately unread local environment settings. It records
observed filesystem bytes/lines (including Windows checkout line endings), not
Git blob sizes. Its entries and this assessment describe the baseline date;
rerun the inventory and consumer review after later cleanup changes.
