test_that("every dataset uses one appraisal record per real person", {
  for (size in c("sample", "leeds", "full")) {
    cfg <- miama_default_config(dataset_size = size)
    expect_equal(cfg$population$person_weight, 1)
    expect_equal(cfg$population$units_contract, "one_record_one_person_v1")
    expect_gt(cfg$population$source_person_weight, 1)
  }
  expect_equal(.results_person_weight(list()), 1)
})

test_that("unit weight changes absolute totals but not relative health effects", {
  cfg <- miama_default_config(dataset_size = "leeds")
  health <- data.frame(census_id = 1:2, cycle = 1, age1year = 50,
    female = 0, dead = .1, d_dead = -.01, haly = .8, d_haly = .02)
  input <- list(health_outcomes = health)
  request <- list(res_outcomes = c("mortality", "halys"))
  out <- prepare_results_data(input, cfg = cfg, results_request = request)
  tab <- results_filter_health_data(out)
  expect_equal(tab$population, c(2, 2))
  expect_equal(tab$prevented_value[tab$outcome == "mortality"], .02)
  expect_equal(tab$prevented_value[tab$outcome == "halys"], .04)
  expect_identical(input$health_outcomes, health)
  cfg$population$person_weight <- cfg$population$source_person_weight
  old <- results_filter_health_data(prepare_results_data(input, cfg = cfg,
    results_request = request))
  expect_equal(old$prevented_value / tab$prevented_value, rep(163.552, 2))
  expect_equal(old$percent_reduction, tab$percent_reduction)
  expect_equal(old$prevented_per_100000, tab$prevented_per_100000)
})

test_that("unit weighting leaves a thousand-person sampling target unchanged", {
  source <- list(ind = data.frame(census_id = 1:1000, age1year = 40,
    female = 0, walktime_wkhr = 1, cycletime_wkhr = 0, sport_wkhr = 0, mmets = 5))
  values <- list(modes = "walk", at_data_unit = "users",
    users_count_ref_walk = 1000, users_count_cf_walk = 1000)
  cfg <- miama_default_config(dataset_size = "leeds")
  one <- apply_reference_appraisal_scope(source, values, seed = 42, cfg = cfg)
  cfg$population$person_weight <- cfg$population$source_person_weight
  old <- apply_reference_appraisal_scope(source, values, seed = 42, cfg = cfg)
  expect_identical(one$ind, old$ind)
  expect_equal(sum(one$ind$ref_user_scope_walk), 1000)
  expect_equal(sum(one$ind$ref_in_scope), 1000)
})
