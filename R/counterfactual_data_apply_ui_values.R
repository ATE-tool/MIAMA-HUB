# MIAMA-HUB Module: Counterfactual Data / Apply UI Values
# Purpose: Apply UI-provided `_cf_` values to a counterfactual copy of
#   `reference_data`.
# Inputs: Current `counterfactual_data`, flattened `appraisal_input_values`, and
#   the unmodified `reference_data` used for reference distributions.
# Outputs: Updated `counterfactual_data` with a `counterfactual_report`.
#
# Structure of this file:
# 1. Public orchestrator
# 2. Handler registry and shared context
# 3. UI field handlers
# 4. Field-specific helpers
# 5. Shared data-manipulation helpers
# 6. Validation helpers
# 7. Constants/defaults
# 8. Report helpers
#
# Handler design:
# Each handler owns one conceptual family of UI fields, not one literal input.
# For example, `.apply_cf_active_user_count_handler()` handles
# `users_count_cf_*` and `pop_number_cf_*` because both mean "set the
# counterfactual number of active mode users".
#
# Anticipated future handler families:
# - active-mode user count targets: implemented first-pass
# - active-mode activity amounts for current/new users
# - population distribution targets: age/sex/PA anchors
# - trip count targets: induced or shifted trip counts
# - trip mode-shift/diversion targets
# - trip attribute targets: distance, duration, purpose distributions
#
# Current scope:
# - Individual row counts stay fixed. User-count targets switch existing people
#   between current non-user/new user and current user/ex-user states.
# - Key indicators (`user_walk`, `user_bike`, `trip_activemode`,
#   `trip_utilitarian`, and CF change flags) are added to the returned data.
# - Trip increases are represented as mode shifts for existing utilitarian
#   non-active trips plus a default 10% induced recreational active trips.
# - Trip decreases switch active trips away from the active mode rather than
#   deleting utilitarian travel demand.
#
# Sampling behavior is centralized in
# `R/counterfactual_data_sampling_functions.R`. Sampling selects existing rows
# "as is"; dependent activity values are drawn from observed current users or
# defaults without creating synthetic individuals.
#
# Current constraints:
# - Counterfactual user-count targets must be finite, non-negative integers after
#   rounding, and no larger than the filtered reference population size.
# - E-bike and walk-to-PT user count changes are accepted only as report notes
#   until reference data exposes defensible target activity columns.
#
# Parameter/constants naming convention:
# - `*_ref` values are measured from `reference_data`.
# - `*_default` values come from constants used only when a reference
#   distribution is unavailable.
# TODO: Externalize constants and constraints once defaults are agreed.


# 1. Public Orchestrator ----

apply_counterfactual_ui_values <- function(
    counterfactual_data,
    appraisal_input_values = list(),
    reference_data = counterfactual_data,
    constants = miama_counterfactual_defaults(),
    seed = 1L
) {
  context <- .counterfactual_context(
    counterfactual_data = counterfactual_data,
    appraisal_input_values = appraisal_input_values,
    reference_data = reference_data,
    constants = constants,
    seed = seed
  )

  counterfactual_data <- context$counterfactual_data
  report <- .counterfactual_report_init(counterfactual_data)

  for (handler in .counterfactual_ui_handler_registry()) {
    result <- handler(counterfactual_data, context)
    counterfactual_data <- result$counterfactual_data
    report$changes <- c(report$changes, result$changes)
    report$notes <- c(report$notes, result$notes)
  }

  counterfactual_data$counterfactual_report <- .counterfactual_report_finalize(
    report,
    counterfactual_data,
    context$reference_data
  )

  counterfactual_data
}


# 2. Handler Registry And Shared Context ----

.counterfactual_ui_handler_registry <- function() {
  list(
    .apply_cf_active_user_count_handler,
    .apply_cf_active_trip_count_handler
  )
}

.counterfactual_context <- function(
    counterfactual_data,
    appraisal_input_values,
    reference_data,
    constants,
    seed
) {
  if (length(appraisal_input_values) == 0 && is.null(names(appraisal_input_values))) {
    names(appraisal_input_values) <- character(0)
  }

  assert_named_list(counterfactual_data, "counterfactual_data")
  assert_named_list(reference_data, "reference_data")
  assert_named_list(appraisal_input_values, "appraisal_input_values")
  assert_named_list(constants, "constants")

  modes <- normalize_active_modes(.ui_value(appraisal_input_values, "modes", character(0)))
  if (length(modes) == 0) {
    modes <- names(.miama_tab2_mode_specs())
  }

  counterfactual_data <- cf_add_key_indicators(counterfactual_data, modes)
  reference_data <- cf_add_key_indicators(reference_data, modes)

  list(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    values = appraisal_input_values,
    constants = constants,
    seed = seed,
    modes = modes,
    user_sampling_strategy = cf_sampling_strategy_from_ui(appraisal_input_values, scope = "user"),
    trip_sampling_strategy = cf_sampling_strategy_from_ui(appraisal_input_values, scope = "trip")
  )
}


# 3. UI Field Handlers ----

# Handler: active-mode user count targets ----
# UI fields:
# - `users_count_cf_walk`, `users_count_cf_bike`
# - `pop_number_cf_walk`, `pop_number_cf_bike`
#
# Data manipulation:
# - Select row IDs from current non-users or current users.
# - Assign mode-specific weekly activity values to selected individual rows.
# - Recalculate derived individual attributes (`mmets`) when available.
# - Mirror changed individual activity onto trip rows when trip data has the
#   same individual-level activity column.
#
# Key assumptions:
# - "User" means activity column > 0, consistent with Step 5 thresholds.
# - New user activity values come from reference users for the same mode.
# - Ex-user activity values come from reference non-users for the same mode.
.apply_cf_active_user_count_handler <- function(counterfactual_data, context) {
  changes <- list()
  notes <- character(0)

  for (mode in context$modes) {
    result <- .apply_cf_user_count_for_mode(
      counterfactual_data = counterfactual_data,
      reference_data = context$reference_data,
      appraisal_input_values = context$values,
      mode = mode,
      constants = context$constants,
      seed = context$seed,
      sampling_strategy = context$user_sampling_strategy
    )

    counterfactual_data <- result$counterfactual_data
    changes <- c(changes, result$changes)
    notes <- c(notes, result$notes)
  }

  list(
    counterfactual_data = counterfactual_data,
    changes = changes,
    notes = notes
  )
}

# Handler: active-mode trip count targets ----
# UI fields:
# - `trips_count_cf_walk`, `trips_count_cf_bike`
# - `trips_number_cf_walk`, `trips_number_cf_bike`
#
# Related refinement fields parsed into report metadata:
# - `trips_timeframe_*`, `trips_denominator_*`
# - `pop_new_current_perc`
# - `trips_dist_value`, `trips_purpose_type`, `trips_purpose_util_perc`
# - `trips_spread_mean_cf`, `trips_spread_util_prop_cf`
#
# Data manipulation, first-pass:
# - Convert user-supplied trip target to a base-week count.
# - If target is larger than current active-mode trip rows, duplicate sampled
#   active-mode reference trip rows.
# - If target is smaller, remove sampled active-mode trip rows.
# - Use reference trip rows as donors so distance/duration/purpose distributions
#   initially follow current use.
#
# Key limitations:
# - This currently manipulates physical rows, not weighted trip totals. If
#   `weight_tripXhh` is present, the report flags this approximation.
# - Advanced distribution controls are parsed and recorded but not yet used to
#   reshape donor sampling or trip attributes.
.apply_cf_active_trip_count_handler <- function(counterfactual_data, context) {
  changes <- list()
  notes <- character(0)

  for (mode in context$modes) {
    result <- .apply_cf_trip_count_for_mode(
      counterfactual_data = counterfactual_data,
      reference_data = context$reference_data,
      appraisal_input_values = context$values,
      mode = mode,
      constants = context$constants,
      seed = context$seed,
      sampling_strategy = context$trip_sampling_strategy
    )

    counterfactual_data <- result$counterfactual_data
    changes <- c(changes, result$changes)
    notes <- c(notes, result$notes)
  }

  list(
    counterfactual_data = counterfactual_data,
    changes = changes,
    notes = notes
  )
}


# 4. Field-Specific Helpers ----

## Tab 2 "How much does AT change?"

### Users, user counts ----

.apply_cf_user_count_for_mode <- function(
    counterfactual_data,
    reference_data,
    appraisal_input_values,
    mode,
    constants,
    seed,
    sampling_strategy
) {
  spec <- .counterfactual_mode_spec(mode)
  if (is.null(spec) || is.na(spec$activity_col)) {
    return(.counterfactual_no_change(
      counterfactual_data,
      paste0("Counterfactual user-count changes for mode `", mode, "` are not implemented yet.")
    ))
  }

  target <- .cf_user_target(appraisal_input_values, spec$suffix)
  if (is.null(target)) {
    return(.counterfactual_no_change(counterfactual_data))
  }

  .require_cf_user_count_columns(counterfactual_data, reference_data, spec)

  pop_total_ref <- nrow(reference_data$ind)
  target <- .validate_cf_user_target(target, pop_total_ref, spec)

  ref_users <- .positive_col(reference_data$ind, spec$activity_col)
  cf_users <- .positive_col(counterfactual_data$ind, spec$activity_col)
  ref_n <- sum(ref_users, na.rm = TRUE)
  cf_n <- sum(cf_users, na.rm = TRUE)
  delta <- target - cf_n

  assignment <- .assign_cf_user_count_delta(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    spec = spec,
    ref_users = ref_users,
    cf_users = cf_users,
    delta = delta,
    constants = constants,
    seed = seed,
    sampling_strategy = sampling_strategy,
    population_target = cf_population_sampling_target(appraisal_input_values)
  )

  counterfactual_data <- assignment$counterfactual_data
  counterfactual_data <- .recalculate_counterfactual_mmets(counterfactual_data, constants)
  trip_effect <- .apply_user_status_trip_effects(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    spec = spec,
    changed_rows = assignment$changed_rows,
    role = assignment$role,
    constants = constants,
    seed = seed,
    trip_target = cf_trip_sampling_target(appraisal_input_values),
    diversion_target = .cf_diversion_target(appraisal_input_values, constants)
  )
  counterfactual_data <- trip_effect$counterfactual_data
  counterfactual_data <- cf_add_key_indicators(counterfactual_data, spec$mode)

  updated_cf_users <- .positive_col(counterfactual_data$ind, spec$activity_col)
  change <- .compact_counterfactual_change(
    field = paste0("users_count_cf_", spec$suffix),
    alias_field = paste0("pop_number_cf_", spec$suffix),
    mode = mode,
    activity_col = spec$activity_col,
    target = target,
    ref_n = ref_n,
    cf_n_before = cf_n,
    cf_n_after = sum(updated_cf_users, na.rm = TRUE),
    delta = delta,
    role = assignment$role,
    donor_source = assignment$donor_source,
    census_id = .changed_census_ids(counterfactual_data$ind, assignment$changed_rows)
  )
  change$sampling_strategy <- assignment$sampling_strategy
  change$relevant_attributes <- assignment$relevant_attributes
  change$user_trip_shift_target_n <- trip_effect$trip_shift_target_n
  change$user_trip_shift_n <- trip_effect$trip_shift_n

  list(
    counterfactual_data = counterfactual_data,
    changes = list(change),
    notes = trip_effect$notes
  )
}

.assign_cf_user_count_delta <- function(
    counterfactual_data,
    reference_data,
    spec,
    ref_users,
    cf_users,
    delta,
    constants,
    seed,
    sampling_strategy,
    population_target
) {
  if (delta == 0) {
    return(list(
      counterfactual_data = counterfactual_data,
      changed_rows = integer(0),
      role = "unchanged",
      donor_source = "reference_data",
      sampling_strategy = sampling_strategy,
      relevant_attributes = cf_individual_sampling_columns(reference_data$ind, spec$mode)
    ))
  }

  if (delta > 0) {
    candidate_rows <- which(!cf_users)
    weights <- cf_individual_candidate_weights(counterfactual_data$ind, candidate_rows, population_target)
    changed_rows <- cf_sample_candidate_indices(
      candidate_rows,
      delta,
      seed + spec$seed_offset,
      weights = weights
    )
    replacement_values <- cf_sample_observed_values(
      values_ref = reference_data$ind[[spec$activity_col]][ref_users],
      n = length(changed_rows),
      default_value = constants[[spec$default_col]],
      seed = seed + spec$seed_offset + 1000L
    )
    role <- "new_users"
  } else {
    candidate_rows <- which(cf_users)
    weights <- cf_individual_candidate_weights(counterfactual_data$ind, candidate_rows, population_target)
    changed_rows <- cf_sample_candidate_indices(
      candidate_rows,
      abs(delta),
      seed + spec$seed_offset,
      weights = weights
    )
    replacement_values <- rep(constants[[spec$ex_user_default_col]], length(changed_rows))
    role <- "ex_users"
  }

  counterfactual_data$ind[[spec$activity_col]][changed_rows] <- replacement_values
  counterfactual_data$ind$cf_user_change[changed_rows] <- role

  list(
    counterfactual_data = counterfactual_data,
    changed_rows = changed_rows,
    role = role,
    donor_source = "reference_data",
    sampling_strategy = sampling_strategy,
    relevant_attributes = cf_individual_sampling_columns(reference_data$ind, spec$mode)
  )
}

.cf_user_target <- function(values, suffix) {
  users_field <- paste0("users_count_cf_", suffix)
  pop_field <- paste0("pop_number_cf_", suffix)

  target <- .ui_value(values, users_field, NULL)
  if (is.null(target)) {
    target <- .ui_value(values, pop_field, NULL)
  }

  target
}

### Trips, Trip counts ----

.apply_cf_trip_count_for_mode <- function(
    counterfactual_data,
    reference_data,
    appraisal_input_values,
    mode,
    constants,
    seed,
    sampling_strategy
) {
  spec <- .counterfactual_mode_spec(mode)
  if (is.null(spec) || !.trip_evidence_available_for_counterfactual(reference_data$trips, spec)) {
    return(.counterfactual_no_change(
      counterfactual_data,
      paste0("Counterfactual trip-count changes for mode `", mode, "` are not implemented yet.")
    ))
  }

  target <- .cf_trip_target(appraisal_input_values, spec$suffix)
  if (is.null(target$value)) {
    return(.counterfactual_no_change(counterfactual_data))
  }

  .require_cf_trip_count_columns(counterfactual_data, reference_data, spec)

  args <- .cf_trip_distribution_args(appraisal_input_values, spec$suffix)
  target_base <- .validate_cf_trip_target(target, reference_data, spec)

  cf_active <- spec$trip_filter(counterfactual_data$trips) & !is.na(counterfactual_data$trips$nts_tripid)
  ref_active <- spec$trip_filter(reference_data$trips) & !is.na(reference_data$trips$nts_tripid)
  cf_n <- sum(cf_active, na.rm = TRUE)
  ref_n <- sum(ref_active, na.rm = TRUE)
  delta <- target_base$count - cf_n

  assignment <- .assign_cf_trip_count_delta(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    spec = spec,
    ref_active = ref_active,
    cf_active = cf_active,
    delta = delta,
    seed = seed,
    sampling_strategy = sampling_strategy,
    trip_target = cf_trip_sampling_target(appraisal_input_values),
    constants = constants,
    diversion_target = .cf_diversion_target(appraisal_input_values, constants)
  )

  counterfactual_data <- assignment$counterfactual_data
  updated_cf_active <- spec$trip_filter(counterfactual_data$trips) &
    !is.na(counterfactual_data$trips$nts_tripid)

  change <- .compact_counterfactual_change(
    field = target$field,
    alias_field = paste0("trips_number_cf_", spec$suffix),
    mode = mode,
    activity_col = spec$trip_distance_col,
    target = target$value,
    ref_n = ref_n,
    cf_n_before = cf_n,
    cf_n_after = sum(updated_cf_active, na.rm = TRUE),
    delta = delta,
    role = assignment$role,
    donor_source = "reference_data$trips",
    census_id = .changed_trip_census_ids(assignment$changed_rows)
  )
  change$target_base_week_count <- target_base$count
  change$target_denominator <- target$denominator
  change$target_timeframe <- target$timeframe
  change$distribution_args <- args
  change$sampling_strategy <- assignment$sampling_strategy
  change$relevant_attributes <- assignment$relevant_attributes
  change$mode_shift_n <- assignment$mode_shift_n
  change$induced_n <- assignment$induced_n

  notes <- character(0)
  if ("weight_tripXhh" %in% names(reference_data$trips)) {
    notes <- c(
      notes,
      paste0(
        "Trip-count handler for mode `", mode,
        "` currently changes physical rows, not weighted `weight_tripXhh` totals."
      )
    )
  }
  if (length(args$advanced_fields_present) > 0) {
    notes <- c(
      notes,
      paste0(
        "Trip distribution fields parsed but not yet applied for mode `", mode,
        "`: ", paste(args$advanced_fields_present, collapse = ", ")
      )
    )
  }

  list(
    counterfactual_data = counterfactual_data,
    changes = list(change),
    notes = notes
  )
}

.assign_cf_trip_count_delta <- function(
    counterfactual_data,
    reference_data,
    spec,
    ref_active,
    cf_active,
    delta,
    seed,
    sampling_strategy,
    trip_target,
    constants,
    diversion_target
) {
  relevant_attributes <- cf_trip_sampling_columns(reference_data$trips, spec$mode)

  if (delta == 0) {
    return(list(
      counterfactual_data = counterfactual_data,
      changed_rows = data.frame(),
      role = "unchanged",
      sampling_strategy = sampling_strategy,
      relevant_attributes = relevant_attributes,
      mode_shift_n = 0L,
      induced_n = 0L
    ))
  }

  if (delta > 0) {
    mechanisms <- cf_trip_mechanism_counts(delta, constants$induced_trip_percent_default)
    shifted <- .shift_nonactive_trips_to_mode(
      counterfactual_data = counterfactual_data,
      reference_data = reference_data,
      spec = spec,
      n = mechanisms$mode_shift_n,
      trip_target = trip_target,
      constants = constants,
      seed = seed + spec$seed_offset + 3000L
    )
    counterfactual_data <- shifted$counterfactual_data
    induced_n <- mechanisms$induced_n + max(0L, mechanisms$mode_shift_n - shifted$changed_n)
    induced <- .add_induced_active_trips(
      counterfactual_data = counterfactual_data,
      reference_data = reference_data,
      spec = spec,
      n = induced_n,
      seed = seed + spec$seed_offset + 3500L
    )
    counterfactual_data <- induced$counterfactual_data
    changed_rows <- rbind(shifted$changed_rows, induced$changed_rows)
    role <- "mode_shift_and_induced_trips"
    mode_shift_n <- shifted$changed_n
    induced_n <- induced$changed_n
  } else {
    remove_rows <- cf_sample_candidate_indices(which(cf_active), abs(delta), seed + spec$seed_offset + 4000L)
    changed_rows <- counterfactual_data$trips[
      remove_rows,
      intersect(c("census_id", "nts_tripid"), names(counterfactual_data$trips)),
      drop = FALSE
    ]
    counterfactual_data$trips <- .switch_trips_away_from_active(
      counterfactual_data$trips,
      rows = remove_rows,
      spec = spec,
      constants = constants,
      diversion_target = diversion_target,
      seed = seed + spec$seed_offset + 4500L
    )
    role <- "shifted_away_trips"
    mode_shift_n <- -length(remove_rows)
    induced_n <- 0L
  }

  counterfactual_data <- cf_add_key_indicators(counterfactual_data, spec$mode)

  list(
    counterfactual_data = counterfactual_data,
    changed_rows = changed_rows,
    role = role,
    sampling_strategy = sampling_strategy,
    relevant_attributes = relevant_attributes,
    mode_shift_n = mode_shift_n,
    induced_n = induced_n
  )
}

.cf_trip_target <- function(values, suffix) {
  tab2_field <- paste0("trips_count_cf_", suffix)
  tab4_field <- paste0("trips_number_cf_", suffix)

  value <- .ui_value(values, tab2_field, NULL)
  field <- tab2_field
  timeframe <- .ui_value(values, paste0("trips_timeframe_", suffix), "year")
  denominator <- .ui_value(values, paste0("trips_denominator_", suffix), "total")

  if (is.null(value)) {
    value <- .ui_value(values, tab4_field, NULL)
    field <- tab4_field
    timeframe <- "week"
    denominator <- "total"
  }

  list(
    field = field,
    value = value,
    timeframe = timeframe,
    denominator = denominator
  )
}

.cf_trip_distribution_args <- function(values, suffix) {
  fields <- c(
    "pop_new_current_perc",
    "trips_dist_value",
    "trips_purpose_type",
    "trips_purpose_util_perc",
    "trips_spread_mean_cf",
    "trips_spread_util_prop_cf",
    "trips_diversion_car_perc",
    "trips_diversion_walk_perc",
    "trips_diversion_bike_perc",
    "trips_diversion_ebike_perc",
    "trips_diversion_pt_perc"
  )
  present <- fields[!vapply(lapply(fields, function(field) .ui_value(values, field, NULL)), is.null, logical(1))]

  list(
    new_user_percent = .ui_value(values, "pop_new_current_perc", NULL),
    trip_distance_default = .ui_value(values, "trips_dist_value", NULL),
    purpose_type = .ui_value(values, "trips_purpose_type", NULL),
    utilitarian_percent = .ui_value(values, "trips_purpose_util_perc", NULL),
    target_mean_distance = .ui_value(values, "trips_spread_mean_cf", NULL),
    target_utilitarian_prop = .ui_value(values, "trips_spread_util_prop_cf", NULL),
    diversion_car_percent = .ui_value(values, "trips_diversion_car_perc", NULL),
    advanced_fields_present = present
  )
}


### Distance ----


### Duration ----


### Mode share/shift/diversion ----

.apply_user_status_trip_effects <- function(
    counterfactual_data,
    reference_data,
    spec,
    changed_rows,
    role,
    constants,
    seed,
    trip_target,
    diversion_target
) {
  notes <- character(0)
  if (length(changed_rows) == 0 || is.null(counterfactual_data$trips) ||
      is.null(counterfactual_data$ind) || !"census_id" %in% names(counterfactual_data$ind) ||
      !"census_id" %in% names(counterfactual_data$trips) ||
      !"nts_tripid" %in% names(counterfactual_data$trips) ||
      !.trip_evidence_available_for_counterfactual(counterfactual_data$trips, spec)) {
    return(list(
      counterfactual_data = counterfactual_data,
      notes = notes,
      trip_shift_target_n = 0L,
      trip_shift_n = 0L
    ))
  }

  changed_ids <- counterfactual_data$ind$census_id[changed_rows]
  trip_shift_target_n <- 0L
  trip_shift_n <- 0L
  if (identical(role, "ex_users")) {
    active <- spec$trip_filter(counterfactual_data$trips)
    trip_rows <- which(counterfactual_data$trips$census_id %in% changed_ids & active)
    counterfactual_data$trips <- .switch_trips_away_from_active(
      counterfactual_data$trips,
      rows = trip_rows,
      spec = spec,
      constants = constants,
      diversion_target = diversion_target,
      seed = seed + spec$seed_offset + 2400L
    )
    return(list(
      counterfactual_data = counterfactual_data,
      notes = notes,
      trip_shift_target_n = length(trip_rows),
      trip_shift_n = length(trip_rows)
    ))
  }

  if (identical(role, "new_users")) {
    trip_shift_target_n <- .new_user_trip_shift_count(
      reference_data = reference_data,
      spec = spec,
      new_user_n = length(changed_ids),
      seed = seed + spec$seed_offset + 2300L
    )
    shifted <- .shift_nonactive_trips_to_mode(
      counterfactual_data = counterfactual_data,
      reference_data = reference_data,
      spec = spec,
      n = trip_shift_target_n,
      trip_target = trip_target,
      constants = constants,
      seed = seed + spec$seed_offset + 2500L,
      census_ids = changed_ids
    )
    counterfactual_data <- shifted$counterfactual_data
    trip_shift_n <- shifted$changed_n
    if (shifted$changed_n < trip_shift_target_n) {
      notes <- c(
        notes,
        paste0(
          "Only ", shifted$changed_n, " plausible non-active trips were shifted for a target of ",
          trip_shift_target_n, " trips among ", length(changed_ids), " new `", spec$mode, "` users."
        )
      )
    }
  }

  list(
    counterfactual_data = counterfactual_data,
    notes = notes,
    trip_shift_target_n = trip_shift_target_n,
    trip_shift_n = trip_shift_n
  )
}

.shift_nonactive_trips_to_mode <- function(
    counterfactual_data,
    reference_data,
    spec,
    n,
    trip_target,
    constants,
    seed,
    census_ids = NULL
) {
  if (n == 0 || is.null(counterfactual_data$trips)) {
    return(list(counterfactual_data = counterfactual_data, changed_rows = .empty_changed_trip_rows(), changed_n = 0L))
  }

  trips <- counterfactual_data$trips
  active <- spec$trip_filter(trips)
  candidates <- which(!active & !is.na(trips$nts_tripid))
  if (!is.null(census_ids) && "census_id" %in% names(trips)) {
    candidates <- candidates[trips$census_id[candidates] %in% census_ids]
  }
  if ("trip_utilitarian" %in% names(trips)) {
    candidates <- candidates[.true_values(trips$trip_utilitarian[candidates])]
  }

  active_distances <- .active_trip_distances(reference_data$trips, spec)
  candidates <- cf_plausible_distance_candidates(
    trips,
    candidates,
    active_distances,
    max_multiplier = constants$plausible_distance_max_multiplier
  )
  if (length(candidates) == 0) {
    return(list(counterfactual_data = counterfactual_data, changed_rows = .empty_changed_trip_rows(), changed_n = 0L))
  }

  shift_n <- min(n, length(candidates))
  weights <- cf_trip_candidate_weights(trips, candidates, active_distances, trip_target)
  rows <- cf_sample_candidate_indices(candidates, shift_n, seed, weights = weights)

  trips <- .switch_trips_to_active_mode(trips, rows, spec)
  trips$cf_trip_change[rows] <- "mode_shift_to_active"
  trips$cf_mode_shift[rows] <- TRUE
  counterfactual_data$trips <- trips

  changed_rows <- trips[rows, intersect(c("census_id", "nts_tripid"), names(trips)), drop = FALSE]
  list(counterfactual_data = counterfactual_data, changed_rows = changed_rows, changed_n = length(rows))
}

.add_induced_active_trips <- function(counterfactual_data, reference_data, spec, n, seed) {
  if (n == 0 || is.null(reference_data$trips)) {
    return(list(counterfactual_data = counterfactual_data, changed_rows = .empty_changed_trip_rows(), changed_n = 0L))
  }

  ref_active <- spec$trip_filter(reference_data$trips) & !is.na(reference_data$trips$nts_tripid)
  donor_rows <- which(ref_active)
  if (length(donor_rows) == 0) {
    return(list(counterfactual_data = counterfactual_data, changed_rows = .empty_changed_trip_rows(), changed_n = 0L))
  }

  donor_rows <- cf_sample_candidate_indices(donor_rows, n, seed, replace = TRUE)
  new_rows <- reference_data$trips[donor_rows, , drop = FALSE]
  new_rows <- .assign_new_trip_ids(counterfactual_data$trips, new_rows)
  new_rows <- .switch_trips_to_active_mode(new_rows, seq_len(nrow(new_rows)), spec)
  if ("weight_tripXhh" %in% names(new_rows)) {
    new_rows$weight_tripXhh <- 1
  }
  if ("trip_purpose" %in% names(new_rows)) {
    new_rows$trip_purpose <- "Recreational"
  }
  new_rows$trip_utilitarian <- FALSE
  new_rows$cf_trip_change <- "induced_recreational_active"
  new_rows$cf_mode_shift <- FALSE
  new_rows$cf_induced <- TRUE

  counterfactual_data$trips <- rbind(counterfactual_data$trips, new_rows)
  changed_rows <- new_rows[, intersect(c("census_id", "nts_tripid"), names(new_rows)), drop = FALSE]
  list(counterfactual_data = counterfactual_data, changed_rows = changed_rows, changed_n = nrow(new_rows))
}

.switch_trips_to_active_mode <- function(trips, rows, spec) {
  if (length(rows) == 0) {
    return(trips)
  }
  if ("trip_mainmode" %in% names(trips)) {
    trips$trip_mainmode[rows] <- spec$trip_mainmode_value
  }
  if (!is.na(spec$trip_distance_col) && spec$trip_distance_col %in% names(trips) &&
      "trip_distraw_km" %in% names(trips)) {
    trips[[spec$trip_distance_col]][rows] <- trips$trip_distraw_km[rows]
  }
  if (!is.na(spec$trip_duration_col) && spec$trip_duration_col %in% names(trips) &&
      "trip_durationraw_min" %in% names(trips)) {
    trips[[spec$trip_duration_col]][rows] <- trips$trip_durationraw_min[rows]
  }

  for (col in setdiff(
    c("trip_walkdist_km", "trip_walktime_min", "trip_cycledist_km", "trip_cycletime_min"),
    c(spec$trip_distance_col, spec$trip_duration_col)
  )) {
    if (col %in% names(trips)) {
      trips[[col]][rows] <- 0
    }
  }

  trips
}

.switch_trips_away_from_active <- function(trips, rows, spec, constants, diversion_target, seed) {
  if (length(rows) == 0) {
    return(trips)
  }
  if ("trip_mainmode" %in% names(trips)) {
    trips$trip_mainmode[rows] <- .sample_diversion_modes(diversion_target, length(rows), seed)
  }
  for (col in c(spec$trip_distance_col, spec$trip_duration_col)) {
    if (!is.na(col) && col %in% names(trips)) {
      trips[[col]][rows] <- 0
    }
  }
  trips$cf_trip_change[rows] <- "mode_shift_away_from_active"
  trips$cf_mode_shift[rows] <- TRUE
  trips
}

.new_user_trip_shift_count <- function(reference_data, spec, new_user_n, seed) {
  if (new_user_n == 0 || is.null(reference_data$ind) || is.null(reference_data$trips) ||
      !"census_id" %in% names(reference_data$ind) ||
      !"census_id" %in% names(reference_data$trips) ||
      !"nts_tripid" %in% names(reference_data$trips) ||
      !spec$activity_col %in% names(reference_data$ind) ||
      !.trip_evidence_available_for_counterfactual(reference_data$trips, spec)) {
    return(new_user_n)
  }

  current_users <- .positive_col(reference_data$ind, spec$activity_col)
  current_user_ids <- reference_data$ind$census_id[current_users]
  if (length(current_user_ids) == 0) {
    return(new_user_n)
  }

  active_trips <- spec$trip_filter(reference_data$trips) & !is.na(reference_data$trips$nts_tripid)
  trip_counts <- table(reference_data$trips$census_id[active_trips])
  observed_counts <- as.integer(trip_counts[as.character(current_user_ids)])
  observed_counts[is.na(observed_counts)] <- 0L

  if (length(observed_counts) == 0 || all(observed_counts == 0)) {
    return(new_user_n)
  }

  set.seed(seed)
  sampled_pos <- sample(seq_along(observed_counts), size = new_user_n, replace = TRUE)
  sum(observed_counts[sampled_pos])
}

.cf_diversion_target <- function(values, constants) {
  mode_fields <- c(
    car = "trips_diversion_car_perc",
    walk = "trips_diversion_walk_perc",
    bike = "trips_diversion_bike_perc",
    ebike = "trips_diversion_ebike_perc",
    pt = "trips_diversion_pt_perc"
  )

  raw <- vapply(mode_fields, function(field) {
    value <- .ui_value(values, field, NA_real_)
    if (length(value) != 1 || is.null(value)) {
      return(NA_real_)
    }
    as.numeric(value)
  }, numeric(1))
  raw <- raw[!is.na(raw) & raw > 0]

  if (length(raw) == 0) {
    return(list(
      modes = constants$default_diversion_mode,
      probs = 1,
      source = "default"
    ))
  }

  probs <- raw / sum(raw)
  list(
    modes = names(probs),
    probs = as.numeric(probs),
    source = "ui"
  )
}

.sample_diversion_modes <- function(diversion_target, n, seed) {
  if (n == 0) {
    return(character(0))
  }

  set.seed(seed)
  sample(diversion_target$modes, size = n, replace = TRUE, prob = diversion_target$probs)
}

.active_trip_distances <- function(trips, spec) {
  if (is.null(trips)) {
    return(numeric(0))
  }
  active <- spec$trip_filter(trips)
  if ("trip_distraw_km" %in% names(trips)) {
    return(trips$trip_distraw_km[active])
  }
  if (!is.na(spec$trip_distance_col) && spec$trip_distance_col %in% names(trips)) {
    return(trips[[spec$trip_distance_col]][active])
  }

  numeric(0)
}

.empty_changed_trip_rows <- function() {
  data.frame(census_id = integer(0), nts_tripid = integer(0))
}

.true_values <- function(x) {
  !is.na(x) & x
}

# 5. Shared Data-Manipulation Helpers ----

.recalculate_counterfactual_mmets <- function(counterfactual_data, constants) {
  if (is.null(counterfactual_data$ind) || !"mmets" %in% names(counterfactual_data$ind)) {
    return(counterfactual_data)
  }

  ind <- counterfactual_data$ind
  walk <- if ("walktime_wkhr" %in% names(ind)) ind$walktime_wkhr else 0
  cycle <- if ("cycletime_wkhr" %in% names(ind)) ind$cycletime_wkhr else 0
  sport <- if ("sport_wkhr" %in% names(ind)) ind$sport_wkhr else 0
  sport[is.na(sport) | sport < 0] <- 0

  counterfactual_data$ind$mmets <-
    walk * constants$mmet_walking +
    cycle * constants$mmet_cycling +
    sport * constants$mmet_vigorous

  counterfactual_data
}

.mirror_ind_activity_to_trips <- function(counterfactual_data, activity_col) {
  if (is.null(counterfactual_data$trips) ||
      is.null(counterfactual_data$ind) ||
      !"census_id" %in% names(counterfactual_data$trips) ||
      !"census_id" %in% names(counterfactual_data$ind) ||
      !activity_col %in% names(counterfactual_data$trips) ||
      !activity_col %in% names(counterfactual_data$ind)) {
    return(counterfactual_data)
  }

  lookup <- as.data.frame(counterfactual_data$ind)[, c("census_id", activity_col), drop = FALSE]
  matched <- match(counterfactual_data$trips$census_id, lookup$census_id)
  counterfactual_data$trips[[activity_col]] <- lookup[[activity_col]][matched]

  counterfactual_data
}

.assign_new_trip_ids <- function(existing_trips, new_rows) {
  if (!"nts_tripid" %in% names(new_rows)) {
    return(new_rows)
  }

  existing_ids <- existing_trips$nts_tripid
  if (is.numeric(existing_ids)) {
    max_id <- suppressWarnings(max(existing_ids, na.rm = TRUE))
    if (!is.finite(max_id)) {
      max_id <- 0
    }
    new_rows$nts_tripid <- seq.int(max_id + 1, max_id + nrow(new_rows))
    return(new_rows)
  }

  new_rows$nts_tripid <- paste0("cf_trip_", seq_len(nrow(new_rows)))
  new_rows
}


# 6. Validation Helpers ----

.require_cf_user_count_columns <- function(counterfactual_data, reference_data, spec) {
  if (is.null(counterfactual_data$ind) || is.null(reference_data$ind)) {
    stop("Counterfactual user-count changes require `ind` data.", call. = FALSE)
  }
  if (!spec$activity_col %in% names(counterfactual_data$ind) ||
      !spec$activity_col %in% names(reference_data$ind)) {
    stop("Activity column not found for mode `", spec$mode, "`: ", spec$activity_col, call. = FALSE)
  }

  invisible(TRUE)
}

.require_cf_trip_count_columns <- function(counterfactual_data, reference_data, spec) {
  if (is.null(counterfactual_data$trips) || is.null(reference_data$trips)) {
    stop("Counterfactual trip-count changes require `trips` data.", call. = FALSE)
  }
  if (!"nts_tripid" %in% names(counterfactual_data$trips) ||
      !"nts_tripid" %in% names(reference_data$trips)) {
    stop("Counterfactual trip-count changes require `nts_tripid` in trip data.", call. = FALSE)
  }
  if (!.trip_evidence_available_for_counterfactual(reference_data$trips, spec)) {
    stop("Trip evidence columns not found for mode `", spec$mode, "`.", call. = FALSE)
  }

  invisible(TRUE)
}

.validate_cf_user_target <- function(target, pop_total_ref, spec) {
  if (!is.numeric(target) || length(target) != 1 || !is.finite(target)) {
    stop("Counterfactual target for mode `", spec$mode, "` must be one finite number.", call. = FALSE)
  }

  target <- as.integer(round(target))
  if (target < 0) {
    stop("Counterfactual target for mode `", spec$mode, "` cannot be negative.", call. = FALSE)
  }
  if (target > pop_total_ref) {
    stop(
      "Counterfactual target for mode `", spec$mode,
      "` cannot exceed filtered reference population size (", pop_total_ref, ").",
      call. = FALSE
    )
  }

  target
}

.validate_cf_trip_target <- function(target, reference_data, spec) {
  if (!is.numeric(target$value) || length(target$value) != 1 || !is.finite(target$value)) {
    stop("Counterfactual trip target for mode `", spec$mode, "` must be one finite number.", call. = FALSE)
  }
  if (target$value < 0) {
    stop("Counterfactual trip target for mode `", spec$mode, "` cannot be negative.", call. = FALSE)
  }
  if (!target$denominator %in% c("total", "mean")) {
    stop("Unsupported trip denominator for mode `", spec$mode, "`: ", target$denominator, call. = FALSE)
  }

  count <- target$value
  if (identical(target$denominator, "mean")) {
    pop_total_ref <- if (!is.null(reference_data$ind)) nrow(reference_data$ind) else NA_integer_
    if (is.na(pop_total_ref)) {
      stop("Mean-per-person trip targets require `ind` data for population size.", call. = FALSE)
    }
    count <- count * pop_total_ref
  }

  count <- count / .counterfactual_timeframe_factor(target$timeframe)
  count <- as.integer(round(count))

  list(count = count)
}

.counterfactual_timeframe_factor <- function(timeframe) {
  switch(
    timeframe,
    day = 1 / 7,
    week = 1,
    year = 52.1775,
    1
  )
}


# 7. Constants And Mode Specs ----

miama_counterfactual_defaults <- function() {
  list(
    mmet_walking = 2.5,
    mmet_cycling = 5.8,
    mmet_vigorous = 7,
    walktime_wkhr_default = 1,
    cycletime_wkhr_default = 1,
    walktime_wkhr_ex_user_default = 0,
    cycletime_wkhr_ex_user_default = 0,
    induced_trip_percent_default = 10,
    default_diversion_mode = "car",
    plausible_distance_max_multiplier = 1.2,
    unsupported_mode_policy = "skip"
  )
}

.counterfactual_mode_spec <- function(mode) {
  base <- .miama_tab2_mode_specs()[[mode]]
  if (is.null(base)) {
    return(NULL)
  }

  activity_col <- switch(
    mode,
    walking = "walktime_wkhr",
    cycling = "cycletime_wkhr",
    NA_character_
  )
  default_col <- switch(
    mode,
    walking = "walktime_wkhr_default",
    cycling = "cycletime_wkhr_default",
    NA_character_
  )
  ex_user_default_col <- switch(
    mode,
    walking = "walktime_wkhr_ex_user_default",
    cycling = "cycletime_wkhr_ex_user_default",
    NA_character_
  )
  trip_mainmode_value <- switch(
    mode,
    walking = "walking",
    cycling = "cycling",
    ebiking = "ebiking",
    pt = "pt",
    mode
  )
  seed_offset <- switch(
    mode,
    walking = 101L,
    cycling = 202L,
    ebiking = 303L,
    pt = 404L,
    999L
  )

  utils::modifyList(base, list(
    mode = mode,
    activity_col = activity_col,
    default_col = default_col,
    ex_user_default_col = ex_user_default_col,
    trip_mainmode_value = trip_mainmode_value,
    seed_offset = seed_offset
  ))
}

.trip_evidence_available_for_counterfactual <- function(trips, spec) {
  if (is.null(trips) || is.null(spec)) {
    return(FALSE)
  }
  if (isTRUE(spec$needs_trip_mainmode) && !"trip_mainmode" %in% names(trips)) {
    return(FALSE)
  }

  any(c(spec$trip_distance_col, spec$trip_duration_col) %in% names(trips))
}


# 8. Report Helpers ----

.counterfactual_report_init <- function(counterfactual_data) {
  report <- counterfactual_data$counterfactual_report
  if (is.null(report)) {
    report <- list(changes = list(), notes = character(0))
  }

  report
}

.counterfactual_report_finalize <- function(report, counterfactual_data, reference_data) {
  report$notes <- unique(report$notes[nzchar(report$notes)])
  report$n_ind <- if (!is.null(counterfactual_data$ind)) nrow(counterfactual_data$ind) else NA_integer_
  report$n_trips <- if (!is.null(counterfactual_data$trips)) nrow(counterfactual_data$trips) else NA_integer_
  report$comparison <- .counterfactual_comparison_report(reference_data, counterfactual_data)
  report
}

.counterfactual_comparison_report <- function(reference_data, counterfactual_data) {
  list(
    ind = .counterfactual_ind_comparison(reference_data$ind, counterfactual_data$ind),
    trips = .counterfactual_trip_comparison(reference_data$trips, counterfactual_data$trips),
    changed_ind_rows = .counterfactual_changed_ind_rows(reference_data$ind, counterfactual_data$ind),
    changed_trip_rows = .counterfactual_changed_trip_rows(reference_data$trips, counterfactual_data$trips)
  )
}

.counterfactual_ind_comparison <- function(reference_ind, counterfactual_ind) {
  cols <- .present_cols(
    c("walktime_wkhr", "cycletime_wkhr", "sport_wkhr", "mmets", "user_walk", "user_bike"),
    reference_ind,
    counterfactual_ind
  )

  summary <- .numeric_comparison_rows(
    reference_data = reference_ind,
    counterfactual_data = counterfactual_ind,
    columns = cols,
    level = "ind"
  )

  if (is.null(reference_ind) || is.null(counterfactual_ind)) {
    return(summary)
  }

  active_rows <- lapply(cols, function(col) {
    ref_active <- .positive_col(reference_ind, col)
    cf_active <- .positive_col(counterfactual_ind, col)
    data.frame(
      level = "ind",
      metric = paste0(col, "_active_rows"),
      ref = sum(ref_active, na.rm = TRUE),
      cf = sum(cf_active, na.rm = TRUE),
      delta = sum(cf_active, na.rm = TRUE) - sum(ref_active, na.rm = TRUE),
      row.names = NULL
    )
  })

  rbind(summary, do.call(rbind, active_rows))
}

.counterfactual_trip_comparison <- function(reference_trips, counterfactual_trips) {
  cols <- .present_cols(
    c(
      "walktime_wkhr", "cycletime_wkhr",
      "trip_walktime_min", "trip_walkdist_km",
      "trip_cycletime_min", "trip_cycledist_km",
      "trip_durationraw_min", "trip_distraw_km"
    ),
    reference_trips,
    counterfactual_trips
  )

  summary <- .numeric_comparison_rows(
    reference_data = reference_trips,
    counterfactual_data = counterfactual_trips,
    columns = cols,
    level = "trips"
  )

  if (is.null(reference_trips) || is.null(counterfactual_trips)) {
    return(summary)
  }

  row_count <- data.frame(
    level = "trips",
    metric = "n_rows",
    ref = nrow(reference_trips),
    cf = nrow(counterfactual_trips),
    delta = nrow(counterfactual_trips) - nrow(reference_trips),
    row.names = NULL
  )

  rbind(row_count, summary)
}

.numeric_comparison_rows <- function(reference_data, counterfactual_data, columns, level) {
  if (is.null(reference_data) || is.null(counterfactual_data) || length(columns) == 0) {
    return(data.frame(
      level = character(0),
      metric = character(0),
      ref = numeric(0),
      cf = numeric(0),
      delta = numeric(0)
    ))
  }

  rows <- lapply(columns, function(col) {
    ref_values <- reference_data[[col]]
    cf_values <- counterfactual_data[[col]]

    data.frame(
      level = level,
      metric = c(
        paste0(col, "_sum"),
        paste0(col, "_mean")
      ),
      ref = c(
        sum(ref_values, na.rm = TRUE),
        mean(ref_values, na.rm = TRUE)
      ),
      cf = c(
        sum(cf_values, na.rm = TRUE),
        mean(cf_values, na.rm = TRUE)
      ),
      row.names = NULL
    )
  })

  out <- do.call(rbind, rows)
  out$delta <- out$cf - out$ref
  out
}

.counterfactual_changed_ind_rows <- function(reference_ind, counterfactual_ind) {
  cols <- .present_cols(
    c("walktime_wkhr", "cycletime_wkhr", "sport_wkhr", "mmets"),
    reference_ind,
    counterfactual_ind
  )

  if (is.null(reference_ind) || is.null(counterfactual_ind) ||
      !"census_id" %in% names(reference_ind) || !"census_id" %in% names(counterfactual_ind) ||
      length(cols) == 0) {
    return(data.frame())
  }

  changed <- Reduce(`|`, lapply(cols, function(col) {
    !.same_or_both_na(reference_ind[[col]], counterfactual_ind[[col]])
  }))

  if (!any(changed, na.rm = TRUE)) {
    return(data.frame())
  }

  out <- data.frame(
    census_id = reference_ind$census_id[changed],
    row.names = NULL
  )

  for (col in cols) {
    out[[paste0(col, "_ref")]] <- reference_ind[[col]][changed]
    out[[paste0(col, "_cf")]] <- counterfactual_ind[[col]][changed]
    if (is.numeric(out[[paste0(col, "_cf")]]) || is.logical(out[[paste0(col, "_cf")]])) {
      out[[paste0(col, "_delta")]] <- out[[paste0(col, "_cf")]] - out[[paste0(col, "_ref")]]
    }
  }
  if ("cf_user_change" %in% names(counterfactual_ind)) {
    out$cf_user_change <- counterfactual_ind$cf_user_change[changed]
  }

  out
}

.counterfactual_changed_trip_rows <- function(reference_trips, counterfactual_trips) {
  if (is.null(counterfactual_trips) || !"nts_tripid" %in% names(counterfactual_trips)) {
    return(data.frame())
  }

  if ("cf_trip_change" %in% names(counterfactual_trips)) {
    changed <- counterfactual_trips$cf_trip_change != "unchanged" |
      ("cf_induced" %in% names(counterfactual_trips) & counterfactual_trips$cf_induced)
  } else {
    changed <- rep(FALSE, nrow(counterfactual_trips))
  }

  if (!any(changed, na.rm = TRUE)) {
    return(data.frame())
  }

  cols <- intersect(
    c(
      "census_id", "nts_tripid", "trip_mainmode", "trip_distraw_km",
      "trip_durationraw_min", "trip_walkdist_km", "trip_walktime_min",
      "trip_cycledist_km", "trip_cycletime_min", "trip_purpose",
      "trip_activemode", "trip_utilitarian", "cf_trip_change",
      "cf_mode_shift", "cf_induced"
    ),
    names(counterfactual_trips)
  )

  as.data.frame(counterfactual_trips)[changed, cols, drop = FALSE]
}

.present_cols <- function(cols, reference_data, counterfactual_data) {
  if (is.null(reference_data) || is.null(counterfactual_data)) {
    return(character(0))
  }

  cols[cols %in% names(reference_data) & cols %in% names(counterfactual_data)]
}

.same_or_both_na <- function(x, y) {
  (is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y)
}

.counterfactual_no_change <- function(counterfactual_data, notes = character(0)) {
  list(
    counterfactual_data = counterfactual_data,
    changes = list(),
    notes = notes
  )
}

.compact_counterfactual_change <- function(
    field,
    alias_field,
    mode,
    activity_col,
    target,
    ref_n,
    cf_n_before,
    cf_n_after,
    delta,
    role,
    donor_source,
    census_id
) {
  list(
    field = field,
    alias_field = alias_field,
    mode = mode,
    activity_col = activity_col,
    target = target,
    ref_n = ref_n,
    cf_n_before = cf_n_before,
    cf_n_after = cf_n_after,
    delta = delta,
    role = role,
    donor_source = donor_source,
    changed_n = length(census_id),
    census_id = census_id
  )
}

.changed_census_ids <- function(ind, rows) {
  if (length(rows) == 0 || !"census_id" %in% names(ind)) {
    return(integer(0))
  }

  ind$census_id[rows]
}

.changed_trip_census_ids <- function(changed_rows) {
  if (is.null(changed_rows) || nrow(changed_rows) == 0 || !"census_id" %in% names(changed_rows)) {
    return(integer(0))
  }

  changed_rows$census_id
}

# Legacy Compatibility -------------------------------------------------------
# These split-step hooks are retained as no-ops so older workflow snippets and
# tests fail softly while the current implementation runs through
# `apply_counterfactual_ui_values()`.

apply_ind_rows_changes <- function(counterfactual_data, ...) {
  counterfactual_data
}

apply_ind_attribute_changes <- function(counterfactual_data, ...) {
  counterfactual_data
}

apply_trip_rows_changes <- function(counterfactual_data, ...) {
  counterfactual_data
}

apply_trip_attribute_changes <- function(counterfactual_data, ...) {
  counterfactual_data
}
