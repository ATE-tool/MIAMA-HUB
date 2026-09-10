test_that("only the selected Tab 2 volume route enters calculation requests", {
  for (mode in c("walk", "bike", "ebike", "pt")) {
    for (unit in c("users", "trips", "distance", "mode_share")) {
      values <- list(at_data_unit = unit, ui_version = "advanced", modes = mode,
                     mode_share_ref = list(walk = list(percent = 20)),
                     mode_share_cf = list(walk = list(percent = 30)))
      fields <- c(users = paste0("users_count_cf_", mode),
                  trips = paste0("trips_count_cf_", mode),
                  distance = paste0("dist_dur_amount_cf_", mode),
                  mode_share = "mode_share_cf")
      for (field in fields[names(fields) != "mode_share"]) values[[field]] <- 10
      original <- serialize(values, NULL)
      request <- receive_appraisal_inputs(values)
      actual <- request$appraisal_input_values
      expect_identical(actual[[fields[[unit]]]], values[[fields[[unit]]]])
      for (field in fields[names(fields) != unit]) expect_null(actual[[field]])
      expect_identical(serialize(values, NULL), original)
      # Inactive entries are retained in the profile, not erased on navigation.
      expect_equal(get_input_value(request$appraisal_inputs_in, fields[["users"]]), 10)
    }
  }
})

test_that("staged and final inputs use the same active route policy", {
  field <- function(value) list(input_value = value, is_filled = TRUE, default_value = value)
  profile <- lapply(list(
    at_data_unit = "trips", ui_version = "advanced", modes = "bike",
    users_count_ref_bike = 155, users_count_cf_bike = 310,
    trips_count_ref_bike = 695, trips_count_cf_bike = 1390,
    pop_number_ref_bike_advanced = 155, pop_number_cf_bike_advanced = 171,
    trips_number_ref_bike = 695, trips_number_cf_bike = 1500,
    assump_new_user_percent = 10
  ), field)
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(profile)
  hub$refinement_reference_data <- list(ind = data.frame(census_id = 1))
  final <- hub$.__enclos_env__$private$.counterfactual_input_values()
  for (values in list(.tab2_stage_input_values(profile), .tab3_stage_input_values(profile), final)) {
    expect_null(values$users_count_ref_bike)
    expect_null(values$users_count_cf_bike)
    expect_equal(values$trips_count_cf_bike, 1390)
    expect_equal(values$assump_new_user_percent, 10)
  }
  expect_equal(final$pop_number_cf_bike_advanced, 171)
  expect_equal(final$trips_number_cf_bike, 1500)
  profile$at_data_unit <- field("users")
  hub$set_appraisal_inputs(profile)
  hub$refinement_reference_data <- list(ind = data.frame(census_id = 1))
  final <- hub$.__enclos_env__$private$.counterfactual_input_values()
  expect_equal(final$users_count_cf_bike, 310)
  expect_null(final$trips_count_cf_bike)
  expect_equal(final$trips_number_cf_bike, 1500)
})

test_that("inactive units and hidden population tables cannot leak into another route", {
  values <- list(at_data_unit = "users", ui_version = "basic",
                 trips_timeframe_bike = "year", trips_denominator_bike = "per_person",
                 distance_unit_bike = "miles", mode_share_total_trips = 100,
                 pop_total_ref_basic = 3, pop_number_cf_bike_basic = 2,
                 pop_total_ref_advanced = 4, trips_number_cf_bike = 99,
                 users_count_cf_bike = 5, assump_trip_speed_kmh_bike = 15)
  actual <- .active_tab2_input_values(values)
  expect_equal(actual$users_count_cf_bike, 5)
  expect_equal(actual$assump_trip_speed_kmh_bike, 15)
  for (name in setdiff(names(values), c("at_data_unit", "ui_version", "users_count_cf_bike", "assump_trip_speed_kmh_bike"))) {
    expect_null(actual[[name]])
  }
  values$at_data_unit <- "trips"
  actual <- .active_tab2_input_values(values)
  expect_equal(actual$pop_total_ref_basic, 3)
  expect_equal(actual$pop_number_cf_bike_basic, 2)
  expect_null(actual$pop_total_ref_advanced)
})

test_that("unlabelled low-level sampler requests are not interpreted as UI routes", {
  values <- list(users_count_cf_bike = 5, trips_count_cf_bike = 50)
  expect_identical(.active_tab2_input_values(values), values)
})

test_that("basic sampling is identical with or without stale counts from another route", {
  data <- list(
    ind = data.frame(census_id = 1:4, walktime_wkhr = c(1, 1, 0, 0),
                     cycletime_wkhr = 0, sport_wkhr = 0, mmets = c(5, 5, 0, 0)),
    trips = data.frame(census_id = 1:4, nts_tripid = 11:14,
      trip_mainmode = c("walking", "walking", "car", "car"),
      trip_distraw_km = 1, trip_durationraw_min = 10,
      trip_walkdist_km = c(1, 1, 0, 0), trip_walktime_min = c(10, 10, 0, 0),
      trip_cycledist_km = 0, trip_cycletime_min = 0)
  )
  sample_request <- function(values) {
    hub <- Hub$new(cfg = list())
    hub$set_appraisal_inputs(values)
    hub$reference_data <- data
    hub$build_counterfactual_data(seed = 13)
  }
  trips <- list(at_data_unit = "trips", ui_version = "basic", modes = "walk",
                trips_count_ref_walk = 2, trips_count_cf_walk = 3,
                trips_timeframe_walk = "week", trips_denominator_walk = "total")
  stale <- c(trips, list(users_count_ref_walk = 99, users_count_cf_walk = 100))
  expect_identical(sample_request(stale), sample_request(trips))
  users <- list(at_data_unit = "users", ui_version = "basic", modes = "walk",
                users_count_ref_walk = 2, users_count_cf_walk = 3)
  stale <- c(users, list(trips_count_ref_walk = 99, trips_count_cf_walk = 100))
  expect_identical(sample_request(stale), sample_request(users))
})
