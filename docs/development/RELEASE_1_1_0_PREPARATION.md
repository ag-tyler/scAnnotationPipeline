# 1.1.0 release preparation

**Prepared:** 2026-11-25 on `development`.

**Acceptance:** Automated verification and user manual testing complete.

**Promotion:** Prepared only; `main`, remote branches, and tags are unchanged.

## Version and scope

Use **1.1.0**. The release adds backward-compatible dataset creation controls
for filenames and optional sources, relaxes matrix naming restrictions, and adds
a standalone personal cache reader. It also fixes annotation persistence and
configured seed handling. Existing saved workspace configurations remain
authoritative and loadable; no dataset migration is required. The additive
user-facing features warrant a minor version increment from 1.0.1.

`DESCRIPTION`, README, and NEWS are prepared for 1.1.0. The current main base is
`9fa0bce` (`9fa0bce` is the locally available 1.0.1 release); the development base
is `6d5e626`. Final implementation, acceptance, and version changes are still in
the development working tree and must be committed before promotion. No remote
fetch was performed during preparation; recheck the remote main tip before
applying the candidate.

Ship the app/server/UI and utility changes, the updated configuration and
preparation/downsampling tools, ordinary regressions, user documentation, and
`scripts/load_dataset_cache.R` with its regression test. Keep profiling/recovery
CLIs, the E00 harness, `tests/development/`, and `docs/development/` on
`development`. Main's app-focused README, repository tree, and external links to
development documentation must be preserved. Do not merge development wholesale.

## Completed acceptance

- [x] Full app run and reviewed browser-baseline rerun: 4,860 verified app
  assertions, with no unresolved failures, errors, warnings, or skips.
- [x] Separate development-tool contracts: 62 assertions passed.
- [x] Annotation persistence follow-up: 226 focused assertions passed, plus a
  read-only reproduction on Test's 1,500 cells.
- [x] Plot-caption-only follow-up: 226 focused assertions passed; the separate
  UI note was removed and the original reviewed screenshot baseline restored.
- [x] User-reported manual testing complete: "All seems to work."
- [x] User explicitly waived another full suite after those two follow-ups.

The phase counts overlap and are not a new summed full-suite count. No full
suite or browser journey was rerun after the follow-ups. The optional >4-GiB
stress test was disabled. Detailed commands and evidence are in
[Testing](../TESTING.md#recorded-verification-status); DC06 is closed in the
[implementation plan](DATASET_CONFIGURATION_AND_ANNOTATION_PLAN.md).

## Prepared transfer

The local review package is under ignored
`artifacts/local-checks/release-1.1.0/`:

- `main-candidate/`: app-focused tree based on local main with the selected
  changes, including main-specific documentation adaptations.
- `main-1.1.0.patch`: reviewable transfer patch, applied with `git apply -p2`.
- `main-1.1.0.zip`: ZIP of the prepared app tree; no Git metadata or local data.
- `manifest.json` and `candidate-sha256.csv`: base revisions, included/excluded
  files, and content hashes.
- `validation.json`: patch application, source parity, R syntax, metadata,
  documentation links, and exclusion checks. These are packaging/static checks,
  not another application test run.
- `commit-message.txt` and `release-notes.md`: prepared promotion text.
- `prepare.R`: exact local preparation script.

The patch is checked against the pinned main base in a disposable export.
Prepared runtime, templates, supported scripts, ordinary tests, and fixtures
must match the accepted development working tree after line-ending normalization.
Only user documentation receives main-specific adaptations. The package must
exclude scientific datasets, private resources, local logs/artifacts, and all
development-only tools and records.

Static packaging checks completed on 2026-11-25: **140 app files**, **38 transfer
files**, **127 runtime/configuration/test/fixture parity checks**, **117 R files
parsed**, and **70 local documentation link/heading checks**, with no errors.
The patch applied to a disposable main export and reproduced the candidate
after line-ending normalization. Development-only assets and local data are
absent. The release archive, patch, and per-file SHA-256 hashes are prepared.
ZIP readback preserved all 140 relative paths and matched every candidate file's
SHA-256 hash.
These checks do not add an app test run to the accepted sequence above.

## Remaining promotion steps

1. Review and commit the implementation/version changes and development-only
   acceptance records on `development`, preserving their respective branch
   scope. No commits were created by this preparation.
2. Fetch the remote branches when ready to promote. If main differs from the
   pinned base, rebuild/review the transfer before applying it.
3. Use a separate main checkout/worktree, preserving the development workspace.
   Review the candidate and run `git apply --check -p2 <main-1.1.0.patch>` followed
   by `git apply -p2 <main-1.1.0.patch>` from that checkout's root. Use the patch's
   absolute path or a correctly resolved relative path.
4. Verify the reviewed file scope and version metadata, then commit using the
   prepared commit message. Do not include development-only assets or ignored
   data. The user-approved testing sequence above is the release gate; another
   full run is not a remaining requirement.
5. After approval to update/publish main, push the reviewed main commit and
   create/push the `v1.1.0` tag and release using the prepared notes. Preserve
   existing tags. Record the final main/development commit IDs here and in the
   branch-separation record.

No scientific inputs, existing workspaces, biological resources, or caches need
rewriting as part of this release. Users of the annotation type fix should restart
the app, reopen an affected dataset, and save annotations again to populate a
previously blank `cell_type_pre_cna` CSV column. The release does not repair
dataset files automatically.
