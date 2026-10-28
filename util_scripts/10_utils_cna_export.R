# ==================================================================================================
# Script: 10_utils_cna_export.R
# Purpose: Validated, provenance-linked publication of reusable CNA values tables.
# ==================================================================================================


CNA_VALUES_EXPORT_SCHEMA_VERSION <- 1L
CNA_VALUES_EXPORT_IMPLEMENTATION <- "cna-values-export-v1"
CNA_VALUES_EXPORT_COLUMNS <- c("gene", "chr", "start_pos", "cell_name", "cna")


cna_values_export_safe_name <- function(sample_name) {
  sample_name <- trimws(as.character(sample_name))
  if (length(sample_name) != 1L || is.na(sample_name) || !nzchar(sample_name)) {
    stop("sample_name must be one non-empty identifier.", call. = FALSE)
  }
  safe <- gsub('[<>:"/\\\\|?*]', "_", sample_name)
  safe <- sub("[. ]+$", "", safe)
  if (!nzchar(safe)) stop("sample_name cannot produce a safe export filename.", call. = FALSE)
  safe
}


cna_values_export_paths <- function(results_dir_path, sample_name, create = FALSE) {
  if (
    length(results_dir_path) != 1L || is.na(results_dir_path) ||
      !nzchar(trimws(results_dir_path))
  ) {
    stop("results_dir_path must be one non-empty path.", call. = FALSE)
  }
  safe_name <- cna_values_export_safe_name(sample_name)
  directory <- file.path(results_dir_path, sample_name, "3_cna_results")
  if (isTRUE(create)) dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  list(
    directory = directory,
    csv = file.path(directory, paste0("cna_values_", safe_name, ".csv.gz")),
    metadata = file.path(directory, paste0("cna_values_", safe_name, ".metadata.yaml"))
  )
}


validate_cna_values_export_metadata <- function(metadata) {
  required <- c(
    "schema_version", "sample", "created_at", "implementation", "format",
    "compression", "columns", "row_count", "gene_count", "cell_count",
    "csv_filename", "csv_checksum", "csv_size_bytes", "csv_modified_at", "cache"
  )
  missing <- setdiff(required, names(metadata))
  if (length(missing) > 0L) {
    stop("CNA export metadata are missing: ", paste(missing, collapse = ", "), ".", call. = FALSE)
  }
  if (!identical(as.integer(metadata$schema_version), CNA_VALUES_EXPORT_SCHEMA_VERSION)) {
    stop("Unsupported CNA export metadata schema version.", call. = FALSE)
  }
  if (!identical(unlist(metadata$columns, use.names = FALSE), CNA_VALUES_EXPORT_COLUMNS)) {
    stop("CNA export metadata contain an unexpected column schema.", call. = FALSE)
  }
  counts <- suppressWarnings(as.numeric(c(
    metadata$row_count, metadata$gene_count, metadata$cell_count, metadata$csv_size_bytes
  )))
  if (length(counts) != 4L || any(!is.finite(counts)) || any(counts < 0)) {
    stop("CNA export metadata contain invalid counts.", call. = FALSE)
  }
  if (!is.list(metadata$cache) || !all(c(
    "filename", "checksum", "dependency_fingerprint"
  ) %in% names(metadata$cache))) {
    stop("CNA export metadata lack cache provenance.", call. = FALSE)
  }
  invisible(TRUE)
}


validate_cna_values_export_file <- function(path, expected_rows) {
  if (!file.exists(path) || file.info(path)$size <= 0L) {
    stop("CNA values export was not written or is empty.", call. = FALSE)
  }
  connection <- gzfile(path, open = "rt")
  on.exit(close(connection), add = TRUE)
  header <- readLines(connection, n = 1L, warn = FALSE)
  expected_header <- paste(CNA_VALUES_EXPORT_COLUMNS, collapse = ",")
  if (length(header) != 1L || !identical(header, expected_header)) {
    stop("CNA values export has an unexpected CSV header.", call. = FALSE)
  }
  row_count <- 0
  repeat {
    lines <- readLines(connection, n = 100000L, warn = FALSE)
    if (length(lines) == 0L) break
    row_count <- row_count + length(lines)
  }
  if (!identical(as.numeric(row_count), as.numeric(expected_rows))) {
    stop(
      "CNA values export row count mismatch: expected ", expected_rows,
      ", found ", row_count, ".",
      call. = FALSE
    )
  }
  invisible(row_count)
}


.publish_cna_values_export_pair <- function(
  temporary_csv,
  temporary_metadata,
  final_csv,
  final_metadata,
  rename_file = file.rename
) {
  if (!file.exists(temporary_csv) || !file.exists(temporary_metadata)) {
    stop("Validated CNA export temporary files are incomplete.", call. = FALSE)
  }
  csv_backup <- paste0(final_csv, ".bak")
  metadata_backup <- paste0(final_metadata, ".bak")
  for (backup in c(csv_backup, metadata_backup)) {
    if (file.exists(backup) && !file.remove(backup)) {
      stop("Could not replace prior CNA export backup: ", backup, call. = FALSE)
    }
  }

  had_csv <- file.exists(final_csv)
  had_metadata <- file.exists(final_metadata)
  if (had_csv && !rename_file(final_csv, csv_backup)) {
    stop("Could not back up the prior CNA values CSV.", call. = FALSE)
  }
  if (had_metadata && !rename_file(final_metadata, metadata_backup)) {
    if (had_csv && file.exists(csv_backup)) rename_file(csv_backup, final_csv)
    stop("Could not back up the prior CNA values metadata.", call. = FALSE)
  }

  if (!rename_file(temporary_csv, final_csv)) {
    if (had_csv && file.exists(csv_backup)) rename_file(csv_backup, final_csv)
    if (had_metadata && file.exists(metadata_backup)) rename_file(metadata_backup, final_metadata)
    stop("Could not publish the CNA values CSV.", call. = FALSE)
  }
  if (!rename_file(temporary_metadata, final_metadata)) {
    if (file.exists(final_csv)) file.remove(final_csv)
    if (had_csv && file.exists(csv_backup)) rename_file(csv_backup, final_csv)
    if (had_metadata && file.exists(metadata_backup)) rename_file(metadata_backup, final_metadata)
    stop(
      if (had_csv || had_metadata) {
        "Could not publish the CNA values metadata; the prior export was restored."
      } else {
        "Could not publish the CNA values metadata; no partial export was retained."
      },
      call. = FALSE
    )
  }

  for (backup in c(csv_backup, metadata_backup)) {
    if (file.exists(backup)) file.remove(backup)
  }
  invisible(list(csv = final_csv, metadata = final_metadata))
}


export_cna_values_table <- function(
  sample_name,
  dataset_dir_path,
  results_dir_path,
  chunk_cell_count = 25L,
  timestamp = Sys.time(),
  rename_file = file.rename
) {
  chunk_cell_count <- suppressWarnings(as.integer(chunk_cell_count))
  if (length(chunk_cell_count) != 1L || is.na(chunk_cell_count) || chunk_cell_count < 1L) {
    stop("chunk_cell_count must be one positive integer.", call. = FALSE)
  }

  cache_filename <- paste0("cna_matrix_", sample_name, ".qs2")
  cna_matrix <- cache_load_data(cache_filename, dataset_dir_path)
  id_columns <- c("gene", "chr", "start_pos")
  if (!is.data.frame(cna_matrix) || !all(id_columns %in% names(cna_matrix))) {
    stop("Validated CNA cache does not contain the required matrix columns.", call. = FALSE)
  }
  cell_names <- setdiff(names(cna_matrix), id_columns)
  if (nrow(cna_matrix) == 0L || length(cell_names) == 0L || anyDuplicated(cell_names)) {
    stop("Validated CNA cache has no exportable gene-cell values.", call. = FALSE)
  }
  identifiers <- c(as.character(cna_matrix$gene), cell_names)
  if (any(grepl("[\r\n]", identifiers))) {
    stop(
      "Gene and cell identifiers cannot contain line breaks in a streamed CSV export.",
      call. = FALSE
    )
  }

  manifest <- load_cache_manifest(dataset_dir_path)
  cache_record <- manifest$artifacts[[cache_filename]]
  if (is.null(cache_record)) {
    stop("CNA matrix cache lacks manifest provenance.", call. = FALSE)
  }

  paths <- cna_values_export_paths(results_dir_path, sample_name, create = TRUE)
  temporary_csv <- tempfile(
    pattern = paste0(".", basename(paths$csv), "-"),
    tmpdir = paths$directory,
    fileext = ".csv.gz"
  )
  temporary_metadata <- tempfile(
    pattern = paste0(".", basename(paths$metadata), "-"),
    tmpdir = paths$directory,
    fileext = ".yaml"
  )
  on.exit({
    if (file.exists(temporary_csv)) file.remove(temporary_csv)
    if (file.exists(temporary_metadata)) file.remove(temporary_metadata)
  }, add = TRUE)

  groups <- split(cell_names, ceiling(seq_along(cell_names) / chunk_cell_count))
  written_rows <- 0
  for (index in seq_along(groups)) {
    chunk <- cna_matrix_to_long(cna_matrix, groups[[index]])
    data.table::setcolorder(chunk, CNA_VALUES_EXPORT_COLUMNS)
    data.table::fwrite(
      chunk,
      file = temporary_csv,
      append = index > 1L,
      col.names = index == 1L,
      compress = "gzip"
    )
    written_rows <- written_rows + nrow(chunk)
  }

  expected_rows <- as.numeric(nrow(cna_matrix)) * length(cell_names)
  if (!identical(as.numeric(written_rows), expected_rows)) {
    stop("CNA export wrote an unexpected number of rows.", call. = FALSE)
  }
  validate_cna_values_export_file(temporary_csv, expected_rows)

  metadata <- list(
    schema_version = CNA_VALUES_EXPORT_SCHEMA_VERSION,
    sample = sample_name,
    created_at = cache_timestamp(timestamp),
    implementation = CNA_VALUES_EXPORT_IMPLEMENTATION,
    format = "CSV",
    compression = "gzip",
    columns = as.list(CNA_VALUES_EXPORT_COLUMNS),
    row_count = expected_rows,
    gene_count = nrow(cna_matrix),
    cell_count = length(cell_names),
    csv_filename = basename(paths$csv),
    csv_checksum = .cache_md5(temporary_csv),
    csv_size_bytes = unname(file.info(temporary_csv)$size),
    csv_modified_at = .cache_mtime_token(file.info(temporary_csv)$mtime),
    cache = list(
      filename = cache_filename,
      checksum = cache_record$checksum,
      dependency_fingerprint = cache_record$dependency_fingerprint,
      manifest_revision = manifest$revision
    ),
    import_example = paste0(
      "data.table::fread('", basename(paths$csv),
      "', colClasses = list(character = c('gene', 'chr', 'cell_name')))"
    ),
    note = paste0(
      "Reusable long-format result derived from the validated CNA matrix cache. ",
      "The internal cache remains authoritative and this CSV is never used as pipeline input."
    )
  )
  yaml::write_yaml(metadata, temporary_metadata)
  persisted_metadata <- yaml::read_yaml(temporary_metadata)
  validate_cna_values_export_metadata(persisted_metadata)

  .publish_cna_values_export_pair(
    temporary_csv,
    temporary_metadata,
    paths$csv,
    paths$metadata,
    rename_file = rename_file
  )

  c(metadata, list(paths = paths))
}


cna_values_export_status <- function(sample_name, dataset_dir_path, results_dir_path) {
  paths <- cna_values_export_paths(results_dir_path, sample_name, create = FALSE)
  if (!file.exists(paths$csv) && !file.exists(paths$metadata)) {
    return(list(exists = FALSE, current = FALSE, reason = "No CNA values export exists.", paths = paths))
  }
  if (!file.exists(paths$csv) || !file.exists(paths$metadata)) {
    return(list(exists = TRUE, current = FALSE, reason = "The CNA values export is incomplete.", paths = paths))
  }
  metadata <- tryCatch(yaml::read_yaml(paths$metadata), error = identity)
  if (inherits(metadata, "error")) {
    return(list(exists = TRUE, current = FALSE, reason = conditionMessage(metadata), paths = paths))
  }
  valid_metadata <- tryCatch(validate_cna_values_export_metadata(metadata), error = identity)
  if (inherits(valid_metadata, "error")) {
    return(list(exists = TRUE, current = FALSE, reason = conditionMessage(valid_metadata), paths = paths))
  }
  manifest <- tryCatch(load_cache_manifest(dataset_dir_path, recover = FALSE), error = identity)
  cache_record <- if (inherits(manifest, "error")) NULL else {
    manifest$artifacts[[metadata$cache$filename]]
  }
  csv_size <- unname(file.info(paths$csv)$size)
  csv_modified_at <- .cache_mtime_token(file.info(paths$csv)$mtime)
  current <- !is.null(cache_record) &&
    cache_check_available(metadata$cache$filename, dataset_dir_path, manifest) &&
    identical(as.character(cache_record$checksum), as.character(metadata$cache$checksum)) &&
    identical(
      as.character(cache_record$dependency_fingerprint),
      as.character(metadata$cache$dependency_fingerprint)
    ) && identical(as.numeric(csv_size), as.numeric(metadata$csv_size_bytes)) &&
    identical(as.character(csv_modified_at), as.character(metadata$csv_modified_at))
  list(
    exists = TRUE,
    current = current,
    reason = if (current) {
      "Export matches the current validated CNA matrix cache."
    } else {
      "Export is outdated or does not match the current validated CNA matrix cache."
    },
    metadata = metadata,
    paths = paths
  )
}
