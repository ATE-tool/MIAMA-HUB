tab2_conversion_fixture <- function() {
  list(
    ind = data.frame(
      census_id = 1:4,
      walktime_wkhr = c(1, 1, 0, 0),
      cycletime_wkhr = c(0, 0, 1, 0),
      sport_wkhr = 0,
      mmets = c(5, 5, 5, 5)
    ),
    trips = data.frame(
      census_id = 1:4,
      nts_tripid = 11:14,
      trip_mainmode = c("walking", "walking", "cycling", "car"),
      trip_distraw_km = c(1, 3, 4, 2),
      trip_durationraw_min = c(10, 30, 20, 15),
      trip_walkdist_km = c(1, 3, 0, 0),
      trip_walktime_min = c(10, 30, 0, 0),
      trip_cycledist_km = c(0, 0, 4, 0),
      trip_cycletime_min = c(0, 0, 20, 0)
    )
  )
}

test_that("distance and duration totals become weekly trip-row targets", {
  data <- tab2_conversion_fixture()
  distance <- .derive_tab2_trip_count_targets(
    list(
      at_data_unit = "distance", modes = "walking",
      ui_dist_dur_type_walk = "distance", distance_unit_walk = "km",
      dist_dur_denominator_walk = "total", dist_dur_timeframe_walk = "week",
      dist_dur_amount_cf_walk = 8
    ),
    data,
    scenario = "cf"
  )
  duration <- .derive_tab2_trip_count_targets(
    list(
      at_data_unit = "distance", modes = "walking",
      ui_dist_dur_type_walk = "duration", duration_unit_walk = "hours",
      dist_dur_denominator_walk = "total", dist_dur_timeframe_walk = "week",
      dist_dur_amount_cf_walk = 2
    ),
    data,
    scenario = "cf"
  )

  expect_equal(distance$values$trips_count_cf_walk, 4)
  expect_equal(distance$report$conversions$walking$reference_mean_per_trip, 2)
  expect_equal(duration$values$trips_count_cf_walk, 6)
  expect_equal(duration$report$conversions$walking$weekly_total, 120)
})

test_that("per-person amounts use the applicable person scope", {
  data <- tab2_conversion_fixture()
  data$ind$cf_in_scope <- c(TRUE, TRUE, FALSE, FALSE)
  converted <- .derive_tab2_trip_count_targets(
    list(
      at_data_unit = "distance", modes = "walking",
      ui_dist_dur_type_walk = "distance", distance_unit_walk = "km",
      dist_dur_denominator_walk = "average_per_person",
      dist_dur_timeframe_walk = "week", dist_dur_amount_cf_walk = 2
    ),
    data,
    scenario = "cf"
  )

  expect_equal(converted$values$trips_count_cf_walk, 2)
  expect_equal(converted$report$conversions$walking$population_denominator, 2)
})

test_that("mode shares generate per-mode targets for each denominator type", {
  data <- tab2_conversion_fixture()
  shares <- list(walk = list(percent = 30), bike = list(percent = 20))
  trips <- .derive_tab2_trip_count_targets(
    list(
      at_data_unit = "mode_share", modes = c("walking", "cycling"),
      mode_share_cf = shares, ui_mode_share_show_options = FALSE,
      mode_share_total_trips_basic = 10
    ),
    data,
    scenario = "cf"
  )
  distance <- .derive_tab2_trip_count_targets(
    list(
      at_data_unit = "mode_share", modes = "walking",
      mode_share_cf = shares, ui_mode_share_show_options = TRUE,
      mode_share_total_unit = "distance", mode_share_total_dist = 100
    ),
    data,
    scenario = "cf"
  )

  expect_equal(trips$values$trips_count_cf_walk, 3)
  expect_equal(trips$values$trips_count_cf_bike, 2)
  expect_equal(distance$values$trips_count_cf_walk, 15)
})

test_that("average per trip is rejected as an incomplete volume input", {
  expect_error(
    .derive_tab2_trip_count_targets(
      list(
        at_data_unit = "distance", modes = "walking",
        ui_dist_dur_type_walk = "distance",
        dist_dur_denominator_walk = "average_per_trip",
        dist_dur_amount_cf_walk = 2
      ),
      tab2_conversion_fixture(),
      scenario = "cf"
    ),
    "does not define total active-travel volume"
  )
})

test_that("converted distance targets use the existing trip sampler and MMET path", {
  data <- tab2_conversion_fixture()
  result <- apply_counterfactual_ui_values(
    init_counterfactual_data(data),
    appraisal_input_values = list(
      at_data_unit = "distance", modes = "walking",
      ui_dist_dur_type_walk = "distance", distance_unit_walk = "km",
      dist_dur_denominator_walk = "total", dist_dur_timeframe_walk = "week",
      dist_dur_amount_cf_walk = 6,
      induced_trips_percent = 100
    ),
    reference_data = data,
    seed = 6
  )

  expect_equal(sum(result$trips$trip_walkdist_km > 0), 3)
  expect_equal(result$counterfactual_report$tab2_input_conversion$data_unit, "distance")
  expect_gt(sum(result$ind$cf_trip_mmet_delta), 0)
})
