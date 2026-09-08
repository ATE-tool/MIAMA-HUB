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
# `users_count_cf_*` and the UI-version-specific `pop_number_cf_*_(basic|advanced)`
# fields because both mean "set the counterfactual number of active mode users".
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
# - The full geography is the source from which the assessed REF person scope is
#   sampled. CF starts with that boundary, but may recruit baseline non-users
#   from the retained geography when its user target exceeds the REF scope.
# - Individual source rows stay fixed. Recruitment expands `cf_in_scope`; it
#   does not duplicate people or alter the reference snapshot.
# - Key indicators (`user_walk`, `user_bike`, `user_ebike`, `user_pt`,
#   `trip_activemode`, `trip_utilitarian`, and CF change flags) are added to the
#   returned data.
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
#   rounding. Increases are limited by eligible baseline non-users in the full
#   filtered geography, not by the smaller assessed REF person scope.
# - E-bike reference volume is zero because source bicycle records are retained
#   as conventional cycling. Cycling supplies donor patterns for e-bike CF
#   changes. PT contributes physical activity only through access walking.
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
  appraisal_input_values <- .assumption_values(appraisal_input_values)
  constants <- .assumption_cf_constants(appraisal_input_values, constants)
  context <- .counterfactual_context(
    counterfactual_data = counterfactual_data,
    appraisal_input_values = appraisal_input_values,
    reference_data = reference_data,
    constants = constants,
    seed = seed
  )

  counterfactual_data <- context$counterfactual_data
  report <- .counterfactual_report_init(counterfactual_data)
  report$tab2_input_conversion <- context$tab2_input_conversion

  for (handler in .counterfactual_ui_handler_registry()) {
    result <- handler(counterfactual_data, context)
    counterfactual_data <- result$counterfactual_data
    report$changes <- c(report$changes, result$changes)
    report$notes <- c(report$notes, result$notes)
  }

  # Recalculate once after every individual and trip handler has run. User-count
  # changes use individual weekly activity; independent trip targets contribute
  # their active minutes. Trip changes made only to mirror user status are
  # excluded from the trip component to avoid counting the same exposure twice.
  counterfactual_data <- .recalculate_counterfactual_mmets(
    counterfactual_data,
    context$reference_data,
    context$constants
  )

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

  tab2_conversion <- .derive_tab2_trip_count_targets(
    appraisal_input_values,
    reference_data = reference_data,
    scenario = "cf",
    modes = modes
  )
  appraisal_input_values <- tab2_conversion$values

  counterfactual_data <- cf_add_key_indicators(.prepare_mode_features(counterfactual_data), modes)
  reference_data <- cf_add_key_indicators(.prepare_mode_features(reference_data), modes)

  list(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    values = appraisal_input_values,
    constants = constants,
    seed = seed,
    modes = modes,
    tab2_input_conversion = tab2_conversion$report,
    user_sampling_strategy = cf_sampling_strategy_from_ui(appraisal_input_values, scope = "user"),
    trip_sampling_strategy = cf_sampling_strategy_from_ui(appraisal_input_values, scope = "trip")
  )
}


# 3. UI Field Handlers ----

# Handler: active-mode user count targets ----
# UI fields:
# - `users_count_cf_[walk|bike|ebike|pt]`
# - basic UI: `pop_number_cf_[walk|bike|ebike|pt]_basic`
# - advanced UI: `pop_number_cf_[walk|bike|ebike|pt]_advanced`
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
# - `trips_count_cf_[walk|bike|ebike|pt]`
# - `trips_number_cf_[walk|bike|ebike|pt]`
#
# Related refinement fields used by sampling or recorded in report metadata:
# - `trips_timeframe_*`, `trips_denominator_*`
# - `pop_new_current_perc`
# - `trips_dist_value`, `trips_purpose_type`, `trips_purpose_util_perc`
# - `trips_spread_mean_cf`, `trips_spread_util_prop_cf`
# - `trips_diversion_sources_[walk|bike|ebike|pt]`
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
# - Counts follow the one-row/one-record contract; survey weights do not alter
#   UI targets or the number of rows sampled.
# - Some advanced controls still remain report-only; spread bars and the
#   target-specific source-mode distribution are used as sampling constraints.
.apply_cf_active_trip_count_handler <- function(counterfactual_data, context) {
  changes <- list()
  notes <- character(0)

  # Allocate modes that may draw from another active mode first. Explicit
  # targets for donor modes are then reconciled against that changed snapshot,
  # so a later e-bike diversion cannot leave cycling below its requested total.
  cross_mode_first <- vapply(context$modes, function(mode) {
    !is.null(context$constants$source_mode_shares[[mode]])
  }, logical(1))
  processing_modes <- context$modes[order(!cross_mode_first)]

  for (mode in processing_modes) {
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

  target_spec <- .cf_user_target(appraisal_input_values, spec$suffix)
  target <- target_spec$value
  if (is.null(target)) {
    return(.counterfactual_no_change(counterfactual_data))
  }

  .require_cf_user_count_columns(counterfactual_data, reference_data, spec)

  target <- .validate_cf_user_target(target, spec)
  new_user_preference <- .cf_new_user_target(appraisal_input_values, constants)

  ref_scope_col <- .reference_user_scope_col(mode, "ref")
  cf_scope_col <- .reference_user_scope_col(mode, "cf")
  ref_scope <- if (ref_scope_col %in% names(reference_data$ind)) {
    .true_values(reference_data$ind[[ref_scope_col]])
  } else {
    rep(TRUE, nrow(reference_data$ind))
  }
  cf_scope <- if (cf_scope_col %in% names(counterfactual_data$ind)) {
    .true_values(counterfactual_data$ind[[cf_scope_col]])
  } else {
    rep(TRUE, nrow(counterfactual_data$ind))
  }
  ref_users <- .positive_col(reference_data$ind, spec$activity_col) & ref_scope
  cf_users <- .positive_col(counterfactual_data$ind, spec$activity_col) & cf_scope
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
    population_target = cf_population_sampling_target(
      appraisal_input_values,
      spec$suffix,
      spread = constants$spread,
      population_refinement = constants$population_refinement
    )
  )

  counterfactual_data <- assignment$counterfactual_data
  source_diversion_target <- .cf_source_diversion_target(
    appraisal_input_values,
    spec$suffix,
    mode = spec$mode,
    constants = constants,
    trips = reference_data$trips
  )
  trip_rate <- .cf_positive_mode_assumption(
    appraisal_input_values,
    "default_trips_per_user_per_week",
    spec$suffix
  )
  explicit_trip_target <- .cf_trip_target(appraisal_input_values, spec$suffix)
  explicit_trip_count <- if (is.null(explicit_trip_target$value)) {
    NULL
  } else {
    .validate_cf_trip_target(explicit_trip_target, reference_data, spec)$count
  }
  trip_effect <- .apply_user_status_trip_effects(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    spec = spec,
    changed_rows = assignment$changed_rows,
    role = assignment$role,
    constants = constants,
    seed = seed,
    trip_target = cf_trip_sampling_target(
      appraisal_input_values,
      spec$suffix,
      spread = constants$spread
    ),
    source_diversion_target = source_diversion_target,
    diversion_target = .cf_away_diversion_target(constants),
    trips_per_user_per_week = trip_rate$value,
    explicit_trip_count = explicit_trip_count
  )
  counterfactual_data <- trip_effect$counterfactual_data
  counterfactual_data <- cf_add_key_indicators(counterfactual_data, spec$mode)

  updated_scope <- if (cf_scope_col %in% names(counterfactual_data$ind)) {
    .true_values(counterfactual_data$ind[[cf_scope_col]])
  } else {
    rep(TRUE, nrow(counterfactual_data$ind))
  }
  updated_cf_users <- .positive_col(counterfactual_data$ind, spec$activity_col) & updated_scope
  updated_cf_n <- sum(updated_cf_users, na.rm = TRUE)
  retained_current_n <- min(cf_n, updated_cf_n)
  recruited_new_n <- max(updated_cf_n - cf_n, 0L)
  realized_new_percent <- if (updated_cf_n > 0) {
    100 * recruited_new_n / updated_cf_n
  } else {
    0
  }
  change <- .compact_counterfactual_change(
    field = target_spec$field,
    alias_field = target_spec$alias_field,
    mode = mode,
    activity_col = spec$activity_col,
    target = target,
    ref_n = ref_n,
    cf_n_before = cf_n,
    cf_n_after = updated_cf_n,
    delta = delta,
    role = assignment$role,
    donor_source = assignment$donor_source,
    census_id = .changed_census_ids(counterfactual_data$ind, assignment$changed_rows)
  )
  change$sampling_strategy <- assignment$sampling_strategy
  change$relevant_attributes <- assignment$relevant_attributes
  change$sampling_constraints <- assignment$sampling_constraints
  change$sampling_fallback <- assignment$sampling_fallback
  change$cf_scope_added_n <- assignment$cf_scope_added_n
  change$user_trip_shift_target_n <- trip_effect$trip_shift_target_n
  change$user_trip_shift_n <- trip_effect$trip_shift_n
  change$trip_sampling_fallback <- trip_effect$sampling_fallback
  change$diversion_source_field <- source_diversion_target$field
  change$source_mode_shares <- source_diversion_target$shares
  change$source_mode_shares_source <- source_diversion_target$source
  change$realized_source_mode_shares <- trip_effect$realized_source_mode_shares
  change$trips_per_user_per_week <- trip_rate$value
  change$trips_per_user_per_week_field <- trip_rate$field
  change$explicit_trip_count <- explicit_trip_count
  change$current_new_user_split <- list(
    retained_current_users = retained_current_n,
    recruited_new_users = recruited_new_n,
    realized_current_user_percent = 100 - realized_new_percent,
    realized_new_user_percent = realized_new_percent,
    preferred_new_user_percent = new_user_preference$percent,
    preferred_new_user_percent_field = new_user_preference$field,
    preferred_new_user_percent_source = new_user_preference$source
  )

  notes <- trip_effect$notes
  if (delta > 0 &&
      realized_new_percent > new_user_preference$percent + sqrt(.Machine$double.eps)) {
    notes <- c(notes, paste0(
      "The explicit counterfactual ", mode, " user target requires ",
      round(realized_new_percent, 1), "% of counterfactual ", mode,
      " users to be recruited baseline non-users, above the preferred ",
      round(new_user_preference$percent, 1), "%. The explicit user count took precedence."
    ))
  }

  list(
    counterfactual_data = counterfactual_data,
    changes = list(change),
    notes = notes
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
      sampling_constraints = population_target$constraints %||% character(0),
      sampling_fallback = NULL,
      cf_scope_added_n = 0L,
      relevant_attributes = cf_individual_sampling_columns(reference_data$ind, spec$mode)
    ))
  }

  if (delta > 0) {
    # Prefer non-users already inside the assessed CF population. If that pool
    # is too small, recruit additional baseline non-users from the retained
    # geographic source population and add them to `cf_in_scope`.
    cf_person_scope <- if ("cf_in_scope" %in% names(counterfactual_data$ind)) {
      .true_values(counterfactual_data$ind$cf_in_scope)
    } else {
      rep(TRUE, nrow(counterfactual_data$ind))
    }
    source_non_users <- !.positive_col(reference_data$ind, spec$activity_col)
    candidate_rows <- which(!cf_users & source_non_users)
    candidate_rows <- cf_population_candidate_filter(
      counterfactual_data$ind,
      candidate_rows,
      population_target,
      select_inside = TRUE
    )
    if (length(candidate_rows) < delta) {
      current_n <- sum(cf_users, na.rm = TRUE)
      .abort_appraisal_input(
        paste0(
          "The counterfactual ", spec$mode, " user target is ", current_n + delta,
          ", but only ", length(candidate_rows),
          " eligible baseline non-users are available in the filtered geographic population."
        ),
        stage = "counterfactual_users",
        fields = c(
          paste0("pop_number_cf_", spec$suffix, "_advanced"),
          paste0("users_count_cf_", spec$suffix)
        ),
        hint = "Reduce the counterfactual user target or broaden the population refinements.",
        details = list(
          mode = spec$mode,
          current_users = current_n,
          requested_users = current_n + delta,
          eligible_new_users = length(candidate_rows)
        )
      )
    }
    inside_candidates <- candidate_rows[cf_person_scope[candidate_rows]]
    outside_candidates <- candidate_rows[!cf_person_scope[candidate_rows]]
    inside_n <- min(delta, length(inside_candidates))
    outside_n <- delta - inside_n
    inside_rows <- .sample_cf_user_candidates(
      counterfactual_data$ind,
      inside_candidates,
      inside_n,
      population_target,
      seed + spec$seed_offset
    )
    outside_rows <- .sample_cf_user_candidates(
      counterfactual_data$ind,
      outside_candidates,
      outside_n,
      population_target,
      seed + spec$seed_offset + 500L
    )
    changed_rows <- c(inside_rows$rows, outside_rows$rows)
    cf_scope_added_n <- length(outside_rows$rows)
    sampling_fallback <- list(
      inside_ref_scope = inside_rows$sampling_fallback,
      recruited_from_source = outside_rows$sampling_fallback
    )
    sampling_fallback <- sampling_fallback[!vapply(sampling_fallback, is.null, logical(1))]
    if (length(sampling_fallback) == 0) sampling_fallback <- NULL
    donor_spec <- .mode_proxy_spec(spec)
    donor_users <- .positive_col(reference_data$ind, donor_spec$activity_col)
    replacement_values <- cf_sample_observed_values(
      values_ref = reference_data$ind[[donor_spec$activity_col]][donor_users] *
        (spec$proxy_duration_factor %||% 1),
      n = length(changed_rows),
      default_value = constants[[spec$default_col]],
      seed = seed + spec$seed_offset + 1000L
    )
    replacement_values <- .assumption_new_user_activity(
      replacement_values, constants$assumption_values %||% list(), spec$suffix,
      reference_mean = mean(reference_data$ind[[donor_spec$activity_col]][donor_users] *
                              (spec$proxy_duration_factor %||% 1), na.rm = TRUE)
    )
    role <- "new_users"
  } else {
    candidate_rows <- which(cf_users)
    candidate_rows <- cf_population_candidate_filter(
      counterfactual_data$ind,
      candidate_rows,
      population_target,
      select_inside = FALSE
    )
    if (length(candidate_rows) < abs(delta)) {
      current_n <- sum(cf_users, na.rm = TRUE)
      .abort_appraisal_input(
        paste0(
          "The counterfactual ", spec$mode, " user target is ", current_n + delta,
          ", which requires removing ", abs(delta), " users, but only ",
          length(candidate_rows), " current users are eligible under the population refinements."
        ),
        stage = "counterfactual_users",
        fields = c(
          paste0("pop_number_cf_", spec$suffix, "_advanced"),
          paste0("users_count_cf_", spec$suffix)
        ),
        hint = "Increase the counterfactual user target or broaden the population refinements."
      )
    }
    weights <- cf_individual_candidate_weights(counterfactual_data$ind, candidate_rows, population_target)
    changed_rows <- cf_sample_candidate_indices(
      candidate_rows,
      abs(delta),
      seed + spec$seed_offset,
      weights = weights
    )
    sampling_fallback <- attr(changed_rows, "sampling_fallback")
    replacement_values <- rep(constants[[spec$ex_user_default_col]], length(changed_rows))
    role <- "ex_users"
    cf_scope_added_n <- 0L
  }

  counterfactual_data$ind[[spec$activity_col]][changed_rows] <- replacement_values
  counterfactual_data$ind$cf_user_change[changed_rows] <- role
  if (delta > 0 && "cf_in_scope" %in% names(counterfactual_data$ind)) {
    counterfactual_data$ind$cf_in_scope[changed_rows] <- TRUE
  }
  if (delta > 0 && !is.null(counterfactual_data$trips) &&
      "cf_in_scope" %in% names(counterfactual_data$trips) &&
      "census_id" %in% names(counterfactual_data$trips)) {
    recruited_ids <- counterfactual_data$ind$census_id[changed_rows]
    counterfactual_data$trips$cf_in_scope[
      counterfactual_data$trips$census_id %in% recruited_ids
    ] <- TRUE
  }
  scope_col <- .reference_user_scope_col(spec$mode, "cf")
  if (scope_col %in% names(counterfactual_data$ind)) {
    counterfactual_data$ind[[scope_col]][changed_rows] <- delta > 0
  }
  list(
    counterfactual_data = counterfactual_data,
    changed_rows = changed_rows,
    role = role,
    donor_source = "reference_data",
    sampling_strategy = sampling_strategy,
    sampling_constraints = population_target$constraints %||% character(0),
    sampling_fallback = sampling_fallback,
    cf_scope_added_n = cf_scope_added_n,
    relevant_attributes = cf_individual_sampling_columns(reference_data$ind, spec$mode)
  )
}

.sample_cf_user_candidates <- function(ind, candidate_rows, n, population_target, seed) {
  if (n == 0) {
    return(list(rows = integer(0), sampling_fallback = NULL))
  }
  weights <- cf_individual_candidate_weights(ind, candidate_rows, population_target)
  rows <- cf_sample_candidate_indices(candidate_rows, n, seed, weights = weights)
  list(rows = rows, sampling_fallback = attr(rows, "sampling_fallback"))
}

.cf_user_target <- function(values, suffix) {
  users_field <- paste0("users_count_cf_", suffix)
  ui_version <- .ui_value(values, "ui_version", "basic")
  ui_version <- if (identical(ui_version, "advanced")) "advanced" else "basic"
  pop_field <- paste0("pop_number_cf_", suffix, "_", ui_version)
  fields <- if (identical(ui_version, "advanced")) {
    c(pop_field, users_field, paste0("pop_number_cf_", suffix, "_basic"))
  } else {
    c(users_field, pop_field)
  }

  for (field in fields) {
    target <- .ui_value(values, field, NULL)
    if (!.is_blank_cf_target(target)) {
      return(list(value = target, field = field, alias_field = pop_field))
    }
  }

  list(value = NULL, field = fields[[1]], alias_field = pop_field)
}

.cf_positive_mode_assumption <- function(values, field_stem, suffix) {
  field <- paste0(field_stem, "_", suffix)
  raw <- .ui_value(values, field, NULL)
  if (is.null(raw) || length(raw) == 0 || (length(raw) == 1 && is.na(raw))) {
    return(list(field = field, value = NULL))
  }

  value <- suppressWarnings(as.numeric(raw))
  if (length(value) != 1 || !is.finite(value) || value <= 0) {
    stop("`", field, "` must be one finite number greater than zero.", call. = FALSE)
  }

  list(field = field, value = value)
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
  source_diversion_target <- .cf_source_diversion_target(
    appraisal_input_values,
    spec$suffix,
    mode = spec$mode,
    constants = constants,
    trips = reference_data$trips
  )
  trip_rate <- .cf_positive_mode_assumption(
    appraisal_input_values,
    "default_trips_per_user_per_week",
    spec$suffix
  )
  target_base <- .validate_cf_trip_target(target, reference_data, spec)

  ref_scope_col <- .reference_trip_scope_col(mode, "ref")
  cf_scope_col <- .reference_trip_scope_col(mode, "cf")
  ref_scope <- if (ref_scope_col %in% names(reference_data$trips)) .true_values(reference_data$trips[[ref_scope_col]]) else TRUE
  cf_scope <- if (cf_scope_col %in% names(counterfactual_data$trips)) .true_values(counterfactual_data$trips[[cf_scope_col]]) else TRUE
  cf_active <- spec$trip_filter(counterfactual_data$trips) & cf_scope & !is.na(counterfactual_data$trips$nts_tripid)
  ref_active <- spec$trip_filter(reference_data$trips) & ref_scope & !is.na(reference_data$trips$nts_tripid)
  cf_n <- sum(cf_active, na.rm = TRUE)
  ref_n <- sum(ref_active, na.rm = TRUE)
  delta <- target_base$count - cf_n

  induced_target <- .cf_induced_trips_target(
    appraisal_input_values,
    spec$suffix,
    constants
  )
  new_user_target <- .cf_new_user_target(appraisal_input_values, constants)
  explicit_user_target <- .cf_user_target(appraisal_input_values, spec$suffix)
  user_allocation <- .cf_trip_user_allocation(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    spec = spec,
    target_trip_count = target_base$count,
    current_trip_count = cf_n,
    trips_per_user_per_week = trip_rate$value,
    new_user_percent = new_user_target$percent,
    explicit_user_target = explicit_user_target$value,
    seed = seed + spec$seed_offset + 2800L
  )
  assignment <- .assign_cf_trip_count_delta(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    spec = spec,
    ref_active = ref_active,
    cf_active = cf_active,
    delta = delta,
    seed = seed,
    sampling_strategy = sampling_strategy,
    trip_target = cf_trip_sampling_target(
      appraisal_input_values,
      spec$suffix,
      spread = constants$spread
    ),
    constants = constants,
    induced_trips_percent = induced_target$percent,
    recipient_ids = user_allocation$ids,
    source_diversion_target = source_diversion_target,
    diversion_target = .cf_away_diversion_target(constants)
  )

  counterfactual_data <- assignment$counterfactual_data
  if (is.null(explicit_user_target$value)) {
    # Trip-driven scenarios may start with no REF users, in which case the
    # preferred current/new split can initially yield no recipient IDs after
    # integer rounding. The owners of the trips actually changed are users by
    # construction and must be represented in the CF user scope shown in Tab 3.
    realized_owner_ids <- unique(c(
      user_allocation$ids,
      .changed_trip_census_ids(assignment$changed_rows)
    ))
    realized_owner_ids <- realized_owner_ids[!is.na(realized_owner_ids)]
    user_allocation$ids <- realized_owner_ids
    user_allocation$target_users <- length(realized_owner_ids)
    user_allocation$report$target_users <- length(realized_owner_ids)
    counterfactual_data <- .set_cf_mode_user_scope(
      counterfactual_data,
      spec,
      realized_owner_ids
    )
  }
  updated_scope <- if (cf_scope_col %in% names(counterfactual_data$trips)) .true_values(counterfactual_data$trips[[cf_scope_col]]) else TRUE
  updated_cf_active <- spec$trip_filter(counterfactual_data$trips) & updated_scope &
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
  change$target_physical_row_count <- target_base$count
  change$implied_weekly_users <- if (is.null(trip_rate$value)) {
    user_allocation$target_users
  } else {
    as.integer(ceiling(target_base$count / trip_rate$value))
  }
  change$trips_per_user_per_week <- trip_rate$value
  change$trips_per_user_per_week_field <- trip_rate$field
  change$realized_changed_users <- length(unique(.changed_trip_census_ids(
    assignment$changed_rows
  )))
  change$target_denominator <- target$denominator
  change$target_timeframe <- target$timeframe
  change$distribution_args <- args
  change$sampling_strategy <- assignment$sampling_strategy
  change$relevant_attributes <- assignment$relevant_attributes
  change$sampling_constraints <- assignment$sampling_constraints
  change$mode_shift_n <- assignment$mode_shift_n
  change$induced_n <- assignment$induced_n
  change$induced_trips_percent <- assignment$induced_trips_percent
  change$induced_trips_percent_field <- induced_target$field
  change$induced_trips_percent_source <- induced_target$source
  change$new_user_percent <- new_user_target$percent
  change$new_user_percent_field <- new_user_target$field
  change$new_user_percent_source <- new_user_target$source
  change$user_allocation <- user_allocation$report
  change$diversion_source_field <- source_diversion_target$field
  change$source_mode_shares <- source_diversion_target$shares
  change$source_mode_shares_source <- source_diversion_target$source
  change$realized_source_mode_shares <- assignment$realized_source_mode_shares

  notes <- character(0)
  if (length(args$advanced_fields_present) > 0) {
    notes <- c(
      notes,
      paste0(
        "Trip distribution fields parsed but not yet applied for mode `", mode,
        "`: ", paste(args$advanced_fields_present, collapse = ", ")
      )
    )
  }
  if (!is.null(assignment$sampling_fallback)) {
    notes <- c(notes, .sampling_fallback_note(assignment$sampling_fallback, paste0(mode, " trip")))
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
    induced_trips_percent,
    recipient_ids,
    source_diversion_target,
    diversion_target
) {
  relevant_attributes <- cf_trip_sampling_columns(reference_data$trips, spec$mode)

  if (delta == 0) {
    return(list(
      counterfactual_data = counterfactual_data,
      changed_rows = data.frame(),
      role = "unchanged",
      sampling_strategy = sampling_strategy,
      sampling_constraints = .trip_sampling_constraints(trip_target, source_diversion_target),
      sampling_fallback = NULL,
      relevant_attributes = relevant_attributes,
      mode_shift_n = 0L,
      induced_n = 0L,
      induced_trips_percent = induced_trips_percent,
      realized_source_mode_shares = NULL
    ))
  }

  if (delta > 0) {
    mechanisms <- cf_trip_mechanism_counts(delta, induced_trips_percent)
    shifted <- .shift_nonactive_trips_to_mode(
      counterfactual_data = counterfactual_data,
      reference_data = reference_data,
      spec = spec,
      n = mechanisms$mode_shift_n,
      trip_target = trip_target,
      source_diversion_target = source_diversion_target,
      constants = constants,
      seed = seed + spec$seed_offset + 3000L,
      recipient_ids = recipient_ids,
      exposure_source = "trip_target"
    )
    counterfactual_data <- shifted$counterfactual_data
    induced_n <- mechanisms$induced_n + max(0L, mechanisms$mode_shift_n - shifted$changed_n)
    induced <- .add_induced_active_trips(
      counterfactual_data = counterfactual_data,
      reference_data = reference_data,
      spec = spec,
      n = induced_n,
      seed = seed + spec$seed_offset + 3500L,
      census_ids = recipient_ids,
      constants = constants
    )
    counterfactual_data <- induced$counterfactual_data
    changed_rows <- rbind(shifted$changed_rows, induced$changed_rows)
    role <- "mode_shift_and_induced_trips"
    mode_shift_n <- shifted$changed_n
    induced_n <- induced$changed_n
    sampling_fallback <- shifted$sampling_fallback
    realized_source_mode_shares <- shifted$realized_source_mode_shares
  } else {
    unlocked <- !.true_values(counterfactual_data$trips$cf_trip_locked)
    removal_candidates <- which(cf_active & unlocked)
    if (length(removal_candidates) < abs(delta)) {
      current_n <- sum(cf_active, na.rm = TRUE)
      stop(
        "Counterfactual trip target for mode `",
        spec$mode, "` requires removing ", abs(delta), " active rows (current ",
        current_n, ", target ", current_n + delta, "), but only ",
        length(removal_candidates), " active rows remain eligible and unlocked. ",
        "Check whether user and trip refinements define compatible targets.",
        call. = FALSE
      )
    }
    remove_rows <- cf_sample_candidate_indices(
      removal_candidates,
      abs(delta),
      seed + spec$seed_offset + 4000L
    )
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
      seed = seed + spec$seed_offset + 4500L,
      exposure_source = "trip_target"
    )
    scope_col <- .reference_trip_scope_col(spec$mode, "cf")
    if (scope_col %in% names(counterfactual_data$trips)) {
      counterfactual_data$trips[[scope_col]][remove_rows] <- FALSE
    }
    role <- "shifted_away_trips"
    mode_shift_n <- -length(remove_rows)
    induced_n <- 0L
    sampling_fallback <- attr(remove_rows, "sampling_fallback")
    realized_source_mode_shares <- NULL
  }

  counterfactual_data <- cf_add_key_indicators(counterfactual_data, spec$mode)

  list(
    counterfactual_data = counterfactual_data,
    changed_rows = changed_rows,
    role = role,
    sampling_strategy = sampling_strategy,
    sampling_constraints = .trip_sampling_constraints(trip_target, source_diversion_target),
    sampling_fallback = sampling_fallback,
    relevant_attributes = relevant_attributes,
    mode_shift_n = mode_shift_n,
    induced_n = induced_n,
    induced_trips_percent = induced_trips_percent,
    realized_source_mode_shares = realized_source_mode_shares
  )
}

.cf_trip_target <- function(values, suffix) {
  tab2_field <- paste0("trips_count_cf_", suffix)
  tab4_field <- paste0("trips_number_cf_", suffix)

  # Tab 4 is the final trip-refinement surface in the advanced workflow, so
  # its count must override the upstream Tab 2 equivalent. Basic appraisals do
  # not visit Tab 4 and retain Tab 2 as their canonical source.
  advanced <- identical(.ui_value(values, "ui_version", "basic"), "advanced")
  fields <- if (advanced) c(tab4_field, tab2_field) else c(tab2_field, tab4_field)
  field <- fields[[1]]
  value <- NULL
  for (candidate in fields) {
    candidate_value <- .ui_value(values, candidate, NULL)
    if (!.is_blank_cf_target(candidate_value)) {
      field <- candidate
      value <- candidate_value
      break
    }
  }

  from_tab4 <- identical(field, tab4_field)
  timeframe <- if (from_tab4) {
    "week"
  } else {
    .ui_value(values, paste0("trips_timeframe_", suffix), "week")
  }
  denominator <- if (from_tab4) {
    "total"
  } else {
    .ui_value(values, paste0("trips_denominator_", suffix), "total")
  }

  if (.is_blank_cf_target(value)) {
    value <- NULL
  }

  list(
    field = field,
    value = value,
    timeframe = timeframe,
    denominator = denominator
  )
}

# Hidden Shiny inputs can be included in a submitted profile as scalar `NA`
# values. Such values mean "not supplied" and must not mask the corresponding
# Basic/Advanced alias. Non-blank invalid values still reach strict validators.
.is_blank_cf_target <- function(value) {
  if (is.null(value) || length(value) == 0) {
    return(TRUE)
  }

  if (length(value) == 1 && is.na(value)) {
    return(TRUE)
  }

  is.character(value) && length(value) == 1 && !nzchar(trimws(value))
}

.cf_trip_distribution_args <- function(values, suffix) {
  report_only_fields <- c(
    "pop_new_current_perc",
    "trips_dist_value",
    paste0("trips_spread_mean_cf_", suffix),
    paste0("trips_spread_util_prop_cf_", suffix)
  )
  present <- report_only_fields[!vapply(
    lapply(report_only_fields, function(field) .ui_value(values, field, NULL)),
    is.null,
    logical(1)
  )]

  list(
    new_user_percent = .ui_value(values, "pop_new_current_perc", NULL),
    trip_distance_default = .ui_value(
      values,
      paste0("default_trip_distance_", suffix),
      NULL
    ),
    purpose_type = .ui_value(values, "trips_purpose_type", NULL),
    utilitarian_percent = .ui_value(values, "trips_purpose_util_perc", NULL),
    target_mean_distance = .ui_value(values, paste0("trips_spread_mean_cf_", suffix), NULL),
    target_utilitarian_prop = .ui_value(values, paste0("trips_spread_util_prop_cf_", suffix), NULL),
    diversion_car_percent = .ui_value(
      values,
      paste0("trips_diversion_car_perc_", suffix),
      NULL
    ),
    advanced_fields_present = present
  )
}

.cf_induced_trips_target <- function(values, suffix, constants) {
  fields <- c(
    paste0("induced_trips_percent_", suffix),
    "induced_trips_percent"
  )
  field <- NULL
  raw <- NULL
  for (candidate in fields) {
    candidate_value <- .ui_value(values, candidate, NULL)
    if (!.is_blank_cf_target(candidate_value)) {
      field <- candidate
      raw <- candidate_value
      break
    }
  }

  source <- "profile"
  if (is.null(field)) {
    raw <- constants$induced_trips_percent_default
    source <- "config_default"
  }
  value <- suppressWarnings(as.numeric(raw))
  if (length(value) != 1 || !is.finite(value) || value < 0 || value > 100) {
    label <- field %||% "induced_trips_percent_default"
    stop("`", label, "` must be between 0 and 100.", call. = FALSE)
  }

  list(
    percent = value,
    field = field,
    source = source
  )
}

.cf_new_user_target <- function(values, constants) {
  field <- "pop_new_current_perc"
  raw <- .ui_value(values, field, NULL)
  source <- "profile"
  if (.is_blank_cf_target(raw)) {
    field <- NULL
    raw <- constants$new_user_percent_default %||% 10
    source <- "config_default"
  }
  value <- suppressWarnings(as.numeric(raw))
  if (length(value) != 1 || !is.finite(value) || value < 0 || value > 100) {
    stop("`pop_new_current_perc` must be between 0 and 100.", call. = FALSE)
  }
  list(percent = value, field = field, source = source)
}

.cf_trip_user_allocation <- function(counterfactual_data,
                                     reference_data,
                                     spec,
                                     target_trip_count,
                                     current_trip_count,
                                     trips_per_user_per_week,
                                     new_user_percent,
                                     explicit_user_target = NULL,
                                     seed = 1L) {
  ind <- counterfactual_data$ind
  if (is.null(ind) || !"census_id" %in% names(ind)) {
    return(list(ids = NULL, target_users = NULL, report = list(method = "unavailable")))
  }
  in_scope <- if ("cf_in_scope" %in% names(ind)) {
    .true_values(ind$cf_in_scope)
  } else {
    rep(TRUE, nrow(ind))
  }
  mode_scope_col <- .reference_user_scope_col(spec$mode, "cf")
  current_mode <- if (mode_scope_col %in% names(ind)) {
    .true_values(ind[[mode_scope_col]]) & in_scope
  } else if (!is.na(spec$activity_col) && spec$activity_col %in% names(ind)) {
    .positive_col(ind, spec$activity_col) & in_scope
  } else {
    rep(FALSE, nrow(ind))
  }

  if (!is.null(explicit_user_target)) {
    return(list(
      ids = ind$census_id[current_mode],
      target_users = sum(current_mode),
      report = list(method = "explicit_user_target", target_users = sum(current_mode))
    ))
  }

  rate <- trips_per_user_per_week
  if (is.null(rate) || !is.finite(rate) || rate <= 0) {
    current_trip_n <- sum(spec$trip_filter(reference_data$trips), na.rm = TRUE)
    current_user_n <- sum(current_mode)
    rate <- if (current_user_n > 0 && current_trip_n > 0) {
      current_trip_n / current_user_n
    } else {
      1
    }
  }
  current_rows <- which(current_mode)
  trip_delta <- target_trip_count - current_trip_count
  equivalent_changed_users <- as.integer(ceiling(abs(trip_delta) / rate))

  if (trip_delta <= 0) {
    removed_users <- min(
      length(current_rows),
      as.integer(round(equivalent_changed_users * new_user_percent / 100))
    )
    target_users <- length(current_rows) - removed_users
    set.seed(seed)
    selected <- if (target_users == 0L) integer(0) else {
      sample(current_rows, target_users, replace = FALSE)
    }
    return(list(
      ids = ind$census_id[selected],
      target_users = target_users,
      report = list(
        method = "trips_per_user",
        trips_per_user_per_week = rate,
        target_users = target_users,
        retained_current_mode_users = target_users,
        equivalent_changed_users = equivalent_changed_users,
        added_current_at_users = 0L,
        added_new_at_users = 0L
      )
    ))
  }

  any_current_at <- rep(FALSE, nrow(ind))
  for (mode in .miama_supported_modes()) {
    col <- .reference_user_scope_col(mode, "ref")
    if (col %in% names(reference_data$ind)) {
      matched <- match(ind$census_id, reference_data$ind$census_id)
      any_current_at <- any_current_at | .true_values(reference_data$ind[[col]][matched])
    } else {
      mode_spec <- .counterfactual_mode_spec(mode)
      if (!is.null(mode_spec) && !is.na(mode_spec$activity_col) &&
          mode_spec$activity_col %in% names(reference_data$ind)) {
        matched <- match(ind$census_id, reference_data$ind$census_id)
        any_current_at <- any_current_at |
          .positive_col(reference_data$ind, mode_spec$activity_col)[matched]
      }
    }
  }
  requested_new_n <- as.integer(round(
    equivalent_changed_users * new_user_percent / 100
  ))
  new_at_candidates <- which(in_scope & !any_current_at)
  new_n <- min(requested_new_n, length(new_at_candidates))
  set.seed(seed + 1L)
  selected_new <- if (new_n == 0L) integer(0) else {
    sample(new_at_candidates, new_n, replace = FALSE)
  }

  # Normally the remaining additional trips are concentrated among existing
  # users of the target mode. E-bike has no observed baseline users, so current
  # active-travel users provide the explicit proxy recipient pool.
  selected_current <- integer(0)
  if (length(current_rows) == 0L) {
    proxy_n <- min(
      equivalent_changed_users - length(selected_new),
      sum(in_scope & any_current_at)
    )
    proxy_candidates <- which(in_scope & any_current_at)
    set.seed(seed)
    if (proxy_n > 0L) {
      selected_current <- sample(proxy_candidates, proxy_n, replace = FALSE)
    }
  }
  selected <- unique(c(current_rows, selected_current, selected_new))
  target_users <- length(selected)
  list(
    ids = ind$census_id[selected],
    target_users = target_users,
    report = list(
      method = "trips_per_user",
      trips_per_user_per_week = rate,
      target_users = target_users,
      retained_current_mode_users = length(current_rows),
      equivalent_changed_users = equivalent_changed_users,
      requested_new_user_percent = new_user_percent,
      added_current_at_users = length(selected_current),
      added_new_at_users = length(selected_new),
      realized_new_user_percent = if (equivalent_changed_users == 0) 0 else {
        100 * length(selected_new) / equivalent_changed_users
      }
    )
  )
}

.set_cf_mode_user_scope <- function(counterfactual_data, spec, census_ids) {
  if (is.null(counterfactual_data$ind) || !"census_id" %in% names(counterfactual_data$ind)) {
    return(counterfactual_data)
  }
  scope_col <- .reference_user_scope_col(spec$mode, "cf")
  old <- if (scope_col %in% names(counterfactual_data$ind)) {
    .true_values(counterfactual_data$ind[[scope_col]])
  } else {
    rep(FALSE, nrow(counterfactual_data$ind))
  }
  new <- counterfactual_data$ind$census_id %in% census_ids
  if ("cf_in_scope" %in% names(counterfactual_data$ind)) {
    new <- new & .true_values(counterfactual_data$ind$cf_in_scope)
  }
  counterfactual_data$ind[[scope_col]] <- new
  if ("cf_user_change" %in% names(counterfactual_data$ind)) {
    counterfactual_data$ind$cf_user_change[!old & new] <- "new_users_from_trip_target"
    counterfactual_data$ind$cf_user_change[old & !new] <- "ex_users_from_trip_target"
  }
  counterfactual_data
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
    source_diversion_target,
    diversion_target,
    trips_per_user_per_week = NULL,
    explicit_trip_count = NULL
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
      trip_shift_n = 0L,
      sampling_fallback = NULL,
      realized_source_mode_shares = NULL
    ))
  }

  changed_ids <- counterfactual_data$ind$census_id[changed_rows]
  trip_shift_target_n <- 0L
  trip_shift_n <- 0L
  sampling_fallback <- NULL
  realized_source_mode_shares <- NULL
  if (identical(role, "ex_users")) {
    active <- spec$trip_filter(counterfactual_data$trips)
    unlocked <- !.true_values(counterfactual_data$trips$cf_trip_locked)
    trip_rows <- which(
      counterfactual_data$trips$census_id %in% changed_ids & active & unlocked
    )
    counterfactual_data$trips <- .switch_trips_away_from_active(
      counterfactual_data$trips,
      rows = trip_rows,
      spec = spec,
      constants = constants,
      diversion_target = diversion_target,
      seed = seed + spec$seed_offset + 2400L,
      exposure_source = "user_status"
    )
    return(list(
      counterfactual_data = counterfactual_data,
      notes = notes,
      trip_shift_target_n = length(trip_rows),
      trip_shift_n = length(trip_rows),
      sampling_fallback = NULL,
      realized_source_mode_shares = NULL
    ))
  }

  if (identical(role, "new_users")) {
    trip_shift_target_n <- .new_user_trip_shift_count(
      reference_data = reference_data,
      spec = spec,
      new_user_n = length(changed_ids),
      seed = seed + spec$seed_offset + 2300L,
      trips_per_user_per_week = trips_per_user_per_week
    )
    if (!is.null(explicit_trip_count)) {
      current_active <- spec$trip_filter(counterfactual_data$trips) &
        !is.na(counterfactual_data$trips$nts_tripid)
      scope_col <- .reference_trip_scope_col(spec$mode, "cf")
      if (scope_col %in% names(counterfactual_data$trips)) {
        current_active <- current_active &
          .true_values(counterfactual_data$trips[[scope_col]])
      }
      remaining_to_target <- max(
        0L,
        as.integer(explicit_trip_count) - sum(current_active, na.rm = TRUE)
      )
      inferred_target <- trip_shift_target_n
      trip_shift_target_n <- min(trip_shift_target_n, remaining_to_target)
      if (trip_shift_target_n < inferred_target) {
        notes <- c(
          notes,
          paste0(
            "User-derived `", spec$mode, "` trips were capped at ",
            trip_shift_target_n, " because the explicit trip target is ",
            explicit_trip_count, "."
          )
        )
      }
    }
    shifted <- .shift_nonactive_trips_to_mode(
      counterfactual_data = counterfactual_data,
      reference_data = reference_data,
      spec = spec,
      n = trip_shift_target_n,
      trip_target = trip_target,
      source_diversion_target = source_diversion_target,
      constants = constants,
      seed = seed + spec$seed_offset + 2500L,
      census_ids = changed_ids,
      exposure_source = "user_status"
    )
    counterfactual_data <- shifted$counterfactual_data
    trip_shift_n <- shifted$changed_n
    sampling_fallback <- shifted$sampling_fallback
    realized_source_mode_shares <- shifted$realized_source_mode_shares
    if (!is.null(sampling_fallback)) {
      notes <- c(notes, .sampling_fallback_note(sampling_fallback, paste0(spec$mode, " trip")))
    }
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
    trip_shift_n = trip_shift_n,
    sampling_fallback = sampling_fallback %||% NULL,
    realized_source_mode_shares = realized_source_mode_shares
  )
}

.shift_nonactive_trips_to_mode <- function(
    counterfactual_data,
    reference_data,
    spec,
    n,
    trip_target,
    source_diversion_target,
    constants,
    seed,
    census_ids = NULL,
    recipient_ids = NULL,
    exposure_source = "trip_target"
) {
  if (n == 0 || is.null(counterfactual_data$trips)) {
    return(list(
      counterfactual_data = counterfactual_data,
      changed_rows = .empty_changed_trip_rows(),
      changed_n = 0L,
      sampling_fallback = NULL,
      realized_source_mode_shares = NULL
    ))
  }

  trips <- counterfactual_data$trips
  active <- spec$trip_filter(trips)
  # A configured source-mode distribution may explicitly make another active
  # mode eligible (for example, cycling or PT diverted to e-bike). Otherwise,
  # preserve the established rule that active modes do not cannibalize one
  # another. `cf_trip_locked` always prevents a row being switched twice.
  active_any_mode <- if ("trip_activemode" %in% names(trips)) {
    .true_values(trips$trip_activemode)
  } else {
    rep(FALSE, nrow(trips))
  }
  active_source_modes <- c("walking", "cycling", "ebiking", "pt")
  cross_mode_source <- source_diversion_target$source %in% c("config", "ui") &&
    !is.null(source_diversion_target$shares) &&
    any(
      names(source_diversion_target$shares) %in% active_source_modes &
        source_diversion_target$shares > 0
    )
  unlocked <- !.true_values(trips$cf_trip_locked)
  candidates <- which(
    !active & (cross_mode_source | !active_any_mode) & unlocked &
      !is.na(trips$nts_tripid)
  )
  if ("cf_in_scope" %in% names(trips)) {
    candidates <- candidates[.true_values(trips$cf_in_scope[candidates])]
  }
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
    return(list(
      counterfactual_data = counterfactual_data,
      changed_rows = .empty_changed_trip_rows(),
      changed_n = 0L,
      sampling_fallback = NULL,
      realized_source_mode_shares = NULL
    ))
  }

  shift_n <- min(n, length(candidates))
  weights <- cf_trip_candidate_weights(trips, candidates, active_distances, trip_target)
  weights <- .source_diversion_candidate_weights(
    trips,
    candidates,
    source_diversion_target,
    base_weights = weights
  )
  rows <- cf_sample_candidate_indices(candidates, shift_n, seed, weights = weights)
  sampling_fallback <- attr(rows, "sampling_fallback")
  realized_source_mode_shares <- .realized_source_mode_shares(trips, rows)

  trips <- .switch_trips_to_active_mode(trips, rows, spec, constants)
  if (!is.null(recipient_ids) && length(recipient_ids) > 0 &&
      "census_id" %in% names(trips)) {
    set.seed(seed + 1L)
    trips$census_id[rows] <- sample(recipient_ids, length(rows), replace = TRUE)
  }
  trips$cf_trip_change[rows] <- "mode_shift_to_active"
  trips$cf_mode_shift[rows] <- TRUE
  trips$cf_trip_locked[rows] <- TRUE
  trips$cf_trip_exposure_source[rows] <- exposure_source
  scope_col <- .reference_trip_scope_col(spec$mode, "cf")
  if (scope_col %in% names(trips)) trips[[scope_col]][rows] <- TRUE
  counterfactual_data$trips <- trips

  changed_rows <- trips[rows, intersect(c("census_id", "nts_tripid"), names(trips)), drop = FALSE]
  list(
    counterfactual_data = counterfactual_data,
    changed_rows = changed_rows,
    changed_n = length(rows),
    sampling_fallback = sampling_fallback,
    realized_source_mode_shares = realized_source_mode_shares
  )
}

.add_induced_active_trips <- function(counterfactual_data,
                                      reference_data,
                                      spec,
                                      n,
                                      seed,
                                      census_ids = NULL,
                                      constants = NULL) {
  if (n == 0 || is.null(reference_data$trips)) {
    return(list(counterfactual_data = counterfactual_data, changed_rows = .empty_changed_trip_rows(), changed_n = 0L))
  }

  donor_spec <- .mode_proxy_spec(spec)
  ref_active <- donor_spec$trip_filter(reference_data$trips) & !is.na(reference_data$trips$nts_tripid)
  donor_rows <- which(ref_active)
  if (length(donor_rows) == 0) {
    return(list(counterfactual_data = counterfactual_data, changed_rows = .empty_changed_trip_rows(), changed_n = 0L))
  }

  donor_rows <- cf_sample_candidate_indices(donor_rows, n, seed, replace = TRUE)
  new_rows <- reference_data$trips[donor_rows, , drop = FALSE]
  if (!is.null(census_ids) && length(census_ids) > 0 && "census_id" %in% names(new_rows)) {
    set.seed(seed + 1L)
    new_rows$census_id <- sample(census_ids, nrow(new_rows), replace = TRUE)
  }
  new_rows <- .assign_new_trip_ids(counterfactual_data$trips, new_rows)
  new_rows <- .switch_trips_to_active_mode(
    new_rows, seq_len(nrow(new_rows)), spec, constants = constants
  )
  # Preserve the donor weight. Each induced synthetic row represents the same
  # population stratum as its sampled donor; assigning weight 1 would mix row
  # counts and represented trip totals and systematically distort outputs.
  if ("trip_purpose" %in% names(new_rows) &&
      (is.character(new_rows$trip_purpose) || is.factor(new_rows$trip_purpose))) {
    new_rows$trip_purpose <- "Recreational"
  }
  # Numeric NTS purpose codes in parquet have no retained value labels. Keep
  # the donor code rather than inventing a recreational code; the explicit
  # binary indicator below is authoritative for counterfactual classification.
  new_rows$trip_utilitarian <- FALSE
  new_rows$cf_trip_change <- "induced_recreational_active"
  new_rows$cf_mode_shift <- FALSE
  new_rows$cf_induced <- TRUE
  new_rows$cf_trip_locked <- TRUE
  new_rows$cf_trip_exposure_source <- "trip_target"
  if ("cf_source_census_id" %in% names(new_rows)) {
    new_rows$cf_source_census_id[] <- NA
  }
  if ("cf_source_nts_tripid" %in% names(new_rows)) {
    new_rows$cf_source_nts_tripid[] <- NA
  }
  if ("cf_in_scope" %in% names(new_rows)) new_rows$cf_in_scope <- TRUE
  scope_col <- .reference_trip_scope_col(spec$mode, "cf")
  if (scope_col %in% names(new_rows)) new_rows[[scope_col]] <- TRUE

  counterfactual_data$trips <- rbind(counterfactual_data$trips, new_rows)
  changed_rows <- new_rows[, intersect(c("census_id", "nts_tripid"), names(new_rows)), drop = FALSE]
  list(counterfactual_data = counterfactual_data, changed_rows = changed_rows, changed_n = nrow(new_rows))
}

.cf_scoped_person_ids <- function(counterfactual_data) {
  if (is.null(counterfactual_data$ind) || !"census_id" %in% names(counterfactual_data$ind)) {
    return(NULL)
  }
  keep <- if ("cf_in_scope" %in% names(counterfactual_data$ind)) {
    .true_values(counterfactual_data$ind$cf_in_scope)
  } else {
    rep(TRUE, nrow(counterfactual_data$ind))
  }
  counterfactual_data$ind$census_id[keep]
}

.switch_trips_to_active_mode <- function(trips, rows, spec, constants = NULL) {
  if (length(rows) == 0) {
    return(trips)
  }
  if ("trip_mainmode" %in% names(trips)) {
    trips$trip_mainmode[rows] <- spec$trip_mainmode_value
  }
  constants <- constants %||% miama_counterfactual_defaults()
  if (identical(spec$mode, "pt")) {
    if (spec$trip_distance_col %in% names(trips)) {
      existing <- .as_plain_numeric(trips[[spec$trip_distance_col]][rows])
      trips[[spec$trip_distance_col]][rows] <- ifelse(
        is.finite(existing) & existing > 0,
        existing,
        constants$pt_access_walk_distance_km_default
      )
    }
    if (spec$trip_duration_col %in% names(trips)) {
      existing <- .as_plain_numeric(trips[[spec$trip_duration_col]][rows])
      trips[[spec$trip_duration_col]][rows] <- ifelse(
        is.finite(existing) & existing > 0,
        existing,
        constants$pt_access_walk_minutes_default
      )
    }
  } else {
    if (!is.na(spec$trip_distance_col) && spec$trip_distance_col %in% names(trips) &&
        "trip_distraw_km" %in% names(trips)) {
      trips[[spec$trip_distance_col]][rows] <- trips$trip_distraw_km[rows]
    }
    if (!is.na(spec$trip_duration_col) && spec$trip_duration_col %in% names(trips)) {
      if (identical(spec$mode, "ebiking") && "trip_distraw_km" %in% names(trips)) {
        trips[[spec$trip_duration_col]][rows] <-
          .as_plain_numeric(trips$trip_distraw_km[rows]) /
          constants$ebike_speed_kmh * 60
      } else if ("trip_durationraw_min" %in% names(trips)) {
        trips[[spec$trip_duration_col]][rows] <- trips$trip_durationraw_min[rows]
      }
    }
  }

  # In the assumptions contract, changed CF trips use target-mode speed.
  # The distance is the sampled journey (PT: access leg), not the donor speed.
  if (!is.null(constants$assumption_values) &&
      spec$trip_distance_col %in% names(trips) && spec$trip_duration_col %in% names(trips)) {
    speed <- constants$assumption_values[[paste0("assump_trip_speed_", spec$suffix)]]
    trips[[spec$trip_duration_col]][rows] <-
      .as_plain_numeric(trips[[spec$trip_distance_col]][rows]) / speed * 60
  }

  for (col in setdiff(
    c(
      "trip_walkdist_km", "trip_walktime_min",
      "trip_cycledist_km", "trip_cycletime_min",
      "trip_ebikedist_km", "trip_ebiketime_min"
    ),
    c(spec$trip_distance_col, spec$trip_duration_col)
  )) {
    if (col %in% names(trips)) {
      trips[[col]][rows] <- 0
    }
  }

  trips
}

.switch_trips_away_from_active <- function(trips,
                                           rows,
                                           spec,
                                           constants,
                                           diversion_target,
                                           seed,
                                           exposure_source = "trip_target") {
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
  trips$cf_trip_locked[rows] <- TRUE
  trips$cf_trip_exposure_source[rows] <- exposure_source
  trips
}

.new_user_trip_shift_count <- function(reference_data,
                                       spec,
                                       new_user_n,
                                       seed,
                                       trips_per_user_per_week = NULL) {
  if (!is.null(trips_per_user_per_week)) {
    return(as.integer(round(new_user_n * trips_per_user_per_week)))
  }

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

# Returns the requested source-mode distribution for shifts into one target
# mode. The target is encoded by the field suffix; its own source share is
# removed because an existing target-mode trip cannot shift into itself.
.cf_source_diversion_target <- function(values,
                                         suffix,
                                         mode = NULL,
                                         constants = NULL,
                                         trips = NULL) {
  field <- paste0("trips_diversion_sources_", suffix)
  raw <- .ui_value(values, field, NULL)
  configured <- constants$source_mode_shares[[mode]] %||% NULL

  if (!is.null(raw)) {
    shares <- .normalize_diversion_source_shares(raw, target_mode = mode)
    if (is.null(shares)) {
      stop(
        "`", field, "` must contain non-negative source-mode percentages with a positive total.",
        call. = FALSE
      )
    }
    return(list(field = field, shares = shares, source = "ui"))
  }

  shares <- .normalize_diversion_source_shares(configured, target_mode = mode)
  source <- if (is.null(shares)) "unconstrained" else "config"
  if (is.null(shares)) {
    shares <- .observed_diversion_source_shares(
      trips,
      target_mode = mode,
      exclude_assessed_active = TRUE
    )
    if (!is.null(shares)) source <- "reference_donor_composition"
  }
  list(
    field = field,
    shares = shares,
    source = source
  )
}

# Assigns each available source-mode pool its requested probability mass while
# preserving distance and spread weights within that pool. Requested modes with
# no eligible candidates are omitted and the remaining positive shares are
# renormalized; the realized distribution is reported after sampling.
.source_diversion_candidate_weights <- function(
    trips,
    candidates,
    source_diversion_target,
    base_weights = rep(1, length(candidates))
) {
  if (length(candidates) == 0 ||
      !"trip_mainmode" %in% names(trips)) {
    return(base_weights)
  }

  source_shares <- source_diversion_target$shares %||% NULL
  if (is.null(source_shares)) return(base_weights)

  source_mode <- .results_trip_mode_group(trips$trip_mainmode[candidates])
  base_weights[is.na(base_weights) | base_weights < 0] <- 0
  totals <- vapply(names(source_shares), function(mode) {
    sum(base_weights[source_mode == mode], na.rm = TRUE)
  }, numeric(1))
  available <- is.finite(totals) & totals > 0 & source_shares > 0
  if (!any(available)) return(base_weights)

  available_shares <- source_shares[available]
  available_shares <- available_shares / sum(available_shares)
  weights <- rep(0, length(candidates))
  for (source in names(available_shares)) {
    rows <- source_mode == source
    weights[rows] <- base_weights[rows] * available_shares[[source]] / totals[[source]]
  }
  weights
}

.realized_source_mode_shares <- function(trips, rows) {
  if (length(rows) == 0 || !"trip_mainmode" %in% names(trips)) return(NULL)

  source_mode <- .results_trip_mode_group(trips$trip_mainmode[rows])
  source_mode <- source_mode[!is.na(source_mode)]
  if (length(source_mode) == 0) return(NULL)

  counts <- table(source_mode)
  stats::setNames(as.numeric(counts) / sum(counts), names(counts))
}

.trip_sampling_constraints <- function(trip_target, source_diversion_target) {
  constraints <- trip_target$constraints %||% character(0)
  if (!is.null(source_diversion_target$shares)) {
    constraints <- c(constraints, "source_mode_distribution")
  }
  unique(constraints)
}

# Active-trip decreases and ex-user changes need a destination mode. This is a
# separate assumption from the car-source shares above; for now they use the
# configured default destination (normally car).
.cf_away_diversion_target <- function(constants) {
  list(
    modes = constants$default_diversion_mode,
    probs = 1,
    source = "default"
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
  donor_spec <- .mode_proxy_spec(spec)
  active <- donor_spec$trip_filter(trips)
  if ("trip_distraw_km" %in% names(trips)) {
    return(trips$trip_distraw_km[active])
  }
  if (!is.na(donor_spec$trip_distance_col) && donor_spec$trip_distance_col %in% names(trips)) {
    return(trips[[donor_spec$trip_distance_col]][active])
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

.recalculate_counterfactual_mmets <- function(counterfactual_data,
                                              reference_data,
                                              constants) {
  if (is.null(counterfactual_data$ind) || !"mmets" %in% names(counterfactual_data$ind)) {
    return(counterfactual_data)
  }
  if (is.null(reference_data$ind) || !"mmets" %in% names(reference_data$ind)) {
    return(counterfactual_data)
  }

  cf_ind <- counterfactual_data$ind
  ref_ind <- reference_data$ind
  matched <- match(cf_ind$census_id, ref_ind$census_id)
  if (anyNA(matched)) {
    stop("Counterfactual individuals could not all be matched to reference MMET rows.", call. = FALSE)
  }

  activity_delta <- function(column) {
    if (!column %in% names(cf_ind) || !column %in% names(ref_ind)) {
      return(0)
    }
    cf_value <- as.numeric(cf_ind[[column]])
    ref_value <- as.numeric(ref_ind[[column]][matched])
    cf_value[is.na(cf_value) | cf_value < 0] <- 0
    ref_value[is.na(ref_value) | ref_value < 0] <- 0
    cf_value - ref_value
  }

  user_delta_walking <- activity_delta("walktime_wkhr") * constants$mmet_walking
  user_delta_cycling <- activity_delta("cycletime_wkhr") * constants$mmet_cycling
  user_delta_ebiking <- activity_delta("ebiketime_wkhr") * constants$mmet_ebiking
  user_delta_pt <- activity_delta("pttime_wkhr") * constants$mmet_pt
  user_delta_other <- activity_delta("sport_wkhr") * constants$mmet_vigorous
  user_delta <- user_delta_walking + user_delta_cycling + user_delta_ebiking +
    user_delta_pt + user_delta_other

  trip_delta_by_mode <- .counterfactual_trip_mmet_delta_by_mode(
    counterfactual_data$trips,
    reference_data$trips,
    cf_ind$census_id,
    constants
  )
  trip_delta <- rowSums(trip_delta_by_mode)

  mode_delta_walking <- user_delta_walking + trip_delta_by_mode$walking
  mode_delta_cycling <- user_delta_cycling + trip_delta_by_mode$cycling
  mode_delta_ebiking <- user_delta_ebiking + trip_delta_by_mode$ebiking
  mode_delta_pt <- user_delta_pt + trip_delta_by_mode$pt

  # Preserve the HM reference exposure and add only exposure caused by changed
  # activity. Reconstructing MMETs for every person from SP activity columns
  # would incorrectly mark unchanged individuals as counterfactual changes.
  counterfactual_data$ind$cf_user_mmet_delta <- user_delta
  counterfactual_data$ind$cf_trip_mmet_delta <- trip_delta
  counterfactual_data$ind$cf_mmet_delta_walking <- mode_delta_walking
  counterfactual_data$ind$cf_mmet_delta_cycling <- mode_delta_cycling
  counterfactual_data$ind$cf_mmet_delta_ebiking <- mode_delta_ebiking
  counterfactual_data$ind$cf_mmet_delta_pt <- mode_delta_pt
  counterfactual_data$ind$cf_mmet_delta_other_activity <- user_delta_other
  counterfactual_data$ind$cf_mmet_delta <- user_delta + trip_delta
  counterfactual_data$ind$mmets <-
    as.numeric(ref_ind$mmets[matched]) + counterfactual_data$ind$cf_mmet_delta

  counterfactual_data
}

.counterfactual_trip_mmet_delta <- function(cf_trips,
                                            ref_trips,
                                            census_ids,
                                            constants) {
  rowSums(.counterfactual_trip_mmet_delta_by_mode(
    cf_trips = cf_trips,
    ref_trips = ref_trips,
    census_ids = census_ids,
    constants = constants
  ))
}

.counterfactual_trip_mmet_delta_by_mode <- function(cf_trips,
                                                     ref_trips,
                                                     census_ids,
                                                     constants) {
  out <- data.frame(
    walking = numeric(length(census_ids)),
    cycling = numeric(length(census_ids)),
    ebiking = numeric(length(census_ids)),
    pt = numeric(length(census_ids)),
    stringsAsFactors = FALSE
  )
  if (is.null(cf_trips) || is.null(ref_trips) ||
      !all(c("census_id", "nts_tripid") %in% names(cf_trips)) ||
      !all(c("census_id", "nts_tripid") %in% names(ref_trips)) ||
      !"cf_trip_exposure_source" %in% names(cf_trips)) {
    return(out)
  }

  include <- cf_trips$cf_trip_exposure_source == "trip_target"
  include[is.na(include)] <- FALSE
  if (!any(include)) {
    return(out)
  }

  active_minutes <- function(trips, mode) {
    spec <- .counterfactual_mode_spec(mode)
    values <- numeric(nrow(trips))
    if (!is.na(spec$trip_duration_col) && spec$trip_duration_col %in% names(trips)) {
      values <- suppressWarnings(as.numeric(trips[[spec$trip_duration_col]]))
    } else if ("trip_durationraw_min" %in% names(trips)) {
      values <- suppressWarnings(as.numeric(trips$trip_durationraw_min))
    }
    # Component columns can be shared. In particular, PT uses the walking
    # component but only where PT is the main mode; applying the mode filter
    # prevents ordinary walking from being counted again as PT exposure.
    values[!spec$trip_filter(trips)] <- 0
    values[!is.finite(values) | values < 0] <- 0
    values
  }

  source_census_id <- if ("cf_source_census_id" %in% names(cf_trips)) {
    as.character(cf_trips$cf_source_census_id)
  } else {
    as.character(cf_trips$census_id)
  }
  source_trip_id <- if ("cf_source_nts_tripid" %in% names(cf_trips)) {
    as.character(cf_trips$cf_source_nts_tripid)
  } else {
    as.character(cf_trips$nts_tripid)
  }
  cf_trip_key <- paste(source_census_id, source_trip_id, sep = "\r")
  ref_trip_key <- paste(ref_trips$census_id, ref_trips$nts_tripid, sep = "\r")
  ref_match <- match(cf_trip_key, ref_trip_key)
  for (mode in .miama_supported_modes()) {
    intensity <- constants[[paste0("mmet_", mode)]]
    cf_minutes <- active_minutes(cf_trips, mode)
    ref_minutes <- numeric(nrow(cf_trips))
    matched_rows <- !is.na(ref_match)
    ref_minutes[matched_rows] <- active_minutes(ref_trips, mode)[ref_match[matched_rows]]
    delta <- (cf_minutes - ref_minutes) * intensity / 60
    per_person <- stats::aggregate(
      delta[include],
      by = list(census_id = cf_trips$census_id[include]),
      FUN = sum,
      na.rm = TRUE
    )
    matched_people <- match(census_ids, per_person$census_id)
    keep <- !is.na(matched_people)
    out[[mode]][keep] <- per_person$x[matched_people[keep]]
  }

  out
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

  prefix <- "cf_trip_"
  while (any(startsWith(as.character(existing_ids), prefix), na.rm = TRUE)) {
    prefix <- paste0(prefix, "_")
  }
  new_rows$nts_tripid <- paste0(prefix, seq_len(nrow(new_rows)))
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

.validate_cf_user_target <- function(target, spec) {
  if (!is.numeric(target) || length(target) != 1 || !is.finite(target)) {
    stop("Counterfactual target for mode `", spec$mode, "` must be one finite number.", call. = FALSE)
  }

  target <- as.integer(round(target))
  if (target < 0) {
    stop("Counterfactual target for mode `", spec$mode, "` cannot be negative.", call. = FALSE)
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

  count <- convert_timeframe_value(
    target$timeframe, count, "week", datatype = "trips"
  )
  count <- as.integer(round(count))

  list(
    count = count
  )
}

# 7. Constants And Mode Specs ----

miama_counterfactual_defaults <- function(cfg = NULL) {
  cfg <- cfg %||% miama_default_config()
  intensities <- cfg$physical_activity$mmet_per_hour %||% MIAMA_MMET_PER_HOUR
  if (!"ebiking" %in% names(intensities) && "cycling" %in% names(intensities)) {
    intensities[["ebiking"]] <- intensities[["cycling"]]
  }
  if (!"pt" %in% names(intensities) && "walking" %in% names(intensities)) {
    intensities[["pt"]] <- intensities[["walking"]]
  }
  required_intensities <- c("walking", "cycling", "ebiking", "pt", "vigorous")
  if (!all(required_intensities %in% names(intensities)) ||
      any(!is.finite(as.numeric(intensities[required_intensities])))) {
    stop(
      "Configured MMET intensities must contain finite walking, cycling, e-biking, PT, and vigorous values.",
      call. = FALSE
    )
  }
  source_mode_shares <- cfg$counterfactual$trips$source_mode_shares %||% list()
  valid_source_modes <- c("walking", "cycling", "ebiking", "pt", "driving", "other")
  for (target_mode in names(source_mode_shares)) {
    shares <- source_mode_shares[[target_mode]]
    if (is.null(names(shares)) || any(!names(shares) %in% valid_source_modes) ||
        any(!is.finite(shares)) || any(shares < 0) || sum(shares) <= 0) {
      stop(
        "Configured source-mode shares for `", target_mode,
        "` must be a named, non-negative vector with a positive sum.",
        call. = FALSE
      )
    }
    source_mode_shares[[target_mode]] <- shares / sum(shares)
  }
  list(
    mmet_walking = unname(intensities[["walking"]]),
    mmet_cycling = unname(intensities[["cycling"]]),
    mmet_ebiking = unname(intensities[["ebiking"]]),
    mmet_pt = unname(intensities[["pt"]]),
    mmet_vigorous = unname(intensities[["vigorous"]]),
    walktime_wkhr_default = 1,
    cycletime_wkhr_default = 1,
    ebiketime_wkhr_default = 1,
    pttime_wkhr_default = cfg$counterfactual$modes$pt$access_walk_minutes_default / 60,
    walktime_wkhr_ex_user_default = 0,
    cycletime_wkhr_ex_user_default = 0,
    ebiketime_wkhr_ex_user_default = 0,
    pttime_wkhr_ex_user_default = 0,
    ebike_speed_kmh = cfg$counterfactual$modes$ebiking$speed_kmh,
    pt_access_walk_distance_km_default = cfg$counterfactual$modes$pt$access_walk_distance_km_default,
    pt_access_walk_minutes_default = cfg$counterfactual$modes$pt$access_walk_minutes_default,
    source_mode_shares = source_mode_shares,
    induced_trips_percent_default = cfg$counterfactual$trips$induced_trips_percent_default %||% 10,
    new_user_percent_default = cfg$counterfactual$population$new_user_percent_default %||% 10,
    default_diversion_mode = "car",
    plausible_distance_max_multiplier = 1.2,
    unsupported_mode_policy = "skip",
    spread = cfg$spread,
    population_refinement = cfg$population_refinement
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
    ebiking = "ebiketime_wkhr",
    pt = "pttime_wkhr",
    NA_character_
  )
  default_col <- switch(
    mode,
    walking = "walktime_wkhr_default",
    cycling = "cycletime_wkhr_default",
    ebiking = "ebiketime_wkhr_default",
    pt = "pttime_wkhr_default",
    NA_character_
  )
  ex_user_default_col <- switch(
    mode,
    walking = "walktime_wkhr_ex_user_default",
    cycling = "cycletime_wkhr_ex_user_default",
    ebiking = "ebiketime_wkhr_ex_user_default",
    pt = "pttime_wkhr_ex_user_default",
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
    seed_offset = seed_offset,
    proxy_mode = if (identical(mode, "ebiking")) "cycling" else NULL,
    proxy_distance_factor = 1,
    proxy_duration_factor = 1
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
  report$mmet_exposure <- .counterfactual_mmet_exposure_report(counterfactual_data$ind)
  report$comparison <- .counterfactual_comparison_report(reference_data, counterfactual_data)
  report
}

.counterfactual_mmet_exposure_report <- function(ind) {
  columns <- c(
    "cf_user_mmet_delta", "cf_trip_mmet_delta",
    "cf_mmet_delta_walking", "cf_mmet_delta_cycling",
    "cf_mmet_delta_ebiking", "cf_mmet_delta_pt",
    "cf_mmet_delta_other_activity", "cf_mmet_delta"
  )
  if (is.null(ind) || !all(columns %in% names(ind))) {
    return(data.frame(
      component = character(0), changed_individuals = integer(0),
      total_mmet_wkhr_delta = numeric(0), stringsAsFactors = FALSE
    ))
  }

  data.frame(
    component = c(
      "individual_activity", "trip_activity", "walking",
      "cycling", "ebiking", "pt", "other_activity", "total"
    ),
    changed_individuals = vapply(columns, function(column) {
      sum(is.finite(ind[[column]]) & ind[[column]] != 0)
    }, integer(1)),
    total_mmet_wkhr_delta = vapply(columns, function(column) {
      sum(ind[[column]], na.rm = TRUE)
    }, numeric(1)),
    stringsAsFactors = FALSE
  )
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
    c(
      "walktime_wkhr", "cycletime_wkhr", "ebiketime_wkhr", "pttime_wkhr",
      "sport_wkhr", "mmets", "user_walk", "user_bike", "user_ebike", "user_pt"
    ),
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
      "cf_mode_shift", "cf_induced", "cf_trip_locked"
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

.sampling_fallback_note <- function(fallback, subject = "candidate") {
  if (is.null(fallback)) return(character(0))

  paste0(
    "Sampling constraints were relaxed for ", subject, " rows: ",
    fallback$positive_weight_candidates, " positive-weight candidates were available for ",
    fallback$requested_n, " requested rows; ", fallback$relaxed_n,
    " row(s) were sampled uniformly from the remaining candidate pool."
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
