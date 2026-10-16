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

On dataset load, completed workflow states are reconciled with the manifest.
Missing, legacy-untracked, corrupt, or dependency-mismatched caches make the
corresponding step and its completed downstream steps visibly `stale`.

## Recovery and migration

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

## Test coverage

`test-04_utils_caching.R` covers manifest persistence, dependency changes,
untracked artifacts, failed replacement, artifact/manifest recovery,
family-specific invalidation, and clearing. Workflow and state tests cover
dependency registration, restart reconciliation, CNA reuse, and regression
behavior.
