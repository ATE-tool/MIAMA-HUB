# MIAMA-HUB Module: Shared / Object Contracts
# Purpose: Validate core package object shapes, especially the output payload
#   returned to MIAMA-UI.
# Inputs: Internal package objects and payload sections.
# Outputs: Validation side effects or informative errors.
# Notes: These checks should help keep the API boundary stable as the package
#   grows.
#
# Validates the output payload contract used by the package API.
validate_ui_return_payload <- function(
    ui_updates,
    reference_summaries,
    counterfactual_summaries,
    health_impacts,
    state
) {
  if (!is.list(ui_updates)) {
    stop("`ui_updates` must be a list.")
  }
  if (!is.list(reference_summaries)) {
    stop("`reference_summaries` must be a list.")
  }
  if (!is.list(counterfactual_summaries)) {
    stop("`counterfactual_summaries` must be a list.")
  }
  if (!is.data.frame(health_impacts)) {
    stop("`health_impacts` must be a data frame.")
  }
  if (!is.list(state)) {
    stop("`state` must be a list.")
  }

  invisible(TRUE)
}

# Infers row counts from placeholder data containers.
infer_n_rows <- function(x) {
  if (is.data.frame(x)) {
    return(nrow(x))
  }

  if (is.list(x) && "reference_data" %in% names(x) && is.data.frame(x$reference_data)) {
    return(nrow(x$reference_data))
  }

  NA_integer_
}
