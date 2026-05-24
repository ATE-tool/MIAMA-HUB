# MIAMA-HUB Module: Input Mapping / Normalize Appraisal Inputs
# Purpose: Standardize incoming `appraisal_inputs` before any downstream
#   reference-data, counterfactual, or results logic is applied.
# Inputs: Raw `appraisal_inputs` payload from UI or standalone execution.
# Outputs: Normalized named list suitable for internal accessors.
# Notes: This file should eventually contain only generic normalization and
#   validation, not domain-specific scenario rules.
#
# Normalize `appraisal_inputs` into a consistent named-list payload.
normalize_appraisal_inputs <- function(appraisal_inputs) {
  if (!is.list(appraisal_inputs) || is.null(names(appraisal_inputs))) {
    stop("`appraisal_inputs` must be a named list.")
  }

  appraisal_inputs
}
