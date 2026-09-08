# Run from MIAMA-HUB with Rscript --vanilla. Uses packaged Leeds data and the
# current source package, not a potentially stale installed build.
pkgload::load_all(".")
cfg <- miama_default_config(dataset_size = "leeds")
profile <- build_mock_appraisal_inputs(overrides = list(
  ui_version = list(input_value = "advanced", is_filled = TRUE),
  modes = list(input_value = c("cycling", "walking")),
  trips_timeframe_walk = list(input_value = "week"),
  trips_timeframe_bike = list(input_value = "week"),
  trips_count_ref_walk = list(input_value = 15000, is_filled = TRUE),
  trips_count_cf_walk = list(input_value = 20000, is_filled = TRUE),
  trips_count_ref_bike = list(input_value = 500, is_filled = TRUE),
  trips_count_cf_bike = list(input_value = 700, is_filled = TRUE)
))
for (field in c("pop_total_ref_advanced", "pop_total_cf_advanced",
                "pop_number_ref_walk_advanced", "pop_number_cf_walk_advanced",
                "pop_number_ref_bike_advanced", "pop_number_cf_bike_advanced",
                "trips_number_ref_walk", "trips_number_cf_walk",
                "trips_number_ref_bike", "trips_number_cf_bike")) {
  profile[[field]] <- list(default_value = NULL, is_filled = FALSE, input_value = NULL)
}

hub <- Hub$new(cfg = cfg)
profile <- hub$build_reference_profile_defaults(profile)
profile <- hub$build_refinement_profile_defaults(profile)
profile <- hub$build_trip_refinement_profile_defaults(profile)
print(get_appraisal_assumptions(profile))
before <- hub$build_results(profile)

profile$assump_trip_speed_walk$is_filled <- TRUE
profile$assump_trip_speed_walk$input_value <-
  profile$assump_trip_speed_walk$default_value * 2
after <- hub$build_results(profile)

# The input contract and output trip counts must survive an exposure edit.
stopifnot(isTRUE(all.equal(before$plot_data$trip_mode_distribution,
                           after$plot_data$trip_mode_distribution)))
stopifnot(!isTRUE(all.equal(before$counterfactual_data$ind$mmets,
                            after$counterfactual_data$ind$mmets)))
stopifnot(any(after$results_data$assumptions$source == "User override"))
stopifnot(!any(before$results_data$assumptions$source == "User override"))
print(after$plot_data$trip_mode_distribution)
message("Leeds assumptions integration checks passed.")
