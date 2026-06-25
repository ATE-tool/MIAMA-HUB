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
    trips_timeframe_walk = list(
      is_filled = TRUE,
      description = "Time frame for the walking trips count.",
      input_value = "year"
    ),
    trips_timeframe_bike = list(
      is_filled = TRUE,
      description = "Time frame for the cycling trips count.",
      input_value = "year"
    ),
    trips_denominator_walk = list(
      is_filled = TRUE,
      description = "Whether walking trips are totals or per-person means.",
      input_value = "total"
    ),
    trips_denominator_bike = list(
      is_filled = TRUE,
      description = "Whether cycling trips are totals or per-person means.",
      input_value = "total"
    ),
    users_timeframe_walk = list(
      is_filled = TRUE,
      description = "Time frame for the walking users count.",
      input_value = "year"
    ),
    users_timeframe_bike = list(
      is_filled = TRUE,
      description = "Time frame for the cycling users count.",
      input_value = "year"
    ),
    ui_dist_dur_type_walk = list(
      is_filled = TRUE,
      description = "Whether walking distance/duration is distance or duration.",
      input_value = "distance"
    ),
    ui_dist_dur_type_bike = list(
      is_filled = TRUE,
      description = "Whether cycling distance/duration is distance or duration.",
      input_value = "distance"
    ),
    distance_unit_walk = list(
      is_filled = TRUE,
      description = "Walking distance unit.",
      input_value = "km"
    ),
    distance_unit_bike = list(
      is_filled = TRUE,
      description = "Cycling distance unit.",
      input_value = "km"
    ),
    duration_unit_walk = list(
      is_filled = TRUE,
      description = "Walking duration unit.",
      input_value = "mins"
    ),
    duration_unit_bike = list(
      is_filled = TRUE,
      description = "Cycling duration unit.",
      input_value = "mins"
    ),
    dist_dur_denominator_walk = list(
      is_filled = TRUE,
      description = "Whether walking distance/duration is total, per person, or per trip.",
      input_value = "total"
    ),
    dist_dur_denominator_bike = list(
      is_filled = TRUE,
      description = "Whether cycling distance/duration is total, per person, or per trip.",
      input_value = "total"
    ),
    dist_dur_timeframe_walk = list(
      is_filled = TRUE,
      description = "Time frame for walking distance/duration.",
      input_value = "year"
    ),
    dist_dur_timeframe_bike = list(
      is_filled = TRUE,
      description = "Time frame for cycling distance/duration.",
      input_value = "year"
    ),
    ui_mode_share_show_options = list(
      is_filled = TRUE,
      description = "Whether advanced mode-share denominator options are shown.",
      input_value = FALSE
    ),
    mode_share_total_unit = list(
      is_filled = TRUE,
      description = "Mode-share denominator unit.",
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
