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
  reference_default_fields <- c(
    heavy_reload_fields,
    "ui_version", "modes", "at_data_unit", "trips_refine_method",
    "trips_refine_choice", "ui_mode_share_show_options", "mode_share_total_unit"
  )
  reference_default_patterns <- paste0(
    "^(",
    paste(c(
      "trips_timeframe", "trips_denominator", "users_timeframe",
      "ui_dist_dur_type", "distance_unit", "duration_unit",
      "dist_dur_denominator", "dist_dur_timeframe"
    ), collapse = "|"),
    ")_"
  )
  reference_defaults_refresh <- reference_reload ||
    any(changed_fields %in% reference_default_fields) ||
    any(grepl(reference_default_patterns, changed_fields))

  if (reference_reload) {
    state$reference_sources <- NULL
    state$reference_data_raw <- NULL
    state$reference_data <- NULL
    state$reference_default_data <- NULL
  }
  refinement_upstream_fields <- c(
    heavy_reload_fields,
    "ui_version", "modes", "at_data_unit", "ui_mode_share_show_options",
    "mode_share_total_unit", "mode_share_total_trips",
    "mode_share_total_trips_basic", "mode_share_total_dist",
    "mode_share_total_dur", "mode_share_ref", "mode_share_cf"
  )
  refinement_upstream_patterns <- paste0(
    "^(users_count_(ref|cf)_|pop_(total|number)_(ref|cf).*_basic$|",
      "trips_count_(ref|cf)_|dist_dur_amount_(ref|cf)_|",
      "trips_timeframe_|trips_denominator_|users_timeframe_|",
      "ui_dist_dur_type_|distance_unit_|duration_unit_|",
      "dist_dur_denominator_|dist_dur_timeframe_)"
  )
  refinement_upstream_changed <- reference_reload ||
    any(changed_fields %in% refinement_upstream_fields) ||
    any(grepl(refinement_upstream_patterns, changed_fields))

  if (isTRUE(refinement_upstream_changed)) {
    state$refinement_reference_data <- NULL
    state$refinement_counterfactual_data <- NULL
    state$refinement_report <- NULL
  }
  if (length(changed_fields) > 0) {
    # Assumption edits rebuild CF/results but preserve accepted Tab 3/4 table
    # snapshots. Tab 2 Next explicitly stages new tables when needed.
    state$counterfactual_data <- NULL
    state$health_impacts <- NULL
    state$results_data <- NULL
  }
  if (reference_defaults_refresh) {
    state$reference_ui_values <- NULL
    state$reference_default_ui_values <- NULL
  }

  list(
    state = state,
    changed_fields = changed_fields,
    invalidated = length(changed_fields) > 0,
    reference_reload = reference_reload,
    reference_defaults_refresh = reference_defaults_refresh,
    refinement_upstream_changed = refinement_upstream_changed
  )
}
