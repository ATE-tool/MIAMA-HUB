# MIAMA-HUB API: Results Metadata And Highlights ----------------------------
# Lightweight helpers used to construct UI controls and summary cards. They do
# not load reference or health data; option IDs and labels come from config.


# Assessment Period ---------------------------------------------------------

#' Get the canonical health assessment period
#'
#' @param cfg Optional MIAMA-HUB configuration.
#' @return Positive integer number of model years.
#' @export
get_assessment_period <- function(cfg = NULL) {
  cfg <- cfg %||% miama_default_config()
  years <- cfg$results$assessment_period_years %||% 40L
  .results_validate_horizon(years)
}


# UI Option Catalogues ------------------------------------------------------

#' Get one configured UI option catalogue
#'
#' @param option One of the names returned by calling this function with
#'   `option = NULL`.
#' @param cfg Optional MIAMA-HUB configuration.
#' @return With `option = NULL`, a character vector of available catalogue
#'   names. Otherwise, a data frame with stable values, labels, order, and
#'   default-selection flags.
#' @export
get_ui_options <- function(option = NULL, cfg = NULL) {
  cfg <- cfg %||% miama_default_config()
  catalogues <- .miama_ui_option_catalogues(cfg)
  if (is.null(option)) return(names(catalogues))
  if (length(option) != 1 || !option %in% names(catalogues)) {
    stop(
      "option must be one of: ", paste(names(catalogues), collapse = ", "),
      call. = FALSE
    )
  }

  spec <- catalogues[[option]]
  values <- unname(as.character(spec$values))
  labels <- names(spec$values)
  if (is.null(labels)) labels <- values
  data.frame(
    option = option,
    value = values,
    label = as.character(labels),
    order = seq_along(values),
    default = values %in% as.character(spec$default %||% character(0)),
    stringsAsFactors = FALSE
  )
}

#' Get all option tables needed by Tab 5
#'
#' @param cfg Optional MIAMA-HUB configuration.
#' @return Named list containing the assessment period and UI-ready tables.
#' @export
get_results_options <- function(cfg = NULL) {
  cfg <- cfg %||% miama_default_config()
  list(
    assessment_period_years = get_assessment_period(cfg),
    health_outcomes = get_health_outcome_options(cfg),
    age_groups = get_ui_options("age_groups", cfg),
    gender = get_ui_options("gender", cfg),
    modes = get_ui_options("results_modes", cfg),
    temporal_aggregation = get_ui_options("temporal_aggregation", cfg),
    population_aggregation = get_ui_options("population_aggregation", cfg),
    impact_type = get_ui_options("impact_type", cfg),
    metric = get_ui_options("metric", cfg),
    timeline_type = get_ui_options("timeline_type", cfg)
  )
}

.miama_ui_option_catalogues <- function(cfg) {
  defaults <- miama_default_config()
  age <- cfg$spread$age %||% defaults$spread$age
  pa <- cfg$spread$pa %||% defaults$spread$pa
  distance <- cfg$spread$trip_distance %||% defaults$spread$trip_distance
  configured <- utils::modifyList(
    .miama_default_ui_options(),
    cfg$options %||% list()
  )

  c(
    list(
      age_groups = list(
        values = stats::setNames(as.character(age$ids), as.character(age$labels)),
        default = as.character(age$ids)
      ),
      population_age_groups = list(
        values = stats::setNames(paste0("pop_", as.character(age$ids)), as.character(age$labels)),
        default = paste0("pop_", as.character(age$ids))
      ),
      pa_categories = list(
        values = stats::setNames(as.character(pa$ids), as.character(pa$labels)),
        default = as.character(pa$ids)
      ),
      trip_distance_categories = list(
        values = stats::setNames(as.character(distance$ids), as.character(distance$labels)),
        default = as.character(distance$ids)
      )
    ),
    configured
  )
}


# Results Highlights --------------------------------------------------------

#' Get the three headline health totals for the results summary card
#'
#' The values cover the configured assessment period and are not affected by
#' interactive Tab 5 filters. Disease cases sum each configured underlying HM
#' incidence stream once, avoiding overlap between UI composites and subtypes.
#'
#' @param results_data Object returned by [prepare_results_data()].
#' @return Three-row data frame suitable for direct UI rendering.
#' @export
get_results_highlights <- function(results_data) {
  if (!is.list(results_data) || is.null(results_data$headline_metrics)) {
    stop("results_data must be the object returned by prepare_results_data().", call. = FALSE)
  }
  x <- results_data$headline_metrics
  values <- c(
    premature_deaths_prevented = x$premature_deaths_prevented,
    life_years_saved = x$life_years_saved,
    disease_cases_prevented = x$disease_cases_prevented
  )
  disease_status <- if (length(x$disease_columns_used %||% character(0)) == 0) {
    "not_available"
  } else if (length(x$disease_columns_missing %||% character(0)) > 0) {
    "partial"
  } else {
    "available"
  }
  status <- c(
    if (is.na(values[[1]])) "not_available" else "available",
    if (is.na(values[[2]])) "not_available" else "available",
    disease_status
  )

  data.frame(
    metric = names(values),
    label = c(
      "Total number of prevented premature deaths",
      "Total number of saved life-years",
      "Total number of prevented disease cases"
    ),
    value = unname(as.numeric(values)),
    unit = c("deaths", "life-years", "disease cases"),
    assessment_period_years = as.integer(x$assessment_period_years),
    status = status,
    stringsAsFactors = FALSE
  )
}
