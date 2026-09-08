test_that("appraisal records retain calculation settings without profile payloads", {
  cfg <- miama_default_config()
  values <- list(trips_count_cf_bike = 1500, pop_number_cf_bike_advanced = 32,
                 trips_diversion_sources_bike = list(car = list(percent = 70)),
                 ui_action = 1, secret = "not for export")
  record <- .prepare_appraisal_record(values, cfg)
  values$trips_count_cf_bike <- 9
  expect_equal(record$calculation_inputs$value[record$calculation_inputs$parameter ==
                                                "trips_count_cf_bike"], "1500")
  expect_true("trips_diversion_sources_bike.car.percent" %in%
                record$calculation_inputs$parameter)
  expect_false(any(grepl("secret|ui_action", record$calculation_inputs$parameter)))
  expect_false(any(grepl("/Users/|/private/", record$model_parameters$value)))
})

test_that("report includes full records, escapes HTML, and preserves export configuration", {
  cfg <- miama_default_config()
  cfg$population$person_weight <- 1
  cf <- list(health_outcomes = data.frame(census_id = 1, cycle = 1L,
    age1year = 50, female = 0, dead = 10, d_dead = -1, dead_cf = 9),
    trips = data.frame(trip_mainmode = "Walk", weight_tripXhh = 1))
  data <- prepare_results_data(cf, reference_data = list(trips = cf$trips),
    results_request = list(res_outcomes = "mortality"),
    appraisal_input_values = list(trips_count_cf_walk = 20000), cfg = cfg)
  cfg$population$person_weight <- 999
  exports <- prepare_results_exports(data, cfg = cfg, include_plots = FALSE)
  expect_equal(exports$metadata$value[exports$metadata$field == "person_weight"], "1")
  exports$report$title <- "<script>alert(1)</script>"
  exports$appraisal_record$calculation_inputs <- data.frame(
    parameter = paste0("parameter_", 1:150), value = 1:150)
  file <- tempfile(fileext = ".html")
  on.exit(unlink(file))
  write_results_report(exports, file, "html")
  html <- paste(readLines(file), collapse = "\n")
  expect_match(html, "parameter_150")
  expect_match(html, "&lt;script&gt;")
  expect_false(grepl("<script>", html, fixed = TRUE))
  expect_match(html, "Effective calculation inputs")
  expect_match(paste(.results_export_markdown(exports), collapse = "\n"), "parameter_150")
})
