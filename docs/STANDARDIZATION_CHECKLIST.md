# Standardization Checklist

Use this checklist to adapt `templates/standardize_general.R` for a new
single-cell dataset. The objective is one reproducible `standardize.R` script
that transforms the raw inputs into the strict format required by the app.

The app copies the general template into every new dataset workspace as
`standardize.R`, together with this checklist as
`datasets/<dataset>/STANDARDIZATION_CHECKLIST.md`. Keep checkmarks and notes in
that dataset-specific copy; this repository document stays an unchecked
reference template and does not need to be reset between datasets. The older
technology-specific script templates are reference material only.

From Dataset Selection → Standardization Guide, **Open Standardization
Checklist** displays the selected workspace's copy inside the app. For an
older workspace without one, **Create Dataset Checklist** makes a copy without
overwriting existing files. Edit the Markdown file in your editor and reopen
the viewer to see your changes. The viewer also provides its exact path and
a Markdown download. Checklist marks are a manual record, not pipeline statuses.

## Definition of done

A dataset is standardized only when all of the following are true:

- [ ] `samples_config.yaml` uses `sample` and contains every required field.
- [ ] Every configured sample has one directory under `processed_data/`.
- [ ] Every sample directory contains its matrix, `Genes.txt`, and `Cells.csv`.
- [ ] Matrix rows align positionally with `Genes.txt`.
- [ ] Matrix columns align positionally with `Cells.csv`.
- [ ] Gene identifiers are non-empty and unique after mapping.
- [ ] Cell identifiers are non-empty and unique across the entire dataset.
- [ ] The matrix contains finite, non-negative values on a declared scale.
- [ ] `Samples.csv` contains every configured sample and correct cell counts.
- [ ] The script reaches `POST-VALIDATION PASSED` in strict mode.

## 1. Create and inspect the workspace

- [ ] In the app, select **Create New Dataset**.
- [ ] Enter a safe dataset folder name.
- [ ] Confirm that **Standardization Template** is set to `general`.
- [ ] Confirm that the new folder contains:

```text
<dataset>/
├── cache/
├── data/
├── processed_data/
├── results/
├── logs/
├── dataset_config.yaml
├── samples_config.yaml
├── selected_config.yaml
├── STANDARDIZATION_CHECKLIST.md
└── standardize.R
```

- [ ] Place the original input files under `data/` or document any intentional
  external source paths in `standardize.R`.
- [ ] Keep raw inputs unchanged. Perform transformations in code so the dataset
  can be reproduced from the original files.

## 2. Inspect the raw data before coding

Record the answers in comments in the dataset's `standardize.R`:

- [ ] What file or object contains expression values?
- [ ] Are genes represented by rows and cells by columns? If not, where will
  the matrix be transposed?
- [ ] Are the values raw UMI counts, TPM, or CPM?
- [ ] Confirm that the values are not already log-transformed.
- [ ] Where are the gene identifiers stored?
- [ ] Are they HGNC symbols, Ensembl IDs, or another identifier type?
- [ ] Where are cell identifiers stored?
- [ ] Are cell identifiers unique only within samples or across the dataset?
- [ ] How are raw sample identifiers mapped to canonical sample names?
- [ ] Is the dataset one combined matrix, one file set per sample, or another
  structure?
- [ ] Which cell-level annotations should be retained?
- [ ] Which sample-level fields are supported by the paper or metadata files?

Do not infer the expression scale solely from a filename. Inspect matrix values
and the source documentation.

## 3. Complete `samples_config.yaml`

- [ ] Use `sample` as the identifier key. Do not use `id`.
- [ ] Add exactly one entry for each biological sample.
- [ ] Use names that are safe as directory names: no `/`, `\`, `.` or `..`.
- [ ] Ensure sample names are unique.
- [ ] Use the same canonical names in raw-to-sample mapping code.
- [ ] Include every required metadata key, even when its value is blank.
- [ ] Leave `n_cells` blank; the script calculates it from the standardized
  cell tables.
- [ ] Distinguish biological sequencing technology from the general template.
  The value `general` is a template name, not a technology.

The prevalidation step stops before output generation if this configuration is
empty, malformed, uses `id`, contains unsafe or duplicate sample names, or is
missing required fields.

## 4. Complete the user settings

Edit the `settings` list near the top of `standardize.R`:

```r
settings <- list(
  app_folder_path = NULL,
  dataset_name = "My_Dataset",
  matrix_state = "UMIcounts",
  reset_selected_config = FALSE
)
```

- [ ] Leave `app_folder_path = NULL` to search upward from the script and
  working directory for `general_config.yaml` and `util_scripts/`.
- [ ] Set an explicit application-root path only when automatic discovery is
  unsuitable.
- [ ] `dataset_name` exactly matches the dataset folder name.
- [ ] `matrix_state` is one of:

| Value | Use when |
| --- | --- |
| `UMIcounts` | Values are non-negative integer UMI/read counts |
| `TPM` | Values are non-negative transcripts-per-million values |
| `CPM` | Values are non-negative counts-per-million values |

- [ ] Keep `reset_selected_config = FALSE` for normal standardization and
  repeat runs. This preserves saved clustering and CNA choices.
- [ ] Set `reset_selected_config = TRUE` only when those saved choices should
  intentionally be reinitialized.
- [ ] Keep `RUN_STANDARDIZATION <- FALSE` until the `BEGIN USER CODE` region is
  implemented and reviewed.

Other scales, including log-transformed matrices, are not accepted by the
standardized-data contract.

## 5. Complete the linear `BEGIN USER CODE` region

Use ordinary R code in this region. No callback functions are required. Load
shared inputs once, apply dataset-specific mappings or transformations, and use
whatever loop structure is natural for the source data.

Possible responsibilities include:

- [ ] Extract an archive when extraction is reproducible and necessary.
- [ ] Discover input files or build a sample-to-file table.
- [ ] Load a combined matrix once or load one matrix inside the sample loop.
- [ ] Load shared gene or cell metadata.
- [ ] Map raw sample identifiers to canonical configured names.
- [ ] Load and apply a gene-identifier mapping resource when necessary.
- [ ] Confirm every configured sample has a raw input source.

For explicit raw-to-canonical mappings, the optional helper preserves order and
fails on unmapped identifiers:

```r
sample_ids <- map_standardization_sample_ids(
  raw_ids,
  c(raw_A = "sample1", raw_B = "sample2")
)
validate_standardization_sample_mapping(unique(sample_ids), sample_names)
```

Inside the sample loop, construct one `sample_input` list:

```r
list(
  expmat = sample_matrix,
  genes = gene_symbols,
  cells = cell_names,
  cell_metadata = optional_cell_metadata
)
```

Then call the two visible pipeline steps:

```r
standardized_sample <- prepare_standardized_sample(
  sample_input = sample_input,
  sample_name = sample_name,
  sample_meta = sample_meta,
  matrix_state = settings$matrix_state
)

register_standardized_sample(
  context = standardization,
  sample_name = sample_name,
  standardized_sample = standardized_sample
)
```

`prepare_standardized_sample()` validates and transforms one in-memory sample.
`register_standardized_sample()` checks cross-sample cell uniqueness, writes to
the isolated staging directory, and records the calculated cell count. Their
full contracts and side effects are available through their docstrings.

## 6. Construct each `sample_input`

### Expression matrix

- [ ] Return a numeric matrix with genes as rows and cells as columns.
- [ ] Use a sparse `Matrix` object where practical.
- [ ] Ensure values match `settings$matrix_state`.
- [ ] Do not normalize or log-transform UMI counts in the standardization step.
- [ ] Apply every row or column filter to both the matrix and its matching
  identifier vector.

### Genes

- [ ] Return one final gene symbol per matrix row.
- [ ] Map Ensembl or other identifiers to gene symbols before constructing
  `sample_input`.
- [ ] Preserve row order during mapping.
- [ ] Use `NA` or an empty value for genuinely unmapped genes; shared code
  removes those identifiers and the corresponding matrix rows together.
- [ ] Do not discard duplicate symbols manually. Shared code sums duplicate
  sparse-matrix rows so total expression is preserved.
- [ ] Review how many genes are removed or collapsed and investigate surprising
  losses.

### Cells

- [ ] Return one cell identifier per matrix column.
- [ ] Make identifiers unique across the complete dataset, not only within one
  sample.
- [ ] If raw barcodes repeat between samples, add a deterministic sample suffix
  or prefix in the user-code loop.
- [ ] Apply the same renamed identifiers to optional cell metadata.
- [ ] Never rely on row order alone when attaching optional metadata; provide a
  `cell_name` key.

### Optional cell metadata

`cell_metadata` may be omitted or set to `NULL`. When supplied:

- [ ] It contains one row per cell and a unique `cell_name` column.
- [ ] Its identifiers exactly match the returned `cells` vector.
- [ ] Retain useful annotations such as `cell_type`, `cell_subtype`, or
  `subclone` when they are supported by the source.
- [ ] Do not use it to override `sample`, `patient`, `source`, or `complexity`.
  Shared code derives those fields consistently.

`prepare_standardized_sample()` reorders optional metadata by `cell_name`,
constructs the required cell schema, assigns sample/patient/source fields, and
calculates complexity as the number of expressed genes per cell.

## 7. Review the shared transformations

Before enabling execution, confirm that the shared behavior is appropriate:

- [ ] Blank or unmapped genes are removed with their matrix rows.
- [ ] Duplicate gene-symbol rows are summed.
- [ ] Duplicate or blank cell identifiers cause a hard failure.
- [ ] UMI-count matrices must contain integers.
- [ ] All supported matrices must contain finite, non-negative values.
- [ ] Optional cell metadata is aligned by `cell_name`.
- [ ] Sample metadata comes from `samples_config.yaml`.
- [ ] Existing `selected_config.yaml` is preserved unless reset was explicitly
  requested.

Do not edit pipeline-code sections to work around malformed inputs. Correct the
dataset-specific user code or configuration instead. Reusable implementation
details are in `util_scripts/08_utils_standardization.R`; the template keeps
their order and purpose visible through named calls and explanatory comments.

## 8. Run the standardization

- [ ] Save the completed dataset-specific `standardize.R`.
- [ ] Start a clean R session.
- [ ] Set:

```r
RUN_STANDARDIZATION <- TRUE
```

- [ ] Run the entire script from the beginning rather than isolated trailing
  sections.
- [ ] Confirm the script sources utilities from the intended app checkout.
- [ ] Review messages about removed or duplicate genes.
- [ ] Do not continue into downstream analysis if the script stops.

The script stages one sample at a time under `processed_data_staging`, creates
`Samples.csv`, and invokes strict postvalidation against the complete staging
directory. Only valid staging output replaces `processed_data`; it then updates
configuration and pipeline state.

## 9. Review the generated outputs

For every configured sample, check:

- [ ] The sample directory name exactly matches its `sample` value.
- [ ] The expression filename matches the selected matrix state.
- [ ] `Genes.txt` has no header and contains one symbol per matrix row.
- [ ] `Cells.csv` contains at least:

```text
cell_name, sample, cell_type, complexity,
cell_subtype, patient, subclone, source
```

- [ ] Every `Cells.csv` row contains the directory's sample name.
- [ ] Complexity is finite and non-negative.
- [ ] `Samples.csv` contains one row per configured sample.
- [ ] `Samples.csv$n_cells` matches the corresponding `Cells.csv` row count.

The final console/report output must contain:

```text
POST-VALIDATION PASSED
```

Because validation uses `strict = TRUE`, a completed run cannot silently accept
reported contract violations.

## 10. Respond to validation failures

Correct the cause and rerun the complete script.

| Failure | Check first |
| --- | --- |
| Unsupported `id` key | Rename it to `sample` in `samples_config.yaml` |
| Missing sample directory/files | Raw-to-sample mapping and write paths |
| Genes length differs from matrix rows | Gene filtering/mapping order |
| Cells length differs from matrix columns | Cell filtering/splitting order |
| Duplicate genes after output | Gene mapping and duplicate-row aggregation |
| Duplicate cells within a sample | Raw barcode handling |
| Cells reused across samples | Add a deterministic sample prefix/suffix |
| Cells assigned to another sample | Canonical sample mapping |
| Non-integer UMI counts | Incorrect scale declaration or transformed input |
| Negative/non-finite expression | Input corruption or inappropriate transformation |
| Incorrect `n_cells` | Cell-table construction or stale output files |

Do not suppress validation errors or switch off strict mode to make a dataset
loadable.

## 11. Repeat-run checklist

- [ ] Keep `reset_selected_config = FALSE` unless a reset is intentional.
- [ ] Confirm the correct app checkout in `app_folder_path`.
- [ ] Confirm raw inputs and mapping rules have not changed unexpectedly.
- [ ] Rerun the entire standardization script.
- [ ] Require strict postvalidation to pass again.
- [ ] Review regenerated output timestamps and unexpected file differences.
- [ ] Rerun downstream clustering/annotation when standardized expression,
  genes, cells, or sample membership changed.

## 12. Reproducibility record

Before considering the dataset complete, record:

- [ ] Source publication/accession and raw-data download location.
- [ ] Raw file names or checksums where available.
- [ ] Expression scale and evidence supporting that choice.
- [ ] Raw-to-canonical sample mapping.
- [ ] Gene-ID mapping resource and version/date.
- [ ] Cell-identifier transformation rule.
- [ ] Counts of removed unmapped genes and collapsed duplicate symbols.
- [ ] Date and result of the final strict standardization run.
- [ ] Any dataset-specific assumptions that a future maintainer must verify.

The completed dataset-specific `standardize.R`, configuration files, and this
record should be sufficient to reproduce the standardized outputs without
manual intermediate edits.
