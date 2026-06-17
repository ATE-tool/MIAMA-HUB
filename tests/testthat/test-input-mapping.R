test_that("receive_appraisal_inputs returns normalized, extracted, and mapped sections", {
  request <- receive_appraisal_inputs(
    list(
      geo_level = list(input_value = NULL, default_value = "lad"),
      geo_id = list(input_value = "E08000035"),
      res_aggregation = list(input_value = "total"),
      res_outcomes = list(input_value = c("mortality", "stroke"))
    )
  )

  expect_type(request, "list")
  expect_true(all(c(
    "appraisal_inputs_in",
    "appraisal_input_values",
    "reference_request",
    "counterfactual_request",
    "results_request"
  ) %in% names(request)))

  expect_equal(request$appraisal_input_values$geo_level, "lad")
  expect_equal(request$appraisal_input_values$geo_id, "E08000035")
  expect_equal(request$reference_request$geo_level, "lad")
  expect_equal(request$reference_request$geo_id, "E08000035")
  expect_equal(request$results_request$res_aggregation, "total")
  expect_equal(request$results_request$res_outcomes, c("mortality", "stroke"))
})

test_that("normalize_appraisal_inputs fills defaults for canonical UI fields", {
  normalized <- normalize_appraisal_inputs(list(
    geo_level = list(
      input_value = NULL,
      default_value = "lad",
      description = "Spatial resolution",
      is_filled = FALSE
    )
  ))

  expect_equal(normalized$geo_level$input_value, "lad")
  expect_equal(normalized$geo_level$input_source, "user")
})
