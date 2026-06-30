test_that("counterfactual payload defaults are empty but well formed", {
  payload <- build_ui_return_payload()

  expect_type(payload$counterfactual_summaries, "list")
  expect_s3_class(payload$health_impacts, "data.frame")
})

test_that("init_counterfactual_data copies reference data shape", {
  reference_data <- list(
    ind = data.frame(census_id = 1:2, walktime_wkhr = c(1, 0)),
    trips = data.frame(census_id = c(1, 2), walktime_wkhr = c(1, 0))
  )

  counterfactual_data <- init_counterfactual_data(reference_data)

  expect_equal(counterfactual_data, reference_data)
})

test_that("apply_counterfactual_ui_values increases walking users from non-users", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:4,
      walktime_wkhr = c(1, 2, 0, 0),
      cycletime_wkhr = c(0, 0, 0, 0),
      sport_wkhr = c(0, 0, 0, 0),
      mmets = c(2.5, 5, 0, 0)
    ),
    trips = data.frame(
      census_id = c(1, 2, 3, 4),
      walktime_wkhr = c(1, 2, 0, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      users_count_cf_walk = 3
    ),
    reference_data = reference_data,
    seed = 10
  )

  expect_equal(sum(counterfactual_data$ind$walktime_wkhr > 0), 3)
  expect_equal(counterfactual_data$ind$mmets, counterfactual_data$ind$walktime_wkhr * 2.5)
  expect_equal(counterfactual_data$trips$walktime_wkhr, counterfactual_data$ind$walktime_wkhr)
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$role, "new_users")
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$target, 3)

  ind_comparison <- counterfactual_data$counterfactual_report$comparison$ind
  expect_true("walktime_wkhr_active_rows" %in% ind_comparison$metric)
  expect_equal(
    ind_comparison$delta[ind_comparison$metric == "walktime_wkhr_active_rows"],
    1
  )
  expect_true(nrow(counterfactual_data$counterfactual_report$comparison$changed_ind_rows) > 0)
})

test_that("apply_counterfactual_ui_values decreases walking users to non-user activity", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:4,
      walktime_wkhr = c(1, 2, 3, 0),
      cycletime_wkhr = c(0, 0, 0, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      users_count_cf_walk = 1
    ),
    reference_data = reference_data,
    seed = 11
  )

  expect_equal(sum(counterfactual_data$ind$walktime_wkhr > 0), 1)
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$role, "ex_users")
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$changed_n, 2)
})

test_that("apply_counterfactual_ui_values validates user-count targets", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      walktime_wkhr = c(1, 0)
    )
  )

  expect_error(
    apply_counterfactual_ui_values(
      init_counterfactual_data(reference_data),
      appraisal_input_values = list(
        modes = "walking",
        users_count_cf_walk = 3
      ),
      reference_data = reference_data
    ),
    "cannot exceed"
  )
})

test_that("apply_counterfactual_ui_values increases walking trip rows from reference donors", {
  reference_data <- list(
    ind = data.frame(census_id = 1:2, walktime_wkhr = c(1, 0)),
    trips = data.frame(
      census_id = c(1, 1, 2),
      nts_tripid = c(10, 11, 20),
      trip_walkdist_km = c(1, 2, 0),
      trip_walktime_min = c(10, 20, 0),
      trip_cycledist_km = c(0, 0, 0),
      trip_cycletime_min = c(0, 0, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      trips_count_cf_walk = 3,
      trips_timeframe_walk = "week",
      trips_denominator_walk = "total"
    ),
    reference_data = reference_data,
    seed = 12
  )

  active <- counterfactual_data$trips$trip_walkdist_km > 0 |
    counterfactual_data$trips$trip_walktime_min > 0
  expect_equal(sum(active), 3)
  expect_equal(nrow(counterfactual_data$trips), 4)
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$field, "trips_count_cf_walk")
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$role, "new_or_shifted_trips")
})

test_that("apply_counterfactual_ui_values converts mean trip targets to total base-week rows", {
  reference_data <- list(
    ind = data.frame(census_id = 1:3),
    trips = data.frame(
      census_id = c(1, 2),
      nts_tripid = c(10, 20),
      trip_walkdist_km = c(1, 0),
      trip_walktime_min = c(10, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      trips_count_cf_walk = 1,
      trips_timeframe_walk = "week",
      trips_denominator_walk = "mean"
    ),
    reference_data = reference_data,
    seed = 13
  )

  active <- counterfactual_data$trips$trip_walkdist_km > 0 |
    counterfactual_data$trips$trip_walktime_min > 0
  expect_equal(sum(active), 3)
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$target_base_week_count, 3)
})

test_that("apply_counterfactual_ui_values decreases walking trip rows", {
  reference_data <- list(
    ind = data.frame(census_id = 1:2),
    trips = data.frame(
      census_id = c(1, 1, 2),
      nts_tripid = c(10, 11, 20),
      trip_walkdist_km = c(1, 2, 0),
      trip_walktime_min = c(10, 20, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      trips_number_cf_walk = 1
    ),
    reference_data = reference_data,
    seed = 14
  )

  active <- counterfactual_data$trips$trip_walkdist_km > 0 |
    counterfactual_data$trips$trip_walktime_min > 0
  expect_equal(sum(active), 1)
  expect_equal(nrow(counterfactual_data$trips), 2)
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$role, "removed_or_shifted_away_trips")
})

test_that("legacy split counterfactual functions preserve data shape", {
  counterfactual_data <- list(ind = data.frame(census_id = 1))

  expect_equal(apply_ind_rows_changes(counterfactual_data), counterfactual_data)
  expect_equal(apply_ind_attribute_changes(counterfactual_data), counterfactual_data)
  expect_equal(apply_trip_rows_changes(counterfactual_data), counterfactual_data)
  expect_equal(apply_trip_attribute_changes(counterfactual_data), counterfactual_data)
})
