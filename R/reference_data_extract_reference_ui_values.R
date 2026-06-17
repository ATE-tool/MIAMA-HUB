# MIAMA-HUB Module: Reference Data / Extract Reference UI Values
# Purpose: Derive compact values from `reference_data` to pre-populate or
#   update UI fields in MIAMA-UI.
# Inputs: Filtered `reference_data` and a `reference_request` spec.
# Outputs: Compact UI updates and related reference-side values.
# Notes: This should be a major interface back to the UI during intermediate
#   steps, and should return small objects rather than datasets.

extract_reference_ui_values <- function(reference_data, reference_request = list()) {
  assert_named_list(reference_data, "reference_data")

  population_size <- if (!is.null(reference_data$ind)) nrow(reference_data$ind) else NA_integer_

  list(
    reference_request = reference_request,
    ui_updates = list(
      pop_total_ref = population_size
    )
  )
}
