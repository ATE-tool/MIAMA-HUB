# MIAMA-HUB Module: Reference Data / Spread Functions
# Purpose: Build compact 5-category spread payloads for MIAMA-UI plots and
#   derive counterfactual bar values from counterfactual slider values.
#
# Terminology:
# - `spread` means a compact categorical distribution for plotting. We avoid
#   `dist` here because trip distance is one of the supported spread topics.
# - `ref` is the reference/no-scheme scenario.
# - `cf` is the counterfactual/with-scheme scenario.
#
# Data contract:
# - Reference extraction returns small data frames, not raw individual/trip rows.
# - Each spread data frame has 10 rows: five categories crossed with two series.
# - Slider-driven counterfactual updates only need the reference spread data
#   frame and counterfactual slider values. They do not need raw synthpop data.

MIAMA_SPREAD_CATEGORY_COUNT <- 5L

miama_spread_topics <- function() {
  c("pop", "trips", "pa")
}

# Public helper for MIAMA-UI ---------------------------------------------------
# Recomputes plot bar values from a compact reference spread payload and
# counterfactual slider values. `cf_mean` shifts the five-category marginal
# distribution; `cf_prop` sets the first plotted series, e.g. male or
# utilitarian.

#' Derive Counterfactual Spread Bar Values
#'
#' @param ref_bars A reference spread data frame returned by HUB in a profile
#'   `default_value`, with columns `category`, `variable`, `percent`, and
#'   `category_midpoint`.
#' @param cf_mean Numeric counterfactual slider value for the category mean.
#'   When `NULL`, the reference mean is reused.
#' @param cf_prop Numeric counterfactual slider value for the first variable's
#'   proportion. Values can be proportions (`0.55`) or percentages (`55`). When
#'   `NULL`, the reference split is reused.
#' @param topic Optional spread topic label: `pop`, `trips`, or `pa`.
#'
#' @return A compact counterfactual spread data frame with the same schema as
#'   `ref_bars`.
#' @export
spread_bar_values_from_slider <- function(ref_bars,
                                          cf_mean = NULL,
                                          cf_prop = NULL,
                                          topic = NULL) {
  ref_bars <- .spread_validate_bars(ref_bars)
  if (!is.null(topic) && !topic %in% miama_spread_topics()) {
    stop("`topic` must be one of: ", paste(miama_spread_topics(), collapse = ", "), call. = FALSE)
  }

  categories <- unique(ref_bars$category[order(ref_bars$category_order)])
  variables <- unique(ref_bars$variable[order(ref_bars$variable_order)])
  if (length(categories) != MIAMA_SPREAD_CATEGORY_COUNT || length(variables) != 2L) {
    stop("`ref_bars` must contain five categories and two variables.", call. = FALSE)
  }

  mean_unchanged <- is.null(cf_mean) || length(cf_mean) == 0 || is.na(cf_mean[1])
  prop_unchanged <- is.null(cf_prop) || length(cf_prop) == 0 || is.na(cf_prop[1])
  if (mean_unchanged && prop_unchanged) {
    ref_bars$scenario <- "cf"
    return(ref_bars)
  }

  ref_matrix <- .spread_bars_to_matrix(ref_bars, categories, variables)
  category_midpoints <- .spread_category_midpoints(ref_bars, categories)
  category_marginal <- rowSums(ref_matrix)
  variable_marginal <- colSums(ref_matrix)

  if (is.null(cf_mean) || length(cf_mean) == 0 || is.na(cf_mean[1])) {
    cf_mean <- .spread_weighted_mean(category_marginal, category_midpoints)
  }
  if (is.null(cf_prop) || length(cf_prop) == 0 || is.na(cf_prop[1])) {
    cf_prop <- variable_marginal[1] / 100
  }
  cf_prop <- .spread_clamp_prop(cf_prop)

  cf_category <- .spread_redistribute_numeric_marginal(
    baseline_percent = category_marginal,
    category_midpoints = category_midpoints,
    cf_mean = as.numeric(cf_mean[1])
  )
  cf_variable <- c(cf_prop, 1 - cf_prop) * 100
  names(cf_variable) <- variables

  out_matrix <- outer(cf_category / 100, cf_variable / 100) * 100
  dimnames(out_matrix) <- list(categories, variables)

  .spread_matrix_to_bars(
    spread_matrix = out_matrix,
    category_midpoints = category_midpoints,
    topic = topic %||% unique(ref_bars$topic)[1],
    scenario = "cf"
  )
}

# Reference spread builders ----------------------------------------------------
# These helpers are called during reference-default extraction. They convert raw
# synthpop rows into the compact spread data frames consumed by MIAMA-UI.

reference_population_spread_bars <- function(ind,
                                             trips = NULL,
                                             modes = c("walking", "cycling"),
                                             fallback_all = TRUE,
                                             cfg = NULL) {
  if (is.null(ind) || !"age1year" %in% names(ind) || !"female" %in% names(ind)) {
    return(.spread_empty_bars("pop", c("male", "female"), "agecat"))
  }

  keep <- .selected_mode_individual_filter(ind, trips, modes)
  if (!any(keep, na.rm = TRUE) && isTRUE(fallback_all)) {
    keep <- rep(TRUE, nrow(ind))
  }
  if (!any(keep, na.rm = TRUE)) {
    return(.spread_empty_bars("pop", c("male", "female"), "agecat"))
  }

  age <- .as_plain_numeric(ind$age1year)
  male <- 1 - .as_plain_numeric(ind$female)
  categories <- .spread_numeric_categories(
    age[keep],
    prefix = "agecat",
    category_spec = .spread_category_spec(cfg, "age")
  )
  category <- .spread_cut(age, categories$breaks)

  .spread_joint_bars(
    category = category[keep],
    variable = ifelse(male[keep] >= 0.5, "male", "female"),
    weights = rep(1, sum(keep, na.rm = TRUE)),
    categories = categories,
    variables = c("male", "female"),
    topic = "pop",
    scenario = "ref"
  )
}

reference_pa_spread_bars <- function(ind,
                                     trips = NULL,
                                     modes = c("walking", "cycling"),
                                     fallback_all = TRUE,
                                     cfg = NULL) {
  if (is.null(ind) || !"female" %in% names(ind)) {
    return(.spread_empty_bars("pa", c("male", "female"), "pacat"))
  }

  pa <- .spread_pa_values(ind)
  if (is.null(pa) || all(is.na(pa))) {
    return(.spread_empty_bars("pa", c("male", "female"), "pacat"))
  }

  keep <- .selected_mode_individual_filter(ind, trips, modes)
  if (!any(keep, na.rm = TRUE) && isTRUE(fallback_all)) {
    keep <- rep(TRUE, nrow(ind))
  }
  if (!any(keep, na.rm = TRUE)) {
    return(.spread_empty_bars("pa", c("male", "female"), "pacat"))
  }

  male <- 1 - .as_plain_numeric(ind$female)
  categories <- .spread_numeric_categories(
    pa[keep],
    prefix = "pacat",
    category_spec = .spread_category_spec(cfg, "pa")
  )
  category <- .spread_cut(pa, categories$breaks)

  .spread_joint_bars(
    category = category[keep],
    variable = ifelse(male[keep] >= 0.5, "male", "female"),
    weights = rep(1, sum(keep, na.rm = TRUE)),
    categories = categories,
    variables = c("male", "female"),
    topic = "pa",
    scenario = "ref"
  )
}

reference_trip_spread_bars <- function(trips,
                                       modes = c("walking", "cycling"),
                                       fallback_all = TRUE,
                                       cfg = NULL) {
  if (is.null(trips) || !"trip_distraw_km" %in% names(trips)) {
    return(.spread_empty_bars("trips", c("utilitarian", "recreational"), "distcat"))
  }

  keep <- .selected_mode_trip_filter(trips, modes) & !is.na(trips$nts_tripid)
  if (!any(keep, na.rm = TRUE) && isTRUE(fallback_all)) {
    keep <- !is.na(trips$nts_tripid)
  }
  if (!any(keep, na.rm = TRUE)) {
    return(.spread_empty_bars("trips", c("utilitarian", "recreational"), "distcat"))
  }

  distance <- .as_plain_numeric(trips$trip_distraw_km)
  categories <- .spread_numeric_categories(
    distance[keep],
    prefix = "distcat",
    category_spec = .spread_category_spec(cfg, "trip_distance")
  )
  category <- .spread_cut(distance, categories$breaks)
  util <- if ("trip_purpose" %in% names(trips)) {
    .utilitarian_trip_filter(trips$trip_purpose)
  } else {
    rep(TRUE, nrow(trips))
  }

  .spread_joint_bars(
    category = category[keep],
    variable = ifelse(util[keep], "utilitarian", "recreational"),
    weights = .trip_weights(trips)[keep],
    categories = categories,
    variables = c("utilitarian", "recreational"),
    topic = "trips",
    scenario = "ref"
  )
}

spread_mean_from_bars <- function(bars) {
  bars <- .spread_validate_bars(bars)
  matrix <- .spread_bars_to_matrix(
    bars,
    unique(bars$category[order(bars$category_order)]),
    unique(bars$variable[order(bars$variable_order)])
  )
  midpoints <- .spread_category_midpoints(bars, rownames(matrix))
  .spread_weighted_mean(rowSums(matrix), midpoints)
}

spread_first_variable_prop_from_bars <- function(bars) {
  bars <- .spread_validate_bars(bars)
  if (all(is.na(bars$percent))) {
    return(NA_real_)
  }
  variables <- unique(bars$variable[order(bars$variable_order)])
  keep <- bars$variable == variables[1]
  sum(bars$percent[keep], na.rm = TRUE) / 100
}

spread_category_props_from_bars <- function(bars) {
  bars <- .spread_validate_bars(bars)
  if (all(is.na(bars$percent))) {
    return(rep(NA_real_, MIAMA_SPREAD_CATEGORY_COUNT))
  }

  categories <- unique(bars$category[order(bars$category_order)])
  props <- vapply(categories, function(category) {
    sum(bars$percent[bars$category == category], na.rm = TRUE) / 100
  }, numeric(1))
  if (sum(props, na.rm = TRUE) <= 0) {
    return(rep(NA_real_, MIAMA_SPREAD_CATEGORY_COUNT))
  }
  unname(props / sum(props, na.rm = TRUE))
}

derive_counterfactual_spread_values <- function(appraisal_input_values,
                                                reference_ui_values) {
  values <- appraisal_input_values
  ui_updates <- if (!is.null(reference_ui_values$ui_updates)) {
    reference_ui_values$ui_updates
  } else {
    reference_ui_values
  }

  add_one <- function(ref_field, cf_bars_field, cf_mean_field, cf_prop_field, topic) {
    ref_bars <- ui_updates[[ref_field]]
    if (!is.data.frame(ref_bars)) {
      return()
    }

    values[[cf_bars_field]] <<- spread_bar_values_from_slider(
      ref_bars = ref_bars,
      cf_mean = .ui_value(values, cf_mean_field, NULL),
      cf_prop = .ui_value(values, cf_prop_field, NULL),
      topic = topic
    )
  }

  for (mode in names(.miama_tab2_mode_specs())) {
    suffix <- .miama_mode_suffix(mode)

    add_one(
      ref_field = paste0("pop_spread_bars_ref_", suffix),
      cf_bars_field = paste0("pop_spread_bars_cf_", suffix),
      cf_mean_field = paste0("pop_spread_age_mean_cf_", suffix),
      cf_prop_field = paste0("pop_spread_sex_prop_cf_", suffix),
      topic = "pop"
    )
    add_one(
      ref_field = paste0("pa_spread_bars_ref_", suffix),
      cf_bars_field = paste0("pa_spread_bars_cf_", suffix),
      cf_mean_field = paste0("pop_spread_pa_mean_cf_", suffix),
      cf_prop_field = paste0("pop_spread_pa_sex_prop_cf_", suffix),
      topic = "pa"
    )
    values[[paste0("pop_spread_pa_bars_cf_", suffix)]] <-
      values[[paste0("pa_spread_bars_cf_", suffix)]]
    add_one(
      ref_field = paste0("trips_spread_bars_ref_", suffix),
      cf_bars_field = paste0("trips_spread_bars_cf_", suffix),
      cf_mean_field = paste0("trips_spread_mean_cf_", suffix),
      cf_prop_field = paste0("trips_spread_util_prop_cf_", suffix),
      topic = "trips"
    )
  }

  values
}

# Internals --------------------------------------------------------------------

.selected_mode_trip_filter <- function(trips, modes) {
  keep <- rep(FALSE, if (is.null(trips)) 0 else nrow(trips))
  if (length(keep) == 0) {
    return(keep)
  }

  for (mode in normalize_active_modes(modes)) {
    if (!mode %in% names(.miama_tab2_mode_specs())) {
      next
    }
    spec <- .miama_tab2_mode_specs()[[mode]]
    if (.trip_evidence_available(trips, spec)) {
      keep <- keep | spec$trip_filter(trips)
    }
  }

  keep
}

.spread_numeric_categories <- function(values, prefix, category_spec = NULL) {
  values <- as.numeric(values)
  if (!is.null(category_spec)) {
    return(.spread_configured_categories(category_spec, prefix))
  }

  observed <- values[!is.na(values)]
  if (length(observed) == 0) {
    breaks <- seq(0, MIAMA_SPREAD_CATEGORY_COUNT)
    midpoints <- seq_len(MIAMA_SPREAD_CATEGORY_COUNT)
  } else {
    breaks <- unique(stats::quantile(
      observed,
      probs = seq(0, 1, length.out = MIAMA_SPREAD_CATEGORY_COUNT + 1L),
      na.rm = TRUE,
      names = FALSE
    ))
    if (length(breaks) < 2L) {
      center <- breaks[1]
      breaks <- seq(center - 0.5, center + 0.5, length.out = MIAMA_SPREAD_CATEGORY_COUNT + 1L)
    }
    categories <- .spread_cut(observed, breaks)
    midpoints <- vapply(seq_len(MIAMA_SPREAD_CATEGORY_COUNT), function(i) {
      vals <- observed[categories == i]
      if (length(vals) == 0 || all(is.na(vals))) {
        return(mean(range(breaks), na.rm = TRUE))
      }
      stats::median(vals, na.rm = TRUE)
    }, numeric(1))
  }

  list(
    breaks = breaks,
    labels = paste0(prefix, "_", seq_len(MIAMA_SPREAD_CATEGORY_COUNT)),
    midpoints = midpoints
  )
}

.spread_category_spec <- function(cfg = NULL, topic) {
  cfg <- cfg %||% miama_default_config()
  spec <- cfg$spread[[topic]]
  if (is.null(spec)) {
    return(NULL)
  }
  spec
}

.spread_configured_categories <- function(category_spec, prefix) {
  breaks <- as.numeric(category_spec$breaks)
  labels <- as.character(category_spec$labels)
  midpoints <- as.numeric(category_spec$midpoints)

  if (length(labels) != MIAMA_SPREAD_CATEGORY_COUNT ||
      length(midpoints) != MIAMA_SPREAD_CATEGORY_COUNT ||
      length(breaks) != MIAMA_SPREAD_CATEGORY_COUNT + 1L) {
    stop(
      "Configured spread categories must define five labels, five midpoints, and six breaks.",
      call. = FALSE
    )
  }

  list(
    breaks = breaks,
    labels = labels %||% paste0(prefix, "_", seq_len(MIAMA_SPREAD_CATEGORY_COUNT)),
    midpoints = midpoints
  )
}

.spread_cut <- function(values, breaks) {
  values <- as.numeric(values)
  if (length(breaks) < 2L) {
    return(rep(1L, length(values)))
  }

  raw <- cut(values, breaks = breaks, include.lowest = TRUE, labels = FALSE)
  raw <- as.integer(raw)
  raw[is.na(raw) & !is.na(values) & values < min(breaks, na.rm = TRUE)] <- 1L
  raw[is.na(raw) & !is.na(values) & values > max(breaks, na.rm = TRUE)] <- MIAMA_SPREAD_CATEGORY_COUNT
  pmin(MIAMA_SPREAD_CATEGORY_COUNT, pmax(1L, raw))
}

.spread_joint_bars <- function(category, variable, weights, categories, variables, topic, scenario) {
  category <- as.integer(category)
  variable <- as.character(variable)
  weights <- as.numeric(weights)
  weights[is.na(weights) | weights < 0] <- 0

  matrix <- matrix(
    0,
    nrow = MIAMA_SPREAD_CATEGORY_COUNT,
    ncol = length(variables),
    dimnames = list(categories$labels, variables)
  )

  for (i in seq_along(category)) {
    cat_i <- category[i]
    var_i <- variable[i]
    if (is.na(cat_i) || !var_i %in% variables || is.na(weights[i])) {
      next
    }
    matrix[cat_i, var_i] <- matrix[cat_i, var_i] + weights[i]
  }

  total <- sum(matrix, na.rm = TRUE)
  if (!is.finite(total) || total <= 0) {
    matrix[] <- 0
  } else {
    matrix <- matrix / total * 100
  }

  .spread_matrix_to_bars(matrix, categories$midpoints, topic = topic, scenario = scenario)
}

.spread_matrix_to_bars <- function(spread_matrix, category_midpoints, topic, scenario) {
  category_order <- seq_len(nrow(spread_matrix))
  variable_order <- seq_len(ncol(spread_matrix))
  out <- expand.grid(
    category_order = category_order,
    variable_order = variable_order,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )

  out$topic <- topic
  out$scenario <- scenario
  out$category <- rownames(spread_matrix)[out$category_order]
  out$variable <- colnames(spread_matrix)[out$variable_order]
  out$category_midpoint <- as.numeric(category_midpoints)[out$category_order]
  out$percent <- as.numeric(spread_matrix[cbind(out$category_order, out$variable_order)])
  out$proportion <- out$percent / 100

  out[, c(
    "topic", "scenario", "category_order", "category", "category_midpoint",
    "variable_order", "variable", "percent", "proportion"
  )]
}

.spread_empty_bars <- function(topic, variables, prefix) {
  matrix <- matrix(
    NA_real_,
    nrow = MIAMA_SPREAD_CATEGORY_COUNT,
    ncol = length(variables),
    dimnames = list(paste0(prefix, "_", seq_len(MIAMA_SPREAD_CATEGORY_COUNT)), variables)
  )
  .spread_matrix_to_bars(
    spread_matrix = matrix,
    category_midpoints = seq_len(MIAMA_SPREAD_CATEGORY_COUNT),
    topic = topic,
    scenario = "ref"
  )
}

.spread_validate_bars <- function(ref_bars) {
  if (!is.data.frame(ref_bars)) {
    stop("`ref_bars` must be a data frame.", call. = FALSE)
  }
  required <- c(
    "category_order", "category", "category_midpoint",
    "variable_order", "variable", "percent"
  )
  missing <- setdiff(required, names(ref_bars))
  if (length(missing) > 0) {
    stop("`ref_bars` is missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  ref_bars$category_order <- as.integer(ref_bars$category_order)
  ref_bars$variable_order <- as.integer(ref_bars$variable_order)
  ref_bars$category <- as.character(ref_bars$category)
  ref_bars$variable <- as.character(ref_bars$variable)
  ref_bars$category_midpoint <- as.numeric(ref_bars$category_midpoint)
  ref_bars$percent <- as.numeric(ref_bars$percent)
  if (!("topic" %in% names(ref_bars))) {
    ref_bars$topic <- NA_character_
  }

  ref_bars
}

.spread_bars_to_matrix <- function(bars, categories, variables) {
  out <- matrix(
    0,
    nrow = length(categories),
    ncol = length(variables),
    dimnames = list(categories, variables)
  )

  for (i in seq_len(nrow(bars))) {
    category <- bars$category[i]
    variable <- bars$variable[i]
    if (category %in% categories && variable %in% variables) {
      out[category, variable] <- bars$percent[i]
    }
  }

  out
}

.spread_category_midpoints <- function(bars, categories) {
  out <- vapply(categories, function(category) {
    midpoint <- unique(bars$category_midpoint[bars$category == category])
    midpoint <- midpoint[!is.na(midpoint)]
    if (length(midpoint) == 0) {
      return(NA_real_)
    }
    midpoint[1]
  }, numeric(1))

  if (any(is.na(out))) {
    out[is.na(out)] <- seq_along(out)[is.na(out)]
  }

  out
}

.spread_redistribute_numeric_marginal <- function(baseline_percent,
                                                  category_midpoints,
                                                  cf_mean) {
  baseline_percent <- as.numeric(baseline_percent)
  category_midpoints <- as.numeric(category_midpoints)
  cf_mean <- as.numeric(cf_mean[1])

  baseline_percent[is.na(baseline_percent) | baseline_percent < 0] <- 0
  if (sum(baseline_percent) <= 0) {
    baseline_percent <- rep(100 / length(baseline_percent), length(baseline_percent))
  } else {
    baseline_percent <- baseline_percent / sum(baseline_percent) * 100
  }

  has_weight <- baseline_percent > 0 & !is.na(category_midpoints)
  if (!any(has_weight)) {
    return(baseline_percent)
  }
  if (!is.finite(cf_mean)) {
    return(baseline_percent)
  }

  min_mean <- min(category_midpoints[has_weight], na.rm = TRUE)
  max_mean <- max(category_midpoints[has_weight], na.rm = TRUE)
  cf_mean <- max(min_mean, min(max_mean, cf_mean))
  baseline_mean <- .spread_weighted_mean(baseline_percent, category_midpoints)
  if (abs(cf_mean - baseline_mean) < 1e-9) {
    return(baseline_percent)
  }

  log_floor <- 1e-300
  lse_weights <- function(lambda) {
    log_weights <- log(pmax(baseline_percent, log_floor)) + lambda * category_midpoints
    log_weights <- log_weights - max(log_weights, na.rm = TRUE)
    exp(log_weights)
  }
  tilted_mean <- function(lambda) {
    weights <- lse_weights(lambda)
    sum(category_midpoints * weights, na.rm = TRUE) / sum(weights, na.rm = TRUE) - cf_mean
  }

  root <- tryCatch(
    stats::uniroot(tilted_mean, interval = c(-30, 30))$root,
    error = function(e) NA_real_
  )
  if (is.na(root)) {
    return(baseline_percent)
  }

  weights <- lse_weights(root)
  weights / sum(weights, na.rm = TRUE) * 100
}

.spread_weighted_mean <- function(percent, midpoints) {
  percent <- as.numeric(percent)
  midpoints <- as.numeric(midpoints)
  total <- sum(percent, na.rm = TRUE)
  if (!is.finite(total) || total <= 0) {
    return(NA_real_)
  }
  sum(midpoints * percent, na.rm = TRUE) / total
}

.spread_clamp_prop <- function(value) {
  value <- as.numeric(value[1])
  if (is.na(value)) {
    return(0.5)
  }
  if (value > 1) {
    value <- value / 100
  }
  max(0, min(1, value))
}

.spread_pa_values <- function(ind) {
  if ("mmets" %in% names(ind)) {
    return(.as_plain_numeric(ind$mmets))
  }
  if ("mmet_wkhr" %in% names(ind)) {
    return(.as_plain_numeric(ind$mmet_wkhr))
  }

  pieces <- list()
  if ("walktime_wkhr" %in% names(ind)) {
    pieces$walk <- .as_plain_numeric(ind$walktime_wkhr) * MIAMA_MMET_PER_HOUR[["walking"]]
  }
  if ("cycletime_wkhr" %in% names(ind)) {
    pieces$cycle <- .as_plain_numeric(ind$cycletime_wkhr) * MIAMA_MMET_PER_HOUR[["cycling"]]
  }
  if ("sport_wkhr" %in% names(ind)) {
    pieces$sport <- .as_plain_numeric(ind$sport_wkhr) * MIAMA_MMET_PER_HOUR[["vigorous"]]
  }
  if (length(pieces) == 0) {
    return(NULL)
  }

  out <- Reduce(`+`, lapply(pieces, function(x) {
    x[is.na(x)] <- 0
    x
  }))
  out
}
