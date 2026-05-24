# MIAMA-HUB Module: Input Mapping / Counterfactual Requests
# Purpose: Translate normalized `appraisal_inputs` into the subset of inputs
#   needed to build counterfactual row and attribute change specs.
# Inputs: Normalized `appraisal_inputs_in`.
# Outputs: `counterfactual_request` spec.
# Notes: Keep this focused on request/spec construction. Actual data
#   manipulation belongs in the counterfactual-data files.
#
# Build the internal counterfactual request spec from normalized inputs.
map_counterfactual_requests <- function(appraisal_inputs_in) {
  assert_named_list(appraisal_inputs_in, "appraisal_inputs_in")

  list(
    individual_row_changes = list(),
    individual_attribute_changes = list(),
    trip_row_changes = list(),
    trip_attribute_changes = list()
  )
}
