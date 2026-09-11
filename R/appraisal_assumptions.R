# Appraisal assumptions: defaults, provenance, applicability and overrides.
#
# This is the single catalogue for quantities that complete an incomplete
# travel input. REF data take precedence over the retained source, then the
# explicitly configured England/fixed fallbacks. Speed is a fixed assumption.
# Profile entries retain a default and its origin separately from user edits.
# Distance routes use distance + speed; duration routes use duration + speed.
# The unused third quantity is derived, never a second independent input.

.assumption_catalogue <- function() {
  data.frame(
    prefix = c("assump_trips_per_user_per_week_", "assump_trip_distance_km_",
               "assump_trip_duration_min_", "assump_trip_speed_kmh_"),
    quantity = c("frequency", "distance", "duration", "speed"),
    label = c("Trips per user per week", "Mean trip distance", "Mean trip duration", "Speed"),
    unit = c("trips/user/week", "km", "minutes", "km/h"),
    stringsAsFactors = FALSE
  )
}

.assumption_positive <- function(value, field) {
  value <- suppressWarnings(as.numeric(value))
  if (length(value) != 1L || !is.finite(value) || value <= 0) {
    stop("Assumption `", field, "` must be one finite number greater than zero.", call. = FALSE)
  }
  value
}

.assumption_observed <- function(data, mode, quantity) {
  if (is.null(data$trips) || !nrow(data$trips)) return(NULL)
  spec <- .counterfactual_mode_spec(mode)
  trips <- data$trips
  rows <- spec$trip_filter(trips)
  if ("ref_in_scope" %in% names(trips)) rows <- rows & .true_values(trips$ref_in_scope)
  rows[is.na(rows)] <- FALSE
  if ("nts_tripid" %in% names(trips)) rows <- rows & !is.na(trips$nts_tripid)
  if (!any(rows)) return(NULL)
  if (quantity == "frequency") {
    if (is.null(data$ind)) return(NULL)
    people <- data$ind
    eligible <- .positive_col(people, spec$activity_col)
    if ("ref_in_scope" %in% names(people)) eligible <- eligible & .true_values(people$ref_in_scope)
    n <- sum(eligible)
    value <- if (n > 0) sum(rows) / n else NA_real_
  } else {
    col <- if (quantity == "distance") spec$trip_distance_col else spec$trip_duration_col
    if (is.na(col) || !col %in% names(trips)) return(NULL)
    x <- .as_plain_numeric(trips[[col]])[rows]
    value <- mean(x[is.finite(x) & x > 0])
  }
  if (length(value) == 1 && is.finite(value) && value > 0) value else NULL
}

#' Populate missing appraisal assumptions
#'
#' Resolves defaults into declared profile fields; saved overrides and resolved
#' defaults remain unchanged unless restore is TRUE. Never runs sampling.
#' @param profile Canonical appraisal profile.
#' @param reference_data Optional assessed REF observations.
#' @param source_data Optional geographic source observations.
#' @param cfg Configuration supplying initial fallback values.
#' @param restore Explicitly replace defaults and clear overrides.
#' @return Updated canonical profile.
#' @export
prepare_assumption_profile <- function(profile, reference_data = NULL,
                                       source_data = NULL, cfg = NULL, restore = FALSE) {
  cfg <- utils::modifyList(miama_default_config(), cfg %||% list())
  geography <- paste(unlist(.assumption_display_values(profile)[c("geo_level", "geo_id")]), collapse = ":")
  for (field in names(profile)[startsWith(names(profile), "assump_")]) {
    if (!identical(profile[[field]]$additional_data$geography, geography)) {
      profile[[field]]$additional_data$resolved <- FALSE
    }
    profile[[field]]$additional_data$geography <- geography
  }
  catalog <- .assumption_catalogue()
  for (mode in .miama_supported_modes()) {
    suffix <- .counterfactual_mode_spec(mode)$suffix
    for (i in seq_len(nrow(catalog))) {
      quantity <- catalog$quantity[i]
      field <- paste0(catalog$prefix[i], suffix)
      if (is.null(profile[[field]])) next
      entry <- profile[[field]]
      if (!restore && isTRUE(entry$additional_data$resolved)) next
      value <- NULL
      origin <- "Fixed fallback"
      proxy <- ""
      if (quantity != "speed") {
        for (candidate in list(list(data = reference_data, origin = "REF population"),
                               list(data = source_data, origin = "Source population"))) {
          value <- .assumption_observed(candidate$data, mode, quantity)
          if (is.null(value) && mode == "ebiking") {
            value <- .assumption_observed(candidate$data, "cycling", quantity)
            if (!is.null(value)) {
              proxy <- "Cycling proxy"
              factor <- switch(quantity,
                distance = cfg$counterfactual$modes$ebiking$proxy_distance_factor,
                duration = cfg$counterfactual$modes$ebiking$proxy_duration_factor, 1)
              value <- value * factor
            }
          }
          if (!is.null(value)) { origin <- candidate$origin; break }
        }
        if (is.null(value)) {
          value <- cfg$assumptions$england[[quantity]][[suffix]]
          if (!is.null(value)) origin <- "England population (stored rate)"
        }
      }
      if (is.null(value)) value <- cfg$assumptions$fixed[[quantity]][[suffix]]
      entry$default_value <- .assumption_positive(value, field)
      entry$unit <- catalog$unit[i]
      entry$label <- catalog$label[i]
      entry$additional_data <- utils::modifyList(entry$additional_data %||% list(),
        list(resolved = TRUE, quantity = quantity, mode = mode, source = origin, proxy = proxy))
      if (restore) { entry$is_filled <- FALSE; entry["input_value"] <- list(NULL) }
      if (isTRUE(entry$is_filled)) .assumption_positive(entry$input_value, field)
      profile[[field]] <- entry
    }
    field <- paste0("assump_trip_source_shares_", suffix)
    if (!is.null(profile[[field]]) && (restore || !isTRUE(profile[[field]]$additional_data$resolved))) {
      diversion <- .reference_diversion_source_defaults(reference_data$trips, mode, cfg, source_data$trips)
      profile <- .prepare_mechanism_field(profile, field, diversion$value, diversion$source, restore)
    }
    profile <- .prepare_mechanism_field(profile, paste0("assump_mmet_per_hour_", suffix),
      unname(cfg$physical_activity$mmet_per_hour[[mode]]), "Configured marginal intensity", restore)
  }
  profile <- .prepare_mechanism_field(profile, "assump_new_user_percent",
    cfg$counterfactual$population$new_user_percent_default, "Configured preference", restore)
  profile <- .prepare_mechanism_field(profile, "assump_induced_trips_percent",
    cfg$counterfactual$trips$assump_induced_trips_percent_default, "Configured preference", restore)
  profile <- .prepare_mechanism_field(profile, "assump_new_user_activity_pattern",
    "observed_donor_patterns", "Implemented sampling policy", restore)
  profile <- .prepare_mechanism_field(profile, "appraisal_model_parameters",
    cfg[c("physical_activity", "counterfactual", "spread", "population_refinement", "results", "population")],
    "Configuration snapshot", restore)
  profile <- .prepare_mechanism_field(profile, "appraisal_sampling_seed", 1L,
    "Default random seed", restore)
  profile <- .prepare_mechanism_field(profile, "appraisal_data_sources",
    cfg$sources, "Configured data source identifiers", restore)
  profile
}

.prepare_mechanism_field <- function(profile, field, value, source, restore) {
  entry <- profile[[field]]
  if (is.null(entry) || (!restore && isTRUE(entry$additional_data$resolved))) return(profile)
  entry$default_value <- value
  entry$additional_data <- utils::modifyList(entry$additional_data %||% list(),
                                            list(resolved = TRUE, source = source))
  if (restore) { entry$is_filled <- FALSE; entry["input_value"] <- list(NULL) }
  profile[[field]] <- entry
  profile
}

.assumption_duration_route <- function(values, suffix) {
  unit <- .ui_value(values, "at_data_unit", "users")
  (identical(unit, "distance") &&
     identical(.ui_value(values, paste0("ui_dist_dur_type_", suffix), "distance"), "duration")) ||
    (identical(unit, "mode_share") &&
       identical(.ui_value(values, "mode_share_total_unit", "trips"), "duration") &&
       isTRUE(.ui_value(values, "ui_mode_share_show_options", FALSE)))
}

#' Assumption fields used by an appraisal
#'
#' A read-only view keyed by canonical schema IDs. Card selection follows
#' explicit route/ownership rules. No defaults, data or sampling are mutated.
#' @param profile Canonical profile with populated assumption defaults.
#' @param tab Optional card number (2, 3 or 4). NULL returns all assumptions.
#' @return Named list of profile entries with read-only display metadata.
#' @export
get_appraisal_assumptions <- function(profile, tab = NULL) {
  if (!is.null(tab) && (length(tab) != 1L || !tab %in% 2:4)) stop("tab must be 2, 3 or 4.")
  values <- .assumption_display_values(profile)
  modes <- normalize_active_modes(values$modes %||% character())
  basic <- !identical(values$ui_version, "advanced")
  rows <- list()
  for (field in names(profile)[startsWith(names(profile), "assump_")]) {
    entry <- profile[[field]]
    mode <- sub("^.*_(walk|bike|ebike|pt)$", "\\1", field)
    per_mode <- mode %in% c("walk", "bike", "ebike", "pt")
    if (per_mode && !normalize_active_modes(mode) %in% modes) next
    quantity <- entry$additional_data$quantity %||% ""
    duration <- per_mode && .assumption_duration_route(values, mode)
    used <- TRUE
    reason <- "Used to allocate activity or calculate exposure"
    owner <- if (basic) 2L else c(2L, 4L)
    collected <- FALSE
    if (quantity == "frequency") {
      owner <- if (basic) 2L else c(2L, 3L)
      collected <- identical(values$at_data_unit, "trips")
      reason <- "Connects trip volume and people receiving activity"
    }
    if (quantity %in% c("distance", "duration")) {
      used <- identical(quantity, if (duration) "duration" else "distance")
      if (per_mode && normalize_active_modes(mode) %in% .assumption_explicit_distance_modes(profile)) used <- FALSE
      reason <- "Completes trip size; the other trip-size quantity is derived"
    }
    if (field == "assump_new_user_percent") {
      owner <- if (basic) 2L else 3L
      used <- !identical(values$at_data_unit, "users") &&
        any(vapply(modes, function(m) !.assumption_explicit_users(profile, .miama_mode_suffix(m)), logical(1)))
      collected <- !basic
      reason <- "Preferred split, overridden by an explicit user count"
    }
    if (field == "assump_new_user_activity_pattern") {
      owner <- if (basic) 2L else 3L
      reason <- "Observed donor variation informs activity of recruited users"
    }
    if (field == "assump_induced_trips_percent") {
      owner <- if (basic) 2L else 4L
      collected <- !basic
      reason <- "Additional trips: induced versus shifted"
    }
    if (startsWith(field, "assump_trip_source_shares_")) {
      owner <- if (basic) 2L else 4L
      collected <- !basic && isTRUE(values$ui_trips_refine_show_chars) &&
        "trip_diversion" %in% values$trips_refine_choice
      reason <- "Source distribution for shifted trips, not mode shares"
    }
    if (startsWith(field, "assump_mmet_per_hour_")) {
      # Retain intensity in the full inventory, not the population/trip cards.
      owner <- integer(0)
      reason <- "Converts active time to physical-activity exposure for health results"
    }
    if (!is.null(tab) && (!used || collected || !tab %in% owner)) next
    entry$display <- list(value = .assumption_entry_value(entry), tab = owner,
      used = used, collected_elsewhere = collected, reason = reason,
      editable = !grepl("^assump_(mmet_per_hour_|new_user_activity_pattern$)", field),
      source = if (isTRUE(entry$is_filled)) "User provided" else entry$additional_data$source)
    rows[[field]] <- entry
  }
  rows
}

.assumption_entry_value <- function(entry) {
  if (isTRUE(entry$is_filled)) entry$input_value else entry$default_value
}

.appraisal_seed <- function(profile, seed = NULL) {
  seed <- seed %||% .assumption_entry_value(profile$appraisal_sampling_seed) %||% 1L
  if (!is.numeric(seed) || length(seed) != 1L || !is.finite(seed) ||
      seed < 0 || seed > .Machine$integer.max || seed != floor(seed)) stop("Invalid appraisal sampling seed.")
  as.integer(seed)
}

.assumption_display_values <- function(profile) {
  lapply(profile, function(entry) if (is_input_field(entry)) .assumption_entry_value(entry) else entry)
}

.assumption_explicit_users <- function(profile, suffix) {
  values <- .assumption_display_values(profile)
  fields <- paste0("pop_number_cf_", suffix,
    if (identical(values$ui_version, "advanced")) "_advanced" else "_basic")
  if (identical(values$at_data_unit, "users")) fields <- c(fields, paste0("users_count_cf_", suffix))
  any(vapply(fields, function(f) isTRUE(profile[[f]]$is_filled) &&
    !is.null(profile[[f]]$input_value), logical(1)))
}

.assumption_explicit_distance_modes <- function(profile) {
  values <- .assumption_display_values(profile)
  if (!identical(values$ui_version, "advanced") || !isTRUE(values$ui_trips_refine_show_chars) ||
      !"trips_distance_purpose" %in% values$trips_refine_choice) return(character())
  modes <- normalize_active_modes(values$modes %||% character())
  modes[vapply(modes, function(m) {
    fields <- paste0(c("trips_spread_mean_cf_", "trips_spread_bars_cf_"), .miama_mode_suffix(m))
    any(vapply(fields, function(f) isTRUE(profile[[f]]$is_filled) &&
      !is.null(profile[[f]]$input_value), logical(1)))
  }, logical(1))]
}

#' Profile fields that refresh assumption cards
#' @param profile Canonical appraisal profile.
#' @param tab Optional owning tab; dependency union is deliberately conservative.
#' @return Character vector containing only IDs present in profile.
#' @export
get_appraisal_assumption_dependencies <- function(profile, tab = NULL) {
  if (!is.null(tab) && (length(tab) != 1L || !tab %in% 2:4)) stop("tab must be 2, 3 or 4.")
  names(profile)[grepl(paste0("^(assump_|appraisal_|geo_|modes$|ui_version$|at_data_unit$|",
    "ui_dist_dur_|distance_unit_|duration_unit_|dist_dur_|users_|trips_|pop_|",
    "mode_share_|ui_mode_share_|ui_pop_|ui_trips_)"), names(profile))]
}

# Flattening is shared by API and UI. Only fields explicitly registered by the
# assumptions module gain effective-default semantics; ordinary inputs retain
# their existing is_filled behavior.
.assumption_values <- function(values) {
  if (!isTRUE(values$.assumptions_enabled)) return(values)
  for (mode in normalize_active_modes(values$modes)) {
    suffix <- .counterfactual_mode_spec(mode)$suffix
    speed <- .assumption_positive(values[[paste0("assump_trip_speed_kmh_", suffix)]], "speed")
    distance_field <- paste0("assump_trip_distance_km_", suffix)
    duration_field <- paste0("assump_trip_duration_min_", suffix)
    if (.assumption_duration_route(values, suffix)) {
      values[[distance_field]] <- .assumption_positive(values[[duration_field]], duration_field) * speed / 60
    } else {
      values[[duration_field]] <- .assumption_positive(values[[distance_field]], distance_field) / speed * 60
    }
  }
  values
}

.assumption_trip_mean <- function(values, reference_data, spec, kind) {
  values <- .assumption_values(values)
  prefix <- if (kind == "distance") "assump_trip_distance_km_" else "assump_trip_duration_min_"
  value <- values[[paste0(prefix, spec$suffix)]]
  if (isTRUE(values$.assumptions_enabled)) return(.assumption_positive(value, paste0(prefix, spec$suffix)))
  .tab2_reference_mode_mean(reference_data$trips, spec, kind)
}

.assumption_cf_constants <- function(values, constants) {
  if (!isTRUE(values$.assumptions_enabled)) return(constants)
  effective <- .assumption_values(values)
  # Advanced distance inputs supersede a completion mean for new-user activity
  # too. Category midpoints approximate the mean when bars provide the input.
  for (mode in values$.assumption_explicit_distance_modes) {
    suffix <- .counterfactual_mode_spec(mode)$suffix
    target <- cf_trip_sampling_target(values, suffix)
    distance <- target$target_mean_distance
    if (!is.null(target$distance_category_props) &&
        length(target$distance_category_props) == length(target$distance_category_midpoints)) {
      distance <- sum(target$distance_category_props * target$distance_category_midpoints)
    }
    if (length(distance) == 1L && is.finite(distance) && distance > 0) {
      effective[[paste0("assump_trip_distance_km_", suffix)]] <- distance
      effective[[paste0("assump_trip_duration_min_", suffix)]] <-
        distance / effective[[paste0("assump_trip_speed_kmh_", suffix)]] * 60
    }
  }
  constants$assumption_values <- effective
  for (mode in normalize_active_modes(values$modes)) {
    suffix <- .miama_mode_suffix(mode)
    field <- paste0("assump_mmet_per_hour_", suffix)
    if (!is.null(values[[field]])) constants[[paste0("mmet_", mode)]] <-
      .assumption_positive(values[[field]], field)
    source <- paste0("assump_trip_source_shares_", suffix)
    if (!is.null(values[[source]])) constants$source_mode_shares[[mode]] <-
      .normalize_diversion_source_shares(values[[source]], mode)
  }
  pattern <- values$assump_new_user_activity_pattern %||% "observed_donor_patterns"
  if (!identical(pattern, "observed_donor_patterns")) stop("Unsupported new-user activity pattern.")
  # PT exposure refers only to the walking access leg. If a donor has no
  # observed access distance, use the same editable fallback shown in the card.
  if ("pt" %in% normalize_active_modes(values$modes)) {
    constants$pt_access_walk_distance_km_default <- effective$assump_trip_distance_km_pt
    constants$pt_access_walk_minutes_default <- effective$assump_trip_duration_min_pt
  }
  constants
}

.assumption_new_user_activity <- function(sampled, values, suffix, reference_mean = mean(sampled)) {
  if (!isTRUE(values$.assumptions_enabled) || !length(sampled)) return(sampled)
  values <- .assumption_values(values)
  hours <- values[[paste0("assump_trips_per_user_per_week_", suffix)]] *
    values[[paste0("assump_trip_duration_min_", suffix)]] / 60
  # Preserve variation in observed donor activity while applying the effective
  # frequency/duration assumption to its mean. Never rewrite REF exposure.
  if (is.finite(reference_mean) && reference_mean > 0) sampled / reference_mean * hours else rep(hours, length(sampled))
}
