# MIAMA-HUB Module: Counterfactual Data / Apply Individual Row Changes
# Purpose: Apply inclusion/exclusion logic to individual-level rows in
#   `counterfactual_data`.
# Inputs: Current counterfactual object and a `counterfactual_request` spec.
# Outputs: Updated counterfactual object with individual row changes applied.
# Notes: This should capture "who is affected" logic, distinct from changing
#   variable values on already-selected individuals.
#
apply_ind_rows_changes <- function(counterfactual_data, counterfactual_request = list()) {
  assert_named_list(counterfactual_data, "counterfactual_data")
  counterfactual_data
}
