# MIAMA-HUB Module: Reference Data / Filter Reference Data
# Purpose: Trim `reference_data_raw` to the relevant geography, population, or
#   trip scope implied by the current appraisal.
# Inputs: Joined reference data and a `reference_request` spec.
# Outputs: Filtered `reference_data`.
# Notes: This layer should mainly affect rows and columns on the status-quo
#   data, not create counterfactual changes.
#
# Placeholder for filtering joined reference data to the current appraisal.
filter_reference_data <- function(reference_data_raw, reference_request = list()) {
  list(
    reference_data = reference_data_raw,
    reference_request = reference_request
  )
}
