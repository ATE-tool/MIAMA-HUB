replication_source <- function() {
  list(ind = data.frame(census_id = 1:6, age1year = 40, female = 0,
    walktime_wkhr = c(1, 1, 0, 0, 0, 0),
    cycletime_wkhr = c(0, 0, 1, 1, 0, 0), sport_wkhr = 0, mmets = 5),
    trips = data.frame(census_id = rep(1:6, each = 2), nts_tripid = 1:12,
      trip_mainmode = rep(c("walking", "walking", "cycling", "cycling", "car", "car"), each = 2),
      trip_walkdist_km = c(rep(2, 4), rep(0, 8)),
      trip_walktime_min = c(rep(20, 4), rep(0, 8)),
      trip_cycledist_km = c(rep(0, 4), rep(2, 4), rep(0, 4)),
      trip_cycletime_min = c(rep(0, 4), rep(20, 4), rep(0, 4)),
      trip_distraw_km = 2, trip_durationraw_min = 20))
}

test_that("person weighting does not reduce sampled people or donor pools", {
  source <- replication_source()
  values <- list(modes = "bike", at_data_unit = "users",
                 users_count_ref_bike = 8, users_count_cf_bike = 8)
  cfg <- miama_default_config(dataset_size = "leeds")
  one <- suppressWarnings(apply_reference_appraisal_scope(source, values,
    seed = 42, cfg = cfg))
  cfg$population$person_weight <- cfg$population$source_person_weight
  expanded <- suppressWarnings(apply_reference_appraisal_scope(source, values,
    seed = 42, cfg = cfg))
  expect_identical(one$ind, expanded$ind)
  expect_identical(one$trips, expanded$trips)
  expect_equal(sum(one$ind$ref_user_scope_bike), 8)
  expect_equal(sum(one$ind$ref_in_scope), 24)
})

test_that("person replacement preserves identities, ownership and stable source rates", {
  source <- replication_source()
  values <- list(modes = "bike", at_data_unit = "users",
                 users_count_ref_bike = 8, users_count_cf_bike = 8)
  ref <- suppressWarnings(apply_reference_appraisal_scope(source, values, seed = 42))
  expect_equal(sum(ref$ind$ref_in_scope), 24)
  expect_equal(sum(ref$ind$ref_user_scope_bike), 8)
  expect_equal(anyDuplicated(ref$ind$census_id), 0)
  expect_equal(anyDuplicated(ref$trips$nts_tripid), 0)
  expect_true(all(ref$trips$census_id %in% ref$ind$census_id))
  expect_equal(source, replication_source())
  repeat_ref <- suppressWarnings(apply_reference_appraisal_scope(ref, values, seed = 42))
  expect_equal(sum(repeat_ref$ind$ref_in_scope), 24)
  expect_equal(nrow(repeat_ref$ind), nrow(ref$ind))
  cf <- apply_counterfactual_ui_values(init_counterfactual_data(ref), values, ref)
  expect_equal(cf$ind$mmets, ref$ind$mmets)
  expect_equal(sum(cf$ind$cf_user_scope_bike), 8)
})

test_that("CF targets can recruit copies beyond the source size", {
  source <- replication_source()
  values <- list(modes = "bike", at_data_unit = "users",
    users_count_ref_bike = 1, users_count_cf_bike = 12)
  ref <- suppressWarnings(apply_reference_appraisal_scope(source, values))
  cf <- suppressWarnings(apply_counterfactual_ui_values(init_counterfactual_data(ref), values, ref))
  expect_equal(sum(ref$ind$ref_user_scope_bike), 1)
  expect_equal(sum(cf$ind$cf_user_scope_bike), 12)
  expect_equal(anyDuplicated(cf$ind$census_id), 0)
})

test_that("zero native e-bike users can use a labelled cycling person proxy", {
  values <- list(modes = "ebike", at_data_unit = "users",
                 users_count_ref_ebike = 8, users_count_cf_ebike = 8)
  ref <- suppressWarnings(apply_reference_appraisal_scope(replication_source(), values))
  expect_equal(sum(ref$ind$ref_user_scope_ebike), 8)
  selected <- ref$ind$ref_user_scope_ebike
  expect_true(all(ref$ind$.miama_reference_mode_proxy[selected] == "cycling"))
  cf <- apply_counterfactual_ui_values(init_counterfactual_data(ref), values, ref)
  expect_equal(cf$ind$mmets, ref$ind$mmets)
})

test_that("copied people get exactly one donor history per appraisal person", {
  source <- replication_source()
  ref <- suppressWarnings(apply_reference_appraisal_scope(source,
    list(modes = "bike", pop_total_ref_basic = 12)))
  cf <- init_counterfactual_data(ref)
  cf$ind$mmets <- cf$ind$mmets + 1
  hm <- expand.grid(census_id = 1:6, cycle = 1:2)
  hm$mr_decile <- 1
  hm$mmets_cycle <- 5
  hm$dead <- 0.1
  lookup <- data.frame(age1year = 40, female = 0, mr_decile = 1,
    cycle = 1:2, mmets_lo = 0, mmets_hi = 100, outcome = "d_dead", slope = -0.01)
  out <- apply_counterfactual_health_outcomes(cf, ref,
    hm_cycle_outcomes = hm, hm_cycle_lookup = lookup)
  expect_equal(nrow(out$health_outcomes), 24)
  expect_equal(anyDuplicated(out$health_outcomes[c("census_id", "cycle")]), 0)
  expect_equal(out$health_outcomes$d_dead, rep(-0.01, 24))
  expect_equal(sum(out$health_outcomes$d_dead), -0.24)
  cfg <- miama_default_config()
  cfg$population$person_weight <- 1
  one <- prepare_results_data(out, ref, cfg = cfg,
                              results_request = list(res_outcomes = "mortality"))
  cfg$population$person_weight <- 20
  twenty <- prepare_results_data(out, ref, cfg = cfg,
                                 results_request = list(res_outcomes = "mortality"))
  expect_equal(twenty$results_table$delta_value, 20 * one$results_table$delta_value)
  expect_equal(twenty$results_table$delta_value, -4.8)
  unchanged <- apply_counterfactual_health_outcomes(init_counterfactual_data(ref), ref,
    hm_cycle_outcomes = hm, hm_cycle_lookup = lookup)
  expect_true(all(unchanged$health_outcomes$d_dead == 0))
})

test_that("all Tab 2 units and modes share the person fallback in both UI versions", {
  source <- replication_source()
  source$ind$pttime_wkhr <- c(0, 0, 0, 0, 1, 1)
  pt <- source$trips$census_id %in% 5:6
  source$trips$trip_mainmode[pt] <- "pt"
  source$trips$trip_walktime_min[pt] <- 20
  source$trips$trip_walkdist_km[pt] <- 2
  for (version in c("basic", "advanced")) {
    for (mode in c("walk", "bike", "ebike", "pt")) {
      for (route in c("users", "trips", "distance", "duration", "mode_share")) {
        values <- list(modes = mode, ui_version = version,
          at_data_unit = if (route == "duration") "distance" else route,
          mode_share_total_trips = 40)
        for (scenario in c("ref", "cf")) {
          field <- switch(route, users = "users_count", trips = "trips_count",
                           "dist_dur_amount")
          amount <- switch(route, users = 8, trips = 40, duration = 800, 80)
          values[[paste0(field, "_", scenario, "_", mode)]] <- amount
          values[[paste0("mode_share_", scenario)]] <-
            setNames(list(list(percent = 100)), mode)
        }
        values[[paste0("ui_dist_dur_type_", mode)]] <- if (route == "duration") "duration" else "distance"
        profile <- lapply(values, function(x) list(input_value = x, default_value = x, is_filled = TRUE))
        staged <- suppressWarnings(prepare_refinement_profile_defaults(source, profile))
        expect_true(nrow(staged$reference_view$ind) > 0,
                  info = paste(version, mode, route))
        expect_equal(anyDuplicated(staged$reference_data$ind$census_id), 0)
        expect_true(all(staged$reference_data$trips$census_id %in% staged$reference_data$ind$census_id))
      }
    }
  }
})

test_that("replacement retains exclusions and inconsistent totals still fail", {
  values <- list(modes = "bike", users_count_ref_bike = 8, pop_total_ref_basic = 7)
  expect_error(apply_reference_appraisal_scope(replication_source(), values), "cannot exceed")
  source <- replication_source()
  source$ind$cycletime_wkhr <- 0
  expect_error(apply_reference_appraisal_scope(source,
    list(modes = "bike", users_count_ref_bike = 2)), "No eligible source people")
})

test_that("string IDs remain unique across repeated copying", {
  source <- replication_source()
  source$ind$census_id <- paste0("p", source$ind$census_id)
  source$trips$census_id <- paste0("p", source$trips$census_id)
  source$trips$nts_tripid <- paste0("t", source$trips$nts_tripid)
  out <- .append_person_donors(source, c(1, 1))
  out <- .append_person_donors(out, c(2, 2))
  expect_equal(anyDuplicated(out$ind$census_id), 0)
  expect_equal(anyDuplicated(out$trips$nts_tripid), 0)
})

test_that("advanced re-scoping restores activity for newly copied CF people", {
  source <- .prepare_mode_features(replication_source())
  source$ind$cf_user_scope_bike <- source$ind$cycletime_wkhr > 0
  source$ind$ref_user_scope_bike <- source$ind$cf_user_scope_bike
  source$ind$ref_in_scope <- TRUE
  source$ind$cf_in_scope <- TRUE
  scoped <- suppressWarnings(.rescope_staged_snapshot(source,
    list(ui_version = "advanced", modes = "bike", at_data_unit = "users",
         pop_total_cf_advanced = 12, pop_number_cf_bike_advanced = 8),
    scenario = "cf"))
  expect_equal(sum(scoped$ind$ref_in_scope), 12)
  expect_equal(sum(scoped$ind$ref_user_scope_bike), 8)
  expect_false(anyNA(scoped$ind$cycletime_wkhr))
  expect_equal(anyDuplicated(scoped$ind$census_id), 0)
})
