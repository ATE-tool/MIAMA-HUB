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
# Current first-pass scope:
# - `users_count_cf_*` and `pop_number_cf_*` manipulate individual-level active
#   travel user counts for walking and cycling.
# - For a target above the current count, selected current non-users become
#   `new_users`; their mode activity is sampled from the reference users'
#   observed activity distribution.
# - For a target below the current count, selected current users become
#   `ex_users`; their mode activity is sampled from current non-users, which is
#   usually zero.
# - If `mmets` is present, it is recalculated from walking, cycling, and sport
#   weekly hours using HM constants.
# - If trip-level data is present, changed individual activity columns are
#   mirrored onto matching trip rows. Trip-specific rows/columns are not yet
#   generated or shifted.
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
    .apply_cf_active_user_count_handler
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

  modes <- .ui_value(appraisal_input_values, "modes", character(0))
  if (length(modes) == 0) {
    modes <- names(.miama_tab2_mode_specs())
  }

  list(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    values = appraisal_input_values,
    constants = constants,
    seed = seed,
    modes = modes
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
      seed = context$seed
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

.apply_cf_user_count_for_mode <- function(
    counterfactual_data,
    reference_data,
    appraisal_input_values,
    mode,
    constants,
    seed
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
    seed = seed
  )

  counterfactual_data <- assignment$counterfactual_data
  counterfactual_data <- .recalculate_counterfactual_mmets(counterfactual_data, constants)
  counterfactual_data <- .mirror_ind_activity_to_trips(counterfactual_data, spec$activity_col)

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

  list(
    counterfactual_data = counterfactual_data,
    changes = list(change),
    notes = character(0)
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
    seed
) {
  if (delta == 0) {
    return(list(
      counterfactual_data = counterfactual_data,
      changed_rows = integer(0),
      role = "unchanged",
      donor_source = "reference_data"
    ))
  }

  if (delta > 0) {
    changed_rows <- .sample_rows(which(!cf_users), delta, seed + spec$seed_offset)
    replacement_values <- .sample_activity_values(
      values_ref = reference_data$ind[[spec$activity_col]][ref_users],
      n = length(changed_rows),
      default_value = constants[[spec$default_col]],
      seed = seed + spec$seed_offset + 1000L
    )
    role <- "new_users"
  } else {
    changed_rows <- .sample_rows(which(cf_users), abs(delta), seed + spec$seed_offset)
    replacement_values <- .sample_activity_values(
      values_ref = reference_data$ind[[spec$activity_col]][!ref_users],
      n = length(changed_rows),
      default_value = 0,
      seed = seed + spec$seed_offset + 2000L
    )
    role <- "ex_users"
  }

  counterfactual_data$ind[[spec$activity_col]][changed_rows] <- replacement_values

  list(
    counterfactual_data = counterfactual_data,
    changed_rows = changed_rows,
    role = role,
    donor_source = "reference_data"
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

  lookup <- counterfactual_data$ind[, c("census_id", activity_col), drop = FALSE]
  matched <- match(counterfactual_data$trips$census_id, lookup$census_id)
  counterfactual_data$trips[[activity_col]] <- lookup[[activity_col]][matched]

  counterfactual_data
}

.sample_rows <- function(candidate_rows, n, seed) {
  if (n == 0) {
    return(integer(0))
  }
  if (length(candidate_rows) < n) {
    stop("Not enough candidate rows available for requested counterfactual change.", call. = FALSE)
  }

  set.seed(seed)
  sample(candidate_rows, size = n, replace = FALSE)
}

.sample_activity_values <- function(values_ref, n, default_value, seed) {
  if (n == 0) {
    return(numeric(0))
  }

  values_ref <- values_ref[!is.na(values_ref)]
  if (length(values_ref) == 0) {
    return(rep(default_value, n))
  }

  set.seed(seed)
  sample(values_ref, size = n, replace = TRUE)
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


# 7. Constants And Mode Specs ----

miama_counterfactual_defaults <- function() {
  list(
    mmet_walking = 2.5,
    mmet_cycling = 5.8,
    mmet_vigorous = 7,
    walktime_wkhr_default = 1,
    cycletime_wkhr_default = 1,
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
    seed_offset = seed_offset
  ))
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
    changed_ind_rows = .counterfactual_changed_ind_rows(reference_data$ind, counterfactual_data$ind)
  )
}

.counterfactual_ind_comparison <- function(reference_ind, counterfactual_ind) {
  cols <- .present_cols(
    c("walktime_wkhr", "cycletime_wkhr", "sport_wkhr", "mmets"),
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
    out[[paste0(col, "_delta")]] <- out[[paste0(col, "_cf")]] - out[[paste0(col, "_ref")]]
  }

  out
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
