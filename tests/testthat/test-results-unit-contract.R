unit_contract_results <- function() {
  prepare_results_data(list(health_outcomes = data.frame(
    census_id = 1, cycle = 1:2, age1year = 40, female = 0,
    dead = c(.1, .2), d_dead = c(-.01, -.02),
    haly = c(.8, .7), d_haly = .02)),
    results_request = list(res_outcomes = c("mortality", "halys")))
}

test_that("scenario plots actually normalize values and tooltips per 100000", {
  results <- unit_contract_results()
  for (plot_fun in list(results_plot_health_timeline, results_plot_health_overview)) {
    absolute <- plot_fun(results, impact_type = "cf_vs_ref", metric = "prevented")
    normalized <- plot_fun(results, impact_type = "cf_vs_ref", metric = "prevented_per_100000")
    expect_equal(normalized$data$value, 100000 * absolute$data$value)
    expect_match(normalized$labels$y, "per 100,000", fixed = TRUE)
    expect_true(all(grepl("per 100,000 people", normalized$data$tooltip_text, fixed = TRUE)))
    unsupported <- plot_fun(results, impact_type = "cf_vs_ref", metric = "percent_reduction")
    expect_match(unsupported$labels$caption, "difference between scenarios")
    expect_false("value" %in% names(unsupported$data))
  }
})

test_that("mode-attributed percentages never silently become absolute values", {
  results <- unit_contract_results()
  attributed <- results$plot_data$health_cube
  attributed$mode <- "cycling"
  results$plot_data$health_cube <- rbind(results$plot_data$health_cube, attributed)
  for (plot_fun in list(results_plot_health_impacts, results_plot_health_timeline,
                       results_plot_health_overview)) {
    plot <- plot_fun(results, modes = "cycling", metric = "percent_reduction")
    expect_match(plot$labels$caption, "no separate REF denominator")
    expect_false("prevented_value" %in% names(plot$data))
  }
  overall <- results_plot_health_impacts(results, modes = NULL, metric = "percent_reduction")
  expect_equal(overall$data$percent_reduction[overall$data$outcome == "mortality"], 10)
})

test_that("panels state units and cumulative normalization retains the cohort", {
  results <- unit_contract_results()
  plot <- results_plot_health_impacts(results, metric = "prevented_per_100000")
  labels <- .results_unit_labeller(plot$data, "prevented_per_100000")(
    data.frame(outcome_label = unique(plot$data$outcome_label)))
  expect_true(any(grepl("gained HALYs", unlist(labels), fixed = TRUE)))
  expect_true(any(grepl("prevented deaths", unlist(labels), fixed = TRUE)))
  timeline <- results_plot_health_timeline(results, metric = "prevented")
  expect_equal(nrow(ggplot2::ggplot_build(timeline)$layout$layout), 1)
  expect_equal(length(unique(timeline$data$outcome)), 2)
  health <- data.frame(census_id = c(1, 2, 1), cycle = c(1, 1, 2),
    age1year = 40, female = 0, dead = .1, d_dead = -.01)
  results <- prepare_results_data(list(health_outcomes = health),
    results_request = list(res_outcomes = "mortality"))
  cumulative <- results_filter_health_data(results, aggregation = "timeline", timeline_type = "cumulative")
  expect_equal(cumulative$population, c(2, 2))
  expect_equal(cumulative$prevented_per_100000, c(1000, 1500))
})
