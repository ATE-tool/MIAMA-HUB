test_that("prepare_results_data aggregates filtered health outcomes", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = c(1, 2),
      cycle = c(0L, 0L),
      age1year = c(30, 60),
      female = c(0, 1),
      dead = c(10, 20),
      d_dead = c(-1, -2),
      dead_cf = c(9, 18),
      diabetes = c(3, 4),
      d_diabetes = c(-0.5, -0.25),
      diabetes_cf = c(2.5, 3.75),
      stroke = c(2, 6),
      d_stroke = c(-0.1, -0.2),
      stroke_cf = c(1.9, 5.8)
    ),
    trips = data.frame(
      census_id = c(1, 2),
      trip_mainmode = c("Walk", "Car"),
      weight_tripXhh = c(1, 3)
    )
  )
  reference_data <- list(
    trips = data.frame(
      census_id = c(1, 2),
      trip_mainmode = c("Walk", "Car"),
      weight_tripXhh = c(1, 4)
    )
  )

  out <- prepare_results_data(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    results_request = list(
      res_outcomes = c("mortality", "diabetes"),
      res_age_groups = c("age_20_34", "age_50_64"),
      res_gender = c("male", "female"),
      res_modes_filter = c("walking", "cycling"),
      res_aggregation = "total",
      res_impact_type = "attributable"
    )
  )

  expect_equal(sort(out$results_table$outcome), c("diabetes", "mortality"))
  expect_equal(out$results_table$delta_value[out$results_table$outcome == "mortality"], -3)
  expect_equal(out$headline_metrics$premature_deaths_prevented, 3)
  expect_equal(out$headline_metrics$disease_cases_prevented, 0.75)
  expect_true(nrow(out$plot_data$trip_mode_distribution) > 0)
  expect_true("Mode-specific health impact attribution is not implemented yet; health results use `mode = all_modes`." %in% out$results_report$notes)
})

test_that("prepare_results_data supports timeline and population aggregation", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = c(1, 1, 2, 2),
      cycle = c(0L, 1L, 0L, 1L),
      age1year = c(30, 31, 60, 61),
      female = c(0, 0, 1, 1),
      dead = c(10, 11, 20, 21),
      d_dead = c(-1, -1.1, -2, -2.1),
      dead_cf = c(9, 9.9, 18, 18.9)
    )
  )

  out <- prepare_results_data(
    counterfactual_data = counterfactual_data,
    results_request = list(
      res_outcomes = "mortality",
      res_aggregation = "timeline",
      res_pop_aggregation = "gender"
    )
  )

  expect_true("cycle" %in% names(out$results_table))
  expect_true("gender" %in% names(out$results_table))
  expect_equal(nrow(out$results_table), 4)
})

test_that("result plotting functions return ggplot objects", {
  skip_if_not_installed("ggplot2")

  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = c(1, 1),
      cycle = c(0L, 1L),
      age1year = c(30, 31),
      female = c(0, 0),
      dead = c(10, 11),
      d_dead = c(-1, -1.1),
      dead_cf = c(9, 9.9)
    )
  )

  results_data <- prepare_results_data(counterfactual_data)

  expect_s3_class(results_plot_health_overview(results_data), "ggplot")
  expect_s3_class(results_plot_health_timeline(results_data), "ggplot")
  expect_s3_class(results_plot_trip_mode_distribution(results_data), "ggplot")
})

test_that("Hub builds results data from counterfactual health outcomes", {
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(build_mock_appraisal_inputs(
    overrides = list(
      res_outcomes = list(input_value = "mortality"),
      res_aggregation = list(input_value = "total")
    )
  ))

  hub$reference_data <- list(ind = data.frame(census_id = 1))
  hub$counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = 1,
      cycle = 0L,
      age1year = 30,
      female = 0,
      dead = 10,
      d_dead = -1,
      dead_cf = 9
    )
  )

  out <- hub$build_results_data()

  expect_equal(out$results_table$outcome, "mortality")
  expect_equal(hub$get_results_data(), out)
})
