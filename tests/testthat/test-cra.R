test_that("minimal config resolves the canonical outcome name without optional exports", {
  tmp <- withr::local_tempdir()
  hub_root <- file.path(tmp, "MIAMA-HUB")
  hm_root <- file.path(tmp, "MIAMA-HM")
  sample_dir <- file.path(hm_root, "health_data", "processed", "sp_cycle_outcomes")
  full_dir <- file.path(hm_root, "health_data", "processed", "sp_cycle_outcomes_death_share")
  dir.create(hub_root, recursive = TRUE)
  dir.create(sample_dir, recursive = TRUE)
  dir.create(full_dir, recursive = TRUE)

  cfg <- list(workflow = list(dataset_size = "sample"))

  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = hub_root,
    MIAMA_HM_ROOT = ""
  ), {
    expect_equal(
      .hm_death_share_path(cfg, "sp_cycle_outcomes_death_share"),
      normalizePath(sample_dir, winslash = "/", mustWork = FALSE)
    )
  })
})

test_that("death-share path uses shared lookup table without sample suffix", {
  tmp <- withr::local_tempdir()
  hub_root <- file.path(tmp, "MIAMA-HUB")
  hm_root <- file.path(tmp, "MIAMA-HM")
  lookup_dir <- file.path(hm_root, "health_data", "processed", "mmet_d_cycle_lookup")
  dir.create(hub_root, recursive = TRUE)
  dir.create(lookup_dir, recursive = TRUE)

  cfg <- list(workflow = list(dataset_size = "sample"))

  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = hub_root,
    MIAMA_HM_ROOT = ""
  ), {
    expect_equal(
      .hm_death_share_path(cfg, "mmet_d_cycle_lookup_death_share"),
      normalizePath(lookup_dir, winslash = "/", mustWork = FALSE)
    )
  })
})

test_that("death-share lookup loading keeps only requested person strata", {
  lookup_path <- tempfile("lookup-")
  lookup <- expand.grid(
    age1year = c(20, 40),
    female = c(0, 1),
    mr_decile = c(1, 2),
    cycle = 1:2,
    outcome = c("dead", "diabetes"),
    mmet_band = 1:2,
    KEEP.OUT.ATTRS = FALSE
  )
  lookup$mmets_lo <- lookup$mmet_band - 1
  lookup$mmets_hi <- lookup$mmet_band
  lookup$slope <- 0.1
  lookup$mmet_band <- NULL
  arrow::write_dataset(lookup, lookup_path, format = "parquet")

  cfg <- miama_default_config()
  cfg$sources$hm_death_share$lookup_cycle <- list(
    path = lookup_path,
    format = "parquet"
  )
  result <- load_hm_cycle_lookup_death_share(
    cfg,
    strata = data.frame(age1year = 20, female = 1, mr_decile = 2),
    cycles = 2
  )

  expect_equal(nrow(result), 4)
  expect_equal(unique(result$age1year), 20)
  expect_equal(unique(result$female), 1)
  expect_equal(unique(result$mr_decile), 2)
  expect_equal(unique(result$cycle), 2)
})

test_that("death-share outcome loading filters people and assessment cycles", {
  outcome_path <- tempfile("cycle-outcomes-")
  outcomes <- expand.grid(
    census_id = c(1, 2),
    cycle = 0:3,
    KEEP.OUT.ATTRS = FALSE
  )
  outcomes$mr_decile <- 1L
  outcomes$mmets_cycle <- 10
  arrow::write_dataset(outcomes, outcome_path, format = "parquet")

  cfg <- miama_default_config(dataset_size = "sample")
  cfg$sources$hm_death_share$cycle_sample <- list(
    path = outcome_path,
    format = "parquet"
  )
  result <- load_hm_cycle_outcomes_death_share(
    cfg,
    census_ids = 2,
    cycles = 0:1
  )

  expect_equal(unique(result$census_id), 2)
  expect_equal(result$cycle, 0:1)
})

test_that("apply_counterfactual_health_outcomes calculates lookup deltas and cf columns", {
  # Lookup arithmetic is tested in an active year with no build-up. Cycle zero
  # is now reserved for REF state and must never receive a scheme delta.
  reference_data <- list(
    ind = data.frame(
      census_id = c(1, 2),
      age1year = c(30L, 40L),
      female = c(0, 1),
      mmets = c(1, 5)
    )
  )
  counterfactual_data <- list(
    ind = data.frame(
      census_id = c(1, 2),
      mmets = c(3, 5)
    )
  )
  hm_cycle_outcomes <- data.frame(
    census_id = c(1, 2),
    mr_decile = c(4L, 5L),
    cycle = c(1L, 1L),
    mmets_cycle = c(1, 5),
    dead = c(10, 20),
    diabetes = c(1, 2)
  )
  hm_cycle_lookup <- data.frame(
    age1year = c(30L, 30L, 40L),
    female = c(0, 0, 1),
    mr_decile = c(4L, 4L, 5L),
    cycle = c(1L, 1L, 1L),
    mmets_lo = c(0, 2, 0),
    mmets_hi = c(2, 4, 35),
    outcome = c("d_dead_per_mmet", "d_dead_per_mmet", "d_dead_per_mmet"),
    slope = c(0.1, 0.2, 0.5)
  )

  out <- apply_counterfactual_health_outcomes(
    counterfactual_data,
    reference_data,
    include_cf_columns = TRUE,
    scheme_profile = list(scheme_peak_year = 0),
    hm_cycle_outcomes = hm_cycle_outcomes,
    hm_cycle_lookup = hm_cycle_lookup
  )

  expect_true("health_outcomes" %in% names(out))
  expect_equal(nrow(out$health_outcomes), 2)
  expect_equal(out$health_outcomes$d_dead, c(0.3, 0))
  expect_equal(out$health_outcomes$dead_cf, c(10.3, 20))
  expect_equal(out$counterfactual_health_report$n_changed_ind, 1)
  expect_true("impact_overview" %in% names(out$counterfactual_health_report))
  expect_equal(
    out$counterfactual_health_report$impact_overview$delta_total[
      out$counterfactual_health_report$impact_overview$outcome == "dead"
    ],
    0.3
  )
})

test_that("apply_counterfactual_health_outcomes accepts data.table inputs from workflow objects", {
  reference_data <- list(
    ind = data.table::data.table(
      census_id = 1,
      age1year = 30L,
      female = 0,
      mmets = 1
    )
  )
  counterfactual_data <- list(
    ind = data.table::data.table(
      census_id = 1,
      mmets = 3
    )
  )
  hm_cycle_outcomes <- data.table::data.table(
    census_id = 1,
    mr_decile = 4L,
    cycle = 1L,
    mmets_cycle = 1,
    dead = 10
  )
  hm_cycle_lookup <- data.table::data.table(
    age1year = c(30L, 30L),
    female = c(0, 0),
    mr_decile = c(4L, 4L),
    cycle = c(1L, 1L),
    mmets_lo = c(0, 2),
    mmets_hi = c(2, 4),
    outcome = c("d_dead_per_mmet", "d_dead_per_mmet"),
    slope = c(0.1, 0.2)
  )

  out <- apply_counterfactual_health_outcomes(
    counterfactual_data,
    reference_data,
    scheme_profile = list(scheme_peak_year = 0),
    hm_cycle_outcomes = hm_cycle_outcomes,
    hm_cycle_lookup = hm_cycle_lookup
  )

  expect_equal(out$health_outcomes$d_dead, 0.3)
  expect_false("dead_cf" %in% names(out$health_outcomes))
  expect_false(out$counterfactual_health_report$include_cf_columns)
})

test_that("apply_counterfactual_health_outcomes accepts labelled numeric inputs", {
  skip_if_not_installed("vctrs")

  labelled <- function(x) {
    vctrs::new_vctr(x, class = "haven_labelled", labels = c(example = 0))
  }

  reference_data <- list(ind = data.frame(census_id = 1))
  reference_data$ind$age1year <- labelled(30)
  reference_data$ind$female <- labelled(0)
  reference_data$ind$mmets <- labelled(1)

  counterfactual_data <- list(ind = data.frame(census_id = 1))
  counterfactual_data$ind$mmets <- labelled(3)

  hm_cycle_outcomes <- data.frame(census_id = 1, dead = 10)
  hm_cycle_outcomes$mr_decile <- labelled(4)
  hm_cycle_outcomes$cycle <- labelled(1)
  hm_cycle_outcomes$mmets_cycle <- labelled(1)

  hm_cycle_lookup <- data.frame(outcome = c("d_dead_per_mmet", "d_dead_per_mmet"))
  hm_cycle_lookup$age1year <- labelled(c(30, 30))
  hm_cycle_lookup$female <- labelled(c(0, 0))
  hm_cycle_lookup$mr_decile <- labelled(c(4, 4))
  hm_cycle_lookup$cycle <- labelled(c(1, 1))
  hm_cycle_lookup$mmets_lo <- labelled(c(0, 2))
  hm_cycle_lookup$mmets_hi <- labelled(c(2, 4))
  hm_cycle_lookup$slope <- labelled(c(0.1, 0.2))

  out <- apply_counterfactual_health_outcomes(
    counterfactual_data,
    reference_data,
    scheme_profile = list(scheme_peak_year = 0),
    hm_cycle_outcomes = hm_cycle_outcomes,
    hm_cycle_lookup = hm_cycle_lookup
  )

  expect_equal(out$health_outcomes$d_dead, 0.3)
  expect_false("dead_cf" %in% names(out$health_outcomes))
})

test_that("apply_counterfactual_health_outcomes handles reduced mmets with negative deltas", {
  reference_data <- list(
    ind = data.frame(census_id = 1, age1year = 30L, female = 0, mmets = 3)
  )
  counterfactual_data <- list(
    ind = data.frame(census_id = 1, mmets = 1)
  )
  hm_cycle_outcomes <- data.frame(
    census_id = 1,
    mr_decile = 4L,
    cycle = 1L,
    mmets_cycle = 3,
    dead = 10
  )
  hm_cycle_lookup <- data.frame(
    age1year = c(30L, 30L),
    female = c(0, 0),
    mr_decile = c(4L, 4L),
    cycle = c(1L, 1L),
    mmets_lo = c(0, 2),
    mmets_hi = c(2, 4),
    outcome = c("d_dead_per_mmet", "d_dead_per_mmet"),
    slope = c(0.1, 0.2)
  )

  out <- apply_counterfactual_health_outcomes(
    counterfactual_data,
    reference_data,
    scheme_profile = list(scheme_peak_year = 0),
    hm_cycle_outcomes = hm_cycle_outcomes,
    hm_cycle_lookup = hm_cycle_lookup
  )

  expect_equal(out$health_outcomes$d_dead, -0.3)
  expect_false("dead_cf" %in% names(out$health_outcomes))
  expect_equal(out$health_outcomes$dead + out$health_outcomes$d_dead, 9.7)
})

test_that("MMET lookup accepts an empty appraisal scope", {
  hm_cycle_outcomes <- data.frame(
    census_id = numeric(0), mr_decile = integer(0), cycle = integer(0),
    mmets_cycle = numeric(0), dead = numeric(0)
  )
  hm_cycle_lookup <- data.frame(
    age1year = 40L, female = 0, mr_decile = 1L, cycle = 0L,
    mmets_lo = 0, mmets_hi = 100, outcome = "d_dead_per_mmet", slope = 0.1
  )
  exposure <- data.frame(
    census_id = numeric(0), age1year = integer(0), female = numeric(0),
    mmets_ref = numeric(0), mmets_cf_ind = numeric(0), mmets_delta = numeric(0)
  )

  out <- .apply_mmet_delta_lookup(
    hm_cycle_outcomes, hm_cycle_lookup, exposure, include_cf_columns = FALSE
  )

  expect_equal(nrow(out), 0)
  expect_true("d_dead" %in% names(out))
})

test_that("HALYs reconstruct prevalence and apply disability adjustments", {
  diseases <- "diabetes"
  health <- data.frame(
    census_id = c(1, 1),
    cycle = c(0L, 1L),
    age1year = c(40, 40),
    female = c(0, 0),
    dead = c(0.10, 0.10),
    d_dead = c(0, -0.02),
    depression_remission = c(0, 0),
    d_depression_remission = c(0, 0),
    diabetes = c(0.20, 0.10),
    d_diabetes = c(0, -0.04),
    death_share_diabetes = c(0.5, 0.5),
    d_death_share_diabetes = c(0, 0)
  )
  pyld <- data.frame(
    age = c(40, 41), sex = c(1, 1), pyld_rate = c(0.1, 0.1)
  )
  dw <- data.frame(
    age = c(40, 41), sex = c(1, 1), disease = "diabetes", dw_adj = c(0.2, 0.2)
  )

  out <- calculate_health_adjusted_life_years(
    health, pyld, dw, diseases = diseases, include_cf_columns = TRUE
  )

  # Cycle 0 prevalence is opening incidence. Cycle 1 prevalence subtracts the
  # current cycle's deaths multiplied by death share.
  expect_equal(out$haly, c(0.774, 0.675), tolerance = 1e-10)
  expect_equal(out$haly_cf, c(0.774, 0.6984), tolerance = 1e-10)
  expect_equal(out$d_haly, c(0, 0.0234), tolerance = 1e-10)
})

test_that("HALYs handle exhausted populations and ages beyond parameter tables", {
  diseases <- "diabetes"
  health <- data.frame(
    census_id = c(1, 1, 2, 2),
    cycle = c(0L, 1L, 0L, 1L),
    age1year = c(40, 40, 100, 100),
    female = c(0, 0, 0, 0),
    dead = c(0.4, 0.6, 1, 0),
    d_dead = c(0, 0, 0, 0),
    depression_remission = 0,
    d_depression_remission = 0,
    diabetes = c(0.2, 0.1, 0.1, 0),
    d_diabetes = 0,
    death_share_diabetes = 0.5,
    d_death_share_diabetes = 0
  )
  pyld <- data.frame(
    age = c(40, 41, 100), sex = 1, pyld_rate = 0.1
  )
  dw <- data.frame(
    age = c(40, 41, 100), sex = 1, disease = "diabetes", dw_adj = 0.2
  )

  out <- calculate_health_adjusted_life_years(
    health, pyld, dw, diseases = diseases, include_cf_columns = TRUE
  )

  expect_equal(out$haly[2], 0)
  expect_equal(out$haly_cf[2], 0)
  expect_equal(out$d_haly[2], 0)
  expect_true(is.na(out$haly[4]))
  expect_true(is.na(out$haly_cf[4]))
  expect_true(is.na(out$d_haly[4]))
})
