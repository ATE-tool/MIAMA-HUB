# MIAMA-HUB Module: API / Refinement Profile Defaults
# Purpose: Stage row-consistent REF and CF synthpop snapshots after Tab 2 and
#   populate the Tab 3 profile defaults from those snapshots.

prepare_refinement_profile_defaults <- function(reference_data,
                                                profile,
                                                reference_request = list(),
                                                cfg = NULL,
                                                seed = 1L) {
  assert_named_list(reference_data, "reference_data")
  assert_named_list(profile, "profile")

  stage_values <- .tab2_stage_input_values(profile)
  scoped_reference <- apply_reference_appraisal_scope(
    reference_data,
    appraisal_input_values = stage_values,
    seed = seed,
    cfg = cfg
  )
  staged_counterfactual <- apply_counterfactual_ui_values(
    init_counterfactual_data(scoped_reference),
    stage_values,
    reference_data = scoped_reference,
    constants = miama_counterfactual_defaults(cfg),
    seed = seed
  )

  reference_view <- materialize_appraisal_scope(scoped_reference, "ref")
  counterfactual_view <- materialize_appraisal_scope(staged_counterfactual, "cf")
  ref_values <- extract_reference_ui_values(
    reference_view,
    reference_request,
    stage_values,
    cfg = cfg,
    spread_fallback_data = reference_data
  )
  cf_values <- extract_reference_ui_values(
    counterfactual_view,
    reference_request,
    stage_values,
    cfg = cfg,
    spread_fallback_data = reference_data
  )

  updates <- .refinement_profile_updates(
    ref_values$ui_updates,
    cf_values$ui_updates
  )
  realized_new_user_percent <- .counterfactual_realized_new_user_percent(
    staged_counterfactual$counterfactual_report
  )
  if (!is.null(realized_new_user_percent)) {
    updates$pop_new_current_perc <- realized_new_user_percent
  }
  updated_profile <- apply_refinement_defaults_to_profile(profile, updates)
  report <- attr(updated_profile, "refinement_defaults_report")
  report$reference_scope_report <- scoped_reference$reference_scope_report
  report$counterfactual_report <- staged_counterfactual$counterfactual_report
  report$realized_new_user_percent <- realized_new_user_percent
  report$seed <- as.integer(seed)
  attr(updated_profile, "refinement_defaults_report") <- report

  list(
    profile = updated_profile,
    reference_data = scoped_reference,
    counterfactual_data = staged_counterfactual,
    reference_view = reference_view,
    counterfactual_view = counterfactual_view,
    report = report
  )
}

prepare_trip_refinement_profile_defaults <- function(reference_data,
                                                     profile,
                                                     reference_request = list(),
                                                     cfg = NULL,
                                                     seed = 1L,
                                                     staged_reference_data = NULL,
                                                     staged_counterfactual_data = NULL) {
  assert_named_list(reference_data, "reference_data")
  assert_named_list(profile, "profile")

  stage_values <- .tab3_stage_input_values(profile)
  use_staged_snapshots <- !is.null(staged_reference_data) &&
    !is.null(staged_counterfactual_data)
  tab3_changed_fields <- if (use_staged_snapshots) {
    .tab3_profile_refinement_edits(profile, stage_values)
  } else {
    character(0)
  }
  tab3_changed <- length(tab3_changed_fields) > 0

  if (use_staged_snapshots && !tab3_changed) {
    # The user accepted the Tab 3 defaults. Continue with the exact REF and CF
    # snapshots produced from Tab 2; rebuilding from the geography would erase
    # trip-based differences before Tab 4 is populated.
    scoped_reference <- staged_reference_data
    staged_counterfactual <- staged_counterfactual_data
  } else if (use_staged_snapshots) {
    # Tab 3 changed the assessed people. Re-scope each existing behavioral
    # snapshot independently, preserving its trips and activity values.
    scoped_reference <- .rescope_staged_snapshot(
      staged_reference_data, stage_values, scenario = "ref",
      seed = seed, cfg = cfg
    )
    staged_counterfactual <- .rescope_staged_snapshot(
      staged_counterfactual_data, stage_values, scenario = "cf",
      seed = seed + 10000L, cfg = cfg
    )
  } else {
    # Developer/API fallback when Tab 4 staging is called without first staging
    # Tab 2. This retains the standalone behavior used by existing callers.
    scoped_reference <- apply_reference_appraisal_scope(
      reference_data,
      appraisal_input_values = stage_values,
      seed = seed,
      cfg = cfg
    )
    staged_counterfactual <- apply_counterfactual_ui_values(
      init_counterfactual_data(scoped_reference),
      stage_values,
      reference_data = scoped_reference,
      constants = miama_counterfactual_defaults(cfg),
      seed = seed
    )
  }

  reference_view <- materialize_appraisal_scope(scoped_reference, "ref")
  counterfactual_view <- materialize_appraisal_scope(staged_counterfactual, "cf")
  ref_values <- extract_reference_ui_values(
    reference_view,
    reference_request,
    stage_values,
    cfg = cfg,
    spread_fallback_data = reference_data
  )
  cf_values <- extract_reference_ui_values(
    counterfactual_view,
    reference_request,
    stage_values,
    cfg = cfg,
    spread_fallback_data = reference_data
  )

  updates <- .trip_refinement_profile_updates(
    ref_values$ui_updates,
    cf_values$ui_updates
  )
  realized_induced_percent <- .counterfactual_realized_induced_trip_percent(
    staged_counterfactual$counterfactual_report
  )
  induced_default_source <- "realized_trip_changes"
  if (is.null(realized_induced_percent)) {
    realized_induced_percent <- .profile_field_effective_value(
      profile$pop_new_current_perc,
      default = cfg$counterfactual$population$new_user_percent_default %||% 10
    )
    induced_default_source <- "current_new_user_percent"
  }
  if (!is.null(realized_induced_percent)) {
    updates$induced_trips_percent <- realized_induced_percent
  }
  updated_profile <- apply_refinement_defaults_to_profile(profile, updates)
  report <- attr(updated_profile, "refinement_defaults_report")
  report$reference_scope_report <- scoped_reference$reference_scope_report
  report$counterfactual_report <- staged_counterfactual$counterfactual_report
  report$used_staged_tab2_snapshots <- use_staged_snapshots
  report$tab3_population_rescoped <- tab3_changed
  report$tab3_rescope_trigger_fields <- tab3_changed_fields
  report$realized_induced_trips_percent <- realized_induced_percent
  report$induced_trips_percent_default_source <- induced_default_source
  report$seed <- as.integer(seed)
  attr(updated_profile, "trip_refinement_defaults_report") <- report

  list(
    profile = updated_profile,
    reference_data = scoped_reference,
    counterfactual_data = staged_counterfactual,
    reference_view = reference_view,
    counterfactual_view = counterfactual_view,
    report = report
  )
}

.counterfactual_realized_new_user_percent <- function(report) {
  changes <- report$changes %||% list()
  new_n <- 0
  affected_n <- 0

  for (change in changes) {
    if (is.null(change$delta) || !is.finite(change$delta) || change$delta <= 0) next

    split <- change$current_new_user_split
    if (is.list(split)) {
      current <- as.numeric(split$retained_current_users %||% 0)
      new <- as.numeric(split$recruited_new_users %||% 0)
      if (is.finite(current) && is.finite(new) && current + new > 0) {
        new_n <- new_n + new
        affected_n <- affected_n + current + new
      }
      next
    }

    allocation <- change$user_allocation
    if (is.list(allocation) && identical(allocation$method, "trips_per_user")) {
      equivalent <- as.numeric(allocation$equivalent_changed_users %||% 0)
      new <- as.numeric(allocation$added_new_at_users %||% 0)
      if (is.finite(equivalent) && is.finite(new) && equivalent > 0) {
        new_n <- new_n + new
        affected_n <- affected_n + equivalent
      }
    }
  }

  if (affected_n <= 0) return(NULL)
  round(100 * new_n / affected_n, 1)
}

.counterfactual_realized_induced_trip_percent <- function(report) {
  changes <- report$changes %||% list()
  induced_n <- 0
  added_n <- 0

  for (change in changes) {
    if (is.null(change$delta) || !is.finite(change$delta) || change$delta <= 0) next
    shifted <- as.numeric(change$mode_shift_n %||% 0)
    induced <- as.numeric(change$induced_n %||% 0)
    if (!is.finite(shifted) || !is.finite(induced) || shifted + induced <= 0) next
    induced_n <- induced_n + induced
    added_n <- added_n + shifted + induced
  }

  if (added_n <= 0) return(NULL)
  round(100 * induced_n / added_n, 1)
}

.profile_field_effective_value <- function(field, default = NULL) {
  if (!is_input_field(field)) return(default)
  if (isTRUE(field$is_filled) && !is.null(field$input_value)) {
    return(field$input_value)
  }
  field$default_value %||% default
}

.tab2_stage_input_values <- function(profile) {
  values <- .active_tab2_input_values(extract_input_values(profile))

  # Tab 3 and Tab 4 controls may already contain defaults or stale hidden
  # Shiny inputs. Neither tab is an upstream source while the Tab 2 snapshot
  # is being staged. In particular, `trips_number_*` (Tab 4) must not outrank
  # the `trips_count_*` values submitted in Tab 2.
  downstream_fields <- grep(
    paste0(
      "^(pop_(total|number)_(ref|cf).*_advanced|",
      "pop_spread_|pop_target_|pa_spread_|",
      "trips_number_|trips_spread_|trips_diversion_|",
      "trips_dist_value$|trips_purpose_)"
    ),
    names(values),
    value = TRUE
  )
  values[downstream_fields] <- rep(list(NULL), length(downstream_fields))

  modes <- normalize_active_modes(.ui_value(values, "modes", character(0)))
  modes <- intersect(modes, names(.miama_tab2_mode_specs()))
  for (mode in modes) {
    suffix <- .miama_mode_suffix(mode)
    assumption_field <- paste0("default_trips_per_user_per_week_", suffix)
    if (is.null(.ui_value(values, assumption_field, NULL)) &&
        is_input_field(profile[[assumption_field]])) {
      values[[assumption_field]] <- profile[[assumption_field]]$default_value
    }
    for (scenario in c("ref", "cf")) {
      source_fields <- c(
        paste0("users_count_", scenario, "_", suffix),
        paste0("pop_number_", scenario, "_", suffix, "_basic")
      )
      source <- .first_nonblank_ui_value(values, source_fields)
      if (!is.null(source)) {
        values[[paste0("pop_number_", scenario, "_", suffix, "_advanced")]] <- source
      }
    }
  }

  for (scenario in c("ref", "cf")) {
    source <- .first_nonblank_ui_value(
      values,
      paste0("pop_total_", scenario, "_basic")
    )
    if (!is.null(source)) {
      values[[paste0("pop_total_", scenario, "_advanced")]] <- source
    }
  }

  values
}

.tab3_stage_input_values <- function(profile) {
  values <- .active_tab2_input_values(extract_input_values(profile))

  # Category counts are already stored in the profile from the Tab 2 -> Tab 3
  # staging call. Reconstruct the table targets here as well as in Shiny so a
  # quick click on "Next" cannot submit the pre-refinement table values before
  # updateNumericInput() has reached the browser.
  values <- .apply_tab3_category_counts(values, profile)
  values <- .apply_tab3_percent_counts(values, profile)

  # Tab 4 controls may contain stale hidden values from an earlier visit. They
  # must not alter the Tab 3 population snapshots used to initialize Tab 4.
  tab4_fields <- grep(
    paste0(
      "^(trips_number_(total_)?(ref|cf)|trips_spread_|",
      "trips_diversion_|trips_dist_value$|trips_purpose_)"
    ),
    names(values),
    value = TRUE
  )
  values[tab4_fields] <- rep(list(NULL), length(tab4_fields))

  # Tab 2 remains authoritative for the unit supplied there. In particular, a
  # trip-based appraisal carries its REF/CF trip totals through Tab 3 while the
  # population controls refine how those trips are distributed across people.
  # The reference scoper can duplicate donor trip patterns when a smaller final
  # person scope does not contain enough physical trip rows.

  values
}

.tab3_profile_refinement_edits <- function(profile, values = extract_input_values(profile)) {
  # Refinement controls describe how the table was calculated; they are not
  # themselves evidence that its scope changed. This matters when Shiny keeps
  # a selected method such as 100% or all categories: the resulting counts are
  # unchanged and the exact Tab 2 trip quotas must continue into Tab 4.
  fields <- c(
    grep("^pop_(total|number)_(ref|cf).*_advanced$", names(profile), value = TRUE),
    grep("^(pop|pa)_spread_.*_cf_", names(profile), value = TRUE)
  )

  fields[vapply(fields, function(field_name) {
    field <- profile[[field_name]]
    if (!is_input_field(field)) return(FALSE)
    value <- .ui_value(values, field_name, NULL)
    if (is.null(value)) return(FALSE)
    comparison <- field$additional_data$default_value_backup %||%
      field$default_value
    if (is.null(comparison)) return(length(value) > 0)
    !.same_profile_value(value, comparison)
  }, logical(1))]
}

.tab3_profile_has_refinement_edits <- function(profile, values = extract_input_values(profile)) {
  length(.tab3_profile_refinement_edits(profile, values)) > 0
}

.rescope_staged_snapshot <- function(data,
                                     values,
                                     scenario = c("ref", "cf"),
                                     seed = 1L,
                                     cfg = NULL) {
  scenario <- match.arg(scenario)
  source_activity <- list()
  scope_values <- values
  modes <- normalize_active_modes(.ui_value(values, "modes", character(0)))
  modes <- intersect(modes, names(.miama_tab2_mode_specs()))

  if (identical(scenario, "cf")) {
    # Trip-derived CF users are represented by mode scope flags; their activity
    # remains on trip rows to avoid counting exposure twice. Temporarily expose
    # those flags as positive activity so the generic reference-scope sampler
    # validates against the staged CF population rather than the original REF
    # activity columns. The original activity values are restored below.
    for (mode in modes) {
      spec <- .counterfactual_mode_spec(mode)
      scope_col <- .reference_user_scope_col(mode, "cf")
      if (!is.null(spec) && !is.na(spec$activity_col) &&
          spec$activity_col %in% names(data$ind) && scope_col %in% names(data$ind)) {
        source_activity[[spec$activity_col]] <- data$ind[[spec$activity_col]]
        flagged <- .true_values(data$ind[[scope_col]])
        temporary_activity <- .as_plain_numeric(data$ind[[spec$activity_col]][flagged])
        temporary_activity[!is.finite(temporary_activity)] <- 0
        data$ind[[spec$activity_col]][flagged] <- pmax(temporary_activity, 1)
      }
    }
    scope_values$pop_total_ref_advanced <-
      .ui_value(values, "pop_total_cf_advanced", NULL)
    scope_values$pop_total_ref_basic <-
      .ui_value(values, "pop_total_cf_basic", NULL)
    for (mode in modes) {
      suffix <- .miama_mode_suffix(mode)
      scope_values[[paste0("pop_number_ref_", suffix, "_advanced")]] <-
        .ui_value(values, paste0("pop_number_cf_", suffix, "_advanced"), NULL)
      scope_values[[paste0("pop_number_ref_", suffix, "_basic")]] <-
        .ui_value(values, paste0("pop_number_cf_", suffix, "_basic"), NULL)
      scope_values[[paste0("users_count_ref_", suffix)]] <-
        .ui_value(values, paste0("users_count_cf_", suffix), NULL)
      scope_values[[paste0("trips_count_ref_", suffix)]] <-
        .ui_value(values, paste0("trips_count_cf_", suffix), NULL)
    }
  } else {
    # Counterfactual spread sliders choose who changes in CF; they must not
    # bias the independently scoped reference snapshot.
    cf_spread_fields <- grep("^pop_spread_.*_cf_", names(scope_values), value = TRUE)
    scope_values[cf_spread_fields] <- rep(list(NULL), length(cf_spread_fields))
  }

  scoped <- apply_reference_appraisal_scope(
    data,
    appraisal_input_values = scope_values,
    seed = seed,
    cfg = cfg
  )
  if (identical(scenario, "cf") && length(source_activity) > 0) {
    for (column in names(source_activity)) {
      ids <- scoped$ind$census_id
      missing <- !ids %in% data$ind$census_id
      if (any(missing) && ".miama_parent_census_id" %in% names(scoped$ind)) {
        ids[missing] <- scoped$ind$.miama_parent_census_id[missing]
      }
      scoped$ind[[column]] <- source_activity[[column]][
        match(ids, data$ind$census_id)
      ]
    }
  }
  scoped$reference_scope_report$scenario <- scenario
  scoped
}

.apply_tab3_category_counts <- function(values, profile) {
  method <- .ui_value(values, "pop_refine_method", NULL)
  field_name <- switch(
    method %||% "",
    pop_age = "pop_target_age_groups",
    pop_pa_level = "pop_target_pa_groups",
    NULL
  )
  if (is.null(field_name) || is.null(profile[[field_name]]$additional_data)) {
    return(values)
  }

  selected <- as.character(.ui_value(values, field_name, character(0)))
  if (length(selected) == 0) return(values)
  modes <- normalize_active_modes(.ui_value(values, "modes", character(0)))
  modes <- intersect(modes, names(.miama_tab2_mode_specs()))

  for (scenario in c("ref", "cf")) {
    scenario_data <- profile[[field_name]]$additional_data[[scenario]]
    selected_data <- scenario_data[intersect(selected, names(scenario_data))]
    if (length(selected_data) == 0) next

    total <- sum(vapply(selected_data, function(x) {
      suppressWarnings(as.numeric(x$pop_tot %||% NA_real_))
    }, numeric(1)), na.rm = FALSE)
    if (is.finite(total)) {
      values[[paste0("pop_total_", scenario, "_advanced")]] <- total
    }

    for (mode in modes) {
      suffix <- .miama_mode_suffix(mode)
      key <- paste0("pop_", suffix)
      mode_total <- sum(vapply(selected_data, function(x) {
        suppressWarnings(as.numeric(x[[key]] %||% NA_real_))
      }, numeric(1)), na.rm = FALSE)
      if (is.finite(mode_total)) {
        values[[paste0("pop_number_", scenario, "_", suffix, "_advanced")]] <- mode_total
      }
    }
  }

  values
}

.apply_tab3_percent_counts <- function(values, profile) {
  if (!identical(.ui_value(values, "pop_refine_method", NULL), "pop_perc")) {
    return(values)
  }
  percent <- suppressWarnings(as.numeric(.ui_value(values, "pop_target_percent", NA_real_)))
  if (length(percent) != 1L || !is.finite(percent)) return(values)
  multiplier <- max(0, min(100, percent)) / 100

  fields <- grep(
    "^pop_(total|number)_(ref|cf).*_advanced$",
    names(profile),
    value = TRUE
  )
  for (field_name in fields) {
    backup <- suppressWarnings(as.numeric(
      profile[[field_name]]$additional_data$default_value_backup %||% NA_real_
    ))
    if (length(backup) == 1L && is.finite(backup)) {
      values[[field_name]] <- round(backup * multiplier)
    }
  }
  values
}

.first_nonblank_ui_value <- function(values, fields) {
  for (field in fields) {
    value <- .ui_value(values, field, NULL)
    if (!.is_blank_cf_target(value)) return(value)
  }
  NULL
}

materialize_appraisal_scope <- function(data, scenario = c("ref", "cf")) {
  scenario <- match.arg(scenario)
  out <- data

  if (!is.null(out$ind)) {
    general_col <- paste0(scenario, "_in_scope")
    keep <- if (general_col %in% names(out$ind)) {
      .true_values(out$ind[[general_col]])
    } else {
      rep(TRUE, nrow(out$ind))
    }
    out$ind <- out$ind[keep, , drop = FALSE]

    for (mode in intersect(.miama_supported_modes(), names(.miama_tab2_mode_specs()))) {
      spec <- .miama_tab2_mode_specs()[[mode]]
      scope_col <- .reference_user_scope_col(mode, scenario)
      materialized_scope_col <- paste0(".miama_user_scope_", spec$suffix)
      if (scope_col %in% names(out$ind)) {
        out$ind[[materialized_scope_col]] <- .true_values(out$ind[[scope_col]])
      }
      if (!is.na(spec$ind_duration_col) &&
          spec$ind_duration_col %in% names(out$ind) &&
          scope_col %in% names(out$ind)) {
        outside <- !.true_values(out$ind[[scope_col]])
        out$ind[[spec$ind_duration_col]][outside] <- 0
      }
    }
  }

  if (!is.null(out$trips)) {
    general_col <- paste0(scenario, "_in_scope")
    keep <- if (general_col %in% names(out$trips)) {
      .true_values(out$trips[[general_col]])
    } else {
      rep(TRUE, nrow(out$trips))
    }
    out$trips <- out$trips[keep, , drop = FALSE]

    for (mode in intersect(.miama_supported_modes(), names(.miama_tab2_mode_specs()))) {
      spec <- .miama_tab2_mode_specs()[[mode]]
      scope_col <- .reference_trip_scope_col(mode, scenario)
      if (!scope_col %in% names(out$trips)) next
      out$trips[[paste0(".miama_trip_scope_", spec$suffix)]] <-
        .true_values(out$trips[[scope_col]])
      # PT uses the walking component columns. Zeroing them for the PT scope
      # would also erase ordinary walking trips already materialized above.
      if (identical(mode, "pt")) next
      outside <- !.true_values(out$trips[[scope_col]])
      for (column in c(spec$trip_distance_col, spec$trip_duration_col)) {
        if (!is.na(column) && column %in% names(out$trips)) {
          out$trips[[column]][outside] <- 0
        }
      }
    }
  }

  out
}

.refinement_profile_updates <- function(ref_updates, cf_updates) {
  keep_ref <- grepl(
    paste0(
      "^(pop_total_ref_(basic|advanced)|pop_number_ref_.*_(basic|advanced)|",
      "pop_spread_.*_ref_.*|pa_spread_bars_ref_.*|",
      "pop_target_age_groups|pop_target_pa_groups)$"
    ),
    names(ref_updates)
  )
  updates <- ref_updates[keep_ref]

  for (field_name in c("pop_target_age_groups", "pop_target_pa_groups")) {
    if (is.list(ref_updates[[field_name]]) && is.list(cf_updates[[field_name]])) {
      updates[[field_name]] <- list(
        ref = ref_updates[[field_name]],
        cf = cf_updates[[field_name]]
      )
    }
  }

  mappings <- c(
    pop_total_ref_basic = "pop_total_cf_basic",
    pop_total_ref_advanced = "pop_total_cf_advanced"
  )
  mode_ref <- grep(
    "^pop_number_ref_.*_(basic|advanced)$",
    names(cf_updates),
    value = TRUE
  )
  mappings <- c(mappings, stats::setNames(
    sub("_ref_", "_cf_", mode_ref, fixed = TRUE),
    mode_ref
  ))
  slider_ref <- grep(
    "^(pop_spread_(age_mean|sex_prop|pa_mean|pa_sex_prop)_ref_)",
    names(cf_updates),
    value = TRUE
  )
  mappings <- c(mappings, stats::setNames(
    sub("_ref_", "_cf_", slider_ref, fixed = TRUE),
    slider_ref
  ))

  for (source in names(mappings)) {
    if (!is.null(cf_updates[[source]])) {
      updates[[mappings[[source]]]] <- cf_updates[[source]]
    }
  }
  updates
}

.trip_refinement_profile_updates <- function(ref_updates, cf_updates) {
  ref_fields <- grep(
    paste0(
      "^(trips_number_total_ref|trips_number_ref_|",
      "trips_spread_(bars|mean|util_prop)_ref_|",
      "trips_diversion_sources_)"
    ),
    names(ref_updates),
    value = TRUE
  )
  updates <- ref_updates[ref_fields]

  cf_sources <- grep(
    "^(trips_number_total_ref|trips_number_ref_|trips_spread_(mean|util_prop)_ref_)",
    names(cf_updates),
    value = TRUE
  )
  for (source in cf_sources) {
    target <- .reference_cf_field(source)
    if (!is.na(target)) updates[[target]] <- cf_updates[[source]]
  }
  updates
}

apply_refinement_defaults_to_profile <- function(profile, updates) {
  out <- profile
  updated <- reset <- skipped <- character(0)

  for (field_name in names(updates)) {
    if (!field_name %in% names(out) || !is_input_field(out[[field_name]])) {
      skipped <- c(skipped, field_name)
      next
    }

    field <- out[[field_name]]
    if (.refinement_field_resets_input(field_name)) {
      # Preserve the canonical field shape. `$<- NULL` would delete the list
      # element, causing later schema accessors to treat the whole field as a
      # submitted value.
      field["input_value"] <- list(NULL)
      field$is_filled <- FALSE
      reset <- c(reset, field_name)
    }

    if ("additional_data" %in% names(field) &&
        !.profile_field_has_default_backup(field)) {
      if (.profile_field_has_scenario_additional_data(field)) {
        field$additional_data$ref <- updates[[field_name]]$ref
        field$additional_data$cf <- updates[[field_name]]$cf
      } else {
        field$additional_data <- updates[[field_name]]
      }
    } else {
      field$default_value <- updates[[field_name]]
      if (.profile_field_has_default_backup(field)) {
        field$additional_data$default_value_backup <- updates[[field_name]]
      }
    }
    out[[field_name]] <- field
    updated <- c(updated, field_name)
  }

  attr(out, "refinement_defaults_report") <- list(
    updated_fields = unique(updated),
    reset_input_fields = unique(reset),
    skipped_fields = unique(skipped)
  )
  out
}

.refinement_field_resets_input <- function(field_name) {
  grepl(
    paste0(
      "^pop_(total|number)_(ref|cf).*_advanced$|",
      "^trips_number_(total_)?(ref|cf)|",
      "^trips_spread_(mean|util_prop)_(ref|cf)_"
    ),
    field_name
  )
}

.drop_unmodified_advanced_population_values <- function(values, profile) {
  fields <- grep(
    "^pop_(total|number)_(ref|cf).*_advanced$",
    intersect(names(values), names(profile)),
    value = TRUE
  )
  for (field_name in fields) {
    field <- profile[[field_name]]
    if (!is_input_field(field) || is.null(field$input_value)) next
    default <- field$default_value
    if (.same_profile_value(field$input_value, default)) {
      values[[field_name]] <- NULL
    }
  }
  values
}

# Shiny submits rendered Tab 4 count controls even when the user has not edited
# them. In an advanced appraisal those fields otherwise outrank the Tab 2 trip
# representation (including mode shares) and can turn a real Tab 2 change into
# a no-change result. This cleaner is therefore limited to callers that have
# not completed the advanced Tab 3/4 staging lifecycle. Once Tab 4 exists, its
# displayed values are the final contract, including accepted generated values.
.drop_unmodified_trip_refinement_values <- function(values, profile) {
  fields <- grep(
    "^trips_number_(total_)?(ref|cf)(_|$)",
    intersect(names(values), names(profile)),
    value = TRUE
  )
  for (field_name in fields) {
    field <- profile[[field_name]]
    if (!is_input_field(field) || is.null(field$input_value)) next
    if (.same_profile_value(field$input_value, field$default_value)) {
      values[[field_name]] <- NULL
    }
  }
  values
}

.same_profile_value <- function(x, y) {
  if (is.null(x) || is.null(y)) return(FALSE)
  isTRUE(all.equal(x, y, check.attributes = FALSE)) ||
    isTRUE(all.equal(suppressWarnings(as.numeric(x)), suppressWarnings(as.numeric(y))))
}
