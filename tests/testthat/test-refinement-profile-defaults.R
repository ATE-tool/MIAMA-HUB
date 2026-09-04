profile_field <- function(value = NULL, filled = FALSE, default = NULL, backup = FALSE) {
  field <- list(default_value = default, is_filled = filled, input_value = value)
  if (backup) field$additional_data <- list(default_value_backup = default)
  field
}

test_that("refinement defaults summarize staged Tab 2 REF and CF snapshots", {
  profile <- list(
    ui_version = profile_field("advanced", TRUE),
    geo_level = profile_field("lad", TRUE),
    geo_id = profile_field("E08000035", TRUE),
    modes = profile_field("walking", TRUE),
    at_data_unit = profile_field("users", TRUE),
    users_count_ref_walk = profile_field(1, TRUE),
    users_count_cf_walk = profile_field(2, TRUE),
    pop_total_ref_basic = profile_field(),
    pop_total_cf_basic = profile_field(),
    pop_number_ref_walk_basic = profile_field(),
    pop_number_cf_walk_basic = profile_field(),
    pop_total_ref_advanced = profile_field(6, TRUE, 6, TRUE),
    pop_total_cf_advanced = profile_field(6, TRUE, 6, TRUE),
    pop_number_ref_walk_advanced = profile_field(2, TRUE, 2, TRUE),
    pop_number_cf_walk_advanced = profile_field(2, TRUE, 2, TRUE),
    pop_spread_age_mean_ref_walk = profile_field(),
    pop_spread_age_mean_cf_walk = profile_field(),
    pop_spread_sex_prop_ref_walk = profile_field(),
    pop_spread_sex_prop_cf_walk = profile_field(),
    pop_spread_bars_ref_walk = profile_field(),
    pop_target_age_groups = profile_field(default = "pop_age_18_29"),
    pop_target_pa_groups = profile_field(default = "sedentary")
  )
  profile$pop_target_age_groups$additional_data <- list(ref = list(), cf = list())
  profile$pop_target_pa_groups$additional_data <- list(ref = list(), cf = list())
  reference_data <- list(
    ind = data.frame(
      census_id = 1:6,
      age1year = 20:25,
      female = c(0, 1, 0, 1, 0, 1),
      walktime_wkhr = c(1, 2, 0, 0, 0, 0),
      cycletime_wkhr = 0,
      sport_wkhr = 0,
      mmets = c(2.5, 5, 0, 0, 0, 0)
    )
  )
  hub <- Hub$new(cfg = miama_default_config())
  hub$reference_default_data <- reference_data

  updated <- hub$build_refinement_profile_defaults(profile, seed = 2)
  report <- attr(updated, "refinement_defaults_report")

  # One requested REF walker is half of the two source walkers, so HUB infers
  # an assessed population of half the six-person source population.
  expect_equal(updated$pop_total_ref_advanced$default_value, 3)
  expect_equal(updated$pop_total_cf_advanced$default_value, 3)
  expect_equal(updated$pop_total_ref_basic$default_value, 3)
  expect_equal(updated$pop_total_cf_basic$default_value, 3)
  expect_equal(updated$pop_number_ref_walk_advanced$default_value, 1)
  expect_equal(updated$pop_number_cf_walk_advanced$default_value, 2)
  expect_equal(updated$pop_number_ref_walk_basic$default_value, 1)
  expect_equal(updated$pop_number_cf_walk_basic$default_value, 2)
  expect_false(updated$pop_number_ref_walk_advanced$is_filled)
  expect_null(updated$pop_number_ref_walk_advanced$input_value)
  expect_true("input_value" %in% names(updated$pop_number_ref_walk_advanced))
  expect_true("input_value" %in% names(updated$pop_total_ref_advanced))
  expect_equal(updated$pop_number_ref_walk_advanced$additional_data$default_value_backup, 1)
  expect_equal(
    updated$pop_target_age_groups$additional_data$ref$pop_age_18_29$pop_walk,
    1
  )
  expect_equal(
    updated$pop_target_age_groups$additional_data$cf$pop_age_18_29$pop_walk,
    2
  )
  expect_equal(sum(hub$refinement_reference_data$ind$ref_user_scope_walk), 1)
  expect_equal(
    sum(hub$refinement_counterfactual_data$ind$cf_user_scope_walk &
          hub$refinement_counterfactual_data$ind$walktime_wkhr > 0),
    2
  )
  expect_true("pop_number_ref_walk_advanced" %in% report$updated_fields)
})

test_that("zero reference mode users retain usable Tab 3 spread defaults", {
  profile <- list(
    ui_version = profile_field("advanced", TRUE),
    geo_level = profile_field("lad", TRUE),
    geo_id = profile_field("E08000035", TRUE),
    modes = profile_field("walking", TRUE),
    at_data_unit = profile_field("users", TRUE),
    users_count_ref_walk = profile_field(0, TRUE),
    users_count_cf_walk = profile_field(1, TRUE),
    pop_total_ref_advanced = profile_field(default = 4, backup = TRUE),
    pop_total_cf_advanced = profile_field(default = 4, backup = TRUE),
    pop_number_ref_walk_advanced = profile_field(default = 0, backup = TRUE),
    pop_number_cf_walk_advanced = profile_field(default = 1, backup = TRUE),
    pop_spread_age_mean_ref_walk = profile_field(),
    pop_spread_age_mean_cf_walk = profile_field(),
    pop_spread_sex_prop_ref_walk = profile_field(),
    pop_spread_sex_prop_cf_walk = profile_field(),
    pop_spread_bars_ref_walk = profile_field(),
    pop_spread_pa_mean_ref_walk = profile_field(),
    pop_spread_pa_mean_cf_walk = profile_field(),
    pop_spread_pa_sex_prop_ref_walk = profile_field(),
    pop_spread_pa_sex_prop_cf_walk = profile_field(),
    pop_spread_pa_bars_ref_walk = profile_field(),
    pa_spread_bars_ref_walk = profile_field(),
    pop_target_age_groups = profile_field(default = "pop_age_18_29"),
    pop_target_pa_groups = profile_field(default = "sedentary")
  )
  profile$pop_target_age_groups$additional_data <- list(ref = list(), cf = list())
  profile$pop_target_pa_groups$additional_data <- list(ref = list(), cf = list())
  reference_data <- list(
    ind = data.frame(
      census_id = 1:4,
      age1year = c(20, 30, 40, 50),
      female = c(0, 1, 0, 1),
      walktime_wkhr = c(1, 0, 0, 0),
      cycletime_wkhr = 0,
      sport_wkhr = 0,
      mmets = c(5, 10, 20, 30)
    )
  )
  hub <- Hub$new(cfg = miama_default_config())
  hub$reference_default_data <- reference_data

  updated <- hub$build_refinement_profile_defaults(profile, seed = 2)

  expect_equal(updated$pop_number_ref_walk_advanced$default_value, 0)
  expect_true(is.finite(updated$pop_spread_age_mean_ref_walk$default_value))
  expect_true(is.finite(updated$pop_spread_sex_prop_ref_walk$default_value))
  expect_true(is.finite(updated$pop_spread_pa_mean_ref_walk$default_value))
  expect_true(is.finite(updated$pop_spread_pa_sex_prop_ref_walk$default_value))
  expect_true(.spread_bars_have_data(updated$pop_spread_bars_ref_walk$default_value))
  expect_true(.spread_bars_have_data(updated$pop_spread_pa_bars_ref_walk$default_value))
})

test_that("Tab 3 age and PA categories exhaust each staged population", {
  ind <- data.frame(
    census_id = 1:8,
    age1year = c(NA, 10, 18, 29, 30, 59, 60, 95),
    female = 0,
    walktime_wkhr = c(0, 1, 0, 1, 0, 1, 0, 1),
    cycletime_wkhr = 0,
    sport_wkhr = 0,
    mmets = c(NA, 0, 5, 10, 25, 50, 75, 100)
  )

  values <- .reference_tab3_category_values(ind, trips = NULL)

  expect_equal(sum(vapply(values$age, `[[`, integer(1), "pop_tot")), nrow(ind))
  expect_equal(sum(vapply(values$pa, `[[`, integer(1), "pop_tot")), nrow(ind))
  expect_equal(values$age$pop_age_other$pop_tot, 1)
  expect_equal(values$age$pop_age_under_18$pop_tot, 1)
  expect_equal(values$pa$unknown$pop_tot, 1)
})

test_that("unchanged rendered advanced defaults defer to filled Tab 2 values", {
  values <- list(
    ui_version = "advanced",
    users_count_ref_walk = 1,
    pop_number_ref_walk_advanced = 2
  )
  profile <- list(
    pop_number_ref_walk_advanced = profile_field(2, TRUE, 2)
  )

  effective <- .drop_unmodified_advanced_population_values(values, profile)
  target <- .reference_user_scope_target(effective, "walk")

  expect_null(effective$pop_number_ref_walk_advanced)
  expect_equal(target$field, "users_count_ref_walk")
  expect_equal(target$value, 1)
})

test_that("Tab 3 staging reconstructs category-refined table values in HUB", {
  profile <- list(
    modes = profile_field("walking", TRUE),
    pop_refine_method = profile_field("pop_age", TRUE),
    pop_target_age_groups = profile_field(c("pop_age_18_29", "pop_age_30_39"), TRUE),
    pop_total_ref_advanced = profile_field(3475, TRUE),
    pop_total_cf_advanced = profile_field(3475, TRUE),
    pop_number_ref_walk_advanced = profile_field(1200, TRUE),
    pop_number_cf_walk_advanced = profile_field(1300, TRUE)
  )
  profile$pop_target_age_groups$additional_data <- list(
    ref = list(
      pop_age_18_29 = list(pop_tot = 1000, pop_walk = 300),
      pop_age_30_39 = list(pop_tot = 900, pop_walk = 250)
    ),
    cf = list(
      pop_age_18_29 = list(pop_tot = 1000, pop_walk = 350),
      pop_age_30_39 = list(pop_tot = 900, pop_walk = 300)
    )
  )

  values <- .tab3_stage_input_values(profile)

  expect_equal(values$pop_total_ref_advanced, 1900)
  expect_equal(values$pop_total_cf_advanced, 1900)
  expect_equal(values$pop_number_ref_walk_advanced, 550)
  expect_equal(values$pop_number_cf_walk_advanced, 650)
})

test_that("advanced slider values become counterfactual sampling targets", {
  ref_matrix <- matrix(
    c(20, 10, 15, 10, 5, 5, 10, 5, 10, 10),
    nrow = 5,
    dimnames = list(paste0("age_", 1:5), c("male", "female"))
  )
  ref_bars <- .spread_matrix_to_bars(
    ref_matrix,
    category_midpoints = c(23.5, 34.5, 44.5, 54.5, 70),
    topic = "pop",
    scenario = "ref"
  )
  ref_bars$reference_mean <- spread_mean_from_bars(ref_bars)
  ref_bars$reference_prop <- spread_first_variable_prop_from_bars(ref_bars)

  values <- derive_counterfactual_spread_values(
    appraisal_input_values = list(
      pop_spread_age_mean_cf_walk = 55,
      pop_spread_sex_prop_cf_walk = 0.7
    ),
    reference_ui_values = list(
      pop_spread_bars_ref_walk = ref_bars,
      pop_spread_age_mean_ref_walk = ref_bars$reference_mean[[1]],
      pop_spread_sex_prop_ref_walk = ref_bars$reference_prop[[1]]
    )
  )
  target <- cf_population_sampling_target(
    values,
    suffix = "walk",
    spread = miama_default_config()$spread
  )

  expect_equal(target$male_prop, 0.7, tolerance = 1e-8)
  expect_equal(sum(target$age_category_props), 1, tolerance = 1e-8)
  expect_gt(
    sum(target$age_category_props[4:5]),
    sum(spread_category_props_from_bars(ref_bars)[4:5])
  )
  expect_true(all(c("sex", "age") %in% target$constraints))
})

test_that("Tab 3 handoff stages row-count trip defaults for Tab 4", {
  profile <- list(
    ui_version = profile_field("advanced", TRUE),
    geo_level = profile_field("lad", TRUE),
    geo_id = profile_field("E08000035", TRUE),
    modes = profile_field("walking", TRUE),
    at_data_unit = profile_field("users", TRUE),
    users_count_ref_walk = profile_field(2, TRUE),
    users_count_cf_walk = profile_field(2, TRUE),
    pop_total_ref_advanced = profile_field(default = 3, backup = TRUE),
    pop_total_cf_advanced = profile_field(default = 3, backup = TRUE),
    pop_number_ref_walk_advanced = profile_field(default = 2, backup = TRUE),
    pop_number_cf_walk_advanced = profile_field(default = 2, backup = TRUE),
    trips_number_total_ref = profile_field(),
    trips_number_total_cf = profile_field(),
    trips_number_ref_walk = profile_field(),
    trips_number_cf_walk = profile_field(),
    trips_spread_mean_ref_walk = profile_field(),
    trips_spread_mean_cf_walk = profile_field(),
    trips_spread_util_prop_ref_walk = profile_field(),
    trips_spread_util_prop_cf_walk = profile_field(),
    trips_spread_bars_ref_walk = profile_field(),
    trips_diversion_sources_walk = profile_field()
  )
  reference_data <- list(
    ind = data.frame(
      census_id = 1:3,
      age1year = c(20, 30, 40),
      female = c(0, 1, 0),
      walktime_wkhr = c(1, 1, 0),
      cycletime_wkhr = 0,
      sport_wkhr = 0,
      mmets = c(5, 10, 0)
    ),
    trips = data.frame(
      census_id = 1:3,
      nts_tripid = 11:13,
      trip_mainmode = c("Walk", "Walk", "Car"),
      trip_distraw_km = c(1, 2, 3),
      trip_durationraw_min = c(10, 20, 15),
      trip_walkdist_km = c(1, 2, 0),
      trip_walktime_min = c(10, 20, 0),
      trip_purpose = c("Commuting", "Leisure", "Shopping"),
      weight_tripXhh = c(10, 20, 30)
    )
  )
  hub <- Hub$new(cfg = miama_default_config())
  hub$reference_default_data <- reference_data

  updated <- hub$build_trip_refinement_profile_defaults(profile, seed = 3)
  report <- attr(updated, "trip_refinement_defaults_report")

  expect_equal(updated$trips_number_total_ref$default_value, 3)
  expect_equal(updated$trips_number_total_cf$default_value, 3)
  expect_equal(updated$trips_number_ref_walk$default_value, 2)
  expect_equal(updated$trips_number_cf_walk$default_value, 2)
  expect_equal(updated$trips_diversion_sources_walk$default_value$car$percent, 100)
  expect_false(updated$trips_number_ref_walk$is_filled)
  expect_true("trips_number_ref_walk" %in% report$updated_fields)
})

test_that("Tab 4 defaults preserve staged Tab 2 REF and CF trip snapshots", {
  profile <- list(
    ui_version = profile_field("advanced", TRUE),
    modes = profile_field("walking", TRUE),
    at_data_unit = profile_field("trips", TRUE),
    trips_count_ref_walk = profile_field(1, TRUE),
    trips_count_cf_walk = profile_field(2, TRUE),
    pop_total_ref_advanced = profile_field(default = 3, backup = TRUE),
    pop_total_cf_advanced = profile_field(default = 3, backup = TRUE),
    pop_number_ref_walk_advanced = profile_field(default = 1, backup = TRUE),
    pop_number_cf_walk_advanced = profile_field(default = 2, backup = TRUE),
    trips_number_total_ref = profile_field(),
    trips_number_total_cf = profile_field(),
    trips_number_ref_walk = profile_field(),
    trips_number_cf_walk = profile_field(),
    trips_spread_mean_ref_walk = profile_field(),
    trips_spread_mean_cf_walk = profile_field(),
    trips_spread_util_prop_ref_walk = profile_field(),
    trips_spread_util_prop_cf_walk = profile_field(),
    trips_spread_bars_ref_walk = profile_field(),
    trips_diversion_sources_walk = profile_field()
  )
  source <- list(
    ind = data.frame(
      census_id = 1:3, age1year = 20:22, female = c(0, 1, 0),
      walktime_wkhr = c(1, 0, 0), cycletime_wkhr = 0,
      sport_wkhr = 0, mmets = c(5, 0, 0)
    ),
    trips = data.frame(
      census_id = 1:3, nts_tripid = 11:13,
      trip_mainmode = c("Walk", "Car", "Car"),
      trip_distraw_km = c(1, 2, 3),
      trip_durationraw_min = c(10, 15, 20),
      trip_walkdist_km = c(1, 0, 0),
      trip_walktime_min = c(10, 0, 0),
      trip_purpose = c("Commuting", "Shopping", "Shopping")
    )
  )
  values <- extract_input_values(profile)
  staged_ref <- apply_reference_appraisal_scope(source, values, seed = 2)
  staged_cf <- apply_counterfactual_ui_values(
    init_counterfactual_data(staged_ref), values,
    reference_data = staged_ref, seed = 2
  )

  staged <- prepare_trip_refinement_profile_defaults(
    reference_data = source,
    staged_reference_data = staged_ref,
    staged_counterfactual_data = staged_cf,
    profile = profile,
    seed = 2
  )

  expect_equal(staged$profile$trips_number_ref_walk$default_value, 1)
  expect_equal(staged$profile$trips_number_cf_walk$default_value, 2)
  expect_true(staged$report$used_staged_tab2_snapshots)
  expect_false(staged$report$tab3_population_rescoped)
})

test_that("new-user allocation does not discard staged Tab 2 trip changes", {
  profile <- list(
    ui_version = profile_field("advanced", TRUE),
    modes = profile_field("walking", TRUE),
    at_data_unit = profile_field("trips", TRUE),
    trips_count_ref_walk = profile_field(1, TRUE),
    trips_count_cf_walk = profile_field(2, TRUE),
    pop_new_current_perc = profile_field(100, TRUE, 10, TRUE),
    pop_total_ref_advanced = profile_field(default = 3, backup = TRUE),
    pop_total_cf_advanced = profile_field(default = 3, backup = TRUE),
    pop_number_ref_walk_advanced = profile_field(default = 1, backup = TRUE),
    pop_number_cf_walk_advanced = profile_field(default = 2, backup = TRUE),
    trips_number_total_ref = profile_field(),
    trips_number_total_cf = profile_field(),
    trips_number_ref_walk = profile_field(),
    trips_number_cf_walk = profile_field(),
    trips_spread_mean_ref_walk = profile_field(),
    trips_spread_mean_cf_walk = profile_field(),
    trips_spread_util_prop_ref_walk = profile_field(),
    trips_spread_util_prop_cf_walk = profile_field(),
    trips_spread_bars_ref_walk = profile_field(),
    trips_diversion_sources_walk = profile_field(),
    induced_trips_percent = profile_field(default = 10)
  )
  source <- list(
    ind = data.frame(
      census_id = 1:3, age1year = 20:22, female = c(0, 1, 0),
      walktime_wkhr = c(1, 0, 0), cycletime_wkhr = 0,
      sport_wkhr = 0, mmets = c(5, 0, 0)
    ),
    trips = data.frame(
      census_id = 1:3, nts_tripid = 11:13,
      trip_mainmode = c("Walk", "Car", "Car"),
      trip_distraw_km = c(1, 2, 3),
      trip_durationraw_min = c(10, 15, 20),
      trip_walkdist_km = c(1, 0, 0),
      trip_walktime_min = c(10, 0, 0),
      trip_purpose = c("Commuting", "Shopping", "Shopping")
    )
  )
  values <- extract_input_values(profile)
  staged_ref <- apply_reference_appraisal_scope(source, values, seed = 2)
  staged_cf <- apply_counterfactual_ui_values(
    init_counterfactual_data(staged_ref), values,
    reference_data = staged_ref, seed = 2
  )

  staged <- prepare_trip_refinement_profile_defaults(
    reference_data = source,
    staged_reference_data = staged_ref,
    staged_counterfactual_data = staged_cf,
    profile = profile,
    seed = 2
  )

  expect_false(staged$report$tab3_population_rescoped)
  expect_equal(staged$profile$trips_number_ref_walk$default_value, 1)
  expect_equal(staged$profile$trips_number_cf_walk$default_value, 2)
  expect_equal(staged$profile$induced_trips_percent$default_value, 100)
  expect_equal(staged$report$realized_induced_trips_percent, 100)
  expect_equal(staged$report$induced_trips_percent_default_source, "realized_trip_changes")
  expect_equal(sum(staged$counterfactual_data$ind$cf_user_scope_walk), 2)
})

test_that("realized current/new user shares are aggregated for Tab 3 defaults", {
  report <- list(changes = list(
    list(
      delta = 3,
      current_new_user_split = list(
        retained_current_users = 1,
        recruited_new_users = 3
      )
    ),
    list(
      delta = 10,
      user_allocation = list(
        method = "trips_per_user",
        equivalent_changed_users = 10,
        added_new_at_users = 2
      )
    )
  ))

  expect_equal(.counterfactual_realized_new_user_percent(report), 35.7)
  expect_null(.counterfactual_realized_new_user_percent(list(changes = list(
    list(delta = 0)
  ))))
})

test_that("realized induced trip shares are aggregated for Tab 4 defaults", {
  report <- list(changes = list(
    list(delta = 10, mode_shift_n = 8, induced_n = 2),
    list(delta = 5, mode_shift_n = 3, induced_n = 2),
    list(delta = -2, mode_shift_n = 0, induced_n = 0)
  ))

  expect_equal(.counterfactual_realized_induced_trip_percent(report), 26.7)
  expect_null(.counterfactual_realized_induced_trip_percent(list(changes = list())))
})

test_that("CF re-scope recognizes trip-derived users without changing activity", {
  staged_cf <- list(
    ind = data.frame(
      census_id = 1:3,
      walktime_wkhr = c(1, 0, 0),
      ref_in_scope = TRUE,
      cf_in_scope = TRUE,
      ref_user_scope_walk = c(TRUE, FALSE, FALSE),
      cf_user_scope_walk = c(TRUE, TRUE, FALSE)
    )
  )
  values <- list(
    modes = "walking",
    pop_total_cf_advanced = 3,
    pop_number_cf_walk_advanced = 2
  )

  rescoped <- .rescope_staged_snapshot(
    staged_cf,
    values,
    scenario = "cf",
    seed = 3,
    cfg = miama_default_config()
  )

  expect_equal(sum(rescoped$ind$cf_user_scope_walk), 2)
  expect_equal(rescoped$ind$walktime_wkhr, c(1, 0, 0))
})

test_that("zero reference trips retain usable Tab 4 spread defaults", {
  empty_trips <- data.frame(
    census_id = integer(),
    nts_tripid = integer(),
    trip_mainmode = character(),
    trip_distraw_km = numeric(),
    trip_durationraw_min = numeric(),
    trip_walkdist_km = numeric(),
    trip_walktime_min = numeric(),
    trip_purpose = character()
  )
  source_trips <- data.frame(
    census_id = 1:3,
    nts_tripid = 11:13,
    trip_mainmode = c("Walk", "Car", "Bus"),
    trip_distraw_km = c(1, 5, 3),
    trip_durationraw_min = c(10, 20, 15),
    trip_walkdist_km = c(1, 0, 0.5),
    trip_walktime_min = c(10, 0, 5),
    trip_purpose = c("Commuting", "Shopping", "Leisure")
  )
  values <- extract_reference_ui_values(
    reference_data = list(ind = NULL, trips = empty_trips),
    appraisal_input_values = list(modes = "walking"),
    spread_fallback_data = list(ind = NULL, trips = source_trips)
  )$ui_updates

  expect_equal(values$trips_number_total_ref, 0)
  expect_equal(values$trips_number_ref_walk, 0)
  expect_true(is.finite(values$trips_spread_mean_ref_walk))
  expect_true(is.finite(values$trips_spread_util_prop_ref_walk))
  expect_true(.spread_bars_have_data(values$trips_spread_bars_ref_walk))
})

test_that("Tab 3 population refinement replaces an infeasible upstream trip quota", {
  profile <- list(
    ui_version = profile_field("advanced", TRUE),
    geo_level = profile_field("lad", TRUE),
    geo_id = profile_field("E08000035", TRUE),
    modes = profile_field("walking", TRUE),
    at_data_unit = profile_field("trips", TRUE),
    trips_count_ref_walk = profile_field(3, TRUE),
    trips_count_cf_walk = profile_field(3, TRUE),
    pop_total_ref_advanced = profile_field(1, TRUE, 1, TRUE),
    pop_total_cf_advanced = profile_field(1, TRUE, 1, TRUE),
    pop_number_ref_walk_advanced = profile_field(1, TRUE, 1, TRUE),
    pop_number_cf_walk_advanced = profile_field(1, TRUE, 1, TRUE),
    trips_number_total_ref = profile_field(),
    trips_number_total_cf = profile_field(),
    trips_number_ref_walk = profile_field(),
    trips_number_cf_walk = profile_field(),
    trips_spread_mean_ref_walk = profile_field(),
    trips_spread_mean_cf_walk = profile_field(),
    trips_spread_util_prop_ref_walk = profile_field(),
    trips_spread_util_prop_cf_walk = profile_field(),
    trips_spread_bars_ref_walk = profile_field(),
    trips_diversion_sources_walk = profile_field()
  )
  reference_data <- list(
    ind = data.frame(
      census_id = 1:3,
      age1year = c(20, 30, 40),
      female = c(0, 1, 0),
      walktime_wkhr = 1,
      cycletime_wkhr = 0,
      sport_wkhr = 0,
      mmets = 2.5
    ),
    trips = data.frame(
      census_id = 1:3,
      nts_tripid = 11:13,
      trip_mainmode = "Walk",
      trip_distraw_km = 1,
      trip_durationraw_min = 10,
      trip_walkdist_km = 1,
      trip_walktime_min = 10,
      trip_purpose = "Commuting"
    )
  )
  hub <- Hub$new(cfg = miama_default_config())
  hub$reference_default_data <- reference_data

  updated <- hub$build_trip_refinement_profile_defaults(profile, seed = 3)

  # The final one-person Tab 3 scope owns one observed trip. The original
  # three-trip Tab 2 target must not be forced back into that reduced scope.
  expect_equal(updated$trips_number_total_ref$default_value, 1)
  expect_equal(updated$trips_number_total_cf$default_value, 1)
  expect_equal(updated$trips_number_ref_walk$default_value, 1)
  expect_equal(updated$trips_number_cf_walk$default_value, 1)
  expect_equal(sum(hub$refinement_reference_data$ind$ref_in_scope), 1)
  expect_equal(sum(hub$refinement_reference_data$trips$ref_in_scope), 1)

  # Staging is internal: the submitted Tab 2 profile values remain available
  # for audit and are not rewritten by the transition.
  expect_equal(updated$trips_count_ref_walk$input_value, 3)
  expect_equal(updated$trips_count_cf_walk$input_value, 3)
})

test_that("Tab 2 staging ignores downstream Tab 4 trip values", {
  profile <- list(
    modes = profile_field("walking", TRUE),
    at_data_unit = profile_field("trips", TRUE),
    trips_count_ref_walk = profile_field(2, TRUE),
    trips_count_cf_walk = profile_field(3, TRUE),
    trips_number_ref_walk = profile_field(99, TRUE, 99, TRUE),
    trips_number_cf_walk = profile_field(100, TRUE, 100, TRUE),
    trips_number_total_ref = profile_field(99, TRUE, 99, TRUE),
    trips_spread_mean_ref_walk = profile_field(10, TRUE, 10, TRUE),
    trips_diversion_sources_walk = profile_field(
      list(car = list(percent = 100)), TRUE,
      list(car = list(percent = 100)), TRUE
    )
  )

  values <- .tab2_stage_input_values(profile)

  expect_equal(values$trips_count_ref_walk, 2)
  expect_equal(values$trips_count_cf_walk, 3)
  expect_null(values$trips_number_ref_walk)
  expect_null(values$trips_number_cf_walk)
  expect_null(values$trips_number_total_ref)
  expect_null(values$trips_spread_mean_ref_walk)
  expect_null(values$trips_diversion_sources_walk)
})

test_that("unchanged Tab 4 trip defaults do not override Tab 2 targets", {
  profile <- list(
    trips_number_total_ref = profile_field(100, TRUE, 100),
    trips_number_total_cf = profile_field(100, TRUE, 100),
    trips_number_ref_walk = profile_field(30, TRUE, 30),
    trips_number_cf_walk = profile_field(30, TRUE, 30),
    trips_number_cf_bike = profile_field(25, TRUE, 20)
  )
  values <- extract_input_values(profile)

  cleaned <- .drop_unmodified_trip_refinement_values(values, profile)

  expect_null(cleaned$trips_number_total_ref)
  expect_null(cleaned$trips_number_total_cf)
  expect_null(cleaned$trips_number_ref_walk)
  expect_null(cleaned$trips_number_cf_walk)
  expect_equal(cleaned$trips_number_cf_bike, 25)
})
