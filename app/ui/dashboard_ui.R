# Dashboard and reference-data UI.


pipeline_overview_sample_tooltip <- function(sample_names, max_names = 15L) {
  sample_names <- as.character(sample_names)
  shown_names <- utils::head(sample_names, max_names)
  omitted_count <- length(sample_names) - length(shown_names)
  tags$div(
    strong(paste0("Samples in this status (", length(sample_names), ")")),
    tags$ul(
      class = "list-unstyled mb-0 mt-1",
      lapply(shown_names, tags$li)
    ),
    if (omitted_count > 0L) {
      div(class = "mt-1", paste0("… and ", omitted_count, " more. See sample details for the full list."))
    }
  )
}


pipeline_overview_status_badge <- function(record, count = NULL, sample_names = NULL) {
  presentation <- pipeline_status_presentation(record)
  label <- if (is.null(count)) {
    presentation$label
  } else {
    paste(count, presentation$label)
  }
  badge <- span(
    class = paste0(
      "badge text-bg-", presentation$class,
      " pipeline-status-badge pipeline-status-", presentation$status
    ),
    tabindex = if (!is.null(sample_names)) "0" else NULL,
    icon(presentation$icon, class = "me-1", `aria-hidden` = "true"),
    label
  )
  if (is.null(sample_names)) {
    return(badge)
  }
  bslib::tooltip(
    badge,
    pipeline_overview_sample_tooltip(sample_names),
    placement = "top"
  )
}


pipeline_overview_status_cell <- function(record) {
  div(
    class = paste0("pipeline-status-cell pipeline-status-", record$status),
    pipeline_overview_status_badge(record),
    if (!is.null(record$reason) && nzchar(record$reason)) {
      div(class = "small text-body-secondary mt-1", record$reason)
    }
  )
}


pipeline_status_overview_ui <- function(summary) {
  standardization <- pipeline_status_presentation(summary$standardization)
  stage_cards <- lapply(summary$stages, function(stage) {
    nonzero <- which(stage$counts > 0L)
    card(
      class = "h-100 pipeline-overview-stage-card",
      card_header(strong(stage$label)),
      card_body(
        if (length(nonzero) == 0L) {
          span(class = "text-body-secondary", "No samples")
        } else {
          tags$div(
            class = "d-flex flex-wrap gap-1",
            lapply(nonzero, function(index) {
              status <- names(stage$counts)[[index]]
              pipeline_overview_status_badge(
                new_pipeline_overview_record(status),
                stage$counts[[index]],
                stage$samples_by_status[[status]]
              )
            })
          )
        }
      )
    )
  })

  details_content <- if (summary$sample_count == 0L) {
    div(class = "alert alert-secondary mt-3 mb-0", "No samples are configured for this dataset.")
  } else {
    tags$div(
      class = "table-responsive mt-3",
      tags$table(
        class = "table table-sm table-striped align-middle pipeline-overview-table",
        tags$thead(tags$tr(
          tags$th(scope = "col", "Sample"),
          lapply(summary$stages, function(stage) tags$th(scope = "col", stage$label)),
          tags$th(scope = "col", "Next action")
        )),
        tags$tbody(lapply(summary$samples, function(sample_summary) {
          tags$tr(
            tags$th(scope = "row", sample_summary$name),
            lapply(sample_summary$records, function(record) {
              tags$td(pipeline_overview_status_cell(record))
            }),
            tags$td(class = "pipeline-next-action", sample_summary$next_action$label)
          )
        }))
      )
    )
  }

  card(
    class = "mb-4 pipeline-status-overview",
    card_header(
      div(
        class = "d-flex flex-wrap justify-content-between align-items-center gap-2",
        h4("Pipeline Status", class = "mb-0"),
        span(
          class = paste0("badge text-bg-", standardization$class),
          icon(standardization$icon, class = "me-1", `aria-hidden` = "true"),
          paste0("Standardization: ", standardization$label)
        )
      )
    ),
    card_body(
      div(
        class = "mb-3",
        strong(summary$dataset_id),
        span(
          class = "text-body-secondary ms-2",
          paste0(summary$sample_count, if (summary$sample_count == 1L) " sample" else " samples")
        )
      ),
      if (!is.null(summary$standardization$reason) && nzchar(summary$standardization$reason)) {
        div(class = "small text-body-secondary mb-3", summary$standardization$reason)
      },
      if (!is.null(summary$attention)) {
        div(
          class = "alert alert-light border py-2",
          strong("Next attention: "),
          summary$attention$name,
          " — ",
          summary$attention$next_action$label
        )
      } else if (summary$sample_count > 0L) {
        div(class = "alert alert-success py-2", "All samples have completed or intentionally skipped their remaining steps.")
      },
      div(
        class = "row row-cols-1 row-cols-md-2 row-cols-xl-3 g-2",
        lapply(stage_cards, function(stage_card) div(class = "col", stage_card))
      ),
      tags$details(
        class = "mt-3 pipeline-overview-details",
        tags$summary(class = "btn btn-outline-secondary", "Show sample details"),
        details_content
      )
    )
  )
}


dataset_cleanup_export_warning_ui <- function(readiness) {
  warnings <- unlist(readiness$warnings, use.names = FALSE)
  if (length(warnings) == 0L) return(NULL)
  div(class = "alert alert-warning py-2",
    strong("Optional CNA values exports"),
    lapply(warnings, function(warning) p(warning, class = "mb-0"))
  )
}


dataset_storage_card_ui <- function(storage_state, readiness = NULL, archive_audit = NULL) {
  status <- storage_state$status
  cleanup <- storage_state$details$cleanup
  cache_size <- if (!is.null(readiness)) {
    readiness$cache$size_bytes
  } else if (!is.null(cleanup$cache_size_bytes)) {
    cleanup$cache_size_bytes
  } else 0
  recovered <- storage_state$details$recovered_bytes

  presentation <- switch(
    status,
    active = if (!is.null(readiness) && isTRUE(readiness$ready)) {
      list(class = "success", icon = "box-archive", label = "Ready to archive")
    } else {
      list(class = "secondary", icon = "database", label = "Active - cleanup not ready")
    },
    cleaning = list(class = "warning", icon = "spinner", label = "Cleanup in progress"),
    archived = if (!is.null(archive_audit) && !isTRUE(archive_audit$intact)) {
      list(class = "danger", icon = "triangle-exclamation", label = "Archive output missing")
    } else {
      list(class = "success", icon = "box-archive", label = "Results archived / caches cleaned")
    },
    cleanup_failed = list(class = "danger", icon = "triangle-exclamation", label = "Cleanup needs attention")
  )

  action <- if (identical(status, "archived")) {
    actionButton(
      "btn_reopen_dataset",
      "Reopen Dataset for Editing...",
      icon = icon("rotate-left"),
      class = "btn-outline-warning"
    )
  } else if (
    identical(status, "cleanup_failed") &&
      isTRUE(storage_state$details$cache_retired) &&
      isTRUE(storage_state$details$deletion_pending)
  ) {
    actionButton(
      "btn_retry_dataset_cleanup",
      "Retry Retired Cache Deletion",
      icon = icon("rotate"),
      class = "btn-outline-danger"
    )
  } else {
    button <- actionButton(
      "btn_review_dataset_cleanup",
      "Review Dataset Cleanup...",
      icon = icon("broom"),
      class = "btn-outline-danger"
    )
    if (is.null(readiness) || !isTRUE(readiness$ready)) shinyjs::disabled(button) else button
  }

  reasons <- if (!is.null(readiness) && !isTRUE(readiness$ready)) readiness$reasons else character()
  card(
    class = "mb-4 dataset-storage-card",
    card_header(
      div(
        class = "d-flex flex-wrap justify-content-between align-items-center gap-2",
        h4("Dataset Storage", class = "mb-0"),
        span(
          class = paste0("badge text-bg-", presentation$class),
          icon(presentation$icon, class = "me-1", `aria-hidden` = "true"),
          presentation$label
        )
      )
    ),
    card_body(
      if (identical(status, "archived")) {
        tagList(
          p(paste0(
              "Final results are retained in read-only archive mode. ",
              format_storage_bytes(if (is.null(recovered)) cache_size else recovered),
              " of reconstructible cache data was removed."
          )),
          dataset_cleanup_export_warning_ui(cleanup),
          if (!is.null(archive_audit) && !isTRUE(archive_audit$intact)) {
            div(
              class = "alert alert-danger py-2",
              "One or more retained outputs are missing or changed: ",
              paste(utils::head(archive_audit$issues, 3L), collapse = "; ")
            )
          }
        )
      } else if (identical(status, "cleanup_failed")) {
        div(class = "alert alert-danger py-2", storage_state$reason)
      } else if (identical(status, "cleaning")) {
        div(class = "alert alert-warning py-2", "Cleanup was interrupted and will be reconciled on reload.")
      } else {
        tagList(
          p(paste0(
            "Reconstructible cache: ", format_storage_bytes(cache_size),
            ". Cleanup is available only after every sample has durable final outputs."
          )),
          dataset_cleanup_export_warning_ui(readiness),
          if (length(reasons) > 0L) {
            tags$details(
              class = "mb-3",
              tags$summary(paste0(length(reasons), " cleanup requirement(s) remain")),
              tags$ul(
                class = "small mt-2 mb-0",
                lapply(utils::head(reasons, 15L), tags$li),
                if (length(reasons) > 15L) tags$li(paste0("... and ", length(reasons) - 15L, " more."))
              )
            )
          }
        )
      },
      action
    )
  )
}

dashboard_panel <- function() {
  nav_panel(
    title = "Start Menu",
    value = "menu_tab",
    div(
      class = "container mt-5",
      style = "max-width: 800px;",
      h2("Pipeline Dashboard", class = "mb-4 text-center"),
      actionButton(
        "btn_change_dataset",
        "Change Dataset",
        icon = icon("exchange-alt"),
        class = "btn-outline-primary btn-lg w-100 mb-4"
      ),
      uiOutput("pipeline_status_overview"),
      uiOutput("dataset_storage_status"),
      card(
        card_header(h4("Utilities", class = "mb-0")),
        card_body(
          p("View and extract metadata prompt:"),
          actionButton(
            "btn_copy_info",
            "Go to Reference Data",
            icon = icon("file-alt"),
            class = "btn-outline-secondary w-100"
          )
        )
      ),
      card(
        card_header(h4("Pre-Processing & Clustering", class = "mb-0")),
        card_body(
          p("Runs PCA, UMAP, and Louvain clustering across all predefined resolutions for all samples."),
          actionButton(
            "btn_run_clustering",
            "Run Clustering for all Resolutions",
            icon = icon("cogs"),
            class = "btn-primary btn-lg w-100"
          ),
          actionButton(
            "btn_run_single_clustering",
            "Run Clustering for One Sample",
            icon = icon("sync"),
            class = "btn-outline-primary w-100 mt-2"
          )
        )
      ),
      card(
        card_header(h4("Resolution Selection", class = "mb-0")),
        card_body(
          p("Review UMAP plots for each sample and select the most biologically relevant clustering resolution."),
          actionButton(
            "btn_go_res",
            "Go to Resolution Selection",
            icon = icon("search"),
            class = "btn-info btn-lg w-100"
          )
        )
      ),
      card(
        card_header(h4("Differential Expression (DE)", class = "mb-0")),
        card_body(
          p(
            "Runs differential expression analysis. ",
            strong("Requires a resolution to be selected for all samples.")
          ),
          actionButton(
            "btn_run_de",
            "Run Differential Expression Analysis",
            icon = icon("chart-bar"),
            class = "btn-warning btn-lg w-100"
          )
        )
      ),
      card(
        card_header(h4("Manual Cell Type Annotation", class = "mb-0")),
        card_body(
          p("Assign final cell identities based on DE marker matches and signature scores."),
          actionButton(
            "btn_go_anno",
            "Go to Manual Annotation",
            icon = icon("edit"),
            class = "btn-success btn-lg w-100"
          )
        )
      ),
      card(
        card_header(h4("Copy Number Alteration (CNA)", class = "mb-0")),
        card_body(
          p("Run the CNA pipeline: compute CNA signals, select malignant clusters, and assign malignant cells."),
          actionButton(
            "btn_go_cna",
            "Go to CNA Analysis",
            icon = icon("dna"),
            class = "btn-danger btn-lg w-100"
          )
        )
      )
    )
  )
}

reference_panel <- function(clipboard_text) {
  nav_panel(
    title = "Reference Data",
    value = "clipboard_tab",
    div(
      class = "container mt-5",
      style = "max-width: 800px;",
      h3("Metadata Extraction Prompt", class = "mb-3"),
      div(
        class = "alert alert-info",
        icon("info-circle"),
        " Click 'Select All Text' below, then manually copy (Ctrl+C / Cmd+C)."
      ),
      actionButton(
        "btn_select_all",
        "Select All Text",
        icon = icon("check-square"),
        class = "btn-primary mb-3"
      ),
      tags$textarea(
        id = "prompt_text_area",
        class = "form-control mb-4",
        style = "height: 50vh; font-family: monospace; resize: vertical;",
        readonly = TRUE,
        clipboard_text
      ),
      actionButton(
        "btn_back_menu_3",
        "Back to Menu",
        class = "btn-secondary w-100"
      )
    )
  )
}
