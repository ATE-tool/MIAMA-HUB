# MIAMA-HUB Module: Dev Helpers / Build Mock Appraisal Inputs
# Purpose: Create a minimal canonical `appraisal_inputs` object for
#   development workflows before MIAMA-UI is wired directly into MIAMA-HUB.
# Inputs: Optional overrides supplied as a named list.
# Outputs: Canonical UI-shaped appraisal input fields with populated values.
# Notes: Keep this intentionally small and expand only as downstream modules
#   need more parameters.

build_mock_appraisal_inputs <- function(overrides = list()) {
  defaults <- list(
    geo_level = list(
      is_filled = TRUE,
      description = "Spatial resolution of the appraisal.",
      input_value = "lad"
    ),
    geo_id = list(
      is_filled = TRUE,
      description = "Identifier of the selected geographic unit.",
      input_value = "E08000035"
    ),
    modes = list(
      is_filled = TRUE,
      description = "Active travel modes included in the appraisal.",
      input_value = c("walking", "cycling")
    ),
    at_data_unit = list(
      is_filled = TRUE,
      description = "Primary data format used to quantify active travel.",
      input_value = "trips"
    ),
    res_aggregation = list(
      is_filled = TRUE,
      description = "Whether results are total or timeline outputs.",
      input_value = "total"
    ),
    res_outcomes = list(
      is_filled = TRUE,
      description = "Health outcomes included in result summaries.",
      input_value = c("mortality", "stroke", "diabetes")
    )
  )

  if (length(overrides) == 0) {
    return(defaults)
  }

  utils::modifyList(defaults, overrides)
}
