# Console diagnostics only; no workflow state, event logging, or UI callbacks.
new_console_step_timer <- function(prefix, clock = function() proc.time()[["elapsed"]]) {
  #' Report real step durations and cumulative elapsed time at stage boundaries.
  #' @param prefix Human-readable operation/sample identity.
  #' @param clock Monotonic elapsed-seconds clock; injectable for deterministic tests.
  #' @return A function(stage, detail, outcome = NULL). Terminal outcomes close it.
  started <- clock()
  step_started <- started
  current_stage <- NULL
  finished <- FALSE
  function(stage, detail, outcome = NULL) {
    if (finished) return(invisible(NULL))
    now <- clock()
    if (is.null(current_stage)) step_started <<- now
    terminal <- stage %in% c("completed", "failed", "skipped") ||
      (!is.null(outcome) && outcome %in% c("completed", "failed", "skipped"))
    status <- if (terminal) {
      if (is.null(outcome)) stage else outcome
    } else "completed"
    if (!is.null(current_stage) && (terminal || !identical(stage, current_stage))) {
      message(prefix, " | ", current_stage, " | ", status,
        " | step ", sprintf("%.1f", now - step_started), "s",
        " | elapsed ", sprintf("%.1f", now - started), "s")
      step_started <<- now
    }
    message(prefix, " | ", stage, " | ", detail,
      " | elapsed ", sprintf("%.1f", now - started), "s")
    current_stage <<- stage
    finished <<- terminal
    invisible(NULL)
  }
}
