test_that("build_ui_return_payload exposes compact named sections", {
  payload <- build_ui_return_payload(
    ui_updates = list(example = 1),
    reference_summaries = list(example = 2)
  )

  expect_type(payload, "list")
  expect_true(all(c(
    "ui_updates",
    "reference_summaries",
    "counterfactual_summaries",
    "health_impacts",
    "state"
  ) %in% names(payload)))
})
