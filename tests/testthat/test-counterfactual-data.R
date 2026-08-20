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
  expect_equal(nrow(counterfactual_data$ind), nrow(reference_data$ind))
  expect_true("user_walk" %in% names(counterfactual_data$ind))
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

test_that("blank basic user target does not mask advanced target", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:3,
      walktime_wkhr = c(0, 0, 0),
      cycletime_wkhr = c(1, 0, 0),
      sport_wkhr = c(0, 0, 0),
      mmets = c(5.8, 0, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "cycling",
      users_count_cf_bike = NA_real_,
      pop_number_cf_bike = 2
    ),
    reference_data = reference_data,
    seed = 10
  )

  expect_equal(sum(counterfactual_data$ind$cycletime_wkhr > 0), 2)
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$target, 2)
})

test_that("blank user targets produce no counterfactual user change", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      walktime_wkhr = c(1, 0),
      cycletime_wkhr = c(0, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      users_count_cf_walk = NA_real_,
      pop_number_cf_walk = NULL
    ),
    reference_data = reference_data
  )

  expect_equal(counterfactual_data$ind$walktime_wkhr, reference_data$ind$walktime_wkhr)
  expect_length(counterfactual_data$counterfactual_report$changes, 0)
})

test_that("counterfactual MMET calculation preserves unchanged HM exposure", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:3,
      walktime_wkhr = c(1, 0, 0),
      cycletime_wkhr = c(0, 0, 0),
      sport_wkhr = c(0, 0, 0),
      mmets = c(100, 200, 300)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      users_count_cf_walk = 2
    ),
    reference_data = reference_data,
    seed = 10
  )

  changed <- counterfactual_data$ind$walktime_wkhr != reference_data$ind$walktime_wkhr
  expect_equal(sum(changed), 1)
  expect_equal(
    counterfactual_data$ind$mmets[!changed],
    reference_data$ind$mmets[!changed]
  )
  expect_equal(
    counterfactual_data$ind$mmets[changed] - reference_data$ind$mmets[changed],
    counterfactual_data$ind$walktime_wkhr[changed] * 2.5
  )
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

test_that("new walking users shift trips using current-user active trip rates", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      walktime_wkhr = c(1, 0),
      cycletime_wkhr = c(0, 0)
    ),
    trips = data.frame(
      census_id = c(1, 1, 2, 2),
      nts_tripid = c(11, 12, 21, 22),
      trip_mainmode = c("walking", "walking", "car", "car"),
      trip_distraw_km = c(1, 1, 0.8, 0.9),
      trip_durationraw_min = c(10, 10, 8, 9),
      trip_walkdist_km = c(1, 1, 0, 0),
      trip_walktime_min = c(10, 10, 0, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      users_count_cf_walk = 2
    ),
    reference_data = reference_data,
    seed = 16
  )

  change <- counterfactual_data$counterfactual_report$changes[[1]]
  expect_equal(change$user_trip_shift_target_n, 2)
  expect_equal(change$user_trip_shift_n, 2)
  expect_equal(sum(counterfactual_data$trips$trip_walkdist_km > 0), 4)
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

test_that("apply_counterfactual_ui_values increases walking trips by shifting modes and inducing recreational trips", {
  reference_data <- list(
    ind = data.frame(census_id = 1:4, walktime_wkhr = c(1, 0, 0, 0)),
    trips = data.frame(
      census_id = c(1, 2, 3, 4),
      nts_tripid = c(10, 20, 30, 40),
      trip_mainmode = c("walking", "car", "car", "car"),
      trip_distraw_km = c(1, 1.5, 0.8, 0.9),
      trip_durationraw_min = c(10, 15, 8, 9),
      trip_walkdist_km = c(1, 0, 0, 0),
      trip_walktime_min = c(10, 0, 0, 0),
      trip_cycledist_km = c(0, 0, 0, 0),
      trip_cycletime_min = c(0, 0, 0, 0),
      trip_purpose = c("Commuting", "Shopping", "Shopping", "Leisure")
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
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$role, "mode_shift_and_induced_trips")
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$mode_shift_n, 2)
})

test_that("induced trips preserve unlabeled numeric purpose and set recreational indicator", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      walktime_wkhr = c(1, 0),
      cycletime_wkhr = c(0, 0)
    ),
    trips = data.frame(
      census_id = c(1, 2),
      nts_tripid = c(11, 21),
      trip_mainmode = c(1, 3),
      trip_purpose = c(10, 5),
      trip_distraw_km = c(1, 1),
      trip_durationraw_min = c(10, 10),
      trip_walkdist_km = c(1, 0),
      trip_walktime_min = c(10, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      trips_count_cf_walk = 12,
      trips_timeframe_walk = "week",
      trips_denominator_walk = "total"
    ),
    reference_data = reference_data,
    constants = utils::modifyList(
      miama_counterfactual_defaults(),
      list(induced_trip_percent_default = 100)
    ),
    seed = 20
  )

  induced <- counterfactual_data$trips$cf_induced
  expect_true(any(induced))
  expect_type(counterfactual_data$trips$trip_purpose, "double")
  expect_false(anyNA(counterfactual_data$trips$trip_purpose[induced]))
  expect_true(all(!counterfactual_data$trips$trip_utilitarian[induced]))
})

test_that("car diversion shares are specific to each active target mode", {
  reference_data <- list(
    ind = data.frame(census_id = 1:3),
    trips = data.frame(
      census_id = 1:3,
      nts_tripid = c(10, 20, 30),
      trip_mainmode = c("walking", "car driver", "bus"),
      trip_distraw_km = c(1, 1, 1),
      trip_durationraw_min = c(10, 10, 10),
      trip_walkdist_km = c(1, 0, 0),
      trip_walktime_min = c(10, 0, 0),
      trip_purpose = rep("Commuting", 3)
    )
  )

  from_car <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      trips_count_cf_walk = 2,
      trips_timeframe_walk = "week",
      trips_denominator_walk = "total",
      trips_diversion_car_perc_walk = 100
    ),
    reference_data = reference_data,
    seed = 21
  )
  from_other <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      trips_count_cf_walk = 2,
      trips_timeframe_walk = "week",
      trips_denominator_walk = "total",
      trips_diversion_car_perc_walk = 0
    ),
    reference_data = reference_data,
    seed = 21
  )

  expect_equal(from_car$trips$trip_mainmode[2], "walking")
  expect_equal(from_car$trips$trip_mainmode[3], "bus")
  expect_equal(from_other$trips$trip_mainmode[2], "car driver")
  expect_equal(from_other$trips$trip_mainmode[3], "walking")
  expect_equal(
    from_car$counterfactual_report$changes[[1]]$car_diversion_field,
    "trips_diversion_car_perc_walk"
  )
  expect_equal(
    from_car$counterfactual_report$changes[[1]]$realized_car_diversion_percent,
    100
  )
  expect_true("source_mode_car" %in%
    from_car$counterfactual_report$changes[[1]]$sampling_constraints)
})

test_that("apply_counterfactual_ui_values converts mean trip targets to total base-week rows", {
  reference_data <- list(
    ind = data.frame(census_id = 1:3),
    trips = data.frame(
      census_id = c(1, 2, 3),
      nts_tripid = c(10, 20, 30),
      trip_mainmode = c("walking", "car", "car"),
      trip_distraw_km = c(1, 0.8, 0.9),
      trip_durationraw_min = c(10, 8, 9),
      trip_walkdist_km = c(1, 0, 0),
      trip_walktime_min = c(10, 0, 0)
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
  expect_equal(nrow(counterfactual_data$trips), 3)
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$target_base_week_count, 3)
})

test_that("induced walking trips receive unit trip weights", {
  reference_data <- list(
    ind = data.frame(census_id = 1:5, walktime_wkhr = c(1, 0, 0, 0, 0)),
    trips = data.frame(
      census_id = 1:5,
      nts_tripid = c(10, 20, 30, 40, 50),
      trip_mainmode = c("walking", rep("car", 4)),
      trip_distraw_km = c(1, 0.8, 0.9, 1, 0.7),
      trip_durationraw_min = c(10, 8, 9, 10, 7),
      trip_walkdist_km = c(1, 0, 0, 0, 0),
      trip_walktime_min = c(10, 0, 0, 0, 0),
      trip_purpose = c("Commuting", rep("Shopping", 4)),
      weight_tripXhh = c(2, 3, 3, 3, 3)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      trips_count_cf_walk = 6,
      trips_timeframe_walk = "week",
      trips_denominator_walk = "total"
    ),
    reference_data = reference_data,
    seed = 17
  )

  induced <- counterfactual_data$trips$cf_induced
  expect_equal(sum(induced), 1)
  expect_equal(counterfactual_data$trips$weight_tripXhh[induced], 1)
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$induced_n, 1)
})

test_that("apply_counterfactual_ui_values decreases walking trips by shifting modes away", {
  reference_data <- list(
    ind = data.frame(census_id = 1:2),
    trips = data.frame(
      census_id = c(1, 1, 2),
      nts_tripid = c(10, 11, 20),
      trip_mainmode = c("walking", "walking", "car"),
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
  expect_equal(nrow(counterfactual_data$trips), 3)
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$role, "shifted_away_trips")
})

test_that("counterfactual changed trip report handles data.table trip inputs", {
  reference_data <- list(
    trips = data.table::data.table(
      census_id = 1,
      nts_tripid = 10,
      trip_mainmode = "walking",
      cf_trip_change = "unchanged",
      cf_induced = FALSE
    )
  )
  counterfactual_data <- list(
    trips = data.table::data.table(
      census_id = 1,
      nts_tripid = 10,
      trip_mainmode = "car",
      cf_trip_change = "mode_shift_away_from_active",
      cf_induced = FALSE
    )
  )

  changed <- MIAMAHUB:::.counterfactual_changed_trip_rows(
    reference_data$trips,
    counterfactual_data$trips
  )

  expect_s3_class(changed, "data.frame")
  expect_equal(nrow(changed), 1)
  expect_equal(changed$trip_mainmode, "car")
})

test_that("counterfactual sampling functions support status and candidate selection", {
  rows <- data.frame(
    census_id = 1:3,
    female = c(0, 1, 0),
    age1year = c(20, 40, 60),
    walktime_wkhr = c(1, 2, 3),
    trip_purpose = c("Commuting", "Shopping", "Leisure")
  )

  plan <- cf_row_delta_plan(cf_row_number = 5, ref_row_number = 3)
  expect_equal(plan$action, "increase_status_count")
  expect_equal(plan$n, 2)

  weights <- cf_individual_candidate_weights(rows, 1:3, list(male_prop = 0.75))
  expect_equal(length(weights), 3)

  values <- cf_sample_observed_values(c(1, 3, NA), n = 2, default_value = 0, seed = 1)
  expect_equal(length(values), 2)
})

test_that("individual candidate weights support haven-labelled sex values", {
  skip_if_not_installed("haven")
  skip_if_not_installed("vctrs")

  rows <- data.frame(census_id = 1:3)
  rows$female <- vctrs::new_vctr(
    c(0, 1, NA),
    class = "haven_labelled",
    labels = c(male = 0, female = 1)
  )

  weights <- cf_individual_candidate_weights(
    rows,
    1:3,
    list(male_prop = 0.75)
  )

  expect_equal(weights, c(0.75, 0.25, 0.25))
})

test_that("candidate sampling relaxes zero weights only when required", {
  sampled <- cf_sample_candidate_indices(
    candidate_rows = 101:105,
    n = 4,
    seed = 9,
    weights = c(0.7, 0.3, 0, 0, 0)
  )
  fallback <- attr(sampled, "sampling_fallback")

  expect_equal(length(sampled), 4)
  expect_true(all(c(101L, 102L) %in% sampled))
  expect_equal(fallback$reason, "insufficient_positive_weight_candidates")
  expect_equal(fallback$positive_weight_candidates, 2)
  expect_equal(fallback$relaxed_n, 2)
})

test_that("candidate sampling falls back uniformly when all weights are zero", {
  sampled <- cf_sample_candidate_indices(
    candidate_rows = 1:4,
    n = 2,
    seed = 4,
    weights = rep(0, 4)
  )

  expect_equal(length(sampled), 2)
  expect_equal(attr(sampled, "sampling_fallback")$reason, "all_candidate_weights_zero")
})

test_that("apply_counterfactual_ui_values reports configured sampling strategy", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:4,
      walktime_wkhr = c(1, 3, 0, 0),
      cycletime_wkhr = c(0, 0, 0, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      users_count_cf_walk = 3,
      user_sampling_strategy = "random_sample_as_is_rows"
    ),
    reference_data = reference_data,
    seed = 15
  )

  change <- counterfactual_data$counterfactual_report$changes[[1]]
  expect_equal(change$sampling_strategy, "random_sample_as_is_rows")
  expect_true("walktime_wkhr" %in% change$relevant_attributes)
  expect_equal(sum(counterfactual_data$ind$walktime_wkhr > 0), 3)
})

test_that("independent active-trip shifts add weekly MMET exposure", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      walktime_wkhr = c(1, 0),
      cycletime_wkhr = c(0, 0),
      sport_wkhr = c(0, 0),
      mmets = c(10, 20)
    ),
    trips = data.frame(
      census_id = 1:2,
      nts_tripid = c(11, 21),
      trip_mainmode = c("walking", "car"),
      trip_distraw_km = c(1, 1),
      trip_durationraw_min = c(10, 10),
      trip_walkdist_km = c(1, 0),
      trip_walktime_min = c(10, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(
      modes = "walking",
      trips_count_cf_walk = 2,
      trips_timeframe_walk = "week",
      trips_denominator_walk = "total"
    ),
    reference_data = reference_data,
    seed = 24
  )

  expected_delta <- 10 / 60 * MIAMA_MMET_PER_HOUR[["walking"]]
  expect_equal(sum(counterfactual_data$ind$cf_trip_mmet_delta), expected_delta)
  expect_equal(sum(counterfactual_data$ind$cf_mmet_delta_walking), expected_delta)
  expect_equal(sum(counterfactual_data$ind$cf_mmet_delta_cycling), 0)
  expect_equal(sum(counterfactual_data$ind$cf_user_mmet_delta), 0)
  expect_equal(
    counterfactual_data$ind$mmets - reference_data$ind$mmets,
    counterfactual_data$ind$cf_mmet_delta
  )
})

test_that("trips mirroring a user-status change do not double count MMET exposure", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      walktime_wkhr = c(1, 0),
      cycletime_wkhr = c(0, 0),
      sport_wkhr = c(0, 0),
      mmets = c(10, 20)
    ),
    trips = data.frame(
      census_id = c(1, 2),
      nts_tripid = c(11, 21),
      trip_mainmode = c("walking", "car"),
      trip_distraw_km = c(1, 1),
      trip_durationraw_min = c(10, 10),
      trip_walkdist_km = c(1, 0),
      trip_walktime_min = c(10, 0)
    )
  )

  counterfactual_data <- apply_counterfactual_ui_values(
    init_counterfactual_data(reference_data),
    appraisal_input_values = list(modes = "walking", users_count_cf_walk = 2),
    reference_data = reference_data,
    seed = 25
  )

  expect_equal(sum(counterfactual_data$ind$cf_trip_mmet_delta), 0)
  expect_equal(sum(counterfactual_data$ind$cf_user_mmet_delta), 2.5)
  expect_equal(sum(counterfactual_data$ind$cf_mmet_delta_walking), 2.5)
  expect_equal(sum(counterfactual_data$ind$cf_mmet_delta), 2.5)
})

test_that("legacy split counterfactual functions preserve data shape", {
  counterfactual_data <- list(ind = data.frame(census_id = 1))

  expect_equal(apply_ind_rows_changes(counterfactual_data), counterfactual_data)
  expect_equal(apply_ind_attribute_changes(counterfactual_data), counterfactual_data)
  expect_equal(apply_trip_rows_changes(counterfactual_data), counterfactual_data)
  expect_equal(apply_trip_attribute_changes(counterfactual_data), counterfactual_data)
})
