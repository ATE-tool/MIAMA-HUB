test_that("Hub initializes with cfg only and accepts profile state later", {
  hub <- Hub$new(cfg = list())

  expect_null(hub$appraisal_inputs)
  expect_null(hub$request)

  profile <- build_mock_appraisal_inputs()
  request <- hub$set_appraisal_inputs(profile)

  expect_false(is.null(request))
  expect_false(is.null(hub$get_profile()))
})

test_that("Hub exposes reference UI updates and single-field accessors", {
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(build_mock_appraisal_inputs(
    overrides = list(
      at_data_unit = list(input_value = "users"),
      modes = list(input_value = c("walking", "cycling"))
    )
  ))

  hub$reference_data <- list(
    ind = data.frame(
      census_id = 1:3,
      age1year = c(20, 30, 40),
      female = c(0, 1, 0),
      walktime_wkhr = c(1, 0, 2),
      cycletime_wkhr = c(0, 3, 0)
    )
  )

  ui_values <- hub$build_reference_ui_values()
  updates <- hub$get_reference_ui_updates()

  expect_equal(ui_values$ui_updates$pop_total_ref, 3)
  expect_equal(updates$pop_number_ref_walk, 2)
  expect_equal(hub$get_reference_ui_value("pop_number_ref_bike"), 1)
  expect_equal(hub$get_population_size(), 3)
  expect_equal(hub$get_appraisal_summary_values()$population_size, 3)
  expect_null(hub$get_reference_ui_value("missing_field"))
  expect_equal(hub$get_reference_ui_value("missing_field", default = 99), 99)
})

test_that("Hub exposes profile subsets for setup and counterfactual UI steps", {
  profile <- build_mock_appraisal_inputs(overrides = list(
    ui_version = list(input_value = "advanced", is_filled = TRUE),
    intervention_type = list(input_value = "infras", is_filled = TRUE),
    users_count_cf_walk = list(input_value = 10, is_filled = TRUE)
  ))
  hub <- Hub$new(cfg = list())

  setup <- hub$get_appraisal_setup_inputs(profile)
  counterfactual <- hub$get_counterfactual_profile_inputs(profile)

  expect_true(all(c("ui_version", "geo_level", "geo_id", "modes", "intervention_type") %in% names(setup)))
  expect_true("modes" %in% names(counterfactual))
  expect_true("users_count_cf_walk" %in% names(counterfactual))
  expect_false("res_outcomes" %in% names(counterfactual))
})

test_that("apply_reference_defaults_to_profile writes defaults without filling inputs", {
  profile <- list(
    pop_total_ref = list(is_filled = FALSE, input_value = NULL, description = "Population"),
    users_count_ref_walk = list(is_filled = FALSE, input_value = NULL, description = "Walk users"),
    users_count_cf_walk = list(is_filled = FALSE, input_value = NULL, description = "CF walk users")
  )

  out <- apply_reference_defaults_to_profile(
    profile,
    ui_updates = list(pop_total_ref = 10, users_count_ref_walk = 3, missing_field = 99)
  )
  report <- attr(out, "reference_defaults_report")

  expect_equal(out$pop_total_ref$default_value, 10)
  expect_equal(out$users_count_ref_walk$default_value, 3)
  expect_null(out$pop_total_ref$input_value)
  expect_false(out$pop_total_ref$is_filled)
  expect_equal(report$updated_fields, c("pop_total_ref", "users_count_ref_walk"))
  expect_equal(report$skipped_fields, "missing_field")
})

test_that("Hub builds a profile with reference defaults in one UI-facing call", {
  profile <- build_mock_appraisal_inputs(overrides = list(
    at_data_unit = list(input_value = "users", is_filled = TRUE),
    modes = list(input_value = "walking", is_filled = TRUE),
    pop_total_ref = list(is_filled = FALSE, input_value = NULL, description = "Population"),
    population_size = list(is_filled = FALSE, input_value = NULL, description = "Population size"),
    pop_number_ref_walk = list(is_filled = FALSE, input_value = NULL, description = "Walking users")
  ))
  hub <- Hub$new(cfg = list())
  hub$reference_sources <- list(source_report = list())
  hub$reference_data <- list(
    ind = data.frame(
      census_id = 1:3,
      age1year = c(20, 30, 40),
      female = c(0, 1, 0),
      walktime_wkhr = c(1, 0, 2)
    )
  )

  updated <- hub$build_reference_profile_defaults(profile)
  report <- attr(updated, "reference_defaults_report")

  expect_equal(updated$pop_total_ref$default_value, 3)
  expect_equal(updated$population_size$default_value, 3)
  expect_equal(updated$pop_number_ref_walk$default_value, 2)
  expect_null(updated$pop_total_ref$input_value)
  expect_false(updated$pop_total_ref$is_filled)
  expect_true("pop_total_ref" %in% report$updated_fields)
})

test_that("Hub exposes appraisal summary geo name from geo lookup", {
  skip_if_not_installed("arrow")

  tmp <- withr::local_tempdir()
  sp_dir <- file.path(tmp, "sp_attributes_parquet")
  arrow::write_dataset(
    data.frame(
      census_id = 1:2,
      region = c("North West", "North West"),
      lad25cd = c("E08000035", "E08000035"),
      lad25nm = c("Leeds", "Leeds"),
      stringsAsFactors = FALSE
    ),
    sp_dir,
    format = "parquet"
  )

  hub <- Hub$new(
    cfg = list(
      sources = list(sp_attributes = list(path = sp_dir, format = "parquet")),
      output = list(lookup = file.path(tmp, "lookup"))
    )
  )
  hub$set_appraisal_inputs(build_mock_appraisal_inputs(overrides = list(
    geo_level = list(input_value = "lad"),
    geo_id = list(input_value = "E08000035"),
    appraisal_name = list(input_value = "Leeds test")
  )))

  summary <- hub$get_appraisal_summary_values()

  expect_equal(hub$get_geo_name(), "Leeds")
  expect_equal(summary$geo_name, "Leeds")
  expect_equal(summary$appraisal_name, "Leeds test")
})

test_that("Hub clears cached reference UI values when lightweight inputs change", {
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(build_mock_appraisal_inputs())
  hub$reference_sources <- list(source_report = list())
  hub$reference_data_raw <- list(ind = data.frame(), trips = data.frame())
  hub$reference_data <- list(ind = data.frame(), trips = data.frame())
  hub$reference_ui_values <- list(ui_updates = list(pop_total_ref = 3))

  hub$update_inputs(list(
    modes = list(input_value = "walking")
  ))

  expect_null(hub$reference_ui_values)
  expect_false(is.null(hub$reference_sources))
  expect_false(is.null(hub$reference_data_raw))
  expect_false(is.null(hub$reference_data))
})

test_that("Hub builds counterfactual data from appraisal input values", {
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(build_mock_appraisal_inputs(
    overrides = list(
      at_data_unit = list(input_value = "users"),
      modes = list(input_value = "walking"),
      users_count_cf_walk = list(input_value = 2)
    )
  ))

  hub$reference_data <- list(
    ind = data.frame(
      census_id = 1:3,
      walktime_wkhr = c(1, 0, 0),
      cycletime_wkhr = c(0, 0, 0)
    )
  )

  counterfactual_data <- hub$build_counterfactual_data(seed = 1)

  expect_equal(sum(counterfactual_data$ind$walktime_wkhr > 0), 2)
  expect_equal(counterfactual_data$counterfactual_report$changes[[1]]$target, 2)
  expect_equal(hub$get_counterfactual_data(), counterfactual_data)
})

test_that("Hub builds results through high-level UI method when data are already available", {
  hub <- Hub$new(cfg = list())
  profile <- build_mock_appraisal_inputs(
    overrides = list(
      res_outcomes = list(input_value = "mortality", is_filled = TRUE),
      res_aggregation = list(input_value = "total", is_filled = TRUE)
    )
  )
  hub$reference_sources <- list(source_report = list())
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

  out <- hub$build_results(profile)

  expect_true(all(c("profile", "reference_data", "counterfactual_data", "results_data") %in% names(out)))
  expect_equal(out$results_data$results_table$outcome, "mortality")
  expect_equal(out$results_data$headline_metrics$premature_deaths_prevented, 1)
})
