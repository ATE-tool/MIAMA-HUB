test_that("summary uses the same profile fields and ignores inactive decline years", {
  expect_identical(get_scheme_effect_summary(),
    c(scheme_peak_year = "Maximum effect at year 1", scheme_no_decline = "No decline"))
  p <- list(scheme_peak_year = 2, scheme_no_decline = FALSE,
            scheme_decline_year = 4, scheme_end_year = 6)
  expect_identical(names(get_scheme_effect_summary(p)),
                   c("scheme_peak_year", "scheme_decline_year", "scheme_end_year"))
  expect_identical(unname(get_scheme_effect_summary(p)),
    c("Maximum effect at year 2", "Decline starts at year 4", "Zero effect at year 6"))
  expect_identical(get_scheme_effect_summary(list(scheme_peak_year = 0))[[1]],
                   "Maximum effect immediately")
  expect_error(get_scheme_effect_summary(modifyList(p, list(scheme_end_year = 3))),
               "maximum effect")
  before <- serialize(p, NULL)
  get_scheme_effect_summary(p)
  expect_identical(serialize(p, NULL), before)
})

test_that("scheme annual factors integrate build-up, plateau and decline", {
  expect_equal(get_scheme_effect_timeline(cycles = 0:3)$effect_factor, c(0, .5, 1, 1))
  expect_equal(get_scheme_effect_timeline(list(scheme_peak_year = 0), 0:2)$effect_factor, c(0, 1, 1))
  p <- list(scheme_peak_year = 2, scheme_no_decline = FALSE,
            scheme_decline_year = 4, scheme_end_year = 6)
  curve <- get_scheme_effect_timeline(p, 0:8)
  expect_equal(curve$effect_factor, c(0, .25, .75, 1, 1, .75, .25, 0, 0))
  expect_equal(curve$effect_at_year_end, c(0, .5, 1, 1, 1, .5, 0, 0, 0))
  profile <- lapply(p, function(x) list(default_value = x, is_filled = FALSE, input_value = NULL))
  expect_equal(get_scheme_effect_timeline(profile, 0:8), curve)
  profile$scheme_peak_year$input_value <- 1
  profile$scheme_peak_year$is_filled <- TRUE
  expect_equal(get_scheme_effect_timeline(profile, 1)$effect_factor, .5)
  expect_error(get_scheme_effect_timeline(list(scheme_peak_year = NA_real_)), "whole year")
  expect_error(get_scheme_effect_timeline(list(scheme_peak_year = -1)), "whole year")
  expect_error(get_scheme_effect_timeline(list(scheme_peak_year = 1.5)), "whole year")
  expect_error(get_scheme_effect_timeline(modifyList(p, list(scheme_end_year = 4))), "maximum effect")
  expect_error(get_scheme_effect_timeline(modifyList(p, list(scheme_decline_year = 1))), "maximum effect")
  # Inactive decline fields cannot invalidate a permanent scheme.
  expect_silent(get_scheme_effect_timeline(list(scheme_no_decline = TRUE, scheme_end_year = NA_real_)))
})

test_that("annual disease, HALY and reconstructed health-year benefits stop together", {
  x <- data.frame(census_id = 1, cycle = 0:4,
                  dead = c(.1, rep(.02, 4)), d_dead = c(0, rep(-.01, 4)),
                  unhealthy = c(.3, rep(.02, 4)), d_unhealthy = c(0, rep(-.01, 4)),
                  haly = .5, d_haly = c(0, rep(.1, 4)))
  x$dead_cf <- x$dead + x$d_dead
  x$haly_cf <- x$haly + x$d_haly
  curve <- get_scheme_effect_timeline(list(scheme_no_decline = FALSE,
                       scheme_decline_year = 1, scheme_end_year = 2), 0:4)
  y <- .scale_scheme_health_outcomes(x, curve)
  expect_equal(y$d_dead, c(0, -.005, -.005, 0, 0))
  expect_equal(y$d_haly, c(0, .05, .05, 0, 0))
  expect_equal(y$dead_cf, y$dead + y$d_dead)
  expect_equal(y$haly_cf, y$haly + y$d_haly)
  expect_equal(y$dead, x$dead)
  years <- .results_amat_years_timeline(y, 1, 4)
  for (measure in c("life_years", "healthy_life_years")) {
    z <- years[years$measure == measure, ]
    expect_equal(z$annual_benefit, c(.005, .01, 0, 0))
    expect_equal(z$cumulative_benefit, c(.005, .015, .015, .015))
  }
  expect_equal(years$annual_benefit[years$measure == "halys"], c(.05, .05, 0, 0))
})

test_that("health lookup receives only active cycles and reports annual factors", {
  ref <- list(ind = data.frame(census_id = 1, age1year = 40, female = 0, mmets = 1))
  cf <- list(ind = data.frame(census_id = 1, mmets = 2))
  hm <- data.frame(census_id = 1, mr_decile = 1, cycle = 0:4, mmets_cycle = 1, dead = .1)
  lookup <- data.frame(age1year = 40, female = 0, mr_decile = 1, cycle = 0:4,
                       mmets_lo = 0, mmets_hi = 100, outcome = "d_dead", slope = -.01)
  seen <- NULL
  original <- .calculate_mmet_delta_wide
  local_mocked_bindings(.calculate_mmet_delta_wide = function(changed_cycle_data, ...) {
    seen <<- changed_cycle_data$cycle
    original(changed_cycle_data, ...)
  })
  out <- apply_counterfactual_health_outcomes(cf, ref,
    hm_cycle_outcomes = hm, hm_cycle_lookup = lookup,
    scheme_profile = list(scheme_peak_year = 1, scheme_no_decline = FALSE,
                          scheme_decline_year = 1, scheme_end_year = 2))
  expect_equal(seen, 1:2)
  expect_equal(out$health_outcomes$d_dead, c(0, -.005, -.005, 0, 0))
  expect_equal(out$health_outcomes$mmets_new, c(1, 2, 2, 1, 1))
  expect_equal(out$counterfactual_health_report$scheme_effect_timeline$effect_factor,
               c(0, .5, .5, 0, 0))
  # Immediate stop is not allowed, but an appraisal may contain only baseline
  # and post-scheme years; no delta lookup should run in that case.
  seen <- NULL
  zero <- apply_counterfactual_health_outcomes(cf, ref,
    hm_cycle_outcomes = hm[c(1, 4, 5), ], hm_cycle_lookup = lookup,
    scheme_profile = list(scheme_peak_year = 0, scheme_no_decline = FALSE,
                          scheme_decline_year = 0, scheme_end_year = 1))
  expect_null(seen)
  expect_equal(zero$health_outcomes$d_dead, c(0, 0, 0))
})
