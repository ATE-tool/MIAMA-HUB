test_that("staged finalization keeps people while allowing shifted and induced trips", {
  source <- list(ind = data.frame(census_id = 1:6, age1year = 40, female = 0,
    walktime_wkhr = c(1, 1, 0, 0, 0, 0), cycletime_wkhr = 0, sport_wkhr = 0,
    mmets = c(2.5, 2.5, 0, 0, 0, 0)),
    trips = data.frame(census_id = rep(1:6, each = 2), nts_tripid = 1:12,
      trip_mainmode = c(rep("walking", 4), rep("car", 8)),
      trip_purpose = "Commuting", trip_distraw_km = 1, trip_durationraw_min = 10,
      trip_walkdist_km = c(rep(1, 4), rep(0, 8)),
      trip_walktime_min = c(rep(10, 4), rep(0, 8)),
      trip_cycledist_km = 0, trip_cycletime_min = 0))
  cfg <- miama_default_config()
  values <- list(ui_version = "advanced", modes = "walking", at_data_unit = "trips",
    pop_total_ref_advanced = 6, pop_total_cf_advanced = 6,
    pop_number_ref_walk_advanced = 2, pop_number_cf_walk_advanced = 2,
    trips_number_ref_walk = 4, trips_number_cf_walk = 4)
  ref <- apply_reference_appraisal_scope(source, values, cfg = cfg)
  cf <- apply_counterfactual_ui_values(init_counterfactual_data(ref), values, ref)
  for (induced in c(0, 100)) {
    edited <- modifyList(values, list(trips_number_cf_walk = 6,
      assump_induced_trips_percent = induced,
      assump_trip_source_shares_walk = list(car = list(percent = 100))))
    out <- .finalize_staged_appraisal(ref, cf, edited, cfg, 1)
    expect_identical(out$counterfactual$ind$cf_in_scope, cf$ind$cf_in_scope)
    expect_identical(out$counterfactual$ind$cf_user_scope_walk, cf$ind$cf_user_scope_walk)
    expect_equal(sum(out$counterfactual$trips$cf_induced), if (induced == 100) 2 else 0)
    expect_equal(sum(.counterfactual_mode_spec("walking")$trip_filter(out$counterfactual$trips)), 6)
    repeated <- .finalize_staged_appraisal(ref, cf, edited, cfg, 1)
    expect_identical(out$counterfactual$ind$cf_mmet_delta, repeated$counterfactual$ind$cf_mmet_delta)
    reduced <- .finalize_staged_appraisal(ref, out$counterfactual,
      modifyList(edited, list(trips_number_cf_walk = 0)), cfg, 1)
    expect_equal(sum(.counterfactual_mode_spec("walking")$trip_filter(reduced$counterfactual$trips)), 0)
    expect_identical(reduced$counterfactual$ind$cf_user_scope_walk, cf$ind$cf_user_scope_walk)
  }
  edited <- modifyList(values, list(trips_number_ref_walk = 3))
  out <- .finalize_staged_appraisal(ref, cf, edited, cfg, 1)
  expect_identical(out$reference$ind$ref_in_scope, ref$ind$ref_in_scope)
  expect_identical(out$reference$ind$ref_user_scope_walk, ref$ind$ref_user_scope_walk)
  expect_equal(sum(out$reference$trips$ref_trip_scope_walk), 3)
  expect_error(.finalize_staged_appraisal(ref, cf,
    modifyList(values, list(pop_total_cf_advanced = 5)), cfg, 1), "Return to Tab 3")
})
