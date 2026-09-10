test_that("PT walkers qualify for additional walking without automatic promotion", {
  data <- list(ind = data.frame(census_id = 1:4,
    cf_in_scope = c(TRUE, TRUE, TRUE, FALSE),
    cf_user_scope_walk = c(TRUE, FALSE, FALSE, FALSE),
    ref_user_scope_walk = c(TRUE, FALSE, FALSE, FALSE),
    cf_user_scope_pt = c(FALSE, TRUE, FALSE, TRUE),
    ref_user_scope_pt = c(FALSE, TRUE, FALSE, TRUE)))
  allocate <- function(x = data, delta = 2, explicit = NULL) {
    .cf_trip_user_allocation(x, x, .counterfactual_mode_spec("walking"),
      target_trip_count = 10 + delta, current_trip_count = 10,
      trips_per_user_per_week = 2, new_user_percent = 0,
      explicit_user_target = explicit)
  }
  out <- allocate()
  expect_equal(out$ids, 1L)
  expect_equal(out$recipient_ids, c(1L, 2L))
  expect_equal(out$report$added_new_at_users, 0L)
  expect_equal(out$report$eligible_pt_walking_users, 1L)
  expect_null(allocate(delta = 0)$recipient_ids)
  expect_null(allocate(delta = -2)$recipient_ids)
  expect_equal(allocate(explicit = 1)$ids, 1L)
  expect_null(allocate(explicit = 1)$recipient_ids)

  data$ind$cf_user_scope_walk <- FALSE
  out <- allocate(data)
  expect_length(out$ids, 0)
  expect_equal(out$recipient_ids, 2L)
})
