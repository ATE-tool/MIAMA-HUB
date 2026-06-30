test_that("get_geo_levels and get_geo_options build cached lookup from synthpop parquet", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("dplyr")

  tmp <- withr::local_tempdir()
  sp_dir <- file.path(tmp, "sp_attributes_parquet")
  lookup_dir <- file.path(tmp, "lookup")

  arrow::write_dataset(
    data.frame(
      census_id = 1:5,
      region = c("North West", "North West", "London", "London", "London"),
      lad25cd = c("E08000035", "E08000035", "E09000001", "E09000001", "E09000002"),
      lad25nm = c("Leeds", "Leeds", "City of London", "City of London", "Barking"),
      stringsAsFactors = FALSE
    ),
    sp_dir,
    format = "parquet"
  )

  cfg <- list(
    sources = list(
      sp_attributes = list(path = sp_dir, format = "parquet")
    ),
    output = list(
      lookup = lookup_dir
    )
  )

  levels <- get_geo_levels(cfg)
  regions <- get_geo_options(cfg, "reg")
  lads <- get_geo_options(cfg, "lad")

  expect_true(file.exists(file.path(lookup_dir, "geo_options.rds")))
  expect_equal(levels$geo_level, c("eng", "reg", "lad"))
  expect_equal(levels$n_options, c(1L, 2L, 3L))
  expect_equal(regions$geo_id, c("London", "North West"))
  expect_equal(regions$n_individuals, c(3L, 2L))
  expect_equal(lads$geo_id, c("E09000002", "E09000001", "E08000035"))
  expect_equal(get_geo_options(cfg, "region")$geo_level, c("reg", "reg"))
})

test_that("Hub exposes geo options through session cfg", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("dplyr")

  tmp <- withr::local_tempdir()
  sp_dir <- file.path(tmp, "sp_attributes_parquet")

  arrow::write_dataset(
    data.frame(
      census_id = 1:2,
      region = c("London", "North West"),
      lad25cd = c("E09000001", "E08000035"),
      lad25nm = c("City of London", "Leeds"),
      stringsAsFactors = FALSE
    ),
    sp_dir,
    format = "parquet"
  )

  hub <- Hub$new(cfg = list(
    sources = list(
      sp_attributes = list(path = sp_dir, format = "parquet")
    ),
    output = list(
      lookup = file.path(tmp, "lookup")
    )
  ))

  options <- hub$get_geo_options("eng")

  expect_equal(options$geo_id, "eng")
  expect_equal(options$geo_name, "England")
  expect_equal(options$n_individuals, 2L)
})

test_that("get_geo_options rejects unsupported geography levels", {
  cfg <- list(
    sources = list(
      sp_attributes = list(path = "missing", format = "parquet")
    ),
    output = list(
      lookup = withr::local_tempdir()
    )
  )

  expect_error(get_geo_options(cfg, "msoa"), "Unsupported geo_level")
})
