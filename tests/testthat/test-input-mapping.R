test_that("receive_appraisal_inputs returns normalized, extracted, and mapped sections", {
  request <- receive_appraisal_inputs(
    list(
      geo_level = list(input_value = "lad", is_filled = TRUE),
      geo_id = list(input_value = "E08000035", is_filled = TRUE),
      res_aggregation = list(input_value = "total", is_filled = TRUE),
      res_outcomes = list(input_value = c("mortality", "stroke"), is_filled = TRUE)
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

test_that("normalize_appraisal_inputs preserves defaults without treating them as input values", {
  normalized <- normalize_appraisal_inputs(list(
    geo_level = list(
      input_value = NULL,
      default_value = "lad",
      description = "Spatial resolution",
      is_filled = FALSE
    )
  ))

  expect_null(normalized$geo_level$input_value)
  expect_equal(normalized$geo_level$default_value, "lad")
  expect_equal(normalized$geo_level$input_source, "user")

  request <- receive_appraisal_inputs(normalized)
  expect_null(request$appraisal_input_values$geo_level)
  expect_null(request$reference_request$geo_level)
})

test_that("normalize_active_modes accepts UI and HUB mode identifiers", {
  expect_equal(
    normalize_active_modes(c("walk", "bike", "ebike", "pt")),
    c("walking", "cycling", "ebiking", "pt")
  )
  expect_equal(
    normalize_active_modes(c("walking", "cycling", "cycling")),
    c("walking", "cycling")
  )
})
