# MIAMA-HUB Module: Results Data / Plotting Functions
# Purpose: Reusable Tab 5 plot-data filters and development ggplot functions.
#
# Results presentation outline:
#
# Core 1 -- Health impact by outcome
#   One bar per selected health outcome. Shows either cumulative prevented
#   outcomes/percentage reduction or side-by-side reference and counterfactual.
#
# Core 2 -- Health impacts over time
#   One cumulative line per selected health outcome by default. Annual impact
#   and faceted reference/counterfactual lines remain diagnostic options.
#
# Advanced 1 -- Health impact by age
#   Cumulative health impacts split across the five configured age groups and
#   faceted by outcome. This is a health-impact view, not the input spread plot.
#
# Advanced 2 -- Health impact by gender
#   Cumulative health impacts split by male/female model strata and faceted by
#   outcome. Labels follow the gender categories present in HM output.
#
# Advanced 3 -- Health impact by active mode
#   Attributable health deltas allocated from each individual's mode-specific
#   MMET contribution. Absolute reference/counterfactual burdens remain all-mode.
#
# Advanced 4 -- Travel by mode
#   Reference and counterfactual trip-row totals or shares by travel mode.
#   This remains distinct from the MMET-attributed health-by-mode view.
#
# Label and unit contract:
# - Titles, subtitles, captions, and axis labels have semantic defaults derived
#   from the selected metric and returned data. Every plot exposes explicit
#   `title`, `subtitle`, `caption`, `x_label`, and `y_label` overrides for UI use.
# - Pass `NULL` to use the semantic default or `NA_character_` to suppress a
#   label. Changing a label does not transform the underlying numeric values.
# - Benefit values are reference minus counterfactual for adverse outcomes and
#   counterfactual minus reference for HALYs; positive values are health gains.
# - `prevented_per_100000` uses the represented population attached to each
#   result group. Cycle 0 is excluded before plot data are constructed.
# - Reference/counterfactual health values are modelled deaths, disease cases,
#   or the generic "health outcomes" when both types occur in one plot.
# - Trip shares are proportions (displayed as percentages); trip counts follow
#   the appraisal contract that one synthetic trip row is one trip record.
#
# UI contract:
# - `results_filter_health_data()` filters and aggregates the compact health cube
#   without rerunning counterfactual or health-model calculations.
# - Plot functions consume only `results_data$plot_data`, so MIAMA-UI can use the
#   same functions or reproduce them from the returned compact data frames.
# - Each plot maps a formatted HTML `tooltip_text` aesthetic. Interactive callers
#   should use `plotly::ggplotly(plot, tooltip = "text")` to suppress raw field
#   names while static callers can continue to use the returned ggplot object.
# - `modes = NULL` uses the canonical `all_modes` health total. Supplying active
#   modes selects attributed health deltas for those modes.


# Filterable Health Plot Data ------------------------------------------------

results_filter_health_data <- function(
    results_data,
    outcomes = NULL,
    age_groups = NULL,
    gender = NULL,
    aggregation = c("total", "timeline"),
    group_by = c("outcome", "age_group", "gender", "mode", "none"),
    timeline_type = c("annual", "cumulative"),
    modes = NULL
) {
  aggregation <- match.arg(aggregation)
  group_by <- match.arg(group_by)
  timeline_type <- match.arg(timeline_type)
  cube <- .results_get_plot_data(results_data, "health_cube")
  if (nrow(cube) == 0) return(cube)

  if (!is.null(outcomes) && length(outcomes) > 0) {
    cube <- cube[cube$outcome %in% outcomes, , drop = FALSE]
  }
  if (!is.null(age_groups) && length(age_groups) > 0) {
    cube <- cube[cube$age_group %in% age_groups, , drop = FALSE]
  }
  if (!is.null(gender) && length(gender) > 0) {
    cube <- cube[cube$gender %in% gender, , drop = FALSE]
  }
  available_modes <- unique(as.character(cube$mode))
  requested_modes <- .results_normalize_health_modes(modes)
  show_each_mode <- identical(group_by, "mode") &&
    (is.null(modes) || length(modes) == 0 || "all_modes" %in% requested_modes)
  if (show_each_mode) {
    selected_modes <- setdiff(available_modes, "all_modes")
    if (length(selected_modes) == 0 && "all_modes" %in% available_modes) {
      selected_modes <- "all_modes"
    }
  } else if (is.null(modes) || length(modes) == 0) {
    selected_modes <- if ("all_modes" %in% available_modes) "all_modes" else available_modes
  } else {
    selected_modes <- intersect(requested_modes, available_modes)
  }
  cube <- cube[cube$mode %in% selected_modes, , drop = FALSE]
  if (nrow(cube) == 0) return(cube)

  keep_mode_groups <- identical(group_by, "mode") || length(selected_modes) == 1L
  group_cols <- c("outcome", "outcome_label", "outcome_type")
  if (keep_mode_groups) group_cols <- c(group_cols, "mode")
  if (identical(aggregation, "timeline")) group_cols <- c(group_cols, "cycle")
  if (group_by %in% c("age_group", "gender")) group_cols <- c(group_cols, group_by)

  out <- stats::aggregate(
    cube[, c("ref_value", "cf_value", "delta_value"), drop = FALSE],
    by = cube[, group_cols, drop = FALSE],
    FUN = sum,
    na.rm = TRUE
  )
  if (!"mode" %in% names(out)) {
    out$mode <- "selected_modes"
  }
  # A cumulative numerator must retain its cohort denominator, not shrink it
  # when older people no longer have source rows in later model cycles.
  population_groups <- if (identical(aggregation, "timeline") &&
                           identical(timeline_type, "cumulative")) {
    setdiff(group_cols, "cycle")
  } else group_cols
  out$population <- .results_cube_population(cube, population_groups, out)
  attributed <- out$mode != "all_modes"
  out$ref_value[attributed] <- NA_real_
  out$cf_value[attributed] <- NA_real_

  if (identical(aggregation, "timeline") && identical(timeline_type, "cumulative")) {
    series_cols <- setdiff(group_cols, "cycle")
    series_key <- do.call(paste, c(lapply(out[, series_cols, drop = FALSE], as.character), sep = "\r"))
    ordering <- order(series_key, out$cycle)
    out <- out[ordering, , drop = FALSE]
    series_key <- series_key[ordering]
    for (column in c("ref_value", "cf_value", "delta_value")) {
      out[[column]] <- stats::ave(out[[column]], series_key, FUN = cumsum)
    }
  }

  out$percent_change <- 100 * .results_divide_or_na(out$delta_value, out$ref_value)
  benefit_sign <- .results_benefit_sign(out$outcome_type)
  out$prevented_value <- benefit_sign * out$delta_value
  out$percent_reduction <- benefit_sign * out$percent_change
  out$prevented_per_100000 <- 100000 * .results_divide_or_na(out$prevented_value, out$population)

  if ("age_group" %in% names(out)) {
    age_levels <- .results_plot_age_group_levels(results_data)
    age_labels <- stats::setNames(age_levels$label, age_levels$id)
    out$group_label <- unname(age_labels[out$age_group])
  } else if ("gender" %in% names(out)) {
    out$group_label <- ifelse(out$gender == "female", "Female", "Male")
  } else if (identical(group_by, "mode")) {
    out$group_label <- .results_health_mode_label(out$mode)
  } else {
    out$group_label <- out$outcome_label
  }

  out
}


# Core 1: Health Impact By Outcome ------------------------------------------

results_plot_health_overview <- function(
    results_data,
    value = NULL,
    outcomes = NULL,
    age_groups = NULL,
    gender = NULL,
    impact_type = c("attributable", "cf_vs_ref"),
    metric = c("percent_reduction", "prevented", "prevented_per_100000"),
    title = NULL,
    subtitle = NULL,
    caption = NULL,
    x_label = NULL,
    y_label = NULL,
    modes = NULL
) {
  .require_ggplot2()
  impact_type <- match.arg(.results_plot_impact_type(impact_type), c("attributable", "cf_vs_ref"))
  metric <- match.arg(metric)

  # Preserve the original development API while using benefit-oriented defaults.
  if (!is.null(value)) {
    if (identical(value, "percent_change")) metric <- "percent_reduction"
    if (identical(value, "delta")) metric <- "prevented"
  }

  plot_data <- results_filter_health_data(
    results_data, outcomes, age_groups, gender,
    aggregation = "total", group_by = "outcome", modes = modes
  )
  if (nrow(plot_data) == 0) return(.results_empty_plot("No health overview data available"))
  if (identical(impact_type, "cf_vs_ref") && any(plot_data$mode != "all_modes")) {
    return(.results_empty_plot("Reference versus counterfactual burden is available for all modes only"))
  }
  if (any(plot_data$mode != "all_modes") && identical(metric, "percent_reduction")) {
    metric <- "prevented"
  }

  labels <- .results_health_plot_labels(
    results_data = results_data,
    plot_data = plot_data,
    plot = "overview",
    impact_type = impact_type,
    metric = metric,
    title = title,
    subtitle = subtitle,
    caption = caption,
    x_label = x_label,
    y_label = y_label
  )

  if (identical(impact_type, "cf_vs_ref")) {
    scenario_data <- rbind(
      transform(plot_data, scenario = "Reference", value = ref_value),
      transform(plot_data, scenario = "Counterfactual", value = cf_value)
    )
    scenario_data$scenario <- factor(scenario_data$scenario, levels = c("Reference", "Counterfactual"))
    scenario_data$outcome_label <- stats::reorder(scenario_data$outcome_label, scenario_data$value)
    scenario_data$tooltip_text <- .results_health_tooltip(
      scenario_data,
      value = scenario_data$value,
      metric = "modelled",
      scenario = scenario_data$scenario,
      period = "Cumulative"
    )

    return(
      ggplot2::ggplot(
        scenario_data,
        ggplot2::aes(x = outcome_label, y = value, fill = scenario, text = tooltip_text)
      ) +
        ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.76), width = 0.68) +
        ggplot2::coord_flip() +
        ggplot2::scale_fill_manual(values = .results_scenario_colors()) +
        ggplot2::labs(
          title = labels$title, subtitle = labels$subtitle, caption = labels$caption,
          x = labels$x, y = labels$y, fill = NULL
        ) +
        .results_plot_theme()
    )
  }

  y_col <- switch(
    metric,
    percent_reduction = "percent_reduction",
    prevented_per_100000 = "prevented_per_100000",
    "prevented_value"
  )
  plot_data$direction <- ifelse(plot_data[[y_col]] >= 0, "Health gain", "Health loss")
  plot_data$mode_label <- .results_health_mode_label(plot_data$mode)
  plot_data$tooltip_text <- .results_health_tooltip(
    plot_data,
    value = plot_data[[y_col]],
    metric = metric,
    group_name = "Active mode",
    group_value = plot_data$mode_label,
    period = "Cumulative"
  )

  if (length(unique(plot_data$mode)) > 1) {
    return(
      ggplot2::ggplot(
        plot_data,
        ggplot2::aes(
          x = stats::reorder(outcome_label, .data[[y_col]]),
          y = .data[[y_col]], fill = mode_label, text = tooltip_text
        )
      ) +
        ggplot2::geom_hline(yintercept = 0, color = "grey65", linewidth = 0.35) +
        ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.76), width = 0.68) +
        ggplot2::coord_flip() +
        ggplot2::scale_fill_manual(values = .results_group_colors(length(unique(plot_data$mode)))) +
        ggplot2::labs(
          title = labels$title, subtitle = labels$subtitle, caption = labels$caption,
          x = labels$x, y = labels$y, fill = "Active mode"
        ) +
        .results_plot_theme()
    )
  }

  ggplot2::ggplot(
    plot_data,
    ggplot2::aes(
      x = stats::reorder(outcome_label, .data[[y_col]]),
      y = .data[[y_col]], fill = direction, text = tooltip_text
    )
  ) +
    ggplot2::geom_hline(yintercept = 0, color = "grey65", linewidth = 0.35) +
    ggplot2::geom_col(width = 0.68) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = c("Health gain" = "#087E6A", "Health loss" = "#C94C4C")) +
    ggplot2::labs(
      title = labels$title, subtitle = labels$subtitle, caption = labels$caption,
      x = labels$x, y = labels$y, fill = NULL
    ) +
    .results_plot_theme(legend_position = "none")
}


# Advanced 1-2: Health Impact By Age Or Gender ------------------------------

results_plot_health_impacts <- function(
    results_data,
    outcomes = NULL,
    age_groups = NULL,
    gender = NULL,
    group_by = c("age_group", "gender", "mode"),
    metric = c("prevented", "percent_reduction", "prevented_per_100000"),
    title = NULL,
    subtitle = NULL,
    caption = NULL,
    x_label = NULL,
    y_label = NULL,
    modes = NULL
) {
  .require_ggplot2()
  group_by <- match.arg(group_by)
  metric <- match.arg(metric)
  plot_data <- results_filter_health_data(
    results_data, outcomes, age_groups, gender,
    aggregation = "total", group_by = group_by, modes = modes
  )
  if (nrow(plot_data) == 0) return(.results_empty_plot("No detailed health-impact data available"))

  if (any(plot_data$mode != "all_modes") && identical(metric, "percent_reduction")) {
    metric <- "prevented"
  }

  y_col <- switch(
    metric,
    percent_reduction = "percent_reduction",
    prevented_per_100000 = "prevented_per_100000",
    "prevented_value"
  )
  labels <- .results_health_plot_labels(
    results_data = results_data,
    plot_data = plot_data,
    plot = group_by,
    impact_type = "attributable",
    metric = metric,
    title = title,
    subtitle = subtitle,
    caption = caption,
    x_label = x_label,
    y_label = y_label
  )

  group_levels <- if (identical(group_by, "age_group")) {
    .results_plot_age_group_levels(results_data)$label
  } else if (identical(group_by, "mode")) {
    .results_plot_mode_levels(plot_data$mode)
  } else {
    c("Male", "Female")
  }
  plot_data$group_label <- factor(plot_data$group_label, levels = group_levels)
  plot_data$outcome_label <- factor(
    plot_data$outcome_label,
    levels = .results_plot_outcome_levels(results_data, plot_data)
  )
  group_name <- switch(group_by, age_group = "Age group", gender = "Gender", mode = "Active mode")
  plot_data$tooltip_text <- .results_health_tooltip(
    plot_data,
    value = plot_data[[y_col]],
    metric = metric,
    group_name = group_name,
    group_value = plot_data$group_label,
    period = "Cumulative"
  )
  p <- ggplot2::ggplot(
    plot_data,
    ggplot2::aes(
      x = group_label, y = .data[[y_col]], fill = group_label,
      text = tooltip_text
    )
  ) +
    ggplot2::facet_wrap(~outcome_label, scales = "free_y") +
    ggplot2::scale_fill_manual(values = .results_group_colors(length(group_levels)))

  p +
    ggplot2::geom_hline(yintercept = 0, color = "grey70", linewidth = 0.3) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::labs(
      title = labels$title, subtitle = labels$subtitle, caption = labels$caption,
      x = labels$x, y = labels$y, fill = NULL
    ) +
    .results_plot_theme(legend_position = "none")
}


# Core 2: Health Impacts Over Time ------------------------------------------

results_plot_health_timeline <- function(
    results_data,
    outcomes = NULL,
    age_groups = NULL,
    gender = NULL,
    impact_type = c("attributable", "cf_vs_ref"),
    metric = c("prevented_per_100000", "prevented", "percent_reduction"),
    timeline_type = c("cumulative", "annual"),
    title = NULL,
    subtitle = NULL,
    caption = NULL,
    x_label = NULL,
    y_label = NULL,
    modes = NULL
) {
  .require_ggplot2()
  impact_type <- match.arg(.results_plot_impact_type(impact_type), c("attributable", "cf_vs_ref"))
  metric <- match.arg(metric)
  timeline_type <- match.arg(timeline_type)
  # Absolute reference and counterfactual burdens exist only for the all-mode
  # series. Mode selections remain meaningful for attributable impacts, but
  # must not suppress the scenario timeline when the UI retains checked modes.
  timeline_modes <- if (identical(impact_type, "cf_vs_ref")) NULL else modes
  plot_data <- results_filter_health_data(
    results_data, outcomes, age_groups, gender,
    aggregation = "timeline", group_by = "outcome",
    timeline_type = timeline_type, modes = timeline_modes
  )
  if (nrow(plot_data) == 0 || !"cycle" %in% names(plot_data)) {
    return(.results_empty_plot("No timeline data available"))
  }
  if (any(plot_data$mode != "all_modes") && identical(metric, "percent_reduction")) {
    metric <- "prevented"
  }

  labels <- .results_health_plot_labels(
    results_data = results_data,
    plot_data = plot_data,
    plot = "timeline",
    impact_type = impact_type,
    metric = metric,
    timeline_type = timeline_type,
    title = title,
    subtitle = subtitle,
    caption = caption,
    x_label = x_label,
    y_label = y_label
  )

  if (identical(impact_type, "cf_vs_ref")) {
    scenario_data <- rbind(
      transform(plot_data, scenario = "Reference", value = ref_value),
      transform(plot_data, scenario = "Counterfactual", value = cf_value)
    )
    scenario_data$scenario <- factor(scenario_data$scenario, levels = c("Reference", "Counterfactual"))
    scenario_data$outcome_label <- factor(
      scenario_data$outcome_label,
      levels = .results_plot_outcome_levels(results_data, scenario_data)
    )
    scenario_data$tooltip_text <- .results_health_tooltip(
      scenario_data,
      value = scenario_data$value,
      metric = "modelled",
      scenario = scenario_data$scenario,
      cycle = scenario_data$cycle,
      period = if (identical(timeline_type, "cumulative")) "Cumulative" else "Annual"
    )
    return(
      ggplot2::ggplot(
        scenario_data,
        ggplot2::aes(
          x = cycle,
          y = value,
          color = scenario,
          group = interaction(outcome_label, scenario, drop = TRUE),
          text = tooltip_text
        )
      ) +
        ggplot2::geom_line(linewidth = 0.85) +
        ggplot2::facet_wrap(~outcome_label, scales = "free_y") +
        ggplot2::scale_color_manual(values = .results_scenario_colors()) +
        ggplot2::labs(
          title = labels$title, subtitle = labels$subtitle, caption = labels$caption,
          x = labels$x, y = labels$y, color = NULL
        ) +
        .results_plot_theme()
    )
  }

  y_col <- switch(
    metric,
    percent_reduction = "percent_reduction",
    prevented_per_100000 = "prevented_per_100000",
    "prevented_value"
  )
  plot_data$series_label <- if (length(unique(plot_data$mode)) > 1) {
    paste(plot_data$outcome_label, .results_health_mode_label(plot_data$mode), sep = " - ")
  } else {
    plot_data$outcome_label
  }
  plot_data$mode_label <- .results_health_mode_label(plot_data$mode)
  plot_data$outcome_label <- factor(
    plot_data$outcome_label,
    levels = .results_plot_outcome_levels(results_data, plot_data)
  )
  plot_data$tooltip_text <- .results_health_tooltip(
    plot_data,
    value = plot_data[[y_col]],
    metric = metric,
    group_name = "Active mode",
    group_value = plot_data$mode_label,
    cycle = plot_data$cycle,
    period = if (identical(timeline_type, "cumulative")) "Cumulative" else "Annual"
  )
  ggplot2::ggplot(
    plot_data,
    ggplot2::aes(
      x = cycle,
      y = .data[[y_col]],
      color = series_label,
      group = series_label,
      text = tooltip_text
    )
  ) +
    ggplot2::geom_hline(yintercept = 0, color = "grey75", linewidth = 0.3) +
    ggplot2::geom_line(linewidth = 0.85) +
    ggplot2::labs(
      title = labels$title, subtitle = labels$subtitle, caption = labels$caption,
      x = labels$x, y = labels$y, color = NULL
    ) +
    .results_plot_theme()
}


# Advanced 4: Reference Versus Counterfactual Travel By Mode ----------------

results_plot_trip_mode_distribution <- function(
    results_data,
    modes = NULL,
    value = c("proportion", "trips"),
    title = NULL,
    subtitle = NULL,
    caption = NULL,
    x_label = NULL,
    y_label = NULL
) {
  .require_ggplot2()
  value <- match.arg(value)
  plot_data <- .results_get_plot_data(results_data, "trip_mode_distribution")
  if (nrow(plot_data) == 0) return(.results_empty_plot("No trip mode distribution data available"))

  if (!is.null(modes) && length(modes) > 0) {
    mode_ids <- .results_normalize_plot_modes(modes)
    plot_data <- plot_data[plot_data$mode %in% mode_ids, , drop = FALSE]
  }
  if (nrow(plot_data) == 0) return(.results_empty_plot("No selected trip modes available"))

  # Reverse factor levels because coord_flip() displays the first level at the
  # bottom. The visible top-to-bottom order follows the canonical UI catalogue.
  mode_order <- c("Walking", "Cycling", "E-biking", "Public transport", "Driving", "Other")
  plot_data$mode_label <- factor(plot_data$mode_label, levels = rev(mode_order))
  plot_data$scenario <- factor(plot_data$scenario, levels = c("Reference", "Counterfactual"))
  y_col <- if (identical(value, "proportion")) "proportion" else "trips"
  plot_data$value_label <- if (identical(value, "proportion")) {
    paste0(format(round(100 * plot_data$proportion, 1), trim = TRUE), "%")
  } else {
    format(round(plot_data$trips, 1), trim = TRUE)
  }
  plot_data$tooltip_text <- .results_trip_tooltip(plot_data, value)
  labels <- .results_trip_plot_labels(
    value = value,
    title = title,
    subtitle = subtitle,
    caption = caption,
    x_label = x_label,
    y_label = y_label
  )

  p <- ggplot2::ggplot(
    plot_data,
    ggplot2::aes(
      x = mode_label, y = .data[[y_col]], fill = scenario,
      text = tooltip_text
    )
  ) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.76), width = 0.68) +
    ggplot2::geom_text(
      ggplot2::aes(label = value_label),
      position = ggplot2::position_dodge(width = 0.76),
      hjust = -0.12,
      size = 3
    ) +
    ggplot2::coord_flip(clip = "off") +
    ggplot2::scale_fill_manual(values = .results_scenario_colors()) +
    ggplot2::labs(
      title = labels$title, subtitle = labels$subtitle, caption = labels$caption,
      x = labels$x, y = labels$y, fill = NULL
    ) +
    .results_plot_theme()

  if (identical(value, "proportion")) {
    p <- p + ggplot2::scale_y_continuous(
      labels = function(x) paste0(round(100 * x), "%"),
      expand = ggplot2::expansion(mult = c(0, 0.14))
    )
  } else {
    p <- p + ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(0, 0.14))
    )
  }
  p
}


# Shared Plot Helpers --------------------------------------------------------

.results_health_tooltip <- function(data,
                                    value,
                                    metric,
                                    group_name = NULL,
                                    group_value = NULL,
                                    scenario = NULL,
                                    cycle = NULL,
                                    period = NULL) {
  n <- nrow(data)
  if (n == 0) return(character(0))

  outcome_type <- if ("outcome_type" %in% names(data)) data$outcome_type else rep(NA_character_, n)
  value_name <- .results_health_tooltip_value_name(outcome_type, metric, period)
  value_text <- .results_tooltip_number(value, percent = identical(metric, "percent_reduction"))
  tooltip <- paste0("<b>", as.character(data$outcome_label), "</b>")

  if (!is.null(group_name) && !is.null(group_value)) {
    tooltip <- paste0(tooltip, "<br>", group_name, ": ", as.character(group_value))
  }
  if (!is.null(scenario)) {
    tooltip <- paste0(tooltip, "<br>Scenario: ", as.character(scenario))
  }
  if (!is.null(cycle)) {
    tooltip <- paste0(tooltip, "<br>Model year: ", as.character(cycle))
  }

  paste0(tooltip, "<br>", value_name, ": ", value_text)
}

.results_health_tooltip_value_name <- function(outcome_type, metric, period) {
  outcome_type <- as.character(outcome_type)
  outcome_type[is.na(outcome_type) | !nzchar(outcome_type)] <- "health"
  outcome <- ifelse(
    outcome_type == "mortality",
    "deaths",
    ifelse(
      outcome_type == "disease", "disease cases",
      ifelse(outcome_type == "health_years", "HALYs", "health outcomes")
    )
  )
  prefix <- if (is.null(period) || !nzchar(period)) "" else paste0(period, " ")

  switch(
    metric,
    modelled = paste0(prefix, "modelled ", outcome),
    percent_reduction = ifelse(
      outcome_type == "health_years", "Increase from reference", "Reduction from reference"
    ),
    prevented_per_100000 = paste0(
      prefix, ifelse(outcome_type == "health_years", "gained ", "prevented "),
      outcome, " per 100,000"
    ),
    paste0(
      prefix, ifelse(outcome_type == "health_years", "gained ", "prevented "), outcome
    )
  )
}

.results_trip_tooltip <- function(data, value) {
  value_name <- if (identical(value, "proportion")) {
    "Share of trip records"
  } else {
    "Trip records per reference week"
  }
  value_text <- if (identical(value, "proportion")) {
    .results_tooltip_number(100 * data$proportion, percent = TRUE)
  } else {
    .results_tooltip_number(data$trips)
  }

  paste0(
    "<b>", as.character(data$mode_label), "</b>",
    "<br>Scenario: ", as.character(data$scenario),
    "<br>", value_name, ": ", value_text
  )
}

.results_tooltip_number <- function(value, percent = FALSE) {
  value <- suppressWarnings(as.numeric(value))
  formatted <- vapply(value, function(x) {
    if (!is.finite(x)) return("Not available")
    if (x == 0) return("0")

    rounded <- signif(x, digits = 3)
    format(
      rounded,
      scientific = abs(rounded) >= 1e7 || abs(rounded) < 1e-4,
      big.mark = ",",
      trim = TRUE
    )
  }, character(1))

  if (isTRUE(percent)) paste0(formatted, "%") else formatted
}

.results_health_plot_labels <- function(results_data,
                                        plot_data,
                                        plot,
                                        impact_type,
                                        metric,
                                        timeline_type = "total",
                                        title,
                                        subtitle,
                                        caption,
                                        x_label,
                                        y_label) {
  unit <- .results_health_outcome_unit(plot_data)
  health_years_only <- all(as.character(plot_data$outcome_type) == "health_years")
  mixed_years <- any(as.character(plot_data$outcome_type) == "health_years") && !health_years_only
  cycle_span <- .results_cycle_span(results_data)
  is_timeline <- identical(plot, "timeline")
  is_cumulative <- is_timeline && identical(timeline_type, "cumulative")

  default_title <- switch(
    plot,
    overview = "Health impact by outcome",
    timeline = "Health impacts over time",
    age_group = "Health impact by age group",
    gender = "Health impact by gender",
    mode = "Health impact by active mode"
  )

  if (identical(impact_type, "cf_vs_ref")) {
    default_y <- if (is_timeline && !is_cumulative) {
      paste0("Modelled ", unit, " per model year")
    } else {
      paste0("Cumulative modelled ", unit)
    }
    default_subtitle <- if (is_timeline) {
      paste0("Reference and counterfactual values across ", cycle_span)
    } else {
      paste0("Reference and counterfactual totals across ", cycle_span)
    }
    default_caption <- paste(
      "Reference = without scheme; counterfactual = with scheme.",
      "Values are health-model outputs and should not be summed across unlike outcome types."
    )
  } else {
    default_y <- if (identical(metric, "percent_reduction")) {
      if (mixed_years) "Health improvement from reference (%)" else if (health_years_only) "Increase from reference (%)" else "Reduction from reference (%)"
    } else if (mixed_years) {
      paste0(if (is_timeline && !is_cumulative) "Annual" else "Cumulative",
        " health benefit (outcome-specific units)",
        if (identical(metric, "prevented_per_100000")) " per 100,000 residents" else "")
    } else if (identical(metric, "prevented_per_100000")) {
      paste0(
        if (is_cumulative || !is_timeline) "Cumulative " else "",
        if (health_years_only) "gained " else "prevented ", unit,
        " per 100,000 residents"
      )
    } else if (is_timeline && !is_cumulative) {
      paste0(if (health_years_only) "Gained " else "Prevented ", unit, " per model year")
    } else {
      paste0("Cumulative ", if (health_years_only) "gained " else "prevented ", unit)
    }
    default_subtitle <- if (is_timeline) {
      paste0(if (is_cumulative) "Cumulative" else "Annual", " scheme impact across ", cycle_span)
    } else {
      paste0("Cumulative scheme impact across ", cycle_span)
    }
    default_caption <- if (identical(metric, "percent_reduction")) {
      paste(
        if (mixed_years) {
          "Improvement (%) = 100 x (reference - counterfactual) / reference for deaths/cases; 100 x (counterfactual - reference) / reference for HALYs."
        } else if (health_years_only) {
          "Increase (%) = 100 x (counterfactual - reference) / reference."
        } else {
          "Reduction (%) = 100 x (reference - counterfactual) / reference."
        },
        "Positive values indicate a health gain; negative values indicate a health loss."
      )
    } else {
      paste(
        if (health_years_only) {
          "HALYs gained = counterfactual - reference."
        } else {
          "Prevented outcomes = reference - counterfactual."
        },
        "Positive values indicate a health gain; negative values indicate a health loss."
      )
    }
  }

  list(
    title = .results_resolve_plot_label(title, default_title),
    subtitle = .results_resolve_plot_label(subtitle, default_subtitle),
    caption = .results_resolve_plot_label(caption, default_caption),
    x = .results_resolve_plot_label(x_label, switch(
      plot,
      overview = "Health outcome",
      timeline = "Model year (cycle 1 = first modelled year)",
      age_group = "Age group",
      gender = "Gender",
      mode = "Active mode"
    )),
    y = .results_resolve_plot_label(y_label, default_y)
  )
}

.results_cube_population <- function(cube, group_cols, grouped_result) {
  strata_cols <- unique(c(group_cols, "age_group", "gender"))
  strata <- stats::aggregate(
    cube$population,
    by = cube[, strata_cols, drop = FALSE],
    FUN = max,
    na.rm = TRUE
  )
  names(strata)[ncol(strata)] <- "population"
  population <- stats::aggregate(
    strata$population,
    by = strata[, group_cols, drop = FALSE],
    FUN = sum,
    na.rm = TRUE
  )
  names(population)[ncol(population)] <- "population"
  group_key <- function(x) do.call(paste, c(lapply(x[, group_cols, drop = FALSE], as.character), sep = "\r"))
  population$population[match(group_key(grouped_result), group_key(population))]
}

.results_trip_plot_labels <- function(value,
                                      title,
                                      subtitle,
                                      caption,
                                      x_label,
                                      y_label) {
  is_share <- identical(value, "proportion")
  list(
    title = .results_resolve_plot_label(title, "Reference and counterfactual travel by mode"),
    subtitle = .results_resolve_plot_label(
      subtitle,
      if (is_share) "Share of trip records within each scenario" else "Weekly trip-record totals"
    ),
    caption = .results_resolve_plot_label(
      caption,
      paste(
        "One synthetic trip row is treated as one trip record; survey weights do not alter these totals.",
        "Reference = without scheme; counterfactual = with scheme."
      )
    ),
    x = .results_resolve_plot_label(x_label, "Travel mode"),
    y = .results_resolve_plot_label(
      y_label,
      if (is_share) "Share of trip records (%)" else "Trip records per reference week"
    )
  )
}

.results_health_outcome_unit <- function(plot_data) {
  outcome_types <- unique(as.character(plot_data$outcome_type))
  outcome_types <- outcome_types[!is.na(outcome_types) & nzchar(outcome_types)]
  if (length(outcome_types) == 1 && identical(outcome_types, "mortality")) return("deaths")
  if (length(outcome_types) == 1 && identical(outcome_types, "disease")) return("disease cases")
  if (length(outcome_types) == 1 && identical(outcome_types, "health_years")) return("HALYs")
  "health outcomes"
}

.results_cycle_span <- function(results_data) {
  cube <- .results_get_plot_data(results_data, "health_cube")
  if (nrow(cube) == 0 || !"cycle" %in% names(cube)) return("the modelled assessment period")
  cycles <- suppressWarnings(as.numeric(cube$cycle))
  cycles <- cycles[is.finite(cycles)]
  if (length(cycles) == 0) return("the modelled assessment period")
  paste0("model cycles ", min(cycles), "-", max(cycles))
}

.results_resolve_plot_label <- function(value, default) {
  if (is.null(value)) return(default)
  if (length(value) == 1 && is.na(value)) return(NULL)
  as.character(value)[1]
}

.results_plot_impact_type <- function(x) {
  if (length(x) > 1) x <- x[1]
  if (identical(x, "cf_vs_bl")) "cf_vs_ref" else x
}

.results_normalize_plot_modes <- function(modes) {
  map <- c(
    walking = "walking", walk = "walking", cycling = "cycling", bike = "cycling",
    ebiking = "ebiking", ebike = "ebiking", pt = "pt", public_transport = "pt",
    car = "driving", driving = "driving", other = "other"
  )
  unique(unname(map[as.character(modes)]))
}

.results_health_mode_label <- function(mode) {
  labels <- c(
    all_modes = "All modes", selected_modes = "Selected modes",
    walking = "Walking", cycling = "Cycling", ebiking = "E-biking",
    pt = "Public transport",
    other_activity = "Other activity", unattributed = "Unattributed"
  )
  value <- unname(labels[as.character(mode)])
  value[is.na(value)] <- as.character(mode)[is.na(value)]
  value
}

.results_scenario_colors <- function() {
  c(Reference = "#C4487A", Counterfactual = "#087E6A")
}

.results_group_colors <- function(n) {
  palette <- c("#326789", "#087E6A", "#D18A24", "#8B5E83", "#5E6B73")
  rep(palette, length.out = n)
}

.results_plot_theme <- function(legend_position = "top") {
  ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      legend.position = legend_position,
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold", color = "#263238", size = 13),
      plot.subtitle = ggplot2::element_text(color = "#52616B", size = 10),
      plot.caption = ggplot2::element_text(color = "#65737E", hjust = 0, size = 8.5),
      axis.title = ggplot2::element_text(color = "#36454F"),
      axis.text = ggplot2::element_text(color = "#36454F"),
      strip.text = ggplot2::element_text(face = "bold", color = "#263238")
    )
}

.results_plot_age_group_levels <- function(results_data) {
  levels <- .results_get_plot_data(results_data, "age_group_levels")
  if (!all(c("id", "label") %in% names(levels)) || nrow(levels) == 0) {
    return(.results_age_group_levels())
  }
  levels
}

.results_plot_outcome_levels <- function(results_data, plot_data) {
  levels <- .results_get_plot_data(results_data, "outcome_levels")
  available <- unique(as.character(plot_data$outcome_label))
  if (!all(c("id", "label") %in% names(levels)) || nrow(levels) == 0) {
    return(available)
  }
  configured <- as.character(levels$label)
  c(configured[configured %in% available], setdiff(available, configured))
}

.results_plot_mode_levels <- function(modes) {
  canonical <- c(
    "walking", "cycling", "ebiking", "pt", "other_activity", "unattributed",
    "selected_modes", "all_modes"
  )
  modes <- unique(as.character(modes))
  ordered <- c(canonical[canonical %in% modes], setdiff(modes, canonical))
  .results_health_mode_label(ordered)
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
