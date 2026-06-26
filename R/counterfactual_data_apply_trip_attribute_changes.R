# MIAMA-HUB Module: Counterfactual Data / Apply Trip Attribute Changes
# Purpose: Modify trip-level variable values in `counterfactual_data` after the
#   relevant trip rows have been selected.
# Inputs: Current counterfactual object and a `counterfactual_request` spec.
# Outputs: Updated counterfactual object with trip attribute changes.
# Notes: This is where trip-distance, duration, or mode-shift related value
#   changes should ultimately land.
#
apply_trip_attribute_changes <- function(counterfactual_data, counterfactual_request = list()) {
  assert_named_list(counterfactual_data, "counterfactual_data")
  counterfactual_data
}
