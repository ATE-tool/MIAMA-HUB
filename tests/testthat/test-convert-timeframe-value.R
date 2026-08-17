test_that("convert_timeframe_value converts trip values", {
  expect_equal(convert_timeframe_value("week", 70, "day", "trips"), 10)
  expect_equal(convert_timeframe_value("day", 10, "week", "trips"), 70)
  expect_equal(convert_timeframe_value("week", 2, "year", "trips"), 2 * 52.1775)
  expect_equal(convert_timeframe_value("year", 52.1775, "week", "trips"), 1)
  expect_equal(convert_timeframe_value("week", 12, "week", "trips"), 12)
})

test_that("convert_timeframe_value keeps user values unchanged", {
  expect_equal(convert_timeframe_value("day", 100, "year", "users"), 100)
  expect_equal(convert_timeframe_value("year", 100, "week", "users"), 100)
  expect_equal(convert_timeframe_value("week", 100, "day", "users"), 100)
})

test_that("convert_timeframe_value validates its public inputs", {
  expect_error(
    convert_timeframe_value("month", 10, "week"),
    "old_timeframe.*day, week, year"
  )
  expect_error(
    convert_timeframe_value("week", 10, "month"),
    "new_timeframe.*day, week, year"
  )
  expect_error(
    convert_timeframe_value("week", NA_real_, "year"),
    "old_value"
  )
  expect_error(
    convert_timeframe_value("week", 10, "year", "distance"),
    "one of.*trips.*users"
  )
})

test_that("Hub exposes the same stateless timeframe converter", {
  hub <- Hub$new(cfg = list())
  expect_equal(
    hub$convert_timeframe_value("week", 7, "day", "trips"),
    convert_timeframe_value("week", 7, "day", "trips")
  )
  expect_equal(hub$convert_timeframe_value("week", 7, "day", "users"), 7)
})
