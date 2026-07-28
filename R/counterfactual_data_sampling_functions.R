# MIAMA-HUB Module: Counterfactual Data / Sampling Functions
# Purpose: Support Step 6 by selecting existing reference/counterfactual rows
#   that plausibly change status. These helpers do not create synthetic people.
#
# Counterfactual principle:
# - `counterfactual_data` starts as a 1:1 copy of `reference_data`.
# - Individual-level changes keep the population fixed. Existing rows switch
#   between current user, new user, ex-user, or unchanged status.
# - Utilitarian trip demand is treated as fixed. Active-travel trip increases
#   are mostly existing non-active trips shifting mode, plus a small default
#   share of induced recreational trips that add new trip rows.
# - Sampling is "as-is" row selection. We may weight candidate selection by
#   age/sex or distance distributions, but selected rows remain real rows.
#
# Individual sampling:
# Candidate people are current users or non-users for a mode. Selection can be
# weighted by UI/ref proportions for sex and five age categories. Until the UI
# category breaks are final, HUB accepts `agecat_1_prop_cf` ...
# `agecat_5_prop_cf` or percentage equivalents.
#
# Trip sampling:
# Candidate shifted trips are non-active utilitarian trips. Selection is
# constrained by five distance categories from current active-mode trips so a
# shifted trip is plausible for the target active mode. HUB accepts future
# `distcat_1_prop_cf` ... `distcat_5_prop_cf` fields.
#
# Remaining clarification needs:
# - Final age and distance category break definitions. Current implementation
#   derives five categories from local reference-data quintiles.
# - More detailed mode-specific diversion fields in MIAMA-UI. HUB already parses
#   simple `% car` and future per-mode percentage hooks.
# - Weighted trip data. Current behavior keeps existing trip weights for shifted
#   rows and assigns `weight_tripXhh = 1` to induced trip rows.

miama_counterfactual_sampling_strategies <- function() {
  "random_sample_as_is_rows"
}

cf_sampling_strategy_from_ui <- function(values, default = "random_sample_as_is_rows", scope = NULL) {
  scoped_field <- if (!is.null(scope)) paste0(scope, "_sampling_strategy") else NA_character_
  strategy <- if (!is.na(scoped_field)) values[[scoped_field]] else NULL

  if (is.null(strategy) || length(strategy) == 0) {
    strategy <- values[["sampling_strategy"]]
  }
  if (is.null(strategy) || length(strategy) == 0) {
    strategy <- default
  }

  cf_validate_sampling_strategy(strategy)
}

cf_validate_sampling_strategy <- function(strategy) {
  if (!is.character(strategy) || length(strategy) != 1 || is.na(strategy)) {
    stop("`sampling_strategy` must be one character value.", call. = FALSE)
  }
  if (!strategy %in% miama_counterfactual_sampling_strategies()) {
    stop(
      "Unsupported `sampling_strategy`: ", strategy,
      ". Supported value: random_sample_as_is_rows.",
      call. = FALSE
    )
  }

  strategy
}

cf_row_delta_plan <- function(cf_row_number, ref_row_number) {
  if (!is.numeric(cf_row_number) || length(cf_row_number) != 1 || !is.finite(cf_row_number)) {
    stop("`cf_row_number` must be one finite number.", call. = FALSE)
  }
  if (!is.numeric(ref_row_number) || length(ref_row_number) != 1 || !is.finite(ref_row_number)) {
    stop("`ref_row_number` must be one finite number.", call. = FALSE)
  }

  cf_row_number <- as.integer(round(cf_row_number))
  ref_row_number <- as.integer(round(ref_row_number))
  if (cf_row_number < 0 || ref_row_number < 0) {
    stop("Row counts cannot be negative.", call. = FALSE)
  }

  delta <- cf_row_number - ref_row_number
  action <- if (delta > 0) {
    "increase_status_count"
  } else if (delta < 0) {
    "decrease_status_count"
  } else {
    "unchanged"
  }

  list(
    cf_row_number = cf_row_number,
    ref_row_number = ref_row_number,
    delta = delta,
    action = action,
    n = abs(delta)
  )
}

# Key indicators -------------------------------------------------------------
# Indicators make the core appraisal currencies visible in the data object.

cf_add_key_indicators <- function(counterfactual_data, modes = c("walking", "cycling")) {
  if (!is.null(counterfactual_data$ind)) {
    counterfactual_data$ind <- cf_add_ind_user_indicators(counterfactual_data$ind)
    if (!"cf_user_change" %in% names(counterfactual_data$ind)) {
      counterfactual_data$ind$cf_user_change <- "unchanged"
    }
  }

  if (!is.null(counterfactual_data$trips)) {
    counterfactual_data$trips <- cf_add_trip_indicators(counterfactual_data$trips, modes)
    if (!"cf_trip_change" %in% names(counterfactual_data$trips)) {
      counterfactual_data$trips$cf_trip_change <- "unchanged"
    }
    if (!"cf_mode_shift" %in% names(counterfactual_data$trips)) {
      counterfactual_data$trips$cf_mode_shift <- FALSE
    }
    if (!"cf_induced" %in% names(counterfactual_data$trips)) {
      counterfactual_data$trips$cf_induced <- FALSE
    }
  }

  counterfactual_data
}

cf_add_ind_user_indicators <- function(ind) {
  if ("walktime_wkhr" %in% names(ind)) {
    ind$user_walk <- !is.na(ind$walktime_wkhr) & ind$walktime_wkhr > 0
  }
  if ("cycletime_wkhr" %in% names(ind)) {
    ind$user_bike <- !is.na(ind$cycletime_wkhr) & ind$cycletime_wkhr > 0
  }

  ind
}

cf_add_trip_indicators <- function(trips, modes = c("walking", "cycling")) {
  active <- rep(FALSE, nrow(trips))
  for (mode in modes) {
    spec <- .counterfactual_mode_spec(mode)
    if (!is.null(spec) && .trip_evidence_available_for_counterfactual(trips, spec)) {
      active <- active | spec$trip_filter(trips)
    }
  }

  trips$trip_activemode <- active
  trips$trip_utilitarian <- cf_trip_utilitarian(trips, active)
  trips
}

cf_trip_utilitarian <- function(trips, active = rep(FALSE, nrow(trips))) {
  util <- rep(TRUE, nrow(trips))
  if ("trip_purpose" %in% names(trips)) {
    purpose <- tolower(as.character(trips$trip_purpose))
    recreational <- grepl("leisure|holiday|sport|exercise|recreation|visit|social", purpose)
    known <- !is.na(purpose) & nzchar(purpose)
    util[known] <- !recreational[known]
  }

  util[!active] <- TRUE
  util
}

# Candidate selection --------------------------------------------------------
# Weighted row sampling keeps rows real while nudging samples toward requested
# age/sex or distance distributions.

cf_sample_candidate_indices <- function(candidate_rows, n, seed, weights = NULL, replace = FALSE) {
  n <- as.integer(n)
  if (n == 0) {
    return(integer(0))
  }
  if (length(candidate_rows) == 0) {
    stop("No candidate rows available for requested counterfactual change.", call. = FALSE)
  }
  if (!isTRUE(replace) && length(candidate_rows) < n) {
    stop("Not enough candidate rows available for requested counterfactual change.", call. = FALSE)
  }

  if (!is.null(weights)) {
    weights <- weights[seq_along(candidate_rows)]
    weights[is.na(weights) | weights < 0] <- 0
    if (sum(weights) == 0) {
      weights <- NULL
    }
  }

  set.seed(seed)
  sampled_pos <- sample(seq_along(candidate_rows), size = n, replace = replace, prob = weights)
  candidate_rows[sampled_pos]
}

cf_individual_candidate_weights <- function(ind, candidate_rows, target = list()) {
  weights <- rep(1, length(candidate_rows))
  if (length(candidate_rows) == 0) {
    return(weights)
  }

  if ("female" %in% names(ind) && !is.null(target$male_prop)) {
    female <- ind$female[candidate_rows]
    male <- !is.na(female) & female == 0
    weights <- weights * ifelse(male, target$male_prop, 1 - target$male_prop)
  }

  if ("age1year" %in% names(ind) && !is.null(target$age_quintile_props)) {
    quintile <- cf_numeric_quintile(ind$age1year)
    weights <- weights * cf_quintile_weights(quintile[candidate_rows], target$age_quintile_props)
  }

  weights
}

cf_trip_candidate_weights <- function(trips, candidate_rows, active_distances, target = list()) {
  weights <- rep(1, length(candidate_rows))
  if (length(candidate_rows) == 0 || !"trip_distraw_km" %in% names(trips)) {
    return(weights)
  }
  if (length(active_distances) == 0 || all(is.na(active_distances))) {
    return(weights)
  }

  quintile <- cf_distance_quintile(trips$trip_distraw_km, active_distances)
  props <- target$distance_quintile_props
  if (is.null(props)) {
    props <- .cf_reference_quintile_props(cf_distance_quintile(active_distances, active_distances))
  }

  weights * cf_quintile_weights(quintile[candidate_rows], props)
}

cf_numeric_quintile <- function(values, breaks = NULL) {
  values <- as.numeric(values)
  if (is.null(breaks)) {
    observed <- values[!is.na(values)]
    if (length(observed) == 0) {
      return(rep(NA_integer_, length(values)))
    }
    breaks <- unique(stats::quantile(observed, probs = seq(0, 1, 0.2), na.rm = TRUE, names = FALSE))
  }
  if (length(breaks) < 2) {
    return(rep(1L, length(values)))
  }

  as.integer(cut(values, breaks = breaks, include.lowest = TRUE, labels = FALSE))
}

cf_distance_quintile <- function(distances, active_distances) {
  active_distances <- as.numeric(active_distances)
  if (length(active_distances) == 0 || all(is.na(active_distances))) {
    return(rep(NA_integer_, length(distances)))
  }
  breaks <- unique(stats::quantile(
    active_distances[!is.na(active_distances)],
    probs = seq(0, 1, 0.2),
    na.rm = TRUE,
    names = FALSE
  ))
  cf_numeric_quintile(distances, breaks = breaks)
}

cf_quintile_weights <- function(quintile, props) {
  if (is.null(props) || length(props) == 0) {
    return(rep(1, length(quintile)))
  }
  props <- as.numeric(props)
  props <- props / sum(props, na.rm = TRUE)
  out <- rep(0, length(quintile))
  known <- !is.na(quintile) & quintile >= 1 & quintile <= length(props)
  out[known] <- props[quintile[known]]
  out[!known] <- mean(props, na.rm = TRUE)
  out
}

cf_plausible_distance_candidates <- function(trips, candidate_rows, active_distances, max_multiplier = 1.2) {
  if (!"trip_distraw_km" %in% names(trips) || length(candidate_rows) == 0) {
    return(candidate_rows)
  }

  active_distances <- as.numeric(active_distances)
  max_distance <- suppressWarnings(max(active_distances, na.rm = TRUE))
  if (!is.finite(max_distance) || max_distance <= 0) {
    return(candidate_rows)
  }

  candidate_rows[trips$trip_distraw_km[candidate_rows] <= max_distance * max_multiplier]
}

.cf_reference_quintile_props <- function(quintile) {
  tab <- table(factor(quintile, levels = 1:5))
  if (sum(tab) == 0) {
    return(rep(0.2, 5))
  }

  as.numeric(tab) / sum(tab)
}

# UI target hooks ------------------------------------------------------------
# Existing UI fields provide sex and mean-distance/purpose summaries. Quintile
# hooks are intentionally permissive for upcoming Tab 3/4 controls.

cf_population_sampling_target <- function(values, suffix = NULL) {
  pop_bars_cf <- .cf_mode_value(values, "pop_spread_bars_cf", suffix)
  male_prop <- if (is.data.frame(pop_bars_cf)) {
    spread_first_variable_prop_from_bars(pop_bars_cf)
  } else {
    .cf_mode_value(values, "pop_spread_sex_prop_cf", suffix)
  }
  if (is.null(male_prop)) {
    male_prop <- .cf_mode_value(values, "pop_spread_pa_sex_prop_cf", suffix)
  }

  age_props <- if (is.data.frame(pop_bars_cf)) {
    spread_category_props_from_bars(pop_bars_cf)
  } else {
    cf_ui_category_props(values, "agecat")
  }

  list(
    male_prop = .cf_clamp_prop(male_prop),
    age_quintile_props = age_props
  )
}

cf_trip_sampling_target <- function(values, suffix = NULL) {
  trip_bars_cf <- .cf_mode_value(values, "trips_spread_bars_cf", suffix)

  list(
    distance_quintile_props = if (is.data.frame(trip_bars_cf)) {
      spread_category_props_from_bars(trip_bars_cf)
    } else {
      cf_ui_category_props(values, "distcat")
    },
    target_mean_distance = .cf_mode_value(values, "trips_spread_mean_cf", suffix),
    target_utilitarian_prop = if (is.data.frame(trip_bars_cf)) {
      spread_first_variable_prop_from_bars(trip_bars_cf)
    } else {
      .cf_mode_value(values, "trips_spread_util_prop_cf", suffix)
    }
  )
}

.cf_mode_value <- function(values, field_stem, suffix = NULL) {
  if (!is.null(suffix) && length(suffix) > 0 && !is.na(suffix[1])) {
    mode_field <- paste0(field_stem, "_", suffix[1])
    value <- values[[mode_field]]
    if (!is.null(value)) {
      return(value)
    }
  }

  values[[field_stem]]
}

cf_ui_category_props <- function(values, prefix) {
  prop_fields <- paste0(prefix, "_", 1:5, "_prop_cf")
  perc_fields <- paste0(prefix, "_", 1:5, "_perc_cf")

  raw <- unlist(values[prop_fields], use.names = FALSE)
  if (length(raw) != 5 || any(vapply(raw, is.null, logical(1)))) {
    raw <- unlist(values[perc_fields], use.names = FALSE)
    if (length(raw) == 5) {
      raw <- as.numeric(raw) / 100
    }
  }

  if (length(raw) != 5 || any(is.na(as.numeric(raw)))) {
    return(NULL)
  }

  props <- as.numeric(raw)
  if (sum(props) <= 0) {
    return(NULL)
  }

  props / sum(props)
}

cf_ui_quintile_props <- function(values, prefix) {
  prop_fields <- paste0(prefix, "_q", 1:5, "_prop_cf")
  perc_fields <- paste0(prefix, "_q", 1:5, "_perc_cf")

  raw <- unlist(values[prop_fields], use.names = FALSE)
  if (length(raw) != 5 || any(vapply(raw, is.null, logical(1)))) {
    raw <- unlist(values[perc_fields], use.names = FALSE)
    if (length(raw) == 5) {
      raw <- as.numeric(raw) / 100
    }
  }

  if (length(raw) != 5 || any(is.na(as.numeric(raw)))) {
    return(NULL)
  }

  props <- as.numeric(raw)
  if (sum(props) <= 0) {
    return(NULL)
  }

  props / sum(props)
}

.cf_clamp_prop <- function(value) {
  if (is.null(value) || length(value) != 1 || is.na(value)) {
    return(NULL)
  }
  value <- as.numeric(value)
  if (value > 1) {
    value <- value / 100
  }
  max(0, min(1, value))
}

# Attribute values -----------------------------------------------------------
# User status changes alter dependent activity values. New users receive
# observed current-user activity values; ex-users receive configured near-zero
# defaults.

cf_sample_observed_values <- function(values_ref, n, default_value, seed) {
  n <- as.integer(n)
  if (n == 0) {
    return(values_ref[0])
  }

  observed <- values_ref[!is.na(values_ref)]
  if (length(observed) == 0) {
    return(rep(default_value, n))
  }

  set.seed(seed)
  sample(observed, size = n, replace = TRUE)
}

cf_trip_mechanism_counts <- function(delta, induced_percent = 10) {
  if (delta <= 0) {
    return(list(mode_shift_n = 0L, induced_n = 0L))
  }

  induced_n <- as.integer(round(delta * induced_percent / 100))
  induced_n <- min(delta, max(0L, induced_n))
  list(
    mode_shift_n = as.integer(delta - induced_n),
    induced_n = induced_n
  )
}

cf_individual_sampling_columns <- function(ind, modes = c("walking", "cycling")) {
  if (is.null(ind)) {
    return(character(0))
  }

  mode_cols <- unlist(lapply(modes, function(mode) {
    switch(
      mode,
      walking = c("user_walk", "walktime_wkhr", "walkdist_wkkm"),
      cycling = c("user_bike", "cycletime_wkhr", "cycledist_wkkm"),
      ebiking = c("user_ebike", "ebiketime_wkhr", "ebikedist_wkkm"),
      pt = c("user_pt", "pttime_wkhr", "ptdist_wkkm"),
      character(0)
    )
  }), use.names = FALSE)

  cols <- c(
    "female", "sex", "age1year", "agegroup",
    mode_cols,
    "sport_wkhr", "mmets", "mmet_wkhr", "pa_wkhr",
    "cf_user_change"
  )

  unique(cols[cols %in% names(ind)])
}

cf_trip_sampling_columns <- function(trips, modes = c("walking", "cycling")) {
  if (is.null(trips)) {
    return(character(0))
  }

  mode_cols <- unlist(lapply(modes, function(mode) {
    switch(
      mode,
      walking = c("trip_walkdist_km", "trip_walktime_min"),
      cycling = c("trip_cycledist_km", "trip_cycletime_min"),
      ebiking = c("trip_ebikedist_km", "trip_ebiketime_min"),
      pt = c("trip_walkdist_km", "trip_walktime_min"),
      character(0)
    )
  }), use.names = FALSE)

  cols <- c(
    "trip_mainmode", "mode",
    "trip_distraw_km", "trip_durationraw_min",
    mode_cols,
    "trip_distancegroup", "distancegroup",
    "trip_purpose", "purpose", "trip_purpose_type",
    "trip_activemode", "trip_utilitarian", "cf_trip_change",
    "cf_mode_shift", "cf_induced"
  )

  unique(cols[cols %in% names(trips)])
}
