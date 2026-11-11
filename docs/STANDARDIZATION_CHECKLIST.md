# Optional Data Preparation Checklist

Use this reference when preparing data with your own scripts and tools. The
[README input specification](../README.md#preparing-input-data) defines the
required output. Checklist usage, checkmarks, preparation scripts, raw-data
folders, sample YAML, and AI metadata extraction are optional. The app does not
display this checklist, copy it into datasets, or inspect its completion.

Prepare outside the analysis workspace, then import the finished directory.
Existing dataset-specific checklists and scripts remain your notes; the app
does not overwrite them. The optional legacy R template has separate
[helper instructions](USER_GUIDE.md#optional-preparation-helpers).

## 1. Identify samples and source data

- [ ] Identify the biological samples actually represented in the expression
  files; do not count sequencing lanes, clusters, or technical replicates as
  separate biological samples by default.
- [ ] Choose one safe canonical ID per sample, matching the source IDs where
  possible. Use those IDs consistently in `Samples.csv`, directory names, and
  cell metadata. Follow the README's Windows/Linux naming rules, including
  exact capitalization and no case-only collisions.
- [ ] Determine the expression scale from source documentation and data, rather
  than assuming a filename proves its contents. Supported scales are counts,
  TPM, and CPM, without log transformation.
- [ ] Identify matrix orientation, gene identifiers, cell identifiers, and any
  supplied sample/cell annotations before splitting or filtering.

## 2. Prepare the authoritative Samples.csv

- [ ] Include all required headers listed in the README, including `n_cells`.
  Header order is unrestricted; preserve useful extra columns.
- [ ] Include one row per imported sample and no additional samples. Row order
  determines the app's sample order. `sample` is non-empty and unique.
- [ ] Keep identifiers as text, including leading zeros such as `0007`. Check
  spreadsheet exports for unintended identifier or date conversions.
- [ ] Use UTF-8 CSV. Quote fields containing commas, quotes, or newlines; double
  quotes inside quoted fields. Use empty fields for unknown metadata, rather
  than the literal string `NA`.
- [ ] Assign clinical metadata only when supported for that sample/patient.
  Distinguish patient disease extent from sampled tissue, primary/metastatic
  specimen status, and treatment timing relative to sampling.
- [ ] If using the optional metadata prompt in `resources/`, review its draft
  against the publication, supplements, and the expression files. Its use is
  not required and its output is not validation evidence.
- [ ] Set `n_cells` from each final prepared `Cells.csv` row count, after your
  preparation filters. Never substitute publication or pre-filter cell counts.
  The metadata prompt intentionally leaves this column blank for you to fill.

## 3. Export aligned expression, gene, and cell files

```text
<prepared-directory>/
  Samples.csv
  <sample>/
    Exp_data_UMIcounts.mtx
    Genes.txt
    Cells.csv
```

- [ ] Each CSV sample has one exactly same-named immediate subdirectory. Remove
  unrelated directories from the directory you select for import.
- [ ] Use one matrix filename/scale throughout the dataset:
  `Exp_data_UMIcounts.mtx`, `Exp_data_TPM.mtx`, or `Exp_data_CPM.mtx`.
  Do not leave multiple supported expression matrices in a sample directory.
- [ ] Write Matrix Market matrices with genes as rows and cells as columns.
  Values are finite and non-negative; counts are integers. Do not log-transform
  values. The app performs downstream normalization/transformation.
- [ ] `Genes.txt` has no header, one non-empty unique gene symbol per line, and
  exactly matches matrix row order. Map IDs to the biological resources' gene
  symbols and sum duplicate mapped gene rows before exporting.
- [ ] `Cells.csv` has one row per matrix column, in exactly that column order,
  and these headers: `cell_name`, `sample`, `cell_type`, `complexity`,
  `cell_subtype`, `patient`, `subclone`, `source`.
- [ ] Cell names are non-empty and unique across the entire dataset. Prefix
  reused barcodes with their sample ID. Each cell's `sample` matches its folder.
- [ ] `complexity` is the number of nonzero gene values for that cell, rather
  than its total expression count. Keep it finite and non-negative.
- [ ] Unknown annotation values may be blank. Keep `patient` and anatomical
  `source` consistent with sample metadata when known. Extra cell columns may
  be retained.
- [ ] Apply gene/cell filtering and reordering consistently to matrices and
  metadata; verify dimensions, order, and final sample cell counts yourself.
- [ ] Export ordinary files/directories; resolve child symbolic links into
  copied files before import. Keep the original prepared directory unchanged
  for future reference.

## 4. Import and begin analysis

- [ ] Start the app, select **Create New Dataset**, and provide a name, the
  prepared-data directory, and an existing destination parent directory.
- [ ] Use the in-app **Browse** controls or type paths directly. Both Windows
  and Linux paths refer to the computer running R. A remotely hosted app needs
  server-accessible files; directory browsing does not upload local client data.
- [ ] Check the resolved source/destination, then select **Create Dataset**.
  Original files are copied, not moved. An existing workspace is never
  overwritten. Correct any structural errors together and retry.
- [ ] After copying, the app opens the workspace immediately. Choose
  **Select Samples for Clustering**; no shutdown or external script step follows
  successful creation.

The app checks `Samples.csv`, sample/folder membership, required filenames,
readability, and non-empty files at import and on every load. It does not read
expression matrices, genes, or cells during this check, compare dimensions,
verify cell counts, or certify scientific correctness. Passing structure checks
does not replace the preparation review above. There is no required strict
validation report, script sentinel, prompt record, or checklist completion mark.

## 5. Optional preparation notes and later changes

When helpful, retain source publication/accession links, raw-to-canonical sample
maps, gene-mapping versions, filtering choices, scale evidence, and your scripts.
These records improve reproducibility but are not import requirements. Record
source DOI/URL in the generated `dataset_config.yaml` if you want it shown in a
review snapshot.

Annotation saves update the workspace's copied `Cells.csv`. Prepare replacement
inputs separately and import a new workspace rather than replacing data during
analysis. The app does not monitor external input replacement or reconcile it
as a supported workflow.

Finished datasets can create folder/ZIP review snapshots before or after cache
cleanup without preparation scripts, sample YAML, or checklist files. Snapshots
retain the complete `processed_data/`, including authoritative `Samples.csv`,
current cells, matrices, and genes. Existing optional preparation files are
included when present; their absence produces no provenance warnings.
