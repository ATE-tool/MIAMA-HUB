# MIAMA-HUB Module: CRA / Summarize Health Impacts
# Purpose: Convert CRA outputs into compact result summaries suitable for UI
#   return payloads.
# Inputs: Health impacts object and a `results_request`.
# Outputs: Small summary lists keyed to output needs.
# Notes: Keep this UI-facing but still package-internal; it should shape CRA
#   outputs without performing CRA itself.
#
# Placeholder for compact health impact summaries returned to the UI.
summarize_health_impacts <- function(health_impacts, results_request = list()) {
  list(
    health_impacts = health_impacts,
    results_request = results_request
  )
}
