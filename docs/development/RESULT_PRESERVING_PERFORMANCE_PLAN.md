# Result-preserving computation performance plan

**Date:** 2026-11-11

**Status:** Performance investigation closed/deferred on **2026-11-13** at the
user's request because there is insufficient time for implementation and testing.
This plan is retained on `main` for reference. No performance implementation,
E00 harness or associated tests are included in `main` by this documentation
change. E01-E08 were not started and are deferred.

**Archived experiment:** `perf/result-preserving-computation`, preserved at
[`a62b241`](https://github.com/ag-tyler/scAnnotationPipeline/commit/a62b241a716110e4e72fc2c612b15dbfcb9de265).
E00 was implemented and verified only on that branch; its historical evidence
is recorded below. The branch is retained as an archive, not merged into `main`.

**Historical pinned baseline:** `23b5f49` on `main` when the experiment branch
was created. Its runtime code matches `acbb4ce`, the source tested by the recorded
Windows automated gate:
4,276 assertions passed. The additional baseline commit records that gate.
Sections below preserve the proposed experiments and their historical evidence.
Any future resumption requires a new implementation request and a refreshed
baseline against the then-current `main`.

## 1. Objective and scope

Investigate the review's suggestions **1, 2, 3, 4, and 6**, prioritizing the same
scientific results with lower elapsed time and/or peak memory. This is an
experimental plan, not a commitment to implement every suggestion or replace
the existing algorithms.

Include:

- **1:** Reuse a sample's neighbor/SNN graph across clustering resolutions.
- **2:** Avoid explicit dense centering during PCA.
- **3:** Replace duplicate cache validation/load work with one validated load.
- **4a:** Select the existing CNA genes before centering unused gene rows.
- **4b:** Investigate matrix/chunk-based CNA intermediates and avoid unnecessary
  wide/long conversions while retaining the existing scientific algorithm.
- **6a:** Calculate the existing DE statistic without centering the full matrix.
- **6b:** Share validated CNA inputs across subclone calculations in one action.

Suggestion **5 is excluded**: no alternative Ward implementation, packed-distance
rewrite, different distance metric, or replacement clustering algorithm.
Thread/BLAS tuning, parallel samples, faster UMAP modes, fewer genes/PCs/cells,
different smoothing windows, and visualization resampling are also outside
this plan. The existing Ward implementation, parameters, plotted data, and
scientific decision rules stay the reference throughout these experiments.

The prepared-data import plan's remaining P07 manual/Linux acceptance is
separate. Performance work does not close that acceptance or existing human
release review.

## 2. Priority, expected benefits, and effort

The order below gives **result-preservation confidence first priority**, likely
runtime benefit second, and implementation/testing effort third. Pure reuse of
identical work comes before changes to numerical execution. Consequently the
largest potential speedups are not necessarily attempted first.

Effort ranges are rough **engineering person-days** for a focused candidate,
including investigation and corrections. They are not agent wall-clock promises
or benchmark durations. E00 supplies shared infrastructure; difficult output
disagreements can exceed these estimates. No speedup factor has been measured.

| Order / ID | Candidate and original suggestion | Preservation confidence | Expected time-saving potential | Implementation effort / difficulty | Testing effort / difficulty |
| --- | --- | --- | --- | --- | --- |
| 0 / E00 | Baseline, equivalence harness, and benchmark protocol | Establishes what unchanged means | No direct speedup; prevents misleading results | 1–2 days; medium | 1–2 days; medium/high |
| 1 / E01 | Reuse neighbor/SNN graph (#1) | Very high if graph, cell order, seeds and RNG behavior match | High for the graph-building portion of multi-resolution runs; smaller for the whole workflow | 0.5–1 day; low/medium | 1–2 days; medium |
| 2 / E02 | One validated cache load (#3) | Very high if validation and failure/recovery semantics match | Low/medium overall; potentially higher on I/O-bound or cache-heavy paths | 0.5–1.5 days; medium | 1–2 days; medium/high |
| 3 / E03 | Shared CNA subclone inputs (#6b) | Very high with read-only ownership and no cross-subclone mutation | Low/medium, increasing with matrix size and number of subclones | 0.5–1.5 days; medium | 1–2 days; medium |
| 4 / E04 | CNA gene selection before centering (#4a) | High; selected values should be unchanged when means/order are preserved | Low/medium within CNA preparation; depends on how many genes are unused | 0.25–0.75 day; low | 0.5–1.5 days; medium |
| 5 / E05 | DE means without full centering (#6a) | High mathematical equivalence; rounding/tie risk | Medium on memory-bound DE calculations; plot/scoring time is unaffected | 0.5–1 day; low/medium | 1–2 days; medium/high |
| 6 / E06 | Implicit sparse PCA centering (#2) | Same intended mathematics; greatest propagation risk into neighbors/UMAP | Medium/high potential for memory-bound PCA; runtime must be measured | 1–2 days; medium/high | 2–4 days; high |
| 7 / E07 | Matrix/chunk-based CNA intermediates (#4b) | Conditional on reproducing all ordering, smoothing and reference semantics | High potential on large CNA samples; unmeasured | 3–7 days; high | 4–8 days; very high |
| Final / E08 | Combined-candidate and release comparison | Confirms accepted changes remain equivalent together | Measures realized end-to-end benefit | 0.5–1 day; medium | 1–3 days; high, including long machine runs |

Likely benefit tiers, independently of implementation order:

- **Largest memory/possibly runtime opportunity:** E06 and E07.
- **Clear redundant computation:** E01, especially with multiple resolutions.
- **Workload-dependent savings:** E02, E03 and E05; cache I/O, subclone counts,
  and the fraction of DE time spent on arithmetic determine the actual benefit.
- **Smallest, relatively contained numerical change:** E04. Tang's filtered
  samples often contain only moderately more than the retained 5,000 CNA genes,
  so reducing centering alone will not remove most CNA runtime.

Reorder later experiments only after recording baseline evidence and the reason
for changing priority. An expensive rewrite with negligible end-to-end benefit
can be rejected even if its outputs match.

## 3. Baseline evidence and limits

Historical Tang2026_Colorectal batches on 2026-11-04 took about 30m 37s for
clustering 15 samples at four resolutions, 10m 21s for DE on 15 samples, and
60m 56s for CNA matrices/heatmaps on nine samples. Those are historical batch
elapsed times, not a current per-kernel profile or promised optimization target.

Read-only cache metadata gives useful scale examples:

- CRC_LM1: 6,226 filtered genes and 26,742 cells. One explicitly centered dense
  PCA matrix occupies approximately 1.33 GB of double values before copies.
- CRC_LM1: 5,000 CNA genes by 26,742 cells, approximately 134 million entries.
  Repeated long tables add multiple vectors of this length.
- CRC_LM3: 11,488 candidate cells in Ward clustering. Its quadratic distance
  costs remain outside the selected optimization scope.

These size calculations motivate experiments but do not measure peak RAM or
prove which operation dominates. Current console stage timing and a dedicated
baseline harness must supply that evidence before broad rewrites.

## 4. Branch and experiment discipline

- The original investigation is closed/deferred. The following rules describe
  the original experiment and any future resumption; they do not authorize
  further implementation. Resume in a separate experimental branch and record
  a new baseline before evaluating changes against a newer `main`.
- The original implementation and investigation used `perf/result-preserving-computation`.
  Do not commit optimizations to `main`, move its ref, or merge this branch into
  it during investigation. Any eventual merge requires explicit user acceptance
  of the concrete comparison results.
- Preserve the pinned baseline. Use a disposable baseline checkout/worktree or
  reference implementation in the comparison harness. Never compare only with
  the immediately preceding optimized commit.
- Commit the harness and each candidate separately when implementation is
  requested. Record standalone results against the baseline, then compare the
  accepted combination. Keep rejected experiments out of the proposed merge.
- Plan approval does not approve every optimization. A later implementation
  request starts the specified experiment and its gates; it does not authorize
  automatically proceeding through all candidates.
- Keep experimental selection in the development harness until a candidate is
  accepted. No new user-facing configuration or default-on experimental path
  is needed merely to conduct a comparison.
- Use independent disposable workspaces and cache trees for baseline/candidate
  runs. Candidate computation must not accidentally reuse baseline caches and
  appear equivalent without exercising the changed code.
- Original dataset inputs, annotations, thresholds, notes and caches remain
  untouched. Run representative data only in disposable copies. Keep large
  benchmark outputs under gitignored `artifacts/local-checks/` and retain small
  deterministic fixtures in the test suite where appropriate.
- Pin R/package versions, seeds, thread settings, parameters and input identity
  within a paired comparison. Record Windows and Linux separately. A baseline
  or dependency change requires rerunning affected comparisons.

## 5. Result-preservation contract

E00 must record numerical tolerances, meaningful output comparisons and the
benchmark protocol **before** a candidate is tested. The initial proposals below
are conservative planning defaults, not permission to relax checks later.

### Structural and exact-reuse outcomes

- Preserve cell/gene/sample identity and order, metadata, selected resolutions,
  reference populations, candidate populations, parameters and output schemas.
- E01–E03 should produce identical numerical objects/results. Count reduced
  graph builds, deserializations and reshapes directly, in addition to timing.
- Compare saved scientific payloads independently from timestamps, elapsed-time
  messages and serialization metadata that legitimately change. Preserve
  existing state/error/recovery behavior and archived-workspace protections.
- Label permutations must be distinguished from changed membership. They are
  not automatically acceptable: existing saved cluster selections/annotations
  must still refer to the correct cells. Preserve IDs or demonstrate unchanged
  supported decision mapping; a new migration mechanism is outside scope.

### Numerical and downstream outcomes

- Keep the existing CNA golden test at its current `1e-8` tolerance. Add explicit
  elementwise error summaries; an aggregate comparison alone can hide outliers.
- Propose a maximum absolute difference of `1e-8` for deterministic unrounded
  CNA/DE arithmetic, with identical names/order and matching finite/missing-value
  behavior. Require identical four-decimal CNA cache values where rounding is
  part of the current contract. E00 must confirm these tolerances are suitable.
- Require identical ranked DE gene lists and marker matches initially. Record
  equal/near-equal score ties and cutoff-boundary cases. Do not silently accept
  ranking changes or change tie-breaking to conceal a difference.
- For PCA, compare singular values and cell subspaces, accounting for sign and
  degenerate-basis ambiguities. Initial diagnostic thresholds to evaluate in
  E00 are relative singular-value error at most `1e-6` and maximum principal
  angle at most `1e-3` radians. Measure subspace agreement without constructing
  a cell-by-cell projection matrix.
- Sign/rotation alignment is for diagnostics only. The candidate must run
  independently and pass its actual downstream neighbor/UMAP/clustering checks;
  production code cannot depend on a baseline result to align its output.
- Compare the SNN graph and cell partitions at every tested resolution. The
  default acceptance boundary is unchanged membership after label matching
  (ARI = 1), with saved-decision compatibility also demonstrated.
- Define a near-equality policy for UMAP in E00. Propose rigid-aligned RMS
  displacement no greater than 1% of the baseline embedding's RMS radius and
  99th-percentile displacement no greater than 5%; also report maximum error
  and local-neighborhood agreement. Only translation/rotation/reflection are
  alignment allowances, not arbitrary warping or rescaling. These are proposed
  comparison bounds and do not substitute for unchanged cell partitions.
- Keep the existing Ward distance calculation and `ward.D2` execution. Compare
  the resulting tree/cuts and subclone memberships; differing tie resolution
  cannot silently invalidate saved selections.
- Require the same final cell annotations, malignant/non-malignant calls and
  subclone membership on acceptance cases. Do not adjust thresholds, references,
  manual labels or resolutions to make a candidate pass.

Repeat the baseline against itself to establish actual reproducibility before
attributing differences to a candidate. If the current implementation is not
stable under pinned conditions, investigate that first. Any scientifically
meaningful difference blocks default adoption; document it and defer/reject the
candidate or seek a separately agreed change in scope.

## 6. Experiments and their individual gates

### E00 — Baseline and equivalence/measurement harness

Build paired baseline/candidate comparisons before changing computation.
Existing clustering regression tests mainly check shape/completeness; they do
not establish unchanged cell partitions or embeddings. Extend behavioral coverage
rather than relying solely on the current suite's pass count.

Use deterministic synthetic cases plus representative small, typical and large
real-data copies. Candidate examples are CRC_T1, CRC_LM1 and CRC_LM3, subject to
available memory and a recorded test budget. Include near-tied genes, similar
singular values, multiple resolutions, multiple reference types/subclones,
chromosomes around the smoothing-window boundary, and invalid/corrupt inputs.

Record stage and end-to-end elapsed time, peak process memory, matrix/table
dimensions, graph-build and cache-read counts, and all preservation metrics.
Measure cold/fresh computation separately from valid-cache reuse and invalid
cache recovery. Keep workspace-copy/setup costs separately identified and use
the same inclusion boundary for both implementations. Use paired repeated runs
(normally at least three), with a recorded reduced-repeat protocol for very
expensive full-size runs. OS file-cache conditions and input residency must be
reported consistently.

Gate: comparison thresholds/protocol are recorded, baseline repeats understood,
and the harness detects deliberately changed partitions, reordered inputs,
threshold flips and invalid cache reuse.

#### E00 implementation and verification record (2026-11-11; archived branch only)

The implementation is absent from `main`. These links point to the archived
experimental commit: [runner](https://github.com/ag-tyler/scAnnotationPipeline/blob/a62b241a716110e4e72fc2c612b15dbfcb9de265/scripts/benchmark_computation.R),
[protocol and usage](https://github.com/ag-tyler/scAnnotationPipeline/blob/a62b241a716110e4e72fc2c612b15dbfcb9de265/scripts/performance/README.md),
[versioned contract](https://github.com/ag-tyler/scAnnotationPipeline/blob/a62b241a716110e4e72fc2c612b15dbfcb9de265/scripts/performance/contract.yaml),
[comparators](https://github.com/ag-tyler/scAnnotationPipeline/blob/a62b241a716110e4e72fc2c612b15dbfcb9de265/scripts/performance/equivalence.R), and
[automated coverage](https://github.com/ag-tyler/scAnnotationPipeline/blob/a62b241a716110e4e72fc2c612b15dbfcb9de265/tests/testthat/test-e00-performance-harness.R).
The app and production utility scripts are unchanged. The baseline is exported
from `23b5f49531ab19878c4642f389282bae604c10b4`; working-tree utility copies run
independently as the candidate. Source snapshots, harness/configuration/input
checksums, package versions, locale and thread settings accompany each run.

The contract fixes the proposed numerical bounds before optimization: `1e-8`
unrounded CNA/DE error; PCA relative singular-value error `1e-6` and principal
angle `1e-3`; rigid-aligned UMAP RMS 1%, p99 5% of baseline RMS radius, and mean
15-neighbor overlap at least 99% on up to 128 deterministic anchors. Identity,
rankings, sparse topology/graphs, rounded CNA, Ward trees, cluster IDs and final
assignments remain exact. These conservative numerical limits are gates for
future experiments, not evidence of biological interchangeability of a changed
algorithm. E00 A/A comparisons use the stricter **exact** policy throughout.

Each repeat has four fresh processes: baseline/candidate capture passes and
baseline/candidate measurement passes. Role order alternates. Temporary probes
capture native PCA, embeddings, per-resolution SNN graphs, unrounded CNA, DE
rankings/marker matches, scores, heatmap inputs and scientific cache payloads.
Measurements run untouched functions/namespaces, with exact observer-control
comparisons of scientific cache payloads and final decisions. Baseline repeats
are also compared exactly. Package/input/workspace setup and post-workload
artifact collection are outside elapsed workload time. Normal plots/cache writes
remain included. Inclusive stage diagnostics, graph/cache/reshape counts, each
cache-control load time, sampled RSS and Windows lifetime peak working set are
recorded; memory includes worker setup. See the protocol for these boundaries.

Windows verification uses three repeats per case, 900 seconds and 12 GB per
worker. Real samples are deliberately reduced to **128 seeded, cell-type
stratified cells**, retaining all input genes and original cell order before
normal filtering. This is the recorded reduced-data E00 protocol. It exercises
all configured resolutions, references, Ward selections/subclones and final
thresholds without incurring full-size Ward/runtime costs during harness
development. It does not establish full-size equivalence or timing. Markers are
a resource-derived top-30 panel; saved real-data decisions are copied. Synthetic
cases have two fixed diagnostic subclones; absent real-data decisions would also
use fixed diagnostic selections. None of these copied/subset runs establishes
biological annotation acceptance.
Original data, cache/manifest, configuration and resource fingerprints must
remain unchanged.

Implementation checklist:

- [x] Freeze baseline/candidate sources, contract and common input; isolate caches.
- [x] Implement exact/numerical scientific comparisons and per-resolution graphs.
- [x] Separate capture probes from uninstrumented timing and check observer parity.
- [x] Record resource bounds, stage diagnostics, operation counts and cache controls.
- [x] Verify deliberate partitions/IDs, reordering, PCA/UMAP drift, ranking changes,
  numeric outliers/schema changes, rounded CNA, threshold flips and unsafe reuse fail.
- [x] Pass focused Windows automated tests: **136 assertions / 31 cases**, zero
  failures, errors, warnings or skips. Includes E00, cache validity, golden CNA,
  CNA characterization, clustering regression and CNA-cache regression coverage.
- [x] Finish the five three-repeat scientific comparisons below: **60 isolated
  workers and 55 comparison groups**, all passing with the final comparator.

| Case | Filtered genes x cells | Resolutions / graph builds | Captured scientific artifacts | Evidence directory under `artifacts/local-checks/` |
| --- | --- | --- | --- | --- |
| Synthetic main | 420 x 64 | 3 / 3 | 26 | `e00-synthetic-verified/` |
| Synthetic ties/window boundaries | 5,020 x 64 | 3 / 3 | 26 | `e00-boundaries-verified/` |
| Tang CRC_T1 subset | 6,114 x 128 | 4 / 4 | 28 | `e00-tang-t1-verified/` |
| Tang CRC_LM1 subset | 6,323 x 128 | 4 / 4 | 28 | `e00-tang-lm1-final/` |
| Tang CRC_LM3 subset | 6,382 x 128 | 4 / 4 | 28 | `e00-tang-lm3-final/` |

Each directory retains source/harness/input snapshots, `SUMMARY.txt`,
`comparisons.json`, `comparisons.rds`, `measurements.csv`,
`measurement_medians.csv`, worker scientific payloads, stage/counter records and
logs. Large evidence is intentionally gitignored. Per-case input dimensions
differ from historical full-sample dimensions because filtering is recomputed
after deterministic cell subsetting. Graph-build counts establish the actual
redundant-work baseline for E01; they are not a measured speedup.

All five cases passed role comparisons, exact capture-versus-measure controls
and exact baseline repeats, including scientific values/order, native PCA/UMAP,
per-resolution partitions/IDs and graphs, ranked DE/markers, CNA/Ward outputs and
final assignments. Each real-data experiment verified its original source
fingerprints unchanged through completion. The deliberately exercised backup
recovery warning was identical between compared workers; no other worker
warnings occurred. [Consolidated local evidence](../../artifacts/local-checks/e00_final_evidence.csv)
records dimensions, counts and baseline measurement medians; per-case
`final_comparator_verification.json` records the final checker audit.

**Historical E00 outcome: complete on the experimental branch only.** The comparison
thresholds/protocol are fixed, baseline repeatability is established on the
recorded cases, and deliberate result/caching changes are rejected. No
optimization is accepted by this outcome. At E00 completion, `main` was still
at `23b5f49`; no app or production utility changes were part of E00. The E00
harness and tests remain archived and are not incorporated into `main`.

The full application/browser suite was not rerun for this development-only
harness. The recorded main baseline's full Windows gate remains separate.

Full-size representative comparisons, single-operation warm large-cache timing,
candidate-specific edge cases, Linux measurements and the combined E08 release
gate remain required in the relevant later experiments. Independent E00 cases
may overlap in execution; their timing rows are diagnostic, not speedup evidence.
OS caches were not flushed. No performance improvement is claimed by A/A results.

### E01 — One neighbor/SNN graph per sample (#1)

Separate graph construction from resolution-specific clustering in
`louvain_clustering()` / `cluster_all_samples()`. Reuse only within the same
sample/PCA/settings computation initially; persistent graph caching is not
required. Preserve single-sample paths and the effective RNG behavior.

Test one/multiple resolutions, repeated runs, changed cell order/settings, and
single/batch entry points. Compare graphs, every partition, cell IDs, UMAP
coordinates, saved selections, and plot/label behavior. Instrument the actual
graph builder: four resolutions should need one graph build, not four.

Gate: exact result equivalence and a measured reduction in redundant work.

### E02 — One validated cache load (#3)

Provide/reuse a validated-load result instead of invoking `cache_check_valid()`
and then deserializing the same artifact again. Start with DE and CNA computation
call sites. Keep checksums, dependency/object validation, backup recovery policy,
manifest locking and caller-specific failure behavior intact.

Test valid, missing, corrupt, stale-dependency and backup cases, archived paths,
and independent operations. Existing check calls may use `recover = FALSE`;
combining calls must not silently change that policy. Reuse only inside the
current operation, not an unchecked long-lived object cache. Verify equivalent
scientific/state/error outcomes and actual read counts. Retain save/readback
verification unless separately justified and reviewed.

Gate: identical returned objects/outcomes, preserved safeguards, fewer verified
loads on measured paths, and no new corruption/recovery regressions.

### E03 — Shared CNA inputs across subclones (#6b)

Load/validate common CNA matrix and clustering inputs once per signal/correlation
action. Reuse prepared representations while preserving per-subclone selection,
hotspot calculation, outputs and dependency tracking. Guard against data.table
mutation by reference leaking between subclones.

Compare one/multiple subclones, changed order, repeated selections, valid/invalid
cuts, failed subclones and changed references. Assert inputs remain unchanged
and each subclone's scores, cell IDs and cache payloads match the baseline.
Measure peak memory as well as saved I/O: retaining shared objects must not
create an unacceptable memory lifetime/copy regression.

Gate: identical scientific outputs with reduced repeated preparation and no
cross-subclone contamination.

### E04 — Select CNA genes before centering (#4a)

Calculate the same original gene means and select exactly the same ranked,
positioned genes, including tie order. Center only those selected rows. Preserve
clipping, chromosome/cell order, smoothing and reference correction downstream.

Compare fewer/exactly/more than 5,000 positioned genes, mean ties, sparse/dense
inputs, chromosome order and all existing invalid-input behavior. Compare both
unrounded CNA values and rounded caches/final calls.

Gate: unchanged selected inputs/results, plus measured centering/memory benefit.
Keep expectations modest when only a small number of filtered genes are unused.

### E05 — DE means without a full centered matrix (#6a)

Compute the same cluster mean minus global gene mean statistic without allocating
the full centered matrix. Preserve log-expression scale, denominators, cell/gene
alignment, ranking, top-N selection and marker/scoring semantics.

Test sparse/dense matrices, uneven/small clusters, zeros, equal/near-equal scores,
gene ordering and top-N boundary ties. Compare full score vectors before
truncation, ranked genes, marker tables and downstream annotations. A numerical
speedup cannot be accepted solely because plots look similar.

Gate: agreed numeric equivalence and unchanged ranking/marker/annotation results.

### E06 — Implicit sparse PCA centering (#2)

Investigate IRLBA implicit centering with the correct gene axis. Current input
is genes by cells and downstream code uses the unscaled cell right-singular
vectors (`exp_pca$v`). Transposing input requires mapping singular-vector roles
back correctly. Replacing these vectors with conventional PCA scores multiplied
by singular values would change the current analysis.

Preserve component count, effective seeds, convergence settings, current scaling
convention and downstream parameters. Test sparse/dense inputs, near-degenerate
components, varying sample sizes, convergence failures, single/batch entry points
and every configured resolution. Check native PCA outputs and independently
generated neighbors/embeddings/partitions, not just aligned diagnostic vectors.

Gate: PCA and downstream preservation contract satisfied, plus measured elapsed
time/peak-memory improvement. Correct mathematics alone is insufficient if
approximate neighbor search or UMAP amplifies numerical differences.

### E07 — CNA matrix/chunk representation (#4b)

Only proceed after profiling shows worthwhile allocation/conversion costs.
Start with removing a demonstrably redundant conversion; evaluate chromosome-
or cell-block processing separately before attempting a broad backend rewrite.

Preserve the current gene selection/order, clipping, `caTools::runmean` window
and endpoint behavior, chromosome boundaries, per-cell median centering,
per-reference-type means/ranges, correction thresholds, rounding and schemas.
Preserve cell/gene identities through wide/long conversions. Keep Ward inputs,
candidate selection, plot data and the Ward implementation unchanged.

Test short chromosomes/window edges, coordinate ties, reordered inputs, several
reference populations, zero/near-threshold values, dense/sparse inputs and chunk
boundaries. Compare full CNA matrices, signal/correlation, trees/cuts, final
assignments, saved outputs and heatmap data. Small fixtures and the existing
golden case are necessary but insufficient; include full-size paired runs.

Gate: all scientific/consumer compatibility checks pass and the end-to-end or
peak-memory benefit justifies the substantially larger maintenance surface.

### E08 — Combined acceptance and proposed integration

Compare the accepted combination directly with the pinned baseline. Repeat
focused and full suites, relevant browser/state/storage/snapshot journeys, and
representative end-to-end runs. Validate cache implementation/version decisions
so older caches cannot conceal a changed computation. Exercise Windows and Linux
where available and leave any unperformed platform checks explicitly open.

Publish a per-candidate evidence table: baseline/candidate commits, environment,
inputs, cold/warm timings, peak RAM, scientific comparisons, failures and
accept/revise/defer/reject outcome. Accept only repeatable benefits larger than
measurement variability; memory improvements can qualify if documented and not
offset by an unacceptable runtime regression. Consider maintenance cost when
the gain is small. No universal speedup factor is promised.

Gate: no unresolved result-preservation failures, measured benefits, reviewed
combined evidence, and an explicit user decision before integration into main.

## 7. Progress and decision record

- [x] Investigation closed/deferred on 2026-11-13 due to insufficient time;
  retain the plan on `main` and keep experimental code on the archived branch.
- [x] Dedicated branch created from the recorded main baseline.
- [x] Scope, ranked candidates, effort estimates and proposed gates documented.
- [x] E00 — Baseline, tolerances and comparison harness established; Windows
  verification completed 2026-11-11 (record above).
- [ ] E01 — Neighbor graph reuse evaluated; outcome recorded.
- [ ] E02 — Validated-load reuse evaluated; outcome recorded.
- [ ] E03 — Shared subclone inputs evaluated; outcome recorded.
- [ ] E04 — Early CNA gene selection evaluated; outcome recorded.
- [ ] E05 — DE arithmetic reformulation evaluated; outcome recorded.
- [ ] E06 — Sparse PCA centering evaluated; outcome recorded.
- [ ] E07 — CNA intermediates evaluated or explicitly deferred/rejected.
- [ ] E08 — Accepted combination verified and integration decision recorded.

**Current decision:** E01-E08 are deferred without implementation or acceptance.
Their unchecked items preserve the requirements for a possible future project;
they are not active work. E00 completion above refers solely to the archived
experiment, not to infrastructure available on `main`.

For each experiment, record **not started / investigating / accepted / revise /
deferred / rejected**, with dated evidence. An evaluated-and-rejected experiment
may close its investigation checkbox; it must never be described as an accepted
optimization. Keep implementation status distinct from validated acceptance.

## 8. References

- [Prepared-data import plan and Windows acceptance](PREPARED_DATA_IMPORT_PLAN.md)
- [Current computation helpers](../../util_scripts/02_utils_annotation.R)
- [Workflow orchestration](../../util_scripts/05_utils_workflow.R)
- [Cache validation/loading](../../util_scripts/04_utils_caching.R)
- [Clustering regression coverage](../../tests/testthat/test-regression_clustering.R)
- [CNA golden comparison](../../tests/testthat/test-golden_outputs.R)
- [Cache validity contract](../CACHE_VALIDITY.md)
- [IRLBA implicit centering and vector conventions](https://bwlewis.r-universe.dev/irlba/doc/manual.html)
