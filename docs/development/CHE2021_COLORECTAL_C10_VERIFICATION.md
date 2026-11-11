# Che2021 Colorectal — C10 verification and acceptance

**Date:** 2026-11-04  
**Scope:** Final verification of C01–C09 after the completed November manual
review. All new execution uses disposable synthetic workspaces. The completed
Che workspace in Windows Documents, the repository's destructive-test copy,
and other real datasets are not inputs to these tests and are not modified.

**Status:** Final automated verification and agent visual inspection pass:
3,871 assertions, zero failures/errors/test warnings/skips. Human post-fix
acceptance remains open. This record supplements rather than
rewrites the original manual failures and scientific results.

Related records:

- [Remediation plan and C10 criteria](CHE2021_COLORECTAL_REMEDIATION_PLAN.md#c10--verification-and-acceptance-gate)
- [Original manual review](CHE2021_COLORECTAL_MANUAL_REVIEW.md)
- [Original follow-up tracker](CHE2021_COLORECTAL_2_FOLLOW_UP_PLAN.md)
- [Release acceptance](RELEASE_ACCEPTANCE.md)

## Additional defect found during C10

The new archived-GUI journey reproduced an empty `cache/` directory being
created merely by loading an archived dataset. A hidden CNA status observer
evaluated `cna_sample_preflight()`, whose cache metadata helpers create the
cache directory. No cache payload or scientific result was restored, but this
violated the archived read-only lifecycle.

`cna_status_preflight()` now waits while storage is retired. A server regression
forces evaluation of the archived eligibility output and verifies zero
preflight/cache calls; after reopening, normal preflight resumes. The browser
checks archive loading, dataset switching, damage review and optional-export
snapshots without recreating `cache/`. Reopening remains explicit.

## Acceptance evidence by checkpoint

| Checkpoints | Final synthetic evidence | Boundary |
| --- | --- | --- |
| APP-05/07, ANN-07, STO-04; C01 | Browser switches unequal sample sets, stale indices, dirty annotations, CNA views and archived workspaces; saved annotation survives restart. | Original manual crashes remain historical failures. |
| ERR-01; C02 | Owned workers die before/after cache publication, recover and retry all configured resolutions. Browser recovery covers legacy confirmation and ended-owner restart. Live owners stay protected. | No real worker is terminated. |
| CNA-07/09; C03 | Computed/omitted/reset navigation guards cache reads; one main heatmap build across warm re-entry and cut changes. Archived preflight regression added in C10. | Timing uses tiny synthetic inputs. |
| STO-07; C04 | Archive/reopen, one-sample recovery, configuration, cut/threshold/final saves and restart show the current next action. | Numerical rebuild phases republish deterministic fixtures; this is not a full scientific recomputation. |
| SNP-03/04/06; C05 | Production review/completion modals tested at desktop and narrow widths with complete selectable paths and bounded geometry. | No new real full-size copy. |
| ERR-03; C06 | UTF-8 and fallback-C Unicode rollback, partial Both publication, exact ownership, preserved prior exports, locale restoration and honest OS-removal refusal. | An OS refusal can still require cleanup of the specifically reported partial output. |
| CNA-02, SEL-02/03, THR-01–04, PRE-03, ANN-06/08; C07–C09 | Omission/reversal, exact saved cuts, new defaults, precise thresholds, saved progress, dropdowns and optional origin reminders. | All P2 implementations are delivered; no C07–C09 feature is deferred. |
| APP-06 | Measured first load, same-session reload and fresh-process restart; session identity distinguishes reload from restart; standardized file hashes stay unchanged. | These measurements do not estimate full Che reload latency. |
| ERR-04 | Four independent archived GUI fixtures: missing/changed required `Cells.csv`, and missing/changed optional CNA CSV. | Automated GUI evidence; human checkbox remains open. |

For required missing files, the snapshot action is disabled. For required
content changes, cheap readiness can still offer the action, but full inventory
verification refuses review and keeps publication disabled. The archive card
reports damage in both cases. Optional damage is also reported by the archive
audit, but science stays completed: review excludes the invalid CNA pair,
requires acknowledgement and publishes a verified folder without it. Both
optional cases preserve pipeline/selection/expression/gene hashes and leave
the cache absent. Required and optional damage are never combined in one case.

## Exact synthetic cases and preservation

- Browser CNA sample names: `Synthetic_sample`, `Z_omitted`, `Z_reset`.
  C03 uses saved k = 7 and changes to 8. C08 restores k = 12 with IDs 1/2,
  changes 12 → 13 → 12 without inheriting the old selection, initializes an
  unsaved sample at 7, edits it to 9, and restores another saved cut at 4.
  Portable tests additionally cover saved k above 20 and small-tree bounds.
- C08 restores display maximum 0.47, X = 0.43, equal Y = 0.163 and Y = 4.137;
  unsaved display maximum is 0.5. Clipping/save/reload preserves assignments.
- C04's untouched controls are `Z_omitted` and `Z_reset`. Process-death/retry
  tests preserve sample `control`, its state, cell-table hash and control output.
  This supplies new identified controls; the original manual subset-control
  name was never recorded and is not retroactively inferred.
- Long-name coverage uses the reported
  `results/COL07_liver_metastasis/3_cna_plots/cna_threshold_unscaled_selection_subclone_1_COL07_liver_metastasis.png`
  and an unbroken filename with 24 repetitions of `unbroken_filename_`.
  Review widths are 1280px and 375px. This is display coverage; native Windows
  filesystem path limits remain enforced separately.

## Measurements and final automated run

Focused C10 browser run: 51 assertions passed. Focused C03 status/navigation
run, including the new archived guard: 55 assertions passed. Neither run had
failures, errors, test warnings or skips. These focused counts overlap the final
suite and must not be added to its total.

The complete final run passed **3,871 assertions**, with **zero failures,
errors, test warnings or skips**. It includes the entire normal test directory,
all main browser journeys, the snapshot layout browsers and archive workers.
The initial pre-C10 baseline passed 3,814 assertions; C10 adds 57 assertions
across archived-status guards (6), four archived GUI damage cases (42) and
measured reload/restart checks (9). Final counts come from this one complete successful run;
neither preliminary failures nor focused reruns are counted again.

Synthetic timings (48 cells, 66 genes; seconds including browser idle waits):

| Operation | Focused run | Complete-suite run |
| --- | ---: | ---: |
| Initial app process/browser startup | 4.50 | 5.98 |
| First dataset load | 4.38 | 6.45 |
| Same-session dataset reload | 1.09 | 1.32 |
| Restarted app process/browser startup | 4.03 | 5.98 |
| Dataset load after process restart | 4.57 | 6.44 |

These are observations, not performance thresholds. “First” does not mean an
OS disk cache was flushed. Startup and dataset loading are measured separately.
During the complete run, C03's first heatmap entry took 4.47 s and warm re-entry
2.60 s, with one heatmap build, one hclust read and one CNA matrix read across
the navigation/cut journey. Timing variation between runs is retained rather
than presented as a fixed speed guarantee.

Agent visual inspection confirmed contained, readable wrapping of the COL07
and unbroken paths at 1280px and 375px, including the relative-base and resolved
destination guidance. A scrolled narrow view retains the complete file list
and accessible footer controls. The focused layout run passed 68 assertions
(including 57 browser assertions), zero failures/errors/test warnings/skips.
These overlap the complete suite. No screenshot baseline was changed.

Runtime: Windows, R 4.5.3, Microsoft Edge, supported
`English_United States.utf8` locale (`LC_NUMERIC=C`). The normal test suite
includes snapshot layout browsers and archive workers. Baseline updates are
disabled. The optional real >4 GiB ZIP64 test is not enabled for this replay;
its earlier dated evidence remains in Release Acceptance. Logs, results and
optional screenshots stay ignored under `artifacts/local-checks/`.

Exploratory C10 runs exposed incomplete-fixture and test-harness assumptions
(missing annotation plot, deterministic session seed reuse, notification
selection and repeated screenshot filenames). Whole-element screenshot capture
also timed out; viewport capture after scrolling to the file list succeeded.
Those harness issues were corrected. The
archived preflight issue above was a real application defect and received a
production fix. Exploratory counts are not final acceptance counts.

## Remaining human sign-off and deferrals

C10's human post-fix journey remains unperformed. Do not check the original
failed boxes merely because automated regressions pass. On disposable fixtures,
the reviewer still needs to confirm:

- [ ] Saved annotation → dataset switch/restart; interrupted clustering → retry.
- [ ] Computed CNA → omitted/reset → computed; archive → reopen → recovery of
  one sample with identified untouched controls.
- [ ] Narrow snapshot review with long paths; Unicode failure/rollback with a
  preserved earlier output.
- [ ] Archived required damage and optional export damage separately, following
  the outcomes above; optional exclusions require acknowledgement.

No new full-size Che heatmap/load benchmark or new >4 GiB ZIP64 run is claimed.
The historical missing control identity and absent historical timings remain
unrecoverable evidence gaps. A final human sign-off should record date,
environment, observed sample/cut/control names and exceptions here. Until then,
software verification and human acceptance must remain separate statuses.
