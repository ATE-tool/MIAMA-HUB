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
# Advanced 3 -- Travel by mode
#   Reference and counterfactual weighted trip totals or shares by travel mode.
#   Health impacts cannot currently be attributed to individual travel modes.
#
# Label and unit contract:
# - Titles, subtitles, captions, and axis labels have semantic defaults derived
#   from the selected metric and returned data. Every plot exposes explicit
#   `title`, `subtitle`, `caption`, `x_label`, and `y_label` overrides for UI use.
# - Pass `NULL` to use the semantic default or `NA_character_` to suppress a
#   label. Changing a label does not transform the underlying numeric values.
# - `prevented_value = reference - counterfactual`; positive values are a health
#   gain. `percent_reduction = 100 * (reference - counterfactual) / reference`.
# - `prevented_per_100000` uses the represented population attached to each
#   result group. Cycle 0 is excluded before plot data are constructed.
# - Reference/counterfactual health values are modelled deaths, disease cases,
#   or the generic "health outcomes" when both types occur in one plot.
# - Trip shares are proportions (displayed as percentages); trip counts are sums
#   of `weight_tripXhh` when available and therefore are labelled weighted trips.
#
# UI contract:
# - `results_filter_health_data()` filters and aggregates the compact health cube
#   without rerunning counterfactual or health-model calculations.
# - Plot functions consume only `results_data$plot_data`, so MIAMA-UI can use the
#   same functions or reproduce them from the returned compact data frames.
# - Health impacts currently have `mode = "all_modes"`; mode-specific plotting
#   is intentionally limited to the trip-distribution chart.


# Filterable Health Plot Data ------------------------------------------------

results_filter_health_data <- function(
    results_data,
    outcomes = NULL,
    age_groups = NULL,
    gender = NULL,
    aggregation = c("total", "timeline"),
    group_by = c("outcome", "age_group", "gender", "none"),
    timeline_type = c("annual", "cumulative")
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
  if (nrow(cube) == 0) return(cube)

  group_cols <- c("outcome", "outcome_label", "outcome_type", "mode")
  if (identical(aggregation, "timeline")) group_cols <- c(group_cols, "cycle")
  if (group_by %in% c("age_group", "gender")) group_cols <- c(group_cols, group_by)

  out <- stats::aggregate(
    cube[, c("ref_value", "cf_value", "delta_value"), drop = FALSE],
    by = cube[, group_cols, drop = FALSE],
    FUN = sum,
    na.rm = TRUE
  )
  out$population <- .results_cube_population(cube, group_cols, out)

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
  out$prevented_value <- -out$delta_value
  out$percent_reduction <- -out$percent_change
  out$prevented_per_100000 <- 100000 * .results_divide_or_na(out$prevented_value, out$population)

  if ("age_group" %in% names(out)) {
    age_levels <- .results_plot_age_group_levels(results_data)
    age_labels <- stats::setNames(age_levels$label, age_levels$id)
    out$group_label <- unname(age_labels[out$age_group])
  } else if ("gender" %in% names(out)) {
    out$group_label <- ifelse(out$gender == "female", "Female", "Male")
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
    y_label = NULL
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
    aggregation = "total", group_by = "outcome"
  )
  if (nrow(plot_data) == 0) return(.results_empty_plot("No health overview data available"))

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

    return(
      ggplot2::ggplot(scenario_data, ggplot2::aes(x = outcome_label, y = value, fill = scenario)) +
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

  ggplot2::ggplot(
    plot_data,
    ggplot2::aes(x = stats::reorder(outcome_label, .data[[y_col]]), y = .data[[y_col]], fill = direction)
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
    group_by = c("age_group", "gender"),
    metric = c("prevented", "percent_reduction", "prevented_per_100000"),
    title = NULL,
    subtitle = NULL,
    caption = NULL,
    x_label = NULL,
    y_label = NULL
) {
  .require_ggplot2()
  group_by <- match.arg(group_by)
  metric <- match.arg(metric)
  plot_data <- results_filter_health_data(
    results_data, outcomes, age_groups, gender,
    aggregation = "total", group_by = group_by
  )
  if (nrow(plot_data) == 0) return(.results_empty_plot("No detailed health-impact data available"))

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
  } else {
    c("Male", "Female")
  }
  plot_data$group_label <- factor(plot_data$group_label, levels = group_levels)
  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = group_label, y = .data[[y_col]], fill = group_label)) +
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
    y_label = NULL
) {
  .require_ggplot2()
  impact_type <- match.arg(.results_plot_impact_type(impact_type), c("attributable", "cf_vs_ref"))
  metric <- match.arg(metric)
  timeline_type <- match.arg(timeline_type)
  plot_data <- results_filter_health_data(
    results_data, outcomes, age_groups, gender,
    aggregation = "timeline", group_by = "outcome", timeline_type = timeline_type
  )
  if (nrow(plot_data) == 0 || !"cycle" %in% names(plot_data)) {
    return(.results_empty_plot("No timeline data available"))
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
    return(
      ggplot2::ggplot(scenario_data, ggplot2::aes(x = cycle, y = value, color = scenario)) +
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
  ggplot2::ggplot(plot_data, ggplot2::aes(x = cycle, y = .data[[y_col]], color = outcome_label)) +
    ggplot2::geom_hline(yintercept = 0, color = "grey75", linewidth = 0.3) +
    ggplot2::geom_line(linewidth = 0.85) +
    ggplot2::labs(
      title = labels$title, subtitle = labels$subtitle, caption = labels$caption,
      x = labels$x, y = labels$y, color = NULL
    ) +
    .results_plot_theme()
}


# Advanced 3: Reference Versus Counterfactual Travel By Mode ----------------

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

  mode_order <- c("Walking", "Cycling", "Public transport", "Driving", "Other")
  plot_data$mode_label <- factor(plot_data$mode_label, levels = mode_order)
  plot_data$scenario <- factor(plot_data$scenario, levels = c("Reference", "Counterfactual"))
  y_col <- if (identical(value, "proportion")) "proportion" else "trips"
  labels <- .results_trip_plot_labels(
    value = value,
    title = title,
    subtitle = subtitle,
    caption = caption,
    x_label = x_label,
    y_label = y_label
  )

  p <- ggplot2::ggplot(plot_data, ggplot2::aes(x = mode_label, y = .data[[y_col]], fill = scenario)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.76), width = 0.68) +
    ggplot2::coord_flip() +
    ggplot2::scale_fill_manual(values = .results_scenario_colors()) +
    ggplot2::labs(
      title = labels$title, subtitle = labels$subtitle, caption = labels$caption,
      x = labels$x, y = labels$y, fill = NULL
    ) +
    .results_plot_theme()

  if (identical(value, "proportion")) {
    p <- p + ggplot2::scale_y_continuous(labels = function(x) paste0(round(100 * x), "%"))
  }
  p
}


# Shared Plot Helpers --------------------------------------------------------

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
  cycle_span <- .results_cycle_span(results_data)
  is_timeline <- identical(plot, "timeline")
  is_cumulative <- is_timeline && identical(timeline_type, "cumulative")

  default_title <- switch(
    plot,
    overview = "Health impact by outcome",
    timeline = "Health impacts over time",
    age_group = "Health impact by age group",
    gender = "Health impact by gender"
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
      "Reduction from reference (%)"
    } else if (identical(metric, "prevented_per_100000")) {
      paste0(if (is_cumulative || !is_timeline) "Cumulative prevented " else "Prevented ", unit, " per 100,000 residents")
    } else if (is_timeline && !is_cumulative) {
      paste0("Prevented ", unit, " per model year")
    } else {
      paste0("Cumulative prevented ", unit)
    }
    default_subtitle <- if (is_timeline) {
      paste0(if (is_cumulative) "Cumulative" else "Annual", " scheme impact across ", cycle_span)
    } else {
      paste0("Cumulative scheme impact across ", cycle_span)
    }
    default_caption <- if (identical(metric, "percent_reduction")) {
      paste(
        "Reduction (%) = 100 x (reference - counterfactual) / reference.",
        "Positive values indicate fewer outcomes with the scheme; negative values indicate an increase."
      )
    } else {
      paste(
        "Prevented outcomes = reference - counterfactual.",
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
      gender = "Gender"
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
      if (is_share) "Share of weighted trips within each scenario" else "Weighted weekly trip totals"
    ),
    caption = .results_resolve_plot_label(
      caption,
      paste(
        "Trip totals use weight_tripXhh where available; induced trips currently receive weight 1.",
        "Reference = without scheme; counterfactual = with scheme."
      )
    ),
    x = .results_resolve_plot_label(x_label, "Travel mode"),
    y = .results_resolve_plot_label(
      y_label,
      if (is_share) "Share of weighted trips (%)" else "Weighted trips per reference week"
    )
  )
}

.results_health_outcome_unit <- function(plot_data) {
  outcome_types <- unique(as.character(plot_data$outcome_type))
  outcome_types <- outcome_types[!is.na(outcome_types) & nzchar(outcome_types)]
  if (length(outcome_types) == 1 && identical(outcome_types, "mortality")) return("deaths")
  if (length(outcome_types) == 1 && identical(outcome_types, "disease")) return("disease cases")
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
    ebiking = "cycling", ebike = "cycling", pt = "pt", public_transport = "pt",
    car = "driving", driving = "driving", other = "other"
  )
  unique(unname(map[as.character(modes)]))
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
