assumption_fixture <- function() {
  list(ind = data.frame(census_id = 1:4, walktime_wkhr = c(1, 2, 0, 0),
                        cycletime_wkhr = c(0, 0, 1, 0), sport_wkhr = 0, mmets = 10),
       trips = data.frame(census_id = 1:4, nts_tripid = 11:14,
                          trip_mainmode = c("walking", "walking", "cycling", "car"),
                          trip_distraw_km = c(1, 3, 4, 2),
                          trip_durationraw_min = c(10, 30, 20, 2),
                          trip_walkdist_km = c(1, 3, 0, 0), trip_walktime_min = c(10, 30, 0, 0),
                          trip_cycledist_km = c(0, 0, 4, 0), trip_cycletime_min = c(0, 0, 20, 0)))
}

test_that("assumption defaults follow provenance without changing reference rows", {
  source <- assumption_fixture()
  ref <- source
  ref$trips$ref_in_scope <- c(TRUE, FALSE, FALSE, FALSE)
  profile <- prepare_assumption_profile(list(modes = "walk"), ref, source)
  expect_equal(profile$default_trip_distance_walk$default_value, 1)
  expect_equal(profile$default_trip_distance_walk$assumption$source, "REF population")
  expect_equal(profile$default_trip_distance_bike$default_value, 4)
  expect_equal(profile$default_trip_distance_bike$assumption$source, "Source population")
  expect_equal(profile$assump_trip_speed_walk$assumption$source, "Fixed fallback")
  empty <- prepare_assumption_profile(list(modes = "walk"))
  expect_equal(empty$default_trip_distance_walk$assumption$source, "England population (stored rate)")
  expect_identical(source, assumption_fixture())
})

test_that("duration and distance routes expose only two independent quantities", {
  p <- prepare_assumption_profile(list(modes = "walk", at_data_unit = "distance",
                                     ui_dist_dur_type_walk = "duration"), source_data = assumption_fixture())
  fields <- get_appraisal_assumptions(p)$field
  expect_true("default_trip_duration_walk" %in% fields)
  expect_false("default_trip_distance_walk" %in% fields)
  values <- .assumption_values(extract_input_values(p))
  expect_equal(values$default_trip_distance_walk, 20 * 5 / 60)
})

test_that("overrides survive refresh and change distance and duration conversions", {
  p <- prepare_assumption_profile(list(modes = "walk", at_data_unit = "distance",
                                     dist_dur_amount_cf_walk = 12), source_data = assumption_fixture())
  p$default_trip_distance_walk$is_filled <- TRUE
  p$default_trip_distance_walk$input_value <- 3
  p <- prepare_assumption_profile(p, source_data = assumption_fixture())
  expect_equal(get_appraisal_assumptions(p)$source[get_appraisal_assumptions(p)$field == "default_trip_distance_walk"], "User override")
  converted <- .derive_tab2_trip_count_targets(extract_input_values(p), assumption_fixture(), "cf")
  expect_equal(converted$values$trips_count_cf_walk, 4)
  p$ui_dist_dur_type_walk <- "duration"
  p$dist_dur_amount_cf_walk <- 120
  p$default_trip_duration_walk$is_filled <- TRUE
  p$default_trip_duration_walk$input_value <- 15
  converted <- .derive_tab2_trip_count_targets(extract_input_values(p), assumption_fixture(), "cf")
  expect_equal(converted$values$trips_count_cf_walk, 8)
  p$default_trip_duration_walk$input_value <- 0
  expect_error(get_appraisal_assumptions(p), "greater than zero")
})

test_that("switching uses target speed instead of donor car time", {
  data <- assumption_fixture()
  p <- prepare_assumption_profile(list(modes = "walk"), source_data = data)
  p$assump_trip_speed_walk$is_filled <- TRUE
  p$assump_trip_speed_walk$input_value <- 4
  constants <- .assumption_cf_constants(extract_input_values(p), miama_counterfactual_defaults())
  trips <- .switch_trips_to_active_mode(data$trips, 4L, .counterfactual_mode_spec("walking"), constants)
  expect_equal(trips$trip_walktime_min[4], 30)
  expect_equal(data$trips$trip_durationraw_min[4], 2)
  expect_equal(trips$trip_walktime_min[1:2], data$trips$trip_walktime_min[1:2])
})

test_that("user activity assumptions preserve variation and respond to speed", {
  p <- prepare_assumption_profile(list(modes = "walk"), source_data = assumption_fixture())
  values <- extract_input_values(p)
  x <- .assumption_new_user_activity(c(1, 2), values, "walk")
  values$assump_trip_speed_walk <- values$assump_trip_speed_walk * 2
  y <- .assumption_new_user_activity(c(1, 2), values, "walk")
  expect_equal(y, x / 2)
  expect_equal(x[2] / x[1], 2)
})

test_that("partial configuration and provided inputs retain clear precedence", {
  p <- prepare_assumption_profile(list(modes = "walk"), cfg = list())
  expect_equal(p$assump_trip_speed_walk$default_value, 5)
  p$default_trips_per_user_per_week_walk$assumption$provided_above <- TRUE
  expect_false("default_trips_per_user_per_week_walk" %in% get_appraisal_assumptions(p, 2)$field)
  expect_true("default_trips_per_user_per_week_walk" %in% get_appraisal_assumptions(p)$field)
  p$ui_version <- "advanced"
  p$trips_spread_mean_cf_walk <- list(is_filled = TRUE, input_value = 4, default_value = 2)
  expect_false("default_trip_distance_walk" %in% get_appraisal_assumptions(p, 4)$field)
  expect_equal(cf_trip_sampling_target(extract_input_values(p), "walk")$target_mean_distance, 4)
  p$trips_spread_mean_cf_walk$input_value <- 2
  expect_equal(cf_trip_sampling_target(extract_input_values(p), "walk")$target_mean_distance,
               p$default_trip_distance_walk$default_value)
})

test_that("assumption edits invalidate results without replacing accepted people", {
  staged <- list(ind = data.frame(census_id = 1:3))
  state <- list(refinement_reference_data = staged, refinement_counterfactual_data = staged,
                counterfactual_data = staged, results_data = list(done = TRUE))
  invalidated <- invalidate_hub_state(state, "assump_trip_speed_walk")$state
  expect_identical(invalidated$refinement_reference_data, staged)
  expect_identical(invalidated$refinement_counterfactual_data, staged)
  expect_null(invalidated$counterfactual_data)
  expect_null(invalidated$results_data)
})

test_that("trip counts remain fixed while speed changes realized CF exposure", {
  source <- assumption_fixture()
  p <- prepare_assumption_profile(list(modes = "walk", at_data_unit = "trips",
                                      trips_count_cf_walk = 3, pop_new_current_perc = 0,
                                      induced_trips_percent = 0), source_data = source)
  run <- function(profile) apply_counterfactual_ui_values(
    init_counterfactual_data(source), extract_input_values(profile), source, seed = 1)
  first <- run(p)
  p$assump_trip_speed_walk$is_filled <- TRUE
  p$assump_trip_speed_walk$input_value <- 10
  second <- run(p)
  expect_equal(sum(first$trips$trip_mainmode == "walking"), 3)
  expect_equal(first$trips$trip_mainmode, second$trips$trip_mainmode)
  changed <- first$trips$trip_mainmode != source$trips$trip_mainmode
  expect_true(any(changed))
  expect_equal(second$trips$trip_walktime_min[changed], first$trips$trip_walktime_min[changed] / 2)
  expect_identical(source, assumption_fixture())
  p$trips_count_cf_walk <- 2
  unchanged <- run(p)
  expect_equal(unchanged$ind$mmets, source$ind$mmets)
})

test_that("PT fallback uses the editable access leg and exports retain overrides", {
  p <- prepare_assumption_profile(list(modes = "pt"))
  p$default_trip_distance_pt$is_filled <- TRUE
  p$default_trip_distance_pt$input_value <- 1.6
  constants <- .assumption_cf_constants(extract_input_values(p), miama_counterfactual_defaults())
  expect_equal(constants$pt_access_walk_distance_km_default, 1.6)
  expect_equal(constants$pt_access_walk_minutes_default, 20)
  snapshot <- get_appraisal_assumptions(p)
  p$default_trip_distance_pt$input_value <- 0.8
  exported <- .results_export_assumptions(list(assumptions = snapshot), miama_default_config())
  row <- exported[exported$item == "pt Mean trip distance", ]
  expect_equal(row$value, "1.6 km")
  expect_match(row$source, "User override")
  expect_equal(snapshot$value[snapshot$field == "default_trip_distance_pt"], 1.6)
})
