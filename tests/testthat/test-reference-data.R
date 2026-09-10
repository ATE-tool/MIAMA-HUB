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

test_that("HM-to-synthpop join rejects cycle-expanded individual IDs", {
  reference_sources <- list(
    hm_outcomes = data.frame(
      census_id = c(1, 1),
      cycle = c(1, 2),
      mmets = c(10, 10)
    ),
    sp_attributes = data.frame(census_id = 1, nts_id = 101),
    sp_trips = data.frame(census_id = 1, nts_tripid = 1001)
  )

  expect_error(
    join_hm_and_synthpop(reference_sources),
    "must contain one row per `census_id`"
  )
})

test_that("HM-to-synthpop join does not repeat health outcomes on trip rows", {
  reference_sources <- list(
    hm_outcomes = data.frame(
      census_id = c(1, 2),
      mmets = c(10, 20),
      dead = c(0.1, 0.2)
    ),
    sp_attributes = data.frame(
      census_id = c(1, 2),
      nts_id = c(101, 102),
      age1year = c(30, 40)
    ),
    sp_trips = data.frame(
      census_id = c(1, 1),
      nts_id = c(101, 101),
      age1year = c(30, 30),
      nts_tripid = c(1001, 1002)
    )
  )

  joined <- join_hm_and_synthpop(reference_sources)

  expect_true(all(c("mmets", "dead") %in% names(joined$ind)))
  expect_false(any(c("mmets", "dead") %in% names(joined$trips)))
  expect_true(all(c("nts_id", "age1year", "nts_tripid") %in% names(joined$trips)))
  expect_equal(nrow(joined$trips), 3)
  expect_equal(sum(is.na(joined$trips$nts_tripid)), 1)
})

test_that("trip census-id parquet filter is skipped when geography pushdown is available", {
  matched_ids <- c(1, 2, 3)

  expect_null(.synthpop_trip_census_ids_filter(
    list(geo_level = "lad", geo_id = "E08000035"),
    matched_ids
  ))
  expect_null(.synthpop_trip_census_ids_filter(
    list(geo_level = "reg", geo_id = "Yorkshire and The Humber"),
    matched_ids
  ))
  expect_equal(.synthpop_trip_census_ids_filter(
    list(geo_level = "eng", geo_id = NULL),
    matched_ids
  ), matched_ids)
  expect_equal(.synthpop_trip_census_ids_filter(
    list(),
    matched_ids
  ), matched_ids)
})

test_that("extract_reference_ui_values derives Tab 2 trip reference fields", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      walktime_wkhr = c(1, 0),
      cycletime_wkhr = c(0, 2)
    ),
    trips = data.frame(
      census_id = c(1, 2, 2),
      nts_tripid = c(11, 21, 22),
      weight_tripXhh = c(1, 2, 1),
      trip_walkdist_km = c(1, 0, 0),
      trip_walktime_min = c(10, 0, 0),
      trip_cycledist_km = c(0, 5, 3),
      trip_cycletime_min = c(0, 20, 12)
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "trips",
      modes = c("walking", "cycling"),
      trips_timeframe_walk = "week",
      trips_timeframe_bike = "week",
      trips_denominator_walk = "total",
      trips_denominator_bike = "total"
    )
  )

  expect_equal(values$ui_updates$pop_total_ref_basic, 2)
  expect_equal(values$ui_updates$pop_total_ref_advanced, 2)
  expect_equal(values$ui_updates$population_size, 2)
  expect_equal(values$ui_updates$trips_count_ref_walk, 1)
  expect_equal(values$ui_updates$trips_count_ref_bike, 2)
})

test_that("extract_reference_ui_values scales Tab 2 trip counts by timeframe", {
  reference_data <- list(
    ind = data.frame(census_id = 1:2),
    trips = data.frame(
      census_id = c(1, 2, 2),
      nts_tripid = c(11, 21, 22),
      weight_tripXhh = c(1, 2, 1),
      trip_walkdist_km = c(1, 0, 0),
      trip_walktime_min = c(10, 0, 0),
      trip_cycledist_km = c(0, 5, 3),
      trip_cycletime_min = c(0, 20, 12)
    )
  )

  day_values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "trips",
      modes = c("walking", "cycling"),
      trips_timeframe_walk = "day",
      trips_timeframe_bike = "day"
    )
  )
  year_values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "trips",
      modes = c("walking", "cycling"),
      trips_timeframe_walk = "year",
      trips_timeframe_bike = "year"
    )
  )

  expect_equal(day_values$ui_updates$trips_count_ref_walk, 1 / 7)
  expect_equal(day_values$ui_updates$trips_count_ref_bike, 2 / 7)
  expect_equal(year_values$ui_updates$trips_count_ref_walk, 52.1775)
  expect_equal(year_values$ui_updates$trips_count_ref_bike, 2 * 52.1775)
})

test_that("extract_reference_ui_values derives summary geo_name where possible", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      lad25cd = c("E08000035", "E08000035"),
      lad25nm = c("Leeds", "Leeds")
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    reference_request = list(geo_level = "lad", geo_id = "E08000035"),
    appraisal_input_values = list(modes = "walking")
  )

  expect_equal(values$ui_updates$geo_name, "Leeds")
  expect_equal(values$ui_updates$population_size, values$ui_updates$pop_total_ref_basic)
  expect_equal(values$ui_updates$population_size, values$ui_updates$pop_total_ref_advanced)
})

test_that("extract_reference_ui_values supports individual-only user counts", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:3,
      walktime_wkhr = c(1, 0, 0.5),
      cycletime_wkhr = c(0, 2, 0)
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "users",
      modes = c("walking", "cycling", "ebiking")
    )
  )

  expect_equal(values$ui_updates$users_count_ref_walk, 2)
  expect_equal(values$ui_updates$users_count_ref_bike, 1)
  expect_equal(values$ui_updates$users_count_ref_ebike, 0)
  expect_false("users_count_ref_ebike" %in% values$extraction_report$skipped_fields)
})

test_that("extract_reference_ui_values derives mode-share reference fields", {
  reference_data <- list(
    ind = data.frame(census_id = 1:2),
    trips = data.frame(
      census_id = c(1, 1, 2),
      nts_tripid = c(11, 12, 21),
      weight_tripXhh = c(1, 1, 2),
      trip_distraw_km = c(2, 5, 6),
      trip_durationraw_min = c(20, 30, 40),
      trip_walkdist_km = c(2, 0, 0),
      trip_walktime_min = c(20, 0, 0),
      trip_cycledist_km = c(0, 5, 6),
      trip_cycletime_min = c(0, 30, 40)
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "mode_share",
      modes = c("walking", "cycling"),
      ui_mode_share_show_options = FALSE
    )
  )

  expect_equal(values$ui_updates$mode_share_total_trips, 3)
  expect_equal(values$ui_updates$mode_share_total_trips_basic, 3)
  expect_equal(values$ui_updates$mode_share_ref_walk, 100 / 3)
  expect_equal(values$ui_updates$mode_share_ref_bike, 200 / 3)
  expect_true(all(c("mode_share_ref_ebike", "mode_share_ref_pt") %in% names(values$ui_updates)))
  expect_equal(values$ui_updates$mode_share_ref_ebike, 0)
  expect_true(is.na(values$ui_updates$mode_share_ref_pt))
})

test_that("extract_reference_ui_values classifies numeric NTS main modes", {
  reference_data <- list(
    ind = data.frame(census_id = 1:13),
    trips = data.frame(
      census_id = 1:13,
      nts_tripid = 101:113,
      weight_tripXhh = rep(1, 13),
      trip_mainmode = 1:13,
      trip_distraw_km = rep(1, 13),
      trip_durationraw_min = rep(10, 13),
      trip_walkdist_km = c(1, rep(0, 12)),
      trip_walktime_min = c(10, rep(0, 12)),
      trip_cycledist_km = c(0, 1, rep(0, 11)),
      trip_cycletime_min = c(0, 10, rep(0, 11))
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(at_data_unit = "mode_share")
  )

  expect_equal(values$ui_updates$mode_share_ref_walk, 100 / 13)
  expect_equal(values$ui_updates$mode_share_ref_bike, 100 / 13)
  expect_equal(values$ui_updates$mode_share_ref_car, 500 / 13)
  expect_equal(values$ui_updates$mode_share_ref_pt, 600 / 13)
  expect_equal(
    sum(c(
      values$ui_updates$mode_share_ref_walk,
      values$ui_updates$mode_share_ref_bike,
      values$ui_updates$mode_share_ref_car,
      values$ui_updates$mode_share_ref_pt
    )),
    100
  )
})

test_that("extract_reference_ui_values derives Tab 3 population reference fields", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:4,
      age1year = c(20, 30, 40, 50),
      female = c(0, 1, 1, 0),
      walktime_wkhr = c(1, 0, 0, 2),
      cycletime_wkhr = c(0, 3, 0, 0)
    )
  )

  current_values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "users",
      modes = c("walking", "cycling"),
      pop_refine_choice = "pop_age_current"
    )
  )

  expect_equal(current_values$ui_updates$pop_total_ref_advanced, 4)
  expect_equal(current_values$ui_updates$pop_number_ref_walk_advanced, 2)
  expect_equal(current_values$ui_updates$pop_number_ref_bike_advanced, 1)
  expect_equal(current_values$ui_updates$pop_spread_age_mean_ref_walk, 39.5)
  expect_equal(current_values$ui_updates$pop_spread_sex_prop_ref_walk, 1)
  expect_equal(current_values$ui_updates$pop_spread_age_mean_ref_bike, 35)
  expect_equal(current_values$ui_updates$pop_spread_sex_prop_ref_bike, 0)

  new_values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "users",
      modes = c("walking", "cycling"),
      pop_refine_choice = "pop_age_new"
    )
  )

  expect_equal(new_values$ui_updates$pop_spread_age_mean_ref_walk, 39.5)
  expect_equal(new_values$ui_updates$pop_spread_sex_prop_ref_walk, 1)
})

test_that("Tab 3 spread defaults fall back when a mode has no valid adult category", {
  reference_data <- list(
    ind = data.frame(
      census_id = 1:2,
      age1year = c(16, 40),
      female = c(0, 1),
      walktime_wkhr = c(0, 0),
      cycletime_wkhr = c(1, 0)
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(modes = "cycling")
  )

  expect_equal(values$ui_updates$pop_spread_age_mean_ref_bike, 45)
  expect_equal(sum(values$ui_updates$pop_spread_bars_ref_bike$percent), 100)
  expect_true(any(grepl(
    "No usable mode-specific bike spread",
    values$extraction_report$notes
  )))
})

test_that("extract_reference_ui_values handles haven-labelled numeric columns", {
  skip_if_not_installed("haven")
  skip_if_not_installed("vctrs")

  reference_data <- list(
    ind = data.frame(
      census_id = 1:3
    ),
    trips = data.frame(
      census_id = c(1, 2, 3),
      nts_tripid = c(11, 21, 31),
      trip_purpose = c("Commuting", "Leisure", "Shopping")
    )
  )
  reference_data$ind$age1year <- haven::labelled(c(20, 30, 40), c(young = 20, mid = 30, old = 40))
  reference_data$ind$female <- vctrs::new_vctr(c(0, 1, 0), class = "haven_labelled", labels = c(male = 0, female = 1))
  reference_data$ind$walktime_wkhr <- haven::labelled(c(1, 0, 2), c(none = 0))
  reference_data$trips$weight_tripXhh <- haven::labelled(c(1, 2, 1), c(one = 1, two = 2))
  reference_data$trips$trip_walkdist_km <- haven::labelled(c(1, 0, 2), c(none = 0))
  reference_data$trips$trip_walktime_min <- haven::labelled(c(10, 0, 20), c(none = 0))
  reference_data$trips$trip_distraw_km <- haven::labelled(c(1, 5, 2), c(short = 1))
  reference_data$trips$trip_durationraw_min <- haven::labelled(c(10, 50, 20), c(short = 10))

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "trips",
      modes = "walking",
      trips_timeframe_walk = "week",
      trips_denominator_walk = "total",
      pop_refine_choice = "pop_age_current"
    )
  )

  expect_equal(values$ui_updates$pop_number_ref_walk_advanced, 2)
  expect_equal(values$ui_updates$trips_count_ref_walk, 2)
  expect_equal(values$ui_updates$pop_spread_age_mean_ref_walk, 34.5)
  expect_equal(values$ui_updates$pop_spread_sex_prop_ref_walk, 1)
  expect_equal(values$ui_updates$trips_spread_mean_ref_walk, 2.25)
})

test_that("spread categories respect configured interval boundaries", {
  cfg <- miama_default_config()

  expect_identical(
    .spread_cut(c(17, 18, 29, 30, 59, 60), cfg$spread$age$breaks, cfg$spread$age$right),
    c(NA_integer_, 1L, 1L, 2L, 4L, 5L)
  )
  expect_identical(
    .spread_cut(c(0, 0.1, 10, 25, 50, 51), cfg$spread$pa$breaks, cfg$spread$pa$right),
    c(1L, 2L, 2L, 3L, 4L, 5L)
  )
})

test_that("spread bars remain exact when CF sliders equal reference anchors", {
  ref_matrix <- matrix(
    c(20, 5, 10, 5, 10, 5, 5, 10, 10, 20),
    nrow = 5,
    dimnames = list(paste0("category_", 1:5), c("male", "female"))
  )
  ref_bars <- .spread_matrix_to_bars(
    ref_matrix,
    category_midpoints = c(20, 35, 45, 55, 70),
    topic = "pop",
    scenario = "ref"
  )
  ref_bars$reference_mean <- 42.3
  ref_bars$reference_prop <- 0.5

  cf_bars <- spread_bar_values_from_slider(
    ref_bars,
    cf_mean = 42.3,
    cf_prop = 0.5,
    topic = "pop"
  )

  expect_equal(cf_bars$percent, ref_bars$percent)
  expect_equal(cf_bars$category, ref_bars$category)
  expect_true(all(cf_bars$scenario == "cf"))
})

test_that("trip purpose categories use one utilitarian default rule", {
  purpose <- c("Commuting", "Leisure", NA, "")

  expect_identical(
    .utilitarian_trip_filter(purpose),
    c(TRUE, FALSE, TRUE, TRUE)
  )
  expect_identical(
    cf_trip_utilitarian(data.frame(trip_purpose = purpose), active = rep(TRUE, 4)),
    c(TRUE, FALSE, TRUE, TRUE)
  )
})

test_that("extract_reference_ui_values derives Tab 4 trip reference fields", {
  reference_data <- list(
    ind = data.frame(census_id = 1:2),
    trips = data.frame(
      census_id = c(1, 1, 2),
      nts_tripid = c(11, 12, 21),
      weight_tripXhh = c(1, 1, 2),
      trip_distraw_km = c(2, 5, 6),
      trip_durationraw_min = c(20, 30, 40),
      trip_mainmode = c("Walk", "Cycle", "Cycle"),
      trip_purpose = c("Commuting", "Leisure", "Shopping"),
      trip_walkdist_km = c(2, 0, 0),
      trip_walktime_min = c(20, 0, 0),
      trip_cycledist_km = c(0, 5, 6),
      trip_cycletime_min = c(0, 30, 40)
    )
  )

  values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "trips",
      modes = c("walking", "cycling")
    )
  )

  expect_equal(values$ui_updates$trips_number_total_ref, 3)
  expect_equal(values$ui_updates$trips_number_ref_walk, 1)
  expect_equal(values$ui_updates$trips_number_ref_bike, 2)
  expect_equal(values$ui_updates$trips_spread_mean_ref_walk, 3.5)
  expect_equal(values$ui_updates$trips_spread_util_prop_ref_walk, 1)
  # The spread slider mean is reconstructed from configured category midpoints,
  # not from the raw two-row arithmetic mean.
  expect_equal(values$ui_updates$trips_spread_mean_ref_bike, 7.5)
  expect_equal(values$ui_updates$trips_spread_util_prop_ref_bike, 1 / 2)
  expect_equal(values$ui_updates$assump_trip_source_shares_walk$bike$percent, 100)
  expect_equal(values$ui_updates$assump_trip_source_shares_bike$walk$percent, 100)

  diversion_values <- extract_reference_ui_values(
    reference_data,
    appraisal_input_values = list(
      at_data_unit = "trips",
      modes = "walking",
      trips_refine_method = "trip_diversion"
    )
  )
  expect_true(all(c("mode_share_ref_walk", "mode_share_ref_bike", "mode_share_ref_ebike", "mode_share_ref_pt") %in% names(diversion_values$ui_updates)))
})

test_that("unchanged spread sliders preserve reference joint bars", {
  ref_matrix <- matrix(
    c(5, 10, 15, 20, 0, 10, 5, 15, 10, 10),
    nrow = 5,
    ncol = 2,
    dimnames = list(paste0("category_", 1:5), c("male", "female"))
  )
  ref_bars <- .spread_matrix_to_bars(
    ref_matrix,
    category_midpoints = 1:5,
    topic = "pop",
    scenario = "ref"
  )

  cf_bars <- spread_bar_values_from_slider(ref_bars)

  expect_equal(cf_bars$percent, ref_bars$percent)
  expect_equal(cf_bars$proportion, ref_bars$proportion)
  expect_true(all(cf_bars$scenario == "cf"))
})
