# MIAMA-HUB Module: Results Data / Prepare
# Purpose: Convert Step 7 counterfactual health outcomes into compact tables,
#   headline values, and plot-ready data for Tab 5.
#
# Inputs:
# - `counterfactual_data$health_outcomes`, produced by
#   `apply_counterfactual_health_outcomes()`
# - optional `reference_data`, used for reference-vs-counterfactual trip mode
#   distribution plots
# - `results_request`, mapped from Tab 5 `appraisal_inputs`
#
# Outputs:
# - `results_table`: filtered and aggregated health outcome table
# - `headline_metrics`: first-pass values for the main results tiles
# - `plot_data`: compact UI-facing source tables. `health_cube` drives all
#   health plots; `trip_mode_distribution` drives the travel-mode plot. The
#   overview/timeline tables are convenience views, not separate data contracts.
# - `results_report`: assumptions, filters, and known limitations
#
# Results semantics:
# - Cycle 0 is baseline state and is excluded; cycle 1 is the first result year.
# - Raw `d_*` values remain `cf - ref`; presentation impacts use `ref - cf`.
# - Expected outcomes are multiplied by `cfg$population$person_weight`.
#
# Current limitations:
# - Health impacts are not yet attributable to individual active modes. Results
#   therefore use `mode = "all_modes"` and record a report note when mode
#   filters are supplied.
# - Life-years/HALY headline metrics need a final agreed formula. The current
#   output keeps this value as `NA_real_` and reports the clarification need.

prepare_results_data <- function(
    counterfactual_data,
    reference_data = NULL,
    results_request = list(),
    appraisal_input_values = list(),
    cfg = NULL
) {
  cfg <- cfg %||% miama_default_config()
  if (length(results_request) == 0 && is.null(names(results_request))) {
    names(results_request) <- character(0)
  }
  if (length(appraisal_input_values) == 0 && is.null(names(appraisal_input_values))) {
    names(appraisal_input_values) <- character(0)
  }

  assert_named_list(counterfactual_data, "counterfactual_data")
  assert_named_list(results_request, "results_request")
  assert_named_list(appraisal_input_values, "appraisal_input_values")

  if (is.null(counterfactual_data$health_outcomes)) {
    stop("Step 8 requires `counterfactual_data$health_outcomes`. Run Step 7 first.", call. = FALSE)
  }

  health_outcomes_all <- as.data.frame(counterfactual_data$health_outcomes)
  cycle_zero_rows <- if ("cycle" %in% names(health_outcomes_all)) {
    sum(health_outcomes_all$cycle == 0, na.rm = TRUE)
  } else {
    0L
  }
  health_outcomes <- if ("cycle" %in% names(health_outcomes_all)) {
    health_outcomes_all[is.na(health_outcomes_all$cycle) | health_outcomes_all$cycle != 0, , drop = FALSE]
  } else {
    health_outcomes_all
  }
  request <- .results_request_defaults(results_request, appraisal_input_values)
  outcome_specs <- .results_outcome_specs()
  person_weight <- .results_person_weight(cfg)

  long <- .results_health_long(health_outcomes, outcome_specs, person_weight)
  health_cube <- .results_health_cube(long)
  filtered <- .filter_results_health_long(long, request)
  results_table <- .aggregate_results_health(filtered, request)

  trip_distribution <- .results_trip_mode_distribution(reference_data, counterfactual_data)
  headline_metrics <- .results_headline_metrics(results_table)
  plot_data <- list(
    health_cube = health_cube,
    health_overview = .results_plot_health_overview_data(results_table, request),
    health_timeline = .results_plot_timeline_data(filtered, request),
    trip_mode_distribution = trip_distribution
  )

  report <- .results_report(
    health_outcomes = health_outcomes,
    long = long,
    filtered = filtered,
    results_table = results_table,
    request = request,
    outcome_specs = outcome_specs,
    trip_distribution = trip_distribution,
    person_weight = person_weight,
    population_source = cfg$population$source %||% "Configured synthetic-population scale",
    cycle_zero_rows = cycle_zero_rows
  )

  list(
    results_request = request,
    headline_metrics = headline_metrics,
    results_table = results_table,
    plot_data = plot_data,
    results_report = report
  )
}

.results_health_cube <- function(long) {
  if (nrow(long) == 0) {
    return(data.frame(
      outcome = character(0), outcome_label = character(0),
      outcome_type = character(0), mode = character(0), cycle = integer(0),
      age_group = character(0), gender = character(0), ref_value = numeric(0),
      cf_value = numeric(0), delta_value = numeric(0), population = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  keep <- !is.na(long$age_group) & !is.na(long$gender)
  stats::aggregate(
    long[keep, c("ref_value", "cf_value", "delta_value", "population"), drop = FALSE],
    by = long[keep, c(
      "outcome", "outcome_label", "outcome_type", "mode", "cycle",
      "age_group", "gender"
    ), drop = FALSE],
    FUN = sum,
    na.rm = TRUE
  )
}

# Request Normalisation ------------------------------------------------------
# Tab 5 names are still settling. This helper accepts both the current UI
# `res_aggregation` field and the schema's `res_temp_aggregation` alias.

.results_request_defaults <- function(results_request, appraisal_input_values = list()) {
  values <- utils::modifyList(appraisal_input_values, results_request)
  aggregation <- .ui_value(values, "res_aggregation", NULL) %||%
    .ui_value(values, "res_temp_aggregation", "total")

  list(
    res_outcomes = .ui_value(values, "res_outcomes", character(0)),
    res_age_groups = .ui_value(values, "res_age_groups", .results_age_group_levels()$id),
    res_gender = .ui_value(values, "res_gender", c("male", "female")),
    res_modes_filter = normalize_active_modes(.ui_value(values, "res_modes_filter", .ui_value(values, "modes", character(0)))),
    res_aggregation = aggregation,
    res_temp_aggregation = aggregation,
    res_pop_aggregation = .ui_value(values, "res_pop_aggregation", "total"),
    res_impact_type = .results_normalize_impact_type(.ui_value(values, "res_impact_type", "attributable"))
  )
}

.results_normalize_impact_type <- function(x) {
  if (identical(x, "cf_vs_bl")) {
    return("cf_vs_ref")
  }
  x %||% "attributable"
}

# Outcome Mapping ------------------------------------------------------------
# Map UI outcome IDs to one or more HM outcome columns. Composite outcomes are
# summed over their component columns.

.results_outcome_specs <- function() {
  cancer_cols <- c(
    "bladder_cancer", "breast_cancer", "colon_cancer", "endometrial_cancer",
    "esophageal_cancer", "gastric_cardia_cancer", "head_and_neck_cancer",
    "liver_cancer", "lung_cancer", "myeloid_leukemia"
  )

  list(
    mortality = list(label = "All-cause mortality", columns = "dead", type = "mortality"),
    cvd = list(label = "Cardiovascular disease", columns = c("coronary_heart_disease", "stroke"), type = "disease"),
    ihd = list(label = "Ischaemic heart disease", columns = "coronary_heart_disease", type = "disease"),
    stroke = list(label = "Stroke", columns = "stroke", type = "disease"),
    diabetes = list(label = "Diabetes type 2", columns = "diabetes", type = "disease"),
    depression = list(label = "Depression", columns = "depression", type = "disease"),
    alzheimer = list(label = "Alzheimer's & dementias", columns = "all_cause_dementia", type = "disease"),
    cancers = list(label = "All cancers", columns = cancer_cols, type = "disease"),
    breast_cancer = list(label = "Breast cancer", columns = "breast_cancer", type = "disease"),
    colon_cancer = list(label = "Colon cancer", columns = "colon_cancer", type = "disease")
  )
}

.results_health_long <- function(health_outcomes, outcome_specs, person_weight = 1) {
  if (nrow(health_outcomes) == 0) {
    return(.empty_results_long())
  }

  required <- c("census_id", "cycle", "age1year", "female")
  missing <- setdiff(required, names(health_outcomes))
  if (length(missing) > 0) {
    stop("Health outcomes are missing required Step 8 columns: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  rows <- lapply(names(outcome_specs), function(outcome_id) {
    spec <- outcome_specs[[outcome_id]]
    raw_cols <- spec$columns[spec$columns %in% names(health_outcomes)]
    if (length(raw_cols) == 0) {
      return(NULL)
    }

    delta_cols <- paste0("d_", raw_cols)
    delta_cols <- delta_cols[delta_cols %in% names(health_outcomes)]
    if (length(delta_cols) == 0) {
      return(NULL)
    }

    cf_cols <- paste0(raw_cols, "_cf")
    cf_cols <- cf_cols[cf_cols %in% names(health_outcomes)]

    ref_value <- rowSums(health_outcomes[, raw_cols, drop = FALSE], na.rm = TRUE)
    delta_value <- rowSums(health_outcomes[, delta_cols, drop = FALSE], na.rm = TRUE)
    cf_value <- if (length(cf_cols) > 0) {
      rowSums(health_outcomes[, cf_cols, drop = FALSE], na.rm = TRUE)
    } else {
      ref_value + delta_value
    }

    data.frame(
      census_id = health_outcomes$census_id,
      cycle = health_outcomes$cycle,
      age1year = health_outcomes$age1year,
      age_group = .results_age_group(health_outcomes$age1year),
      gender = ifelse(health_outcomes$female == 1, "female", "male"),
      mode = "all_modes",
      outcome = outcome_id,
      outcome_label = spec$label,
      outcome_type = spec$type,
      ref_value = ref_value * person_weight,
      cf_value = cf_value * person_weight,
      delta_value = delta_value * person_weight,
      population = person_weight,
      stringsAsFactors = FALSE
    )
  })

  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0) {
    return(.empty_results_long())
  }

  do.call(rbind, rows)
}

.empty_results_long <- function() {
  data.frame(
    census_id = integer(0),
    cycle = integer(0),
    age1year = numeric(0),
    age_group = character(0),
    gender = character(0),
    mode = character(0),
    outcome = character(0),
    outcome_label = character(0),
    outcome_type = character(0),
    ref_value = numeric(0),
    cf_value = numeric(0),
    delta_value = numeric(0),
    population = numeric(0)
  )
}

# Filtering And Aggregation --------------------------------------------------
# Filter by Tab 5 controls, then aggregate either to 50-year totals or cycle
# timelines. Population strata are only retained when requested.

.filter_results_health_long <- function(long, request) {
  out <- long

  if (length(request$res_outcomes) > 0) {
    out <- out[out$outcome %in% request$res_outcomes, , drop = FALSE]
  }
  if (length(request$res_age_groups) > 0) {
    out <- out[out$age_group %in% request$res_age_groups, , drop = FALSE]
  }
  if (length(request$res_gender) > 0) {
    out <- out[out$gender %in% request$res_gender, , drop = FALSE]
  }

  out
}

.aggregate_results_health <- function(filtered, request) {
  if (nrow(filtered) == 0) {
    return(.empty_results_table(request))
  }

  group_cols <- c("outcome", "outcome_label", "outcome_type", "mode")
  if (identical(request$res_aggregation, "timeline")) {
    group_cols <- c(group_cols, "cycle")
  }
  if (identical(request$res_pop_aggregation, "age_group")) {
    group_cols <- c(group_cols, "age_group")
  } else if (identical(request$res_pop_aggregation, "gender")) {
    group_cols <- c(group_cols, "gender")
  }

  aggregated <- stats::aggregate(
    filtered[, c("ref_value", "cf_value", "delta_value"), drop = FALSE],
    by = filtered[, group_cols, drop = FALSE],
    FUN = sum,
    na.rm = TRUE
  )
  aggregated$population <- .results_population_by_group(filtered, group_cols, aggregated)
  aggregated$percent_change <- 100 * .results_divide_or_na(aggregated$delta_value, aggregated$ref_value)
  aggregated$prevented_value <- -aggregated$delta_value
  aggregated$percent_reduction <- -aggregated$percent_change
  aggregated$prevented_per_100000 <- 100000 * .results_divide_or_na(
    aggregated$prevented_value,
    aggregated$population
  )
  aggregated$impact_value <- if (identical(request$res_impact_type, "attributable")) {
    aggregated$prevented_value
  } else {
    aggregated$cf_value
  }

  cycle_sort <- if ("cycle" %in% names(aggregated)) aggregated$cycle else rep(0, nrow(aggregated))
  aggregated[order(aggregated$outcome_label, cycle_sort), , drop = FALSE]
}

.empty_results_table <- function(request) {
  cols <- list(
    outcome = character(0),
    outcome_label = character(0),
    outcome_type = character(0),
    mode = character(0)
  )
  if (identical(request$res_aggregation, "timeline")) {
    cols$cycle <- integer(0)
  }
  if (identical(request$res_pop_aggregation, "age_group")) {
    cols$age_group <- character(0)
  }
  if (identical(request$res_pop_aggregation, "gender")) {
    cols$gender <- character(0)
  }
  cols$ref_value <- numeric(0)
  cols$cf_value <- numeric(0)
  cols$delta_value <- numeric(0)
  cols$population <- numeric(0)
  cols$percent_change <- numeric(0)
  cols$prevented_value <- numeric(0)
  cols$percent_reduction <- numeric(0)
  cols$prevented_per_100000 <- numeric(0)
  cols$impact_value <- numeric(0)
  as.data.frame(cols, stringsAsFactors = FALSE)
}

# Headline Metrics -----------------------------------------------------------
# Headline tile values follow the Tab 5 draft labels. "Prevented" values are
# represented as `-delta`, so negative deltas become positive prevented counts.

.results_headline_metrics <- function(results_table) {
  mortality <- results_table[results_table$outcome == "mortality", , drop = FALSE]
  disease <- results_table[results_table$outcome_type == "disease", , drop = FALSE]

  mortality_delta <- sum(mortality$delta_value, na.rm = TRUE)
  disease_delta <- sum(disease$delta_value, na.rm = TRUE)

  list(
    premature_deaths_prevented = -mortality_delta,
    life_years_saved = NA_real_,
    disease_cases_prevented = -disease_delta,
    mortality_delta = mortality_delta,
    disease_cases_delta = disease_delta
  )
}

# Plot Data ------------------------------------------------------------------
# Keep plot-ready data independent from ggplot so UI can use the tables directly
# if it wants its own plotting layer.

.results_plot_health_overview_data <- function(results_table, request) {
  out <- results_table
  if (!"cycle" %in% names(out)) {
    out$cycle <- rep(NA_integer_, nrow(out))
  }
  out
}

.results_plot_timeline_data <- function(filtered, request) {
  if (nrow(filtered) == 0) {
    return(.empty_results_table(list(res_aggregation = "timeline", res_pop_aggregation = "total")))
  }

  out <- stats::aggregate(
    filtered[, c("ref_value", "cf_value", "delta_value"), drop = FALSE],
    by = filtered[, c("outcome", "outcome_label", "outcome_type", "mode", "cycle"), drop = FALSE],
    FUN = sum,
    na.rm = TRUE
  )
  group_cols <- c("outcome", "outcome_label", "outcome_type", "mode", "cycle")
  out$population <- .results_population_by_group(filtered, group_cols, out)
  out$prevented_value <- -out$delta_value
  out$percent_reduction <- -100 * .results_divide_or_na(out$delta_value, out$ref_value)
  out$prevented_per_100000 <- 100000 * .results_divide_or_na(out$prevented_value, out$population)
  out
}

.results_trip_mode_distribution <- function(reference_data, counterfactual_data) {
  ref <- if (!is.null(reference_data)) reference_data$trips else NULL
  cf <- counterfactual_data$trips
  if (is.null(ref) || is.null(cf) || !"trip_mainmode" %in% names(ref) || !"trip_mainmode" %in% names(cf)) {
    return(data.frame(
      scenario = character(0),
      mode = character(0),
      mode_label = character(0),
      trips = numeric(0),
      proportion = numeric(0)
    ))
  }

  out <- rbind(
    .trip_mode_distribution_one(ref, "Reference"),
    .trip_mode_distribution_one(cf, "Counterfactual")
  )
  row.names(out) <- NULL
  out
}

.trip_mode_distribution_one <- function(trips, scenario) {
  weights <- .trip_weights(trips)
  mode <- .results_trip_mode_group(trips$trip_mainmode)
  totals <- stats::aggregate(weights, by = list(mode = mode), FUN = sum, na.rm = TRUE)
  names(totals)[names(totals) == "x"] <- "trips"
  totals$scenario <- scenario
  totals$proportion <- .results_divide_or_na(totals$trips, sum(totals$trips, na.rm = TRUE))
  labels <- c(
    walking = "Walking", cycling = "Cycling", pt = "Public transport",
    driving = "Driving", other = "Other"
  )
  totals$mode_label <- unname(labels[totals$mode])
  totals[, c("scenario", "mode", "mode_label", "trips", "proportion")]
}

.results_trip_mode_group <- function(values) {
  numeric_values <- suppressWarnings(as.numeric(as.character(values)))
  text_values <- tolower(as.character(values))
  out <- rep("other", length(values))

  is_walk <- (!is.na(numeric_values) & numeric_values == MIAMA_NTS_MAINMODE_B04[["walk"]]) |
    grepl("walk", text_values)
  is_bike <- (!is.na(numeric_values) & numeric_values == MIAMA_NTS_MAINMODE_B04[["bicycle"]]) |
    grepl("bicy|cycl|e[- ]?bike", text_values)
  is_pt <- (!is.na(numeric_values) & numeric_values %in% MIAMA_NTS_MAINMODE_PT_CODES) |
    grepl("public|bus|rail|train|tram|metro|underground|tube|coach", text_values)
  is_driving <- (!is.na(numeric_values) & numeric_values %in% unname(MIAMA_NTS_MAINMODE_B04[c(
    "car_driver", "car_passenger"
  )])) | grepl("car|van|driver|passenger", text_values)

  out[is_driving] <- "driving"
  out[is_pt] <- "pt"
  out[is_bike] <- "cycling"
  out[is_walk] <- "walking"
  out
}

# Report ---------------------------------------------------------------------
# Capture current filters and known gaps so the first draft is explicit about
# what Tab 5 controls are and are not doing yet.

.results_report <- function(
    health_outcomes,
    long,
    filtered,
    results_table,
    request,
    outcome_specs,
    trip_distribution,
    person_weight,
    population_source,
    cycle_zero_rows
) {
  available_outcomes <- unique(long$outcome)
  requested_outcomes <- request$res_outcomes
  missing_requested <- setdiff(requested_outcomes, available_outcomes)

  notes <- character(0)
  if (length(request$res_modes_filter) > 0) {
    notes <- c(notes, "Mode-specific health impact attribution is not implemented yet; health results use `mode = all_modes`.")
  }
  if (length(missing_requested) > 0) {
    notes <- c(notes, paste0("Requested outcomes not available in current health outputs: ", paste(missing_requested, collapse = ", ")))
  }
  if (is.na(.results_headline_metrics(results_table)$life_years_saved)) {
    notes <- c(notes, "Life-years/HALY headline metric needs final formula and is currently returned as NA.")
  }

  list(
    n_health_rows = nrow(health_outcomes),
    cycle_zero_rows_excluded = cycle_zero_rows,
    population_person_weight = person_weight,
    population_scaling_source = population_source,
    n_long_rows = nrow(long),
    n_filtered_rows = nrow(filtered),
    n_results_rows = nrow(results_table),
    filters = request,
    available_outcomes = available_outcomes,
    missing_requested_outcomes = missing_requested,
    trip_distribution_available = nrow(trip_distribution) > 0,
    notes = unique(notes)
  )
}

# Small Helpers --------------------------------------------------------------

.results_age_group_levels <- function() {
  data.frame(
    id = c("age_20_34", "age_35_49", "age_50_64", "age_65_74", "age_75plus"),
    label = c("20-34", "35-49", "50-64", "65-74", "75+"),
    stringsAsFactors = FALSE
  )
}

.results_age_group <- function(age) {
  out <- rep(NA_character_, length(age))
  out[!is.na(age) & age >= 20 & age <= 34] <- "age_20_34"
  out[!is.na(age) & age >= 35 & age <= 49] <- "age_35_49"
  out[!is.na(age) & age >= 50 & age <= 64] <- "age_50_64"
  out[!is.na(age) & age >= 65 & age <= 74] <- "age_65_74"
  out[!is.na(age) & age >= 75] <- "age_75plus"
  out
}

.results_divide_or_na <- function(numerator, denominator) {
  out <- numerator / denominator
  out[is.na(denominator) | denominator == 0] <- NA_real_
  out
}

.results_person_weight <- function(cfg) {
  value <- cfg$population$person_weight %||% MIAMA_SYNTHPOP_PERSON_WEIGHT
  value <- suppressWarnings(as.numeric(value))
  if (length(value) != 1 || !is.finite(value) || value <= 0) {
    stop("cfg$population$person_weight must be one positive finite number.", call. = FALSE)
  }
  value
}

.results_population_by_group <- function(data, group_cols, grouped_result) {
  keys <- unique(data[, unique(c(group_cols, "census_id", "population")), drop = FALSE])
  population <- stats::aggregate(
    keys$population,
    by = keys[, group_cols, drop = FALSE],
    FUN = sum,
    na.rm = TRUE
  )
  names(population)[ncol(population)] <- "population"
  group_key <- function(x) do.call(paste, c(lapply(x[, group_cols, drop = FALSE], as.character), sep = "\r"))
  matched <- match(group_key(grouped_result), group_key(population))
  population$population[matched]
}
