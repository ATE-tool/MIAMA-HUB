# MIAMA-HUB Module: API / Reference Profile Defaults
# Purpose: Insert HUB-derived reference values into a MIAMA-UI profile object.
#
# MIAMA-UI stores the active appraisal profile as a canonical parameter list.
# User-entered values live in `input_value` when `is_filled = TRUE`. Reference
# values that pre-populate UI fields should instead be written to
# `default_value`, so they remain distinguishable from submitted user inputs.

apply_reference_defaults_to_profile <- function(profile, ui_updates) {
  assert_named_list(profile, "profile")
  assert_named_list(ui_updates, "ui_updates")

  out <- profile
  filtered_updates <- .filter_reference_defaults_for_profile(profile, ui_updates)
  ui_updates <- filtered_updates$ui_updates
  updated <- character(0)
  skipped <- character(0)

  for (field_name in names(ui_updates)) {
    if (!field_name %in% names(out) || !is_input_field(out[[field_name]])) {
      skipped <- c(skipped, field_name)
      next
    }

    out[[field_name]]$default_value <- ui_updates[[field_name]]
    updated <- c(updated, field_name)
  }

  attr(out, "reference_defaults_report") <- list(
    updated_fields = updated,
    skipped_fields = skipped,
    excluded_fields = filtered_updates$excluded_fields,
    n_updated = length(updated),
    n_skipped = length(skipped),
    n_excluded = length(filtered_updates$excluded_fields),
    default_context = filtered_updates$context
  )

  out
}

.filter_reference_defaults_for_profile <- function(profile, ui_updates) {
  values <- extract_input_values(profile)
  control_fields <- intersect(c("ui_version", "at_data_unit", "modes", "trips_refine_method"), names(values))
  has_control_values <- any(!vapply(values[control_fields], is.null, logical(1)))
  if (!isTRUE(has_control_values)) {
    return(list(
      ui_updates = ui_updates,
      excluded_fields = character(0),
      context = list(
        ui_version = NULL,
        at_data_unit = NULL,
        trips_refine_method = NULL,
        modes = character(0),
        selected_mode_suffixes = character(0),
        conditional_filter_applied = FALSE
      )
    ))
  }

  ui_version <- .reference_default_value(values, "ui_version", "basic")
  at_data_unit <- .reference_default_value(values, "at_data_unit", "trips")
  trips_refine_method <- .reference_default_value(values, "trips_refine_method", NULL)
  modes <- normalize_active_modes(.reference_default_value(values, "modes", character(0)))
  selected_suffixes <- .reference_default_mode_suffixes(modes)

  keep <- vapply(names(ui_updates), function(field_name) {
    .reference_default_field_is_relevant(
      field_name = field_name,
      ui_version = ui_version,
      at_data_unit = at_data_unit,
      trips_refine_method = trips_refine_method,
      selected_suffixes = selected_suffixes
    )
  }, logical(1))

  list(
    ui_updates = ui_updates[keep],
    excluded_fields = names(ui_updates)[!keep],
    context = list(
      ui_version = ui_version,
      at_data_unit = at_data_unit,
      trips_refine_method = trips_refine_method,
      modes = modes,
      selected_mode_suffixes = selected_suffixes,
      conditional_filter_applied = TRUE
    )
  )
}

.reference_default_field_is_relevant <- function(
    field_name,
    ui_version,
    at_data_unit,
    trips_refine_method,
    selected_suffixes
) {
  if (field_name %in% c("geo_name", "population_size", "pop_total_ref")) {
    return(TRUE)
  }

  mode_suffix <- .reference_default_field_mode_suffix(field_name)
  is_mode_share_field <- grepl("^mode_share_ref_|^mode_share_total_", field_name)
  mode_share_all_modes <- identical(at_data_unit, "mode_share") ||
    identical(trips_refine_method, "trip_diversion")

  if (!is.na(mode_suffix) && !mode_share_all_modes && length(selected_suffixes) > 0 &&
      !mode_suffix %in% selected_suffixes) {
    return(FALSE)
  }

  if (!is.na(mode_suffix) && is_mode_share_field && mode_share_all_modes) {
    mode_specific_ok <- TRUE
  } else if (!is.na(mode_suffix) && length(selected_suffixes) > 0) {
    mode_specific_ok <- mode_suffix %in% selected_suffixes
  } else {
    mode_specific_ok <- TRUE
  }

  if (!isTRUE(mode_specific_ok)) {
    return(FALSE)
  }

  if (identical(ui_version, "advanced")) {
    return(
      grepl("^pop_number_ref_|^pop_spread_", field_name) ||
        grepl("^trips_number_total_ref$|^trips_number_ref_|^trips_spread_", field_name) ||
        (identical(trips_refine_method, "trip_diversion") &&
           grepl("^trips_diversion_|^mode_share_ref_|^mode_share_total_", field_name))
    )
  }

  if (identical(at_data_unit, "users")) {
    return(grepl("^users_count_ref_", field_name))
  }
  if (identical(at_data_unit, "trips")) {
    return(grepl("^trips_count_ref_", field_name))
  }
  if (identical(at_data_unit, "distance")) {
    return(grepl("^dist_dur_amount_ref_", field_name))
  }
  if (identical(at_data_unit, "mode_share")) {
    return(grepl("^mode_share_ref_|^mode_share_total_", field_name))
  }

  FALSE
}

.reference_default_field_mode_suffix <- function(field_name) {
  prefixes <- c(
    "users_count_ref_",
    "trips_count_ref_",
    "dist_dur_amount_ref_",
    "mode_share_ref_",
    "pop_number_ref_",
    "trips_number_ref_"
  )

  for (prefix in prefixes) {
    if (startsWith(field_name, prefix)) {
      return(sub(paste0("^", prefix), "", field_name))
    }
  }

  NA_character_
}

.reference_default_mode_suffixes <- function(modes) {
  supported <- names(.miama_tab2_mode_specs())
  modes <- modes[modes %in% supported]
  unname(vapply(modes, .miama_mode_suffix, character(1)))
}

.reference_default_value <- function(values, field_name, default = NULL) {
  value <- values[[field_name]]
  if (is.null(value) || length(value) == 0 || is.na(value[1])) {
    return(default)
  }

  value
}
