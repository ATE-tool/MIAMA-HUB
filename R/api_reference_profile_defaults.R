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
