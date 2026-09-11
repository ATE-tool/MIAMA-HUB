# Fixed travel records with real HM identities let this test exercise the final
# health pipeline without loading a whole geography or precomputing CF outcomes.
t3_source <- function(mode, cfg) {
  attrs <- arrow::open_dataset(cfg$sources$sp_attributes$path) |>
    dplyr::select(census_id, age1year, female) |> dplyr::collect()
  ind <- as.data.frame(attrs[1:8, ])
  hm <- load_hm_outcomes(cfg, census_ids = ind$census_id)
  ind$mmets <- hm$mmets[match(ind$census_id, hm$census_id)]
  for (col in c("walktime_wkhr", "cycletime_wkhr", "ebiketime_wkhr",
                "pttime_wkhr", "sport_wkhr")) ind[[col]] <- 0
  spec <- .counterfactual_mode_spec(mode)
  ind[[spec$activity_col]][1:2] <- 1
  trips <- data.frame(census_id = rep(ind$census_id, each = 2), nts_tripid = 1:16,
    trip_mainmode = c(rep(mode, 4), rep("car", 12)), trip_purpose = "Commuting",
    trip_distraw_km = 1, trip_durationraw_min = 10,
    trip_walkdist_km = 0, trip_walktime_min = 0,
    trip_cycledist_km = 0, trip_cycletime_min = 0,
    trip_ebikedist_km = 0, trip_ebiketime_min = 0)
  trips[[spec$trip_distance_col]][1:4] <- 1
  trips[[spec$trip_duration_col]][1:4] <- 10
  list(ind = ind, trips = trips)
}

test_that("accepted advanced tables survive real final health-result construction", {
  cfg <- miama_default_config("sample")
  for (mode in .miama_supported_modes()) for (route in c("users", "trips", "distance", "duration", "mode_share")) {
    source <- t3_source(mode, cfg)
    suffix <- .counterfactual_mode_spec(mode)$suffix
    values <- list(ui_version = "advanced", modes = mode, at_data_unit = route,
      pop_total_ref_advanced = 8, pop_total_cf_advanced = 8,
      scheme_peak_year = 0, res_outcomes = "mortality", res_aggregation = "total")
    prefix <- if (route == "users") "users_count_" else "trips_count_"
    values[[paste0(prefix, "ref_", suffix)]] <- if (route == "users") 2 else 4
    values[[paste0(prefix, "cf_", suffix)]] <- if (route == "users") 3 else 6
    if (route %in% c("distance", "duration", "mode_share")) {
      values[[paste0(prefix, "ref_", suffix)]] <- NULL
      values[[paste0(prefix, "cf_", suffix)]] <- NULL
      if (route == "mode_share") {
        values$mode_share_total_trips <- 16
        values$mode_share_ref <- setNames(list(list(percent = 25)), suffix)
        values$mode_share_cf <- setNames(list(list(percent = 37.5)), suffix)
      } else {
        values$at_data_unit <- "distance"
        values[[paste0("ui_dist_dur_type_", suffix)]] <- route
        values[[paste0("dist_dur_denominator_", suffix)]] <- "total"
        values[[paste0("dist_dur_timeframe_", suffix)]] <- "week"
        values[[paste0("dist_dur_amount_ref_", suffix)]] <- if (route == "distance") 4 else 40
        values[[paste0("dist_dur_amount_cf_", suffix)]] <- if (route == "distance") 6 else 60
      }
    }
    profile <- lapply(values, function(x) list(input_value = x, is_filled = TRUE))
    for (scenario in c("ref", "cf")) {
      for (field in c(paste0("pop_number_", scenario, "_", suffix, "_advanced"),
                      paste0("trips_number_", scenario, "_", suffix))) {
        profile[[field]] <- list(input_value = NULL, default_value = NULL, is_filled = FALSE)
      }
    }
    staging_source <- source
    # Production UI stages synthpop before attaching HM data at results time.
    if (route == "duration") staging_source$ind$mmets <- NULL
    tab3 <- prepare_refinement_profile_defaults(staging_source, profile, cfg = cfg, seed = 13)
    tab4 <- prepare_trip_refinement_profile_defaults(staging_source, tab3$profile,
      cfg = cfg, seed = 13, staged_reference_data = tab3$reference_data,
      staged_counterfactual_data = tab3$counterfactual_data)

    run <- function(profile) {
      hub <- Hub$new(cfg = cfg)
      hub$reference_data <- source
      hub$refinement_reference_data <- tab4$reference_data
      hub$refinement_counterfactual_data <- tab4$counterfactual_data
      out <- hub$build_results(profile, seed = 13)
      expect_gt(out$health_impacts$n_cycle_rows, 0)
      expect_true("mortality" %in% out$results_data$results_table$outcome)
      out
    }
    original <- run(tab4$profile)
    repeated <- run(tab4$profile)
    expect_identical(original$counterfactual_data$ind, repeated$counterfactual_data$ind)
    expect_equal(original$results_data$results_table, repeated$results_data$results_table)
    if (route != "duration") {
      expect_equal(original$counterfactual_data$ind$cf_mmet_delta,
                   tab4$counterfactual_data$ind$cf_mmet_delta, info = paste(mode, route, "staged exposure"))
    } else expect_true(all(is.finite(original$counterfactual_data$ind$cf_mmet_delta)))

    # A Tab 4 override changes trips, never the accepted Tab 3 people contract.
    edited <- tab4$profile
    field <- paste0("trips_number_cf_", suffix)
    target <- .ui_value(extract_input_values(edited), field, edited[[field]]$default_value)
    edited[[field]] <- list(input_value = target + 2, is_filled = TRUE)
    changed <- run(edited)
    for (scenario in c("ref", "cf")) {
      key <- if (scenario == "ref") "reference_data" else "counterfactual_data"
      scope <- paste0(scenario, "_in_scope")
      users <- paste0(scenario, "_user_scope_", suffix)
      a <- original[[key]]$ind
      b <- changed[[key]]$ind
      staged <- tab4[[key]]$ind
      expect_equal(sum(a[[scope]]), 8, info = paste(mode, route, scenario))
      expect_equal(sum(a[[users]]), sum(staged[[users]]), info = paste(mode, route, scenario))
      expect_identical(a$census_id[a[[scope]]], staged$census_id[staged[[scope]]])
      expect_identical(a$census_id[a[[scope]]], b$census_id[b[[scope]]])
      expect_identical(a$census_id[a[[users]]], b$census_id[b[[users]]])
    }
    view <- materialize_appraisal_scope(changed$counterfactual_data, "cf")
    spec <- .counterfactual_mode_spec(mode)
    expect_equal(sum(spec$trip_filter(view$trips) & !is.na(view$trips$nts_tripid)), target + 2)
    expect_true(all(is.finite(changed$counterfactual_data$ind$cf_mmet_delta)))
  }
})

test_that("manual Tab 3 counts remain binding through final results", {
  cfg <- miama_default_config("sample")
  source <- t3_source("walking", cfg)
  values <- list(ui_version = "advanced", modes = "walking", at_data_unit = "trips",
    trips_count_ref_walk = 4, trips_count_cf_walk = 6,
    pop_total_ref_advanced = 8, pop_total_cf_advanced = 8,
    scheme_peak_year = 0, res_outcomes = "mortality", res_aggregation = "total")
  profile <- lapply(values, function(x) list(input_value = x, is_filled = TRUE))
  for (scenario in c("ref", "cf")) for (field in c(
      paste0("pop_number_", scenario, "_walk_advanced"), paste0("trips_number_", scenario, "_walk"))) {
    profile[[field]] <- list(input_value = NULL, default_value = NULL, is_filled = FALSE)
  }
  tab3 <- prepare_refinement_profile_defaults(source, profile, cfg = cfg, seed = 13)
  profile <- tab3$profile
  for (scenario in c("ref", "cf")) {
    profile[[paste0("pop_total_", scenario, "_advanced")]]$input_value <- 6
    profile[[paste0("pop_total_", scenario, "_advanced")]]$is_filled <- TRUE
    profile[[paste0("pop_number_", scenario, "_walk_advanced")]]$input_value <- 2
    profile[[paste0("pop_number_", scenario, "_walk_advanced")]]$is_filled <- TRUE
  }
  tab4 <- prepare_trip_refinement_profile_defaults(source, profile, cfg = cfg, seed = 13,
    staged_reference_data = tab3$reference_data, staged_counterfactual_data = tab3$counterfactual_data)
  for (target in c(6, 9)) {
    accepted <- tab4$profile
    accepted$trips_number_cf_walk <- list(input_value = target, is_filled = TRUE)
    hub <- Hub$new(cfg = cfg)
    hub$reference_data <- source
    hub$refinement_reference_data <- tab4$reference_data
    hub$refinement_counterfactual_data <- tab4$counterfactual_data
    out <- hub$build_results(accepted, seed = 13)
    expect_equal(sum(out$reference_data$ind$ref_in_scope), 6)
    expect_equal(sum(out$counterfactual_data$ind$cf_in_scope), 6)
    expect_equal(sum(out$reference_data$ind$ref_user_scope_walk), 2)
    expect_equal(sum(out$counterfactual_data$ind$cf_user_scope_walk), 2)
    # This caught final reconstruction replacing a staged person despite
    # preserving the accepted total. Check membership, not only its size.
    expect_setequal(out$counterfactual_data$ind$census_id[out$counterfactual_data$ind$cf_in_scope],
      tab4$counterfactual_data$ind$census_id[tab4$counterfactual_data$ind$cf_in_scope])
    view <- materialize_appraisal_scope(out$counterfactual_data, "cf")
    expect_equal(sum(.counterfactual_mode_spec("walking")$trip_filter(view$trips)), target)
    expect_gt(out$health_impacts$n_cycle_rows, 0)
    if (target == 6) {
      expect_equal(out$counterfactual_data$ind$cf_mmet_delta,
                   tab4$counterfactual_data$ind$cf_mmet_delta)
      expect_equal(out$counterfactual_data$ind$mmets, tab4$counterfactual_data$ind$mmets)
    }
  }
})
