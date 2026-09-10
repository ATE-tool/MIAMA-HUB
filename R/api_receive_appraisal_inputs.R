# MIAMA-HUB Module: API / Receive Appraisal Inputs
# Purpose: Entry point for incoming `appraisal_inputs` payloads from MIAMA-UI
#   or standalone runs.
# Inputs: Canonical `appraisal_inputs` object or compatible named list.
# Outputs: A small internal request bundle split into reference,
#   counterfactual, and results request sections.
# Notes: This is a dev-facing package API for now. It is not yet a network API;
#   it is an R function that accepts the UI payload shape and exposes its values
#   to downstream MIAMA-HUB code.
#
#' Receive Appraisal Inputs
#'
#' Accept a canonical `appraisal_inputs` object from MIAMA-UI (or a compatible
#' named list), normalize it, flatten it into plain values for developer use,
#' and map it into internal request sections.
#'
#' @param appraisal_inputs A named list of appraisal input fields or values.
#'
#' @return A named list containing normalized inputs, extracted values, and
#'   internal request specs.
#' @export
receive_appraisal_inputs <- function(appraisal_inputs) {
  appraisal_inputs_in <- normalize_appraisal_inputs(appraisal_inputs)
  appraisal_input_values <- .active_tab2_input_values(extract_input_values(appraisal_inputs_in))

  list(
    appraisal_inputs_in = appraisal_inputs_in,
    appraisal_input_values = appraisal_input_values,
    reference_request = map_reference_requests(appraisal_inputs_in),
    counterfactual_request = map_counterfactual_requests(appraisal_inputs_in),
    results_request = map_results_requests(appraisal_inputs_in)
  )
}
