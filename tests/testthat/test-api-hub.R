test_that("Hub initializes with cfg only and accepts profile state later", {
  hub <- Hub$new(cfg = list())

  expect_null(hub$appraisal_inputs)
  expect_null(hub$request)

  profile <- build_mock_appraisal_inputs()
  request <- hub$set_appraisal_inputs(profile)

  expect_false(is.null(request))
  expect_false(is.null(hub$get_profile()))
})

test_that("counterfactual changes retain reference defaults", {
  marker <- list(ui_updates = list(pop_total_ref_basic = 100))
  state <- list(
    reference_sources = list(source = TRUE),
    reference_data_raw = list(ind = data.frame(census_id = 1)),
    reference_data = list(ind = data.frame(census_id = 1)),
    reference_ui_values = marker,
    reference_default_data = list(ind = data.frame(census_id = 1)),
    reference_default_ui_values = marker,
    counterfactual_data = list(ind = data.frame(census_id = 1)),
    results_data = list(value = 1)
  )

  invalidation <- invalidate_hub_state(state, "trips_count_cf_bike")

  expect_false(invalidation$reference_reload)
  expect_false(invalidation$reference_defaults_refresh)
  expect_identical(invalidation$state$reference_default_ui_values, marker)
  expect_null(invalidation$state$counterfactual_data)
  expect_null(invalidation$state$results_data)
})

test_that("reference display changes recompute defaults without reloading rows", {
  state <- list(
    reference_sources = list(source = TRUE),
    reference_data_raw = list(ind = data.frame(census_id = 1)),
    reference_data = list(ind = data.frame(census_id = 1)),
    reference_ui_values = list(value = 1),
    reference_default_data = list(ind = data.frame(census_id = 1)),
    reference_default_ui_values = list(value = 1),
    counterfactual_data = list(value = 1),
    results_data = list(value = 1)
  )

  invalidation <- invalidate_hub_state(state, "trips_timeframe_bike")

  expect_false(invalidation$reference_reload)
  expect_true(invalidation$reference_defaults_refresh)
  expect_false(is.null(invalidation$state$reference_default_data))
  expect_null(invalidation$state$reference_default_ui_values)
})

test_that("Tab 3 changes retain staged Tab 2 snapshots", {
  staged_ref <- list(ind = data.frame(census_id = 1))
  staged_cf <- list(ind = data.frame(census_id = 1))
  state <- list(
    refinement_reference_data = staged_ref,
    refinement_counterfactual_data = staged_cf,
    refinement_report = list(stage = "tab2"),
    counterfactual_data = list(value = 1),
    results_data = list(value = 1)
  )

  tab3 <- invalidate_hub_state(state, "pop_total_cf_advanced")
  tab2 <- invalidate_hub_state(state, "mode_share_cf")

  expect_false(tab3$refinement_upstream_changed)
  expect_identical(tab3$state$refinement_reference_data, staged_ref)
  expect_identical(tab3$state$refinement_counterfactual_data, staged_cf)
  expect_null(tab3$state$counterfactual_data)
  expect_true(tab2$refinement_upstream_changed)
  expect_null(tab2$state$refinement_reference_data)
  expect_null(tab2$state$refinement_counterfactual_data)
})

test_that("final calculations retain accepted Tab 3 population contracts", {
  field <- function(value) {
    list(
      input_value = value,
      is_filled = TRUE,
      default_value = value,
      additional_data = list(default_value_backup = value)
    )
  }
  profile <- list(
    ui_version = field("advanced"),
    pop_total_ref_advanced = field(100),
    pop_total_cf_advanced = field(110),
    pop_number_ref_walk_advanced = field(40),
    pop_number_cf_walk_advanced = field(50),
    trips_number_total_ref = field(300),
    trips_number_total_cf = field(360),
    trips_number_ref_walk = field(120),
    trips_number_cf_walk = field(180),
    trips_count_ref_walk = field(90),
    trips_count_cf_walk = field(100)
  )
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(profile)
  hub$refinement_reference_data <- list(ind = data.frame(census_id = 1))

  values <- hub$.__enclos_env__$private$.counterfactual_input_values()

  expect_equal(values$pop_total_ref_advanced, 100)
  expect_equal(values$pop_total_cf_advanced, 110)
  expect_equal(values$pop_number_ref_walk_advanced, 40)
  expect_equal(values$pop_number_cf_walk_advanced, 50)
  expect_equal(values$trips_number_total_ref, 300)
  expect_equal(values$trips_number_total_cf, 360)
  expect_equal(values$trips_number_ref_walk, 120)
  expect_equal(values$trips_number_cf_walk, 180)
})

test_that("Hub exposes reference UI updates and single-field accessors", {
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(build_mock_appraisal_inputs(
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

  expect_equal(ui_values$ui_updates$pop_total_ref_basic, 3)
  expect_equal(ui_values$ui_updates$pop_total_ref_advanced, 3)
  expect_equal(updates$pop_number_ref_walk_basic, 2)
  expect_equal(updates$pop_number_ref_walk_advanced, 2)
  expect_equal(hub$get_reference_ui_value("pop_number_ref_bike_advanced"), 1)
  expect_equal(hub$get_population_size(), 3)
  expect_equal(hub$get_appraisal_summary_values()$population_size, 3)
  expect_null(hub$get_reference_ui_value("missing_field"))
  expect_equal(hub$get_reference_ui_value("missing_field", default = 99), 99)
})

test_that("Hub exposes profile subset for setup UI step", {
  profile <- build_mock_appraisal_inputs(overrides = list(
    ui_version = list(input_value = "advanced", is_filled = TRUE),
    intervention_type = list(input_value = "infras", is_filled = TRUE),
    users_count_cf_walk = list(input_value = 10, is_filled = TRUE)
  ))
  hub <- Hub$new(cfg = list())

  setup <- hub$get_appraisal_setup_inputs(profile)

  expect_true(all(c("ui_version", "geo_level", "geo_id", "modes", "intervention_type") %in% names(setup)))
  expect_false("users_count_cf_walk" %in% names(setup))
  expect_false("res_outcomes" %in% names(setup))
})

test_that("get_input_value treats unfilled list fields as missing even without input_value", {
  profile <- list(
    geo_level = list(is_filled = FALSE, description = "Spatial resolution")
  )

  expect_null(get_input_value(profile, "geo_level", default = NULL))
  expect_equal(get_input_value(profile, "geo_level", default = "missing"), "missing")
})

test_that("apply_reference_defaults_to_profile writes defaults without filling inputs", {
  profile <- list(
    pop_total_ref_basic = list(is_filled = FALSE, input_value = NULL, description = "Population"),
    users_count_ref_walk = list(is_filled = FALSE, input_value = NULL, description = "Walk users"),
    users_count_cf_walk = list(is_filled = FALSE, input_value = NULL, description = "CF walk users")
  )

  out <- apply_reference_defaults_to_profile(
    profile,
    ui_updates = list(pop_total_ref_basic = 10, users_count_ref_walk = 3, missing_field = 99)
  )
  report <- attr(out, "reference_defaults_report")

  expect_equal(out$pop_total_ref_basic$default_value, 10)
  expect_equal(out$users_count_ref_walk$default_value, 3)
  expect_equal(out$users_count_cf_walk$default_value, 3)
  expect_null(out$pop_total_ref_basic$input_value)
  expect_false(out$pop_total_ref_basic$is_filled)
  expect_equal(
    report$updated_fields,
    c("pop_total_ref_basic", "users_count_ref_walk", "users_count_cf_walk")
  )
  expect_equal(report$skipped_fields, "missing_field")
})

test_that("all canonical reference-counterfactual pairs start at no change", {
  profile <- list(
    users_count_ref_walk = list(is_filled = FALSE, input_value = NULL),
    users_count_cf_walk = list(is_filled = FALSE, input_value = NULL),
    trips_count_ref_bike = list(is_filled = FALSE, input_value = NULL),
    trips_count_cf_bike = list(is_filled = TRUE, input_value = 1500),
    dist_dur_amount_ref_walk = list(is_filled = FALSE, input_value = NULL),
    dist_dur_amount_cf_walk = list(is_filled = FALSE, input_value = NULL),
    trips_number_total_ref = list(is_filled = FALSE, input_value = NULL),
    trips_number_total_cf = list(is_filled = FALSE, input_value = NULL),
    mode_share_ref = list(is_filled = FALSE, input_value = NULL),
    mode_share_cf = list(is_filled = FALSE, input_value = NULL)
  )
  mode_share <- list(
    car = list(percent = 60),
    bike = list(percent = 5),
    walk = list(percent = 25),
    pt = list(percent = 10)
  )

  out <- apply_reference_defaults_to_profile(
    profile,
    ui_updates = list(
      users_count_ref_walk = 100,
      trips_count_ref_bike = 734,
      dist_dur_amount_ref_walk = 1200,
      trips_number_total_ref = 5000,
      mode_share_ref = mode_share
    )
  )
  report <- attr(out, "reference_defaults_report")

  expect_equal(out$users_count_cf_walk$default_value, 100)
  expect_equal(out$trips_count_cf_bike$default_value, 734)
  expect_equal(out$dist_dur_amount_cf_walk$default_value, 1200)
  expect_equal(out$trips_number_total_cf$default_value, 5000)
  expect_identical(out$mode_share_cf$default_value, mode_share)
  expect_equal(out$trips_count_cf_bike$input_value, 1500)
  expect_true(out$trips_count_cf_bike$is_filled)
  expect_setequal(
    report$mirrored_cf_fields,
    c(
      "users_count_cf_walk", "trips_count_cf_bike",
      "dist_dur_amount_cf_walk", "trips_number_total_cf", "mode_share_cf"
    )
  )
})

test_that("reference spread defaults initialise matching counterfactual sliders", {
  profile <- list(
    pop_spread_age_mean_ref_bike = list(is_filled = FALSE, input_value = NULL),
    pop_spread_age_mean_cf_bike = list(
      is_filled = TRUE,
      input_value = 42,
      default_value = NULL
    ),
    pop_spread_sex_prop_ref_bike = list(is_filled = FALSE, input_value = NULL),
    pop_spread_sex_prop_cf_bike = list(is_filled = FALSE, input_value = NULL),
    trips_spread_mean_ref_walk = list(is_filled = FALSE, input_value = NULL),
    trips_spread_mean_cf_walk = list(is_filled = FALSE, input_value = NULL),
    pop_spread_bars_ref_bike = list(is_filled = FALSE, input_value = NULL)
  )

  out <- apply_reference_defaults_to_profile(
    profile,
    ui_updates = list(
      pop_spread_age_mean_ref_bike = 36.5,
      pop_spread_sex_prop_ref_bike = 0.44,
      trips_spread_mean_ref_walk = 3.2,
      pop_spread_bars_ref_bike = data.frame(category = "18-29", value = 1)
    )
  )
  report <- attr(out, "reference_defaults_report")

  expect_equal(out$pop_spread_age_mean_cf_bike$default_value, 36.5)
  expect_equal(out$pop_spread_sex_prop_cf_bike$default_value, 0.44)
  expect_equal(out$trips_spread_mean_cf_walk$default_value, 3.2)
  expect_equal(out$pop_spread_age_mean_cf_bike$input_value, 42)
  expect_true(out$pop_spread_age_mean_cf_bike$is_filled)
  expect_false(out$pop_spread_sex_prop_cf_bike$is_filled)
  expect_equal(
    report$mirrored_cf_fields,
    c(
      "pop_spread_age_mean_cf_bike",
      "pop_spread_sex_prop_cf_bike",
      "trips_spread_mean_cf_walk"
    )
  )
  expect_equal(
    unname(report$mirrored_cf_sources),
    c(
      "pop_spread_age_mean_ref_bike",
      "pop_spread_sex_prop_ref_bike",
      "trips_spread_mean_ref_walk"
    )
  )
})

test_that("reference population defaults initialise matching counterfactual fields", {
  profile <- list(
    pop_total_ref_advanced = list(
      is_filled = FALSE, input_value = NULL,
      additional_data = list(default_value_backup = NULL)
    ),
    pop_total_cf_advanced = list(
      is_filled = FALSE, input_value = NULL,
      additional_data = list(default_value_backup = NULL)
    ),
    pop_number_ref_bike_advanced = list(
      is_filled = FALSE, input_value = NULL,
      additional_data = list(default_value_backup = NULL)
    ),
    pop_number_cf_bike_advanced = list(
      is_filled = TRUE,
      input_value = 120,
      default_value = NULL,
      additional_data = list(default_value_backup = NULL)
    ),
    pop_number_ref_walk_basic = list(is_filled = FALSE, input_value = NULL),
    pop_number_cf_walk_basic = list(is_filled = FALSE, input_value = NULL)
  )

  out <- apply_reference_defaults_to_profile(
    profile,
    ui_updates = list(
      pop_total_ref_advanced = 1000,
      pop_number_ref_bike_advanced = 100,
      pop_number_ref_walk_basic = 400
    )
  )
  report <- attr(out, "reference_defaults_report")

  expect_equal(out$pop_total_cf_advanced$default_value, 1000)
  expect_equal(out$pop_number_cf_bike_advanced$default_value, 100)
  expect_equal(out$pop_number_cf_walk_basic$default_value, 400)
  expect_true(out$pop_number_cf_bike_advanced$is_filled)
  expect_equal(out$pop_number_cf_bike_advanced$input_value, 120)
  expect_equal(out$pop_total_ref_advanced$additional_data$default_value_backup, 1000)
  expect_equal(out$pop_total_cf_advanced$additional_data$default_value_backup, 1000)
  expect_equal(out$pop_number_ref_bike_advanced$additional_data$default_value_backup, 100)
  expect_equal(out$pop_number_cf_bike_advanced$additional_data$default_value_backup, 100)
  expect_setequal(
    report$default_value_backup_fields,
    c(
      "pop_total_ref_advanced", "pop_total_cf_advanced",
      "pop_number_ref_bike_advanced", "pop_number_cf_bike_advanced"
    )
  )
  expect_setequal(
    report$mirrored_cf_fields,
    c(
      "pop_total_cf_advanced",
      "pop_number_cf_bike_advanced",
      "pop_number_cf_walk_basic"
    )
  )
})

test_that("category population defaults are written to additional data", {
  age_data <- list(
    pop_age_18_29 = list(
      pop_tot = 10L,
      pop_walk = 4L,
      pop_bike = 2L,
      pop_ebike = NA_integer_,
      pop_pt = 1L
    )
  )
  pa_data <- list(
    moderate = list(
      pop_tot = 8L,
      pop_walk = 3L,
      pop_bike = 1L,
      pop_ebike = NA_integer_,
      pop_pt = 1L
    )
  )
  profile <- list(
    pop_target_age_groups = list(
      default_value = "pop_age_18_29",
      additional_data = list(ref = list(), cf = list()),
      is_filled = FALSE,
      input_value = NULL
    ),
    pop_target_pa_groups = list(
      default_value = "moderate",
      additional_data = list(ref = list(), cf = list()),
      is_filled = FALSE,
      input_value = NULL
    )
  )

  out <- apply_reference_defaults_to_profile(
    profile,
    ui_updates = list(
      pop_target_age_groups = age_data,
      pop_target_pa_groups = pa_data
    )
  )

  expect_identical(out$pop_target_age_groups$additional_data$ref, age_data)
  expect_identical(out$pop_target_age_groups$additional_data$cf, age_data)
  expect_identical(out$pop_target_age_groups$default_value, "pop_age_18_29")
  expect_identical(out$pop_target_pa_groups$additional_data$ref, pa_data)
  expect_identical(out$pop_target_pa_groups$additional_data$cf, pa_data)
  expect_identical(out$pop_target_pa_groups$default_value, "moderate")
  expect_setequal(
    attr(out, "reference_defaults_report")$additional_data_fields,
    c("pop_target_age_groups", "pop_target_pa_groups")
  )
})

test_that("profile fields with additional_data receive derived metadata generically", {
  profile <- list(
    future_category_field = list(
      default_value = "category_a",
      additional_data = list(category_a = list(pop_tot = NA_integer_)),
      is_filled = FALSE,
      input_value = NULL
    )
  )
  derived <- list(category_a = list(pop_tot = 25L))

  out <- apply_reference_defaults_to_profile(
    profile,
    ui_updates = list(future_category_field = derived)
  )

  expect_identical(out$future_category_field$additional_data, derived)
  expect_identical(out$future_category_field$default_value, "category_a")
  expect_identical(
    attr(out, "reference_defaults_report")$additional_data_fields,
    "future_category_field"
  )
})

test_that("reference defaults include age and PA category population counts", {
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(build_mock_appraisal_inputs())
  hub$reference_default_data <- list(
    ind = data.frame(
      census_id = 1:4,
      age1year = c(20, 35, 45, 70),
      female = c(0, 1, 0, 1),
      walktime_wkhr = c(1, 0, 2, 0),
      cycletime_wkhr = c(0, 3, 0, 0),
      mmets = c(0, 5, 20, 60)
    )
  )

  updates <- hub$build_reference_default_ui_values()$ui_updates

  expect_equal(updates$pop_target_age_groups$pop_age_18_29$pop_tot, 1)
  expect_equal(updates$pop_target_age_groups$pop_age_40_49$pop_walk, 1)
  expect_equal(updates$pop_target_age_groups$pop_age_30_39$pop_bike, 1)
  expect_equal(updates$pop_target_age_groups$pop_age_18_29$pop_ebike, 0)
  expect_equal(updates$pop_target_pa_groups$sedentary$pop_tot, 1)
  expect_equal(updates$pop_target_pa_groups$very_high$pop_tot, 1)
})

test_that("apply_reference_defaults_to_profile writes all matching broad defaults", {
  profile <- list(
    ui_version = list(is_filled = TRUE, input_value = "basic"),
    at_data_unit = list(is_filled = TRUE, input_value = "users"),
    modes = list(is_filled = TRUE, input_value = "walk"),
    pop_total_ref_basic = list(is_filled = FALSE, input_value = NULL),
    users_count_ref_walk = list(is_filled = FALSE, input_value = NULL),
    users_count_ref_bike = list(is_filled = FALSE, input_value = NULL),
    trips_number_ref_walk = list(is_filled = FALSE, input_value = NULL),
    pop_number_ref_walk_advanced = list(is_filled = FALSE, input_value = NULL)
  )

  out <- apply_reference_defaults_to_profile(
    profile,
    ui_updates = list(
      pop_total_ref_basic = 10,
      users_count_ref_walk = 4,
      users_count_ref_bike = 5,
      trips_number_ref_walk = 6,
      pop_number_ref_walk_advanced = 7
    )
  )
  report <- attr(out, "reference_defaults_report")

  expect_equal(out$pop_total_ref_basic$default_value, 10)
  expect_equal(out$users_count_ref_walk$default_value, 4)
  expect_equal(out$users_count_ref_bike$default_value, 5)
  expect_equal(out$trips_number_ref_walk$default_value, 6)
  expect_equal(out$pop_number_ref_walk_advanced$default_value, 7)
  expect_equal(report$n_updated, 5)
  expect_equal(report$n_skipped, 0)
})

test_that("apply_reference_defaults_to_profile writes aggregate and per-mode mode-share defaults", {
  advanced_profile <- list(
    ui_version = list(is_filled = TRUE, input_value = "advanced"),
    modes = list(is_filled = TRUE, input_value = "walk"),
    trips_refine_method = list(is_filled = TRUE, input_value = "trip_diversion"),
    pop_number_ref_walk_advanced = list(is_filled = FALSE, input_value = NULL),
    pop_number_ref_bike_advanced = list(is_filled = FALSE, input_value = NULL),
    trips_number_ref_walk = list(is_filled = FALSE, input_value = NULL),
    trips_number_ref_bike = list(is_filled = FALSE, input_value = NULL),
    assump_trip_source_shares_walk = list(is_filled = FALSE, input_value = NULL),
    mode_share_ref = list(is_filled = FALSE, input_value = NULL),
    mode_share_ref_walk = list(is_filled = FALSE, input_value = NULL),
    mode_share_ref_bike = list(is_filled = FALSE, input_value = NULL),
    users_count_ref_walk = list(is_filled = FALSE, input_value = NULL)
  )

  advanced <- apply_reference_defaults_to_profile(
    advanced_profile,
    ui_updates = list(
      pop_number_ref_walk_advanced = 1,
      pop_number_ref_bike_advanced = 2,
      trips_number_ref_walk = 3,
      trips_number_ref_bike = 4,
      assump_trip_source_shares_walk = list(car = list(percent = 100)),
      mode_share_ref = list(
        car = list(percent = 87),
        bike = list(percent = 7),
        walk = list(percent = 6),
        pt = list(percent = 0)
      ),
      mode_share_ref_walk = 6,
      mode_share_ref_bike = 7,
      users_count_ref_walk = 8
    )
  )

  expect_equal(advanced$pop_number_ref_walk_advanced$default_value, 1)
  expect_equal(advanced$pop_number_ref_bike_advanced$default_value, 2)
  expect_equal(advanced$trips_number_ref_walk$default_value, 3)
  expect_equal(advanced$trips_number_ref_bike$default_value, 4)
  expect_equal(advanced$assump_trip_source_shares_walk$default_value$car$percent, 100)
  expect_equal(advanced$mode_share_ref$default_value$car$percent, 87)
  expect_equal(advanced$mode_share_ref_walk$default_value, 6)
  expect_equal(advanced$mode_share_ref_bike$default_value, 7)
  expect_equal(advanced$users_count_ref_walk$default_value, 8)
  expect_equal(attr(advanced, "reference_defaults_report")$n_skipped, 0)
})

test_that("Hub builds a profile with reference defaults in one UI-facing call", {
  profile <- build_mock_appraisal_inputs(overrides = list(
    ui_version = list(input_value = "basic", is_filled = TRUE),
    at_data_unit = list(input_value = "users", is_filled = TRUE),
    modes = list(input_value = "walking", is_filled = TRUE),
    pop_total_ref_basic = list(is_filled = FALSE, input_value = NULL, description = "Population"),
    pop_total_ref_advanced = list(is_filled = FALSE, input_value = NULL, description = "Population"),
    population_size = list(is_filled = FALSE, input_value = NULL, description = "Population size"),
    users_count_ref_walk = list(is_filled = FALSE, input_value = NULL, description = "Walking users"),
    pop_number_ref_walk_basic = list(is_filled = FALSE, input_value = NULL, description = "Basic walking users"),
    pop_number_ref_walk_advanced = list(is_filled = FALSE, input_value = NULL, description = "Advanced walking users")
  ))
  hub <- Hub$new(cfg = list())
  hub$reference_default_data <- list(
    ind = data.frame(
      census_id = 1:3,
      age1year = c(20, 30, 40),
      female = c(0, 1, 0),
      walktime_wkhr = c(1, 0, 2)
    )
  )

  updated <- hub$build_reference_profile_defaults(profile)
  report <- attr(updated, "reference_defaults_report")

  expect_equal(updated$pop_total_ref_basic$default_value, 3)
  expect_equal(updated$pop_total_ref_advanced$default_value, 3)
  expect_equal(updated$population_size$default_value, 3)
  expect_equal(updated$users_count_ref_walk$default_value, 2)
  expect_equal(updated$pop_number_ref_walk_basic$default_value, 2)
  expect_equal(updated$pop_number_ref_walk_advanced$default_value, 2)
  expect_null(updated$pop_total_ref_basic$input_value)
  expect_false(updated$pop_total_ref_basic$is_filled)
  expect_true(all(c("pop_total_ref_basic", "pop_total_ref_advanced") %in% report$updated_fields))
})

test_that("Hub reference loading fails fast when Tab 1 geography is not written to profile", {
  profile <- build_mock_appraisal_inputs()
  profile$geo_level$input_value <- NULL
  profile$geo_level$is_filled <- FALSE
  profile$geo_id$input_value <- NULL
  profile$geo_id$is_filled <- FALSE
  hub <- Hub$new(cfg = list())

  expect_error(
    hub$build_reference_profile_defaults(profile),
    "Reference geography is not set"
  )
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
    )
  )
  hub$set_appraisal_inputs(build_mock_appraisal_inputs(overrides = list(
    geo_level = list(input_value = "lad"),
    geo_id = list(input_value = "E08000035"),
    appraisal_name = list(input_value = "Leeds test")
  )))

  summary <- hub$get_appraisal_summary_values()

  expect_equal(hub$get_geo_name(), "Leeds")
  expect_equal(summary$geo_name, "Leeds")
  expect_equal(summary$appraisal_name, "Leeds test")
})

test_that("Hub clears cached reference UI values when lightweight inputs change", {
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(build_mock_appraisal_inputs())
  hub$reference_sources <- list(source_report = list())
  hub$reference_data_raw <- list(ind = data.frame(), trips = data.frame())
  hub$reference_data <- list(ind = data.frame(), trips = data.frame())
  hub$reference_ui_values <- list(ui_updates = list(pop_total_ref_basic = 3))

  hub$update_inputs(list(
    modes = list(input_value = "walking")
  ))

  expect_null(hub$reference_ui_values)
  expect_false(is.null(hub$reference_sources))
  expect_false(is.null(hub$reference_data_raw))
  expect_false(is.null(hub$reference_data))
})

test_that("Hub clears cached reference data when profile geography changes", {
  hub <- Hub$new(cfg = list())
  profile <- build_mock_appraisal_inputs()
  hub$set_appraisal_inputs(profile)
  hub$reference_sources <- list(source_report = list())
  hub$reference_data_raw <- list(ind = data.frame(), trips = data.frame())
  hub$reference_data <- list(ind = data.frame(), trips = data.frame())
  hub$reference_ui_values <- list(ui_updates = list(pop_total_ref_basic = 3))

  profile$geo_id$input_value <- "E09000001"
  hub$set_appraisal_inputs(profile)

  expect_null(hub$reference_sources)
  expect_null(hub$reference_data_raw)
  expect_null(hub$reference_data)
  expect_null(hub$reference_ui_values)
})

test_that("Hub keeps loaded reference data when profile change only affects display defaults", {
  hub <- Hub$new(cfg = list())
  profile <- build_mock_appraisal_inputs()
  hub$set_appraisal_inputs(profile)
  hub$reference_sources <- list(source_report = list())
  hub$reference_data_raw <- list(ind = data.frame(), trips = data.frame())
  hub$reference_data <- list(ind = data.frame(), trips = data.frame())
  hub$reference_ui_values <- list(ui_updates = list(pop_total_ref_basic = 3))

  profile$modes$input_value <- "walking"
  hub$set_appraisal_inputs(profile)

  expect_false(is.null(hub$reference_sources))
  expect_false(is.null(hub$reference_data_raw))
  expect_false(is.null(hub$reference_data))
  expect_null(hub$reference_ui_values)
})

test_that("Hub builds counterfactual data from appraisal input values", {
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(build_mock_appraisal_inputs(
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

test_that("Hub builds results through high-level UI method when data are already available", {
  hub <- Hub$new(cfg = list(population = list(person_weight = 1)))
  profile <- build_mock_appraisal_inputs(
    overrides = list(
      res_outcomes = list(input_value = "mortality", is_filled = TRUE),
      res_aggregation = list(input_value = "total", is_filled = TRUE)
    )
  )
  hub$reference_sources <- list(source_report = list())
  hub$reference_data <- list(ind = data.frame(census_id = 1))
  hub$counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = 1,
      cycle = 1L,
      age1year = 30,
      female = 0,
      dead = 10,
      d_dead = -1,
      dead_cf = 9
    )
  )

  out <- hub$build_results(profile)

  expect_true(all(c(
    "profile", "reference_data", "counterfactual_data", "health_impacts",
    "results_data", "highlights", "plot_data"
  ) %in% names(out)))
  expect_null(out$counterfactual_data$health_outcomes)
  expect_false(out$health_impacts$cycle_data_retained)
  expect_equal(out$health_impacts$n_cycle_rows, 1)
  expect_identical(out$plot_data, out$results_data$plot_data)
  expect_true(all(c(
    "health_cube", "mode_attribution", "trip_mode_distribution", "spreads"
  ) %in% names(out$plot_data)))
  expect_equal(out$results_data$results_table$outcome, "mortality")
  expect_equal(out$results_data$headline_metrics$premature_deaths_prevented, 1)
  expect_identical(out$highlights, hub$get_results_highlights())
  expect_equal(hub$get_results_highlights()$value[[1]], 1)
})

test_that("Hub reuses compacted results without rebuilding released cycle data", {
  hub <- Hub$new(cfg = list(population = list(person_weight = 1)))
  profile <- build_mock_appraisal_inputs(overrides = list(
    res_outcomes = list(input_value = "mortality", is_filled = TRUE),
    res_aggregation = list(input_value = "total", is_filled = TRUE)
  ))
  hub$reference_data <- list(ind = data.frame(census_id = 1))
  hub$counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = 1, cycle = 1L, age1year = 30, female = 0,
      dead = 10, d_dead = -1
    )
  )

  first <- hub$build_results(profile)
  second <- hub$build_results(profile)

  expect_null(second$counterfactual_data$health_outcomes)
  expect_identical(second$results_data, first$results_data)
  expect_identical(second$health_impacts, first$health_impacts)
})

test_that("Hub exposes lightweight assessment and option metadata", {
  hub <- Hub$new(cfg = miama_default_config())

  expect_equal(hub$get_assessment_period(), 40L)
  expect_true("age_groups" %in% hub$get_ui_options())
  expect_identical(
    hub$get_ui_options("age_groups")$value,
    hub$cfg$population_refinement$age$ids
  )
  expect_true("metric" %in% names(hub$get_results_options()))
})
