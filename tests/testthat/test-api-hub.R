test_that("Hub exposes reference UI updates and single-field accessors", {
  hub <- Hub$new(cfg = list(), appraisal_inputs = build_mock_appraisal_inputs(
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
    ),
    appraisal_inputs = build_mock_appraisal_inputs(overrides = list(
      geo_level = list(input_value = "lad"),
      geo_id = list(input_value = "E08000035"),
      appraisal_name = list(input_value = "Leeds test")
    ))
  )

  summary <- hub$get_appraisal_summary_values()

  expect_equal(hub$get_geo_name(), "Leeds")
  expect_equal(summary$geo_name, "Leeds")
  expect_equal(summary$appraisal_name, "Leeds test")
})

test_that("Hub clears cached reference UI values when lightweight inputs change", {
  hub <- Hub$new(cfg = list(), appraisal_inputs = build_mock_appraisal_inputs())
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
  hub <- Hub$new(cfg = list(), appraisal_inputs = build_mock_appraisal_inputs(
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
