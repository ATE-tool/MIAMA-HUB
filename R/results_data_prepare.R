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
# Mode attribution:
# - `all_modes` remains the canonical health-model total.
# - Mode-specific health deltas are allocated per person in proportion to that
#   person's signed counterfactual MMET delta from walking, cycling, e-biking,
#   public-transport access walking, or other activity. Absolute
#   reference/counterfactual burdens are not mode-specific.
# - Life years, healthy life years, and HALYs follow the MIAMA-HM verification
#   formulas. HALYs are calculated in Step 7 from reconstructed prevalence,
#   residual pYLD, and comorbidity-adjusted disability weights.

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
  age_group_levels <- .results_age_group_levels(cfg)
  request <- .results_request_defaults(results_request, appraisal_input_values, cfg)
  outcome_specs <- .results_outcome_specs(cfg)
  outcome_levels <- data.frame(
    id = names(outcome_specs),
    label = vapply(outcome_specs, function(x) x$label, character(1)),
    stringsAsFactors = FALSE
  )
  person_weight <- .results_person_weight(cfg)

  long <- .results_health_long(health_outcomes, outcome_specs, person_weight, cfg)
  mode_attribution <- .results_mmet_mode_attribution(counterfactual_data$ind)
  health_cube <- .results_health_cube(long, mode_attribution)
  filtered <- .filter_results_health_long(health_cube, request)
  results_table <- .aggregate_results_health(filtered, request)

  trip_distribution <- .results_trip_mode_distribution(reference_data, counterfactual_data)
  amat_health_timeline <- .results_amat_health_timeline(
    health_outcomes = health_outcomes_all,
    health_cube = health_cube,
    person_weight = person_weight,
    horizon_years = get_assessment_period(cfg)
  )
  headline_metrics <- .results_headline_metrics(
    health_outcomes = health_outcomes,
    amat_health_timeline = amat_health_timeline,
    cfg = cfg,
    person_weight = person_weight
  )
  plot_data <- list(
    health_cube = health_cube,
    mode_attribution = mode_attribution,
    age_group_levels = age_group_levels,
    outcome_levels = outcome_levels,
    amat_health_timeline = amat_health_timeline,
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
    cycle_zero_rows = cycle_zero_rows,
    amat_health_timeline = amat_health_timeline,
    assessment_period_years = get_assessment_period(cfg),
    mode_attribution = mode_attribution
  )

  list(
    results_request = request,
    headline_metrics = headline_metrics,
    results_table = results_table,
    plot_data = plot_data,
    results_report = report
  )
}

# AMAT Health Timeline ------------------------------------------------------
# MIAMA-HM defines life years in cycle t as 1 - cumulative death incidence and
# healthy life years as 1 - cumulative unhealth incidence. Incidence outcomes
# are already cycle-specific. This table keeps both the technical `cf - ref`
# delta and a benefit-oriented value whose positive sign always means health
# improvement.

.results_amat_health_timeline <- function(health_outcomes,
                                          health_cube,
                                          person_weight,
                                          horizon_years = 40L) {
  horizon_years <- .results_validate_horizon(horizon_years)
  incidence <- .results_amat_incidence_timeline(health_cube, horizon_years)
  years <- .results_amat_years_timeline(
    health_outcomes,
    person_weight = person_weight,
    horizon_years = horizon_years
  )
  out <- rbind(years, incidence)
  if (nrow(out) == 0) return(.empty_amat_health_timeline())
  out <- out[order(out$measure_type, out$measure, out$cycle), , drop = FALSE]
  rownames(out) <- NULL
  out
}

.results_amat_years_timeline <- function(health_outcomes,
                                         person_weight,
                                         horizon_years) {
  required <- c("census_id", "cycle")
  if (!all(required %in% names(health_outcomes))) {
    return(.empty_amat_health_timeline())
  }

  keep <- !is.na(health_outcomes$cycle) & health_outcomes$cycle >= 0 &
    health_outcomes$cycle <= horizon_years
  if (!any(keep)) return(.empty_amat_health_timeline())

  value_cols <- intersect(
    c(
      "census_id", "cycle",
      "dead", "d_dead", "dead_cf",
      "unhealthy", "d_unhealthy", "unhealthy_cf",
      "haly", "d_haly", "haly_cf"
    ),
    names(health_outcomes)
  )
  # The health table is wide. AMAT life-year calculations need only these
  # columns, so avoid copying every disease stream for every person-cycle row.
  x <- health_outcomes[keep, value_cols, drop = FALSE]
  ord <- order(x$census_id, x$cycle)
  ids <- x$census_id[ord]
  cycles <- as.integer(x$cycle[ord])

  build_measure <- function(measure, ref_col, delta_col, cf_col, direct_values = FALSE) {
    if (!ref_col %in% names(x)) return(NULL)
    ref_incidence <- .as_plain_numeric(x[[ref_col]][ord])
    cf_incidence <- if (cf_col %in% names(x)) {
      .as_plain_numeric(x[[cf_col]][ord])
    } else if (delta_col %in% names(x)) {
      ref_incidence + .as_plain_numeric(x[[delta_col]][ord])
    } else {
      return(NULL)
    }

    ref_value <- if (isTRUE(direct_values)) {
      ref_incidence
    } else {
      1 - .results_grouped_cumsum(ref_incidence, ids)
    }
    cf_value <- if (isTRUE(direct_values)) {
      cf_incidence
    } else {
      1 - .results_grouped_cumsum(cf_incidence, ids)
    }
    # Cycle 0 initializes survival/healthy state but earns no reported years.
    report_rows <- cycles > 0
    if (!any(report_rows)) return(NULL)
    aggregated <- stats::aggregate(
      cbind(ref_value, cf_value)[report_rows, , drop = FALSE] * person_weight,
      by = list(cycle = cycles[report_rows]),
      FUN = sum,
      na.rm = TRUE
    )
    .results_amat_timeline_rows(
      measure = measure,
      measure_label = switch(
        measure,
        life_years = "Life years",
        healthy_life_years = "Healthy life years",
        halys = "Health-adjusted life years (HALYs)"
      ),
      measure_type = measure,
      unit = "person-years",
      direction = "higher_is_better",
      cycle = aggregated$cycle,
      ref_value = aggregated$ref_value,
      cf_value = aggregated$cf_value
    )
  }

  rows <- list(
    build_measure("life_years", "dead", "d_dead", "dead_cf"),
    build_measure("healthy_life_years", "unhealthy", "d_unhealthy", "unhealthy_cf"),
    build_measure("halys", "haly", "d_haly", "haly_cf", direct_values = TRUE)
  )
  rows <- rows[!vapply(rows, is.null, logical(1))]
  if (length(rows) == 0) .empty_amat_health_timeline() else do.call(rbind, rows)
}

.results_amat_incidence_timeline <- function(health_cube, horizon_years) {
  if (is.null(health_cube) || nrow(health_cube) == 0) {
    return(.empty_amat_health_timeline())
  }
  keep <- !is.na(health_cube$cycle) & health_cube$cycle > 0 &
    health_cube$cycle <= horizon_years & health_cube$mode == "all_modes" &
    health_cube$outcome_type != "health_years"
  # The cube has already aggregated person-outcome rows by cycle, age, and
  # gender. Reusing it avoids a second aggregate over the much larger long
  # person-cycle-outcome table.
  x <- health_cube[keep, , drop = FALSE]
  if (nrow(x) == 0) return(.empty_amat_health_timeline())

  aggregated <- stats::aggregate(
    x[, c("ref_value", "cf_value"), drop = FALSE],
    by = x[, c("outcome", "outcome_label", "outcome_type", "cycle"), drop = FALSE],
    FUN = sum,
    na.rm = TRUE
  )
  rows <- lapply(seq_len(nrow(aggregated)), function(i) {
    type <- if (identical(aggregated$outcome_type[[i]], "mortality")) "deaths" else "disease_cases"
    .results_amat_timeline_rows(
      measure = aggregated$outcome[[i]],
      measure_label = aggregated$outcome_label[[i]],
      measure_type = type,
      unit = if (identical(type, "deaths")) "deaths" else "disease cases",
      direction = "lower_is_better",
      cycle = aggregated$cycle[[i]],
      ref_value = aggregated$ref_value[[i]],
      cf_value = aggregated$cf_value[[i]]
    )
  })
  out <- do.call(rbind, rows)

  # Cumulative values must run within outcome, not in the row order inherited
  # from aggregate(). Rebuild each outcome as an ordered series.
  groups <- split(out, out$measure)
  groups <- lapply(groups, function(group) {
    group <- group[order(group$cycle), , drop = FALSE]
    group$cumulative_delta_cf_minus_ref <- cumsum(group$annual_delta_cf_minus_ref)
    group$cumulative_benefit <- cumsum(group$annual_benefit)
    group
  })
  do.call(rbind, groups)
}

.results_amat_timeline_rows <- function(measure,
                                        measure_label,
                                        measure_type,
                                        unit,
                                        direction,
                                        cycle,
                                        ref_value,
                                        cf_value) {
  delta <- cf_value - ref_value
  benefit <- if (identical(direction, "higher_is_better")) delta else -delta
  data.frame(
    measure = measure,
    measure_label = measure_label,
    measure_type = measure_type,
    cycle = as.integer(cycle),
    reference_value = as.numeric(ref_value),
    counterfactual_value = as.numeric(cf_value),
    annual_delta_cf_minus_ref = as.numeric(delta),
    annual_benefit = as.numeric(benefit),
    cumulative_delta_cf_minus_ref = cumsum(as.numeric(delta)),
    cumulative_benefit = cumsum(as.numeric(benefit)),
    unit = unit,
    benefit_direction = direction,
    stringsAsFactors = FALSE
  )
}

.results_grouped_cumsum <- function(values, groups) {
  values <- as.numeric(values)
  values[is.na(values)] <- 0
  if (length(values) == 0) return(numeric(0))
  cumulative <- cumsum(values)
  starts <- c(TRUE, groups[-1] != groups[-length(groups)])
  start_index <- which(starts)
  lengths <- diff(c(start_index, length(values) + 1L))
  previous <- c(0, cumulative[start_index[-1] - 1L])
  cumulative - rep(previous, lengths)
}

.results_benefit_sign <- function(outcome_type) {
  ifelse(as.character(outcome_type) == "health_years", 1, -1)
}

.results_validate_horizon <- function(horizon_years) {
  if (length(horizon_years) != 1 || is.na(horizon_years) ||
      horizon_years < 1 || horizon_years != as.integer(horizon_years)) {
    stop("horizon_years must be one positive whole number.", call. = FALSE)
  }
  as.integer(horizon_years)
}

.empty_amat_health_timeline <- function() {
  data.frame(
    measure = character(0), measure_label = character(0),
    measure_type = character(0), cycle = integer(0),
    reference_value = numeric(0), counterfactual_value = numeric(0),
    annual_delta_cf_minus_ref = numeric(0), annual_benefit = numeric(0),
    cumulative_delta_cf_minus_ref = numeric(0), cumulative_benefit = numeric(0),
    unit = character(0), benefit_direction = character(0),
    stringsAsFactors = FALSE
  )
}

.results_health_cube <- function(long, mode_attribution = NULL) {
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
  all_modes <- stats::aggregate(
    long[keep, c("ref_value", "cf_value", "delta_value", "population"), drop = FALSE],
    by = long[keep, c(
      "outcome", "outcome_label", "outcome_type", "cycle",
      "age_group", "gender"
    ), drop = FALSE],
    FUN = sum,
    na.rm = TRUE
  )
  all_modes$mode <- "all_modes"
  all_modes <- all_modes[, c(
    "outcome", "outcome_label", "outcome_type", "mode", "cycle",
    "age_group", "gender", "ref_value", "cf_value", "delta_value", "population"
  ), drop = FALSE]

  attributed <- .results_attributed_health_cube(long[keep, , drop = FALSE], mode_attribution)
  if (nrow(attributed) == 0) return(all_modes)
  out <- rbind(all_modes, attributed)
  rownames(out) <- NULL
  out
}

.results_mmet_mode_attribution <- function(ind, tolerance = 1e-10) {
  empty <- data.frame(
    census_id = integer(0), mode = character(0), mmet_delta = numeric(0),
    attribution_share = numeric(0), stringsAsFactors = FALSE
  )
  if (is.null(ind) || !all(c("census_id", "cf_mmet_delta") %in% names(ind))) {
    return(empty)
  }

  mode_columns <- c(
    walking = "cf_mmet_delta_walking",
    cycling = "cf_mmet_delta_cycling",
    ebiking = "cf_mmet_delta_ebiking",
    pt = "cf_mmet_delta_pt",
    other_activity = "cf_mmet_delta_other_activity"
  )
  if (!any(mode_columns %in% names(ind))) return(empty)

  total <- .as_plain_numeric(ind$cf_mmet_delta)
  components <- lapply(mode_columns, function(column) {
    if (!column %in% names(ind)) return(rep(0, nrow(ind)))
    value <- .as_plain_numeric(ind[[column]])
    value[!is.finite(value)] <- 0
    value
  })
  components <- as.data.frame(components, stringsAsFactors = FALSE)
  residual <- total - rowSums(components)
  residual[!is.finite(residual) | abs(residual) <= tolerance] <- 0
  components$unattributed <- residual

  changed <- is.finite(total) & abs(total) > tolerance
  if (!any(changed)) return(empty)

  rows <- lapply(names(components), function(mode) {
    value <- components[[mode]][changed]
    data.frame(
      census_id = ind$census_id[changed],
      mode = mode,
      mmet_delta = value,
      attribution_share = value / total[changed],
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  out <- out[is.finite(out$attribution_share) & abs(out$mmet_delta) > tolerance, , drop = FALSE]
  rownames(out) <- NULL
  out
}

.results_attributed_health_cube <- function(long, mode_attribution) {
  if (is.null(mode_attribution) || nrow(mode_attribution) == 0 || nrow(long) == 0) {
    return(.empty_results_health_cube())
  }

  modes <- unique(as.character(mode_attribution$mode))
  group_cols <- c(
    "outcome", "outcome_label", "outcome_type", "cycle",
    "age_group", "gender"
  )
  rows <- lapply(modes, function(mode) {
    shares <- mode_attribution[mode_attribution$mode == mode, c("census_id", "attribution_share"), drop = FALSE]
    matched <- match(long$census_id, shares$census_id)
    share <- shares$attribution_share[matched]
    share[is.na(share)] <- 0

    # Do not copy the complete person-outcome table once per mode. Only the
    # grouping columns and two values are required for attributed aggregation.
    x <- long[, c(group_cols, "delta_value", "population"), drop = FALSE]
    x$delta_value <- x$delta_value * share
    grouped <- stats::aggregate(
      x[, c("delta_value", "population"), drop = FALSE],
      by = x[, group_cols, drop = FALSE],
      FUN = sum,
      na.rm = TRUE
    )
    grouped$mode <- mode
    grouped$ref_value <- NA_real_
    grouped$cf_value <- NA_real_
    grouped[, c(
      "outcome", "outcome_label", "outcome_type", "mode", "cycle",
      "age_group", "gender", "ref_value", "cf_value", "delta_value", "population"
    ), drop = FALSE]
  })
  do.call(rbind, rows)
}

.empty_results_health_cube <- function() {
  data.frame(
    outcome = character(0), outcome_label = character(0), outcome_type = character(0),
    mode = character(0), cycle = integer(0), age_group = character(0),
    gender = character(0), ref_value = numeric(0), cf_value = numeric(0),
    delta_value = numeric(0), population = numeric(0), stringsAsFactors = FALSE
  )
}

# Request Normalisation ------------------------------------------------------
# Tab 5 names are still settling. This helper accepts both the current UI
# `res_aggregation` field and the schema's `res_temp_aggregation` alias.

.results_request_defaults <- function(results_request, appraisal_input_values = list(), cfg = NULL) {
  values <- utils::modifyList(appraisal_input_values, results_request)
  aggregation <- .ui_value(values, "res_aggregation", NULL) %||%
    .ui_value(values, "res_temp_aggregation", "total")

  list(
    res_outcomes = .ui_value(values, "res_outcomes", character(0)),
    res_age_groups = .ui_value(values, "res_age_groups", .results_age_group_levels(cfg)$id),
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

.results_outcome_specs <- function(cfg = NULL) {
  .miama_health_outcome_specs(cfg)
}

.results_health_long <- function(health_outcomes, outcome_specs, person_weight = 1, cfg = NULL) {
  if (nrow(health_outcomes) == 0) {
    return(.empty_results_long())
  }

  required <- c("census_id", "cycle", "age1year", "female")
  missing <- setdiff(required, names(health_outcomes))
  if (length(missing) > 0) {
    stop("Health outcomes are missing required Step 8 columns: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  # These classifications are invariant across outcomes and expensive on a
  # full person-cycle table, so calculate them once rather than in every row
  # of the outcome catalogue.
  age_group <- .results_age_group(health_outcomes$age1year, cfg)
  gender <- ifelse(health_outcomes$female == 1, "female", "male")

  rows <- lapply(names(outcome_specs), function(outcome_id) {
    spec <- outcome_specs[[outcome_id]]
    raw_cols <- as.character(spec$columns)
    if (!all(raw_cols %in% names(health_outcomes))) {
      return(NULL)
    }

    delta_cols <- paste0("d_", raw_cols)
    if (!all(delta_cols %in% names(health_outcomes))) {
      return(NULL)
    }

    cf_cols <- paste0(raw_cols, "_cf")

    ref_value <- rowSums(health_outcomes[, raw_cols, drop = FALSE], na.rm = TRUE)
    delta_value <- rowSums(health_outcomes[, delta_cols, drop = FALSE], na.rm = TRUE)
    cf_value <- if (all(cf_cols %in% names(health_outcomes))) {
      rowSums(health_outcomes[, cf_cols, drop = FALSE], na.rm = TRUE)
    } else {
      ref_value + delta_value
    }

    data.frame(
      census_id = health_outcomes$census_id,
      cycle = health_outcomes$cycle,
      age_group = age_group,
      gender = gender,
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
    age_group = character(0),
    gender = character(0),
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
# Filter by Tab 5 controls, then aggregate either across all available model
# cycles or to cycle timelines. Population strata are retained when requested.

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

  available_modes <- unique(as.character(out$mode))
  requested_modes <- .results_normalize_health_modes(request$res_modes_filter)
  selected_modes <- intersect(requested_modes, setdiff(available_modes, "all_modes"))
  if (length(selected_modes) == 0 && "all_modes" %in% available_modes) {
    selected_modes <- "all_modes"
  }
  if (length(selected_modes) > 0) {
    out <- out[out$mode %in% selected_modes, , drop = FALSE]
  }

  out
}

.results_normalize_health_modes <- function(modes) {
  map <- c(
    all = "all_modes", all_modes = "all_modes",
    walking = "walking", walk = "walking",
    cycling = "cycling", bike = "cycling",
    ebiking = "ebiking", ebike = "ebiking",
    pt = "pt", public_transport = "pt",
    other_activity = "other_activity", unattributed = "unattributed"
  )
  values <- unname(map[as.character(modes)])
  unique(values[!is.na(values)])
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
  attributed <- aggregated$mode != "all_modes"
  aggregated$ref_value[attributed] <- NA_real_
  aggregated$cf_value[attributed] <- NA_real_
  aggregated$population <- .results_cube_population(filtered, group_cols, aggregated)
  aggregated$percent_change <- 100 * .results_divide_or_na(aggregated$delta_value, aggregated$ref_value)
  benefit_sign <- .results_benefit_sign(aggregated$outcome_type)
  aggregated$prevented_value <- benefit_sign * aggregated$delta_value
  aggregated$percent_reduction <- benefit_sign * aggregated$percent_change
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
# Headline tile values follow the Tab 5 draft labels and are rounded to whole
# people or life-years for presentation. Detailed result tables remain unrounded.
# "Prevented" values are represented as `-delta`, so negative deltas become
# positive prevented counts.

.results_headline_metrics <- function(health_outcomes,
                                      amat_health_timeline,
                                      cfg,
                                      person_weight) {
  period <- cfg$results$assessment_period_years %||% 40L
  benefit <- function(measure) {
    rows <- amat_health_timeline[amat_health_timeline$measure == measure, , drop = FALSE]
    if (nrow(rows) == 0) return(NA_real_)
    rows$cumulative_benefit[[which.max(rows$cycle)]]
  }

  configured_diseases <- as.character(
    cfg$results$headline_disease_columns %||% .miama_default_disease_incidence_columns()
  )
  available_diseases <- configured_diseases[
    configured_diseases %in% names(health_outcomes) &
      paste0("d_", configured_diseases) %in% names(health_outcomes)
  ]
  keep <- !is.na(health_outcomes$cycle) & health_outcomes$cycle > 0 &
    health_outcomes$cycle <= period
  disease_delta <- if (length(available_diseases) == 0 || !any(keep)) {
    NA_real_
  } else {
    sum(
      as.matrix(health_outcomes[keep, paste0("d_", available_diseases), drop = FALSE]),
      na.rm = TRUE
    ) * person_weight
  }

  round_headline <- function(value) {
    if (is.na(value)) NA_real_ else round(value)
  }
  mortality_prevented <- round_headline(benefit("mortality"))
  life_years_saved <- round_headline(benefit("life_years"))
  disease_cases_prevented <- round_headline(
    if (is.na(disease_delta)) NA_real_ else -disease_delta
  )
  halys_gained <- round_headline(benefit("halys"))
  list(
    premature_deaths_prevented = mortality_prevented,
    life_years_saved = life_years_saved,
    disease_cases_prevented = disease_cases_prevented,
    halys_gained = halys_gained,
    mortality_delta = if (is.na(mortality_prevented)) NA_real_ else -mortality_prevented,
    disease_cases_delta = if (is.na(disease_cases_prevented)) NA_real_ else -disease_cases_prevented,
    assessment_period_years = as.integer(period),
    disease_columns_used = available_diseases,
    disease_columns_missing = setdiff(configured_diseases, available_diseases)
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
  attributed <- out$mode != "all_modes"
  out$ref_value[attributed] <- NA_real_
  out$cf_value[attributed] <- NA_real_
  group_cols <- c("outcome", "outcome_label", "outcome_type", "mode", "cycle")
  out$population <- .results_cube_population(filtered, group_cols, out)
  benefit_sign <- .results_benefit_sign(out$outcome_type)
  out$prevented_value <- benefit_sign * out$delta_value
  out$percent_reduction <- benefit_sign * 100 * .results_divide_or_na(out$delta_value, out$ref_value)
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
  scenario_scope <- if (identical(scenario, "Reference")) "ref" else "cf"
  if (paste0(scenario_scope, "_in_scope") %in% names(trips)) {
    trips <- trips[.true_values(trips[[paste0(scenario_scope, "_in_scope")]]), , drop = FALSE]
  }
  # Appraisal trip counts use the transparent row-count contract: one
  # synthetic trip row is one trip record. Survey weights remain available in
  # the source data but do not alter UI targets or result trip totals.
  weights <- rep(1, nrow(trips))
  mode <- .results_trip_mode_group(trips$trip_mainmode)
  totals <- if (nrow(trips) == 0) {
    data.frame(mode = character(0), trips = numeric(0))
  } else {
    out <- stats::aggregate(weights, by = list(mode = mode), FUN = sum, na.rm = TRUE)
    names(out)[names(out) == "x"] <- "trips"
    out
  }

  # All four mode inputs are defined by their mode-specific trip
  # evidence, not exclusively by `trip_mainmode`. Use the same filters here as
  # reference-default extraction and counterfactual sampling so a weekly target
  # entered in the modal is the quantity displayed in results and exports.
  active_specs <- .miama_tab2_mode_specs()[.miama_supported_modes()]
  for (active_mode in names(active_specs)) {
    if (!.trip_evidence_available_for_counterfactual(trips, active_specs[[active_mode]])) {
      next
    }
    active <- active_specs[[active_mode]]$trip_filter(trips)
    mode_scope_col <- .reference_trip_scope_col(active_mode, scenario_scope)
    if (mode_scope_col %in% names(trips)) {
      active <- active & .true_values(trips[[mode_scope_col]])
    }
    active_total <- sum(weights[active], na.rm = TRUE)
    row <- match(active_mode, totals$mode)
    if (is.na(row)) {
      totals <- rbind(totals, data.frame(mode = active_mode, trips = active_total))
    } else {
      totals$trips[row] <- active_total
    }
  }

  totals$scenario <- scenario
  totals$proportion <- .results_divide_or_na(totals$trips, sum(totals$trips, na.rm = TRUE))
  labels <- c(
    walking = "Walking", cycling = "Cycling", ebiking = "E-biking",
    pt = "Public transport",
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
  is_ebike <- grepl("e[- ]?bike|electric bicy|electric cycl", text_values)
  is_bike <- ((!is.na(numeric_values) & numeric_values == MIAMA_NTS_MAINMODE_B04[["bicycle"]]) |
    grepl("bicy|cycl", text_values)) & !is_ebike
  is_pt <- (!is.na(numeric_values) & numeric_values %in% MIAMA_NTS_MAINMODE_PT_CODES) |
    grepl("^pt$|public|bus|rail|train|tram|metro|underground|tube|coach", text_values)
  is_driving <- (!is.na(numeric_values) & numeric_values %in% MIAMA_NTS_MAINMODE_CAR_CODES) |
    grepl("car|van|driver|passenger|motorcycle|taxi|private", text_values)

  out[is_driving] <- "driving"
  out[is_pt] <- "pt"
  out[is_bike] <- "cycling"
  out[is_ebike] <- "ebiking"
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
    cycle_zero_rows,
    amat_health_timeline,
    assessment_period_years,
    mode_attribution
) {
  available_outcomes <- unique(long$outcome)
  requested_outcomes <- request$res_outcomes
  missing_requested <- setdiff(requested_outcomes, available_outcomes)

  notes <- character(0)
  mode_summary <- .results_mode_attribution_summary(mode_attribution)
  if (nrow(mode_summary) == 0) {
    notes <- c(notes, "Mode-specific MMET attribution was unavailable; health results use `mode = all_modes`.")
  } else {
    notes <- c(notes, paste0(
      "Mode-specific health deltas are allocated per individual using signed shares of counterfactual MMET change; ",
      "absolute reference and counterfactual burdens remain `all_modes`."
    ))
  }
  if (length(missing_requested) > 0) {
    notes <- c(notes, paste0("Requested outcomes not available in current health outputs: ", paste(missing_requested, collapse = ", ")))
  }
  if (!"life_years" %in% amat_health_timeline$measure) {
    notes <- c(notes, "Life years are unavailable because required cycle death columns were not present.")
  }
  if (!"halys" %in% available_outcomes) {
    notes <- c(notes, "HALYs were unavailable because Step 7 did not produce `haly` and `d_haly` columns.")
  }

  list(
    n_health_rows = nrow(health_outcomes),
    cycle_zero_rows_excluded = cycle_zero_rows,
    population_person_weight = person_weight,
    population_scaling_source = population_source,
    assessment_period_years = assessment_period_years,
    n_long_rows = nrow(long),
    n_filtered_rows = nrow(filtered),
    n_results_rows = nrow(results_table),
    filters = request,
    available_outcomes = available_outcomes,
    missing_requested_outcomes = missing_requested,
    mode_attribution = mode_summary,
    trip_distribution_available = nrow(trip_distribution) > 0,
    notes = unique(notes)
  )
}

.results_mode_attribution_summary <- function(mode_attribution) {
  if (is.null(mode_attribution) || nrow(mode_attribution) == 0) {
    return(data.frame(
      mode = character(0), changed_individuals = integer(0),
      mmet_delta = numeric(0), share_of_net_mmet_delta = numeric(0),
      stringsAsFactors = FALSE
    ))
  }
  totals <- stats::aggregate(
    mode_attribution$mmet_delta,
    by = list(mode = mode_attribution$mode),
    FUN = sum,
    na.rm = TRUE
  )
  names(totals)[names(totals) == "x"] <- "mmet_delta"
  changed <- stats::aggregate(
    mode_attribution$census_id,
    by = list(mode = mode_attribution$mode),
    FUN = function(x) length(unique(x))
  )
  names(changed)[names(changed) == "x"] <- "changed_individuals"
  out <- merge(totals, changed, by = "mode", all = TRUE, sort = FALSE)
  net <- sum(out$mmet_delta, na.rm = TRUE)
  out$share_of_net_mmet_delta <- if (is.finite(net) && abs(net) > 1e-10) {
    out$mmet_delta / net
  } else {
    NA_real_
  }
  out[, c("mode", "changed_individuals", "mmet_delta", "share_of_net_mmet_delta")]
}

# Small Helpers --------------------------------------------------------------

.results_age_group_levels <- function(cfg = NULL) {
  cfg <- cfg %||% miama_default_config()
  spec <- cfg$population_refinement$age %||%
    miama_default_config()$population_refinement$age
  classified_ids <- setdiff(as.character(spec$ids), spec$other_id %||% character(0))
  lower <- upper <- rep(NA_real_, length(spec$ids))
  classified_rows <- match(classified_ids, spec$ids)
  lower[classified_rows] <- as.numeric(spec$breaks[-length(spec$breaks)])
  upper[classified_rows] <- as.numeric(spec$breaks[-1])
  data.frame(
    id = as.character(spec$ids),
    label = as.character(spec$labels),
    lower = lower,
    upper = upper,
    stringsAsFactors = FALSE
  )
}

.results_age_group <- function(age, cfg = NULL) {
  cfg <- cfg %||% miama_default_config()
  spec <- cfg$population_refinement$age %||%
    miama_default_config()$population_refinement$age
  category <- .population_refinement_categories(age, spec)
  as.character(spec$ids[category])
}

.results_divide_or_na <- function(numerator, denominator) {
  out <- numerator / denominator
  out[is.na(denominator) | denominator == 0] <- NA_real_
  out
}

.results_person_weight <- function(cfg) {
  value <- cfg$population$person_weight %||% 1
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
