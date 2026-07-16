test_that("build_ui_return_payload exposes compact named sections", {
  payload <- build_ui_return_payload(
    ui_updates = list(example = 1),
    reference_summaries = list(example = 2)
  )

  expect_type(payload, "list")
  expect_true(all(c(
    "ui_updates",
    "reference_summaries",
    "counterfactual_summaries",
    "health_impacts",
    "state"
  ) %in% names(payload)))
})

test_that("build_mock_appraisal_inputs returns canonical dev fields", {
  mock <- build_mock_appraisal_inputs()

  expect_true(all(c(
    "geo_level",
    "geo_id",
    "modes",
    "at_data_unit",
    "res_aggregation",
    "res_outcomes"
  ) %in% names(mock)))

  expect_equal(mock$geo_level$input_value, "lad")
  expect_equal(mock$res_aggregation$input_value, "total")
})

test_that("filter_reference_data filters by LAD code", {
  reference_data_raw <- list(
    ind = data.frame(
      census_id = 1:3,
      lad25cd = c("E08000035", "E08000035", "E09000001"),
      region = c("North West", "North West", "London")
    ),
    trips = data.frame(
      census_id = c(1, 1, 2, 3),
      lad25cd = c("E08000035", "E08000035", "E08000035", "E09000001"),
      region = c("North West", "North West", "North West", "London")
    )
  )

  filtered <- filter_reference_data(
    reference_data_raw,
    list(geo_level = "lad", geo_id = "E08000035")
  )

  expect_equal(nrow(filtered$ind), 2)
  expect_equal(nrow(filtered$trips), 3)
  expect_equal(filtered$filter_report$geo_level, "lad")
  expect_equal(filtered$filter_report$geo_id, "E08000035")
})

test_that("filter_reference_data leaves England-wide data unchanged", {
  reference_data_raw <- list(
    ind = data.frame(census_id = 1:2, lad25cd = c("A", "B")),
    trips = data.frame(census_id = c(1, 2, 2), lad25cd = c("A", "B", "B"))
  )

  filtered <- filter_reference_data(
    reference_data_raw,
    list(geo_level = "eng", geo_id = NULL)
  )

  expect_equal(nrow(filtered$ind), 2)
  expect_equal(nrow(filtered$trips), 3)
})

test_that("extract_reference_ui_values derives Tab 2 trip reference fields", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      walktime_wkhr = c(1, 0),
      cycletime_wkhr = c(0, 2)
    ),
    trips = data.frame(
      census_id = c(1, 2, 2),
      nts_tripid = c(11, 21, 22),
      weight_tripXhh = c(1, 2, 1),
      trip_walkdist_km = c(1, 0, 0),
      trip_walktime_min = c(10, 0, 0),
      trip_cycledist_km = c(0, 5, 3),
      trip_cycletime_min = c(0, 20, 12)
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "trips",
      modes = c("walking", "cycling"),
      trips_timeframe_walk = "week",
      trips_timeframe_bike = "week",
      trips_denominator_walk = "total",
      trips_denominator_bike = "total"
    )
  )

  expect_equal(values$ui_updates$pop_total_ref, 2)
  expect_equal(values$ui_updates$population_size, 2)
  expect_equal(values$ui_updates$trips_count_ref_walk, 1)
  expect_equal(values$ui_updates$trips_count_ref_bike, 3)
})

test_that("extract_reference_ui_values derives summary geo_name where possible", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      lad25cd = c("E08000035", "E08000035"),
      lad25nm = c("Leeds", "Leeds")
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    reference_request = list(geo_level = "lad", geo_id = "E08000035"),
    appraisal_input_values = list(modes = "walking")
  )

  expect_equal(values$ui_updates$geo_name, "Leeds")
  expect_equal(values$ui_updates$population_size, values$ui_updates$pop_total_ref)
})

test_that("extract_reference_ui_values supports individual-only user counts", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:3,
      walktime_wkhr = c(1, 0, 0.5),
      cycletime_wkhr = c(0, 2, 0)
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "users",
      modes = c("walking", "cycling", "ebiking")
    )
  )

  expect_equal(values$ui_updates$users_count_ref_walk, 2)
  expect_equal(values$ui_updates$users_count_ref_bike, 1)
  expect_true(is.na(values$ui_updates$users_count_ref_ebike))
  expect_true("users_count_ref_ebike" %in% values$extraction_report$skipped_fields)
})

test_that("extract_reference_ui_values derives mode-share reference fields", {
  reference_data <- list(
    ind = data.frame(census_id = 1:2),
    trips = data.frame(
      census_id = c(1, 1, 2),
      nts_tripid = c(11, 12, 21),
      weight_tripXhh = c(1, 1, 2),
      trip_distraw_km = c(2, 5, 6),
      trip_durationraw_min = c(20, 30, 40),
      trip_walkdist_km = c(2, 0, 0),
      trip_walktime_min = c(20, 0, 0),
      trip_cycledist_km = c(0, 5, 6),
      trip_cycletime_min = c(0, 30, 40)
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "mode_share",
      modes = c("walking", "cycling"),
      ui_mode_share_show_options = FALSE
    )
  )

  expect_equal(values$ui_updates$mode_share_total_trips, 4)
  expect_equal(values$ui_updates$mode_share_total_trips_2, 4)
  expect_equal(values$ui_updates$mode_share_ref_walk, 25)
  expect_equal(values$ui_updates$mode_share_ref_bike, 75)
})

test_that("extract_reference_ui_values derives Tab 3 population reference fields", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:4,
      age1year = c(20, 30, 40, 50),
      female = c(0, 1, 1, 0),
      walktime_wkhr = c(1, 0, 0, 2),
      cycletime_wkhr = c(0, 3, 0, 0)
    )
  )

  current_values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "users",
      modes = c("walking", "cycling"),
      pop_refine_choice = "pop_age_current"
    )
  )

  expect_equal(current_values$ui_updates$pop_total_ref, 4)
  expect_equal(current_values$ui_updates$pop_number_ref_walk, 2)
  expect_equal(current_values$ui_updates$pop_number_ref_bike, 1)
  expect_equal(current_values$ui_updates$pop_spread_age_mean_ref, mean(c(20, 30, 50)))
  expect_equal(current_values$ui_updates$pop_spread_sex_prop_ref, 2 / 3)

  new_values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "users",
      modes = c("walking", "cycling"),
      pop_refine_choice = "pop_age_new"
    )
  )

  expect_equal(new_values$ui_updates$pop_spread_age_mean_ref, 40)
  expect_equal(new_values$ui_updates$pop_spread_sex_prop_ref, 0)
})

test_that("extract_reference_ui_values handles haven-labelled numeric columns", {
  skip_if_not_installed("haven")
  skip_if_not_installed("vctrs")

  reference_data <- list(
    ind = data.frame(
      census_id = 1:3
    ),
    trips = data.frame(
      census_id = c(1, 2, 3),
      nts_tripid = c(11, 21, 31),
      trip_purpose = c("Commuting", "Leisure", "Shopping")
    )
  )
  reference_data$ind$age1year <- haven::labelled(c(20, 30, 40), c(young = 20, mid = 30, old = 40))
  reference_data$ind$female <- vctrs::new_vctr(c(0, 1, 0), class = "haven_labelled", labels = c(male = 0, female = 1))
  reference_data$ind$walktime_wkhr <- haven::labelled(c(1, 0, 2), c(none = 0))
  reference_data$trips$weight_tripXhh <- haven::labelled(c(1, 2, 1), c(one = 1, two = 2))
  reference_data$trips$trip_walkdist_km <- haven::labelled(c(1, 0, 2), c(none = 0))
  reference_data$trips$trip_walktime_min <- haven::labelled(c(10, 0, 20), c(none = 0))
  reference_data$trips$trip_distraw_km <- haven::labelled(c(1, 5, 2), c(short = 1))
  reference_data$trips$trip_durationraw_min <- haven::labelled(c(10, 50, 20), c(short = 10))

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "trips",
      modes = "walking",
      trips_timeframe_walk = "week",
      trips_denominator_walk = "total",
      pop_refine_choice = "pop_age_current"
    )
  )

  expect_equal(values$ui_updates$pop_number_ref_walk, 2)
  expect_equal(values$ui_updates$trips_count_ref_walk, 2)
  expect_equal(values$ui_updates$pop_spread_age_mean_ref, 30)
  expect_equal(values$ui_updates$pop_spread_sex_prop_ref, 1)
  expect_equal(values$ui_updates$trips_spread_mean_ref, 13 / 4)
})

test_that("extract_reference_ui_values derives Tab 4 trip reference fields", {
  reference_data <- list(
    ind = data.frame(census_id = 1:2),
    trips = data.frame(
      census_id = c(1, 1, 2),
      nts_tripid = c(11, 12, 21),
      weight_tripXhh = c(1, 1, 2),
      trip_distraw_km = c(2, 5, 6),
      trip_durationraw_min = c(20, 30, 40),
      trip_purpose = c("Commuting", "Leisure", "Shopping"),
      trip_walkdist_km = c(2, 0, 0),
      trip_walktime_min = c(20, 0, 0),
      trip_cycledist_km = c(0, 5, 6),
      trip_cycletime_min = c(0, 30, 40)
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "trips",
      modes = c("walking", "cycling")
    )
  )

  expect_equal(values$ui_updates$trips_number_total_ref, 4)
  expect_equal(values$ui_updates$trips_number_ref_walk, 1)
  expect_equal(values$ui_updates$trips_number_ref_bike, 3)
  expect_equal(values$ui_updates$trips_spread_mean_ref, 19 / 4)
  expect_equal(values$ui_updates$trips_spread_util_prop_ref, 3 / 4)
  expect_equal(values$ui_updates$trips_diversion_total_trips, 4)
  expect_equal(values$ui_updates$trips_diversion_trips_n, 4)
  expect_equal(values$ui_updates$trips_diversion_distance_total, 19)
  expect_equal(values$ui_updates$trips_diversion_duration_total, 130)
})
