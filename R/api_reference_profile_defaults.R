# MIAMA-HUB Module: API / Reference Profile Defaults
# Purpose: Insert HUB-derived reference values into a MIAMA-UI profile object.
#
# MIAMA-UI stores the active appraisal profile as a canonical parameter list.
# User-entered values live in `input_value` when `is_filled = TRUE`. Reference
# values that pre-populate UI fields should instead be written to
# `default_value`, so they remain distinguishable from submitted user inputs.
#
# The application strategy is deliberately broad: HUB calculates all available
# reference defaults and this module writes every update that has a matching
# canonical profile field. UI selections such as `at_data_unit`, `ui_version`,
# and selected modes determine which controls are displayed; they do not filter
# which reference values HUB prepares.
#
# The returned profile carries a `reference_defaults_report` attribute for
# diagnostics. It is not an appraisal input and does not control application
# behavior. The report lists fields written to the profile, reference values
# mirrored to no-change counterfactual defaults, and calculated values that
# had no matching profile field. Development workflows and tests can inspect it
# when reconciling the HUB output with the UI schema.
#
# Paired fields are initialized consistently: HUB writes the observed value to
# the `_ref_` (or `_ref`) field and mirrors it to the corresponding `_cf_` (or
# `_cf`) field's `default_value` whenever that field exists in the profile. This
# includes user/trip counts, distance/duration values, mode share, mode-specific
# spread sliders, and basic/advanced population counts. It gives every paired
# counterfactual control a no-change starting point without marking it as
# user-filled or overwriting submitted values.
# Numeric category metadata for the basic population refinements is written to
# `additional_data`, preserving the categorical `default_value` selections.
# Advanced population count fields can declare
# `additional_data$default_value_backup`. For those fields HUB writes the
# derived reference/no-change value to both `default_value` and the backup.
# Subsequent UI refinement logic may change `default_value`, while the backup
# retains the original geography-derived value until reference defaults are
# deliberately rebuilt (for example after changing geography).

apply_reference_defaults_to_profile <- function(profile, ui_updates) {
  assert_named_list(profile, "profile")
  assert_named_list(ui_updates, "ui_updates")

  out <- profile
  updated <- character(0)
  additional_data_updated <- character(0)
  backup_updated <- character(0)
  skipped <- character(0)

  for (field_name in names(ui_updates)) {
    if (!field_name %in% names(out) || !is_input_field(out[[field_name]])) {
      skipped <- c(skipped, field_name)
      next
    }

    has_backup <- .profile_field_has_default_backup(out[[field_name]])
    if ("additional_data" %in% names(out[[field_name]]) && !has_backup) {
      if (.profile_field_has_scenario_additional_data(out[[field_name]])) {
        out[[field_name]]$additional_data$ref <- ui_updates[[field_name]]
        out[[field_name]]$additional_data$cf <- ui_updates[[field_name]]
      } else {
        out[[field_name]]$additional_data <- ui_updates[[field_name]]
      }
      additional_data_updated <- c(additional_data_updated, field_name)
    } else {
      out[[field_name]]$default_value <- ui_updates[[field_name]]
      if (has_backup) {
        out[[field_name]]$additional_data$default_value_backup <- ui_updates[[field_name]]
        backup_updated <- c(backup_updated, field_name)
      }
    }
    updated <- c(updated, field_name)
  }

  mirrored <- .apply_reference_defaults_to_cf(out, ui_updates)
  out <- mirrored$profile
  updated <- unique(c(updated, mirrored$updated_fields))
  backup_updated <- unique(c(backup_updated, mirrored$backup_fields))

  attr(out, "reference_defaults_report") <- list(
    updated_fields = updated,
    mirrored_cf_fields = mirrored$updated_fields,
    mirrored_cf_sources = mirrored$sources,
    additional_data_fields = additional_data_updated,
    default_value_backup_fields = backup_updated,
    skipped_fields = skipped,
    n_updated = length(updated),
    n_skipped = length(skipped)
  )

  out
}

.apply_reference_defaults_to_cf <- function(profile, ui_updates) {
  out <- profile
  ref_fields <- names(ui_updates)
  cf_fields <- .reference_cf_field(ref_fields)
  matched <- !is.na(cf_fields) & cf_fields %in% names(out)

  updated <- character(0)
  backup_updated <- character(0)
  sources <- stats::setNames(character(0), character(0))
  for (index in which(matched)) {
    cf_field <- cf_fields[[index]]
    ref_field <- ref_fields[[index]]
    if (!is_input_field(out[[cf_field]])) {
      next
    }

    out[[cf_field]]$default_value <- ui_updates[[ref_field]]
    if (.profile_field_has_default_backup(out[[cf_field]])) {
      out[[cf_field]]$additional_data$default_value_backup <- ui_updates[[ref_field]]
      backup_updated <- c(backup_updated, cf_field)
    }
    updated <- c(updated, cf_field)
    sources[[cf_field]] <- ref_field
  }

  list(
    profile = out,
    updated_fields = updated,
    backup_fields = backup_updated,
    sources = sources
  )
}

.profile_field_has_default_backup <- function(field) {
  is.list(field$additional_data) &&
    "default_value_backup" %in% names(field$additional_data)
}

.profile_field_has_scenario_additional_data <- function(field) {
  is.list(field$additional_data) &&
    all(c("ref", "cf") %in% names(field$additional_data))
}

.reference_cf_field <- function(field_name) {
  out <- rep(NA_character_, length(field_name))

  infix <- grepl("_ref_", field_name, fixed = TRUE)
  out[infix] <- sub("_ref_", "_cf_", field_name[infix], fixed = TRUE)

  suffix <- !infix & grepl("_ref$", field_name)
  out[suffix] <- sub("_ref$", "_cf", field_name[suffix])

  out
}
