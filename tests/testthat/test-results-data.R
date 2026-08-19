test_that("health outcome options expose configured Tab 5 metadata", {
  options <- get_health_outcome_options()

  expect_equal(
    options$outcome,
    c(
      "mortality", "cvd", "ihd", "stroke", "diabetes", "depression",
      "alzheimer", "cancers", "breast_cancer", "colon_cancer"
    )
  )
  expect_equal(options$label[options$outcome == "mortality"], "All-cause mortality")
  expect_true(options$default[options$outcome == "ihd"])
  expect_false(options$default[options$outcome == "breast_cancer"])
  expect_true(all(options$available))
})

test_that("health outcome options can verify a health data schema", {
  columns <- c(
    "dead", "d_dead", "dead_cf",
    "diabetes", "d_diabetes"
  )
  options <- get_health_outcome_options(health_data = columns)

  expect_true(options$available[options$outcome == "mortality"])
  expect_true(options$delta_available[options$outcome == "mortality"])
  expect_true(options$counterfactual_available[options$outcome == "mortality"])
  expect_true(options$available[options$outcome == "diabetes"])
  expect_true(options$delta_available[options$outcome == "diabetes"])
  expect_false(options$counterfactual_available[options$outcome == "diabetes"])
  expect_false(options$available[options$outcome == "cvd"])
  expect_equal(get_health_outcome_options(health_data = columns, available_only = TRUE)$outcome,
               c("mortality", "diabetes"))
})

test_that("composite outcomes require every configured component", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = 1,
      cycle = 1L,
      age1year = 50,
      female = 0,
      stroke = 2,
      d_stroke = -0.1,
      stroke_cf = 1.9
    )
  )

  out <- prepare_results_data(
    counterfactual_data,
    results_request = list(res_outcomes = "cvd")
  )

  expect_equal(nrow(out$results_table), 0)
  expect_equal(out$results_report$missing_requested_outcomes, "cvd")
})

test_that("prepare_results_data aggregates filtered health outcomes", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = c(1, 2),
      cycle = c(1L, 1L),
      age1year = c(30, 60),
      female = c(0, 1),
      dead = c(10, 20),
      d_dead = c(-1, -2),
      dead_cf = c(9, 18),
      diabetes = c(3, 4),
      d_diabetes = c(-0.5, -0.25),
      diabetes_cf = c(2.5, 3.75),
      stroke = c(2, 6),
      d_stroke = c(-0.1, -0.2),
      stroke_cf = c(1.9, 5.8)
    ),
    trips = data.frame(
      census_id = c(1, 2),
      trip_mainmode = c("Walk", "Car"),
      weight_tripXhh = c(1, 3)
    )
  )
  reference_data <- list(
    trips = data.frame(
      census_id = c(1, 2),
      trip_mainmode = c("Walk", "Car"),
      weight_tripXhh = c(1, 4)
    )
  )

  out <- prepare_results_data(
    counterfactual_data = counterfactual_data,
    reference_data = reference_data,
    results_request = list(
      res_outcomes = c("mortality", "diabetes"),
      res_age_groups = c("age_30_39", "age_60_plus"),
      res_gender = c("male", "female"),
      res_modes_filter = c("walking", "cycling"),
      res_aggregation = "total",
      res_impact_type = "attributable"
    ),
    cfg = utils::modifyList(miama_default_config(), list(population = list(person_weight = 1)))
  )

  expect_equal(sort(out$results_table$outcome), c("diabetes", "mortality"))
  expect_equal(out$results_table$delta_value[out$results_table$outcome == "mortality"], -3)
  expect_equal(out$headline_metrics$premature_deaths_prevented, 3)
  expect_equal(out$headline_metrics$disease_cases_prevented, 0.75)
  expect_true(nrow(out$plot_data$trip_mode_distribution) > 0)
  expect_true(nrow(out$plot_data$health_cube) > 0)
  expect_true(all(c("mode", "mode_label", "scenario", "proportion") %in%
                    names(out$plot_data$trip_mode_distribution)))
  expect_true("Mode-specific health impact attribution is not implemented yet; health results use `mode = all_modes`." %in% out$results_report$notes)
  expect_identical(
    out$plot_data$age_group_levels$id,
    c("age_18_29", "age_30_39", "age_40_49", "age_50_59", "age_60_plus")
  )
})

test_that("results age groups use the configured Tab 3 boundaries", {
  cfg <- miama_default_config()

  expect_identical(
    .results_age_group(c(17, 18, 29, 30, 39, 40, 49, 50, 59, 60, 90), cfg),
    c(NA, "age_18_29", "age_18_29", "age_30_39", "age_30_39",
      "age_40_49", "age_40_49", "age_50_59", "age_50_59",
      "age_60_plus", "age_60_plus")
  )
  expect_identical(.results_age_group_levels(cfg)$label, cfg$spread$age$labels)
})

test_that("prepare_results_data supports timeline and population aggregation", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = c(1, 1, 2, 2),
      cycle = c(0L, 1L, 0L, 1L),
      age1year = c(30, 31, 60, 61),
      female = c(0, 0, 1, 1),
      dead = c(10, 11, 20, 21),
      d_dead = c(-1, -1.1, -2, -2.1),
      dead_cf = c(9, 9.9, 18, 18.9)
    )
  )

  out <- prepare_results_data(
    counterfactual_data = counterfactual_data,
    results_request = list(
      res_outcomes = "mortality",
      res_aggregation = "timeline",
      res_pop_aggregation = "gender"
    ),
    cfg = utils::modifyList(miama_default_config(), list(population = list(person_weight = 1)))
  )

  expect_true("cycle" %in% names(out$results_table))
  expect_true("gender" %in% names(out$results_table))
  expect_equal(nrow(out$results_table), 2)
  expect_equal(out$results_report$cycle_zero_rows_excluded, 2)
})

test_that("AMAT outputs contain annual and cumulative LY, HLY, and incidence impacts", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = c(1, 1),
      cycle = c(1L, 2L),
      age1year = c(40, 41),
      female = c(0, 0),
      dead = c(0.10, 0.10),
      d_dead = c(-0.02, -0.02),
      dead_cf = c(0.08, 0.08),
      unhealthy = c(0.20, 0.10),
      d_unhealthy = c(-0.05, -0.02),
      unhealthy_cf = c(0.15, 0.08)
    )
  )
  cfg <- utils::modifyList(
    miama_default_config(),
    list(population = list(person_weight = 20), results = list(amat_horizon_years = 40L))
  )
  results_data <- prepare_results_data(counterfactual_data, cfg = cfg)
  amat <- prepare_results_amat_outputs(results_data, horizon_years = 40)

  expect_true(all(c("life_years", "healthy_life_years", "mortality") %in% amat$timeline$measure))
  life_years <- amat$timeline[amat$timeline$measure == "life_years", ]
  healthy_life_years <- amat$timeline[amat$timeline$measure == "healthy_life_years", ]
  mortality <- amat$timeline[amat$timeline$measure == "mortality", ]

  expect_equal(life_years$annual_benefit, c(0.4, 0.8))
  expect_equal(life_years$cumulative_benefit, c(0.4, 1.2))
  expect_equal(healthy_life_years$annual_benefit, c(1, 1.4))
  expect_equal(healthy_life_years$cumulative_benefit, c(1, 2.4))
  expect_equal(mortality$annual_delta_cf_minus_ref, c(-0.4, -0.4))
  expect_equal(mortality$cumulative_benefit, c(0.4, 0.8))
  expect_equal(results_data$headline_metrics$life_years_saved, 1.2)

  first_year <- prepare_results_amat_outputs(results_data, horizon_years = 1)
  expect_equal(unique(first_year$timeline$cycle), 1L)
  expect_true(all(first_year$summary$cycle == 1L))
})

test_that("result plotting functions return ggplot objects", {
  skip_if_not_installed("ggplot2")

  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = c(1, 1),
      cycle = c(0L, 1L),
      age1year = c(30, 31),
      female = c(0, 0),
      dead = c(10, 11),
      d_dead = c(-1, -1.1),
      dead_cf = c(9, 9.9)
    )
  )

  results_data <- prepare_results_data(
    counterfactual_data,
    cfg = utils::modifyList(miama_default_config(), list(population = list(person_weight = 1)))
  )
  results_data$plot_data$trip_mode_distribution <- data.frame(
    mode = rep(c("walking", "cycling"), each = 2),
    mode_label = rep(c("Walking", "Cycling"), each = 2),
    scenario = rep(c("Reference", "Counterfactual"), 2),
    trips = c(10, 12, 4, 6),
    proportion = c(10 / 14, 12 / 18, 4 / 14, 6 / 18)
  )

  overview <- results_plot_health_overview(results_data)
  expect_s3_class(overview, "ggplot")
  expect_equal(overview$labels$title, "Health impact by outcome")
  expect_equal(overview$labels$x, "Health outcome")
  expect_equal(overview$labels$y, "Reduction from reference (%)")
  expect_s3_class(results_plot_health_overview(results_data, impact_type = "cf_vs_ref"), "ggplot")
  gender_plot <- results_plot_health_impacts(results_data, group_by = "gender")
  expect_s3_class(gender_plot, "ggplot")
  expect_equal(gender_plot$labels$title, "Health impact by gender")
  expect_equal(gender_plot$labels$x, "Gender")
  timeline <- results_plot_health_timeline(results_data)
  expect_s3_class(timeline, "ggplot")
  expect_equal(timeline$labels$title, "Health impacts over time")
  expect_match(timeline$labels$x, "Model year")
  expect_s3_class(results_plot_health_timeline(results_data, impact_type = "cf_vs_ref"), "ggplot")
  mode_plot <- results_plot_trip_mode_distribution(results_data)
  expect_s3_class(mode_plot, "ggplot")
  expect_equal(mode_plot$labels$title, "Reference and counterfactual travel by mode")
  expect_equal(mode_plot$labels$x, "Travel mode")
  expect_equal(mode_plot$labels$y, "Share of weighted trips (%)")
})

test_that("results_filter_health_data supports interactive Tab 5 filters", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = c(1, 1, 2, 2),
      cycle = c(0L, 1L, 0L, 1L),
      age1year = c(30, 31, 60, 61),
      female = c(0, 0, 1, 1),
      dead = c(10, 11, 20, 21),
      d_dead = c(-1, -1, -2, -2),
      dead_cf = c(9, 10, 18, 19),
      diabetes = c(2, 2, 4, 4),
      d_diabetes = c(-0.1, -0.1, -0.2, -0.2),
      diabetes_cf = c(1.9, 1.9, 3.8, 3.8)
    )
  )
  results_data <- prepare_results_data(
    counterfactual_data,
    cfg = utils::modifyList(miama_default_config(), list(population = list(person_weight = 1)))
  )

  filtered <- results_filter_health_data(
    results_data,
    outcomes = "mortality",
    age_groups = "age_30_39",
    gender = "male",
    aggregation = "timeline",
    group_by = "gender"
  )

  expect_equal(unique(filtered$outcome), "mortality")
  expect_equal(unique(filtered$gender), "male")
  expect_equal(filtered$cycle, 1L)
  expect_equal(filtered$prevented_value, 1)
})

test_that("trip plot data groups numeric NTS main modes for presentation", {
  trips <- data.frame(
    trip_mainmode = 1:13,
    weight_tripXhh = rep(1, 13)
  )
  out <- .results_trip_mode_distribution(
    reference_data = list(trips = trips),
    counterfactual_data = list(trips = trips)
  )

  expect_equal(sort(unique(out$mode)), sort(c("walking", "cycling", "driving", "pt")))
  expect_equal(out$trips[out$scenario == "Reference" & out$mode == "driving"], 5)
  expect_equal(out$trips[out$scenario == "Reference" & out$mode == "pt"], 6)
  expect_equal(sum(out$proportion[out$scenario == "Reference"]), 1)
})

test_that("Hub builds results data from counterfactual health outcomes", {
  hub <- Hub$new(cfg = list())
  hub$set_appraisal_inputs(build_mock_appraisal_inputs(
    overrides = list(
      res_outcomes = list(input_value = "mortality"),
      res_aggregation = list(input_value = "total")
    )
  ))

  hub$reference_data <- list(ind = data.frame(census_id = 1))
  hub$counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = 1,
      cycle = 1L,
      age1year = 30,
      female = 0,
      dead = 10,
      d_dead = -1,
      dead_cf = 9
    )
  )

  out <- hub$build_results_data()

  expect_equal(out$results_table$outcome, "mortality")
  expect_equal(hub$get_results_data(), out)
})

test_that("results exports assemble filtered tables, metadata, plots, and drafts", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = rep(1:2, each = 2),
      cycle = rep(1:2, 2),
      age1year = c(40, 41, 70, 71),
      female = c(0, 0, 1, 1),
      dead = c(10, 11, 20, 21),
      d_dead = c(-1, -1.1, -2, -2.1),
      dead_cf = c(9, 9.9, 18, 18.9),
      diabetes = c(3, 3.2, 5, 5.2),
      d_diabetes = c(-0.2, -0.2, -0.3, -0.3),
      diabetes_cf = c(2.8, 3, 4.7, 4.9),
      stroke = c(1, 1.1, 2, 2.1),
      d_stroke = c(-0.1, -0.1, -0.2, -0.2),
      stroke_cf = c(0.9, 1, 1.8, 1.9)
    ),
    trips = data.frame(
      trip_mainmode = c("Walk", "Bicycle", "Car"),
      weight_tripXhh = c(5, 3, 12)
    )
  )
  reference_data <- list(
    trips = data.frame(
      trip_mainmode = c("Walk", "Bicycle", "Car"),
      weight_tripXhh = c(4, 2, 14)
    )
  )
  results_data <- prepare_results_data(
    counterfactual_data,
    reference_data,
    results_request = list(
      res_outcomes = c("mortality", "diabetes", "stroke"),
      res_age_groups = c("age_40_49", "age_60_plus"),
      res_gender = c("male", "female"),
      res_aggregation = "total",
      res_pop_aggregation = "total",
      res_impact_type = "attributable"
    ),
    cfg = utils::modifyList(miama_default_config(), list(population = list(person_weight = 1)))
  )
  profile <- list(
    appraisal_name = list(is_filled = TRUE, input_value = "Test scheme"),
    geo_id = list(is_filled = TRUE, input_value = "E00000001"),
    geo_name = list(is_filled = FALSE, input_value = NULL, default_value = "Test place"),
    modes = list(is_filled = TRUE, input_value = c("walking", "cycling"))
  )

  exports <- prepare_results_exports(
    results_data,
    profile = profile,
    cfg = utils::modifyList(miama_default_config(), list(population = list(person_weight = 1))),
    metric = "prevented"
  )

  expect_s3_class(exports, "miama_results_exports")
  expect_equal(sort(unique(exports$results_table$outcome)), c("diabetes", "mortality", "stroke"))
  expect_equal(exports$metadata$value[exports$metadata$field == "appraisal_name"], "Test scheme")
  expect_equal(exports$metadata$value[exports$metadata$field == "geo_name"], "Test place")
  expect_equal(length(exports$plots), 5)
  expect_true(all(vapply(exports$plots, inherits, logical(1), what = "ggplot")))
  expect_true(all(c("field", "value", "unit", "mapping_status") %in% names(exports$amat_inputs)))
  expect_true(all(c("annual_delta_cf_minus_ref", "cumulative_benefit") %in%
                    names(exports$amat_health_timeline)))
  expect_true(all(exports$amat_health_summary$cycle <= 40))
  expect_match(exports$amat_inputs$value[exports$amat_inputs$field == "schema_version"], "draft")
  expect_true(is.na(exports$headline_metrics$value[
    exports$headline_metrics$metric == "disease_cases_prevented"
  ]))
  expect_equal(exports$headline_metrics$status[
    exports$headline_metrics$metric == "disease_cases_prevented"
  ], "not_aggregated")
})

test_that("results export writers create usable files", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = 1,
      cycle = 1L,
      age1year = 50,
      female = 0,
      dead = 10,
      d_dead = -1,
      dead_cf = 9
    ),
    trips = data.frame(trip_mainmode = "Walk", weight_tripXhh = 1)
  )
  results_data <- prepare_results_data(
    counterfactual_data,
    reference_data = list(trips = counterfactual_data$trips),
    results_request = list(res_outcomes = "mortality"),
    cfg = utils::modifyList(miama_default_config(), list(population = list(person_weight = 1)))
  )
  exports <- prepare_results_exports(
    results_data,
    cfg = utils::modifyList(miama_default_config(), list(population = list(person_weight = 1))),
    metric = "prevented"
  )
  directory <- withr::local_tempdir()

  csv_file <- file.path(directory, "results.csv")
  xlsx_file <- file.path(directory, "results.xlsx")
  amat_file <- file.path(directory, "amat.csv")
  report_file <- file.path(directory, "report.md")
  report_docx <- file.path(directory, "report.docx")
  plots_dir <- file.path(directory, "plots")
  zip_file <- file.path(directory, "plots.zip")

  write_results_csv(exports, csv_file)
  write_results_xlsx(exports, xlsx_file)
  write_results_amat_csv(exports, amat_file)
  write_results_report(exports, report_file, format = "markdown")
  if (rmarkdown::pandoc_available()) {
    write_results_report(exports, report_docx, format = "docx")
  }
  png_files <- write_results_plot_pngs(exports, plots_dir, width = 4, height = 3, dpi = 72)
  write_results_plots_zip(exports, zip_file, width = 4, height = 3, dpi = 72)

  expect_true(all(file.exists(c(csv_file, xlsx_file, amat_file, report_file, zip_file))))
  expect_true(all(file.info(c(csv_file, xlsx_file, amat_file, report_file, zip_file))$size > 0))
  if (rmarkdown::pandoc_available()) {
    expect_true(file.exists(report_docx))
    expect_gt(file.info(report_docx)$size, 0)
  }
  expect_true(all(file.exists(png_files)))
  expect_true(all(file.info(png_files)$size > 0))
  expect_true("Results" %in% openxlsx::getSheetNames(xlsx_file))
  expect_true("AMAT_health_timeline" %in% openxlsx::getSheetNames(xlsx_file))
  expect_true("annual_benefit" %in% names(utils::read.csv(amat_file)))
  expect_true("health_overview.png" %in% utils::unzip(zip_file, list = TRUE)$Name)
  expect_match(paste(readLines(report_file), collapse = "\n"), "# MIAMA appraisal results")
})

test_that("results scale synthetic-person outcomes to represented population", {
  counterfactual_data <- list(
    health_outcomes = data.frame(
      census_id = 1,
      cycle = 1L,
      age1year = 30,
      female = 0,
      dead = 0.01,
      d_dead = -0.002,
      dead_cf = 0.008
    )
  )

  out <- prepare_results_data(counterfactual_data)

  expect_equal(out$results_table$ref_value, 0.2)
  expect_equal(out$results_table$prevented_value, 0.04)
  expect_equal(out$results_table$population, 20)
  expect_equal(out$results_table$prevented_per_100000, 200)
  expect_equal(out$results_report$population_person_weight, 20)
})
