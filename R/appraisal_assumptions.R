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
    prefix = c("default_trips_per_user_per_week_", "default_trip_distance_",
               "default_trip_duration_", "assump_trip_speed_"),
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
  spec <- .mode_proxy_spec(.counterfactual_mode_spec(mode))
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

#' Populate calculation assumptions and their provenance
#'
#' Defaults use observed REF, source, configured England, then fixed fallbacks.
#' Existing genuine overrides are preserved. No source records are modified.
#' @param profile Canonical UI appraisal profile.
#' @param reference_data Optional assessed reference people and trips.
#' @param source_data Retained geographic source people and trips.
#' @param cfg HUB configuration.
#' @return Profile with assumption metadata and an assumptions_report attribute.
#' @export
prepare_assumption_profile <- function(profile, reference_data = NULL,
                                       source_data = NULL, cfg = NULL) {
  # Older callers may pass a partial config (including list()). Fill only this
  # section, preserving explicitly configured assumption values.
  defaults <- miama_default_config()$assumptions
  cfg <- cfg %||% list()
  cfg$assumptions <- utils::modifyList(defaults, cfg$assumptions %||% list())
  catalog <- .assumption_catalogue()
  for (mode in .miama_supported_modes()) {
    suffix <- .counterfactual_mode_spec(mode)$suffix
    for (i in seq_len(nrow(catalog))) {
      quantity <- catalog$quantity[i]
      field <- paste0(catalog$prefix[i], suffix)
      entry <- profile[[field]] %||% list(input_value = NULL, is_filled = FALSE)
      value <- NULL
      origin <- "Fixed fallback"
      if (quantity != "speed") {
        value <- .assumption_observed(reference_data, mode, quantity)
        if (!is.null(value)) origin <- "REF population"
        if (is.null(value)) {
          value <- .assumption_observed(source_data, mode, quantity)
          if (!is.null(value)) origin <- "Source population"
        }
        if (is.null(value)) {
          value <- cfg$assumptions$england[[quantity]][[suffix]]
          if (!is.null(value)) origin <- "England population (stored rate)"
        }
      }
      if (is.null(value)) value <- cfg$assumptions$fixed[[quantity]][[suffix]]
      value <- .assumption_positive(value, field)
      # On first migration an unchanged live default is not a manual override.
      if (is.null(entry$assumption) && isTRUE(entry$is_filled) &&
          isTRUE(all.equal(entry$input_value, entry$default_value))) {
        entry$is_filled <- FALSE
        entry["input_value"] <- list(NULL)
      }
      entry$default_value <- value
      entry$unit <- catalog$unit[i]
      entry$label <- catalog$label[i]
      entry$assumption <- list(quantity = quantity, mode = mode, source = origin,
                               proxy = if (mode == "ebiking" && origin %in% c("REF population", "Source population")) "Cycling proxy" else "",
                               provided_above = isTRUE(entry$assumption$provided_above))
      if (isTRUE(entry$is_filled)) .assumption_positive(entry$input_value, field)
      profile[[field]] <- entry
    }
  }
  attr(profile, "assumptions_report") <- get_appraisal_assumptions(profile)
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

#' List effective assumptions for cards and completed results
#' @param profile Canonical profile populated by prepare_assumption_profile().
#' @param tab Optional owning tab (2, 3 or 4).
#' @return Data frame with values, default provenance and applicability.
#' @export
get_appraisal_assumptions <- function(profile, tab = NULL) {
  values <- extract_input_values(profile)
  modes <- normalize_active_modes(.ui_value(values, "modes", character()))
  rows <- list()
  for (field in names(profile)) {
    entry <- profile[[field]]
    if (!is.list(entry) || is.null(entry$assumption)) next
    meta <- entry$assumption
    if (!meta$mode %in% modes) next
    suffix <- .counterfactual_mode_spec(meta$mode)$suffix
    duration_route <- .assumption_duration_route(values, suffix)
    active <- switch(meta$quantity, distance = !duration_route,
                     duration = duration_route, TRUE)
    if (!active) next
    # An explicitly supplied advanced distance distribution is not an
    # assumption. Do not offer a second mean that its sampling weights ignore.
    if (meta$quantity == "distance" &&
        meta$mode %in% values$.assumption_explicit_distance_modes) next
    owner <- if (meta$quantity == "frequency") 3L else 4L
    if (.ui_value(values, "at_data_unit", "users") %in% c("distance", "mode_share")) owner <- 2L
    # Frequency is also required in basic mode; keep one canonical field.
    if (identical(.ui_value(values, "ui_version", "basic"), "basic")) owner <- 2L
    rows[[length(rows) + 1L]] <- data.frame(
      field = field, tab = owner, mode = meta$mode, label = entry$label,
      value = .assumption_positive(values[[field]], field), default_value = entry$default_value,
      unit = entry$unit, source = if (isTRUE(entry$is_filled)) "User override" else meta$source,
      default_source = meta$source, proxy = meta$proxy, editable = TRUE,
      provided_above = isTRUE(meta$provided_above),
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) return(data.frame())
  out <- do.call(rbind, rows)
  if (!is.null(tab)) out <- out[out$tab == tab & !out$provided_above, , drop = FALSE]
  out
}

# Flattening is shared by API and UI. Only fields explicitly registered by the
# assumptions module gain effective-default semantics; ordinary inputs retain
# their existing is_filled behavior.
.assumption_values <- function(values) {
  if (!isTRUE(values$.assumptions_enabled)) return(values)
  for (mode in normalize_active_modes(values$modes)) {
    suffix <- .counterfactual_mode_spec(mode)$suffix
    speed <- .assumption_positive(values[[paste0("assump_trip_speed_", suffix)]], "speed")
    distance_field <- paste0("default_trip_distance_", suffix)
    duration_field <- paste0("default_trip_duration_", suffix)
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
  prefix <- if (kind == "distance") "default_trip_distance_" else "default_trip_duration_"
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
      effective[[paste0("default_trip_distance_", suffix)]] <- distance
      effective[[paste0("default_trip_duration_", suffix)]] <-
        distance / effective[[paste0("assump_trip_speed_", suffix)]] * 60
    }
  }
  constants$assumption_values <- effective
  # PT exposure refers only to the walking access leg. If a donor has no
  # observed access distance, use the same editable fallback shown in the card.
  if ("pt" %in% normalize_active_modes(values$modes)) {
    constants$pt_access_walk_distance_km_default <- effective$default_trip_distance_pt
    constants$pt_access_walk_minutes_default <- effective$default_trip_duration_pt
  }
  constants
}

.assumption_new_user_activity <- function(sampled, values, suffix, reference_mean = mean(sampled)) {
  if (!isTRUE(values$.assumptions_enabled) || !length(sampled)) return(sampled)
  values <- .assumption_values(values)
  hours <- values[[paste0("default_trips_per_user_per_week_", suffix)]] *
    values[[paste0("default_trip_duration_", suffix)]] / 60
  # Preserve variation in observed donor activity while applying the effective
  # frequency/duration assumption to its mean. Never rewrite REF exposure.
  if (is.finite(reference_mean) && reference_mean > 0) sampled / reference_mean * hours else rep(hours, length(sampled))
}
