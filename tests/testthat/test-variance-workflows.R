variance_workflow <- new.env(parent = globalenv())
sys.source(testthat::test_path("..", "..", "inst", "workflows", "dev_sampling_variance.R"),
           envir = variance_workflow)

test_that("trip context preserves mode-specific absolute targets and checks consistency", {
  field <- function(x) list(is_filled = TRUE, input_value = x)
  profile <- list(trips_count_ref_bike = field(26), trips_count_cf_bike = field(31),
    trips_count_ref_walk = field(371), trips_count_cf_walk = field(445))
  rows <- variance_workflow$sv_trip_input_rows(profile, 100, "walking+cycling")
  expect_equal(rows$mode, c("walking", "cycling"))
  expect_equal(rows$additional_weekly_trips, c(74, 5))
  expect_equal(rows$ref_weekly_trips, c(371, 26))
  expect_error(variance_workflow$sv_trip_input_rows(list(), 100, "cycling"), "Missing or invalid")
  directory <- tempfile()
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  saveRDS(list(profile = profile), file.path(directory, "a.rds"))
  saveRDS(list(profile = profile), file.path(directory, "b.rds"))
  runs <- data.frame(id = c("a", "a", "b"), population = 100,
    modes = "cycling", status = "ok")
  expect_equal(nrow(variance_workflow$sv_trip_inputs(runs, directory)), 1L)
  profile$trips_count_cf_bike <- field(32)
  saveRDS(list(profile = profile), file.path(directory, "b.rds"))
  expect_error(variance_workflow$sv_trip_inputs(runs, directory), "Trip targets vary")
})
sys.source(testthat::test_path("..", "..", "inst", "workflows", "dev_route_benchmark.R"),
           envir = variance_workflow)

test_that("sampling summaries separate outcome groups and suppress near-zero ratios", {
  runs <- data.frame(population = 100, modes = "walking", experiment = "fixed_ref",
    outcome = rep(c("halys", "mortality"), each = 3), benefit = c(1, 2, 3, 0, 0, 0),
    status = "ok", exposure_hash = rep(letters[1:3], 2))
  summary <- variance_workflow$sv_summary(runs)
  halys <- summary[summary$outcome == "halys", ]
  expect_equal(halys$mean, 2)
  expect_equal(halys$sd, 1)
  expect_equal(halys$relative_sd_percent, 50)
  expect_equal(halys$distinct_exposures, 3)
  expect_true(is.na(summary$relative_sd_percent[summary$outcome == "mortality"]))
  runs$status[1] <- "error"
  expect_equal(variance_workflow$sv_summary(runs)$n, c(2L, 3L))
})

test_that("trip-scale scenarios remain separate at the same population size", {
  runs <- data.frame(population = 5000, modes = "cycling", experiment = "fixed_ref",
    outcome = "halys", benefit = c(1, 3, 10, 14), status = "ok",
    exposure_hash = letters[1:4], additional_cycling_trips = c(100, 100, 500, 500))
  summary <- variance_workflow$sv_summary(runs)
  expect_equal(summary$additional_cycling_trips, c(100, 500))
  expect_equal(summary$mean, c(2, 12))
  expect_equal(summary$n, c(2L, 2L))
})

test_that("benchmark health totals exclude baseline and mode attribution duplicates", {
  cube <- data.frame(mode = c("all_modes", "all_modes", "all_modes", "walking"),
    cycle = c(0, 1, 1, 1), outcome = c("halys", "halys", "mortality", "halys"),
    delta_value = c(100, .025, -.003, .025))
  out <- list(results_data = list(plot_data = list(health_cube = cube)))
  expect_equal(variance_workflow$bm_health_totals(out), c(halys = .025, deaths_prevented = .003))
})
