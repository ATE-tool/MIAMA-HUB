test_that("counterfactual payload defaults are empty but well formed", {
  payload <- build_ui_return_payload()

  expect_type(payload$counterfactual_summaries, "list")
  expect_s3_class(payload$health_impacts, "data.frame")
})
