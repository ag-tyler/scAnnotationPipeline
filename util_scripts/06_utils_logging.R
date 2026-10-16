# ==================================================================================================
# Script: 06_utils_logging.R
# Purpose: Persistent structured event logging for dataset workflows.
# ==================================================================================================


PIPELINE_LOG_SCHEMA_VERSION <- 1L


pipeline_log_paths <- function(dataset_dir_path, logs_dir = "logs") {
  #' Return the persistent pipeline-log paths for a dataset.
  #'
  #' @param dataset_dir_path Dataset workspace directory.
  #' @param logs_dir Log subdirectory name.
  #'
  #' @return A named list containing the directory, JSON Lines, and readable
  #' log paths. This function does not create any files or directories.

  if (
    length(dataset_dir_path) != 1L || is.na(dataset_dir_path) ||
      !nzchar(trimws(dataset_dir_path))
  ) {
    stop("dataset_dir_path must be one non-empty path.", call. = FALSE)
  }
  if (length(logs_dir) != 1L || is.na(logs_dir) || !nzchar(trimws(logs_dir))) {
    stop("logs_dir must be one non-empty directory name.", call. = FALSE)
  }

  log_dir_path <- file.path(dataset_dir_path, logs_dir)
  list(
    directory = log_dir_path,
    structured = file.path(log_dir_path, "pipeline_events.jsonl"),
    readable = file.path(log_dir_path, "pipeline.log")
  )
}


setup_pipeline_log_dir <- function(dataset_dir_path, logs_dir = "logs") {
  #' Create and return the dataset log directory.

  paths <- pipeline_log_paths(dataset_dir_path, logs_dir)
  dir.create(paths$directory, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(paths$directory)) {
    stop("Could not create pipeline log directory: ", paths$directory, call. = FALSE)
  }
  paths
}


format_pipeline_timestamp <- function(timestamp = Sys.time()) {
  #' Format a pipeline timestamp as UTC ISO 8601 with milliseconds.

  if (length(timestamp) != 1L || is.na(timestamp)) {
    stop("timestamp must contain one non-missing value.", call. = FALSE)
  }
  timestamp <- as.POSIXct(timestamp, tz = "UTC")
  if (is.na(timestamp)) {
    stop("timestamp could not be converted to POSIXct.", call. = FALSE)
  }
  paste0(format(timestamp, "%Y-%m-%dT%H:%M:%OS3", tz = "UTC"), "Z")
}


.pipeline_event_text <- function(value, field, optional = FALSE) {
  if (is.null(value) && optional) return(NULL)
  if (length(value) != 1L || is.na(value) || !nzchar(trimws(as.character(value)))) {
    stop(field, " must be one non-empty value.", call. = FALSE)
  }
  trimws(as.character(value))
}


.append_utf8_line <- function(path, line) {
  connection <- file(path, open = "ab")
  on.exit(close(connection), add = TRUE)
  writeBin(charToRaw(paste0(enc2utf8(line), "\n")), connection)
  invisible(path)
}


log_pipeline_event <- function(
  dataset_dir_path,
  dataset,
  stage,
  event_type,
  outcome,
  sample = NULL,
  parameters = list(),
  reason = NULL,
  timestamp = Sys.time(),
  logs_dir = "logs"
) {
  #' Append one structured and readable pipeline event.
  #'
  #' @description The canonical record is one JSON object per line in
  #' `pipeline_events.jsonl`. A compact companion line is appended to
  #' `pipeline.log` for convenient reading without a JSON parser.
  #'
  #' @param dataset_dir_path Dataset workspace directory.
  #' @param dataset Canonical dataset identifier.
  #' @param stage Pipeline stage, for example `clustering` or `cna`.
  #' @param event_type Stable machine-readable event name.
  #' @param outcome Event result such as `started`, `completed`, `saved`,
  #' `failed`, `skipped`, `reused`, or `invalidated`.
  #' @param sample Optional canonical sample identifier.
  #' @param parameters Named list of relevant parameters or summary counts.
  #' Do not include cell-level data or unnecessary private paths.
  #' @param reason Actionable reason. Required for `failed` and `skipped`.
  #' @param timestamp Event time; defaults to the current time.
  #' @param logs_dir Log subdirectory name.
  #'
  #' @return The persisted event, invisibly.

  dataset <- .pipeline_event_text(dataset, "dataset")
  stage <- .pipeline_event_text(stage, "stage")
  event_type <- .pipeline_event_text(event_type, "event_type")
  outcome <- .pipeline_event_text(outcome, "outcome")
  sample <- .pipeline_event_text(sample, "sample", optional = TRUE)
  reason <- .pipeline_event_text(reason, "reason", optional = TRUE)

  if (!is.list(parameters) || (length(parameters) > 0L && is.null(names(parameters)))) {
    stop("parameters must be a named list.", call. = FALSE)
  }
  if (outcome %in% c("failed", "skipped") && is.null(reason)) {
    stop("A non-empty reason is required for failed or skipped events.", call. = FALSE)
  }

  event <- list(
    schema_version = PIPELINE_LOG_SCHEMA_VERSION,
    timestamp = format_pipeline_timestamp(timestamp),
    dataset = dataset,
    sample = sample,
    stage = stage,
    event_type = event_type,
    outcome = outcome,
    parameters = parameters,
    reason = reason
  )
  paths <- setup_pipeline_log_dir(dataset_dir_path, logs_dir)
  structured_line <- jsonlite::toJSON(
    event,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    POSIXt = "ISO8601"
  )
  .append_utf8_line(paths$structured, structured_line)

  readable_values <- c(
    event$timestamp,
    toupper(event$outcome),
    event$stage,
    event$event_type,
    paste0("dataset=", event$dataset),
    if (!is.null(event$sample)) paste0("sample=", event$sample),
    if (!is.null(event$reason)) paste0("reason=", event$reason),
    if (length(event$parameters) > 0L) {
      paste0(
        "parameters=",
        jsonlite::toJSON(event$parameters, auto_unbox = TRUE, null = "null", na = "null")
      )
    }
  )
  readable_line <- paste(gsub("[\r\n]+", " ", readable_values), collapse = " | ")
  .append_utf8_line(paths$readable, readable_line)

  invisible(event)
}


record_pipeline_event <- function(..., strict = FALSE) {
  #' Persist an event without allowing a logging failure to corrupt workflow output.
  #'
  #' @param ... Arguments forwarded to `log_pipeline_event()`.
  #' @param strict If `TRUE`, propagate logging errors. Otherwise warn and return
  #' `NULL`, which is appropriate after a scientific output has already saved.

  tryCatch(
    log_pipeline_event(...),
    error = function(error) {
      if (isTRUE(strict)) stop(error)
      warning(
        "Could not persist pipeline event: ", conditionMessage(error),
        call. = FALSE
      )
      invisible(NULL)
    }
  )
}


record_state_event <- function(
  state,
  stage,
  event_type,
  outcome,
  sample = NULL,
  parameters = list(),
  reason = NULL,
  strict = FALSE
) {
  #' Persist an event using the currently loaded application state.

  dataset_dir_path <- state$dataset_dir_path
  if (is.null(dataset_dir_path) || !nzchar(dataset_dir_path)) {
    if (isTRUE(strict)) {
      stop("No dataset workspace is loaded for persistent logging.", call. = FALSE)
    }
    warning("No dataset workspace is loaded for persistent logging.", call. = FALSE)
    return(invisible(NULL))
  }

  dataset <- state$dataset_config$project_info$dataset_id
  if (is.null(dataset) || !nzchar(trimws(dataset))) {
    dataset <- basename(normalizePath(dataset_dir_path, winslash = "/", mustWork = FALSE))
  }

  record_pipeline_event(
    dataset_dir_path = dataset_dir_path,
    dataset = dataset,
    sample = sample,
    stage = stage,
    event_type = event_type,
    outcome = outcome,
    parameters = parameters,
    reason = reason,
    strict = strict
  )
}


read_pipeline_events <- function(dataset_dir_path, logs_dir = "logs") {
  #' Read and validate the structured event history for a dataset.
  #'
  #' @return A list of event lists in append order. Missing logs return an empty
  #' list; malformed JSON raises an error naming the affected line.

  path <- pipeline_log_paths(dataset_dir_path, logs_dir)$structured
  if (!file.exists(path)) return(list())

  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[nzchar(trimws(lines))]
  lapply(seq_along(lines), function(index) {
    tryCatch(
      jsonlite::fromJSON(lines[[index]], simplifyVector = FALSE),
      error = function(error) {
        stop(
          "Malformed pipeline event at line ", index, ": ",
          conditionMessage(error),
          call. = FALSE
        )
      }
    )
  })
}
