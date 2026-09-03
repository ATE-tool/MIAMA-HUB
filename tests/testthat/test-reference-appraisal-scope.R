test_that("reference scope selects people and users without changing behaviour", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:6,
      walktime_wkhr = c(1, 2, 0, 0, 0, 0),
      cycletime_wkhr = c(0, 0, 1, 0, 0, 0)
    ),
    trips = data.frame(
      census_id = rep(1:6, each = 2),
      nts_tripid = 1:12,
      trip_mainmode = rep("car", 12),
      trip_walkdist_km = rep(0, 12),
      trip_walktime_min = rep(0, 12),
      trip_cycledist_km = rep(0, 12),
      trip_cycletime_min = rep(0, 12),
      trip_distraw_km = rep(1, 12),
      trip_durationraw_min = rep(10, 12)
    )
  )
  original_ind <- reference_data$ind

  scoped <- apply_reference_appraisal_scope(
    reference_data,
    appraisal_input_values = list(
      ui_version = "advanced",
      modes = c("walking", "cycling"),
      pop_total_ref_advanced = 4,
      pop_number_ref_walk_advanced = 1,
      pop_number_ref_bike_advanced = 1
    ),
    seed = 4
  )

  expect_equal(sum(scoped$ind$ref_in_scope), 4)
  expect_equal(sum(scoped$ind$ref_user_scope_walk), 1)
  expect_equal(sum(scoped$ind$ref_user_scope_bike), 1)
  expect_equal(scoped$ind$walktime_wkhr, original_ind$walktime_wkhr)
  expect_equal(scoped$ind$cycletime_wkhr, original_ind$cycletime_wkhr)
  expect_equal(sum(scoped$trips$ref_in_scope), 8)
  expect_equal(scoped$reference_scope_report$person$donor_population, 6)
})

test_that("counterfactual user growth starts from scoped REF and draws baseline non-users", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:6,
      walktime_wkhr = c(1, 2, 0, 0, 0, 0),
      cycletime_wkhr = 0,
      sport_wkhr = 0,
      mmets = c(2.5, 5, 0, 0, 0, 0)
    )
  )
  scoped <- apply_reference_appraisal_scope(
    reference_data,
    appraisal_input_values = list(
      ui_version = "advanced", modes = "walking",
      pop_total_ref_advanced = 3,
      pop_number_ref_walk_advanced = 1
    ),
    seed = 2
  )

  cf <- apply_counterfactual_ui_values(
    init_counterfactual_data(scoped),
    appraisal_input_values = list(
      ui_version = "advanced", modes = "walking",
      pop_number_cf_walk_advanced = 2
    ),
    reference_data = scoped,
    seed = 3
  )

  expect_equal(sum(cf$ind$cf_user_scope_walk & cf$ind$walktime_wkhr > 0), 2)
  expect_equal(sum(cf$ind$cf_in_scope), 3)
  new_row <- which(cf$ind$cf_user_change == "new_users")
  expect_length(new_row, 1)
  expect_true(scoped$ind$ref_in_scope[new_row])
  expect_equal(reference_data$ind$walktime_wkhr[new_row], 0)
  expect_gt(cf$ind$walktime_wkhr[new_row], 0)
})

test_that("trip-only reference scope derives its mode users from selected trips", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:4,
      walktime_wkhr = c(1, 1, 0, 0),
      cycletime_wkhr = 0
    ),
    trips = data.frame(
      census_id = c(1, 2, 3, 4),
      nts_tripid = 1:4,
      trip_walkdist_km = c(1, 1, 0, 0),
      trip_walktime_min = c(10, 10, 0, 0),
      trip_cycledist_km = 0,
      trip_cycletime_min = 0
    )
  )

  scoped <- apply_reference_appraisal_scope(
    reference_data,
    appraisal_input_values = list(
      ui_version = "advanced",
      modes = "walking",
      trips_count_ref_walk = 1,
      trips_timeframe_walk = "week",
      trips_denominator_walk = "total"
    ),
    seed = 9
  )

  expect_equal(sum(scoped$trips$ref_trip_scope_walk), 1)
  expect_equal(sum(scoped$ind$ref_user_scope_walk), 1)
  expect_true(scoped$reference_scope_report$users$walking$derived_from_trip_scope)
})

test_that("advanced Tab 4 reference trip counts override Tab 2 counts", {
  advanced <- .reference_trip_scope_target(
    list(
      ui_version = "advanced",
      trips_count_ref_walk = 20,
      trips_number_ref_walk = 8,
      trips_timeframe_walk = "year",
      trips_denominator_walk = "per_person"
    ),
    "walk"
  )
  basic <- .reference_trip_scope_target(
    list(
      ui_version = "basic",
      trips_count_ref_walk = 20,
      trips_number_ref_walk = 8,
      trips_timeframe_walk = "year",
      trips_denominator_walk = "per_person"
    ),
    "walk"
  )

  expect_equal(advanced$field, "trips_number_ref_walk")
  expect_equal(advanced$value, 8)
  expect_equal(advanced$timeframe, "week")
  expect_equal(advanced$denominator, "total")
  expect_equal(basic$field, "trips_count_ref_walk")
  expect_equal(basic$value, 20)
  expect_equal(basic$timeframe, "year")
  expect_equal(basic$denominator, "per_person")
})

test_that("checked age groups constrain both REF scope and CF changes", {
  cfg <- miama_default_config()
  reference_data <- list(
    ind = data.frame(
      census_id = 1:6,
      age1year = c(20, 25, 35, 45, 55, 65),
      female = 0,
      walktime_wkhr = c(1, 0, 1, 0, 0, 0),
      cycletime_wkhr = 0,
      sport_wkhr = 0,
      mmets = c(2.5, 0, 2.5, 0, 0, 0)
    )
  )
  values <- list(
    ui_version = "advanced",
    modes = "walking",
    pop_refine_method = "pop_age",
    pop_target_age_groups = "pop_age_18_29",
    pop_total_ref_advanced = 2,
    pop_number_ref_walk_advanced = 1,
    pop_number_cf_walk_advanced = 1
  )

  scoped <- apply_reference_appraisal_scope(
    reference_data,
    appraisal_input_values = values,
    seed = 3,
    cfg = cfg
  )
  cf <- apply_counterfactual_ui_values(
    init_counterfactual_data(scoped),
    appraisal_input_values = values,
    reference_data = scoped,
    constants = miama_counterfactual_defaults(cfg),
    seed = 3
  )

  expect_equal(sum(scoped$ind$ref_in_scope), 2)
  expect_true(all(scoped$ind$age1year[scoped$ind$ref_in_scope] < 30))
  expect_equal(sum(cf$ind$cf_in_scope), 2)
})

test_that("category selections cap stale REF table targets to eligible rows", {
  cfg <- miama_default_config()
  reference_data <- list(
    ind = data.frame(
      census_id = 1:6,
      age1year = c(20, 25, 35, 45, 55, 65),
      walktime_wkhr = c(1, 0, 1, 0, 0, 0),
      cycletime_wkhr = 0
    )
  )

  expect_warning(
    scoped <- apply_reference_appraisal_scope(
      reference_data,
      appraisal_input_values = list(
        ui_version = "advanced",
        modes = "walking",
        pop_refine_method = "pop_age",
        pop_target_age_groups = "pop_age_18_29",
        pop_total_ref_advanced = 5,
        pop_number_ref_walk_advanced = 3
      ),
      seed = 3,
      cfg = cfg
    ),
    "used the available category counts"
  )

  expect_equal(sum(scoped$ind$ref_in_scope), 2)
  expect_equal(sum(scoped$ind$ref_user_scope_walk), 1)
  expect_equal(scoped$reference_scope_report$person$submitted, 5)
  expect_equal(scoped$reference_scope_report$person$requested, 2)
  expect_equal(
    scoped$reference_scope_report$category_capacity_adjustments$users_walking$used,
    1
  )
})

test_that("Tab 2 user counts imply an affected population when no total is supplied", {
  reference_data <- list(ind = data.frame(
    census_id = 1:10,
    walktime_wkhr = c(rep(1, 4), rep(0, 6)),
    cycletime_wkhr = 0
  ))

  scoped <- apply_reference_appraisal_scope(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "users", modes = "walking",
      users_count_ref_walk = 2
    ),
    seed = 7
  )

  expect_equal(sum(scoped$ind$ref_in_scope), 5)
  expect_equal(sum(scoped$ind$ref_user_scope_walk), 2)
  expect_equal(
    scoped$reference_scope_report$person$method,
    "pooled_source_mode_rate_population"
  )
  expect_equal(
    scoped$reference_scope_report$person$mode_estimates$walking$ratio,
    0.5
  )
})

test_that("Tab 2 trip totals imply population and mode users from trip owners", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:10,
      walktime_wkhr = c(rep(1, 4), rep(0, 6)),
      cycletime_wkhr = 0
    ),
    trips = data.frame(
      census_id = c(1:4, 5:10),
      nts_tripid = 1:10,
      trip_walkdist_km = c(rep(1, 4), rep(0, 6)),
      trip_walktime_min = c(rep(10, 4), rep(0, 6)),
      trip_cycledist_km = 0,
      trip_cycletime_min = 0,
      weight_tripXhh = 1
    )
  )

  scoped <- apply_reference_appraisal_scope(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "trips", modes = "walking",
      trips_count_ref_walk = 2,
      trips_timeframe_walk = "week",
      trips_denominator_walk = "total"
    ),
    seed = 9
  )

  expect_equal(sum(scoped$ind$ref_in_scope), 5)
  expect_equal(sum(scoped$trips$ref_trip_scope_walk), 2)
  expect_equal(sum(scoped$ind$ref_user_scope_walk), 2)
})

test_that("multiple modes use their pooled source-population rate", {
  reference_data <- list(ind = data.frame(
    census_id = 1:10,
    walktime_wkhr = c(rep(1, 5), rep(0, 5)),
    cycletime_wkhr = c(rep(1, 2), rep(0, 8))
  ))

  scoped <- apply_reference_appraisal_scope(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "users", modes = c("walking", "cycling"),
      users_count_ref_walk = 2,
      users_count_ref_bike = 1
    ),
    seed = 11
  )

  # (2 + 1) requested users / (5 + 2) source users * 10 people = 4.29.
  expect_equal(sum(scoped$ind$ref_in_scope), 4)
  expect_equal(sum(scoped$ind$ref_user_scope_walk), 2)
  expect_equal(sum(scoped$ind$ref_user_scope_bike), 1)
  expect_equal(
    scoped$reference_scope_report$person$pooled_ratio,
    3 / 7
  )
})

test_that("pooled estimate uses source rates rather than the largest mode estimate", {
  reference_data <- list(ind = data.frame(
    census_id = 1:1000,
    walktime_wkhr = c(rep(1, 950), rep(0, 50)),
    cycletime_wkhr = c(rep(1, 100), rep(0, 900))
  ))

  scoped <- apply_reference_appraisal_scope(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "users", modes = c("walking", "cycling"),
      users_count_ref_walk = 500,
      users_count_ref_bike = 80
    ),
    seed = 12
  )

  # Pooled source rate: 1000 * (500 + 80) / (950 + 100) = 552.38.
  expect_equal(sum(scoped$ind$ref_in_scope), 552)
  expect_equal(sum(scoped$ind$ref_user_scope_walk), 500)
  expect_equal(sum(scoped$ind$ref_user_scope_bike), 80)
  expect_equal(
    scoped$reference_scope_report$person$mode_estimates$walking$estimated_people,
    1000 * 500 / 950
  )
  expect_equal(
    scoped$reference_scope_report$person$mode_estimates$cycling$estimated_people,
    800
  )
})

test_that("induced trip percentage is explicit and independent of purpose", {
  constants <- miama_counterfactual_defaults(list(
    spread = miama_default_config()$spread,
    counterfactual = list(trips = list(induced_trips_percent_default = 10))
  ))
  expect_equal(
    .cf_induced_trips_target(
      list(trips_purpose_type = "utilitarian"),
      "walk",
      constants
    )$percent,
    10
  )
  expect_equal(
    .cf_induced_trips_target(
      list(
        trips_purpose_type = "mixed",
        trips_purpose_util_perc = 65,
        induced_trips_percent = 25,
        induced_trips_percent_walk = 30
      ),
      "walk",
      constants
    )$percent,
    30
  )
})

test_that("health exposure excludes unchanged donors outside CF scope", {
  ref <- data.frame(
    census_id = 1:4, age1year = 30:33, female = c(0, 1, 0, 1),
    mmets = c(1, 2, 3, 4), ref_in_scope = c(TRUE, TRUE, FALSE, FALSE)
  )
  cf <- ref
  cf$cf_in_scope <- c(TRUE, TRUE, TRUE, FALSE)
  cf$mmets[3] <- 5

  exposure <- .counterfactual_health_exposure(ref, cf)

  expect_equal(exposure$census_id, 1:3)
  expect_equal(exposure$mmets_delta, c(0, 0, 2))
})
