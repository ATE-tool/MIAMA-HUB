# MIAMA-HUB Module: Reference Data / Extract Reference UI Values
# Purpose: Derive compact values from `reference_data` to pre-populate or
#   update UI fields in MIAMA-UI.
# Inputs: Filtered `reference_data`, a `reference_request` spec, and optional
#   flattened `appraisal_input_values`.
# Outputs: Compact UI updates and related reference-side values.
# Notes: Keep this as the reference-to-UI interface. It should return small
#   objects rather than datasets.
#
# Current threshold assumptions:
# - Walking users: `walktime_wkhr > 0`.
# - Cycling users: `cycletime_wkhr > 0`.
# - Trip-level walking: `trip_walktime_min > 0` or `trip_walkdist_km > 0`.
# - Trip-level cycling: `trip_cycletime_min > 0` or `trip_cycledist_km > 0`.
# - Walk-to-PT: trip main mode looks like public transport and has positive
#   walking time or distance.
# - E-biking: unavailable until reference data exposes e-bike-specific columns
#   or a defensible classification rule.
# TODO: Make these thresholds configurable by mode. Candidate refinements
#   include walking users with `walktime_wkhr > 2`, or active-travel users/trips
#   meeting minimum trip-count thresholds such as > 10 trips.
#
# Spread-anchor assumptions:
# - Tab 3 population spreads use people with positive reference activity in the
#   selected mode(s); if no users are available, they fall back to the geography.
# - Tab 3 PA spreads use available `mmets`/`mmet_wkhr` values, or reconstruct a
#   pragmatic MMET-like value from walking, cycling, and sport hours.
# - Tab 4 trip spreads use active-mode trips in the selected mode(s); if none
#   are available, they fall back to all trips in the geography.
# - Spread bar defaults are compact 10-row data frames: five categories crossed
#   with two plotted variables.
# TODO: Confirm final age, PA, and trip-distance category definitions once
#   MIAMA-UI no longer treats them as provisional five-category spreads.

extract_reference_ui_values <- function(
    reference_data,
    reference_request = list(),
    appraisal_input_values = list(),
    cfg = NULL
) {
  if (length(reference_request) == 0 && is.null(names(reference_request))) {
    names(reference_request) <- character(0)
  }
  if (length(appraisal_input_values) == 0 && is.null(names(appraisal_input_values))) {
    names(appraisal_input_values) <- character(0)
  }

  assert_named_list(reference_data, "reference_data")
  assert_named_list(reference_request, "reference_request")
  assert_named_list(appraisal_input_values, "appraisal_input_values")

  ind <- reference_data$ind
  trips <- reference_data$trips

  population_size <- if (!is.null(ind)) nrow(ind) else NA_integer_
  context <- .reference_ui_context(appraisal_input_values)
  report <- list(
    at_data_unit = context$at_data_unit,
    modes = context$modes,
    calculation_modes = context$calculation_modes,
    base_timeframe = "week",
    notes = character(0),
    skipped_fields = character(0)
  )

  geo_name <- .reference_geo_name(reference_data, reference_request)
  ui_updates <- list(
    pop_total_ref = population_size,
    population_size = population_size,
    geo_name = geo_name
  )
  if (is.na(geo_name)) {
    report$notes <- c(report$notes, "geo_name could not be derived from filtered reference data.")
  }

  for (mode in context$calculation_modes) {
    if (!mode %in% names(.miama_tab2_mode_specs())) {
      report$notes <- c(report$notes, paste0("Unsupported mode ignored: ", mode))
      next
    }

    suffix <- .miama_mode_suffix(mode)

    field <- paste0("users_count_ref_", suffix)
    result <- .reference_users_count(ind, trips, mode)
    ui_updates[[field]] <- result$value
    report$notes <- c(report$notes, result$notes)

    field <- paste0("trips_count_ref_", suffix)
    result <- .reference_trips_count(
      trips = trips,
      mode = mode,
      timeframe = .ui_value(context$values, paste0("trips_timeframe_", suffix), "week"),
      denominator = .ui_value(context$values, paste0("trips_denominator_", suffix), "total"),
      population_size = population_size
    )
    ui_updates[[field]] <- result$value
    report$notes <- c(report$notes, result$notes)

    field <- paste0("dist_dur_amount_ref_", suffix)
    result <- .reference_dist_dur_amount(
      ind = ind,
      trips = trips,
      mode = mode,
      dist_dur_type = .ui_value(context$values, paste0("ui_dist_dur_type_", suffix), "distance"),
      distance_unit = .ui_value(context$values, paste0("distance_unit_", suffix), "km"),
      duration_unit = .ui_value(context$values, paste0("duration_unit_", suffix), "mins"),
      denominator = .ui_value(context$values, paste0("dist_dur_denominator_", suffix), "total"),
      timeframe = .ui_value(context$values, paste0("dist_dur_timeframe_", suffix), "week"),
      population_size = population_size
    )
    ui_updates[[field]] <- result$value
    report$notes <- c(report$notes, result$notes)
  }

  result <- .reference_mode_share_values(
    trips = trips,
    modes = context$mode_share_modes,
    total_unit = .reference_mode_share_total_unit(context$values),
    show_options = isTRUE(.ui_value(context$values, "ui_mode_share_show_options", FALSE)) ||
      isTRUE(.ui_value(context$values, "ui_trips_diversion_show_options", FALSE))
  )
  ui_updates <- utils::modifyList(ui_updates, result$ui_updates)
  report$notes <- c(report$notes, result$notes)

  tab3_result <- .reference_tab3_population_values(ind, trips, context, cfg = cfg)
  ui_updates <- utils::modifyList(ui_updates, tab3_result$ui_updates)
  report$notes <- c(report$notes, tab3_result$notes)

  tab4_result <- .reference_tab4_trip_values(trips, context, cfg = cfg)
  ui_updates <- utils::modifyList(ui_updates, tab4_result$ui_updates)
  report$notes <- c(report$notes, tab4_result$notes)

  report$spread_bar_values <- .reference_spread_bar_report(ui_updates)
  report$spread_bar_fields <- unique(report$spread_bar_values$field)
  report$notes <- unique(report$notes[nzchar(report$notes)])
  report$skipped_fields <- names(ui_updates)[vapply(ui_updates, function(x) {
    length(x) == 1 && is.na(x)
  }, logical(1))]

  list(
    reference_request = reference_request,
    appraisal_input_values = appraisal_input_values,
    ui_updates = ui_updates,
    extraction_report = report
  )
}

.reference_spread_bar_report <- function(ui_updates) {
  spread_fields <- names(ui_updates)[vapply(ui_updates, is.data.frame, logical(1))]
  spread_fields <- spread_fields[grepl("_spread_.*bars_ref", spread_fields)]

  required_cols <- c(
    "topic",
    "scenario",
    "category_order",
    "category",
    "category_midpoint",
    "variable_order",
    "variable",
    "percent",
    "proportion"
  )

  rows <- lapply(spread_fields, function(field) {
    values <- ui_updates[[field]]
    if (!all(required_cols %in% names(values))) {
      return(NULL)
    }

    values <- values[, required_cols, drop = FALSE]
    values$field <- field
    values <- values[, c("field", required_cols), drop = FALSE]
    values
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]

  if (length(rows) == 0) {
    return(data.frame())
  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

.reference_ui_context <- function(appraisal_input_values) {
  modes <- normalize_active_modes(.ui_value(appraisal_input_values, "modes", character(0)))
  if (length(modes) == 0) {
    modes <- c("walking", "cycling", "ebiking", "pt")
  }
  calculation_modes <- names(.miama_tab2_mode_specs())

  list(
    values = appraisal_input_values,
    modes = modes,
    calculation_modes = calculation_modes,
    mode_share_modes = names(.miama_tab2_mode_specs()),
    at_data_unit = .ui_value(appraisal_input_values, "at_data_unit", "trips"),
    trips_refine_method = .ui_value(appraisal_input_values, "trips_refine_method", NULL)
  )
}

.reference_geo_name <- function(reference_data, reference_request) {
  geo_level <- reference_request$geo_level %||% "eng"
  geo_level <- .normalize_geo_level(as.character(geo_level))
  geo_id <- reference_request$geo_id %||% NULL

  if (identical(geo_level, "eng")) {
    return("England")
  }
  if (identical(geo_level, "reg")) {
    if (is.null(geo_id) || length(geo_id) == 0 || is.na(geo_id[1])) {
      return(NA_character_)
    }
    return(as.character(geo_id[1]))
  }
  if (!identical(geo_level, "lad")) {
    return(NA_character_)
  }

  ind <- reference_data$ind
  if (is.null(ind) || !"lad25nm" %in% names(ind)) {
    return(NA_character_)
  }

  names <- unique(stats::na.omit(as.character(ind$lad25nm)))
  if (length(names) == 0) {
    return(NA_character_)
  }

  names[1]
}

.miama_tab2_mode_specs <- function() {
  list(
    walking = list(
      suffix = "walk",
      ind_duration_col = "walktime_wkhr",
      trip_distance_col = "trip_walkdist_km",
      trip_duration_col = "trip_walktime_min",
      needs_trip_mainmode = FALSE,
      trip_filter = function(trips) .positive_col(trips, "trip_walktime_min") |
        .positive_col(trips, "trip_walkdist_km")
    ),
    cycling = list(
      suffix = "bike",
      ind_duration_col = "cycletime_wkhr",
      trip_distance_col = "trip_cycledist_km",
      trip_duration_col = "trip_cycletime_min",
      needs_trip_mainmode = FALSE,
      trip_filter = function(trips) .positive_col(trips, "trip_cycletime_min") |
        .positive_col(trips, "trip_cycledist_km")
    ),
    ebiking = list(
      suffix = "ebike",
      ind_duration_col = NA_character_,
      trip_distance_col = NA_character_,
      trip_duration_col = NA_character_,
      needs_trip_mainmode = FALSE,
      trip_filter = function(trips) rep(FALSE, nrow(trips))
    ),
    pt = list(
      suffix = "pt",
      ind_duration_col = NA_character_,
      trip_distance_col = "trip_walkdist_km",
      trip_duration_col = "trip_walktime_min",
      needs_trip_mainmode = TRUE,
      trip_filter = function(trips) .pt_trip_filter(trips) &
        (.positive_col(trips, "trip_walktime_min") | .positive_col(trips, "trip_walkdist_km"))
    )
  )
}

.miama_mode_suffix <- function(mode) {
  .miama_tab2_mode_specs()[[mode]]$suffix
}

.reference_users_count <- function(ind, trips, mode) {
  spec <- .miama_tab2_mode_specs()[[mode]]

  if (!is.na(spec$ind_duration_col) && !is.null(ind) && spec$ind_duration_col %in% names(ind)) {
    return(list(
      value = sum(.positive_col(ind, spec$ind_duration_col), na.rm = TRUE),
      notes = character(0)
    ))
  }

  if (!is.null(trips) && all(c("census_id", "nts_tripid") %in% names(trips)) &&
      .trip_evidence_available(trips, spec)) {
    keep <- spec$trip_filter(trips) & !is.na(trips$nts_tripid)
    return(list(
      value = length(unique(trips$census_id[keep])),
      notes = paste0("users_count_ref_", spec$suffix, " was derived from trip rows.")
    ))
  }

  list(
    value = NA_real_,
    notes = paste0("users_count_ref_", spec$suffix, " could not be derived from available columns.")
  )
}

.reference_trips_count <- function(trips, mode, timeframe, denominator, population_size) {
  spec <- .miama_tab2_mode_specs()[[mode]]

  if (is.null(trips) || !"nts_tripid" %in% names(trips) ||
      !.trip_evidence_available(trips, spec)) {
    return(list(
      value = NA_real_,
      notes = paste0("trips_count_ref_", spec$suffix, " requires trip-level reference data.")
    ))
  }

  keep <- spec$trip_filter(trips) & !is.na(trips$nts_tripid)
  total <- .weighted_sum(rep(1, nrow(trips)), trips, keep)
  total <- total * .timeframe_factor(timeframe)

  if (identical(denominator, "mean")) {
    total <- .divide_or_na(total, population_size)
  }

  list(value = total, notes = character(0))
}

.reference_dist_dur_amount <- function(
    ind,
    trips,
    mode,
    dist_dur_type,
    distance_unit,
    duration_unit,
    denominator,
    timeframe,
    population_size
) {
  spec <- .miama_tab2_mode_specs()[[mode]]

  if (identical(dist_dur_type, "duration")) {
    result <- .reference_duration_amount(
      ind = ind,
      trips = trips,
      mode = mode,
      spec = spec,
      denominator = denominator,
      timeframe = timeframe,
      population_size = population_size
    )
    result$value <- .convert_duration_from_minutes(result$value, duration_unit)
    return(result)
  }

  result <- .reference_distance_amount(
    trips = trips,
    mode = mode,
    spec = spec,
    denominator = denominator,
    timeframe = timeframe,
    population_size = population_size
  )
  result$value <- .convert_distance_from_km(result$value, distance_unit)
  result
}

.reference_duration_amount <- function(ind, trips, mode, spec, denominator, timeframe, population_size) {
  if (identical(denominator, "average_per_trip")) {
    return(.reference_trip_component_amount(
      trips = trips,
      mode = mode,
      spec = spec,
      value_col = spec$trip_duration_col,
      denominator = denominator,
      timeframe = timeframe,
      population_size = population_size,
      field_prefix = "dist_dur_amount_ref"
    ))
  }

  if (!is.na(spec$ind_duration_col) && !is.null(ind) && spec$ind_duration_col %in% names(ind)) {
    duration_values <- .as_plain_numeric(ind[[spec$ind_duration_col]])
    total_minutes <- sum(duration_values, na.rm = TRUE) * 60 * .timeframe_factor(timeframe)
    if (identical(denominator, "average_per_person")) {
      total_minutes <- .divide_or_na(total_minutes, population_size)
    }

    return(list(value = total_minutes, notes = character(0)))
  }

  .reference_trip_component_amount(
    trips = trips,
    mode = mode,
    spec = spec,
    value_col = spec$trip_duration_col,
    denominator = denominator,
    timeframe = timeframe,
    population_size = population_size,
    field_prefix = "dist_dur_amount_ref"
  )
}

.reference_distance_amount <- function(trips, mode, spec, denominator, timeframe, population_size) {
  .reference_trip_component_amount(
    trips = trips,
    mode = mode,
    spec = spec,
    value_col = spec$trip_distance_col,
    denominator = denominator,
    timeframe = timeframe,
    population_size = population_size,
    field_prefix = "dist_dur_amount_ref"
  )
}

.reference_trip_component_amount <- function(
    trips,
    mode,
    spec,
    value_col,
    denominator,
    timeframe,
    population_size,
    field_prefix
) {
  field <- paste0(field_prefix, "_", spec$suffix)

  if (is.na(value_col) || is.null(trips) || !value_col %in% names(trips) ||
      !.trip_evidence_available(trips, spec)) {
    return(list(
      value = NA_real_,
      notes = paste0(field, " could not be derived from available columns.")
    ))
  }

  keep <- spec$trip_filter(trips)
  total <- .weighted_sum(trips[[value_col]], trips, keep) * .timeframe_factor(timeframe)

  if (identical(denominator, "average_per_person")) {
    total <- .divide_or_na(total, population_size)
  } else if (identical(denominator, "average_per_trip")) {
    trip_count <- .weighted_sum(rep(1, nrow(trips)), trips, keep)
    total <- .divide_or_na(total, trip_count * .timeframe_factor(timeframe))
  }

  list(value = total, notes = character(0))
}

.reference_mode_share_values <- function(trips, modes, total_unit, show_options) {
  ui_updates <- list()
  notes <- character(0)

  if (is.null(trips) || !"nts_tripid" %in% names(trips)) {
    for (mode in modes) {
      if (!mode %in% names(.miama_tab2_mode_specs())) {
        next
      }
      ui_updates[[paste0("mode_share_ref_", .miama_mode_suffix(mode))]] <- NA_real_
    }
    ui_updates$mode_share_ref_car <- NA_real_
    ui_updates$mode_share_ref <- .mode_share_pie_default(ui_updates)

    return(list(
      ui_updates = ui_updates,
      notes = "Mode share reference values require trip-level reference data."
    ))
  }

  denominator <- .mode_share_denominator(trips, total_unit)
  ui_updates$mode_share_total_trips <- denominator$total_trips
  ui_updates$mode_share_total_trips_basic <- denominator$total_trips
  ui_updates$mode_share_total_dist <- denominator$total_distance
  ui_updates$mode_share_total_dur <- denominator$total_duration

  denom_value <- denominator[[switch(
    total_unit,
    trips = "total_trips",
    distance = "total_distance",
    duration = "total_duration",
    "total_trips"
  )]]

  for (mode in modes) {
    spec <- .miama_tab2_mode_specs()[[mode]]
    if (is.null(spec)) {
      next
    }

    numerator <- .mode_share_numerator(trips, spec, total_unit)
    field <- paste0("mode_share_ref_", spec$suffix)
    ui_updates[[field]] <- 100 * .divide_or_na(numerator, denom_value)

    if (is.na(ui_updates[[field]])) {
      notes <- c(notes, paste0(field, " could not be derived from available columns."))
    }
  }

  car_value <- .mode_share_car_numerator(trips, total_unit)
  ui_updates$mode_share_ref_car <- 100 * .divide_or_na(car_value, denom_value)
  if (is.na(ui_updates$mode_share_ref_car)) {
    notes <- c(notes, "mode_share_ref_car could not be derived from available columns.")
  }

  ui_updates$mode_share_ref <- .mode_share_pie_default(ui_updates)

  if (!isTRUE(show_options) && !identical(total_unit, "trips")) {
    notes <- c(notes, "Mode share advanced options are off; trips denominator is used by the simple UI branch.")
  }

  list(ui_updates = ui_updates, notes = notes)
}

.mode_share_denominator <- function(trips, total_unit) {
  valid <- !is.na(trips$nts_tripid)
  list(
    total_trips = .weighted_sum(rep(1, nrow(trips)), trips, valid),
    total_distance = if ("trip_distraw_km" %in% names(trips)) {
      .weighted_sum(trips$trip_distraw_km, trips, valid)
    } else {
      NA_real_
    },
    total_duration = if ("trip_durationraw_min" %in% names(trips)) {
      .weighted_sum(trips$trip_durationraw_min, trips, valid)
    } else {
      NA_real_
    },
    total_unit = total_unit
  )
}

.mode_share_numerator <- function(trips, spec, total_unit) {
  if (!.trip_evidence_available(trips, spec)) {
    return(NA_real_)
  }

  keep <- spec$trip_filter(trips) & !is.na(trips$nts_tripid)

  if (identical(total_unit, "distance")) {
    if (is.na(spec$trip_distance_col) || !spec$trip_distance_col %in% names(trips)) {
      return(NA_real_)
    }
    return(.weighted_sum(trips[[spec$trip_distance_col]], trips, keep))
  }

  if (identical(total_unit, "duration")) {
    if (is.na(spec$trip_duration_col) || !spec$trip_duration_col %in% names(trips)) {
      return(NA_real_)
    }
    return(.weighted_sum(trips[[spec$trip_duration_col]], trips, keep))
  }

  .weighted_sum(rep(1, nrow(trips)), trips, keep)
}

.mode_share_car_numerator <- function(trips, total_unit) {
  if (is.null(trips) || !"trip_mainmode" %in% names(trips)) {
    return(NA_real_)
  }

  keep <- .car_trip_filter(trips) & !is.na(trips$nts_tripid)

  if (identical(total_unit, "distance")) {
    if (!"trip_distraw_km" %in% names(trips)) {
      return(NA_real_)
    }
    return(.weighted_sum(trips$trip_distraw_km, trips, keep))
  }

  if (identical(total_unit, "duration")) {
    if (!"trip_durationraw_min" %in% names(trips)) {
      return(NA_real_)
    }
    return(.weighted_sum(trips$trip_durationraw_min, trips, keep))
  }

  .weighted_sum(rep(1, nrow(trips)), trips, keep)
}

.mode_share_pie_default <- function(ui_updates) {
  mode_fields <- c(
    car = "mode_share_ref_car",
    bike = "mode_share_ref_bike",
    walk = "mode_share_ref_walk",
    pt = "mode_share_ref_pt"
  )

  stats::setNames(
    lapply(mode_fields, function(field) {
      value <- ui_updates[[field]]
      if (is.null(value) || length(value) == 0 || is.na(value[1])) {
        value <- 0
      }
      list(percent = as.numeric(value[1]))
    }),
    names(mode_fields)
  )
}

.reference_mode_share_total_unit <- function(values) {
  show_options <- isTRUE(.ui_value(values, "ui_mode_share_show_options", FALSE))
  if (isTRUE(show_options)) {
    return(.ui_value(values, "mode_share_total_unit", "trips"))
  }

  diversion_show_options <- isTRUE(.ui_value(values, "ui_trips_diversion_show_options", FALSE))
  if (isTRUE(diversion_show_options)) {
    basis <- .ui_value(values, "trips_diversion_basis", "total_trips")
    return(switch(
      basis,
      total_distance = "distance",
      total_duration = "duration",
      "trips"
    ))
  }

  "trips"
}

.reference_tab3_population_values <- function(ind, trips, context, cfg = NULL) {
  ui_updates <- list()
  notes <- character(0)

  if (is.null(ind)) {
    return(list(
      ui_updates = list(
        pop_spread_age_mean_ref = NA_real_,
        pop_spread_sex_prop_ref = NA_real_,
        pop_spread_pa_mean_ref = NA_real_,
        pop_spread_pa_sex_prop_ref = NA_real_
      ),
      notes = "Tab 3 population reference values require individual-level reference data."
    ))
  }

  active <- .selected_mode_individual_filter(ind, trips, context$modes)
  pop_group <- .population_distribution_filter(
    active = active,
    pop_refine_choice = .ui_value(context$values, "pop_refine_choice", "pop_age_current")
  )

  for (mode in context$modes) {
    if (!mode %in% names(.miama_tab2_mode_specs())) {
      next
    }
    suffix <- .miama_mode_suffix(mode)
    result <- .reference_users_count(ind, trips, mode)
    ui_updates[[paste0("pop_number_ref_", suffix)]] <- result$value
    notes <- c(notes, result$notes)
  }

  ui_updates$pop_spread_age_mean_ref <- .mean_or_na(ind$age1year, pop_group)
  ui_updates$pop_spread_sex_prop_ref <- .male_prop_or_na(ind, pop_group)

  pop_bars <- reference_population_spread_bars(ind, trips, context$modes, fallback_all = TRUE, cfg = cfg)
  pa_bars <- reference_pa_spread_bars(ind, trips, context$modes, fallback_all = TRUE, cfg = cfg)
  ui_updates$pop_spread_bars_ref <- pop_bars
  ui_updates$pa_spread_bars_ref <- pa_bars
  ui_updates$pop_spread_pa_bars_ref <- pa_bars
  ui_updates$pop_spread_pa_mean_ref <- spread_mean_from_bars(pa_bars)
  ui_updates$pop_spread_pa_sex_prop_ref <- spread_first_variable_prop_from_bars(pa_bars)

  for (mode in context$calculation_modes) {
    if (!mode %in% names(.miama_tab2_mode_specs())) {
      next
    }
    suffix <- .miama_mode_suffix(mode)
    mode_pop_bars <- reference_population_spread_bars(ind, trips, mode, fallback_all = FALSE, cfg = cfg)
    mode_pa_bars <- reference_pa_spread_bars(ind, trips, mode, fallback_all = FALSE, cfg = cfg)

    ui_updates[[paste0("pop_spread_bars_ref_", suffix)]] <- mode_pop_bars
    ui_updates[[paste0("pop_spread_age_mean_ref_", suffix)]] <- spread_mean_from_bars(mode_pop_bars)
    ui_updates[[paste0("pop_spread_sex_prop_ref_", suffix)]] <- spread_first_variable_prop_from_bars(mode_pop_bars)
    ui_updates[[paste0("pa_spread_bars_ref_", suffix)]] <- mode_pa_bars
    ui_updates[[paste0("pop_spread_pa_bars_ref_", suffix)]] <- mode_pa_bars
    ui_updates[[paste0("pop_spread_pa_mean_ref_", suffix)]] <- spread_mean_from_bars(mode_pa_bars)
    ui_updates[[paste0("pop_spread_pa_sex_prop_ref_", suffix)]] <- spread_first_variable_prop_from_bars(mode_pa_bars)
  }

  if (!"age1year" %in% names(ind)) {
    notes <- c(notes, "Population age distribution anchors require `age1year`.")
  }
  if (!"female" %in% names(ind)) {
    notes <- c(notes, "Population sex distribution anchors require `female`.")
  }
  if (is.null(.spread_pa_values(ind))) {
    notes <- c(notes, "PA spread anchors require `mmets`, `mmet_wkhr`, or reconstructable activity-hour columns.")
  }

  list(ui_updates = ui_updates, notes = notes)
}

.reference_tab4_trip_values <- function(trips, context, cfg = NULL) {
  ui_updates <- list()
  notes <- character(0)

  if (is.null(trips) || !"nts_tripid" %in% names(trips)) {
    ui_updates$trips_number_total_ref <- NA_real_
    ui_updates$trips_spread_mean_ref <- NA_real_
    ui_updates$trips_spread_util_prop_ref <- NA_real_
    ui_updates$trips_diversion_total_trips <- NA_real_
    ui_updates$trips_diversion_trips_n <- NA_real_
    ui_updates$trips_diversion_distance_total <- NA_real_
    ui_updates$trips_diversion_duration_total <- NA_real_

    for (mode in context$modes) {
      if (mode %in% names(.miama_tab2_mode_specs())) {
        ui_updates[[paste0("trips_number_ref_", .miama_mode_suffix(mode))]] <- NA_real_
      }
    }

    return(list(
      ui_updates = ui_updates,
      notes = "Tab 4 trip reference values require trip-level reference data."
    ))
  }

  denominator <- .mode_share_denominator(trips, "trips")
  ui_updates$trips_number_total_ref <- denominator$total_trips

  for (mode in context$modes) {
    if (!mode %in% names(.miama_tab2_mode_specs())) {
      next
    }

    suffix <- .miama_mode_suffix(mode)
    result <- .reference_trips_count(
      trips = trips,
      mode = mode,
      timeframe = "week",
      denominator = "total",
      population_size = NA_real_
    )
    ui_updates[[paste0("trips_number_ref_", suffix)]] <- result$value
    notes <- c(notes, result$notes)
  }

  valid <- !is.na(trips$nts_tripid)
  selected_active <- .selected_mode_trip_filter(trips, context$modes) & valid
  if (!any(selected_active, na.rm = TRUE)) {
    notes <- c(notes, "Trip spread anchors fell back to all trips because no selected active-mode trips were available.")
  }

  trips_bars <- reference_trip_spread_bars(trips, context$modes, fallback_all = TRUE, cfg = cfg)
  ui_updates$trips_spread_bars_ref <- trips_bars

  if ("trip_distraw_km" %in% names(trips)) {
    ui_updates$trips_spread_mean_ref <- spread_mean_from_bars(trips_bars)
  } else {
    ui_updates$trips_spread_mean_ref <- NA_real_
    notes <- c(notes, "`trips_spread_mean_ref` requires `trip_distraw_km`.")
  }

  if ("trip_purpose" %in% names(trips)) {
    ui_updates$trips_spread_util_prop_ref <- spread_first_variable_prop_from_bars(trips_bars)
  } else {
    ui_updates$trips_spread_util_prop_ref <- NA_real_
    notes <- c(notes, "`trips_spread_util_prop_ref` requires `trip_purpose`.")
  }

  for (mode in context$calculation_modes) {
    if (!mode %in% names(.miama_tab2_mode_specs())) {
      next
    }
    suffix <- .miama_mode_suffix(mode)
    mode_bars <- reference_trip_spread_bars(trips, mode, fallback_all = FALSE, cfg = cfg)
    ui_updates[[paste0("trips_spread_bars_ref_", suffix)]] <- mode_bars
    ui_updates[[paste0("trips_spread_mean_ref_", suffix)]] <- spread_mean_from_bars(mode_bars)
    ui_updates[[paste0("trips_spread_util_prop_ref_", suffix)]] <- spread_first_variable_prop_from_bars(mode_bars)
  }

  ui_updates$trips_diversion_total_trips <- denominator$total_trips
  ui_updates$trips_diversion_trips_n <- denominator$total_trips
  ui_updates$trips_diversion_distance_total <- denominator$total_distance
  ui_updates$trips_diversion_duration_total <- denominator$total_duration

  list(ui_updates = ui_updates, notes = notes)
}

.selected_mode_individual_filter <- function(ind, trips, modes) {
  active <- rep(FALSE, if (is.null(ind)) 0 else nrow(ind))
  if (length(active) == 0) {
    return(active)
  }

  for (mode in modes) {
    if (!mode %in% names(.miama_tab2_mode_specs())) {
      next
    }

    spec <- .miama_tab2_mode_specs()[[mode]]
    if (!is.na(spec$ind_duration_col) && spec$ind_duration_col %in% names(ind)) {
      active <- active | .positive_col(ind, spec$ind_duration_col)
    } else if (!is.null(trips) && all(c("census_id", "nts_tripid") %in% names(trips)) &&
               "census_id" %in% names(ind) && .trip_evidence_available(trips, spec)) {
      keep <- spec$trip_filter(trips) & !is.na(trips$nts_tripid)
      active_ids <- unique(trips$census_id[keep])
      active <- active | ind$census_id %in% active_ids
    }
  }

  active
}

.population_distribution_filter <- function(active, pop_refine_choice) {
  if (pop_refine_choice %in% c("pop_age_new", "pop_pa_new")) {
    group <- !active
  } else {
    group <- active
  }

  if (!any(group, na.rm = TRUE)) {
    return(rep(TRUE, length(active)))
  }

  group
}

.mean_or_na <- function(values, keep) {
  if (is.null(values) || length(values) == 0 || !any(keep, na.rm = TRUE)) {
    return(NA_real_)
  }

  values <- .as_plain_numeric(values)
  mean(values[keep], na.rm = TRUE)
}

.male_prop_or_na <- function(ind, keep) {
  if (is.null(ind) || !"female" %in% names(ind) || !any(keep, na.rm = TRUE)) {
    return(NA_real_)
  }

  female <- .as_plain_numeric(ind$female)
  mean(1 - female[keep], na.rm = TRUE)
}

.weighted_mean_or_na <- function(values, weights, keep) {
  if (length(values) == 0 || length(weights) == 0 || !any(keep, na.rm = TRUE)) {
    return(NA_real_)
  }

  values <- .as_plain_numeric(values)
  weights <- .as_plain_numeric(weights)
  weight_total <- sum(weights[keep], na.rm = TRUE)
  if (is.na(weight_total) || weight_total == 0) {
    return(NA_real_)
  }

  sum(values[keep] * weights[keep], na.rm = TRUE) / weight_total
}

.trip_weights <- function(trips) {
  weights <- rep(1, nrow(trips))
  if ("weight_tripXhh" %in% names(trips)) {
    weights <- .as_plain_numeric(trips$weight_tripXhh)
    weights[is.na(weights)] <- 0
  }

  weights
}

.utilitarian_trip_filter <- function(trip_purpose) {
  purpose <- tolower(as.character(trip_purpose))
  recreational <- grepl("leisure|holiday|sport|exercise|recreation|visit|social", purpose)
  known <- !is.na(purpose) & nzchar(purpose)

  known & !recreational
}

.ui_value <- function(values, field_name, default = NULL) {
  value <- values[[field_name]]
  if (is.null(value) || length(value) == 0) {
    return(default)
  }
  value
}

.positive_col <- function(data, col) {
  if (is.na(col) || is.null(data) || !col %in% names(data)) {
    return(rep(FALSE, if (is.null(data)) 0 else nrow(data)))
  }

  values <- .as_plain_numeric(data[[col]])
  !is.na(values) & values > 0
}

.trip_evidence_available <- function(trips, spec) {
  if (is.null(trips)) {
    return(FALSE)
  }

  if (isTRUE(spec$needs_trip_mainmode) && !"trip_mainmode" %in% names(trips)) {
    return(FALSE)
  }

  any(c(spec$trip_distance_col, spec$trip_duration_col) %in% names(trips))
}

.pt_trip_filter <- function(trips) {
  if (is.null(trips) || !"trip_mainmode" %in% names(trips)) {
    return(rep(FALSE, if (is.null(trips)) 0 else nrow(trips)))
  }

  grepl(
    "public|bus|rail|train|tram|metro|underground|tube|coach",
    tolower(as.character(trips$trip_mainmode))
  )
}

.car_trip_filter <- function(trips) {
  if (is.null(trips) || !"trip_mainmode" %in% names(trips)) {
    return(rep(FALSE, if (is.null(trips)) 0 else nrow(trips)))
  }

  grepl(
    "car|van|taxi|driver|passenger|motor",
    tolower(as.character(trips$trip_mainmode))
  )
}

.weighted_sum <- function(values, trips, keep) {
  if (length(values) == 0 || length(keep) == 0 || !any(keep, na.rm = TRUE)) {
    return(0)
  }

  values <- .as_plain_numeric(values)
  weights <- rep(1, length(values))
  if ("weight_tripXhh" %in% names(trips)) {
    weights <- .as_plain_numeric(trips$weight_tripXhh)
    weights[is.na(weights)] <- 0
  }

  sum(values[keep] * weights[keep], na.rm = TRUE)
}

.as_plain_numeric <- function(values) {
  if (is.null(values)) {
    return(NULL)
  }

  if (inherits(values, "haven_labelled") || inherits(values, "vctrs_vctr")) {
    values <- unclass(values)
  }

  as.numeric(values)
}

.timeframe_factor <- function(timeframe) {
  switch(
    timeframe,
    day = 1 / 7,
    week = 1,
    year = 52.1775,
    1
  )
}

.divide_or_na <- function(numerator, denominator) {
  if (length(denominator) == 0 || is.na(denominator) || denominator == 0) {
    return(NA_real_)
  }

  numerator / denominator
}

.convert_distance_from_km <- function(value, unit) {
  if (is.na(value)) {
    return(value)
  }
  if (identical(unit, "miles")) {
    return(value * 0.621371)
  }
  value
}

.convert_duration_from_minutes <- function(value, unit) {
  if (is.na(value)) {
    return(value)
  }
  if (identical(unit, "hours")) {
    return(value / 60)
  }
  value
}
