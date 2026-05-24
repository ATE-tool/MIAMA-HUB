# MIAMA-HUB Module: Input Mapping / Reference Requests
# Purpose: Translate normalized `appraisal_inputs` into the subset of inputs
#   relevant for reference-data filtering and reference-value extraction.
# Inputs: Normalized `appraisal_inputs_in`.
# Outputs: `reference_request` spec.
# Notes: Geography filters and other status-quo scoping logic should land here.
#   This is a likely adaptation point from the legacy MIAMA workflow's
#   reference-side input handling.
#
# Build the internal reference-data request spec from normalized inputs.
map_reference_requests <- function(appraisal_inputs_in) {
  assert_named_list(appraisal_inputs_in, "appraisal_inputs_in")

  list(
    geo_level = get_input_value(appraisal_inputs_in, "geo_level", default = NULL),
    geo_id = get_input_value(appraisal_inputs_in, "geo_id", default = NULL),
    res_aggregation = get_input_value(appraisal_inputs_in, "res_aggregation", default = NULL)
  )
}
