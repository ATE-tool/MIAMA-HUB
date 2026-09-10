diagnostic_fixture <- function() {
  ind <- data.frame(census_id = c(1, 2, 3, -1, 4),
                    .miama_donor_census_id = c(1, 2, 3, 1, 4),
                    ref_in_scope = c(TRUE, TRUE, FALSE, TRUE, FALSE),
                    cf_in_scope = c(TRUE, TRUE, TRUE, TRUE, FALSE),
                    user_walk = TRUE, user_bike = TRUE,
                    cf_mmet_delta = c(0, 2, 0, 0, 99))
  for (mode in c("walking", "cycling", "ebiking", "pt", "other_activity")) {
    ind[[paste0("cf_mmet_delta_", mode)]] <- 0
  }
  ind$cf_mmet_delta_walking <- c(1, 2, 0, 0, 99)
  ind$cf_mmet_delta_cycling <- c(-1, 0, 0, 0, 0)
  list(ind = ind)
}

test_that("diagnostics distinguish reserves, copies and overlapping mode changes", {
  data <- diagnostic_fixture()
  before <- serialize(data, NULL)
  out <- .appraisal_population_diagnostics(data, data)
  expect_equal(out$populations$retained_person_records, c(5, 5))
  expect_equal(out$populations$assessed_people, c(3, 4))
  expect_equal(out$populations$retained_unique_source_donors, c(4, 4))
  expect_equal(out$populations$assessed_unique_source_donors, c(2, 3))
  expect_equal(out$populations$assessed_copied_records, c(1, 1))
  expect_equal(out$exposure_changes, list(assessed_union_people = 4L,
    net_mmet_changed_people = 1L, any_mode_mmet_changed_people = 2L))
  expect_identical(serialize(data, NULL), before)
  # Reporting must not depend on row order or sum overlapping mode users.
  reversed <- data
  reversed$ind <- reversed$ind[5:1, ]
  expect_equal(.appraisal_population_diagnostics(data, reversed), out)
})

test_that("empty and unavailable snapshots have distinct diagnostic counts", {
  empty <- list(ind = data.frame(census_id = integer()))
  out <- .appraisal_population_diagnostics(empty, empty)
  expect_true(all(unlist(out$populations[-1]) == 0))
  expect_true(all(unlist(out$exposure_changes) == 0))
  missing <- .appraisal_population_diagnostics(NULL, list())
  expect_true(all(is.na(unlist(missing$populations[-1]))))
  plain <- list(ind = data.frame(census_id = 1:2))
  out <- .appraisal_population_diagnostics(plain, plain)
  expect_equal(out$populations$assessed_people, c(2, 2))
  expect_equal(out$populations$assessed_copied_records, c(0, 0))
  expect_true(is.na(out$exposure_changes$net_mmet_changed_people))
  plain$ind$.miama_donor_census_id <- c(1, NA)
  expect_true(all(is.na(.appraisal_population_diagnostics(plain, plain)$populations$assessed_unique_source_donors)))
})

test_that("both report entry points expose counts from their current snapshots", {
  data <- diagnostic_fixture()
  expected <- .appraisal_population_diagnostics(data, data)
  cf_report <- .counterfactual_report_finalize(list(notes = character()), data, data)
  expect_equal(cf_report$population_diagnostics, expected)
  data$counterfactual_report <- cf_report
  data$ind$cf_in_scope[3] <- FALSE
  data$health_outcomes <- data.frame(census_id = 1L, cycle = 1L,
                                    age1year = 50, female = 0,
                                    dead = 0.02, d_dead = -0.01, dead_cf = 0.01)
  results <- prepare_results_data(data, data, results_request = list(res_outcomes = "mortality"))
  expect_equal(results$results_report$population_diagnostics$populations$assessed_people, c(3, 3))
  expect_equal(.appraisal_population_diagnostics(NULL, data),
               .appraisal_population_diagnostics(data, data))
})
