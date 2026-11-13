# Cache Validity and Invalidation

The pipeline stores expensive intermediate results in each dataset's `cache/`
directory. A `.qs2` file is reusable only when its entry in
`cache_manifest.yaml` also passes every applicable check:

- the artifact exists and can be deserialized;
- its byte size and MD5 checksum match the manifest;
- its object structure and numeric values are valid for that artifact type;
- its dependency fingerprint matches the current inputs, parameters, upstream
  artifact versions, and user decisions.

File existence alone is not evidence that a cache is valid.

## Manifest records

Each artifact record includes its type, sample, producing operation, creation
time, checksum, size, dependency fingerprint, dependency details, and a compact
validation summary. The manifest has a schema version and monotonically
increasing revision. It is written through a same-directory temporary file and
keeps a recoverable previous version.

Artifacts are also written through same-directory temporary files. The new
object is read back and structurally validated before it replaces the current
artifact or is registered in the manifest. When an artifact is replaced, one
previous version is kept as `<artifact>.bak`.

## Dependency families

Clustering caches fingerprint:

- the standardized expression matrix and gene list;
- the cell identifiers, sample identifiers, and complexity values used by
  filtering (not later annotation columns in `Cells.csv`);
- filtering, PCA, UMAP, seed, and resolution parameters.

CNA caches fingerprint progressively:

- the filtered expression and current annotated-cell artifact;
- gene-position and reference-cell inputs for the CNA matrix;
- the CNA matrix, current cells, and potentially malignant types for Ward
  clustering;
- the CNA matrix, Ward clustering, reference cells, and selected malignant
  cluster for signal/correlation results.

This creates an explicit dependency chain without coupling cache validity to
unrelated configuration fields.

## Automatic invalidation

The app physically removes dependent CNA artifacts and their manifest records
when a saved resolution, annotation, CNA configuration, or malignant-cluster
selection changes. Reset Sample CNA uses the same manifest-aware invalidation.
Unchanged decisions do not invalidate reusable artifacts.

Dataset loading uses a fast metadata reconciliation against manifest records,
cache file sizes/modification times, and recorded source-file sizes. Unchanged
metadata does not require hashing every large cache. A changed cache timestamp
requires a matching checksum rather than automatically invalidating work.
Workspace-owned source paths resolve against the current dataset, including
legacy Windows `processed_data/<sample>/<file>` paths; relocated sources must
match their recorded checksums. An accessible original workspace cannot mask
changed or missing inputs in the copied workspace. Verified location metadata
is refreshed under the manifest lock, preserving the fast path on later loads;
invalid records remain rejected. Other source changes with
unchanged size are checked on first use. Full integrity, structure, and dependency validation is
performed when an artifact is consumed; validated checksums can be reused while
file metadata remains unchanged. Missing, untracked, changed, or invalid caches
make the affected completed work and its completed downstream steps `stale`.

## Recovery and migration

New dependency fingerprints hash uncompressed serialization with a fixed writer
stamp, UTF-8 text, and consistent dataframe representation. They exclude R's
writer-version stamp, gzip's platform header, and data.table's session
bookkeeping. Legacy fingerprints remain verifiable against their original
serialization profile when the current scientific inputs reproduce them.

For an existing workspace copied from Windows or another Linux location, the
optional manual recovery CLI is maintained on the
[development branch](https://github.com/ag-tyler/scAnnotationPipeline/blob/development/scripts/recover_cache_location.R).
Stop the app and use a development checkout with the intended workspace and
resource paths configured. Run the following from that checkout's repository
root (the scripts are not included in the app-focused checkout):

```sh
Rscript scripts/recover_cache_location.R Tang2026_Colorectal
Rscript scripts/recover_cache_location.R Tang2026_Colorectal --apply
```

The first command previews changes without modifying the workspace. Recovery
verifies every registered cache's size/checksum and recorded source-file
contents, current filtering/clustering parameters, saved annotations, and CNA
configuration. If an old cell-input hash cannot be reproduced, it independently
replays deterministic filtering and requires exact equality with the saved
expression matrix and clustered input rows. For old gene-position hashes it
checks every coordinate actually used by CNA, selected genes, and cell
membership against the saved matrix; reference identities and upstream
fingerprints must still validate. These explicit checks can read large matrices;
ordinary loading does not perform this replay.

Apply preserves both state generations and manifests in a
`cache-location-recovery-*` directory before updating metadata. Verified legacy
bindings survive annotation-only cache rewrites. The tool can migrate completed
workspaces without changing their statuses, or restore stages through base CNA
only when the preserved checkpoint proves they became stale solely from the
old startup cache screen. Genuine invalidations, changed decisions, retired
storage, or unverifiable inputs block recovery. Later CNA decisions remain
stale for review. Scientific input files, cache payloads, and result files are
not replaced, and normal loads never automatically promote stale stages.

If the current artifact is damaged but its recorded previous version is valid,
the previous version is restored. If the manifest is damaged, its previous
consistent checkpoint is restored. If neither version is valid, the cache is
rejected and the producing pipeline step must be rerun.

Cache files created before the manifest contract are intentionally not trusted
or silently adopted because their inputs and parameters cannot be proven.
Loading such a dataset marks affected completed work stale. Rerun clustering
once to register clustering artifacts, then rerun the affected CNA stages.

Do not manually edit `cache_manifest.yaml`. The in-app reset and rerun actions
keep artifacts, workflow state, and logging aligned.

## Finished-dataset cleanup

Do not delete a completed dataset's cache manually. Use the **Dataset Storage**
card on the Start Menu. Cleanup is enabled only when every sample has durable
final tables and plots, every sample has finalized CNA or explicitly omitted it,
and the cache inventory contains only recognized manifest/artifact files.
CNA values exports are optional: missing or outdated exports produce warnings
but do not block cleanup. Existing exports are retained and audited. Export any
values you need before cleanup; exporting afterward requires reopening and
recomputing the required caches.

The app writes a revisioned `storage_state.yaml` cleanup journal, records the
cache inventory and retained-output checksums, renames the whole cache to a
same-parent retirement directory, and only then deletes it. A locked file,
interrupted operation, or failed state write remains recoverable through retry
or rollback. Archived datasets deliberately skip normal missing-cache
reconciliation. Reopening creates an empty cache and makes recomputation
requirements visible in pipeline state; deleted caches are never presented as
restored.

## Test coverage

`test-04_utils_caching.R` covers manifest persistence, dependency changes,
untracked artifacts, failed replacement, artifact/manifest recovery,
family-specific invalidation, and clearing. Workflow and state tests cover
dependency registration, restart reconciliation, CNA reuse, and regression
behavior. `test-f16-dataset-storage.R` covers cleanup readiness, explicit CNA
omission, optional-export warnings, retirement/retry/rollback, archive auditing, and
reopening.
