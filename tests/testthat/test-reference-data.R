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

test_that("build_mock_appraisal_inputs returns canonical dev fields", {
  mock <- build_mock_appraisal_inputs()

  expect_true(all(c(
    "geo_level",
    "geo_id",
    "modes",
    "at_data_unit",
    "res_aggregation",
    "res_outcomes"
  ) %in% names(mock)))

  expect_equal(mock$geo_level$input_value, "lad")
  expect_equal(mock$res_aggregation$input_value, "total")
})

test_that("filter_reference_data filters by LAD code", {
  reference_data_raw <- list(
    ind = data.frame(
      census_id = 1:3,
      lad25cd = c("E08000035", "E08000035", "E09000001"),
      region = c("North West", "North West", "London")
    ),
    trips = data.frame(
      census_id = c(1, 1, 2, 3),
      lad25cd = c("E08000035", "E08000035", "E08000035", "E09000001"),
      region = c("North West", "North West", "North West", "London")
    )
  )

  filtered <- filter_reference_data(
    reference_data_raw,
    list(geo_level = "lad", geo_id = "E08000035")
  )

  expect_equal(nrow(filtered$ind), 2)
  expect_equal(nrow(filtered$trips), 3)
  expect_equal(filtered$filter_report$geo_level, "lad")
  expect_equal(filtered$filter_report$geo_id, "E08000035")
})

test_that("filter_reference_data leaves England-wide data unchanged", {
  reference_data_raw <- list(
    ind = data.frame(census_id = 1:2, lad25cd = c("A", "B")),
    trips = data.frame(census_id = c(1, 2, 2), lad25cd = c("A", "B", "B"))
  )

  filtered <- filter_reference_data(
    reference_data_raw,
    list(geo_level = "eng", geo_id = NULL)
  )

  expect_equal(nrow(filtered$ind), 2)
  expect_equal(nrow(filtered$trips), 3)
})
