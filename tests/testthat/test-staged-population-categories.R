test_that("category totals and subsets use the accepted users for every mode", {
  ind <- data.frame(census_id = 1:6, age1year = c(20, 30, 40, 50, 65, NA),
                    female = 0, mmets = c(0, 2, 8, 15, 40, NA),
                    walktime_wkhr = 1, cycletime_wkhr = 1, ebiketime_wkhr = 0,
                    pttime_wkhr = 0)
  profile <- list(modes = c("walking", "cycling", "ebiking", "pt"))
  masks <- list(walk = c(TRUE, FALSE, TRUE, FALSE, TRUE, FALSE),
                bike = c(FALSE, TRUE, FALSE, TRUE, FALSE, TRUE),
                ebike = c(FALSE, FALSE, TRUE, TRUE, FALSE, TRUE),
                pt = c(TRUE, FALSE, FALSE, FALSE, TRUE, TRUE))
  for (suffix in names(masks)) ind[[paste0(".miama_user_scope_", suffix)]] <- masks[[suffix]]
  categories <- .reference_tab3_category_values(ind, trips = NULL)
  for (kind in c("age", "pa")) {
    field <- if (kind == "age") "pop_target_age_groups" else "pop_target_pa_groups"
    method <- if (kind == "age") "pop_age" else "pop_pa_level"
    payload <- categories[[kind]]
    profile[[field]] <- list(additional_data = list(ref = payload, cf = payload))
    values <- list(modes = profile$modes, pop_refine_method = method)
    values[[field]] <- names(payload)
    all <- .apply_tab3_category_counts(values, profile)
    expect_equal(all$pop_total_cf_advanced, nrow(ind))
    for (mode in profile$modes) {
      suffix <- .miama_mode_suffix(mode)
      expected <- .reference_users_count(ind, NULL, mode)$value
      expect_equal(all[[paste0("pop_number_cf_", suffix, "_advanced")]], expected)
      expect_equal(expected, sum(masks[[suffix]]))
    }
    # Dropping and restoring one category must subtract only its accepted users.
    values[[field]] <- names(payload)[-1]
    subset <- .apply_tab3_category_counts(values, profile)
    for (suffix in names(masks)) {
      expect_equal(subset[[paste0("pop_number_cf_", suffix, "_advanced")]],
                   sum(masks[[suffix]]) - payload[[1]][[paste0("pop_", suffix)]])
    }
    expect_equal(.selected_mode_individual_filter(ind, NULL, c("cycling", "ebiking")),
                 masks$bike | masks$ebike)
  }
})

test_that("unstaged source populations keep the observed activity definition", {
  ind <- data.frame(census_id = 1:2, cycletime_wkhr = c(1, 0), ebiketime_wkhr = 0)
  expect_equal(.selected_mode_individual_filter(ind, NULL, "cycling"), c(TRUE, FALSE))
  expect_equal(.selected_mode_individual_filter(ind, NULL, "ebiking"), c(FALSE, FALSE))
})
