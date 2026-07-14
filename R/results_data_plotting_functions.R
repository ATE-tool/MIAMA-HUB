# MIAMA-HUB Module: Results Data / Plotting Functions
# Purpose: Draft plotting helpers for Tab 5 result presentation.
#
# These functions intentionally consume the compact `plot_data` tables returned
# by `prepare_results_data()` rather than large reference/counterfactual objects.
# They are development helpers for now: UI can render these ggplot objects
# directly or recreate equivalent Shiny-native plots from the same data.

results_plot_health_overview <- function(results_data, value = c("delta", "percent_change")) {
  .require_ggplot2()
  value <- match.arg(value)
  plot_data <- .results_get_plot_data(results_data, "health_overview")
  if (nrow(plot_data) == 0) {
    return(.results_empty_plot("No health overview data available"))
  }

  y_col <- if (identical(value, "percent_change")) "percent_change" else "delta_value"
  y_lab <- if (identical(value, "percent_change")) "Percentage change" else "Delta (counterfactual - reference)"

  ggplot2::ggplot(plot_data, ggplot2::aes(x = stats::reorder(outcome_label, .data[[y_col]]), y = .data[[y_col]])) +
    ggplot2::geom_col(fill = "#2c7fb8", width = 0.72) +
    ggplot2::coord_flip() +
    ggplot2::labs(x = NULL, y = y_lab) +
    ggplot2::theme_minimal(base_size = 11)
}

results_plot_health_timeline <- function(results_data, outcomes = NULL) {
  .require_ggplot2()
  plot_data <- .results_get_plot_data(results_data, "health_timeline")
  if (nrow(plot_data) == 0 || !"cycle" %in% names(plot_data)) {
    return(.results_empty_plot("No timeline data available"))
  }
  if (!is.null(outcomes) && length(outcomes) > 0) {
    plot_data <- plot_data[plot_data$outcome %in% outcomes, , drop = FALSE]
  }
  if (nrow(plot_data) == 0) {
    return(.results_empty_plot("No selected timeline outcomes available"))
  }

  ggplot2::ggplot(plot_data, ggplot2::aes(x = cycle, y = delta_value, color = outcome_label)) +
    ggplot2::geom_hline(yintercept = 0, color = "grey75", linewidth = 0.3) +
    ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::labs(x = "Model cycle", y = "Delta (counterfactual - reference)", color = NULL) +
    ggplot2::theme_minimal(base_size = 11)
}

results_plot_trip_mode_distribution <- function(results_data) {
  .require_ggplot2()
  plot_data <- .results_get_plot_data(results_data, "trip_mode_distribution")
  if (nrow(plot_data) == 0) {
    return(.results_empty_plot("No trip mode distribution data available"))
  }

  ggplot2::ggplot(plot_data, ggplot2::aes(x = stats::reorder(trip_mainmode, proportion), y = proportion, fill = scenario)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.75), width = 0.68) +
    ggplot2::coord_flip() +
    ggplot2::scale_y_continuous(labels = function(x) paste0(round(100 * x), "%")) +
    ggplot2::scale_fill_manual(values = c(Reference = "#d95f8d", Counterfactual = "#1b9e77")) +
    ggplot2::labs(x = NULL, y = "Proportion of weighted trips", fill = NULL) +
    ggplot2::theme_minimal(base_size = 11)
}

.results_get_plot_data <- function(results_data, name) {
  if (!is.list(results_data) || is.null(results_data$plot_data) || is.null(results_data$plot_data[[name]])) {
    return(data.frame())
  }

  as.data.frame(results_data$plot_data[[name]])
}

.results_empty_plot <- function(label) {
  ggplot2::ggplot(data.frame(x = 1, y = 1), ggplot2::aes(x, y)) +
    ggplot2::geom_blank() +
    ggplot2::annotate("text", x = 1, y = 1, label = label, color = "grey40") +
    ggplot2::theme_void()
}

.require_ggplot2 <- function() {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package `ggplot2` is required for results plotting functions.", call. = FALSE)
  }
}
