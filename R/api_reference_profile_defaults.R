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
    n_updated = length(updated),
    n_skipped = length(skipped)
  )

  out
}
