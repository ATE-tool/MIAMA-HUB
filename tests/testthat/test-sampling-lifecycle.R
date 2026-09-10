lifecycle_source <- function(mode) {
  spec <- .counterfactual_mode_spec(mode)
  ind <- data.frame(census_id = 1:8, age1year = rep(c(20, 35, 45, 65), 2),
    female = rep(0:1, 4), walktime_wkhr = 0, cycletime_wkhr = 0,
    ebiketime_wkhr = 0, pttime_wkhr = 0, sport_wkhr = 0, mmets = 5)
  ind[[spec$activity_col]][1:2] <- 1
  trips <- data.frame(census_id = 1:8, nts_tripid = 1:8,
    trip_mainmode = c(rep(mode, 2), rep("car", 6)),
    trip_distraw_km = 1, trip_durationraw_min = 10,
    trip_walkdist_km = 0, trip_walktime_min = 0,
    trip_cycledist_km = 0, trip_cycletime_min = 0,
    trip_ebikedist_km = 0, trip_ebiketime_min = 0)
  trips[[spec$trip_distance_col]][1:2] <- 1
  trips[[spec$trip_duration_col]][1:2] <- 10
  # Native e-bike evidence must work without adding cycling proxy donors.
  list(ind = ind, trips = trips)
}

test_that("repeated requests and no-op category refinements preserve snapshots across modes and units", {
  cfg <- miama_default_config()
  for (mode in c("walking", "cycling", "ebiking", "pt")) {
    suffix <- .counterfactual_mode_spec(mode)$suffix
    source <- lifecycle_source(mode)
    make <- function(prefix, ref, cf) {
      stats::setNames(list(ref, cf), paste0(prefix, c("ref_", "cf_"), suffix))
    }
    distance <- c(list(at_data_unit = "distance"), make("dist_dur_amount_", 2, 3))
    distance[[paste0("ui_dist_dur_type_", suffix)]] <- "distance"
    distance[[paste0("dist_dur_denominator_", suffix)]] <- "total"
    distance[[paste0("dist_dur_timeframe_", suffix)]] <- "week"
    duration <- distance
    duration[[paste0("ui_dist_dur_type_", suffix)]] <- "duration"
    duration[[paste0("duration_unit_", suffix)]] <- "mins"
    duration[[paste0("dist_dur_amount_ref_", suffix)]] <- 20
    duration[[paste0("dist_dur_amount_cf_", suffix)]] <- 30
    routes <- list(
      c(list(at_data_unit = "users"), make("users_count_", 1, 2)),
      c(list(at_data_unit = "trips"), make("trips_count_", 2, 3)),
      distance,
      duration,
      list(at_data_unit = "mode_share", mode_share_total_trips_basic = 8,
        mode_share_ref = stats::setNames(list(list(percent = 25)), suffix),
        mode_share_cf = stats::setNames(list(list(percent = 37.5)), suffix)))
    run <- function(hub, values) {
      hub$set_appraisal_inputs(values)
      hub$reference_data <- source
      out <- hub$build_counterfactual_data(seed = 13)
      list(ind = out$ind, trips = out$trips)
    }
    reused <- Hub$new(cfg = cfg)
    # Reverse traversal revisits routes after other input units were active.
    for (i in c(seq_along(routes), rev(seq_along(routes)))) {
      values <- c(list(ui_version = "basic", modes = mode,
        pop_total_ref_basic = 8, pop_total_cf_basic = 8), routes[[i]])
      expected <- run(Hub$new(cfg = cfg), values)
      expect_identical(run(reused, values), expected, info = paste(mode, i, "reused"))
      expect_identical(run(reused, values), expected, info = paste(mode, i, "repeat"))
      noops <- list(
        list(pop_refine_method = "pop_perc", pop_target_percent = 100),
        list(pop_refine_method = "pop_age", pop_target_age_groups = paste0("pop_", cfg$population_refinement$age$ids)),
        list(pop_refine_method = "pop_pa_level", pop_target_pa_groups = cfg$population_refinement$pa$ids))
      for (noop in noops) {
        expect_identical(run(reused, c(values, noop)), expected,
                         info = paste(mode, i, noop$pop_refine_method))
      }
      # Accepting the generated advanced tables must carry the exact staged
      # snapshots forward, including on repeated Tab 4 entry.
      profile <- lapply(values, function(x) list(input_value = x, is_filled = TRUE))
      profile$ui_version$input_value <- "advanced"
      staged_ref <- apply_reference_appraisal_scope(source, values, seed = 13)
      staged_cf <- apply_counterfactual_ui_values(init_counterfactual_data(staged_ref), values, staged_ref, seed = 13)
      staged <- prepare_trip_refinement_profile_defaults(source, profile,
        staged_reference_data = staged_ref, staged_counterfactual_data = staged_cf,
        seed = 13, cfg = cfg)
      expect_identical(staged$reference_data, staged_ref)
      expect_identical(staged$counterfactual_data, staged_cf)
      repeated <- prepare_trip_refinement_profile_defaults(source, staged$profile,
        staged_reference_data = staged_ref, staged_counterfactual_data = staged_cf,
        seed = 13, cfg = cfg)
      expect_identical(repeated$reference_data, staged_ref)
      expect_identical(repeated$counterfactual_data, staged_cf)
    }
  }
})
