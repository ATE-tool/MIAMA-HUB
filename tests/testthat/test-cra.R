test_that("health impacts defaults to an empty data frame", {
  payload <- build_ui_return_payload()

  expect_equal(nrow(payload$health_impacts), 0)
})

test_that("death-share path prefers sample outcome table for sample workflows", {
  tmp <- withr::local_tempdir()
  hub_root <- file.path(tmp, "MIAMA-HUB")
  hm_root <- file.path(tmp, "MIAMA-HM")
  sample_dir <- file.path(hm_root, "health_data", "processed", "sp_cycle_outcomes_sample_death_share")
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
  lookup_dir <- file.path(hm_root, "health_data", "processed", "mmet_d_cycle_lookup_death_share")
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

test_that("apply_counterfactual_health_outcomes calculates lookup deltas and cf columns", {
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
    cycle = c(0L, 0L),
    mmets_cycle = c(1, 5),
    dead = c(10, 20),
    diabetes = c(1, 2)
  )
  hm_cycle_lookup <- data.frame(
    age1year = c(30L, 30L, 40L),
    female = c(0, 0, 1),
    mr_decile = c(4L, 4L, 5L),
    cycle = c(0L, 0L, 0L),
    mmets_lo = c(0, 2, 0),
    mmets_hi = c(2, 4, 35),
    outcome = c("d_dead_per_mmet", "d_dead_per_mmet", "d_dead_per_mmet"),
    slope = c(0.1, 0.2, 0.5)
  )

  out <- apply_counterfactual_health_outcomes(
    counterfactual_data,
    reference_data,
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
    cycle = 0L,
    mmets_cycle = 1,
    dead = 10
  )
  hm_cycle_lookup <- data.table::data.table(
    age1year = c(30L, 30L),
    female = c(0, 0),
    mr_decile = c(4L, 4L),
    cycle = c(0L, 0L),
    mmets_lo = c(0, 2),
    mmets_hi = c(2, 4),
    outcome = c("d_dead_per_mmet", "d_dead_per_mmet"),
    slope = c(0.1, 0.2)
  )

  out <- apply_counterfactual_health_outcomes(
    counterfactual_data,
    reference_data,
    hm_cycle_outcomes = hm_cycle_outcomes,
    hm_cycle_lookup = hm_cycle_lookup
  )

  expect_equal(out$health_outcomes$d_dead, 0.3)
  expect_equal(out$health_outcomes$dead_cf, 10.3)
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
  hm_cycle_outcomes$cycle <- labelled(0)
  hm_cycle_outcomes$mmets_cycle <- labelled(1)

  hm_cycle_lookup <- data.frame(outcome = c("d_dead_per_mmet", "d_dead_per_mmet"))
  hm_cycle_lookup$age1year <- labelled(c(30, 30))
  hm_cycle_lookup$female <- labelled(c(0, 0))
  hm_cycle_lookup$mr_decile <- labelled(c(4, 4))
  hm_cycle_lookup$cycle <- labelled(c(0, 0))
  hm_cycle_lookup$mmets_lo <- labelled(c(0, 2))
  hm_cycle_lookup$mmets_hi <- labelled(c(2, 4))
  hm_cycle_lookup$slope <- labelled(c(0.1, 0.2))

  out <- apply_counterfactual_health_outcomes(
    counterfactual_data,
    reference_data,
    hm_cycle_outcomes = hm_cycle_outcomes,
    hm_cycle_lookup = hm_cycle_lookup
  )

  expect_equal(out$health_outcomes$d_dead, 0.3)
  expect_equal(out$health_outcomes$dead_cf, 10.3)
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
    cycle = 0L,
    mmets_cycle = 3,
    dead = 10
  )
  hm_cycle_lookup <- data.frame(
    age1year = c(30L, 30L),
    female = c(0, 0),
    mr_decile = c(4L, 4L),
    cycle = c(0L, 0L),
    mmets_lo = c(0, 2),
    mmets_hi = c(2, 4),
    outcome = c("d_dead_per_mmet", "d_dead_per_mmet"),
    slope = c(0.1, 0.2)
  )

  out <- apply_counterfactual_health_outcomes(
    counterfactual_data,
    reference_data,
    hm_cycle_outcomes = hm_cycle_outcomes,
    hm_cycle_lookup = hm_cycle_lookup
  )

  expect_equal(out$health_outcomes$d_dead, -0.3)
  expect_equal(out$health_outcomes$dead_cf, 9.7)
})
