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
  profile$pop_target_age_groups$additional_data <- list()
  profile$pop_target_pa_groups$additional_data <- list()
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
  expect_equal(updated$pop_number_ref_walk_advanced$default_value, 1)
  expect_equal(updated$pop_number_cf_walk_advanced$default_value, 2)
  expect_false(updated$pop_number_ref_walk_advanced$is_filled)
  expect_null(updated$pop_number_ref_walk_advanced$input_value)
  expect_true("input_value" %in% names(updated$pop_number_ref_walk_advanced))
  expect_true("input_value" %in% names(updated$pop_total_ref_advanced))
  expect_equal(updated$pop_number_ref_walk_advanced$additional_data$default_value_backup, 1)
  expect_equal(
    updated$pop_target_age_groups$additional_data$pop_age_18_29$pop_walk,
    1
  )
  expect_equal(
    updated$pop_target_age_groups$additional_data$pop_age_18_29$pop_walk_cf,
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
