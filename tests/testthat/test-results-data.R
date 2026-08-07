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
  expect_true(nrow(out$plot_data$health_cube) > 0)
  expect_true(all(c("mode", "mode_label", "scenario", "proportion") %in%
                    names(out$plot_data$trip_mode_distribution)))
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
  results_data$plot_data$trip_mode_distribution <- data.frame(
    mode = rep(c("walking", "cycling"), each = 2),
    mode_label = rep(c("Walking", "Cycling"), each = 2),
    scenario = rep(c("Reference", "Counterfactual"), 2),
    trips = c(10, 12, 4, 6),
    proportion = c(10 / 14, 12 / 18, 4 / 14, 6 / 18)
  )

  overview <- results_plot_health_overview(results_data)
  expect_s3_class(overview, "ggplot")
  expect_equal(overview$labels$title, "Health impact by outcome")
  expect_equal(overview$labels$x, "Health outcome")
  expect_equal(overview$labels$y, "Reduction from reference (%)")
  expect_s3_class(results_plot_health_overview(results_data, impact_type = "cf_vs_ref"), "ggplot")
  gender_plot <- results_plot_health_impacts(results_data, group_by = "gender")
  expect_s3_class(gender_plot, "ggplot")
  expect_equal(gender_plot$labels$title, "Health impact by gender")
  expect_equal(gender_plot$labels$x, "Gender")
  timeline <- results_plot_health_timeline(results_data)
  expect_s3_class(timeline, "ggplot")
  expect_equal(timeline$labels$title, "Health impacts over time")
  expect_match(timeline$labels$x, "Model year")
  expect_s3_class(results_plot_health_timeline(results_data, impact_type = "cf_vs_ref"), "ggplot")
  mode_plot <- results_plot_trip_mode_distribution(results_data)
  expect_s3_class(mode_plot, "ggplot")
  expect_equal(mode_plot$labels$title, "Reference and counterfactual travel by mode")
  expect_equal(mode_plot$labels$x, "Travel mode")
  expect_equal(mode_plot$labels$y, "Share of weighted trips (%)")
})

test_that("results_filter_health_data supports interactive Tab 5 filters", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = c(1, 1, 2, 2),
      cycle = c(0L, 1L, 0L, 1L),
      age1year = c(30, 31, 60, 61),
      female = c(0, 0, 1, 1),
      dead = c(10, 11, 20, 21),
      d_dead = c(-1, -1, -2, -2),
      dead_cf = c(9, 10, 18, 19),
      diabetes = c(2, 2, 4, 4),
      d_diabetes = c(-0.1, -0.1, -0.2, -0.2),
      diabetes_cf = c(1.9, 1.9, 3.8, 3.8)
    )
  )
  results_data <- prepare_results_data(counterfactual_data)

  filtered <- results_filter_health_data(
    results_data,
    outcomes = "mortality",
    age_groups = "age_20_34",
    gender = "male",
    aggregation = "timeline",
    group_by = "gender"
  )

  expect_equal(unique(filtered$outcome), "mortality")
  expect_equal(unique(filtered$gender), "male")
  expect_equal(filtered$cycle, c(0L, 1L))
  expect_equal(filtered$prevented_value, c(1, 1))
})

test_that("trip plot data groups numeric NTS main modes for presentation", {
  trips <- data.frame(
    trip_mainmode = 1:13,
    weight_tripXhh = rep(1, 13)
  )
  out <- .results_trip_mode_distribution(
    reference_data = list(trips = trips),
    counterfactual_data = list(trips = trips)
  )

  expect_equal(sort(unique(out$mode)), sort(c("walking", "cycling", "driving", "pt", "other")))
  expect_equal(sum(out$proportion[out$scenario == "Reference"]), 1)
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
