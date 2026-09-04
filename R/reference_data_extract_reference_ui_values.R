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
    cfg = NULL,
    spread_fallback_data = NULL
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

  reference_data <- .prepare_mode_features(reference_data)
  if (!is.null(spread_fallback_data)) {
    assert_named_list(spread_fallback_data, "spread_fallback_data")
  }
  ind <- reference_data$ind
  trips <- reference_data$trips

  population_size <- if (!is.null(ind)) nrow(ind) else NA_integer_
  context <- .reference_ui_context(appraisal_input_values)
  report <- list(
    modes = context$modes,
    calculation_modes = context$calculation_modes,
    base_timeframe = "week",
    notes = character(0),
    skipped_fields = character(0)
  )

  geo_name <- .reference_geo_name(reference_data, reference_request)
  ui_updates <- list(
    pop_total_ref_basic = population_size,
    pop_total_ref_advanced = population_size,
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
    ui_updates[[paste0("pop_number_ref_", suffix, "_basic")]] <- result$value
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
    show_options = isTRUE(.ui_value(context$values, "ui_mode_share_show_options", FALSE))
  )
  ui_updates <- utils::modifyList(ui_updates, result$ui_updates)
  report$notes <- c(report$notes, result$notes)

  tab3_result <- .reference_tab3_population_values(
    ind,
    trips,
    context,
    cfg = cfg,
    fallback_ind = spread_fallback_data$ind %||% NULL,
    fallback_trips = spread_fallback_data$trips %||% NULL
  )
  ui_updates <- utils::modifyList(ui_updates, tab3_result$ui_updates)
  report$notes <- c(report$notes, tab3_result$notes)

  tab4_result <- .reference_tab4_trip_values(
    trips,
    context,
    cfg = cfg,
    fallback_trips = spread_fallback_data$trips %||% NULL
  )
  ui_updates <- utils::modifyList(ui_updates, tab4_result$ui_updates)
  report$notes <- c(report$notes, tab4_result$notes)

  ui_updates <- .reference_add_spread_anchors(ui_updates)

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

.reference_add_spread_anchors <- function(ui_updates) {
  topics <- list(
    pop = c("pop_spread_bars_ref_", "pop_spread_age_mean_ref_", "pop_spread_sex_prop_ref_"),
    pa = c("pa_spread_bars_ref_", "pop_spread_pa_mean_ref_", "pop_spread_pa_sex_prop_ref_"),
    trips = c("trips_spread_bars_ref_", "trips_spread_mean_ref_", "trips_spread_util_prop_ref_")
  )

  for (suffix in vapply(names(.miama_tab2_mode_specs()), .miama_mode_suffix, character(1))) {
    for (fields in topics) {
      bars_field <- paste0(fields[[1]], suffix)
      bars <- ui_updates[[bars_field]]
      if (!is.data.frame(bars)) next

      bars$reference_mean <- ui_updates[[paste0(fields[[2]], suffix)]]
      bars$reference_prop <- ui_updates[[paste0(fields[[3]], suffix)]]
      ui_updates[[bars_field]] <- bars
    }
  }

  ui_updates
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
    mode_share_modes = names(.miama_tab2_mode_specs())
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
      trip_filter = function(trips) {
        (.positive_col(trips, "trip_walktime_min") |
           .positive_col(trips, "trip_walkdist_km")) & !.pt_trip_filter(trips)
      }
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
      ind_duration_col = "ebiketime_wkhr",
      trip_distance_col = "trip_ebikedist_km",
      trip_duration_col = "trip_ebiketime_min",
      needs_trip_mainmode = FALSE,
      proxy_mode = "cycling",
      trip_filter = function(trips) .positive_col(trips, "trip_ebiketime_min") |
        .positive_col(trips, "trip_ebikedist_km")
    ),
    pt = list(
      suffix = "pt",
      ind_duration_col = "pttime_wkhr",
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

  # Materialized REF/CF snapshots expose the authoritative mode-user scope.
  # Trip-derived users retain trip-based health exposure, avoiding a duplicate
  # change in the individual activity column solely for display purposes.
  materialized_scope_col <- paste0(".miama_user_scope_", spec$suffix)
  if (!is.null(ind) && materialized_scope_col %in% names(ind)) {
    return(list(
      value = sum(.true_values(ind[[materialized_scope_col]])),
      notes = character(0)
    ))
  }

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
  materialized_scope_col <- paste0(".miama_trip_scope_", spec$suffix)
  if (materialized_scope_col %in% names(trips)) {
    keep <- keep & .true_values(trips[[materialized_scope_col]])
  }
  total <- sum(keep, na.rm = TRUE)
  total <- convert_timeframe_value("week", total, timeframe, datatype = "trips")

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
    total_minutes <- convert_timeframe_value(
      "week",
      sum(duration_values, na.rm = TRUE) * 60,
      timeframe,
      datatype = "trips"
    )
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
  total <- convert_timeframe_value(
    "week",
    sum(.as_plain_numeric(trips[[value_col]])[keep], na.rm = TRUE),
    timeframe,
    datatype = "trips"
  )

  if (identical(denominator, "average_per_person")) {
    total <- .divide_or_na(total, population_size)
  } else if (identical(denominator, "average_per_trip")) {
    trip_count <- sum(keep, na.rm = TRUE)
    converted_trip_count <- convert_timeframe_value(
      "week", trip_count, timeframe, datatype = "trips"
    )
    total <- .divide_or_na(total, converted_trip_count)
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

    numerator <- .mode_share_numerator(trips, mode, spec, total_unit)
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
    total_trips = sum(valid, na.rm = TRUE),
    total_distance = if ("trip_distraw_km" %in% names(trips)) {
      sum(.as_plain_numeric(trips$trip_distraw_km)[valid], na.rm = TRUE)
    } else {
      NA_real_
    },
    total_duration = if ("trip_durationraw_min" %in% names(trips)) {
      sum(.as_plain_numeric(trips$trip_durationraw_min)[valid], na.rm = TRUE)
    } else {
      NA_real_
    },
    total_unit = total_unit
  )
}

.mode_share_numerator <- function(trips, mode, spec, total_unit) {
  # Aggregate mode share is a partition by main mode. Active-component columns
  # remain the fallback for compact/legacy inputs without `trip_mainmode`.
  if ("trip_mainmode" %in% names(trips)) {
    keep <- .mainmode_trip_filter(trips, mode) & !is.na(trips$nts_tripid)
    distance_col <- "trip_distraw_km"
    duration_col <- "trip_durationraw_min"
  } else {
    if (!.trip_evidence_available(trips, spec)) {
      return(NA_real_)
    }
    keep <- spec$trip_filter(trips) & !is.na(trips$nts_tripid)
    distance_col <- spec$trip_distance_col
    duration_col <- spec$trip_duration_col
  }

  if (identical(total_unit, "distance")) {
    if (is.na(distance_col) || !distance_col %in% names(trips)) {
      return(NA_real_)
    }
    return(sum(.as_plain_numeric(trips[[distance_col]])[keep], na.rm = TRUE))
  }

  if (identical(total_unit, "duration")) {
    if (is.na(duration_col) || !duration_col %in% names(trips)) {
      return(NA_real_)
    }
    return(sum(.as_plain_numeric(trips[[duration_col]])[keep], na.rm = TRUE))
  }

  sum(keep, na.rm = TRUE)
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
    return(sum(.as_plain_numeric(trips$trip_distraw_km)[keep], na.rm = TRUE))
  }

  if (identical(total_unit, "duration")) {
    if (!"trip_durationraw_min" %in% names(trips)) {
      return(NA_real_)
    }
    return(sum(.as_plain_numeric(trips$trip_durationraw_min)[keep], na.rm = TRUE))
  }

  sum(keep, na.rm = TRUE)
}

.mode_share_pie_default <- function(ui_updates) {
  mode_fields <- c(
    car = "mode_share_ref_car",
    bike = "mode_share_ref_bike",
    ebike = "mode_share_ref_ebike",
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

  "trips"
}

.reference_tab3_population_values <- function(ind,
                                              trips,
                                              context,
                                              cfg = NULL,
                                              fallback_ind = NULL,
                                              fallback_trips = NULL) {
  ui_updates <- list()
  notes <- character(0)

  if (is.null(ind)) {
    return(list(
      ui_updates = list(),
      notes = "Tab 3 population reference values require individual-level reference data."
    ))
  }

  for (mode in context$modes) {
    if (!mode %in% names(.miama_tab2_mode_specs())) {
      next
    }
    suffix <- .miama_mode_suffix(mode)
    result <- .reference_users_count(ind, trips, mode)
    ui_updates[[paste0("pop_number_ref_", suffix, "_advanced")]] <- result$value
    notes <- c(notes, result$notes)
  }

  for (mode in context$calculation_modes) {
    if (!mode %in% names(.miama_tab2_mode_specs())) {
      next
    }
    suffix <- .miama_mode_suffix(mode)
    mode_pop_bars <- reference_population_spread_bars(
      ind, trips, mode, fallback_all = FALSE, cfg = cfg
    )
    mode_pa_bars <- reference_pa_spread_bars(
      ind, trips, mode, fallback_all = FALSE, cfg = cfg
    )
    pop_fallback <- !.spread_bars_have_data(mode_pop_bars)
    pa_fallback <- !.spread_bars_have_data(mode_pa_bars)
    if (pop_fallback) {
      # An empty mode vector deliberately selects no mode rows, which makes
      # the spread helper fall back to all assessed people. E-bike retains its
      # explicit cycling proxy before that broader fallback is considered.
      proxy <- .miama_tab2_mode_specs()[[mode]]$proxy_mode %||% character(0)
      mode_pop_bars <- reference_population_spread_bars(
        ind, trips, proxy, fallback_all = TRUE, cfg = cfg
      )
    }
    if (pa_fallback) {
      proxy <- .miama_tab2_mode_specs()[[mode]]$proxy_mode %||% character(0)
      mode_pa_bars <- reference_pa_spread_bars(
        ind, trips, proxy, fallback_all = TRUE, cfg = cfg
      )
    }
    if (!.spread_bars_have_data(mode_pop_bars) && !is.null(fallback_ind)) {
      proxy <- .miama_tab2_mode_specs()[[mode]]$proxy_mode %||% character(0)
      mode_pop_bars <- reference_population_spread_bars(
        fallback_ind, fallback_trips, proxy, fallback_all = TRUE, cfg = cfg
      )
    }
    if (!.spread_bars_have_data(mode_pa_bars) && !is.null(fallback_ind)) {
      proxy <- .miama_tab2_mode_specs()[[mode]]$proxy_mode %||% character(0)
      mode_pa_bars <- reference_pa_spread_bars(
        fallback_ind, fallback_trips, proxy, fallback_all = TRUE, cfg = cfg
      )
    }
    if (pop_fallback || pa_fallback) {
      notes <- c(notes, paste0(
        "No usable mode-specific ", suffix,
        " spread was available; empty Tab 3 defaults use the assessed population ",
        "distribution, or the geographic baseline when the assessed REF scope is empty."
      ))
    }

    ui_updates[[paste0("pop_spread_bars_ref_", suffix)]] <- mode_pop_bars
    ui_updates[[paste0("pop_spread_age_mean_ref_", suffix)]] <- spread_mean_from_bars(mode_pop_bars)
    ui_updates[[paste0("pop_spread_sex_prop_ref_", suffix)]] <- spread_first_variable_prop_from_bars(mode_pop_bars)
    ui_updates[[paste0("pa_spread_bars_ref_", suffix)]] <- mode_pa_bars
    ui_updates[[paste0("pop_spread_pa_bars_ref_", suffix)]] <- mode_pa_bars
    ui_updates[[paste0("pop_spread_pa_mean_ref_", suffix)]] <- spread_mean_from_bars(mode_pa_bars)
    ui_updates[[paste0("pop_spread_pa_sex_prop_ref_", suffix)]] <- spread_first_variable_prop_from_bars(mode_pa_bars)
  }

  category_values <- .reference_tab3_category_values(ind, trips, cfg = cfg)
  ui_updates$pop_target_age_groups <- category_values$age
  ui_updates$pop_target_pa_groups <- category_values$pa
  notes <- c(notes, category_values$notes)

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

.reference_tab3_category_values <- function(ind, trips, cfg = NULL) {
  cfg <- cfg %||% miama_default_config()
  mode_suffixes <- c(
    walking = "walk",
    cycling = "bike",
    ebiking = "ebike",
    pt = "pt"
  )
  mode_filters <- lapply(names(mode_suffixes), function(mode) {
    spec <- .miama_tab2_mode_specs()[[mode]]
    available <- (!is.na(spec$ind_duration_col) && spec$ind_duration_col %in% names(ind)) ||
      (!is.null(trips) &&
         all(c("census_id", "nts_tripid") %in% names(trips)) &&
         "census_id" %in% names(ind) &&
         .trip_evidence_available(trips, spec))

    list(
      available = available,
      keep = if (available) {
        .selected_mode_individual_filter(ind, trips, mode)
      } else {
        rep(FALSE, nrow(ind))
      }
    )
  })
  names(mode_filters) <- names(mode_suffixes)

  category_counts <- function(categories, category_names) {
    stats::setNames(lapply(seq_along(category_names), function(i) {
      in_category <- !is.na(categories) & categories == i
      values <- list(pop_tot = sum(in_category))

      for (mode in names(mode_suffixes)) {
        filter <- mode_filters[[mode]]
        values[[paste0("pop_", mode_suffixes[[mode]])]] <-
          if (filter$available) sum(in_category & filter$keep) else NA_integer_
      }

      values
    }), category_names)
  }

  age_spec <- cfg$population_refinement$age %||%
    miama_default_config()$population_refinement$age
  age_values <- if ("age1year" %in% names(ind)) {
    age <- .as_plain_numeric(ind$age1year)
    age_categories <- .population_refinement_categories(age, age_spec)
    age_names <- paste0("pop_", age_spec$ids)
    category_counts(
      age_categories,
      age_names
    )
  } else {
    .empty_tab3_category_values(
      paste0("pop_", age_spec$ids)
    )
  }

  pa_spec <- cfg$population_refinement$pa %||%
    miama_default_config()$population_refinement$pa
  pa_names <- pa_spec$ids
  pa <- .spread_pa_values(ind)
  pa_values <- if (is.null(pa)) {
    .empty_tab3_category_values(pa_names)
  } else {
    category_counts(.population_refinement_categories(pa, pa_spec), pa_names)
  }

  unavailable_modes <- names(mode_filters)[!vapply(mode_filters, `[[`, logical(1), "available")]
  notes <- if (length(unavailable_modes) > 0) {
    paste0(
      "Tab 3 category-specific population values could not be derived for: ",
      paste(unavailable_modes, collapse = ", "),
      "."
    )
  } else {
    character(0)
  }

  list(age = age_values, pa = pa_values, notes = notes)
}

.population_refinement_categories <- function(values, spec) {
  ids <- as.character(spec$ids)
  other_id <- as.character(spec$other_id %||% character(0))
  classified_ids <- setdiff(ids, other_id)
  if (length(spec$breaks) != length(classified_ids) + 1L) {
    stop(
      "Population-refinement category breaks must define one more boundary ",
      "than classified category IDs.",
      call. = FALSE
    )
  }

  cut_categories <- as.integer(.spread_cut(
    .as_plain_numeric(values),
    spec$breaks,
    right = isTRUE(spec$right)
  ))
  categories <- match(classified_ids, ids)[cut_categories]
  if (length(other_id) == 1L) {
    categories[is.na(categories)] <- match(other_id, ids)
  }
  categories
}

.empty_tab3_category_values <- function(category_names) {
  value_names <- c("pop_tot", "pop_walk", "pop_bike", "pop_ebike", "pop_pt")
  stats::setNames(lapply(category_names, function(category) {
    stats::setNames(as.list(rep(NA_integer_, length(value_names))), value_names)
  }), category_names)
}

.reference_tab4_trip_values <- function(trips,
                                        context,
                                        cfg = NULL,
                                        fallback_trips = NULL) {
  ui_updates <- list()
  notes <- character(0)

  if (is.null(trips) || !"nts_tripid" %in% names(trips)) {
    ui_updates$trips_number_total_ref <- NA_real_
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

  for (mode in context$calculation_modes) {
    if (!mode %in% names(.miama_tab2_mode_specs())) {
      next
    }
    suffix <- .miama_mode_suffix(mode)
    mode_bars <- reference_trip_spread_bars(trips, mode, fallback_all = FALSE, cfg = cfg)
    trip_fallback <- !.spread_bars_have_data(mode_bars)
    if (trip_fallback) {
      proxy <- .miama_tab2_mode_specs()[[mode]]$proxy_mode %||% character(0)
      mode_bars <- reference_trip_spread_bars(
        trips, proxy, fallback_all = TRUE, cfg = cfg
      )
      if (!.spread_bars_have_data(mode_bars) && !is.null(fallback_trips)) {
        mode_bars <- reference_trip_spread_bars(
          fallback_trips, proxy, fallback_all = TRUE, cfg = cfg
        )
      }
      notes <- c(notes, paste0(
        "No usable mode-specific ", suffix,
        " trip spread was available; Tab 4 defaults use all assessed trips, ",
        "or geographic baseline trips when the assessed REF scope is empty."
      ))
    }
    ui_updates[[paste0("trips_spread_bars_ref_", suffix)]] <- mode_bars
    ui_updates[[paste0("trips_spread_mean_ref_", suffix)]] <- spread_mean_from_bars(mode_bars)
    ui_updates[[paste0("trips_spread_util_prop_ref_", suffix)]] <- spread_first_variable_prop_from_bars(mode_bars)

    ui_updates[[paste0("trips_diversion_sources_", suffix)]] <-
      .reference_diversion_source_pie(
        trips = trips,
        target_mode = mode,
        cfg = cfg,
        fallback_trips = fallback_trips
      )
  }

  list(ui_updates = ui_updates, notes = notes)
}

.reference_diversion_source_pie <- function(trips,
                                             target_mode,
                                             cfg = NULL,
                                             fallback_trips = NULL) {
  cfg <- cfg %||% miama_default_config()
  configured <- cfg$counterfactual$trips$source_mode_shares[[target_mode]] %||% NULL
  shares <- .normalize_diversion_source_shares(configured, target_mode)

  if (is.null(shares)) {
    shares <- .observed_diversion_source_shares(trips, target_mode)
  }
  if (is.null(shares) && !is.null(fallback_trips)) {
    shares <- .observed_diversion_source_shares(fallback_trips, target_mode)
  }

  internal_modes <- setdiff(
    c("driving", "cycling", "ebiking", "walking", "pt", "other"),
    target_mode
  )
  if (is.null(shares)) {
    shares <- stats::setNames(rep(1 / length(internal_modes), length(internal_modes)), internal_modes)
  }
  shares <- shares[intersect(internal_modes, names(shares))]
  shares <- shares / sum(shares)

  ui_names <- c(
    driving = "car", cycling = "bike", ebiking = "ebike",
    walking = "walk", pt = "pt", other = "other"
  )
  stats::setNames(
    lapply(as.numeric(shares), function(value) list(percent = 100 * value)),
    unname(ui_names[names(shares)])
  )
}

.observed_diversion_source_shares <- function(trips,
                                               target_mode,
                                               exclude_assessed_active = FALSE) {
  if (is.null(trips) || nrow(trips) == 0 || !"nts_tripid" %in% names(trips) ||
      !"trip_mainmode" %in% names(trips)) {
    return(NULL)
  }
  spec <- .miama_tab2_mode_specs()[[target_mode]]
  if (is.null(spec)) return(NULL)

  valid <- !is.na(trips$nts_tripid)
  target_active <- if (.trip_evidence_available(trips, spec)) {
    spec$trip_filter(trips)
  } else {
    rep(FALSE, nrow(trips))
  }
  utilitarian <- if ("trip_purpose" %in% names(trips)) {
    .utilitarian_trip_filter(trips$trip_purpose)
  } else {
    rep(TRUE, nrow(trips))
  }
  keep <- valid & !target_active & utilitarian
  if (isTRUE(exclude_assessed_active) && "trip_activemode" %in% names(trips)) {
    keep <- keep & !.true_values(trips$trip_activemode)
  }
  if ("ref_in_scope" %in% names(trips)) {
    keep <- keep & .true_values(trips$ref_in_scope)
  }
  if (!any(keep, na.rm = TRUE)) return(NULL)

  source_mode <- .results_trip_mode_group(trips$trip_mainmode[keep])
  counts <- table(source_mode)
  shares <- as.numeric(counts) / sum(counts)
  stats::setNames(shares, names(counts))
}

.normalize_diversion_source_shares <- function(shares, target_mode = NULL) {
  if (is.null(shares) || length(shares) == 0 || is.null(names(shares))) return(NULL)

  aliases <- c(
    car = "driving", driving = "driving", bike = "cycling", cycling = "cycling",
    ebike = "ebiking", ebiking = "ebiking", walk = "walking", walking = "walking",
    pt = "pt", other = "other"
  )
  normalized_names <- unname(aliases[tolower(names(shares))])
  values <- vapply(shares, function(value) {
    if (is.list(value)) value <- value$percent %||% NA_real_
    suppressWarnings(as.numeric(value)[1])
  }, numeric(1))
  keep <- !is.na(normalized_names) & is.finite(values) & values >= 0
  if (!any(keep)) return(NULL)

  values <- tapply(values[keep], normalized_names[keep], sum)
  values <- stats::setNames(as.numeric(values), names(values))
  if (!is.null(target_mode)) values <- values[names(values) != target_mode]
  if (length(values) == 0 || sum(values) <= 0) return(NULL)
  values / sum(values)
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
  rep(1, nrow(trips))
}

.utilitarian_trip_filter <- function(trip_purpose) {
  purpose <- tolower(as.character(trip_purpose))
  recreational <- grepl("leisure|holiday|sport|exercise|recreation|visit|social", purpose)
  known <- !is.na(purpose) & nzchar(purpose)
  utilitarian <- rep(TRUE, length(purpose))
  utilitarian[known] <- !recreational[known]
  utilitarian
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

  values <- trips$trip_mainmode
  numeric_values <- suppressWarnings(as.numeric(as.character(values)))
  numeric_match <- !is.na(numeric_values) & numeric_values %in% MIAMA_NTS_MAINMODE_PT_CODES
  text_match <- grepl(
    "^pt$|public|bus|rail|train|tram|metro|underground|tube|coach",
    tolower(as.character(values))
  )
  numeric_match | text_match
}

.mainmode_trip_filter <- function(trips, mode) {
  if (is.null(trips) || !"trip_mainmode" %in% names(trips)) {
    return(rep(FALSE, if (is.null(trips)) 0 else nrow(trips)))
  }

  values <- trips$trip_mainmode
  numeric_values <- suppressWarnings(as.numeric(as.character(values)))
  text_values <- tolower(as.character(values))

  switch(
    mode,
    walking = (!is.na(numeric_values) & numeric_values == MIAMA_NTS_MAINMODE_B04[["walk"]]) |
      grepl("walk", text_values),
    cycling = (!is.na(numeric_values) & numeric_values == MIAMA_NTS_MAINMODE_B04[["bicycle"]]) |
      grepl("bicy|cycl", text_values),
    ebiking = grepl("e[- ]?bike|electric bicy|electric cycl", text_values),
    pt = .pt_trip_filter(trips),
    car = .car_trip_filter(trips),
    rep(FALSE, nrow(trips))
  )
}

.car_trip_filter <- function(trips) {
  if (is.null(trips) || !"trip_mainmode" %in% names(trips)) {
    return(rep(FALSE, if (is.null(trips)) 0 else nrow(trips)))
  }

  values <- trips$trip_mainmode
  numeric_values <- suppressWarnings(as.numeric(as.character(values)))
  numeric_match <- !is.na(numeric_values) & numeric_values %in% MIAMA_NTS_MAINMODE_CAR_CODES
  text_match <- grepl(
    "car|van|taxi|driver|passenger|motor",
    tolower(as.character(values))
  )
  numeric_match | text_match
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
