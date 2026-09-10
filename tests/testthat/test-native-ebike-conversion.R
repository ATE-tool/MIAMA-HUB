test_that("e-bike conversion prefers valid native measures before cycling proxies", {
  spec <- .counterfactual_mode_spec("ebiking")
  spec$proxy_distance_factor <- 1.3
  spec$proxy_duration_factor <- 0.8
  trips <- data.frame(nts_tripid = 1:4,
    trip_ebikedist_km = c(4, 6, 0, 0),
    trip_ebiketime_min = c(12, 18, 0, 0),
    trip_cycledist_km = c(0, 0, 2, 4),
    trip_cycletime_min = c(0, 0, 10, 20))
  mean_for <- function(x, kind) .tab2_reference_mode_mean(x, spec, kind)
  for (x in list(trips, trips[1:2, ])) {
    expect_equal(mean_for(x, "distance"), 5)
    expect_equal(mean_for(x, "duration"), 15)
  }
  expect_equal(mean_for(trips[3:4, ], "distance"), 3 * 1.3)
  expect_equal(mean_for(trips[3:4, ], "duration"), 15 * 0.8)
  trips$trip_ebikedist_km[1:2] <- c(NA, Inf)
  expect_equal(mean_for(trips, "distance"), 3 * 1.3)
  expect_equal(mean_for(trips, "duration"), 15)
  trips$trip_ebiketime_min[1:2] <- c(-1, 0)
  expect_equal(mean_for(trips, "duration"), 15 * 0.8)
  trips$nts_tripid[3:4] <- NA
  expect_error(mean_for(trips, "distance"), "No positive reference distance")
  expect_error(mean_for(trips, "duration"), "No positive reference duration")
  trips$trip_ebikedist_km <- NULL
  trips$nts_tripid <- 1:4
  expect_equal(mean_for(trips, "distance"), 3 * 1.3)
})
