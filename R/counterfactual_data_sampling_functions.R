# MIAMA-HUB Module: Counterfactual Data / Sampling Functions
# Purpose: Support Step 6 by selecting existing reference/counterfactual rows
#   that plausibly change status. These helpers do not create synthetic people.
#
# Counterfactual principle:
# - `counterfactual_data` starts as a 1:1 copy of `reference_data`.
# - Source rows remain fixed, but the assessed CF scope may expand beyond REF.
#   Eligible baseline non-users from the retained geography can be recruited as
#   new users without duplicating synthetic people.
# - Utilitarian trip demand is treated as fixed. Active-travel trip increases
#   are mostly existing non-active trips shifting mode, plus a small default
#   share of induced recreational trips that add new trip rows.
# - Sampling is "as-is" row selection. We may weight candidate selection by
#   age/sex or distance distributions, but selected rows remain real rows.
#
# Individual sampling:
# Candidate people are current users or non-users for a mode. Selection can be
# weighted by UI/ref proportions for sex, five age categories, and five PA
# categories. Counterfactual spread bars are preferred; older direct category
# proportion hooks remain as fallbacks.
#
# Trip sampling:
# Candidate shifted trips are non-active utilitarian trips. Selection is
# constrained by five distance categories so a shifted trip is plausible for the
# target active mode. Counterfactual spread bars are preferred; older
# `distcat_1_prop_cf` ... `distcat_5_prop_cf` fields remain as fallbacks.
#
# Remaining clarification needs:
# - Final age, PA, and distance category definitions. Current implementation
#   uses the configured spread-bar category midpoints when compact cf bars are
#   available, with local quintiles only as a fallback for older direct category
#   proportion fields.
# - More detailed mode-specific diversion fields in MIAMA-UI. HUB already parses
#   simple `% car` and future per-mode percentage hooks.
# - Weighted trip data. Shifted rows retain their existing weights and induced
#   rows retain the sampled donor weight. UI weighted targets are translated to
#   physical-row targets before these samplers are called.

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

cf_add_key_indicators <- function(counterfactual_data, modes = .miama_supported_modes()) {
  counterfactual_data <- .prepare_mode_features(counterfactual_data)
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
    if (!"cf_trip_locked" %in% names(counterfactual_data$trips)) {
      counterfactual_data$trips$cf_trip_locked <- FALSE
    }
    if (!"cf_trip_exposure_source" %in% names(counterfactual_data$trips)) {
      counterfactual_data$trips$cf_trip_exposure_source <- "unchanged"
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
  if ("ebiketime_wkhr" %in% names(ind)) {
    ind$user_ebike <- !is.na(ind$ebiketime_wkhr) & ind$ebiketime_wkhr > 0
  }
  if ("pttime_wkhr" %in% names(ind)) {
    ind$user_pt <- !is.na(ind$pttime_wkhr) & ind$pttime_wkhr > 0
  }

  ind
}

cf_add_trip_indicators <- function(trips, modes = .miama_supported_modes()) {
  active <- rep(FALSE, nrow(trips))
  for (mode in modes) {
    spec <- .counterfactual_mode_spec(mode)
    if (!is.null(spec) && .trip_evidence_available_for_counterfactual(trips, spec)) {
      active <- active | spec$trip_filter(trips)
    }
  }

  trips$trip_activemode <- active
  utilitarian <- cf_trip_utilitarian(trips, active)
  if ("cf_induced" %in% names(trips)) {
    induced <- !is.na(trips$cf_induced) & trips$cf_induced
    utilitarian[induced] <- FALSE
  }
  trips$trip_utilitarian <- utilitarian
  trips
}

cf_trip_utilitarian <- function(trips, active = rep(FALSE, nrow(trips))) {
  util <- rep(TRUE, nrow(trips))
  if ("trip_purpose" %in% names(trips)) {
    util <- .utilitarian_trip_filter(trips$trip_purpose)
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

  fallback <- NULL
  if (!is.null(weights)) {
    weights <- weights[seq_along(candidate_rows)]
    weights[!is.finite(weights) | weights < 0] <- 0
    if (sum(weights) == 0) {
      fallback <- list(
        reason = "all_candidate_weights_zero",
        requested_n = n,
        positive_weight_candidates = 0L,
        relaxed_n = n
      )
      weights <- NULL
    }
  }

  set.seed(seed)
  if (!isTRUE(replace) && !is.null(weights) && sum(weights > 0) < n) {
    positive_pos <- which(weights > 0)
    zero_pos <- which(weights == 0)
    relaxed_n <- n - length(positive_pos)

    # All positive-weight rows are required to reach `n`; fill only the
    # unavoidable remainder from rows excluded by the combined constraints.
    sampled_pos <- c(
      positive_pos,
      sample(zero_pos, size = relaxed_n, replace = FALSE)
    )
    sampled_pos <- sample(sampled_pos, length(sampled_pos), replace = FALSE)
    fallback <- list(
      reason = "insufficient_positive_weight_candidates",
      requested_n = n,
      positive_weight_candidates = length(positive_pos),
      relaxed_n = relaxed_n
    )
  } else {
    sampled_pos <- sample(seq_along(candidate_rows), size = n, replace = replace, prob = weights)
  }

  out <- candidate_rows[sampled_pos]
  attr(out, "sampling_fallback") <- fallback
  out
}

cf_individual_candidate_weights <- function(ind, candidate_rows, target = list()) {
  weights <- rep(1, length(candidate_rows))
  if (length(candidate_rows) == 0) {
    return(weights)
  }

  if ("female" %in% names(ind) && !is.null(target$male_prop)) {
    female <- .as_plain_numeric(ind$female[candidate_rows])
    male <- !is.na(female) & female == 0
    weights <- weights * ifelse(male, target$male_prop, 1 - target$male_prop)
  }

  if ("age1year" %in% names(ind) && !is.null(target$age_category_props)) {
    category <- if (!is.null(target$age_category_breaks)) {
      cf_numeric_quintile(
        ind$age1year,
        breaks = target$age_category_breaks,
        right = target$age_category_right
      )
    } else if (!is.null(target$age_category_midpoints)) {
      cf_numeric_category_from_midpoints(ind$age1year, target$age_category_midpoints)
    } else {
      cf_numeric_quintile(ind$age1year)
    }
    weights <- weights * cf_quintile_weights(category[candidate_rows], target$age_category_props)
  } else if ("age1year" %in% names(ind) && !is.null(target$age_quintile_props)) {
    quintile <- cf_numeric_quintile(ind$age1year)
    weights <- weights * cf_quintile_weights(quintile[candidate_rows], target$age_quintile_props)
  }

  if (!is.null(target$pa_category_props)) {
    pa <- .spread_pa_values(ind)
    if (!is.null(pa) && !all(is.na(pa))) {
      category <- if (!is.null(target$pa_category_breaks)) {
        cf_numeric_quintile(
          pa,
          breaks = target$pa_category_breaks,
          right = target$pa_category_right
        )
      } else if (!is.null(target$pa_category_midpoints)) {
        cf_numeric_category_from_midpoints(pa, target$pa_category_midpoints)
      } else {
        cf_numeric_quintile(pa)
      }
      weights <- weights * cf_quintile_weights(category[candidate_rows], target$pa_category_props)
    }
  }

  weights
}

cf_trip_candidate_weights <- function(trips, candidate_rows, active_distances, target = list()) {
  weights <- rep(1, length(candidate_rows))
  if (length(candidate_rows) == 0 || !"trip_distraw_km" %in% names(trips)) {
    return(weights)
  }

  if (is.null(target$distance_category_props) && !is.null(target$target_mean_distance)) {
    return(weights * cf_mean_distance_weights(
      trips$trip_distraw_km[candidate_rows],
      target$target_mean_distance
    ))
  }

  if (length(active_distances) == 0 || all(is.na(active_distances))) {
    return(weights)
  }

  if (!is.null(target$distance_category_props)) {
    category <- if (!is.null(target$distance_category_breaks)) {
      cf_numeric_quintile(
        trips$trip_distraw_km,
        breaks = target$distance_category_breaks,
        right = target$distance_category_right
      )
    } else if (!is.null(target$distance_category_midpoints)) {
      cf_numeric_category_from_midpoints(trips$trip_distraw_km, target$distance_category_midpoints)
    } else {
      cf_distance_quintile(trips$trip_distraw_km, active_distances)
    }
    props <- target$distance_category_props
  } else {
    category <- cf_distance_quintile(trips$trip_distraw_km, active_distances)
    props <- target$distance_quintile_props
    if (is.null(props)) {
      props <- .cf_reference_quintile_props(cf_distance_quintile(active_distances, active_distances))
    }
  }

  weights * cf_quintile_weights(category[candidate_rows], props)
}

cf_mean_distance_weights <- function(distances, target_mean) {
  distances <- suppressWarnings(as.numeric(distances))
  target_mean <- suppressWarnings(as.numeric(target_mean))
  if (length(target_mean) != 1 || !is.finite(target_mean) || target_mean <= 0) {
    return(rep(1, length(distances)))
  }

  observed <- distances[is.finite(distances) & distances >= 0]
  spread <- suppressWarnings(stats::IQR(observed, na.rm = TRUE) / 1.349)
  bandwidth <- max(c(spread, target_mean / 2, 0.25), na.rm = TRUE)
  weights <- exp(-0.5 * ((distances - target_mean) / bandwidth) ^ 2)
  weights[!is.finite(weights)] <- 0
  if (sum(weights) <= 0) {
    return(rep(1, length(distances)))
  }

  weights
}

cf_numeric_quintile <- function(values, breaks = NULL, right = TRUE) {
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

  as.integer(cut(
    values,
    breaks = breaks,
    include.lowest = TRUE,
    right = isTRUE(right),
    labels = FALSE
  ))
}

cf_numeric_category_from_midpoints <- function(values, midpoints) {
  values <- as.numeric(values)
  midpoints <- sort(unique(as.numeric(midpoints)))
  midpoints <- midpoints[is.finite(midpoints)]
  if (length(midpoints) < 2) {
    return(rep(1L, length(values)))
  }

  boundaries <- (midpoints[-1] + midpoints[-length(midpoints)]) / 2
  boundaries <- c(-Inf, as.numeric(boundaries), Inf)
  as.integer(cut(values, breaks = boundaries, include.lowest = TRUE, labels = FALSE))
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

cf_population_sampling_target <- function(values, suffix = NULL, spread = NULL) {
  pop_bars_cf <- .cf_mode_value(values, "pop_spread_bars_cf", suffix)
  pa_bars_cf <- .cf_mode_value(values, "pa_spread_bars_cf", suffix)
  if (is.null(pa_bars_cf)) {
    pa_bars_cf <- .cf_mode_value(values, "pop_spread_pa_bars_cf", suffix)
  }

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
  pa_props <- if (is.data.frame(pa_bars_cf)) {
    spread_category_props_from_bars(pa_bars_cf)
  } else {
    cf_ui_category_props(values, "pacat")
  }

  selected_age <- .cf_selected_category_indices(
    values,
    method = "pop_age",
    field = "pop_target_age_groups",
    ids = spread$age$ids %||% character(0),
    strip_prefix = "pop_"
  )
  selected_pa <- .cf_selected_category_indices(
    values,
    method = "pop_pa_level",
    field = "pop_target_pa_groups",
    ids = spread$pa$ids %||% character(0)
  )
  if (!is.null(selected_age)) {
    age_props <- as.numeric(seq_along(spread$age$ids) %in% selected_age)
    age_props <- age_props / sum(age_props)
  }
  if (!is.null(selected_pa)) {
    pa_props <- as.numeric(seq_along(spread$pa$ids) %in% selected_pa)
    pa_props <- pa_props / sum(pa_props)
  }

  list(
    male_prop = .cf_clamp_prop(male_prop),
    age_category_props = age_props,
    age_category_midpoints = if (is.data.frame(pop_bars_cf)) {
      cf_spread_category_midpoints_from_bars(pop_bars_cf)
    } else {
      NULL
    },
    age_category_breaks = spread$age$breaks %||% NULL,
    age_category_right = spread$age$right %||% TRUE,
    age_quintile_props = age_props,
    pa_category_props = pa_props,
    pa_category_midpoints = if (is.data.frame(pa_bars_cf)) {
      cf_spread_category_midpoints_from_bars(pa_bars_cf)
    } else {
      NULL
    },
    pa_category_breaks = spread$pa$breaks %||% NULL,
    pa_category_right = spread$pa$right %||% TRUE,
    selected_age_categories = selected_age,
    selected_pa_categories = selected_pa,
    constraints = c(
      if (!is.null(male_prop)) "sex",
      if (!is.null(age_props)) "age",
      if (!is.null(pa_props)) "pa"
    )
  )
}

.cf_selected_category_indices <- function(values,
                                          method,
                                          field,
                                          ids,
                                          strip_prefix = NULL) {
  if (!identical(.ui_value(values, "pop_refine_method", NULL), method)) {
    return(NULL)
  }
  selected <- as.character(.ui_value(values, field, character(0)))
  if (!is.null(strip_prefix)) selected <- sub(paste0("^", strip_prefix), "", selected)
  matched <- match(selected, ids)
  matched <- matched[!is.na(matched)]
  if (length(matched) == 0) {
    stop("Selected population categories do not match the configured category definitions.", call. = FALSE)
  }
  unique(matched)
}

cf_population_candidate_filter <- function(ind,
                                           candidate_rows,
                                           target,
                                           select_inside = TRUE) {
  has_selection <- !is.null(target$selected_age_categories) ||
    !is.null(target$selected_pa_categories)
  if (!has_selection) return(candidate_rows)
  keep <- rep(TRUE, length(candidate_rows))
  if (!is.null(target$selected_age_categories)) {
    category <- cf_numeric_quintile(
      ind$age1year,
      breaks = target$age_category_breaks,
      right = target$age_category_right
    )
    keep <- keep & category[candidate_rows] %in% target$selected_age_categories
  }
  if (!is.null(target$selected_pa_categories)) {
    pa <- .spread_pa_values(ind)
    category <- cf_numeric_quintile(
      pa,
      breaks = target$pa_category_breaks,
      right = target$pa_category_right
    )
    keep <- keep & category[candidate_rows] %in% target$selected_pa_categories
  }
  candidate_rows[if (isTRUE(select_inside)) keep else !keep]
}

cf_trip_sampling_target <- function(values, suffix = NULL, spread = NULL) {
  ui_version <- values$ui_version %||% "basic"
  ui_version <- if (identical(ui_version, "advanced")) "advanced" else "basic"
  trip_bars_cf <- .cf_mode_value(values, "trips_spread_bars_cf", suffix)
  distance_props <- if (is.data.frame(trip_bars_cf)) {
    spread_category_props_from_bars(trip_bars_cf)
  } else {
    cf_ui_category_props(values, "distcat")
  }
  util_prop <- if (is.data.frame(trip_bars_cf)) {
    spread_first_variable_prop_from_bars(trip_bars_cf)
  } else {
    .cf_mode_value(values, "trips_spread_util_prop_cf", suffix)
  }
  target_mean_distance <- if (identical(ui_version, "advanced")) {
    .cf_mode_value(values, "trips_spread_mean_cf", suffix)
  } else {
    NULL
  }
  if (is.null(target_mean_distance) || length(target_mean_distance) == 0 ||
      (length(target_mean_distance) == 1 && is.na(target_mean_distance))) {
    target_mean_distance <- .cf_mode_value(values, "default_trip_distance", suffix)
  }

  list(
    distance_category_props = distance_props,
    distance_category_midpoints = if (is.data.frame(trip_bars_cf)) {
      cf_spread_category_midpoints_from_bars(trip_bars_cf)
    } else {
      NULL
    },
    distance_category_breaks = spread$trip_distance$breaks %||% NULL,
    distance_category_right = spread$trip_distance$right %||% TRUE,
    distance_quintile_props = distance_props,
    target_mean_distance = target_mean_distance,
    target_utilitarian_prop = util_prop,
    constraints = c(
      if (!is.null(distance_props)) "distance",
      if (is.null(distance_props) && !is.null(target_mean_distance)) "distance_mean",
      if (!is.null(util_prop)) "purpose"
    )
  )
}

cf_spread_category_midpoints_from_bars <- function(bars) {
  if (!is.data.frame(bars) || !"category_midpoint" %in% names(bars)) {
    return(NULL)
  }
  category_col <- if ("category_order" %in% names(bars)) {
    order(bars$category_order)
  } else {
    seq_len(nrow(bars))
  }
  ordered <- bars[category_col, , drop = FALSE]
  midpoints <- ordered$category_midpoint[!duplicated(ordered$category)]
  midpoints <- as.numeric(midpoints)
  if (length(midpoints) == 0 || all(is.na(midpoints))) {
    return(NULL)
  }
  midpoints
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

cf_trip_mechanism_counts <- function(delta, induced_trips_percent = 10) {
  if (delta <= 0) {
    return(list(mode_shift_n = 0L, induced_n = 0L))
  }

  induced_n <- as.integer(round(delta * induced_trips_percent / 100))
  induced_n <- min(delta, max(0L, induced_n))
  list(
    mode_shift_n = as.integer(delta - induced_n),
    induced_n = induced_n
  )
}

cf_individual_sampling_columns <- function(ind, modes = .miama_supported_modes()) {
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

cf_trip_sampling_columns <- function(trips, modes = .miama_supported_modes()) {
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
    "cf_mode_shift", "cf_induced", "cf_trip_locked"
  )

  unique(cols[cols %in% names(trips)])
}
