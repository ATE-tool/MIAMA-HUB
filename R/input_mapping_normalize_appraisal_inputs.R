# MIAMA-HUB Module: Input Mapping / Normalize Appraisal Inputs
# Purpose: Standardize incoming `appraisal_inputs` before any downstream
#   reference-data, counterfactual, or results logic is applied.
# Inputs: Raw `appraisal_inputs` payload from UI or standalone execution.
# Outputs: Normalized named list suitable for internal accessors.
# Notes: This file should contain generic normalization and light validation.
#
# Normalize `appraisal_inputs` into a consistent named-list payload.
normalize_appraisal_inputs <- function(appraisal_inputs) {
  if (!is.list(appraisal_inputs) || is.null(names(appraisal_inputs))) {
    stop("`appraisal_inputs` must be a named list.", call. = FALSE)
  }

  normalized <- appraisal_inputs

  for (nm in names(normalized)) {
    field <- normalized[[nm]]

    if (is_input_field(field)) {
      if (!"is_filled" %in% names(field)) {
        field$is_filled <- !is.null(field$input_value)
      }

      if (is.null(field$input_value) && "default_value" %in% names(field)) {
        field$input_value <- field$default_value
      }

      if (is.null(field$input_source)) {
        field$input_source <- "user"
      }

      normalized[[nm]] <- field
    }
  }

  normalized
}
