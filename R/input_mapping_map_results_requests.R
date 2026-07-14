# MIAMA-HUB Module: Input Mapping / Results Requests
# Purpose: Translate normalized `appraisal_inputs` into the subset of inputs
#   that control result aggregation and output selection.
# Inputs: Normalized `appraisal_inputs_in`.
# Outputs: `results_request` spec.
# Notes: This is where UI result settings such as aggregation mode should be
#   mapped into internal package requests.
#
# Build the internal results request spec from normalized inputs.
map_results_requests <- function(appraisal_inputs_in) {
  assert_named_list(appraisal_inputs_in, "appraisal_inputs_in")

  list(
    res_aggregation = get_input_value(appraisal_inputs_in, "res_aggregation", default = NULL),
    res_temp_aggregation = get_input_value(appraisal_inputs_in, "res_temp_aggregation", default = NULL),
    res_pop_aggregation = get_input_value(appraisal_inputs_in, "res_pop_aggregation", default = NULL),
    res_impact_type = get_input_value(appraisal_inputs_in, "res_impact_type", default = NULL),
    res_outcomes = get_input_value(appraisal_inputs_in, "res_outcomes", default = NULL),
    res_age_groups = get_input_value(appraisal_inputs_in, "res_age_groups", default = NULL),
    res_gender = get_input_value(appraisal_inputs_in, "res_gender", default = NULL),
    res_modes_filter = get_input_value(appraisal_inputs_in, "res_modes_filter", default = NULL)
  )
}
