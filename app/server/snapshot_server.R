# Snapshot destination and preview live only in this session's transient dialog.
snapshot_server_arguments <- function(state, context, fresh = FALSE) {
  config <- context$config
  dataset <- state$dataset_dir_path
  config_paths <- list(
    "dataset_config.yaml" = file.path(dataset, config$config_files$dataset),
    "samples_config.yaml" = file.path(dataset, config$config_files$samples),
    "selected_config.yaml" = state$selected_config_path,
    "pipeline_state.yaml" = state$pipeline_state_path,
    "standardize.R" = file.path(dataset, "standardize.R"),
    "STANDARDIZATION_CHECKLIST.md" = file.path(dataset, "STANDARDIZATION_CHECKLIST.md")
  )
  list(
    dataset_dir_path = dataset,
    pipeline_state = if (fresh) yaml::read_yaml(state$pipeline_state_path) else state$pipeline_state,
    storage_state = if (fresh) load_dataset_storage_state(dataset, recover = FALSE) else state$storage_state,
    paths_list = state$paths_list,
    selected_config = if (fresh) yaml::read_yaml(state$selected_config_path) else state$live_selected_config,
    selected_config_path = state$selected_config_path,
    dataset_config = if (fresh) yaml::read_yaml(config_paths[["dataset_config.yaml"]]) else state$dataset_config,
    processed_dir_path = file.path(dataset, config$dataset_paths$processed_dir),
    results_dir_path = state$results_dir_path,
    logs_dir_path = file.path(dataset, config$dataset_paths$logs_dir),
    config_paths = config_paths,
    annotation_dirty = isTRUE(state$annotation_dirty), active_actions = state$active_actions,
    datasets_dir_path = context$paths$datasets_dir
  )
}

register_snapshot_server <- function(input, output, session, state, context) {
  rv <- state
  preview <- reactiveVal(NULL)
  options_now <- function() snapshot_options(input$snapshot_mode,
    isTRUE(input$snapshot_include_logs), isTRUE(input$snapshot_include_cna_values))
  # Paths in third-party exceptions are deliberately not shown or logged.
  report_error <- function(error = NULL) showNotification(
    if (inherits(error, "snapshot_error")) conditionMessage(error) else
      "Snapshot could not be prepared. Check completion requirements, source files, destination permissions and available space, then review again.",
    type = "error", duration = 15)
  readiness_for <- function(args) do.call(dataset_snapshot_readiness,
    args[names(args) %in% names(formals(dataset_snapshot_readiness))])
  inventory_for <- function(args, options) do.call(build_snapshot_inventory,
    c(args[names(args) %in% setdiff(names(formals(build_snapshot_inventory)), "options")], list(options = options)))

  observeEvent(input$btn_create_review_snapshot, {
    req(rv$pipeline_state, rv$storage_state)
    args <- snapshot_server_arguments(rv, context)
    if (!readiness_for(args)$ready) {
      showNotification("Finish all samples and save edits before creating a review snapshot.", type = "warning")
      return()
    }
    preview(NULL)
    arm_app_confirmation(rv, "review_snapshot")
    showModal(modalDialog(title = "Create Review Snapshot", size = "l", easyClose = FALSE,
      p("Complete processed data and all ordinary results/plots are copied. Raw inputs and caches are not. This is not a resumable workspace."),
      textInput("snapshot_destination", "Existing destination directory (outside app-managed datasets)", value = ""),
      selectInput("snapshot_mode", "Output", c("Folder" = "folder", "Compressed archive (.zip)" = "archive", "Both" = "both"), selected = "folder"),
      checkboxInput("snapshot_include_logs", "Include logs", value = TRUE),
      checkboxInput("snapshot_include_cna_values", "Include existing CNA values (never recompute)", value = FALSE),
      p(class = "small text-muted", "Optional origin: set project_info.source_doi and/or source_url in dataset_config.yaml. Metadata is not anonymized by packaging."),
      uiOutput("review_snapshot_preview"),
      checkboxInput("snapshot_acknowledge", "I reviewed and accept the listed omissions and unavailable metadata", value = FALSE),
      footer = tagList(actionButton("btn_cancel_review_snapshot", "Cancel", class = "btn-secondary"),
        actionButton("btn_preview_review_snapshot", "Review Contents", class = "btn-outline-primary"),
        shinyjs::disabled(actionButton("btn_confirm_review_snapshot", "Create Verified Snapshot", class = "btn-primary")))
    ))
  })
  observeEvent(input$btn_cancel_review_snapshot, {
    claim_app_confirmation(rv, "review_snapshot")
    preview(NULL)
    updateTextInput(session, "snapshot_destination", value = "")
    removeModal()
  })
  observeEvent(list(input$snapshot_destination, input$snapshot_mode, input$snapshot_include_logs, input$snapshot_include_cna_values), {
    preview(NULL)
    updateCheckboxInput(session, "snapshot_acknowledge", value = FALSE)
  }, ignoreInit = TRUE)
  observe({
    current <- preview()
    shinyjs::toggleState("btn_confirm_review_snapshot",
      condition = !is.null(current) && (!length(current$warnings) || isTRUE(input$snapshot_acknowledge)))
  })
  output$review_snapshot_preview <- renderUI({
    current <- preview()
    if (is.null(current)) return(p(class = "small", "Review Contents validates the destination and previews the snapshot before copying."))
    tagList(
      tags$dl(tags$dt("Source files / uncompressed bytes"),
        tags$dd(paste(nrow(current$inventory$files), "/", format_storage_bytes(current$inventory$size_bytes))),
        tags$dt("Conservative additional destination space (including staging/readback)"),
        tags$dd(format_storage_bytes(current$inventory$required_space_bytes + 1024^2)),
        tags$dt("Generated files"), tags$dd("README, annotation summary, filtering summary and integrity manifest")),
      p(class = "small", "No compression ratio is promised. Both uses the same payload in both forms."),
      tags$details(tags$summary("Included files"), tags$ul(lapply(current$inventory$files$path, tags$li))),
      tags$ul(lapply(current$inventory$omissions, tags$li)),
      if (length(current$warnings)) div(class = "alert alert-warning", tags$ul(lapply(current$warnings, tags$li)))
    )
  })
  observeEvent(input$btn_preview_review_snapshot, {
    preview(NULL)
    tryCatch(withProgress(message = "Reviewing snapshot contents", value = 0.1, {
      args <- snapshot_server_arguments(rv, context, fresh = TRUE)
      readiness <- readiness_for(args)
      if (!readiness$ready) {
        showNotification(paste(readiness$reasons, collapse = "; "), type = "warning", duration = 15)
        return()
      }
      parent <- validate_snapshot_destination(input$snapshot_destination, args$dataset_dir_path, args$datasets_dir_path)
      options <- options_now()
      inventory <- inventory_for(args, options)
      validate_snapshot_output_paths(parent, inventory, args$pipeline_state$dataset_id)
      summaries <- build_snapshot_summaries(args$pipeline_state, args$paths_list, args$selected_config)
      missing_origin <- !nzchar(.snapshot_default(args$dataset_config$project_info$source_doi, "")) &&
        !nzchar(.snapshot_default(args$dataset_config$project_info$source_url, ""))
      preview(list(inventory = inventory, options = options,
        warnings = unique(c(inventory$warnings, summaries$warnings,
          if (missing_origin) "Dataset origin not provided; optional DOI/link fields can be filled before export."))))
      setProgress(1)
    }), error = function(e) report_error(e))
  })
  observeEvent(input$btn_confirm_review_snapshot, {
    reviewed <- preview()
    if (is.null(reviewed) || (length(reviewed$warnings) && !isTRUE(input$snapshot_acknowledge))) return()
    if (!claim_app_confirmation(rv, "review_snapshot")) return()
    # Recheck current state and the reviewed inventory before claiming the action.
    result <- tryCatch({
      args <- snapshot_server_arguments(rv, context, fresh = TRUE)
      current <- inventory_for(args, options_now())
      if (!identical(current, reviewed$inventory) || !readiness_for(args)$ready) {
        preview(NULL)
        arm_app_confirmation(rv, "review_snapshot")
        showNotification("Source files or requirements changed. Review Contents again before copying.", type = "warning")
        return()
      }
      if (length(rv$active_actions) || !begin_app_action(rv, "review_snapshot")) return()
      on.exit(finish_app_action(rv, "review_snapshot"), add = TRUE)
      destination <- input$snapshot_destination
      preview(NULL)
      removeModal()
      # Clear the browser input as well as the server's preview after this operation.
      on.exit(updateTextInput(session, "snapshot_destination", value = ""), add = TRUE)
      withProgress(message = "Creating verified review snapshot", value = 0, {
        last_progress_stage <- NULL
        last_progress_time <- -Inf
        do.call(create_review_snapshot, c(args, list(destination = destination,
          options = reviewed$options, acknowledge_warnings = isTRUE(input$snapshot_acknowledge),
          progress_callback = function(stage, progress, detail, bytes, elapsed_seconds) {
            if (!identical(stage, last_progress_stage) || elapsed_seconds - last_progress_time >= 0.2 || progress == 1) {
              setProgress(value = progress, detail = paste0(detail, " (", round(elapsed_seconds), "s elapsed)"))
              last_progress_stage <<- stage
              last_progress_time <<- elapsed_seconds
            }
          },
          event_callback = function(outcome, parameters) record_state_event(rv, stage = "storage",
            event_type = "review_snapshot", outcome = outcome, parameters = parameters)
        )))
      })
    }, error = identity)
    if (inherits(result, "error")) { report_error(result); return() }
    if (is.null(result)) return()
    # Only transient UI shows the new destinations. Nothing is saved to state.
    showModal(modalDialog(title = "Review snapshot verified", easyClose = TRUE,
      p("Every requested output was verified and published. Scientific statuses are unchanged."),
      if (length(result$warnings)) div(class = "alert alert-warning", tags$ul(lapply(result$warnings, tags$li))),
      tags$ul(lapply(result$outputs, tags$li)), footer = modalButton("Done")))
  })
}
