test_that("health impacts defaults to an empty data frame", {
  payload <- build_ui_return_payload()

  expect_equal(nrow(payload$health_impacts), 0)
})
