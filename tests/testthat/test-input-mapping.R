test_that("receive_appraisal_inputs returns mapped request sections", {
  request <- receive_appraisal_inputs(
    list(
      res_aggregation = list(input_value = "total")
    )
  )

  expect_type(request, "list")
  expect_true(all(c(
    "appraisal_inputs_in",
    "reference_request",
    "counterfactual_request",
    "results_request"
  ) %in% names(request)))
})
