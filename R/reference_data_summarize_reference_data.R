# MIAMA-HUB Module: Reference Data / Summarize Reference Data
# Purpose: Produce compact reference-side summaries for downstream payloads,
#   logging, or UI updates.
# Inputs: Filtered reference data object.
# Outputs: Small summary lists.
# Notes: Keep summaries lightweight and reusable across intermediate and final
#   outputs.
#
# Placeholder for compact summaries derived from filtered reference data.
summarize_reference_data <- function(reference_data) {
  list(
    n_rows = infer_n_rows(reference_data)
  )
}
