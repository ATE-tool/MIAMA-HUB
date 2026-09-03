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
  updated_profile <- apply_refinement_defaults_to_profile(profile, updates)
  report <- attr(updated_profile, "refinement_defaults_report")
  report$reference_scope_report <- scoped_reference$reference_scope_report
  report$counterfactual_report <- staged_counterfactual$counterfactual_report
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
                                                     seed = 1L) {
  assert_named_list(reference_data, "reference_data")
  assert_named_list(profile, "profile")

  stage_values <- .tab3_stage_input_values(profile)
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

  updates <- .trip_refinement_profile_updates(
    ref_values$ui_updates,
    cf_values$ui_updates
  )
  updated_profile <- apply_refinement_defaults_to_profile(profile, updates)
  report <- attr(updated_profile, "refinement_defaults_report")
  report$reference_scope_report <- scoped_reference$reference_scope_report
  report$counterfactual_report <- staged_counterfactual$counterfactual_report
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

.tab2_stage_input_values <- function(profile) {
  values <- extract_input_values(profile)

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
  values <- extract_input_values(profile)

  # Category counts are already stored in the profile from the Tab 2 -> Tab 3
  # staging call. Reconstruct the table targets here as well as in Shiny so a
  # quick click on "Next" cannot submit the pre-refinement table values before
  # updateNumericInput() has reached the browser.
  values <- .apply_tab3_category_counts(values, profile)

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

  # Tab 3 is the final person/user scope presented before Tab 4. If it reduces
  # that scope, an upstream Tab 2 trip quota may no longer fit among trips owned
  # by the remaining people. Reapplying the old quota would either fail or undo
  # the population refinement. Stage this transition as a user-scope request,
  # discard only the flattened Tab 2 trip-count targets, and let Tab 4 defaults
  # be measured from the trips belonging to the final Tab 3 REF/CF snapshots.
  tab2_trip_fields <- grep(
    "^trips_count_(ref|cf)_",
    names(values),
    value = TRUE
  )
  values[tab2_trip_fields] <- rep(list(NULL), length(tab2_trip_fields))
  values$at_data_unit <- "users"

  values
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
      "^(pop_total_ref_advanced|pop_number_ref_.*_advanced|",
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
    pop_total_ref_advanced = "pop_total_cf_advanced"
  )
  mode_ref <- grep("^pop_number_ref_.*_advanced$", names(cf_updates), value = TRUE)
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
      "trips_diversion_(total_trips|trips_n|distance_total|duration_total)$)"
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

.same_profile_value <- function(x, y) {
  if (is.null(x) || is.null(y)) return(FALSE)
  isTRUE(all.equal(x, y, check.attributes = FALSE)) ||
    isTRUE(all.equal(suppressWarnings(as.numeric(x)), suppressWarnings(as.numeric(y))))
}
