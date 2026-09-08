# MIAMA-HUB Module: Tab 2 Input Conversion
# Purpose: Convert alternative Tab 2 active-travel volume representations into
# canonical weekly, per-mode trip-row targets used by the existing constrained
# reference and counterfactual samplers.

.derive_tab2_trip_count_targets <- function(values,
                                            reference_data,
                                            scenario = c("ref", "cf"),
                                            modes = NULL) {
  scenario <- match.arg(scenario)
  data_unit <- .ui_value(values, "at_data_unit", NULL)
  if (is.null(data_unit) || length(data_unit) != 1 ||
      !data_unit %in% c("distance", "mode_share")) {
    return(list(values = values, report = list(data_unit = data_unit, conversions = list())))
  }

  if (is.null(reference_data$trips)) {
    stop("Tab 2 `", data_unit, "` inputs require trip-level reference data.", call. = FALSE)
  }
  if (is.null(modes)) {
    modes <- normalize_active_modes(.ui_value(values, "modes", character(0)))
  }
  modes <- intersect(modes, .miama_supported_modes())

  conversions <- list()
  for (mode in modes) {
    spec <- .counterfactual_mode_spec(mode)
    result <- if (identical(data_unit, "distance")) {
      .tab2_dist_dur_trip_target(values, reference_data, scenario, spec)
    } else {
      .tab2_mode_share_trip_target(values, reference_data, scenario, spec)
    }
    if (is.null(result)) next

    field <- paste0("trips_count_", scenario, "_", spec$suffix)
    values[[field]] <- result$trip_rows
    values[[paste0("trips_timeframe_", spec$suffix)]] <- "week"
    values[[paste0("trips_denominator_", spec$suffix)]] <- "total"
    conversions[[mode]] <- c(list(target_field = field), result)
  }

  list(
    values = values,
    report = list(
      data_unit = data_unit,
      scenario = scenario,
      conversions = conversions
    )
  )
}

.tab2_dist_dur_trip_target <- function(values, reference_data, scenario, spec) {
  field <- paste0("dist_dur_amount_", scenario, "_", spec$suffix)
  raw <- .ui_value(values, field, NULL)
  if (.is_blank_cf_target(raw)) return(NULL)
  amount <- .tab2_nonnegative_number(raw, field)

  kind <- .ui_value(values, paste0("ui_dist_dur_type_", spec$suffix), "distance")
  if (!kind %in% c("distance", "duration")) {
    stop("Unsupported distance/duration type for `", field, "`: ", kind, ".", call. = FALSE)
  }
  denominator <- .ui_value(
    values, paste0("dist_dur_denominator_", spec$suffix), "total"
  )
  if (identical(denominator, "average_per_trip")) {
    stop(
      "`", field, "` is an average per trip and does not define total active-travel volume. ",
      "Provide a total or average per person, or use Tab 4 to refine trip distance.",
      call. = FALSE
    )
  }
  if (!denominator %in% c("total", "average_per_person")) {
    stop("Unsupported denominator for `", field, "`: ", denominator, ".", call. = FALSE)
  }

  canonical_amount <- .tab2_canonical_dist_dur_amount(amount, kind, values, spec$suffix)
  timeframe <- .ui_value(values, paste0("dist_dur_timeframe_", spec$suffix), "week")
  weekly_amount <- convert_timeframe_value(
    timeframe, canonical_amount, "week", datatype = "trips"
  )
  population_n <- .tab2_scope_population_n(reference_data, scenario)
  weekly_total <- if (identical(denominator, "average_per_person")) {
    weekly_amount * population_n
  } else {
    weekly_amount
  }
  mean_per_trip <- .assumption_trip_mean(values, reference_data, spec, kind)
  trip_rows <- .tab2_amount_to_trip_rows(weekly_total, mean_per_trip, field)

  list(
    source_field = field,
    source_kind = kind,
    source_denominator = denominator,
    source_timeframe = timeframe,
    canonical_unit = if (identical(kind, "distance")) "km/week" else "minutes/week",
    weekly_total = weekly_total,
    reference_mean_per_trip = mean_per_trip,
    population_denominator = if (identical(denominator, "average_per_person")) population_n else NULL,
    trip_rows = trip_rows
  )
}

.tab2_mode_share_trip_target <- function(values, reference_data, scenario, spec) {
  shares_field <- paste0("mode_share_", scenario)
  shares <- .ui_value(values, shares_field, NULL)
  share <- .tab2_mode_share_percent(shares, spec$suffix, shares_field)
  if (is.null(share)) return(NULL)

  total_unit <- .reference_mode_share_total_unit(values)
  total_field <- switch(
    total_unit,
    trips = if (isTRUE(.ui_value(values, "ui_mode_share_show_options", FALSE))) {
      "mode_share_total_trips"
    } else {
      "mode_share_total_trips_basic"
    },
    distance = "mode_share_total_dist",
    duration = "mode_share_total_dur"
  )
  total <- .ui_value(values, total_field, NULL)
  if (.is_blank_cf_target(total) && identical(total_unit, "trips")) {
    fallback <- if (identical(total_field, "mode_share_total_trips")) {
      "mode_share_total_trips_basic"
    } else {
      "mode_share_total_trips"
    }
    total <- .ui_value(values, fallback, NULL)
    if (!.is_blank_cf_target(total)) total_field <- fallback
  }
  if (.is_blank_cf_target(total)) {
    stop("Mode-share input requires `", total_field, "`.", call. = FALSE)
  }
  total <- .tab2_nonnegative_number(total, total_field)
  target_amount <- total * share / 100
  mean_per_trip <- NULL
  trip_rows <- if (identical(total_unit, "trips")) {
    as.integer(round(target_amount))
  } else {
    kind <- if (identical(total_unit, "distance")) "distance" else "duration"
    mean_per_trip <- .assumption_trip_mean(values, reference_data, spec, kind)
    .tab2_amount_to_trip_rows(target_amount, mean_per_trip, shares_field)
  }

  list(
    source_field = shares_field,
    denominator_field = total_field,
    source_kind = paste0("mode_share_", total_unit),
    share_percent = share,
    denominator_total = total,
    canonical_unit = switch(total_unit, trips = "trips/week", distance = "km/week", duration = "minutes/week"),
    reference_mean_per_trip = mean_per_trip,
    trip_rows = trip_rows
  )
}

.tab2_canonical_dist_dur_amount <- function(amount, kind, values, suffix) {
  if (identical(kind, "distance")) {
    unit <- .ui_value(values, paste0("distance_unit_", suffix), "km")
    if (!unit %in% c("km", "miles")) stop("Unsupported distance unit: ", unit, ".", call. = FALSE)
    return(amount * if (identical(unit, "miles")) 1.609344 else 1)
  }

  unit <- .ui_value(values, paste0("duration_unit_", suffix), "mins")
  if (!unit %in% c("mins", "minutes", "hours")) stop("Unsupported duration unit: ", unit, ".", call. = FALSE)
  amount * if (identical(unit, "hours")) 60 else 1
}

.tab2_reference_mode_mean <- function(trips, spec, kind) {
  donor_spec <- .mode_proxy_spec(spec)
  active <- donor_spec$trip_filter(trips) & !is.na(trips$nts_tripid)
  column <- if (identical(kind, "distance")) donor_spec$trip_distance_col else donor_spec$trip_duration_col
  if (is.na(column) || !column %in% names(trips)) {
    stop("Reference trips do not contain the required ", kind, " column for `", spec$mode, "`.", call. = FALSE)
  }
  values <- .as_plain_numeric(trips[[column]])[active]
  values <- values[is.finite(values) & values > 0]
  result <- mean(values)
  if (!is.finite(result) || result <= 0) {
    stop("No positive reference ", kind, " values are available for `", spec$mode, "` trips.", call. = FALSE)
  }
  factor <- if (identical(spec$mode %||% "", "ebiking")) {
    if (identical(kind, "distance")) spec$proxy_distance_factor %||% 1 else spec$proxy_duration_factor %||% 1
  } else {
    1
  }
  result * factor
}

.tab2_amount_to_trip_rows <- function(total, mean_per_trip, field) {
  raw_rows <- round(total / mean_per_trip)
  if (!is.finite(raw_rows) || raw_rows < 0 || raw_rows > .Machine$integer.max) {
    stop("Could not derive a trip-row target from `", field, "`.", call. = FALSE)
  }
  as.integer(raw_rows)
}

.tab2_mode_share_percent <- function(shares, suffix, field) {
  if (is.null(shares) || !is.list(shares)) return(NULL)
  entry <- shares[[suffix]]
  if (is.null(entry)) return(NULL)
  raw <- if (is.list(entry)) entry$percent else entry
  value <- .tab2_nonnegative_number(raw, paste0(field, "$", suffix, "$percent"))
  if (value > 100) stop("Mode-share percentages must be between 0 and 100.", call. = FALSE)
  value
}

.tab2_scope_population_n <- function(reference_data, scenario) {
  if (is.null(reference_data$ind)) return(NA_integer_)
  scope <- paste0(scenario, "_in_scope")
  if (scope %in% names(reference_data$ind)) {
    return(sum(.true_values(reference_data$ind[[scope]])))
  }
  nrow(reference_data$ind)
}

.tab2_nonnegative_number <- function(value, field) {
  value <- suppressWarnings(as.numeric(value))
  if (length(value) != 1 || !is.finite(value) || value < 0) {
    stop("`", field, "` must be one finite non-negative number.", call. = FALSE)
  }
  value
}
