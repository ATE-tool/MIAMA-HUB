benchmark_helpers <- new.env(parent = globalenv())
sys.source(testthat::test_path("..", "..", "inst", "workflows", "dev_route_benchmark.R"),
           envir = benchmark_helpers)

test_that("benchmarks keep identities and distinguish new from existing users", {
  source <- list(ind = data.frame(census_id = 1:4, age1year = 40, female = 0,
    walktime_wkhr = c(1, 0, 0, 0), cycletime_wkhr = 0, sport_wkhr = 0, mmets = 5),
    trips = data.frame(census_id = c(1, 1, 2, 3, 4), nts_tripid = c(1, 2, 1, 1, 1),
      trip_mainmode = c("walking", rep("car", 4)), trip_purpose = "Commuting",
      trip_distraw_km = 1, trip_durationraw_min = 10,
      trip_walkdist_km = c(1, 0, 0, 0, 0), trip_walktime_min = c(10, 0, 0, 0, 0),
      trip_cycledist_km = 0, trip_cycletime_min = 0))
  source <- cf_add_key_indicators(apply_reference_appraisal_scope(source,
    list(modes = c("walk", "bike", "ebike", "pt"), pop_total_ref_basic = 4)),
    c("walking", "cycling", "ebiking", "pt"))
  before <- benchmark_helpers$bm_measure(source, "walking")
  current <- benchmark_helpers$bm_benchmark(source, "walking", "existing_users",
    miama_counterfactual_defaults(), 1L)
  after <- benchmark_helpers$bm_measure(current$data, "walking")
  expect_equal(after["users"], before["users"])
  expect_gt(after["trips"], before["trips"])
  expect_gt(after["mmet_delta"], 0)
  expect_identical(current$data$trips$nts_tripid, source$trips$nts_tripid)
  new <- benchmark_helpers$bm_benchmark(source, "walking", "new_users",
    miama_counterfactual_defaults(), 1L)
  expect_gt(benchmark_helpers$bm_measure(new$data, "walking")["users"], before["users"])
  expect_false(any(new$changed_ids == 1))
  expect_error(benchmark_helpers$bm_benchmark(source, "ebiking", "existing_users",
    miama_counterfactual_defaults(), 1L), "No eligible")
})

test_that("route profiles do not supply the opposing volume target", {
  counts <- c(people = 10, users = 2, trips = 4)
  for (route in c("users", "trips")) for (workflow in c("basic", "advanced")) {
    p <- benchmark_helpers$bm_profile("cycling", route, workflow, counts, counts, miama_default_config("leeds"))
    values <- extract_input_values(p)
    other <- if (route == "users") "trips_count_cf_bike" else "users_count_cf_bike"
    expect_null(values[[other]])
    expect_equal(values[[paste0("pop_total_ref_", workflow)]], 10)
  }
})
