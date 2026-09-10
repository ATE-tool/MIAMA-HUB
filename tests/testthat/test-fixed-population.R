fixed_population_source <- function() {
  list(ind = data.frame(census_id = 1:6, age1year = 40, female = 0,
    walktime_wkhr = c(1, 1, 0, 0, 0, 0),
    cycletime_wkhr = c(1, 0, 1, 0, 0, 0),
    ebiketime_wkhr = 0, pttime_wkhr = c(0, 0, 0, 1, 0, 0),
    sport_wkhr = 0, mmets = c(5, 2.5, 2.5, 1, 0, 0)))
}

fixed_population_run <- function(values) {
  ref <- suppressWarnings(apply_reference_appraisal_scope(fixed_population_source(), values))
  cf <- apply_counterfactual_ui_values(init_counterfactual_data(ref), values, ref)
  list(ref = ref, cf = cf)
}

test_that("basic explicit total is fixed while mode membership can overlap", {
  values <- list(ui_version = "basic", modes = c("walk", "bike"), at_data_unit = "users",
    pop_total_ref_basic = 3, pop_total_cf_basic = 3,
    users_count_ref_walk = 2, users_count_cf_walk = 3,
    users_count_ref_bike = 1, users_count_cf_bike = 3)
  out <- fixed_population_run(values)
  expect_equal(sum(out$ref$ind$ref_in_scope), 3)
  expect_equal(sum(out$cf$ind$cf_in_scope), 3)
  expect_equal(sum(out$cf$ind$cf_user_scope_walk), 3)
  expect_equal(sum(out$cf$ind$cf_user_scope_bike), 3)
  expect_identical(out$cf$ind$cf_in_scope, out$ref$ind$ref_in_scope)
  values$users_count_cf_walk <- 4
  expect_error(fixed_population_run(values), "cannot exceed the fixed population total")
  values$users_count_cf_walk <- 3
  values$pop_total_cf_basic <- 4
  expect_error(fixed_population_run(values), "must be the same")
})

test_that("fixed totals permit donor reuse above source size for every mode", {
  for (mode in c("walk", "bike", "ebike", "pt")) {
    values <- list(ui_version = "basic", modes = mode, at_data_unit = "users",
      pop_total_ref_basic = 12, pop_total_cf_basic = 12)
    values[[paste0("users_count_ref_", mode)]] <- 0
    values[[paste0("users_count_cf_", mode)]] <- 12
    out <- fixed_population_run(values)
    expect_equal(sum(out$ref$ind$ref_in_scope), 12, info = mode)
    expect_equal(sum(out$cf$ind$cf_in_scope), 12, info = mode)
    expect_equal(sum(out$cf$ind[[paste0("cf_user_scope_", mode)]]), 12, info = mode)
  }
})

test_that("advanced explicit CF total can be deliberately edited independently", {
  for (total in c(2, 12)) {
    values <- list(ui_version = "advanced", modes = "walk", at_data_unit = "users",
      pop_total_ref_advanced = 3, pop_total_cf_advanced = total,
      pop_number_ref_walk_advanced = 1, pop_number_cf_walk_advanced = total)
    out <- fixed_population_run(values)
    expect_equal(sum(out$ref$ind$ref_in_scope), 3)
    expect_equal(sum(out$cf$ind$cf_in_scope), total)
    expect_equal(sum(out$cf$ind$cf_user_scope_walk), total)
  }
})

test_that("absence of an explicit total preserves inferred recruitment", {
  values <- list(modes = "walk", at_data_unit = "users",
    users_count_ref_walk = 1, users_count_cf_walk = 6)
  out <- fixed_population_run(values)
  expect_gt(sum(out$cf$ind$cf_in_scope), sum(out$ref$ind$ref_in_scope))
})

test_that("trip-authoritative routes and later trip edits preserve fixed people", {
  source <- fixed_population_source()
  source$trips <- data.frame(census_id = rep(1:6, each = 2), nts_tripid = 1:12,
    trip_mainmode = c(rep("walking", 4), rep("car", 8)),
    trip_distraw_km = 1, trip_durationraw_min = 10,
    trip_walkdist_km = c(rep(1, 4), rep(0, 8)),
    trip_walktime_min = c(rep(10, 4), rep(0, 8)),
    trip_cycledist_km = 0, trip_cycletime_min = 0)
  routes <- list(
    list(at_data_unit = "trips", trips_count_ref_walk = 2, trips_count_cf_walk = 4),
    list(at_data_unit = "distance", ui_dist_dur_type_walk = "distance",
      dist_dur_amount_ref_walk = 2, dist_dur_amount_cf_walk = 4,
      dist_dur_denominator_walk = "total", dist_dur_timeframe_walk = "week", distance_unit_walk = "km"),
    list(at_data_unit = "distance", ui_dist_dur_type_walk = "duration",
      dist_dur_amount_ref_walk = 20, dist_dur_amount_cf_walk = 40,
      dist_dur_denominator_walk = "total", dist_dur_timeframe_walk = "week", duration_unit_walk = "mins"),
    list(at_data_unit = "mode_share", mode_share_total_trips_basic = 12,
      mode_share_ref = list(walk = list(percent = 100/6)),
      mode_share_cf = list(walk = list(percent = 100/3))))
  for (route in routes) {
    values <- c(list(ui_version = "basic", modes = "walk",
      pop_total_ref_basic = 3, pop_total_cf_basic = 3), route)
    ref <- suppressWarnings(apply_reference_appraisal_scope(source, values))
    cf <- apply_counterfactual_ui_values(init_counterfactual_data(ref), values, ref)
    expect_equal(sum(ref$ind$ref_in_scope), 3)
    expect_equal(sum(cf$ind$cf_in_scope), 3)
    # An explicit downstream trip target can change volume, not the people count.
    values$trips_number_cf_walk <- 8
    cf <- suppressWarnings(apply_counterfactual_ui_values(init_counterfactual_data(ref), values, ref))
    expect_equal(sum(cf$ind$cf_in_scope), 3)
  }
})
