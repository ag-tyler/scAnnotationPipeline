arguments <- commandArgs(trailingOnly = TRUE)
stopifnot(length(arguments) == 1L)
job <- readRDS(arguments[[1]])
locale <- if (.Platform$OS.type == "windows") "English_United States.utf8" else "C.UTF-8"
stopifnot(nzchar(Sys.setlocale("LC_ALL", locale)))
source(file.path(job$harness_root, "workload.R"))
warnings <- list()
result <- withCallingHandlers(perf_worker(job), warning = function(condition) {
  text <- gsub(job$directory, "<WORKSPACE>", conditionMessage(condition), fixed = TRUE)
  text <- gsub(job$source_root, "<SOURCE>", text, fixed = TRUE)
  warnings[[length(warnings) + 1L]] <<- list(classes = class(condition), message = text)
})
result$warnings <- warnings
saveRDS(result, file.path(job$directory, "result.rds"))
