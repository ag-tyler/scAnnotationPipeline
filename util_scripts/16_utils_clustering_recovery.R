# Clustering is synchronous in the Shiny R process. Keep live invocation tokens
# across sessions; PID plus creation time distinguishes restarts/PID reuse.
if (!exists(".clustering_executions", inherits = FALSE)) {
  .clustering_executions <- new.env(parent = emptyenv())
}

begin_clustering_execution <- function(session_id) {
  token <- basename(tempfile("clustering-"))
  owner <- list(host = unname(Sys.info()[["nodename"]]), pid = Sys.getpid(),
    process_started_at = sprintf("%.6f", as.numeric(ps::ps_create_time(ps::ps_handle()))),
    session_id = session_id, token = token)
  .clustering_executions[[token]] <- TRUE
  owner
}

end_clustering_execution <- function(owner) {
  if (exists(owner$token, .clustering_executions, inherits = FALSE)) {
    rm(list = owner$token, envir = .clustering_executions)
  }
  invisible(TRUE)
}

clustering_execution_status <- function(owner) {
  scalar <- function(value) typeof(value) %in% c("character", "integer", "double") &&
    length(value) == 1L && !is.na(value) && nzchar(as.character(value))
  if (!is.list(owner) || !all(vapply(owner[c("host", "pid", "process_started_at", "token")], scalar, logical(1))) ||
      !all(c("host", "pid", "process_started_at", "token") %in% names(owner))) return("unknown")
  if (!identical(owner$host, unname(Sys.info()[["nodename"]]))) return("unknown")
  pid <- suppressWarnings(as.numeric(owner$pid))
  created <- suppressWarnings(as.numeric(owner$process_started_at))
  if (!is.finite(pid) || pid < 1 || pid != floor(pid) || !is.finite(created)) return("unknown")
  tryCatch({
    handle <- ps::ps_handle(pid)
    if (!ps::ps_is_running(handle) || abs(as.numeric(ps::ps_create_time(handle)) - created) > 0.01) return("ended")
    if (pid == Sys.getpid()) {
      if (exists(owner$token, .clustering_executions, inherits = FALSE)) "live" else "ended"
    } else "live"
  }, error = function(error) {
    if (inherits(error, "no_such_process")) "ended" else "unknown"
  })
}

interrupted_clustering_candidates <- function(state) {
  samples <- names(state$samples)
  samples[vapply(samples, function(sample) {
    identical(get_pipeline_step(state, "clustering", sample)$status, "in_progress") &&
      !identical(clustering_execution_status(get_pipeline_step(state, "clustering", sample)$details$execution_owner), "live")
  }, logical(1))]
}

reconcile_interrupted_clustering <- function(state, state_path, confirmed_samples = character()) {
  recovered <- character()
  if (!all(confirmed_samples %in% names(state$samples))) stop("Recovery sample selection changed; reload and review again.", call. = FALSE)
  for (sample in names(state$samples)) {
    if (length(confirmed_samples) && !(sample %in% confirmed_samples)) next
    record <- get_pipeline_step(state, "clustering", sample)
    confirmed <- sample %in% confirmed_samples
    if (!identical(record$status, "in_progress")) {
      if (confirmed) stop("Clustering status changed; reload and review recovery again.", call. = FALSE)
      next
    }
    ownership <- clustering_execution_status(record$details$execution_owner)
    if (confirmed && identical(ownership, "live")) stop("The original clustering process is still active; recovery is blocked.", call. = FALSE)
    if (!identical(ownership, "ended") && !confirmed) next
    reason <- "Clustering was interrupted before completion. Retry clustering, then review and save a resolution and rerun downstream analysis."
    state <- mark_pipeline_steps_stale(state, "clustering", reason, sample)
    state <- update_downstream_stale_reason(state, "clustering", sample, reason)
    recovery <- list(
        attempt = record$attempt, started_at = record$started_at,
        execution_owner = record$details$execution_owner,
        recovered_at = pipeline_state_timestamp(Sys.time()),
        mode = if (confirmed) "explicit_confirmation" else "owner_ended")
    history <- record$details$interruption_recoveries
    history[[paste0("attempt_", record$attempt)]] <- recovery
    state <- transition_pipeline_step(state, "clustering", "failed", sample,
      reason = reason, details = list(interruption_recovery = recovery,
        interruption_recoveries = history))
    recovered <- c(recovered, sample)
  }
  if (length(recovered)) state <- save_pipeline_state_at_path(state, state_path)
  attr(state, "clustering_recovered") <- recovered
  state
}
