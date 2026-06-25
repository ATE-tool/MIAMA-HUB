# MIAMA-HUB Dev Workflow: Inspect Reference UI Values
# Runs Step 5 for Tab 2-4 reference-value branches so generated status-quo
# values can be inspected for plausibility against the same filtered
# reference_data object.
#
# Prerequisites: same as dev_workflow.R.
#   MIAMA_PROJECT_ROOT=/path/to/MIAMA-HUB
#   MIAMA_HM_ROOT=/path/to/MIAMA-HM

# 0. Setup ----
# -----------------------------------------------------------------------------#

devtools::load_all()

cfg <- miama_default_config()
cfg$workflow$dataset_size <- "sample"
cfg$cache$enabled         <- TRUE
cfg$cache$refresh         <- FALSE

base_modes <- c("walking", "cycling", "ebiking", "pt")

base_appraisal_inputs <- build_mock_appraisal_inputs(
  overrides = list(
    geo_level = list(input_value = "lad"),
    geo_id = list(input_value = "E08000035"),
    modes = list(input_value = base_modes),
    res_aggregation = list(input_value = "total")
  )
)

base_request <- receive_appraisal_inputs(base_appraisal_inputs)


# 1. Build filtered reference_data once ----
# -----------------------------------------------------------------------------#

reference_sources <- load_reference_sources(
  cfg,
  reference_request = base_request$reference_request,
  results_request = base_request$results_request
)

reference_data_raw <- join_hm_and_synthpop(reference_sources)

reference_data <- filter_reference_data(
  reference_data_raw,
  base_request$reference_request
)


# 2. Define reference-value scenarios to inspect ----
# -----------------------------------------------------------------------------#

reference_ui_scenarios <- list(
  users = list(
    at_data_unit = list(input_value = "users"),
    users_timeframe_walk = list(input_value = "year"),
    users_timeframe_bike = list(input_value = "year"),
    users_timeframe_ebike = list(input_value = "year"),
    users_timeframe_pt = list(input_value = "year")
  ),
  trips_total_year = list(
    at_data_unit = list(input_value = "trips"),
    trips_timeframe_walk = list(input_value = "year"),
    trips_timeframe_bike = list(input_value = "year"),
    trips_timeframe_ebike = list(input_value = "year"),
    trips_timeframe_pt = list(input_value = "year"),
    trips_denominator_walk = list(input_value = "total"),
    trips_denominator_bike = list(input_value = "total"),
    trips_denominator_ebike = list(input_value = "total"),
    trips_denominator_pt = list(input_value = "total")
  ),
  trips_mean_week = list(
    at_data_unit = list(input_value = "trips"),
    trips_timeframe_walk = list(input_value = "week"),
    trips_timeframe_bike = list(input_value = "week"),
    trips_timeframe_ebike = list(input_value = "week"),
    trips_timeframe_pt = list(input_value = "week"),
    trips_denominator_walk = list(input_value = "mean"),
    trips_denominator_bike = list(input_value = "mean"),
    trips_denominator_ebike = list(input_value = "mean"),
    trips_denominator_pt = list(input_value = "mean")
  ),
  distance_total_year = list(
    at_data_unit = list(input_value = "distance"),
    ui_dist_dur_type_walk = list(input_value = "distance"),
    ui_dist_dur_type_bike = list(input_value = "distance"),
    ui_dist_dur_type_ebike = list(input_value = "distance"),
    ui_dist_dur_type_pt = list(input_value = "distance"),
    distance_unit_walk = list(input_value = "km"),
    distance_unit_bike = list(input_value = "km"),
    distance_unit_ebike = list(input_value = "km"),
    distance_unit_pt = list(input_value = "km"),
    dist_dur_denominator_walk = list(input_value = "total"),
    dist_dur_denominator_bike = list(input_value = "total"),
    dist_dur_denominator_ebike = list(input_value = "total"),
    dist_dur_denominator_pt = list(input_value = "total"),
    dist_dur_timeframe_walk = list(input_value = "year"),
    dist_dur_timeframe_bike = list(input_value = "year"),
    dist_dur_timeframe_ebike = list(input_value = "year"),
    dist_dur_timeframe_pt = list(input_value = "year")
  ),
  duration_avg_per_person_week = list(
    at_data_unit = list(input_value = "distance"),
    ui_dist_dur_type_walk = list(input_value = "duration"),
    ui_dist_dur_type_bike = list(input_value = "duration"),
    ui_dist_dur_type_ebike = list(input_value = "duration"),
    ui_dist_dur_type_pt = list(input_value = "duration"),
    duration_unit_walk = list(input_value = "hours"),
    duration_unit_bike = list(input_value = "hours"),
    duration_unit_ebike = list(input_value = "hours"),
    duration_unit_pt = list(input_value = "hours"),
    dist_dur_denominator_walk = list(input_value = "average_per_person"),
    dist_dur_denominator_bike = list(input_value = "average_per_person"),
    dist_dur_denominator_ebike = list(input_value = "average_per_person"),
    dist_dur_denominator_pt = list(input_value = "average_per_person"),
    dist_dur_timeframe_walk = list(input_value = "week"),
    dist_dur_timeframe_bike = list(input_value = "week"),
    dist_dur_timeframe_ebike = list(input_value = "week"),
    dist_dur_timeframe_pt = list(input_value = "week")
  ),
  mode_share_trips = list(
    at_data_unit = list(input_value = "mode_share"),
    ui_mode_share_show_options = list(input_value = FALSE),
    mode_share_total_unit = list(input_value = "trips")
  ),
  mode_share_distance = list(
    at_data_unit = list(input_value = "mode_share"),
    ui_mode_share_show_options = list(input_value = TRUE),
    mode_share_total_unit = list(input_value = "distance")
  ),
  mode_share_duration = list(
    at_data_unit = list(input_value = "mode_share"),
    ui_mode_share_show_options = list(input_value = TRUE),
    mode_share_total_unit = list(input_value = "duration")
  ),
  population_current_age_sex = list(
    pop_refine_choice = list(input_value = "pop_age_current")
  ),
  population_new_age_sex = list(
    pop_refine_choice = list(input_value = "pop_age_new")
  ),
  population_current_pa = list(
    pop_refine_choice = list(input_value = "pop_pa_current")
  ),
  population_new_pa = list(
    pop_refine_choice = list(input_value = "pop_pa_new")
  ),
  trips_distribution = list(
    trips_refine_choice = list(input_value = "trips_distance_purpose")
  ),
  trips_diversion_simple = list(
    trips_refine_method = list(input_value = "trip_diversion"),
    ui_trips_diversion_show_options = list(input_value = FALSE)
  ),
  trips_diversion_distance = list(
    trips_refine_method = list(input_value = "trip_diversion"),
    ui_trips_diversion_show_options = list(input_value = TRUE),
    trips_diversion_basis = list(input_value = "total_distance")
  ),
  trips_diversion_duration = list(
    trips_refine_method = list(input_value = "trip_diversion"),
    ui_trips_diversion_show_options = list(input_value = TRUE),
    trips_diversion_basis = list(input_value = "total_duration")
  )
)


# 3. Extract and inspect all scenario values ----
# -----------------------------------------------------------------------------#

reference_ui_values_all <- lapply(names(reference_ui_scenarios), function(scenario_name) {
  appraisal_inputs <- utils::modifyList(
    base_appraisal_inputs,
    reference_ui_scenarios[[scenario_name]]
  )
  request <- receive_appraisal_inputs(appraisal_inputs)

  extract_reference_ui_values(
    reference_data,
    request$reference_request,
    request$appraisal_input_values
  )
})
names(reference_ui_values_all) <- names(reference_ui_scenarios)

reference_ui_update_table <- do.call(
  rbind,
  lapply(names(reference_ui_values_all), function(scenario_name) {
    updates <- reference_ui_values_all[[scenario_name]]$ui_updates
    data.frame(
      scenario = scenario_name,
      field = names(updates),
      value = unlist(updates, use.names = FALSE),
      row.names = NULL
    )
  })
)

reference_ui_extraction_notes <- lapply(reference_ui_values_all, function(x) {
  x$extraction_report[c("at_data_unit", "modes", "skipped_fields", "notes")]
})

print(reference_ui_update_table)
str(reference_ui_extraction_notes)
