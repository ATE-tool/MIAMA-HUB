# MIAMA-HUB Module: Reference Data / Apply Appraisal Scope
# Purpose: Select the reference population, mode users, and active-mode trips
#   represented by user-entered reference values without changing their observed
#   behaviour or health exposure.
#
# The full geography remains in the object as an immutable source from which an
# assessed population is sampled. Scope flags identify that population and the
# observed mode users/trips represented by the Tab 2 values. Counterfactual
# changes are subsequently made within the same assessed population.

apply_reference_appraisal_scope <- function(reference_data,
                                             appraisal_input_values = list(),
                                             seed = 1L,
                                             cfg = NULL) {
  assert_named_list(reference_data, "reference_data")
  assert_named_list(appraisal_input_values, "appraisal_input_values")
  if (is.null(reference_data$ind)) {
    stop("Reference appraisal scope requires `reference_data$ind`.", call. = FALSE)
  }

  out <- .prepare_mode_features(reference_data)
  modes <- normalize_active_modes(.ui_value(appraisal_input_values, "modes", character(0)))
  modes <- intersect(modes, .miama_supported_modes())
  if (length(modes) == 0) modes <- .miama_supported_modes()

  tab2_conversion <- .derive_tab2_trip_count_targets(
    appraisal_input_values,
    reference_data = out,
    scenario = "ref",
    modes = modes
  )
  appraisal_input_values <- tab2_conversion$values

  user_targets <- stats::setNames(lapply(modes, function(mode) {
    .reference_user_scope_target(appraisal_input_values, .counterfactual_mode_spec(mode)$suffix)
  }), modes)
  trip_targets <- stats::setNames(lapply(modes, function(mode) {
    .reference_trip_scope_target(appraisal_input_values, .counterfactual_mode_spec(mode)$suffix)
  }), modes)
  person_target <- .reference_person_scope_target(
    appraisal_input_values,
    reference_data = out,
    modes = modes,
    user_targets = user_targets,
    trip_targets = trip_targets
  )
  population_target <- cf_population_sampling_target(
    appraisal_input_values,
    spread = cfg$spread %||% miama_default_config()$spread
  )
  eligible_people <- cf_population_candidate_filter(
    out$ind,
    seq_len(nrow(out$ind)),
    population_target,
    select_inside = TRUE
  )
  required_trip_owners <- .reference_trip_owner_requirements(
    reference_data = out,
    modes = modes,
    user_targets = user_targets,
    trip_targets = trip_targets,
    seed = seed
  )
  selected_people <- .sample_reference_people(
    out$ind,
    target_n = person_target$value,
    user_targets = user_targets,
    seed = seed,
    eligible_rows = eligible_people,
    required_rows = required_trip_owners
  )
  out$ind$ref_in_scope <- seq_len(nrow(out$ind)) %in% selected_people
  out$ind$cf_in_scope <- out$ind$ref_in_scope

  user_report <- list()
  for (mode in modes) {
    spec <- .counterfactual_mode_spec(mode)
    active <- .positive_col(out$ind, spec$activity_col)
    target <- user_targets[[mode]]
    candidates <- which(out$ind$ref_in_scope & active)
    selected <- if (is.null(target$value)) {
      candidates
    } else {
      .sample_reference_rows(candidates, target$value, seed + spec$seed_offset)
    }
    ref_col <- .reference_user_scope_col(mode, "ref")
    cf_col <- .reference_user_scope_col(mode, "cf")
    out$ind[[ref_col]] <- seq_len(nrow(out$ind)) %in% selected
    out$ind[[cf_col]] <- out$ind[[ref_col]]
    user_report[[mode]] <- list(
      field = target$field,
      requested = target$value,
      realized = length(selected),
      available_active_people = length(candidates)
    )
  }

  trip_report <- list()
  if (!is.null(out$trips)) {
    owner_scope <- out$ind$ref_in_scope[match(out$trips$census_id, out$ind$census_id)]
    owner_scope[is.na(owner_scope)] <- FALSE
    out$trips$ref_in_scope <- owner_scope
    out$trips$cf_in_scope <- owner_scope

    for (mode in modes) {
      spec <- .counterfactual_mode_spec(mode)
      if (!.trip_evidence_available_for_counterfactual(out$trips, spec)) next
      active <- spec$trip_filter(out$trips) & !is.na(out$trips$nts_tripid)
      owner_user_scope <- out$ind[[.reference_user_scope_col(mode, "ref")]][
        match(out$trips$census_id, out$ind$census_id)
      ]
      owner_user_scope[is.na(owner_user_scope)] <- FALSE
      candidates <- which(out$trips$ref_in_scope & owner_user_scope & active)
      target <- trip_targets[[mode]]
      target_rows <- if (is.null(target$value)) {
        length(candidates)
      } else {
        .reference_trip_target_rows(target)
      }
      selected <- .sample_reference_rows(candidates, target_rows, seed + spec$seed_offset + 500L)
      ref_col <- .reference_trip_scope_col(mode, "ref")
      cf_col <- .reference_trip_scope_col(mode, "cf")
      out$trips[[ref_col]] <- seq_len(nrow(out$trips)) %in% selected
      out$trips[[cf_col]] <- out$trips[[ref_col]]

      # A trip-only reference input still defines an observable mode-user
      # population. When no user count was supplied, use the owners of the
      # selected active trips so downstream Tab 3 summaries describe the same
      # scoped snapshot instead of reverting to all baseline mode users.
      if (is.null(user_targets[[mode]]$value) && !is.null(target$value)) {
        selected_ids <- unique(out$trips$census_id[selected])
        selected_users <- out$ind$ref_in_scope & out$ind$census_id %in% selected_ids
        user_ref_col <- .reference_user_scope_col(mode, "ref")
        user_cf_col <- .reference_user_scope_col(mode, "cf")
        out$ind[[user_ref_col]] <- selected_users
        out$ind[[user_cf_col]] <- selected_users
        user_report[[mode]]$field <- target$field
        user_report[[mode]]$requested <- NULL
        user_report[[mode]]$realized <- sum(selected_users)
        user_report[[mode]]$derived_from_trip_scope <- TRUE
      }
      trip_report[[mode]] <- list(
        field = target$field,
        requested = target$value,
        realized_rows = length(selected),
        available_active_rows = length(candidates)
      )
    }
  }

  out$reference_scope_report <- list(
    person = list(
      field = person_target$field,
      requested = person_target$value,
      realized = sum(out$ind$ref_in_scope),
      donor_population = nrow(out$ind),
      method = person_target$method,
      data_unit = person_target$data_unit,
      pooled_requested = person_target$pooled_requested,
      pooled_baseline = person_target$pooled_baseline,
      pooled_ratio = person_target$pooled_ratio,
      mode_estimates = person_target$mode_estimates
    ),
    users = user_report,
    trips = trip_report,
    tab2_input_conversion = tab2_conversion$report,
    population_constraints = population_target$constraints,
    seed = as.integer(seed),
    interpretation = paste(
      "Scope flags select the assessed reference snapshot; observed activity",
      "and reference health exposure are unchanged."
    )
  )
  out
}

.reference_person_scope_target <- function(values,
                                           reference_data,
                                           modes,
                                           user_targets,
                                           trip_targets) {
  default_n <- nrow(reference_data$ind)
  version <- if (identical(.ui_value(values, "ui_version", "basic"), "advanced")) "advanced" else "basic"
  fields <- if (identical(version, "advanced")) {
    c("pop_total_ref_advanced", "pop_total_ref_basic")
  } else {
    c("pop_total_ref_basic", "pop_total_ref_advanced")
  }
  explicit <- .first_reference_target(
    values, fields, default = NULL, maximum = default_n,
    label = "reference population", integer = TRUE
  )
  data_unit <- .ui_value(values, "at_data_unit", NULL)
  if (!is.null(explicit$value)) {
    explicit$method <- "explicit_population"
    explicit$data_unit <- data_unit
    explicit$pooled_requested <- NA_real_
    explicit$pooled_baseline <- NA_real_
    explicit$pooled_ratio <- NA_real_
    explicit$mode_estimates <- list()
    return(explicit)
  }

  estimates <- .reference_population_mode_estimates(
    reference_data = reference_data,
    modes = modes,
    data_unit = data_unit,
    user_targets = user_targets,
    trip_targets = trip_targets
  )
  usable <- vapply(estimates, function(x) is.finite(x$estimated_people), logical(1))
  if (!any(usable)) {
    return(list(
      field = NULL, value = default_n, method = "full_geography_fallback",
      data_unit = data_unit, pooled_requested = NA_real_,
      pooled_baseline = NA_real_, pooled_ratio = NA_real_,
      mode_estimates = estimates
    ))
  }

  # Pool the selected-mode rates observed in the source population. Summing
  # both the requested and baseline mode volumes treats a person who uses two
  # modes consistently on both sides and avoids choosing one mode as the sole
  # population anchor. Per-mode estimates remain in the report for audit.
  pooled_requested <- sum(vapply(
    estimates[usable], `[[`, numeric(1), "requested"
  ))
  pooled_baseline <- sum(vapply(
    estimates[usable], `[[`, numeric(1), "baseline"
  ))
  pooled_ratio <- pooled_requested / pooled_baseline
  target <- as.integer(round(default_n * pooled_ratio))
  specified_users <- vapply(user_targets, function(x) x$value %||% 0, numeric(1))
  # A pooled estimate can only be operational if it contains every explicitly
  # entered mode-user count.
  target <- max(target, specified_users, 0)
  if (target > default_n) {
    stop(
      "Tab 2 reference values imply an assessed population of ", target,
      ", exceeding the available donor population of ", default_n, ".",
      call. = FALSE
    )
  }

  list(
    field = NULL,
    value = target,
    method = "pooled_source_mode_rate_population",
    data_unit = data_unit,
    pooled_requested = pooled_requested,
    pooled_baseline = pooled_baseline,
    pooled_ratio = pooled_ratio,
    mode_estimates = estimates
  )
}

.reference_population_mode_estimates <- function(reference_data,
                                                 modes,
                                                 data_unit,
                                                 user_targets,
                                                 trip_targets) {
  n_people <- nrow(reference_data$ind)
  out <- stats::setNames(vector("list", length(modes)), modes)

  for (mode in modes) {
    spec <- .counterfactual_mode_spec(mode)
    suffix <- spec$suffix
    use_users <- identical(data_unit, "users")
    use_trips <- data_unit %in% c("trips", "distance", "mode_share")
    if (is.null(data_unit) || !nzchar(data_unit)) {
      use_users <- !is.null(user_targets[[mode]]$value)
      use_trips <- !use_users && !is.null(trip_targets[[mode]]$value)
    }

    if (use_users && !is.null(user_targets[[mode]]$value)) {
      baseline <- sum(.positive_col(reference_data$ind, spec$activity_col))
      requested <- user_targets[[mode]]$value
      ratio <- if (baseline > 0) requested / baseline else NA_real_
      out[[mode]] <- list(
        mode = mode, source = "users", field = user_targets[[mode]]$field,
        requested = requested, baseline = baseline, ratio = ratio,
        estimated_people = n_people * ratio
      )
      next
    }

    if (use_trips && !is.null(trip_targets[[mode]]$value) &&
        !is.null(reference_data$trips) &&
        .trip_evidence_available_for_counterfactual(reference_data$trips, spec)) {
      target <- trip_targets[[mode]]
      if (identical(target$denominator, "mean")) {
        stop("Reference trip scope with a mean denominator is not implemented; provide a total.", call. = FALSE)
      }
      active <- spec$trip_filter(reference_data$trips) &
        !is.na(reference_data$trips$nts_tripid)
      baseline <- sum(active, na.rm = TRUE)
      requested <- convert_timeframe_value(
        target$timeframe, target$value, "week", datatype = "trips"
      )
      ratio <- if (baseline > 0) requested / baseline else NA_real_
      out[[mode]] <- list(
        mode = mode, source = "trips", field = target$field,
        requested = requested, baseline = baseline, ratio = ratio,
        estimated_people = n_people * ratio
      )
      next
    }

    out[[mode]] <- list(
      mode = mode, source = data_unit %||% "unavailable", field = NULL,
      requested = NA_real_, baseline = NA_real_, ratio = NA_real_,
      estimated_people = NA_real_
    )
  }
  out
}

.reference_user_scope_target <- function(values, suffix) {
  version <- if (identical(.ui_value(values, "ui_version", "basic"), "advanced")) "advanced" else "basic"
  fields <- if (identical(version, "advanced")) {
    c(
      paste0("pop_number_ref_", suffix, "_advanced"),
      paste0("users_count_ref_", suffix),
      paste0("pop_number_ref_", suffix, "_basic")
    )
  } else {
    c(paste0("users_count_ref_", suffix), paste0("pop_number_ref_", suffix, "_basic"))
  }
  .first_reference_target(values, fields, default = NULL,
                          label = paste(suffix, "reference users"), integer = TRUE)
}

.reference_trip_owner_requirements <- function(reference_data,
                                               modes,
                                               user_targets,
                                               trip_targets,
                                               seed) {
  if (is.null(reference_data$trips)) return(integer(0))
  required_ids <- vector(mode = typeof(reference_data$ind$census_id))

  for (mode in modes) {
    # When an explicit user scope exists, trip selection is intentionally
    # nested inside it. Trip-only input instead needs selected trip owners to be
    # present in the inferred person scope before mode users can be derived.
    if (!is.null(user_targets[[mode]]$value) || is.null(trip_targets[[mode]]$value)) next
    spec <- .counterfactual_mode_spec(mode)
    if (!.trip_evidence_available_for_counterfactual(reference_data$trips, spec)) next
    active <- spec$trip_filter(reference_data$trips) &
      !is.na(reference_data$trips$nts_tripid)
    target_rows <- .reference_trip_target_rows(trip_targets[[mode]])
    available_rows <- sum(active, na.rm = TRUE)
    if (target_rows > available_rows) {
      stop(
        "Reference trip target `", trip_targets[[mode]]$field, "` for mode `",
        mode, "` requests ", target_rows, " rows per reference week, but only ",
        available_rows, " eligible baseline rows are available. ",
        "Reduce the reference value or rebuild the reference defaults for the current geography.",
        call. = FALSE
      )
    }
    selected <- .sample_reference_rows(
      which(active), target_rows, seed + spec$seed_offset + 400L
    )
    required_ids <- c(required_ids, reference_data$trips$census_id[selected])
  }

  unique(match(unique(required_ids), reference_data$ind$census_id, nomatch = 0L)) |>
    setdiff(0L)
}

.reference_trip_scope_target <- function(values, suffix) {
  tab2_field <- paste0("trips_count_ref_", suffix)
  tab4_field <- paste0("trips_number_ref_", suffix)
  advanced <- identical(.ui_value(values, "ui_version", "basic"), "advanced")
  fields <- if (advanced) c(tab4_field, tab2_field) else c(tab2_field, tab4_field)
  target <- .first_reference_target(values, fields, default = NULL, label = paste(suffix, "reference trips"))
  from_tab4 <- identical(target$field, tab4_field)
  target$timeframe <- if (from_tab4) {
    "week"
  } else {
    .ui_value(values, paste0("trips_timeframe_", suffix), "week")
  }
  target$denominator <- if (from_tab4) {
    "total"
  } else {
    .ui_value(values, paste0("trips_denominator_", suffix), "total")
  }
  target
}

.first_reference_target <- function(values,
                                    fields,
                                    default = NULL,
                                    maximum = Inf,
                                    label,
                                    integer = FALSE) {
  for (field in unique(fields)) {
    value <- .ui_value(values, field, NULL)
    if (.is_blank_cf_target(value)) next
    value <- suppressWarnings(as.numeric(value))
    if (length(value) != 1 || !is.finite(value) || value < 0) {
      stop("`", field, "` must be one finite non-negative number.", call. = FALSE)
    }
    if (isTRUE(integer)) value <- as.integer(round(value))
    if (value > maximum) {
      stop("Requested ", label, " (", value, ") exceeds the available donor population (", maximum, ").", call. = FALSE)
    }
    return(list(field = field, value = value))
  }
  list(field = NULL, value = default)
}

.sample_reference_people <- function(ind,
                                     target_n,
                                     user_targets,
                                     seed,
                                     eligible_rows = seq_len(nrow(ind)),
                                     required_rows = integer(0)) {
  n <- nrow(ind)
  target_n <- as.integer(target_n)
  eligible <- seq_len(n) %in% eligible_rows
  if (target_n > sum(eligible)) {
    stop(
      "The requested reference population (", target_n,
      ") exceeds the ", sum(eligible),
      " people eligible under the selected Tab 3 population categories.",
      call. = FALSE
    )
  }
  required_rows <- intersect(unique(required_rows), which(eligible))
  if (length(required_rows) > target_n) {
    stop(
      "The selected reference trips require ", length(required_rows),
      " unique owners, exceeding the inferred reference population of ",
      target_n, ".",
      call. = FALSE
    )
  }
  if (target_n == n && all(eligible)) return(seq_len(n))
  active <- lapply(names(user_targets), function(mode) {
    .positive_col(ind, .counterfactual_mode_spec(mode)$activity_col) & eligible
  })
  names(active) <- names(user_targets)
  specified <- names(user_targets)[!vapply(user_targets, function(x) is.null(x$value), logical(1))]
  if (length(specified) == 0) {
    return(c(required_rows, .sample_reference_rows(
      setdiff(which(eligible), required_rows),
      target_n - length(required_rows),
      seed
    )))
  }

  requested <- vapply(user_targets[specified], `[[`, numeric(1), "value")
  if (any(requested > target_n)) {
    stop("Reference user count cannot exceed reference population size.", call. = FALSE)
  }

  # Build a person scope with enough observed users to satisfy every requested
  # mode margin. Prioritizing rows that satisfy several outstanding margins
  # preserves real cross-mode overlap and works for any subset of four modes.
  selected <- required_rows
  availability <- vapply(specified, function(mode) sum(active[[mode]]), numeric(1))
  if (any(requested > availability)) {
    stop("Reference mode-user targets exceed the available donor populations.", call. = FALSE)
  }
  mode_order <- specified[order(requested / pmax(availability, 1), decreasing = TRUE)]
  for (index in seq_along(mode_order)) {
    mode <- mode_order[[index]]
    deficit <- requested[[mode]] - sum(active[[mode]][selected])
    if (deficit <= 0) next

    candidates <- which(eligible & active[[mode]] & !seq_len(n) %in% selected)
    outstanding <- mode_order[vapply(mode_order, function(candidate_mode) {
      requested[[candidate_mode]] > sum(active[[candidate_mode]][selected])
    }, logical(1))]
    overlap_score <- if (length(outstanding) == 0) {
      rep(0, length(candidates))
    } else {
      Reduce(`+`, lapply(outstanding, function(candidate_mode) {
        as.integer(active[[candidate_mode]][candidates])
      }))
    }
    set.seed(seed + index)
    candidates <- candidates[order(-overlap_score, stats::runif(length(candidates)))]
    selected <- unique(c(selected, utils::head(candidates, deficit)))
  }

  unmet <- vapply(specified, function(mode) {
    requested[[mode]] - sum(active[[mode]][selected])
  }, numeric(1))
  if (any(unmet > 0) || length(selected) > target_n) {
    stop(
      "Reference population/user targets cannot be jointly sampled from the available donor overlap.",
      call. = FALSE
    )
  }

  c(selected, .sample_reference_rows(
    setdiff(which(eligible), selected),
    target_n - length(selected),
    seed + 10L
  ))
}

.sample_reference_rows <- function(rows, n, seed) {
  n <- as.integer(n)
  if (n == 0L) return(integer(0))
  if (n < 0L || length(rows) < n) {
    stop("Not enough eligible baseline rows to construct the requested reference scope.", call. = FALSE)
  }
  if (length(rows) == 1L) return(rows)
  set.seed(seed)
  sample(rows, n, replace = FALSE)
}

.reference_trip_target_rows <- function(target) {
  value <- target$value
  if (identical(target$denominator, "mean")) {
    stop("Reference trip scope with a mean denominator is not implemented; provide a total.", call. = FALSE)
  }
  weekly <- convert_timeframe_value(target$timeframe, value, "week", datatype = "trips")
  as.integer(round(weekly))
}

.reference_user_scope_col <- function(mode, scenario = c("ref", "cf")) {
  paste0(match.arg(scenario), "_user_scope_", .counterfactual_mode_spec(mode)$suffix)
}

.reference_trip_scope_col <- function(mode, scenario = c("ref", "cf")) {
  paste0(match.arg(scenario), "_trip_scope_", .counterfactual_mode_spec(mode)$suffix)
}
