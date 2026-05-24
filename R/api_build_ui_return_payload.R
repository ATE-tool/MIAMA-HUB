# MIAMA-HUB Module: API / Build UI Return Payload
# Purpose: Package-level output constructor for compact values returned to
#   MIAMA-UI after intermediate or final processing steps.
# Inputs: Compact UI updates, summaries, health impacts, and optional state.
# Outputs: A single named list following the HUB output contract.
# Notes: This is an exported top-level API. Keep the payload compact and avoid
#   returning large datasets to the UI by default.
#
#' Build UI Return Payload
#'
#' Top-level API placeholder that returns compact objects suitable for sending
#' back to `MIAMA-UI`.
#'
#' @param ui_updates Named list of UI-facing values.
#' @param reference_summaries Named list of compact reference summaries.
#' @param counterfactual_summaries Named list of compact CF summaries.
#' @param health_impacts Data frame of health impacts.
#' @param state Internal package state to retain between steps.
#'
#' @return A named list representing the package output contract.
#' @export
build_ui_return_payload <- function(
    ui_updates = list(),
    reference_summaries = list(),
    counterfactual_summaries = list(),
    health_impacts = data.frame(),
    state = list()
) {
  validate_ui_return_payload(
    ui_updates = ui_updates,
    reference_summaries = reference_summaries,
    counterfactual_summaries = counterfactual_summaries,
    health_impacts = health_impacts,
    state = state
  )

  list(
    ui_updates = ui_updates,
    reference_summaries = reference_summaries,
    counterfactual_summaries = counterfactual_summaries,
    health_impacts = health_impacts,
    state = state
  )
}
