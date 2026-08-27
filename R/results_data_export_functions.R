# MIAMA-HUB Module: Results Data / Export Functions
# Purpose: Assemble one static Tab 5 export contract and write the formats
#   advertised by MIAMA-UI without rerunning counterfactual or HM calculations.
#
# Export products:
# - Results table: CSV or multi-sheet Excel workbook using the bundle's selection
#   snapshot.
# - Plots package: six standard high-resolution PNG files plus a manifest.
# - AMAT outputs: yearly and cumulative deaths, disease incidence, life years,
#   healthy life years, and health-adjusted life years over the configured
#   assessment horizon.
# - Report: pre-filled Markdown, Word, or PDF generated from the same bundle.
#
# The export bundle is intentionally data-first and immutable after assembly.
# Optional filter arguments define a selection snapshot; when they are omitted,
# the initial `results_request` stored in `results_data` is used. MIAMA-UI
# currently creates this bundle once after `build_results()` and does not rebuild
# it when users later filter on-screen plots.


# Export bundle -------------------------------------------------------------

prepare_results_exports <- function(
    results_data,
    profile = NULL,
    cfg = NULL,
    outcomes = NULL,
    age_groups = NULL,
    gender = NULL,
    modes = NULL,
    aggregation = NULL,
    group_by = NULL,
    timeline_type = c("cumulative", "annual"),
    impact_type = NULL,
    metric = c("prevented_per_100000", "prevented", "percent_reduction"),
    include_plots = TRUE
) {
  if (!is.list(results_data) || is.null(results_data$plot_data)) {
    stop("results_data must be the object returned by prepare_results_data().", call. = FALSE)
  }

  cfg <- cfg %||% miama_default_config()
  request <- results_data$results_request %||% list()
  outcomes <- .results_export_filter(outcomes, request$res_outcomes)
  age_groups <- .results_export_filter(age_groups, request$res_age_groups)
  gender <- .results_export_filter(gender, request$res_gender)
  modes <- .results_export_filter(modes, request$res_modes_filter)
  aggregation <- aggregation %||% request$res_aggregation %||% "total"
  group_by <- group_by %||% .results_export_group_by(request$res_pop_aggregation)
  timeline_type <- match.arg(timeline_type)
  impact_type <- impact_type %||% request$res_impact_type %||% "attributable"
  metric <- match.arg(metric)

  aggregation <- match.arg(aggregation, c("total", "timeline"))
  group_by <- match.arg(group_by, c("outcome", "age_group", "gender", "mode", "none"))
  impact_type <- match.arg(.results_plot_impact_type(impact_type), c("attributable", "cf_vs_ref"))

  results_table <- results_filter_health_data(
    results_data = results_data,
    outcomes = outcomes,
    age_groups = age_groups,
    gender = gender,
    modes = modes,
    aggregation = aggregation,
    group_by = group_by,
    timeline_type = timeline_type
  )
  timeline_annual <- results_filter_health_data(
    results_data = results_data,
    outcomes = outcomes,
    age_groups = age_groups,
    gender = gender,
    modes = modes,
    aggregation = "timeline",
    group_by = "outcome",
    timeline_type = "annual"
  )
  timeline_cumulative <- results_filter_health_data(
    results_data = results_data,
    outcomes = outcomes,
    age_groups = age_groups,
    gender = gender,
    modes = modes,
    aggregation = "timeline",
    group_by = "outcome",
    timeline_type = "cumulative"
  )
  trip_modes <- .results_export_trip_modes(results_data, modes)
  headline_metrics <- get_results_highlights(results_data)
  metadata <- .results_export_metadata(profile, cfg, aggregation, group_by, timeline_type)
  filters <- .results_export_filters(
    outcomes, age_groups, gender, modes, aggregation, group_by,
    timeline_type, impact_type, metric
  )
  assumptions <- .results_export_assumptions(results_data, cfg)
  amat_outputs <- prepare_results_amat_outputs(
    results_data = results_data,
    horizon_years = get_assessment_period(cfg),
    outcomes = outcomes
  )
  amat_inputs <- .results_export_amat_inputs(
    metadata = metadata,
    headline_metrics = headline_metrics,
    trip_modes = trip_modes
  )
  report <- .results_export_report_content(
    metadata = metadata,
    filters = filters,
    headline_metrics = headline_metrics,
    assumptions = assumptions,
    results_table = results_table
  )

  plots <- if (isTRUE(include_plots)) {
    .results_export_plots(
      results_data = results_data,
      outcomes = outcomes,
      age_groups = age_groups,
      gender = gender,
      modes = modes,
      impact_type = impact_type,
      metric = metric,
      timeline_type = timeline_type
    )
  } else {
    list()
  }

  structure(
    list(
      schema_version = "miama-results-export-draft-1",
      generated_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
      metadata = metadata,
      filters = filters,
      headline_metrics = headline_metrics,
      results_table = results_table,
      timeline_annual = timeline_annual,
      timeline_cumulative = timeline_cumulative,
      trip_mode_distribution = trip_modes,
      assumptions = assumptions,
      amat_inputs = amat_inputs,
      amat_health_timeline = amat_outputs$timeline,
      amat_health_summary = amat_outputs$summary,
      report = report,
      plots = plots
    ),
    class = c("miama_results_exports", "list")
  )
}


# Results data files --------------------------------------------------------

write_results_csv <- function(exports, file, na = "") {
  .validate_results_exports(exports)
  .ensure_export_parent(file)
  utils::write.csv(exports$results_table, file = file, row.names = FALSE, na = na)
  invisible(normalizePath(file, winslash = "/", mustWork = FALSE))
}

write_results_xlsx <- function(exports, file) {
  .validate_results_exports(exports)
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("Package `openxlsx` is required to write Excel result exports.", call. = FALSE)
  }

  .ensure_export_parent(file)
  sheets <- list(
    Results = exports$results_table,
    Headline_metrics = exports$headline_metrics,
    Timeline_annual = exports$timeline_annual,
    Timeline_cumulative = exports$timeline_cumulative,
    Trip_modes = exports$trip_mode_distribution,
    Metadata = exports$metadata,
    Filters = exports$filters,
    Assumptions = exports$assumptions,
    AMAT_metadata = exports$amat_inputs,
    AMAT_health_timeline = exports$amat_health_timeline,
    AMAT_health_summary = exports$amat_health_summary
  )
  openxlsx::write.xlsx(sheets, file = file, overwrite = TRUE, asTable = TRUE)
  invisible(normalizePath(file, winslash = "/", mustWork = FALSE))
}


# Plot files ----------------------------------------------------------------

write_results_plot_pngs <- function(exports,
                                    directory,
                                    width = 10,
                                    height = 6,
                                    dpi = 300,
                                    bg = "white") {
  .validate_results_exports(exports)
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package `ggplot2` is required to write result plots.", call. = FALSE)
  }
  if (length(exports$plots) == 0) {
    stop("Export bundle has no plots. Rebuild it with include_plots = TRUE.", call. = FALSE)
  }

  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  plot_ids <- names(exports$plots)
  filenames <- paste0(plot_ids, ".png")
  paths <- file.path(directory, filenames)

  for (index in seq_along(paths)) {
    ggplot2::ggsave(
      filename = paths[[index]],
      plot = exports$plots[[index]],
      device = "png",
      width = width,
      height = height,
      units = "in",
      dpi = dpi,
      bg = bg
    )
  }

  manifest <- data.frame(
    plot_id = plot_ids,
    filename = filenames,
    title = vapply(exports$plots, .results_export_plot_title, character(1)),
    width_in = width,
    height_in = height,
    dpi = dpi,
    stringsAsFactors = FALSE
  )
  manifest_path <- file.path(directory, "plot_manifest.csv")
  utils::write.csv(manifest, manifest_path, row.names = FALSE)

  invisible(c(paths, manifest_path))
}

write_results_plots_zip <- function(exports,
                                    file,
                                    width = 10,
                                    height = 6,
                                    dpi = 300,
                                    bg = "white") {
  .ensure_export_parent(file)
  output_file <- normalizePath(file, winslash = "/", mustWork = FALSE)
  plot_dir <- tempfile("miama-result-plots-")
  dir.create(plot_dir, recursive = TRUE)
  on.exit(unlink(plot_dir, recursive = TRUE, force = TRUE), add = TRUE)

  write_results_plot_pngs(exports, plot_dir, width, height, dpi, bg)
  old_dir <- setwd(plot_dir)
  tryCatch(
    utils::zip(output_file, files = list.files(plot_dir), flags = "-q"),
    finally = setwd(old_dir)
  )

  invisible(output_file)
}


# AMAT draft ---------------------------------------------------------------

#' Prepare health outputs for the Active Mode Appraisal Toolkit
#'
#' Returns annual and cumulative differences for deaths, disease incidence,
#' life years, healthy life years, and HALYs. `annual_delta_cf_minus_ref` always uses
#' the technical counterfactual-minus-reference sign. `annual_benefit` uses a
#' positive-is-beneficial sign: reference minus counterfactual for adverse
#' incidence outcomes and counterfactual minus reference for LY/HLY/HALY.
#'
#' @param results_data Object returned by [prepare_results_data()].
#' @param horizon_years Optional positive whole-number assessment horizon.
#'   Defaults to the canonical period stored in `results_data`.
#' @param outcomes Optional health-outcome IDs to retain. Life years, healthy
#'   life years, and HALYs are always retained.
#' @return A list containing `timeline`, `summary`, `horizon_years`, and a draft
#'   schema version.
#' @export
prepare_results_amat_outputs <- function(results_data,
                                         horizon_years = NULL,
                                         outcomes = NULL) {
  if (!is.list(results_data) || is.null(results_data$plot_data)) {
    stop("results_data must be the object returned by prepare_results_data().", call. = FALSE)
  }
  horizon_years <- horizon_years %||%
    results_data$headline_metrics$assessment_period_years %||% 40L
  horizon_years <- .results_validate_horizon(horizon_years)
  timeline <- as.data.frame(
    results_data$plot_data$amat_health_timeline %||% .empty_amat_health_timeline()
  )
  if (nrow(timeline) > 0) {
    timeline <- timeline[timeline$cycle <= horizon_years, , drop = FALSE]
    if (!is.null(outcomes) && length(outcomes) > 0) {
      always <- c("life_years", "healthy_life_years", "halys")
      timeline <- timeline[timeline$measure %in% c(always, as.character(outcomes)), , drop = FALSE]
    }
  }

  if (nrow(timeline) == 0) {
    summary <- timeline
  } else {
    groups <- split(timeline, timeline$measure)
    summary <- do.call(rbind, lapply(groups, function(group) {
      group[which.max(group$cycle), , drop = FALSE]
    }))
    rownames(summary) <- NULL
  }

  list(
    schema_version = "miama-amat-health-draft-1",
    horizon_years = horizon_years,
    timeline = timeline,
    summary = summary
  )
}

write_results_amat_csv <- function(exports, file, na = "") {
  .validate_results_exports(exports)
  .ensure_export_parent(file)
  utils::write.csv(exports$amat_health_timeline, file = file, row.names = FALSE, na = na)
  invisible(normalizePath(file, winslash = "/", mustWork = FALSE))
}


# Report draft --------------------------------------------------------------

write_results_report <- function(exports,
                                 file,
                                 format = c("markdown", "docx", "pdf")) {
  .validate_results_exports(exports)
  format <- match.arg(format)
  .ensure_export_parent(file)
  markdown <- .results_export_markdown(exports)

  if (identical(format, "markdown")) {
    writeLines(markdown, con = file, useBytes = TRUE)
    return(invisible(normalizePath(file, winslash = "/", mustWork = FALSE)))
  }

  if (!requireNamespace("rmarkdown", quietly = TRUE) || !rmarkdown::pandoc_available()) {
    stop("Package `rmarkdown` and Pandoc are required for Word/PDF reports.", call. = FALSE)
  }

  markdown_file <- tempfile(fileext = ".md")
  on.exit(unlink(markdown_file, force = TRUE), add = TRUE)
  writeLines(markdown, con = markdown_file, useBytes = TRUE)
  to <- if (identical(format, "docx")) "docx" else "pdf"
  rmarkdown::pandoc_convert(markdown_file, to = to, output = file)
  invisible(normalizePath(file, winslash = "/", mustWork = FALSE))
}


# Bundle assembly helpers ---------------------------------------------------

.results_export_filter <- function(value, fallback) {
  value <- value %||% fallback
  if (is.null(value) || length(value) == 0) NULL else as.character(value)
}

.results_export_group_by <- function(value) {
  switch(
    value %||% "total",
    age_group = "age_group",
    gender = "gender",
    mode = "mode",
    "outcome"
  )
}

.results_export_trip_modes <- function(results_data, modes) {
  out <- as.data.frame(results_data$plot_data$trip_mode_distribution %||% data.frame())
  if (nrow(out) == 0 || is.null(modes) || length(modes) == 0) return(out)
  mode_ids <- .results_normalize_plot_modes(modes)
  out[out$mode %in% mode_ids, , drop = FALSE]
}

.results_export_metadata <- function(profile, cfg, aggregation, group_by, timeline_type) {
  keys <- c(
    "appraisal_name", "geo_name", "geo_level", "geo_id", "ui_version",
    "modes", "intervention_type", "data_source", "population_size"
  )
  values <- vapply(keys, function(key) {
    .results_export_text(.results_export_profile_value(profile, key))
  }, character(1))

  data.frame(
    field = c(
      keys, "result_aggregation", "result_group_by", "timeline_type",
      "assessment_period_years", "person_weight", "population_scaling_source",
      "impact_sign_convention"
    ),
    value = c(
      values, aggregation, group_by, timeline_type,
      .results_export_text(get_assessment_period(cfg)),
      .results_export_text(cfg$population$person_weight %||% MIAMA_SYNTHPOP_PERSON_WEIGHT),
      .results_export_text(cfg$population$source),
      "Positive prevented values equal reference minus counterfactual"
    ),
    stringsAsFactors = FALSE
  )
}

.results_export_profile_value <- function(profile, field) {
  if (is.null(profile) || !is.list(profile) || !field %in% names(profile)) return(NULL)
  value <- profile[[field]]
  if (!is_input_field(value)) return(value)
  if (isTRUE(value$is_filled) && !is.null(value$input_value)) return(value$input_value)
  value$default_value %||% value$input_value
}

.results_export_text <- function(value) {
  if (is.null(value) || length(value) == 0 || all(is.na(value))) return(NA_character_)
  paste(as.character(value), collapse = "; ")
}

.results_export_filters <- function(outcomes,
                                    age_groups,
                                    gender,
                                    modes,
                                    aggregation,
                                    group_by,
                                    timeline_type,
                                    impact_type,
                                    metric) {
  data.frame(
    filter = c(
      "outcomes", "age_groups", "gender", "modes", "aggregation",
      "group_by", "timeline_type", "impact_type", "metric"
    ),
    value = c(
      .results_export_text(outcomes), .results_export_text(age_groups),
      .results_export_text(gender), .results_export_text(modes), aggregation,
      group_by, timeline_type, impact_type, metric
    ),
    stringsAsFactors = FALSE
  )
}

.results_export_assumptions <- function(results_data, cfg) {
  report <- results_data$results_report %||% list()
  notes <- as.character(report$notes %||% character(0))
  fixed <- data.frame(
    item = c(
      "cycle_zero", "population_scaling", "raw_delta",
      "presented_impact", "mode_attribution"
    ),
    value = c(
      "Cycle 0 excluded; cycle 1 is the first presented model year",
      paste0(
        "Each synthetic person represents ",
        cfg$population$person_weight %||% MIAMA_SYNTHPOP_PERSON_WEIGHT,
        " residents"
      ),
      "delta_value = counterfactual - reference",
      "prevented_value = reference - counterfactual",
      "All-mode totals are canonical; mode-specific deltas are allocated by each individual's signed MMET contribution"
    ),
    source = "HUB results contract",
    stringsAsFactors = FALSE
  )
  if (length(notes) == 0) return(fixed)
  rbind(
    fixed,
    data.frame(
      item = paste0("result_note_", seq_along(notes)),
      value = notes,
      source = "results_report",
      stringsAsFactors = FALSE
    )
  )
}

.results_export_amat_inputs <- function(metadata, headline_metrics, trip_modes) {
  metadata_value <- function(field) {
    value <- metadata$value[metadata$field == field]
    if (length(value) == 0) NA_character_ else value[[1]]
  }
  trip_value <- function(mode, scenario) {
    value <- trip_modes$trips[trip_modes$mode == mode & trip_modes$scenario == scenario]
    if (length(value) == 0) NA_real_ else sum(value, na.rm = TRUE)
  }
  headline_value <- function(metric) {
    value <- headline_metrics$value[headline_metrics$metric == metric]
    if (length(value) == 0) NA_real_ else value[[1]]
  }

  fields <- c(
    "schema_version", "scheme_name", "geography_id", "geography_name",
    "population_size", "walking_trips_reference", "walking_trips_counterfactual",
    "cycling_trips_reference", "cycling_trips_counterfactual",
    "premature_deaths_prevented", "halys_gained", "disease_cases_prevented"
  )
  values <- c(
    "draft-awaiting-AMAT-specification",
    metadata_value("appraisal_name"), metadata_value("geo_id"),
    metadata_value("geo_name"), metadata_value("population_size"),
    trip_value("walking", "Reference"), trip_value("walking", "Counterfactual"),
    trip_value("cycling", "Reference"), trip_value("cycling", "Counterfactual"),
    headline_value("premature_deaths_prevented"),
    headline_value("halys_gained"),
    headline_value("disease_cases_prevented")
  )
  units <- c(
    NA, NA, NA, NA, "people", "weighted trips/week", "weighted trips/week",
    "weighted trips/week", "weighted trips/week", "deaths", "HALYs", "disease cases"
  )

  data.frame(
    field = fields,
    value = values,
    unit = units,
    source = c(
      "HUB export", rep("appraisal profile", 4), rep("trip_mode_distribution", 4),
      rep("headline_metrics", 3)
    ),
    mapping_status = c("draft", rep("requires AMAT field confirmation", length(fields) - 1)),
    stringsAsFactors = FALSE
  )
}

.results_export_report_content <- function(metadata,
                                           filters,
                                           headline_metrics,
                                           assumptions,
                                           results_table) {
  metric <- function(name) {
    value <- headline_metrics$value[headline_metrics$metric == name]
    if (length(value) == 0 || is.na(value[[1]])) "not available" else format(round(value[[1]], 2), big.mark = ",")
  }
  name <- metadata$value[metadata$field == "appraisal_name"]
  if (length(name) == 0 || is.na(name[[1]]) || !nzchar(name[[1]])) name <- "MIAMA appraisal results"

  list(
    title = name[[1]],
    summary = c(
      paste0("Estimated premature deaths prevented: ", metric("premature_deaths_prevented"), "."),
      paste0("Estimated HALYs gained: ", metric("halys_gained"), "."),
      paste0("Estimated disease cases prevented: ", metric("disease_cases_prevented"), "."),
      "Positive prevented values represent lower counterfactual health outcomes than reference."
    ),
    methods = c(
      "Reference and counterfactual synthetic-population activity were mapped to MIAMA-HM cycle outcomes.",
      "Cycle 0 was excluded from presented impacts; cumulative totals sum model cycles from cycle 1 onward."
    ),
    metadata = metadata,
    filters = filters,
    assumptions = assumptions,
    results = results_table
  )
}

.results_export_plots <- function(results_data,
                                  outcomes,
                                  age_groups,
                                  gender,
                                  modes,
                                  impact_type,
                                  metric,
                                  timeline_type) {
  list(
    health_overview = results_plot_health_overview(
      results_data, outcomes = outcomes, age_groups = age_groups, gender = gender,
      modes = modes, impact_type = impact_type, metric = metric
    ),
    health_timeline = results_plot_health_timeline(
      results_data, outcomes = outcomes, age_groups = age_groups, gender = gender,
      modes = modes, impact_type = impact_type, metric = metric, timeline_type = timeline_type
    ),
    health_by_age = results_plot_health_impacts(
      results_data, outcomes = outcomes, age_groups = age_groups, gender = gender,
      modes = modes, group_by = "age_group", metric = metric
    ),
    health_by_gender = results_plot_health_impacts(
      results_data, outcomes = outcomes, age_groups = age_groups, gender = gender,
      modes = modes, group_by = "gender", metric = metric
    ),
    health_by_mode = results_plot_health_impacts(
      results_data, outcomes = outcomes, age_groups = age_groups, gender = gender,
      modes = modes, group_by = "mode", metric = metric
    ),
    trip_mode_distribution = results_plot_trip_mode_distribution(
      results_data, modes = modes, value = "proportion"
    )
  )
}

.results_export_plot_title <- function(plot) {
  title <- plot$labels$title %||% NA_character_
  if (length(title) == 0 || is.null(title)) NA_character_ else as.character(title[[1]])
}


# Markdown helpers ----------------------------------------------------------

.results_export_markdown <- function(exports) {
  report <- exports$report
  c(
    paste0("# ", report$title),
    "",
    paste0("Generated: ", exports$generated_at_utc),
    "",
    "## Summary",
    "",
    paste0("- ", report$summary),
    "",
    "## Appraisal metadata",
    "",
    .results_export_markdown_table(report$metadata),
    "",
    "## Applied result filters",
    "",
    .results_export_markdown_table(report$filters),
    "",
    "## Methods",
    "",
    paste0("- ", report$methods),
    "",
    "## Results",
    "",
    .results_export_markdown_table(report$results),
    "",
    "## Assumptions and limitations",
    "",
    .results_export_markdown_table(report$assumptions)
  )
}

.results_export_markdown_table <- function(data, max_rows = 100L) {
  data <- as.data.frame(data)
  if (nrow(data) == 0 || ncol(data) == 0) return("_No data available._")
  data <- utils::head(data, max_rows)
  values <- lapply(data, function(column) {
    out <- ifelse(is.na(column), "", as.character(column))
    gsub("|", "\\|", out, fixed = TRUE)
  })
  values <- as.data.frame(values, stringsAsFactors = FALSE)
  header <- paste0("| ", paste(names(values), collapse = " | "), " |")
  separator <- paste0("| ", paste(rep("---", ncol(values)), collapse = " | "), " |")
  rows <- apply(values, 1, function(row) paste0("| ", paste(row, collapse = " | "), " |"))
  c(header, separator, rows)
}


# Validation and paths ------------------------------------------------------

.validate_results_exports <- function(exports) {
  if (!inherits(exports, "miama_results_exports")) {
    stop("exports must be created by prepare_results_exports().", call. = FALSE)
  }
  invisible(exports)
}

.ensure_export_parent <- function(file) {
  parent <- dirname(file)
  if (!dir.exists(parent)) dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  invisible(file)
}
