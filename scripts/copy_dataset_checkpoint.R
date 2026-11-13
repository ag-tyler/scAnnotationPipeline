# Copy an ACTIVE app workspace to an independent, resumable checkpoint.
# Stop the app and save all edits before running. Run from the repository root.
# Edit settings and use: Rscript scripts/copy_dataset_checkpoint.R
# Or source this file, then call copy_dataset_checkpoint(source_dir, output_dir).
# This copies a workspace, not a processed_data input or a Review Snapshot.

checkpoint_settings <- list(
  source_dir = "datasets/Tang_Demo_Working",
  output_dir = "datasets/Tang_Demo_01_Clustered",
  app_dir = ".",
  # Normally NULL. If a transferred manifest uses an unfamiliar old root,
  # supply its original workspace path (Windows paths are accepted on a Mac).
  original_source_dir = NULL
)

copy_dataset_checkpoint <- function(source_dir, output_dir, app_dir = ".", original_source_dir = NULL) {
  fail <- function(...) stop(..., call. = FALSE)
  for (package in c("yaml", "fs", "data.table", "Matrix", "qs2", "docstring")) {
    if (!requireNamespace(package, quietly = TRUE)) fail("Install the required R package: ", package)
  }
  text_path <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  if (!text_path(source_dir) || !dir.exists(source_dir)) fail("source_dir must be an existing workspace.")
  if (!text_path(output_dir)) fail("output_dir must be a new workspace path.")
  if (!text_path(app_dir) || !dir.exists(app_dir)) fail("app_dir must be the application repository.")
  if (!is.null(original_source_dir) && !text_path(original_source_dir)) {
    fail("original_source_dir must be NULL or the old workspace path.")
  }
  slash <- function(path) sub("/+$", "", gsub("\\", "/", path, fixed = TRUE))
  source_dir <- as.character(fs::path_real(source_dir))
  app_dir <- as.character(fs::path_real(app_dir))
  # Resolve existing ancestors, including symlinks, before checking containment.
  resolve <- function(path) {
    path <- path.expand(path)
    if (file.exists(path)) return(as.character(fs::path_real(path)))
    parent <- dirname(path)
    if (identical(parent, path)) fail("Cannot resolve output path: ", path)
    file.path(resolve(parent), basename(path))
  }
  output_dir <- slash(resolve(output_dir))
  inside <- function(path, root) {
    # Conservative case-insensitive check also protects default macOS volumes.
    path <- tolower(slash(path)); root <- tolower(slash(root))
    identical(path, root) || startsWith(path, paste0(root, "/"))
  }
  if (inside(output_dir, source_dir) || inside(source_dir, output_dir)) {
    fail("Source and output must be separate, non-nested workspace folders.")
  }
  if (file.exists(output_dir)) fail("Output already exists; choose a new folder: ", output_dir)
  portable_name <- function(name) {
    text_path(name) && name == trimws(name) && !name %in% c(".", "..") &&
      !grepl('[<>:"/\\\\|?*[:cntrl:]]', name) && !grepl("[. ]$", name) &&
      !grepl("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\\.)", name, ignore.case = TRUE)
  }
  new_id <- basename(output_dir)
  if (!portable_name(new_id)) fail("Output folder name must be a portable dataset identifier.")
  general_path <- file.path(app_dir, "general_config.yaml")
  if (!file.exists(general_path)) fail("app_dir must contain general_config.yaml.")
  general <- yaml::read_yaml(general_path)
  config_names <- general$config_files
  for (key in c("dataset", "selected", "state")) {
    if (!portable_name(config_names[[key]])) fail("Invalid configured filename: ", key)
  }
  processed_name <- general$dataset_paths$processed_dir
  if (!portable_name(processed_name)) fail("Configured processed_dir must be a portable folder name.")

  # Load validators into a private environment; do not start Shiny or source
  # app.R, and never call a repairing/loading helper against the source.
  helpers <- new.env(parent = globalenv())
  helpers$.datatable.aware <- TRUE
  for (name in c("01_utils_io.R", "03_utils_misc.R", "04_utils_caching.R",
                 "07_utils_state.R", "11_utils_storage.R", "17_utils_prepared_data.R")) {
    path <- file.path(app_dir, "util_scripts", name)
    if (!file.exists(path)) fail("Missing application helper: ", path)
    sys.source(path, envir = helpers)
  }
  read_yaml <- function(path) {
    if (!file.exists(path) || dir.exists(path)) fail("Missing workspace file: ", path)
    yaml::read_yaml(path)
  }
  config <- read_yaml(file.path(source_dir, config_names$dataset))
  old_id <- config$project_info$dataset_id
  if (!text_path(old_id)) fail("Source dataset configuration has no dataset_id.")
  selected <- read_yaml(file.path(source_dir, config_names$selected))
  state <- read_yaml(file.path(source_dir, config_names$state))
  helpers$validate_pipeline_state(state, old_id)
  records <- c(state$dataset_steps, unlist(state$samples, recursive = FALSE))
  if (any(vapply(records, function(record) identical(record$status, "in_progress"), logical(1)))) {
    fail("A pipeline stage is in progress. Finish or recover it, save edits, and stop the app first.")
  }
  storage_name <- "storage_state.yaml"
  storage_path <- file.path(source_dir, storage_name)
  storage <- if (file.exists(storage_path)) read_yaml(storage_path) else helpers$new_dataset_storage_state(old_id)
  helpers$validate_dataset_storage_state(storage, old_id)
  if (!identical(storage$status, "active")) {
    fail("Only active workspaces can be checkpointed. Archived/cleaning workspaces cannot provide resumable caches.")
  }
  checked <- helpers$check_prepared_data(file.path(source_dir, processed_name), config$std_names)
  if (!checked$valid) fail(checked$message)
  helpers$validate_pipeline_state(state, old_id, checked$samples$sample)

  # Walk without following links/junctions, and reject unfinished operations.
  inventory <- function(root) {
    files <- character()
    directories <- character()
    walk <- function(folder) {
      for (path in as.character(fs::dir_ls(folder, all = TRUE, recurse = FALSE))) {
        if (fs::is_link(path) || !inside(as.character(fs::path_real(path)), root)) {
          fail("Workspace contains a link or escaping path: ", path)
        }
        if (grepl("[.](lock|tmp|temp|part)$|^cache[.]retired|^[.]cache[-_]", basename(path), ignore.case = TRUE)) {
          fail("Workspace contains a lock/temporary operation artifact; finish the operation first: ", path)
        }
        relative <- substring(slash(path), nchar(slash(root)) + 2L)
        if (dir.exists(path)) {
          directories <<- c(directories, relative)
          walk(path)
        } else if (fs::is_file(path)) files <<- c(files, relative)
        else fail("Workspace contains a non-regular file: ", path)
      }
    }
    walk(root)
    files <- sort(files)
    info <- file.info(file.path(root, files))
    list(directories = sort(directories), files = files, sizes = unname(info$size),
      mtimes = unname(as.numeric(info$mtime)))
  }
  before <- inventory(source_dir)
  source_paths <- file.path(source_dir, before$files)
  message("Verifying source files (", length(source_paths), " files)...")
  original_hashes <- unname(tools::md5sum(source_paths))
  if (anyNA(original_hashes)) fail("Could not checksum every source file.")

  parent <- dirname(output_dir)
  if (!dir.exists(parent) && !dir.create(parent, recursive = TRUE)) fail("Cannot create output parent.")
  staging <- tempfile(".checkpoint-copy-", tmpdir = parent)
  if (!dir.create(staging)) fail("Cannot create staging folder.")
  staging <- as.character(fs::path_real(staging))
  # Cleanup is restricted to this freshly created sibling staging directory.
  stopifnot(identical(dirname(staging), as.character(fs::path_real(parent))))
  on.exit(if (dir.exists(staging)) unlink(staging, recursive = TRUE), add = TRUE)
  for (relative in before$directories) {
    if (!dir.create(file.path(staging, relative), recursive = TRUE, showWarnings = FALSE)) {
      if (!dir.exists(file.path(staging, relative))) fail("Cannot create copied directory: ", relative)
    }
  }
  message("Copying workspace (", round(sum(before$sizes) / 1024^2, 1), " MB)...")
  for (relative in before$files) {
    if (!file.copy(file.path(source_dir, relative), file.path(staging, relative), copy.date = TRUE)) {
      fail("Could not copy: ", relative)
    }
  }
  copied_paths <- file.path(staging, before$files)
  copied_hashes <- unname(tools::md5sum(copied_paths))
  if (!identical(original_hashes, copied_hashes)) fail("Copied file checksums differ from the source.")
  # Copy timestamps where supported. Manifest metadata below records the actual
  # destination timestamps, including filesystem precision changes.
  for (index in seq_along(copied_paths)) {
    Sys.setFileTime(copied_paths[[index]], as.POSIXct(before$mtimes[[index]], origin = "1970-01-01", tz = "UTC"))
  }
  hash_index <- stats::setNames(copied_hashes, before$files)
  checksum <- function(relative) {
    if (!relative %in% names(hash_index)) fail("Cache dependency is not in this workspace: ", relative)
    unname(hash_index[[relative]])
  }
  rewritten <- character()
  write_yaml <- function(value, relative) {
    yaml::write_yaml(value, file.path(staging, relative), precision = 17)
    rewritten <<- unique(c(rewritten, relative))
  }
  # Rename primary and recovery metadata. Historical log messages and source
  # scripts stay byte-for-byte intact; the separate provenance file explains it.
  for (relative in c(config_names$dataset, paste0(config_names$dataset, ".bak"))) {
    if (!file.exists(file.path(staging, relative))) next
    value <- read_yaml(file.path(staging, relative))
    if (!identical(value$project_info$dataset_id, old_id)) fail("Inconsistent dataset ID in ", relative)
    value$project_info$dataset_id <- new_id
    write_yaml(value, relative)
  }
  for (relative in c(config_names$state, paste0(config_names$state, ".bak"),
                     storage_name, paste0(storage_name, ".bak"))) {
    if (!file.exists(file.path(staging, relative))) next
    value <- read_yaml(file.path(staging, relative))
    if (startsWith(relative, storage_name)) helpers$validate_dataset_storage_state(value, old_id)
    else helpers$validate_pipeline_state(value, old_id)
    value$dataset_id <- new_id
    write_yaml(value, relative)
  }
  if (!file.exists(storage_path)) {
    storage$dataset_id <- new_id
    write_yaml(storage, storage_name)
  }

  dependency_relative <- function(path, sample, key) {
    roots <- c(source_dir, original_source_dir)
    if (text_path(path)) {
      path <- slash(path)
      for (root in roots) {
        root <- slash(root)
        if (inside(path, root)) {
          relative <- substring(path, nchar(root) + 2L)
          if (relative %in% before$files) return(relative)
        }
      }
    }
    # Auto-recognize standardized expression/gene paths after a Windows/Mac
    # move, without depending on the old machine's files still being present.
    filename <- switch(key, expression = config$std_names$expmat, genes = config$std_names$genes, NULL)
    if (text_path(sample) && text_path(filename)) {
      relative <- paste(processed_name, sample, filename, sep = "/")
      if ((!text_path(path) || endsWith(path, paste0("/", relative))) && relative %in% before$files) {
        return(relative)
      }
    }
    fail("Cannot map a cache dependency into this workspace: ", path,
      ". For a relocated workspace, supply original_source_dir.")
  }
  rebase_record <- function(record, filename, current = TRUE, backup_artifact = FALSE) {
    if (!is.null(record$dataset_root)) record$dataset_root <- output_dir
    original_fingerprint <- record$dependency_fingerprint
    if (!is.null(original_fingerprint) && !identical(
      helpers$cache_dependency_fingerprint(record$dependencies), original_fingerprint)) {
      fail("Cache dependency fingerprint is invalid: ", filename, ". Repair/rerun the source cache first.")
    }
    for (key in names(record$dependencies$files)) {
      dependency <- record$dependencies$files[[key]]
      relative <- dependency_relative(dependency$path, record$sample, key)
      actual <- file.info(file.path(staging, relative))
      matches <- identical(as.numeric(actual$size), as.numeric(dependency$size_bytes)) &&
        identical(checksum(relative), as.character(dependency$checksum))
      if (current && !matches) fail("Cache input no longer matches its recorded checksum: ", relative)
      dependency$path <- paste(output_dir, relative, sep = "/")
      if (matches) dependency$modified_at <- helpers$.cache_mtime_token(actual$mtime)
      record$dependencies$files[[key]] <- dependency
    }
    relative <- paste0("cache/", filename, if (backup_artifact) ".bak" else "")
    if (relative %in% before$files) {
      info <- file.info(file.path(staging, relative))
      matches <- identical(as.numeric(info$size), as.numeric(record$size_bytes)) &&
        identical(checksum(relative), as.character(record$checksum))
      if (current && !matches) fail("Cache artifact checksum/size is invalid: ", filename)
      if (matches) record$modified_at <- helpers$.cache_mtime_token(info$mtime)
    } else if (current) fail("A registered cache artifact is missing: ", filename)
    if (!is.null(record$previous)) {
      record$previous <- rebase_record(record$previous, filename, current = FALSE, backup_artifact = TRUE)
    }
    if (!is.null(original_fingerprint) &&
        !identical(helpers$cache_dependency_fingerprint(record$dependencies), original_fingerprint)) {
      fail("Rebasing unexpectedly changed scientific cache dependencies: ", filename)
    }
    record
  }
  manifest_file <- "cache/cache_manifest.yaml"
  for (relative in c(manifest_file, paste0(manifest_file, ".bak"))) {
    if (!file.exists(file.path(staging, relative))) next
    manifest <- read_yaml(file.path(staging, relative))
    helpers$validate_cache_manifest(manifest)
    for (filename in names(manifest$artifacts)) {
      if (!identical(basename(filename), filename)) fail("Unsafe cache artifact filename: ", filename)
      manifest$artifacts[[filename]] <- rebase_record(manifest$artifacts[[filename]], filename,
        current = identical(relative, manifest_file))
    }
    write_yaml(manifest, relative)
  }

  message("Validating copied state, caches and recorded dependencies...")
  copied_config <- read_yaml(file.path(staging, config_names$dataset))
  copied_state <- read_yaml(file.path(staging, config_names$state))
  copied_storage <- read_yaml(file.path(staging, storage_name))
  copied_check <- helpers$check_prepared_data(file.path(staging, processed_name), copied_config$std_names)
  if (!copied_check$valid) fail(copied_check$message)
  helpers$validate_pipeline_state(copied_state, new_id, copied_check$samples$sample)
  helpers$validate_dataset_storage_state(copied_storage, new_id)
  manifest <- if (file.exists(file.path(staging, manifest_file))) read_yaml(file.path(staging, manifest_file))
    else helpers$new_cache_manifest()
  untracked <- setdiff(list.files(file.path(staging, "cache"), pattern = "[.]qs2$"), names(manifest$artifacts))
  if (length(untracked)) fail("Untracked source cache artifacts: ", paste(untracked, collapse = ", "))
  for (filename in names(manifest$artifacts)) {
    record <- manifest$artifacts[[filename]]
    for (dependency in record$dependencies$artifacts) {
      upstream <- manifest$artifacts[[dependency$filename]]
      if (is.null(upstream) || !identical(upstream$checksum, dependency$checksum) ||
          !identical(upstream$dependency_fingerprint, dependency$dependency_fingerprint)) {
        fail("An upstream cache dependency is stale: ", filename)
      }
    }
    # One object at a time, one decompression thread: no pipeline recomputation.
    object <- helpers$cache_load_data(filename, staging, nthreads = 1L, recover = FALSE)
    rm(object)
    invisible(gc())
  }
  # Source paths point to the FINAL location, which does not exist yet. Supply
  # a staging-only manifest for the app's metadata reconciliation check.
  validation_manifest <- manifest
  stage_paths <- function(record) {
    for (key in names(record$dependencies$files)) {
      path <- record$dependencies$files[[key]]$path
      relative <- substring(path, nchar(output_dir) + 2L)
      record$dependencies$files[[key]]$path <- file.path(staging, relative)
    }
    record
  }
  validation_manifest$artifacts <- lapply(manifest$artifacts, stage_paths)
  # Validation runs in a temporary directory. Keep automatic relocation from
  # persisting staging paths over the final paths already verified above.
  helpers$reconcile_cache_manifest_location <- function(dataset_dir_path, manifest) manifest
  helpers$cache_check_available <- local({
    original <- helpers$cache_check_available
    function(data_file_name, dataset_dir_path, manifest = NULL) {
      original(data_file_name, dataset_dir_path, validation_manifest)
    }
  })
  reconciled <- helpers$reconcile_pipeline_state_dependencies(copied_state)
  if (length(attr(reconciled, "dependency_changes"))) fail("Source workflow prerequisites are inconsistent.")
  reconciled <- helpers$reconcile_pipeline_state_cache(copied_state, copied_check$paths_list,
    copied_config, selected, staging, gene_positions = NULL)
  if (length(attr(reconciled, "cache_changes"))) {
    fail("Copied stages would become stale: ", paste(attr(reconciled, "cache_changes"), collapse = ", "))
  }
  # Ensure the source did not change during copying/validation.
  if (!identical(before, inventory(source_dir)) ||
      !identical(original_hashes, unname(tools::md5sum(source_paths)))) {
    fail("Source changed during copying. Stop the app and retry into a new folder.")
  }
  status_table <- lapply(copied_state$samples, function(steps) lapply(steps, function(step) step$status))
  write_yaml(list(schema_version = 1L, created_at = helpers$pipeline_state_timestamp(),
    source_dir = source_dir, source_dataset_id = old_id, dataset_id = new_id,
    output_dir = output_dir, original_source_dir = original_source_dir,
    source_file_count = length(before$files), copied_bytes = sum(before$sizes),
    cache_artifact_count = length(manifest$artifacts), rewritten_files = rewritten,
    verification = "Copied bytes, cache integrity/structure, recorded dependencies and workflow reconciliation; no recomputation.",
    historical_logs = "Preserved unchanged; earlier events retain their original dataset IDs and paths.",
    sample_steps = status_table), "checkpoint_copy.yaml")
  if (file.exists(output_dir) || !file.rename(staging, output_dir)) {
    fail("Cannot publish checkpoint without overwriting an existing destination: ", output_dir)
  }
  message("Verified checkpoint created: ", output_dir)
  message("Dataset ID: ", new_id, ". Reopen the app to select it; keep master checkpoints untouched.")
  invisible(list(path = output_dir, dataset_id = new_id, samples = copied_check$samples$sample,
    cache_artifacts = length(manifest$artifacts), sample_steps = status_table))
}

if (sys.nframe() == 0L) do.call(copy_dataset_checkpoint, checkpoint_settings)
