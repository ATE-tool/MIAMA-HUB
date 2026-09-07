test_that("CF summary excludes source donors and respects overlapping mode scopes", {
  cf <- list(ind = data.frame(census_id = 1:4,
    cf_in_scope = c(TRUE, TRUE, TRUE, FALSE),
    cf_user_scope_walk = c(TRUE, TRUE, FALSE, TRUE),
    cf_user_scope_bike = c(TRUE, FALSE, FALSE, TRUE),
    cf_user_scope_ebike = c(FALSE, TRUE, FALSE, TRUE),
    cf_user_scope_pt = c(FALSE, FALSE, FALSE, TRUE)))
  values <- .appraisal_population_summary(cf)
  expect_equal(unname(unlist(values)), c(3, 2, 1, 1, 0))
  cf$ind$cf_in_scope[] <- FALSE
  expect_equal(unname(unlist(.appraisal_population_summary(cf))), rep(0, 5))
  expect_true(all(is.na(unlist(.appraisal_population_summary(NULL)))))
})

test_that("summary helper handles materialized scope flags without activity proxies", {
  cf <- list(ind = data.frame(census_id = 1:2,
    .miama_user_scope_walk = c(TRUE, FALSE),
    .miama_user_scope_bike = c(FALSE, FALSE),
    .miama_user_scope_ebike = c(TRUE, TRUE),
    .miama_user_scope_pt = c(FALSE, TRUE)))
  expect_equal(unname(unlist(.appraisal_population_summary(cf))), c(2, 1, 0, 2, 1))
})

test_that("Hub exposes CF counts in results options and completed profile defaults", {
  hub <- Hub$new(cfg = miama_default_config())
  fields <- names(.appraisal_population_summary(NULL))
  profile <- build_mock_appraisal_inputs()
  for (field in fields) profile[[field]] <- list(default_value = NA_real_,
    input_value = NULL, is_filled = FALSE)
  hub$set_appraisal_inputs(profile)
  normalized_profile <- hub$get_profile()
  expect_true(is.na(hub$get_results_options()$res_population_cf_total))
  ind <- data.frame(census_id = 1:3, age1year = 40, female = 0,
    cf_in_scope = c(TRUE, TRUE, FALSE),
    cf_user_scope_walk = c(TRUE, FALSE, TRUE),
    cf_user_scope_bike = FALSE, cf_user_scope_ebike = FALSE,
    cf_user_scope_pt = FALSE)
  hub$reference_data <- list(ind = ind)
  hub$counterfactual_data <- list(ind = ind, health_outcomes = data.frame(
    census_id = 1:2, cycle = 1, age1year = 40, female = 0, dead = .1, d_dead = -.01))
  options <- hub$get_results_options()
  expect_equal(options$res_population_cf_total, 2)
  expect_equal(options$res_population_cf_walk, 1)
  expect_equal(options$assessment_period_years, 40)
  results <- hub$build_results_data()
  expect_equal(results$appraisal_summary$res_population_cf_total, 2)
  expect_equal(hub$get_profile()$res_population_cf_total$default_value, 2)
  expect_false(hub$get_profile()$res_population_cf_total$is_filled)
  expect_equal(hub$get_profile()$geo_id, normalized_profile$geo_id)
})
