test_that("sampling presets populate both profile defaults and runtime constants", {
  trips <- data.frame(nts_tripid = 1:4,
    trip_mainmode = c("Car driver", "Car driver", "Walk", "Bus"))
  for (preset in c("MIAMA", "AMAT/TAG", "HEAT", "uniform")) {
    cfg <- miama_default_config(assumption_preset = preset)
    constants <- miama_counterfactual_defaults(cfg)
    expect_equal(constants$new_user_percent_default, 10)
    expect_equal(constants$assump_induced_trips_percent_default,
                 if (preset == "AMAT/TAG") 23 else 10)
    for (mode in c("walking", "cycling", "ebiking")) {
      pie <- .reference_diversion_source_defaults(NULL, mode, cfg)
      shares <- .normalize_diversion_source_shares(pie$value, mode)
      expect_equal(sum(shares), 1)
      expect_false(mode %in% names(shares))
      expect_true(all(is.finite(shares) & shares >= 0))
      target <- .cf_source_diversion_target(list(), "unused", mode, constants)
      expect_equal(target$shares[sort(names(target$shares))], shares[sort(names(shares))])
    }
    profile <- list(assump_new_user_percent = list(), assump_induced_trips_percent = list(),
                    assump_trip_source_shares_bike = list(), appraisal_model_parameters = list())
    profile <- prepare_assumption_profile(profile, cfg = cfg, source_data = list(trips = trips))
    expect_equal(profile$assump_induced_trips_percent$default_value,
                 constants$assump_induced_trips_percent_default)
    expect_identical(profile$appraisal_model_parameters$default_value$assumptions$sampling_preset, preset)
  }
})

test_that("documented receiver-specific proportions are exact", {
  expect_identical(miama_default_config()$assumptions$sampling_preset, "AMAT/TAG")
  tag <- miama_default_config(assumption_preset = "AMAT/TAG")
  expect_equal(tag$counterfactual$trips$source_mode_shares$cycling,
               c(driving = 30, pt = 33, walking = 14) / 77)
  heat <- miama_default_config(assumption_preset = "HEAT")
  expect_equal(heat$counterfactual$trips$source_mode_shares$cycling,
               c(driving = .3, pt = .5, walking = .2))
  miama <- miama_default_config(assumption_preset = "MIAMA")
  expect_equal(miama$counterfactual$trips$source_mode_shares$walking,
               c(driving = .2, pt = .6, cycling = .2))
  expect_equal(miama$counterfactual$trips$source_mode_shares$ebiking,
               c(driving = .3, pt = .3, cycling = .3, walking = .1))
  expect_error(miama_default_config(assumption_preset = "invalid"), "Unknown assumption preset")
})

test_that("observed composition precedes every fixed preset", {
  trips <- data.frame(nts_tripid = 1:4,
                      trip_mainmode = c("Car driver", "Car driver", "Car driver", "Walk"))
  for (preset in c("AMAT/TAG", "MIAMA", "HEAT", "uniform")) {
    cfg <- miama_default_config(assumption_preset = preset)
    ref <- .reference_diversion_source_defaults(trips, "cycling", cfg)
    source <- .reference_diversion_source_defaults(NULL, "cycling", cfg, trips)
    expect_equal(ref$value$car$percent, 75)
    expect_identical(ref$source, "REF trip mix (proxy)")
    expect_identical(source$source, "Source trip mix (proxy)")
    expect_equal(ref$value, source$value)
    runtime <- .cf_source_diversion_target(list(), "bike", "cycling",
                                          miama_counterfactual_defaults(cfg), trips)
    expect_equal(runtime$shares[["driving"]], .75)
    expect_identical(runtime$source, "reference_donor_composition")
  }
})

test_that("explicit profile values supersede preset source shares and percentages", {
  constants <- miama_counterfactual_defaults(miama_default_config(assumption_preset = "AMAT/TAG"))
  target <- .cf_source_diversion_target(
    list(assump_trip_source_shares_bike = list(walk = list(percent = 100))),
    "bike", "cycling", constants)
  expect_equal(target$shares, c(walking = 1))
  expect_equal(target$source, "ui")
})
