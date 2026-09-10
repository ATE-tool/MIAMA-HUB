test_that("sampling ceilings distinguish machine noise from fractional users", {
  expect_identical(.sampling_count_ceiling(695 / (695 / 155)), 155L)
  expect_identical(.sampling_count_ceiling(c(0, 1e-20, 155 - 1e-10, 155 + 1e-10)),
                   c(0L, 1L, 155L, 156L))
  expect_identical(.sampling_count_ceiling(c(1, 155, 10000) * (1 + .Machine$double.eps)),
                   c(1L, 155L, 10000L))
})

test_that("trip allocation does not invent a user at an exact division boundary", {
  data <- list(ind = data.frame(census_id = 1:200, walktime_wkhr = 0,
                               cycletime_wkhr = 0, sport_wkhr = 0))
  for (mode in c("walking", "cycling", "ebiking", "pt")) {
    out <- .cf_trip_user_allocation(data, data, .counterfactual_mode_spec(mode),
      target_trip_count = 695, current_trip_count = 0,
      trips_per_user_per_week = 695/155, new_user_percent = 100)
    expect_equal(out$report$equivalent_changed_users, 155L, info = mode)
    expect_equal(length(out$ids), 155L, info = mode)
  }
})
