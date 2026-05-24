# MIAMA-HUB Module: API / Receive Appraisal Inputs
# Purpose: Entry point for incoming `appraisal_inputs` payloads from MIAMA-UI
#   or standalone runs.
# Inputs: Canonical `appraisal_inputs` object or compatible named list.
# Outputs: A small internal request bundle split into reference,
#   counterfactual, and results request sections.
# Notes: This file should remain one of the very small exported package APIs.
#   It should orchestrate input mapping, not contain business logic itself.
#
#' Receive Appraisal Inputs
#'
#' Top-level API placeholder that accepts a canonical `appraisal_inputs`
#' object and maps it into internal request sections.
#'
#' @param appraisal_inputs A named list of appraisal input fields or values.
#'
#' @return A named list containing normalized inputs and internal request specs.
#' @export
receive_appraisal_inputs <- function(appraisal_inputs) {
  appraisal_inputs_in <- normalize_appraisal_inputs(appraisal_inputs)

  list(
    appraisal_inputs_in = appraisal_inputs_in,
    reference_request = map_reference_requests(appraisal_inputs_in),
    counterfactual_request = map_counterfactual_requests(appraisal_inputs_in),
    results_request = map_results_requests(appraisal_inputs_in)
  )
}
