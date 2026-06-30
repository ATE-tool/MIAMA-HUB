test_that("miama_project_root() uses MIAMA_PROJECT_ROOT env var when set", {
  withr::with_envvar(list(MIAMA_PROJECT_ROOT = "/tmp/fake_project"), {
    result <- miama_project_root()
    expect_equal(result, normalizePath("/tmp/fake_project", winslash = "/", mustWork = FALSE))
  })
})

test_that("miama_hm_root() errors when MIAMA_HM_ROOT is unset", {
  withr::with_envvar(list(MIAMA_HM_ROOT = ""), {
    expect_error(miama_hm_root(), "MIAMA_HM_ROOT is not set")
  })
})

test_that("miama_hm_root() returns normalised path when env var is set", {
  withr::with_envvar(list(MIAMA_HM_ROOT = "/tmp/fake_hm"), {
    result <- miama_hm_root()
    expect_equal(result, normalizePath("/tmp/fake_hm", winslash = "/", mustWork = FALSE))
  })
})

test_that("miama_paths() returns list with expected keys", {
  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = "/tmp/fake_project",
    MIAMA_HM_ROOT      = "/tmp/fake_hm"
  ), {
    p <- miama_paths()
    expected_keys <- c(
      "project_root", "hm_root", "hm_processed_root",
      "inst_workflows", "data_dir", "cache_dir",
      "output_root", "output_lookup", "output_reference",
      "sp_attributes", "sp_trips",
      "hm_sp_overall", "hm_sp_cycle",
      "hm_sp_overall_sample", "hm_sp_cycle_sample",
      "hm_lookup_overall", "hm_lookup_cycle"
    )
    expect_true(all(expected_keys %in% names(p)))
  })
})

test_that("miama_paths() sources are named lists with path and format", {
  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = "/tmp/fake_project",
    MIAMA_HM_ROOT      = "/tmp/fake_hm"
  ), {
    p <- miama_paths()
    expect_named(p$sp_attributes, c("path", "format"))
    expect_named(p$sp_trips,      c("path", "format"))
    expect_named(p$hm_sp_overall_sample, c("path", "format", "source"))
    expect_true(p$sp_attributes$format %in% c("parquet", "dta"))
    expect_true(p$sp_trips$format      %in% c("parquet", "dta"))
    expect_equal(p$hm_sp_overall_sample$format, "parquet")
  })
})

test_that("miama_paths() sp sources fall back to dta when no parquet dirs exist", {
  # Use a temp dir with no synthpop subdirectories at all
  tmp <- withr::local_tempdir()
  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = tmp,
    MIAMA_HM_ROOT      = "/tmp/fake_hm"
  ), {
    p <- miama_paths()
    expect_equal(p$sp_attributes$format, "dta")
    expect_equal(p$sp_trips$format,      "dta")
  })
})

test_that("miama_paths() selects HUB-local HM sample before external HM", {
  tmp <- withr::local_tempdir()
  hub_dir <- file.path(tmp, "data", "health_data", "sp_overall_outcomes_sample")
  dir.create(hub_dir, recursive = TRUE)

  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = tmp,
    MIAMA_HM_ROOT      = "/tmp/fake_hm"
  ), {
    p <- miama_paths()
    expect_equal(p$hm_sp_overall_sample$path, normalizePath(hub_dir, winslash = "/", mustWork = FALSE))
    expect_equal(p$hm_sp_overall_sample$source, "hub")
  })
})

test_that("miama_paths() can resolve HUB-local HM sample without MIAMA_HM_ROOT", {
  tmp <- withr::local_tempdir()
  hub_dir <- file.path(tmp, "data", "health_data", "sp_cycle_outcomes_sample")
  dir.create(hub_dir, recursive = TRUE)

  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = tmp,
    MIAMA_HM_ROOT      = ""
  ), {
    p <- miama_paths()
    expect_null(p$hm_root)
    expect_equal(p$hm_sp_cycle_sample$path, normalizePath(hub_dir, winslash = "/", mustWork = FALSE))
    expect_equal(p$hm_sp_cycle_sample$source, "hub")
  })
})

test_that("miama_paths() selects dev_parquet when dev directory exists", {
  tmp <- withr::local_tempdir()
  dev_dir <- file.path(tmp, "data", "synthetic_pop", "SPindivid_CensusNTSALS_dev_parquet")
  dir.create(dev_dir, recursive = TRUE)

  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = tmp,
    MIAMA_HM_ROOT      = "/tmp/fake_hm"
  ), {
    p <- miama_paths()
    expect_equal(p$sp_attributes$path,   normalizePath(dev_dir, winslash = "/", mustWork = FALSE))
    expect_equal(p$sp_attributes$format, "parquet")
  })
})

test_that("miama_resolve_config() errors when sp_attributes path is missing", {
  tmp <- withr::local_tempdir()
  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = tmp,
    MIAMA_HM_ROOT      = "/tmp/fake_hm"
  ), {
    cfg <- miama_default_config()
    expect_error(miama_resolve_config(cfg), "Synthpop attributes source not found")
  })
})
