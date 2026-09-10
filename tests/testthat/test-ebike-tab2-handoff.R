ebike_handoff_fixture <- function() {
  list(ind = data.frame(census_id = 1:6, age1year = 30:35, female = 0,
                        walktime_wkhr = c(1, 1, 0, 0, 0, 0),
                        cycletime_wkhr = c(0, 0, 1, 0, 0, 0),
                        sport_wkhr = 0, mmets = 5),
       trips = data.frame(census_id = rep(1:6, each = 2), nts_tripid = 1:12,
                          trip_mainmode = rep(c("walking", "walking", "cycling", "car", "car", "car"), each = 2),
                          trip_distraw_km = 4, trip_durationraw_min = 20,
                          trip_walkdist_km = c(rep(4, 4), rep(0, 8)),
                          trip_walktime_min = c(rep(20, 4), rep(0, 8)),
                          trip_cycledist_km = c(rep(0, 4), rep(4, 2), rep(0, 6)),
                          trip_cycletime_min = c(rep(0, 4), rep(20, 2), rep(0, 6))))
}

ebike_handoff_profile <- function(unit) {
  f <- function(value = NULL) list(input_value = value, is_filled = !is.null(value), default_value = value)
  list(modes = f("ebike"), ui_version = f("advanced"), at_data_unit = f(unit),
       users_count_ref_ebike = f(0), users_count_cf_ebike = f(if (unit == "users") 2 else 0),
       pop_number_ref_ebike_basic = f(0), pop_number_cf_ebike_basic = f(0),
       trips_count_ref_ebike = f(if (unit == "trips") 0 else NULL),
       trips_count_cf_ebike = f(if (unit == "trips") 4 else NULL),
       trips_timeframe_ebike = f("week"), users_timeframe_ebike = f("week"),
       dist_dur_amount_ref_ebike = f(0), dist_dur_amount_cf_ebike = f(16),
       dist_dur_timeframe_ebike = f("week"),
       mode_share_ref = f(list(ebike = list(percent = 0), car = list(percent = 100))),
       mode_share_cf = f(list(ebike = list(percent = 25), car = list(percent = 75))),
       mode_share_total_trips = f(12), assump_trips_per_user_per_week_ebike = f(2),
       pop_number_ref_ebike_advanced = f(), pop_number_cf_ebike_advanced = f(),
       pop_total_ref_advanced = f(), pop_total_cf_advanced = f(),
       assump_induced_trips_percent = f(0))
}

test_that("all Tab 2 routes infer e-bike CF people despite stale hidden zeros", {
  source <- ebike_handoff_fixture()
  for (unit in c("trips", "users", "distance", "mode_share")) {
    profile <- ebike_handoff_profile(unit)
    staged <- prepare_refinement_profile_defaults(source, profile)
    expect_equal(staged$profile$pop_number_ref_ebike_advanced$default_value, 0, info = unit)
    expect_gt(staged$profile$pop_number_cf_ebike_advanced$default_value, 0)
    expect_gt(staged$profile$pop_total_ref_advanced$default_value, 0)
    expect_equal(source, ebike_handoff_fixture())
  }
})

test_that("active user and basic population inputs remain authoritative", {
  profile <- ebike_handoff_profile("users")
  expect_equal(.tab2_stage_input_values(profile)$pop_number_cf_ebike_advanced, 2)
  profile$ui_version$input_value <- "basic"
  profile$at_data_unit$input_value <- "trips"
  profile$pop_number_cf_ebike_basic$input_value <- 2
  expect_equal(.tab2_stage_input_values(profile)$pop_number_cf_ebike_advanced, 2)
})

test_that("zero requested e-bike activity does not invent users", {
  profile <- ebike_handoff_profile("trips")
  profile$trips_count_cf_ebike$input_value <- 0
  staged <- prepare_refinement_profile_defaults(ebike_handoff_fixture(), profile)
  expect_equal(staged$profile$pop_number_ref_ebike_advanced$default_value, 0)
  expect_equal(staged$profile$pop_number_cf_ebike_advanced$default_value, 0)
})

test_that("age and PA payloads preserve staged e-bike users from trip inputs", {
  profile <- ebike_handoff_profile("trips")
  for (field in c("pop_target_age_groups", "pop_target_pa_groups")) {
    profile[[field]] <- list(default_value = NULL, input_value = NULL,
                             is_filled = FALSE, additional_data = list(ref = list(), cf = list()))
  }
  staged <- prepare_refinement_profile_defaults(ebike_handoff_fixture(), profile)
  expected <- staged$profile$pop_number_cf_ebike_advanced$default_value
  expect_gt(expected, 0)
  for (kind in c("age", "pa")) {
    field <- if (kind == "age") "pop_target_age_groups" else "pop_target_pa_groups"
    p <- staged$profile
    p$pop_refine_method <- list(input_value = if (kind == "age") "pop_age" else "pop_pa_level", is_filled = TRUE)
    p[[field]]$is_filled <- TRUE
    p[[field]]$input_value <- names(p[[field]]$additional_data$cf)
    values <- .tab3_stage_input_values(p)
    expect_equal(values$pop_number_ref_ebike_advanced, 0)
    expect_equal(values$pop_number_cf_ebike_advanced, expected)
  }
})
