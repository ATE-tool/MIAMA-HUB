test_that("mixed health outcomes use units and signs appropriate to the plotted metric", {
  cfg <- miama_default_config()
  health <- data.frame(census_id = 1:2, cycle = 1, age1year = c(40, 50),
    female = c(0, 1), dead = .1, d_dead = -.01, haly = .8, d_haly = .02)
  results <- prepare_results_data(list(health_outcomes = health), cfg = cfg,
    results_request = list(res_outcomes = c("mortality", "halys")))
  percent <- results_plot_health_overview(results, metric = "percent_reduction")
  expect_equal(percent$labels$y, "Improvement (%)")
  expect_match(percent$labels$caption, "counterfactual minus reference for HALYs")
  for (metric in c("prevented", "prevented_per_100000")) {
    plot <- results_plot_health_impacts(results, metric = metric)
    expect_match(plot$labels$y, "Health benefit", fixed = TRUE)
    expect_true(all(nchar(strsplit(plot$labels$y, "\n")[[1]]) <= 28))
    expect_identical(grepl("100,000", plot$labels$y), metric == "prevented_per_100000")
  }
  single <- results_plot_health_overview(results, outcomes = "halys", metric = "percent_reduction")
  expect_equal(single$labels$y, "Increase from reference (%)")
  modelled <- results_plot_health_timeline(results, impact_type = "cf_vs_ref",
    metric = "prevented")
  expect_match(modelled$labels$y, "modelled", ignore.case = TRUE)
  expect_false(grepl("%", modelled$labels$y, fixed = TRUE))
})
