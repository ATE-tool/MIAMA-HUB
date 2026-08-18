# MIAMA-HUB Module: API / Reference Profile Defaults
# Purpose: Insert HUB-derived reference values into a MIAMA-UI profile object.
#
# MIAMA-UI stores the active appraisal profile as a canonical parameter list.
# User-entered values live in `input_value` when `is_filled = TRUE`. Reference
# values that pre-populate UI fields should instead be written to
# `default_value`, so they remain distinguishable from submitted user inputs.
# Mode-specific spread sliders are paired: HUB writes the observed value to the
# `_ref_` field and mirrors it to the corresponding `_cf_` field's
# `default_value`. This gives the counterfactual slider a no-change starting
# point without marking it as user-filled or overwriting a submitted value.
# Numeric category metadata for the basic population refinements is written to
# `additional_data`, preserving the categorical `default_value` selections.

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

    if (field_name %in% c("pop_target_age_groups", "pop_target_pa_groups")) {
      out[[field_name]]$additional_data <- ui_updates[[field_name]]
    } else {
      out[[field_name]]$default_value <- ui_updates[[field_name]]
    }
    updated <- c(updated, field_name)
  }

  mirrored <- .apply_reference_spread_defaults_to_cf(out, ui_updates)
  out <- mirrored$profile
  updated <- unique(c(updated, mirrored$updated_fields))

  attr(out, "reference_defaults_report") <- list(
    updated_fields = updated,
    mirrored_cf_fields = mirrored$updated_fields,
    mirrored_cf_sources = mirrored$sources,
    skipped_fields = skipped,
    excluded_fields = filtered_updates$excluded_fields,
    n_updated = length(updated),
    n_skipped = length(skipped),
    n_excluded = length(filtered_updates$excluded_fields),
    default_context = filtered_updates$context
  )

  out
}

.apply_reference_spread_defaults_to_cf <- function(profile, ui_updates) {
  out <- profile
  ref_fields <- names(ui_updates)
  cf_fields <- .reference_spread_cf_field(ref_fields)
  matched <- !is.na(cf_fields) & cf_fields %in% names(out)

  updated <- character(0)
  sources <- stats::setNames(character(0), character(0))
  for (index in which(matched)) {
    cf_field <- cf_fields[[index]]
    ref_field <- ref_fields[[index]]
    if (!is_input_field(out[[cf_field]])) {
      next
    }

    out[[cf_field]]$default_value <- ui_updates[[ref_field]]
    updated <- c(updated, cf_field)
    sources[[cf_field]] <- ref_field
  }

  list(
    profile = out,
    updated_fields = updated,
    sources = sources
  )
}

.reference_spread_cf_field <- function(field_name) {
  supported <- paste0(
    "^(pop_spread_(age_mean|sex_prop|pa_mean|pa_sex_prop)|",
    "trips_spread_(mean|util_prop))_ref_(walk|bike|ebike|pt)$"
  )
  matched <- grepl(supported, field_name)
  out <- rep(NA_character_, length(field_name))
  out[matched] <- sub("_ref_", "_cf_", field_name[matched], fixed = TRUE)
  out
}

.filter_reference_defaults_for_profile <- function(profile, ui_updates) {
  values <- extract_input_values(profile)

  list(
    ui_updates = ui_updates,
    excluded_fields = character(0),
    context = list(
      ui_version = .reference_default_value(values, "ui_version", "basic"),
      at_data_unit = .reference_default_value(values, "at_data_unit", "trips"),
      trips_refine_method = .reference_default_value(values, "trips_refine_method", NULL),
      modes = normalize_active_modes(.reference_default_value(values, "modes", character(0))),
      selected_mode_suffixes = .reference_default_mode_suffixes(
        normalize_active_modes(.reference_default_value(values, "modes", character(0)))
      ),
      conditional_filter_applied = FALSE,
      strategy = "broad_reference_defaults"
    )
  )
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
