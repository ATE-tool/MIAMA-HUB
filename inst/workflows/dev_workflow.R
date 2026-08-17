# MIAMA-HUB Dev Workflow
# Orchestrates the full impact calculation pipeline for development and testing.
# Run interactively, section by section. Step 4 defines a reproducible 10%
# relative active-travel growth scenario and prints every resulting CF target.
#
# Prerequisites: Set env vars in your project .Renviron (usethis::edit_r_environ("project")):
#   MIAMA_PROJECT_ROOT=/path/to/MIAMA-HUB
#   MIAMA_HM_ROOT=/path/to/MIAMA-HM
#   MIAMA_DATA_ROOT=/path/to/external/miama-data
# Then restart R so the vars are picked up before loading the package.
# `MIAMA_HM_ROOT` is optional in the common dev layout where `MIAMA-HUB` and
# `MIAMA-HM` are sibling repos; HUB will discover `../MIAMA-HM` automatically.
# `MIAMA_DATA_ROOT` is optional for packaged sample runs and required for full
# synthpop runs.

# 0. Setup ----
# -----------------------------------------------------------------------------#

## 0.1 Load package ----
find_miama_hub_root <- function(start = getwd()) {
  env_root <- Sys.getenv("MIAMA_PROJECT_ROOT", unset = "")
  candidates <- unique(c(
    env_root[nzchar(env_root)],
    start,
    file.path(start, "MIAMA-HUB"),
    file.path(dirname(start), "MIAMA-HUB")
  ))

  for (candidate in candidates) {
    desc <- file.path(candidate, "DESCRIPTION")
    if (file.exists(desc) && identical(unname(read.dcf(desc)[1, "Package"]), "MIAMAHUB")) {
      return(normalizePath(candidate, winslash = "/", mustWork = FALSE))
    }
  }

  stop(
    "Could not find MIAMA-HUB package root. Set MIAMA_PROJECT_ROOT to the MIAMA-HUB folder.",
    call. = FALSE
  )
}

hub_root <- find_miama_hub_root()
devtools::load_all(hub_root)

## 0.2 Configure run ----
# Config is for runtime/data-source concerns, not appraisal logic.
# Appraisal-driven source selection (e.g. total vs timeline) comes from request.
cfg <- miama_default_config()
cfg$workflow$dataset_size <- "full"   # "sample" or "full"
cfg$cache$enabled         <- TRUE
cfg$cache$refresh         <- FALSE

# Inspect only a small row subset. `dplyr::glimpse()` dispatches through
# `as.data.frame.data.table()`, which can copy a complete large table.
glimpse_head <- function(x, n = 10L) {
  dplyr::glimpse(as.data.frame(utils::head(x, n)))
}

## 0.3 Optional one-time conversion of SP DTA -> parquet ----
# Recommended so Arrow can prefilter by geography before collecting to memory.
# convert_synthpop_to_parquet(cfg, overwrite = FALSE)

## 0.4 Build mock appraisal inputs ----
# Temporary development helper until MIAMA-UI calls MIAMA-HUB directly.
appraisal_inputs <- build_mock_appraisal_inputs(
  overrides = list(
    geo_level = list(input_value = "lad"),
    geo_id = list(input_value = "E08000035"), # Leeds
    modes = list(input_value = c("walking", "cycling")),
    res_aggregation = list(input_value = "timeline")
  )
)

request <- receive_appraisal_inputs(appraisal_inputs)

# Developer-friendly flat values
str(request$appraisal_input_values)
str(request$reference_request)
str(request$results_request)
str(request$counterfactual_request)


# 1. Load synthpop reference-default data ----
# -----------------------------------------------------------------------------#
# Mirrors `Hub$build_reference_profile_defaults()`: load geography-filtered SP
# attributes and trips without HM outcomes. These rows provide UI defaults.

reference_default_data <- load_reference_default_sources(
  cfg,
  reference_request = request$reference_request
)

## 1.1 Inspect source report ----
str(reference_default_data$source_report)

# Quick intake checks
message("SP attributes rows:  ", nrow(reference_default_data$ind))
message("SP trips rows:       ", nrow(reference_default_data$trips))


# 2. Inspect loaded data ----
# -----------------------------------------------------------------------------#

## 2.1 SP attributes ----
glimpse_head(reference_default_data$ind)

## 2.2 SP trips ----
glimpse_head(reference_default_data$trips)

## 2.3 Check expected columns are present ----
# Warn if constants diverge from actual data — adjust constants.R if needed.

sp_attr_missing <- setdiff(MIAMA_SP_ATTRIBUTE_COLS, names(reference_default_data$ind))
sp_trip_missing <- setdiff(MIAMA_SP_TRIP_COLS,      names(reference_default_data$trips))

if (length(sp_attr_missing) > 0) {
  warning("SP attributes missing expected columns: ", paste(sp_attr_missing, collapse = ", "))
} else {
  message("SP attributes: all expected columns present.")
}

if (length(sp_trip_missing) > 0) {
  warning("SP trips missing expected columns: ", paste(sp_trip_missing, collapse = ", "))
} else {
  message("SP trips: all expected columns present.")
}

## 2.4 Check for unexpected NAs in key ID columns ----
key_id_cols <- c("census_id", "nts_id")
for (col in key_id_cols) {
  if (col %in% names(reference_default_data$ind)) {
    n_na <- sum(is.na(reference_default_data$ind[[col]]))
    if (n_na > 0) warning("NA values in sp_attributes$", col, ": ", n_na)
  }
}


# 3. Extract reference values for the UI profile ----
# -----------------------------------------------------------------------------#
# Geography filtering was pushed into the parquet reads in Step 1. No HM join
# is performed while building reference defaults. This mirrors
# `Hub$build_reference_profile_defaults()` and calculates the reference values
# used by the basic and advanced UI fields.

reference_ui_values <- extract_reference_ui_values(
  reference_default_data,
  request$reference_request,
  request$appraisal_input_values,
  cfg = cfg
)

## 3.1 Inspect UI updates and extraction report ----
str(reference_ui_values$ui_updates)
str(reference_ui_values$extraction_report)

## 3.2 Inspect spread bar defaults for selected development modes ----
# These compact 10-row data frames are the reference bar values used by Tab 3/4
# spread plots. They are mode-specific where the profile has mode-specific
# fields, e.g. `pop_spread_bars_ref_walk` and `trips_spread_bars_ref_bike`.

spread_bar_report <- reference_ui_values$extraction_report$spread_bar_values
spread_bar_fields_to_print <- c(
  "pop_spread_bars_ref_walk",
  "pop_spread_bars_ref_bike",
  "pa_spread_bars_ref_walk",
  "pa_spread_bars_ref_bike",
  "trips_spread_bars_ref_walk",
  "trips_spread_bars_ref_bike"
)

spread_bar_report[
  spread_bar_report$field %in% spread_bar_fields_to_print,
  c("field", "topic", "category_order", "category", "variable", "percent"),
  drop = FALSE
] |>
  utils::head(120) |>
  as.data.frame() |>
  print(row.names = FALSE)

# 4. Define a realistic counterfactual scenario ----
# -----------------------------------------------------------------------------#
# HUB consumes absolute CF targets. This development helper translates one
# readable scenario definition into those UI-style fields.
#
# Here, "10% active-travel growth" means a 10% relative increase, separately
# for walking and cycling, in both:
#   1. people using the mode during the synthetic reference week; and
#   2. physical active-mode trip rows during that week.
# It does not mean a 10 percentage-point mode-share increase. Trip targets use
# physical rows because the current CF trip handler changes rows while retaining
# existing `weight_tripXhh` values. Weighted trip-target semantics remain a
# production decision.
#
# User changes are applied before trip-count changes. The second target is
# absolute, so Step 6 reconciles any trips already shifted for new users to the
# final 10%-growth trip target rather than adding another 10%.

dev_cf_scenario <- list(
  name = "10% relative increase in active travel",
  relative_change = 0.10,
  modes = c("walking", "cycling"),
  change_users = TRUE,
  change_trips = TRUE,
  induced_trip_percent = 10,
  # NA uses HUB's existing/default car-diversion behavior. Set named percentages
  # such as c(walking = 70, cycling = 85) to test explicit diversion assumptions.
  car_diversion_percent = c(walking = NA_real_, cycling = NA_real_),
  # Leave empty to preserve the reference spread bars exactly. To test a slider
  # change, provide exact UI field names, for example:
  # list(pop_spread_age_mean_cf_walk = 45,
  #      trips_spread_util_prop_cf_bike = 0.80)
  spread_overrides = list(),
  seed = 1L
)

relative_integer_target <- function(reference, relative_change, upper = Inf) {
  stopifnot(
    length(reference) == 1L,
    is.finite(reference),
    reference >= 0,
    length(relative_change) == 1L,
    is.finite(relative_change),
    relative_change > -1
  )

  target <- as.integer(round(reference * (1 + relative_change)))
  # Small sample counts can otherwise round a non-zero scenario back to no
  # change. Full-data runs will closely match the requested percentage.
  if (relative_change > 0 && target <= reference && reference < upper) {
    target <- as.integer(reference + 1L)
  }
  if (relative_change < 0 && target >= reference && reference > 0) {
    target <- as.integer(reference - 1L)
  }

  as.integer(max(0, min(target, upper)))
}

active_trip_row_count <- function(trips, mode) {
  spec <- .miama_tab2_mode_specs()[[mode]]
  if (is.null(spec)) {
    stop("Unsupported development scenario mode: ", mode, call. = FALSE)
  }
  if (is.null(trips) || !"nts_tripid" %in% names(trips)) {
    stop("Trip-level data with `nts_tripid` are required.", call. = FALSE)
  }

  active <- spec$trip_filter(trips) & !is.na(trips$nts_tripid)
  sum(active, na.rm = TRUE)
}

build_dev_counterfactual_inputs <- function(values, reference_ui_values, reference_data, scenario) {
  ref_values <- reference_ui_values$ui_updates
  population_n <- nrow(reference_data$ind)
  target_rows <- list()

  for (mode in scenario$modes) {
    spec <- .miama_tab2_mode_specs()[[mode]]
    if (is.null(spec)) {
      stop("Unsupported development scenario mode: ", mode, call. = FALSE)
    }
    suffix <- spec$suffix

    if (isTRUE(scenario$change_users)) {
      ref_users <- ref_values[[paste0("users_count_ref_", suffix)]]
      if (is.null(ref_users) || !is.finite(ref_users)) {
        stop("Missing reference user count for mode: ", mode, call. = FALSE)
      }
      cf_users <- relative_integer_target(ref_users, scenario$relative_change, population_n)
      values[[paste0("users_count_cf_", suffix)]] <- cf_users
      target_rows[[length(target_rows) + 1L]] <- data.frame(
        mode = mode,
        metric = "weekly users",
        reference = ref_users,
        counterfactual = cf_users,
        requested_relative_change = scenario$relative_change,
        realized_relative_change = if (ref_users > 0) cf_users / ref_users - 1 else NA_real_,
        target_basis = "individual rows",
        stringsAsFactors = FALSE
      )
    }

    if (isTRUE(scenario$change_trips)) {
      ref_trips <- active_trip_row_count(reference_data$trips, mode)
      cf_trips <- relative_integer_target(ref_trips, scenario$relative_change)
      values[[paste0("trips_timeframe_", suffix)]] <- "week"
      values[[paste0("trips_denominator_", suffix)]] <- "total"
      values[[paste0("trips_count_cf_", suffix)]] <- cf_trips
      target_rows[[length(target_rows) + 1L]] <- data.frame(
        mode = mode,
        metric = "weekly active-mode trips",
        reference = ref_trips,
        counterfactual = cf_trips,
        requested_relative_change = scenario$relative_change,
        realized_relative_change = if (ref_trips > 0) cf_trips / ref_trips - 1 else NA_real_,
        target_basis = "physical trip rows",
        stringsAsFactors = FALSE
      )
    }

    diversion <- scenario$car_diversion_percent[[mode]]
    if (!is.null(diversion) && length(diversion) == 1L && is.finite(diversion)) {
      values[[paste0("trips_diversion_car_perc_", suffix)]] <- diversion
    }
  }

  if (length(scenario$spread_overrides) > 0) {
    if (is.null(names(scenario$spread_overrides)) || any(!nzchar(names(scenario$spread_overrides)))) {
      stop("`spread_overrides` must be a named list of UI fields.", call. = FALSE)
    }
    values[names(scenario$spread_overrides)] <- scenario$spread_overrides
  }

  list(
    values = derive_counterfactual_spread_values(values, reference_ui_values),
    targets = do.call(rbind, target_rows)
  )
}

check_dev_counterfactual_targets <- function(counterfactual_data, targets) {
  realized <- vapply(seq_len(nrow(targets)), function(i) {
    mode <- targets$mode[i]
    metric <- targets$metric[i]
    spec <- .miama_tab2_mode_specs()[[mode]]

    if (identical(metric, "weekly users")) {
      return(sum(.positive_col(counterfactual_data$ind, spec$ind_duration_col), na.rm = TRUE))
    }
    if (identical(metric, "weekly active-mode trips")) {
      return(active_trip_row_count(counterfactual_data$trips, mode))
    }

    NA_real_
  }, numeric(1))

  data.frame(
    mode = targets$mode,
    metric = targets$metric,
    expected = targets$counterfactual,
    realized = realized,
    achieved = realized == targets$counterfactual,
    stringsAsFactors = FALSE
  )
}

dev_cf_inputs <- build_dev_counterfactual_inputs(
  values = request$appraisal_input_values,
  reference_ui_values = reference_ui_values,
  reference_data = reference_default_data,
  scenario = dev_cf_scenario
)
counterfactual_appraisal_input_values <- dev_cf_inputs$values
dev_cf_targets <- dev_cf_inputs$targets

message("Counterfactual scenario: ", dev_cf_scenario$name)
dev_cf_targets |>
  transform(
    requested_percent = 100 * requested_relative_change,
    realized_percent = 100 * realized_relative_change
  ) |>
  as.data.frame() |>
  print(row.names = FALSE)

counterfactual_constants <- miama_counterfactual_defaults()
counterfactual_constants$induced_trip_percent_default <-
  dev_cf_scenario$induced_trip_percent

## 4.1 Inspect derived counterfactual spread bars ----
# With empty `spread_overrides`, CF bars reproduce reference bars exactly.
# Populate the named overrides in `dev_cf_scenario` to test a distribution shift
# independently of the 10% volume scenario.
cf_spread_fields <- unlist(lapply(dev_cf_scenario$modes, function(mode) {
  suffix <- .miama_mode_suffix(mode)
  paste0(c("pop_spread_bars_cf_", "pa_spread_bars_cf_", "trips_spread_bars_cf_"), suffix)
}))
cf_spread_bar_report <- do.call(rbind, lapply(cf_spread_fields, function(field) {
  bars <- counterfactual_appraisal_input_values[[field]]
  if (!is.data.frame(bars)) {
    return(NULL)
  }
  bars$field <- field
  bars
}))

cf_spread_bar_report[
  ,
  c("field", "topic", "scenario", "category_order", "category", "variable", "percent"),
  drop = FALSE
] |>
  as.data.frame() |>
  print(row.names = FALSE)


# 5. Load health-enriched reference data for build_results ----
# Mirrors the first data stage inside `Hub$build_results()`. Overall HM outcomes
# provide one reference MMET row per person. Cycle/death-share data remain
# deferred until Step 7.

reference_sources <- load_reference_sources(
  cfg,
  reference_request = request$reference_request,
  results_request = request$results_request
)
reference_data_raw <- join_hm_and_synthpop(reference_sources)
reference_data <- filter_reference_data(
  reference_data_raw,
  request$reference_request
)

str(reference_sources$source_report)
str(reference_data_raw$join_report)
message("Health-enriched individuals: ", nrow(reference_data$ind))
message("Health-enriched trips:       ", nrow(reference_data$trips))
glimpse_head(reference_data$ind)
glimpse_head(reference_data$trips)


# --- Full counterfactual and results pipeline ----
# -----------------------------------------------------------------------------#

# 6. Create counterfactual data ----
# -----------------------------------------------------------------------------#
# Starts from a 1:1 copy of reference data, applies the absolute CF targets from
# Step 4, and records requested and realized changes in `counterfactual_report`.

counterfactual_data <- init_counterfactual_data(reference_data)
counterfactual_data <- apply_counterfactual_ui_values(
  counterfactual_data,
  counterfactual_appraisal_input_values,
  reference_data = reference_data,
  constants = counterfactual_constants,
  seed = dev_cf_scenario$seed
)

dev_cf_target_check <- check_dev_counterfactual_targets(
  counterfactual_data,
  dev_cf_targets
)
message("Counterfactual target check:")
print(dev_cf_target_check, row.names = FALSE)
if (any(!dev_cf_target_check$achieved)) {
  warning("One or more counterfactual targets were not achieved; inspect `counterfactual_report`.")
}

# The high-level `Hub$build_results()` method releases these same redundant
# row-level intermediates before loading the full cycle table. Keep only the
# filtered reference and counterfactual objects needed below.
rm(reference_sources, reference_data_raw, reference_default_data)
invisible(gc(verbose = FALSE))

message(
  "Changed individual MMET rows entering Step 7: ",
  nrow(counterfactual_data$counterfactual_report$comparison$changed_ind_rows)
)

## 6.1 Inspect counterfactual report and changed data ----
str(counterfactual_data$counterfactual_report)
counterfactual_data$counterfactual_report$comparison$ind
counterfactual_data$counterfactual_report$comparison$trips
counterfactual_data$counterfactual_report$comparison$changed_ind_rows
glimpse_head(counterfactual_data$ind)
glimpse_head(counterfactual_data$trips)

# 7. Rejoin health outcomes based on updated physical activity levels (mmets) for counterfactual data ----
# -----------------------------------------------------------------------------#
# Uses the updated MIAMA-HM death-share cycle tables so HALY-compatible outputs
# are available. For `dataset_size = "sample"`, Step 7 prefers the sample
# death-share cycle table when present. The default `scheme_effect_duration =
# "longterm"` applies the individual MMET delta to every model cycle.

counterfactual_data <- apply_counterfactual_health_outcomes(
  counterfactual_data,
  reference_data,
  cfg = cfg,
  scheme_effect_duration = "longterm"
)

message(
  "Counterfactual health outcomes: ",
  nrow(counterfactual_data$health_outcomes),
  " rows, ",
  round(as.numeric(object.size(counterfactual_data$health_outcomes)) / 1024^2, 1),
  " MB"
)

## 7.1 Inspect counterfactual health outcomes ----
str(counterfactual_data$counterfactual_health_report)
glimpse_head(counterfactual_data$health_outcomes)
counterfactual_data$counterfactual_health_report$impact_overview |>
  dplyr::arrange(dplyr::desc(abs(delta_total))) |>
  utils::head(30) |>
  print()


# 8. Prepare results data for Tab 5 presentation ----
# -----------------------------------------------------------------------------#
# Based on UI Tab 5 inputs this step filters and aggregates the health-outcome
# deltas into compact tables for plots, result tiles, and exports. The first
# draft also creates ggplot objects that can be used for development testing.

results_data <- prepare_results_data(
  counterfactual_data = counterfactual_data,
  reference_data = reference_data,
  results_request = request$results_request,
  appraisal_input_values = counterfactual_appraisal_input_values
)

## 8.1 Inspect result summaries and tables ----
str(results_data$headline_metrics)
str(results_data$results_report)
results_data$results_table |>
  dplyr::arrange(dplyr::desc(abs(delta_value))) |>
  utils::head(30) |>
  print()

## 8.2 Core presentation plots ----
# Core 1: cumulative percentage reduction by selected health outcome.
plot_core_health_by_outcome <- results_plot_health_overview(
  results_data,
  outcomes = c("ihd", "stroke", "diabetes", "depression", "alzheimer", "cancers"),
  impact_type = "attributable",
  metric = "percent_reduction"
)

# Core 2: annual prevented health outcomes over the modelled period.
plot_core_health_timeline <- results_plot_health_timeline(
  results_data,
  outcomes = c("mortality", "ihd", "stroke"),
  impact_type = "attributable",
  metric = "prevented"
)

# Optional scenario form of Core 2: reference and counterfactual trajectories.
plot_core_health_timeline_scenarios <- results_plot_health_timeline(
  results_data,
  outcomes = c("mortality", "ihd"),
  impact_type = "cf_vs_ref"
)

## 8.3 Advanced presentation plots ----
# Advanced 1: cumulative prevented health outcomes by age group.
plot_advanced_health_by_age <- results_plot_health_impacts(
  results_data,
  outcomes = c("mortality", "ihd", "stroke", "diabetes"),
  group_by = "age_group",
  metric = "prevented"
)

# Advanced 2: cumulative prevented health outcomes by gender.
plot_advanced_health_by_gender <- results_plot_health_impacts(
  results_data,
  outcomes = c("mortality", "ihd", "stroke", "diabetes"),
  group_by = "gender",
  metric = "prevented"
)

# Advanced 3: reference and counterfactual weighted trip shares by mode.
plot_advanced_travel_by_mode <- results_plot_trip_mode_distribution(
  results_data,
  value = "proportion"
)

plot_core_health_by_outcome
plot_core_health_timeline
plot_core_health_timeline_scenarios
plot_advanced_health_by_age
plot_advanced_health_by_gender
plot_advanced_travel_by_mode

# Step X: comparison of reference vs counterfactual data
