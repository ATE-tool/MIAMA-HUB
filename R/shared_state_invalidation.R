# MIAMA-HUB Module: Shared / State Invalidation
# Purpose: Define how cached or retained HUB state should be invalidated when
#   upstream input values change.
# Inputs: Existing state and changed input fields.
# Outputs: Simple invalidation metadata or updated state bundles.
# Notes: This becomes important once repeated UI round-trips and recomputation
#   are implemented more fully.

invalidate_hub_state <- function(state = list(), changed_fields = character()) {
  assert_named_list(state, "state")

  heavy_reload_fields <- c("geo_level", "geo_id", "res_aggregation")
  reference_reload <- any(changed_fields %in% heavy_reload_fields)

  if (reference_reload) {
    state$reference_sources <- NULL
    state$reference_data_raw <- NULL
    state$reference_data <- NULL
  }
  if (length(changed_fields) > 0) {
    state$reference_ui_values <- NULL
  }

  list(
    state = state,
    changed_fields = changed_fields,
    invalidated = length(changed_fields) > 0,
    reference_reload = reference_reload
  )
}
