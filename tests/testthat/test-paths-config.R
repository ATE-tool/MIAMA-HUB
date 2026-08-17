test_that("miama_project_root() uses MIAMA_PROJECT_ROOT env var when set", {
  withr::with_envvar(list(MIAMA_PROJECT_ROOT = "/tmp/fake_project"), {
    result <- miama_project_root()
    expect_equal(result, normalizePath("/tmp/fake_project", winslash = "/", mustWork = FALSE))
  })
})

test_that("miama_hm_root() errors when MIAMA_HM_ROOT is unset and no sibling HM repo exists", {
  tmp <- withr::local_tempdir()
  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = tmp,
    MIAMA_HM_ROOT = ""
  ), {
    expect_error(miama_hm_root(), "MIAMA_HM_ROOT is not set")
  })
})

test_that("miama_hm_root() returns normalised path when env var is set", {
  withr::with_envvar(list(MIAMA_HM_ROOT = "/tmp/fake_hm"), {
    result <- miama_hm_root()
    expect_equal(result, normalizePath("/tmp/fake_hm", winslash = "/", mustWork = FALSE))
  })
})

test_that("miama_hm_root_or_null() discovers sibling MIAMA-HM repo", {
  tmp <- withr::local_tempdir()
  hub_root <- file.path(tmp, "MIAMA-HUB")
  hm_root <- file.path(tmp, "MIAMA-HM")
  dir.create(hub_root, recursive = TRUE)
  dir.create(file.path(hm_root, "health_data", "processed"), recursive = TRUE)

  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = hub_root,
    MIAMA_HM_ROOT = ""
  ), {
    expect_equal(miama_hm_root_or_null(), normalizePath(hm_root, winslash = "/", mustWork = FALSE))
    expect_equal(miama_hm_root(), normalizePath(hm_root, winslash = "/", mustWork = FALSE))
  })
})

test_that("miama_paths() returns list with expected keys", {
  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = "/tmp/fake_project",
    MIAMA_HM_ROOT      = "/tmp/fake_hm",
    MIAMA_DATA_ROOT    = "/tmp/fake_data"
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

test_that("miama_paths() sources are named parquet lists with path and format", {
  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = "/tmp/fake_project",
    MIAMA_HM_ROOT      = "/tmp/fake_hm",
    MIAMA_DATA_ROOT    = "/tmp/fake_data"
  ), {
    p <- miama_paths()
    expect_named(p$sp_attributes, c("path", "format"))
    expect_named(p$sp_trips,      c("path", "format"))
    expect_named(p$hm_sp_overall_sample, c("path", "format", "source"))
    expect_equal(p$sp_attributes$format, "parquet")
    expect_equal(p$sp_trips$format, "parquet")
    expect_equal(p$hm_sp_overall_sample$format, "parquet")
  })
})

test_that("miama_paths() sp sources point to expected parquet paths when dirs are missing", {
  # Use a temp dir with no synthpop subdirectories at all
  tmp <- withr::local_tempdir()
  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = tmp,
    MIAMA_HM_ROOT      = "/tmp/fake_hm",
    MIAMA_DATA_ROOT    = tmp
  ), {
    p <- miama_paths()
    expect_equal(p$sp_attributes$format, "parquet")
    expect_equal(p$sp_trips$format, "parquet")
    expect_match(p$sp_attributes$path, "SPindivid_CensusNTSALS_parquet$", fixed = FALSE)
    expect_match(p$sp_trips$path, "SPtrip_CensusNTSALS_parquet$", fixed = FALSE)
  })
})

test_that("miama_runtime_data_dir() falls back to packaged extdata without external root", {
  project_root <- withr::local_tempdir()
  dir.create(file.path(project_root, "data"), recursive = TRUE)

  packaged_root <- withr::local_tempdir()
  packaged_data <- file.path(packaged_root, "extdata", "data")
  dir.create(packaged_data, recursive = TRUE)

  local_mocked_bindings(
    system.file = function(..., package = NULL) {
      args <- c(...)
      if (identical(package, "MIAMAHUB") && identical(args, c("extdata", "data"))) {
        return(packaged_data)
      }
      base::system.file(..., package = package)
    },
    .env = environment(miama_runtime_data_dir)
  )

  withr::with_envvar(list(MIAMA_DATA_ROOT = ""), {
    expect_equal(
      miama_runtime_data_dir(project_root),
      normalizePath(packaged_data, winslash = "/", mustWork = FALSE)
    )
  })
})

test_that("miama_runtime_data_dir() uses explicit external root", {
  external_data <- withr::local_tempdir()
  withr::with_envvar(list(MIAMA_DATA_ROOT = external_data), {
    expect_equal(
      miama_runtime_data_dir(),
      normalizePath(external_data, winslash = "/", mustWork = FALSE)
    )
  })
})

test_that("miama_runtime_data_dir() selects source packaged data, not project data", {
  project_root <- withr::local_tempdir()
  dir.create(file.path(project_root, "data", "synthetic_pop"), recursive = TRUE)
  source_packaged_data <- file.path(project_root, "inst", "extdata", "data")
  dir.create(source_packaged_data, recursive = TRUE)

  local_mocked_bindings(
    system.file = function(...) "",
    .env = environment(miama_runtime_data_dir)
  )

  withr::with_envvar(list(MIAMA_DATA_ROOT = ""), {
    expect_equal(
      miama_runtime_data_dir(project_root),
      normalizePath(source_packaged_data, winslash = "/", mustWork = FALSE)
    )
  })
})

test_that("full config rejects packaged sample synthpop sources", {
  packaged_data <- withr::local_tempdir()
  sp_attributes <- file.path(
    packaged_data, "synthetic_pop", "SPindivid_CensusNTSALS_parquet"
  )
  sp_trips <- file.path(
    packaged_data, "synthetic_pop", "SPtrip_CensusNTSALS_parquet"
  )
  dir.create(sp_attributes, recursive = TRUE)
  dir.create(sp_trips, recursive = TRUE)

  local_mocked_bindings(
    system.file = function(..., package = NULL) {
      args <- c(...)
      if (identical(package, "MIAMAHUB") && identical(args, c("extdata", "data"))) {
        return(packaged_data)
      }
      base::system.file(..., package = package)
    },
    .env = environment(miama_resolve_config)
  )

  cfg <- list(
    workflow = list(dataset_size = "full"),
    sources = list(
      sp_attributes = list(path = sp_attributes, format = "parquet"),
      sp_trips = list(path = sp_trips, format = "parquet")
    )
  )
  expect_error(
    miama_resolve_config(cfg, validate_hm = FALSE),
    "cannot use packaged sample synthpop data"
  )
})

test_that("miama_paths() selects HUB-local HM sample before external HM", {
  tmp <- withr::local_tempdir()
  hub_dir <- file.path(tmp, "data", "health_data", "sp_overall_outcomes_sample")
  dir.create(hub_dir, recursive = TRUE)

  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = tmp,
    MIAMA_HM_ROOT      = "/tmp/fake_hm",
    MIAMA_DATA_ROOT    = file.path(tmp, "data")
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
    MIAMA_HM_ROOT      = "",
    MIAMA_DATA_ROOT    = file.path(tmp, "data")
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
    MIAMA_HM_ROOT      = "/tmp/fake_hm",
    MIAMA_DATA_ROOT    = file.path(tmp, "data")
  ), {
    p <- miama_paths()
    expect_equal(p$sp_attributes$path,   normalizePath(dev_dir, winslash = "/", mustWork = FALSE))
    expect_equal(p$sp_attributes$format, "parquet")
  })
})

test_that("miama_project_root() uses loaded package root before caller working directory", {
  withr::with_envvar(list(MIAMA_PROJECT_ROOT = ""), {
    root <- miama_project_root()
    expect_true(file.exists(file.path(root, "DESCRIPTION")))
    expect_equal(unname(read.dcf(file.path(root, "DESCRIPTION"))[1, "Package"]), "MIAMAHUB")
  })
})

test_that("miama_resolve_config() errors when sp_attributes parquet path is missing", {
  tmp <- withr::local_tempdir()
  withr::with_envvar(list(
    MIAMA_PROJECT_ROOT = tmp,
    MIAMA_HM_ROOT      = "/tmp/fake_hm",
    MIAMA_DATA_ROOT    = tmp
  ), {
    cfg <- miama_default_config()
    expect_error(miama_resolve_config(cfg), "Synthpop attributes parquet directory not found")
  })
})
