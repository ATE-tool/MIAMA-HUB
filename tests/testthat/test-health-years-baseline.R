test_that("health-year exports reconstruct baseline before selecting report years", {
  health <- data.frame(
    census_id = 1, cycle = 0:2,
    unhealthy = c(.30, .10, -.05), unhealthy_cf = c(.30, .05, -.10),
    dead = c(.10, .02, .03), dead_cf = c(.10, .01, .02),
    haly = c(.65, .50, .55), haly_cf = c(.65, .55, .60)
  )
  out <- .results_amat_years_timeline(health[c(3, 1, 2), ], 1, 2)
  hly <- out[out$measure == "healthy_life_years", ]
  ly <- out[out$measure == "life_years", ]
  haly <- out[out$measure == "halys", ]
  expect_equal(hly$cycle, 1:2)
  expect_equal(hly$reference_value, c(.60, .65))
  expect_equal(hly$counterfactual_value, c(.65, .75))
  expect_equal(hly$annual_benefit, c(.05, .10))
  expect_equal(hly$cumulative_benefit, c(.05, .15))
  expect_equal(ly$reference_value, c(.88, .85))
  expect_equal(ly$counterfactual_value, c(.89, .87))
  expect_equal(haly$reference_value, c(.50, .55))
  expect_equal(haly$annual_benefit, c(.05, .05))
  expect_false(any(out$cycle == 0))
  expect_equal(nrow(.results_amat_years_timeline(health[1, ], 1, 2)), 0)
})

test_that("initial state is reconstructed per person and delta columns work", {
  health <- data.frame(census_id = c(2, 1, 2, 1), cycle = c(1, 0, 0, 1),
                       unhealthy = c(.2, .3, .1, .1), d_unhealthy = 0)
  out <- .results_amat_years_timeline(health, 2, 1)
  expect_equal(out$reference_value, 2 * (.6 + .7))
  expect_equal(out$counterfactual_value, out$reference_value)
  expect_equal(out$annual_benefit, 0)
  expect_equal(nrow(.results_amat_years_timeline(health, 1, 0)), 0)
})
