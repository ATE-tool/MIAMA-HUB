assumption_test_profile <- function(unit = "trips", version = "basic") {
  field <- function(x, filled = FALSE) list(default_value = x, input_value = if (filled) x else NULL,
                                          is_filled = filled, additional_data = list())
  p <- list(modes = field(c("walk", "bike", "ebike", "pt"), TRUE),
            at_data_unit = field(unit, TRUE), ui_version = field(version, TRUE),
            geo_level = field("lad", TRUE), geo_id = field("test", TRUE),
            ui_trips_refine_show_chars = field(FALSE), trips_refine_choice = field(character()),
            ui_mode_share_show_options = field(FALSE), mode_share_total_unit = field("trips"),
            assump_new_user_percent = field(10), assump_induced_trips_percent = field(10),
            assump_new_user_activity_pattern = field("observed_donor_patterns"),
            appraisal_model_parameters = field(NULL), appraisal_sampling_seed = field(1L))
  for (m in c("walk", "bike", "ebike", "pt")) {
    for (prefix in c(.assumption_catalogue()$prefix, "assump_trip_source_shares_", "assump_mmet_per_hour_"))
      p[[paste0(prefix, m)]] <- field(NA_real_)
    p[[paste0("ui_dist_dur_type_", m)]] <- field("distance")
    p[[paste0("trips_spread_mean_cf_", m)]] <- field(1)
    p[[paste0("pop_number_cf_", m, "_advanced")]] <- field(1)
  }
  prepare_assumption_profile(p)
}

test_that("getters use schema IDs, are pure, and switch active trip size", {
  for (unit in c("users", "trips", "distance", "mode_share")) {
    for (version in c("basic", "advanced")) {
      p <- assumption_test_profile(unit, version)
      before <- serialize(p, NULL)
      for (tab in 2:4) {
        out <- get_appraisal_assumptions(p, tab)
        expect_true(all(names(out) %in% names(p)))
        expect_true(all(get_appraisal_assumption_dependencies(p, tab) %in% names(p)))
      }
      expect_identical(before, serialize(p, NULL))
    }
  }
  p <- assumption_test_profile("distance")
  for (m in c("walk", "bike", "ebike", "pt")) p[[paste0("ui_dist_dur_type_", m)]]$default_value <- "duration"
  out <- get_appraisal_assumptions(p, 2)
  expect_true(all(paste0("assump_trip_duration_min_", c("walk", "bike", "ebike", "pt")) %in% names(out)))
  expect_false(any(startsWith(names(out), "assump_trip_distance_km_")))
})

test_that("intensities remain in the full inventory, not sampling cards", {
  for (version in c("basic", "advanced")) {
    p <- assumption_test_profile("trips", version)
    expect_true(any(startsWith(names(get_appraisal_assumptions(p)), "assump_mmet_per_hour_")))
    for (tab in 2:4) expect_false(any(startsWith(names(get_appraisal_assumptions(p, tab)) %||% character(), "assump_mmet_per_hour_")))
  }
})

test_that("diversion defaults identify the actual source and user overrides", {
  cfg <- miama_default_config()
  trips <- data.frame(nts_tripid = 1:4, trip_mainmode = c("Car driver", "Car driver", "Car driver", "Walk"))
  ref <- .reference_diversion_source_defaults(trips, "cycling", cfg)
  expect_identical(ref$source, "REF trip mix (proxy)")
  expect_equal(ref$value$car$percent, 75)
  src <- .reference_diversion_source_defaults(data.frame(), "cycling", cfg, trips)
  expect_identical(src$source, "Source trip mix (proxy)")
  expect_identical(src$value, ref$value)
  empty <- .reference_diversion_source_defaults(data.frame(), "cycling", cfg, data.frame())
  expect_identical(empty$source, "Uniform fallback (no usable trip mix)")
  fixed <- .reference_diversion_source_defaults(trips, "ebiking", cfg)
  expect_identical(fixed$source, "Fixed assumption (configured source shares)")
  expect_equal(fixed$value$car$percent, 100 / 3)

  p <- prepare_assumption_profile(assumption_test_profile(), source_data = list(trips = trips), restore = TRUE)
  expect_identical(p$assump_trip_source_shares_bike$additional_data$source, src$source)
  p$assump_trip_source_shares_bike$input_value <- list(car = list(percent = 100))
  p$assump_trip_source_shares_bike$is_filled <- TRUE
  expect_identical(get_appraisal_assumptions(p)$assump_trip_source_shares_bike$display$source, "User provided")
  expect_identical(p$assump_trip_source_shares_bike$additional_data$source, src$source)
})

test_that("defaults and explicit equal overrides survive refresh and serialization", {
  p <- assumption_test_profile()
  f <- "assump_trip_speed_kmh_walk"
  p[[f]]$input_value <- p[[f]]$default_value
  p[[f]]$is_filled <- TRUE
  cfg <- miama_default_config()
  cfg$assumptions$fixed$speed$walk <- 99
  expect_identical(prepare_assumption_profile(p, cfg = cfg), p)
  expect_identical(get_appraisal_assumptions(unserialize(serialize(p, NULL))), get_appraisal_assumptions(p))
  restored <- prepare_assumption_profile(p, cfg = cfg, restore = TRUE)
  expect_equal(restored[[f]]$default_value, 99)
  expect_false(restored[[f]]$is_filled)
  expect_error(get_appraisal_assumptions(p, 5), "tab")
})

test_that("explicit refinements supersede scalar means only while active", {
  p <- assumption_test_profile("users", "advanced")
  p$trips_spread_mean_cf_walk$is_filled <- TRUE
  p$trips_spread_mean_cf_walk$input_value <- 1
  expect_true("assump_trip_distance_km_walk" %in% names(get_appraisal_assumptions(p, 4)))
  p$ui_trips_refine_show_chars$default_value <- TRUE
  p$trips_refine_choice$default_value <- "trips_distance_purpose"
  expect_false("assump_trip_distance_km_walk" %in% names(get_appraisal_assumptions(p, 4)))
})

test_that("profile assumptions drive conversion, intensity and new-user activity", {
  p <- assumption_test_profile("distance")
  p$assump_trip_distance_km_walk$input_value <- 2
  p$assump_trip_distance_km_walk$is_filled <- TRUE
  p$assump_trip_speed_kmh_walk$input_value <- 4
  p$assump_trip_speed_kmh_walk$is_filled <- TRUE
  p$assump_mmet_per_hour_walk$input_value <- 3
  p$assump_mmet_per_hour_walk$is_filled <- TRUE
  values <- extract_input_values(p)
  expect_true(values$.assumptions_enabled)
  expect_equal(.assumption_values(values)$assump_trip_duration_min_walk, 30)
  values$dist_dur_amount_cf_walk <- 20
  expect_equal(.tab2_dist_dur_trip_target(values, list(trips = data.frame(), ind = data.frame()),
    "cf", .counterfactual_mode_spec("walking"))$trip_rows, 10L)
  constants <- .assumption_cf_constants(values, miama_counterfactual_defaults())
  expect_equal(constants$mmet_walking, 3)
  trips <- data.frame(trip_mainmode = 4L, trip_distraw_km = 2,
                      trip_walkdist_km = 0, trip_walktime_min = 0)
  switched <- .switch_trips_to_active_mode(trips, 1L, .counterfactual_mode_spec("walking"), constants)
  expect_equal(switched$trip_walktime_min, 30)
  expect_equal(mean(.assumption_new_user_activity(c(1, 3), values, "walk")),
               values$assump_trips_per_user_per_week_walk / 2)
  expect_equal(.appraisal_seed(p), 1L)
  expect_error(.appraisal_seed(p, -1), "seed")
})

test_that("inactive saved user fields do not suppress trip-route assumptions", {
  p <- assumption_test_profile()
  p$users_count_cf_walk <- list(is_filled = TRUE, input_value = 100, default_value = 100)
  expect_false(.assumption_explicit_users(p, "walk"))
})

test_that("HUB restores effective model configuration from the appraisal", {
  p <- assumption_test_profile()
  cfg <- miama_default_config()
  cfg$counterfactual$population$new_user_percent_default <- 90
  hub <- Hub$new(cfg)
  hub$set_appraisal_inputs(p)
  expect_equal(hub$cfg$counterfactual$population$new_user_percent_default, 10)
  expect_identical(hub$get_appraisal_assumptions(), get_appraisal_assumptions(hub$appraisal_inputs))
})

test_that("stage updates preserve assumption metadata and preferred values", {
  p <- assumption_test_profile()
  field <- "assump_new_user_percent"
  p[[field]]$input_value <- 10
  p[[field]]$is_filled <- TRUE
  updates <- list(assump_new_user_percent = 80)
  expect_identical(apply_refinement_defaults_to_profile(p, updates)[[field]], p[[field]])
  expect_identical(apply_reference_defaults_to_profile(p, updates)[[field]], p[[field]])
  expect_error(Hub$new()$set_appraisal_inputs(list(default_trip_distance_walk = list())),
               "UI appraisal schema")
  p$geo_id$input_value <- "another-city"
  changed <- prepare_assumption_profile(p)
  expect_equal(changed[[field]]$input_value, 10)
  expect_match(changed[[field]]$additional_data$geography, "another-city")
})
