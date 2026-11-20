# Read-only diagnostics for the ordinary app suite, including ZIP checkouts.
check_test_setup <- function(root = getwd(), browser = TRUE, worker = TRUE, quiet = FALSE) {
  emit <- function(...) if (!quiet) cat(..., "\n", sep = "")
  required_files <- c("DESCRIPTION", "app.R", "general_config.yaml", "tests/testthat.R")
  if (!dir.exists(root) || !all(file.exists(file.path(root, required_files)))) {
    stop("Run this check and the tests from the application root containing app.R, ",
      "DESCRIPTION, general_config.yaml, and tests/testthat.R. Current directory: ",
      root, ". Git metadata is not required for a ZIP checkout.", call. = FALSE)
  }
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  emit("Application root: ", root)
  description <- read.dcf(file.path(root, "DESCRIPTION"))
  problems <- character()
  add_problem <- function(message) problems <<- c(problems, message)
  fields <- intersect(c("Depends", "Imports", "Suggests"), colnames(description))
  specs <- trimws(unlist(strsplit(paste(description[1, fields], collapse = ","), ",")))
  if (!browser) specs <- specs[!grepl("^(shinytest2|chromote)([ (]|$)", specs)]
  specs <- unique(c(specs, "R.utils", if (browser) "chromote"))
  for (spec in specs) {
    match <- regmatches(spec, regexec(
      "^([A-Za-z][A-Za-z0-9.]*)\\s*(?:\\((>=|<=|==|!=|>|<)\\s*([^() ]+)\\))?$", spec, perl = TRUE))[[1L]]
    if (!length(match)) { add_problem(paste("Unrecognized dependency specification:", spec)); next }
    package <- match[[2L]]
    if (package == "R") version <- getRversion()
    else {
      if (!requireNamespace(package, quietly = TRUE)) {
        add_problem(paste0("Missing or unloadable package: ", package, ". Install the README requirements",
          if (package == "matkot") " (pak::pak('m20ty/matkot'))" else "", "."))
        next
      }
      version <- utils::packageVersion(package)
    }
    if (length(match) >= 4L && nzchar(match[[3L]])) {
      comparison <- utils::compareVersion(as.character(version), match[[4L]])
      valid <- switch(match[[3L]], ">=" = comparison >= 0, "<=" = comparison <= 0,
        "==" = comparison == 0, "!=" = comparison != 0, ">" = comparison > 0, "<" = comparison < 0)
      if (!valid) add_problem(paste0(package, " ", version, " does not meet ", spec, "."))
    }
  }
  emit("R: ", as.character(getRversion()), "; package dependencies checked.")

  resource_status <- NULL
  if (requireNamespace("yaml", quietly = TRUE)) {
    config <- tryCatch(yaml::read_yaml(file.path(root, "general_config.yaml")), error = identity)
    if (inherits(config, "error")) add_problem(paste("Could not read general_config.yaml:", conditionMessage(config)))
    else {
      keys <- c("marker_sets", "housekeeping_genes", "mitochondrial_genes", "malignant_markers",
        "cancer_cell_map", "gene_positions", "hgnc_complete_set")
      resources <- config$paths$resources_dir
      if (length(resources) != 1L || !all(keys %in% names(config$resource_files))) {
        add_problem("general_config.yaml must define resources_dir and the seven biological resource filenames.")
      } else {
        absolute <- grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", resources)
        if (!absolute) resources <- file.path(root, resources)
        resource_status <- file.exists(file.path(resources, unlist(config$resource_files[keys])))
        names(resource_status) <- keys
        emit("App biological resources: ", sum(resource_status), "/7 present. ",
          "Synthetic tests supply their own; normal app startup requires these files.")
      }
    }
  }

  utf8 <- isTRUE(l10n_info()[["UTF-8"]])
  locale <- Sys.getlocale("LC_CTYPE")
  emit("Host LC_CTYPE: ", locale, "; UTF-8: ", utf8)
  locale_help <- if (.Platform$OS.type == "windows") {
    "On Windows, clear incompatible inherited LC_ALL/LC_CTYPE values, then use a supported UTF-8 locale such as English_United States.utf8. Do not impose the Linux C.UTF-8 locale on Windows. Restart R and recheck."
  } else {
    "Select an installed UTF-8 locale (check locale -a), for example C.UTF-8 where available, before starting R."
  }
  if (!utf8) add_problem(paste("The host R process is not using UTF-8.", locale_help))
  overrides <- Sys.getenv()
  overrides <- overrides[grepl("^LC_|^LANG$|^LANGUAGE$", names(overrides))]
  if (any(nzchar(overrides))) emit("Inherited locale settings: ",
    paste(paste0(names(overrides)[nzchar(overrides)], "=", overrides[nzchar(overrides)]), collapse = "; "))

  worker_result <- NULL
  if (worker && requireNamespace("processx", quietly = TRUE)) {
    rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
    code <- paste0('ok <- isTRUE(l10n_info()[["UTF-8"]]); ',
      'cat("UTF8=", ok, "\\nLC_CTYPE=", Sys.getlocale("LC_CTYPE"), "\\n", sep=""); ',
      'quit(status=if(ok) 0L else 2L)')
    worker_result <- tryCatch(processx::run(rscript, c("--vanilla", "-e", code),
      error_on_status = FALSE, timeout = 20000), error = identity)
    if (inherits(worker_result, "error")) add_problem(paste("Cannot start an independent R worker:", conditionMessage(worker_result)))
    else if (worker_result$status != 0L || !grepl("UTF8=TRUE", worker_result$stdout, fixed = TRUE) ||
      nzchar(trimws(worker_result$stderr))) {
      add_problem(paste("Independent R worker failed its UTF-8/startup check.",
        trimws(worker_result$stdout), trimws(worker_result$stderr), locale_help))
    } else emit("Independent R worker: UTF-8 startup passed.")
  }

  browser_version <- NULL
  if (browser && requireNamespace("chromote", quietly = TRUE)) {
    browser_path <- tryCatch(chromote::find_chrome(), error = function(error) "")
    if (!length(browser_path) || !nzchar(browser_path) || !file.exists(browser_path)) {
      add_problem("No Chrome/Chromium/Edge executable found. Set CHROMOTE_CHROME to the executable's full path, then rerun the check.")
    } else {
      emit("Browser: ", browser_path)
      browser_version <- tryCatch((function() {
        # Reuse chromote's process-wide browser; closing it here can invalidate
        # later test sessions or leave an asynchronous Browser.close promise.
        instance <- chromote::default_chromote_object()
        session <- chromote::ChromoteSession$new(parent = instance)
        on.exit(try(session$close(), silent = TRUE), add = TRUE)
        session$Browser$getVersion()$product
      })(), error = identity)
      if (inherits(browser_version, "error")) {
        add_problem(paste("Headless browser startup failed:", conditionMessage(browser_version),
          "Check CHROMOTE_CHROME, executable permissions, and whether this environment permits browser/R subprocesses."))
      } else emit("Headless browser connection passed: ", browser_version)
    }
  }
  if (length(problems)) stop("Test setup is not ready:\n - ", paste(problems, collapse = "\n - "), call. = FALSE)
  emit("Test setup ready. No application resources or datasets were modified.")
  invisible(list(root = root, utf8 = utf8, locale = locale, resources = resource_status,
    worker = worker_result, browser = browser_version))
}

if (sys.nframe() == 0L) {
  arguments <- commandArgs(trailingOnly = TRUE)
  if (any(!arguments %in% "--no-browser")) stop("Usage: Rscript scripts/check_test_setup.R [--no-browser]", call. = FALSE)
  check_test_setup(browser = !"--no-browser" %in% arguments)
}
