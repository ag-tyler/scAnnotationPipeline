# Local onboarding documents. Checklist progress is user documentation, not
# authoritative scientific pipeline state.

ensure_dataset_standardization_checklist <- function(dataset_dir, template_path) {
  if (!dir.exists(dataset_dir)) {
    stop("Workspace directory does not exist: ", dataset_dir, call. = FALSE)
  }
  checklist_path <- file.path(dataset_dir, "STANDARDIZATION_CHECKLIST.md")
  if (dir.exists(checklist_path)) {
    stop("The checklist path is a directory, not a Markdown file: ", checklist_path, call. = FALSE)
  }
  if (file.exists(checklist_path)) {
    return(list(path = checklist_path, created = FALSE))
  }
  if (!file.exists(template_path)) {
    stop("Checklist template is missing. Restore this repository file: ", template_path, call. = FALSE)
  }
  # Never overwrite a checklist, including one created by another session.
  copied <- file.copy(template_path, checklist_path, overwrite = FALSE)
  if (!isTRUE(copied)) {
    stop("Could not create the workspace checklist. Check write permissions for: ", checklist_path, call. = FALSE)
  }
  list(path = checklist_path, created = TRUE)
}

read_standardization_document <- function(type = c("checklist", "user_guide"),
                                         docs_dir = "docs", dataset_dir = NULL) {
  type <- match.arg(type)
  filename <- if (type == "checklist") "STANDARDIZATION_CHECKLIST.md" else "USER_GUIDE.md"
  source_path <- file.path(docs_dir, filename)
  is_template <- type == "checklist"
  if (type == "checklist" && !is.null(dataset_dir)) {
    local_path <- file.path(dataset_dir, filename)
    if (file.exists(local_path) && !dir.exists(local_path)) {
      source_path <- local_path
      is_template <- FALSE
    } else if (dir.exists(local_path)) {
      stop("The checklist path is a directory, not a Markdown file: ", local_path, call. = FALSE)
    }
  }
  source_path <- normalizePath(source_path, winslash = "/", mustWork = FALSE)
  if (!file.exists(source_path)) {
    stop("Documentation is missing. Restore the file or open it in your editor: ", source_path, call. = FALSE)
  }
  lines <- readLines(source_path, warn = FALSE, encoding = "UTF-8")
  display_lines <- lines
  if (type == "user_guide") {
    start <- which(lines == "## Setting Up a New Dataset")
    if (length(start) != 1L) {
      stop("Dataset Setup section not found. Open the full guide in your editor: ", source_path, call. = FALSE)
    }
    next_heading <- which(seq_along(lines) > start & grepl("^## ", lines))
    end <- if (length(next_heading)) next_heading[1] - 1L else length(lines)
    display_lines <- lines[start:end]
  }
  list(
    type = type,
    title = if (type == "user_guide") "User Guide: Dataset Setup" else if (is_template) {
      "Standardization Checklist — Reference Template"
    } else paste("Standardization Checklist:", basename(dataset_dir)),
    path = source_path,
    dataset_dir = dataset_dir,
    is_template = is_template,
    lines = lines,
    display_lines = display_lines
  )
}
