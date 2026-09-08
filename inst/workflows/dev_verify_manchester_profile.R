# Run from HUB after building the packaged Manchester profile.
# /usr/bin/time -l Rscript --vanilla inst/workflows/dev_verify_manchester_profile.R
# Leaves the completed results in `result` when sourced interactively.
pkgload::load_all(".", quiet = TRUE)
cfg <- miama_default_config("manchester")
profile <- build_mock_appraisal_inputs(overrides = list(
  geo_level = list(input_value = "lad"),
  geo_id = list(input_value = "E08000003"),
  ui_version = list(input_value = "advanced", is_filled = TRUE),
  at_data_unit = list(input_value = "trips", is_filled = TRUE),
  modes = list(input_value = c("cycling", "walking")),
  trips_timeframe_walk = list(input_value = "week"),
  trips_timeframe_bike = list(input_value = "week"),
  trips_count_ref_walk = list(input_value = 30000, is_filled = TRUE),
  trips_count_cf_walk = list(input_value = 40000, is_filled = TRUE),
  trips_count_ref_bike = list(input_value = 1000, is_filled = TRUE),
  trips_count_cf_bike = list(input_value = 1400, is_filled = TRUE)
))
for (field in c("pop_total_ref_advanced", "pop_total_cf_advanced",
                "pop_number_ref_walk_advanced", "pop_number_cf_walk_advanced",
                "pop_number_ref_bike_advanced", "pop_number_cf_bike_advanced",
                "trips_number_ref_walk", "trips_number_cf_walk",
                "trips_number_ref_bike", "trips_number_cf_bike")) {
  profile[[field]] <- list(default_value = NULL, input_value = NULL, is_filled = FALSE)
}
hub <- Hub$new(cfg = cfg)
elapsed <- system.time({
  profile <- hub$build_reference_profile_defaults(profile)
  profile <- hub$build_refinement_profile_defaults(profile)
  profile <- hub$build_trip_refinement_profile_defaults(profile)
  result <- hub$build_results(profile)
})
trips <- result$plot_data$trip_mode_distribution
for (scenario in c("Reference", "Counterfactual")) {
  expected <- if (scenario == "Reference") c(walking = 30000, cycling = 1000) else
    c(walking = 40000, cycling = 1400)
  for (mode in names(expected)) {
    actual <- trips$trips[trips$scenario == scenario & trips$mode == mode]
    stopifnot(length(actual) == 1L, abs(actual - expected[[mode]]) <= 1)
  }
}
print(trips)
print(elapsed)
message("Manchester staging and results checks passed.")
