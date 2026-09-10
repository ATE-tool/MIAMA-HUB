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
# `MIAMA_DATA_ROOT` is optional for packaged sample, Leeds and Manchester runs and
# required for full synthpop runs. Set `MIAMA_DEV_DATASET_SIZE=leeds` to use the
# packaged 5,000-person Leeds profile, or manchester for 10,000 Manchester people.

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
# Pass dataset size at construction time because it determines which source
# paths are resolved. Changing only `cfg$workflow$dataset_size` afterward can
# leave full synthpop paths paired with sample HM paths (or vice versa).
dev_dataset_size <- Sys.getenv("MIAMA_DEV_DATASET_SIZE", unset = "leeds")
cfg <- miama_default_config(dataset_size = dev_dataset_size) # sample, leeds, manchester, full
cfg$cache$enabled         <- TRUE
cfg$cache$refresh         <- FALSE

# Confirm the complete source set before loading. Step 5 uses the one-row-per-
# person cycle-0 HM state to obtain reference MMETs; Step 7 separately uses the
# cycle death-share table and MMET lookup to calculate counterfactual outcomes.
message("Dataset size:          ", cfg$workflow$dataset_size)
message("Synthpop individuals:  ", cfg$sources$sp_attributes$path)
message("Synthpop trips:        ", cfg$sources$sp_trips$path)
hm_overall_key <- if (identical(cfg$workflow$dataset_size, "sample")) "overall_sample" else "overall"
hm_cycle_key <- if (identical(cfg$workflow$dataset_size, "sample")) "cycle_sample" else "cycle"
message("HM cycle-0 reference:  ", .hm_source_path(cfg$sources$hm_outcomes[[hm_overall_key]]))
message("HM death-share cycles: ", .hm_source_path(cfg$sources$hm_death_share[[hm_cycle_key]]))
message("HM MMET lookup:        ", .hm_source_path(cfg$sources$hm_death_share$lookup_cycle))

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
    geo_id = list(input_value = cfg$population$profile$geo_id %||% "E08000035"),
    # Match the UI processing order that previously exposed cross-mode
    # cannibalization: cycling first, then walking.
    modes = list(input_value = c("cycling", "walking")),
    trips_timeframe_bike = list(input_value = "week"),
    trips_timeframe_walk = list(input_value = "week"),
    users_timeframe_bike = list(input_value = "week"),
    users_timeframe_walk = list(input_value = "week"),
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
# This default scenario reproduces the current Leeds UI test exactly. The modal
# values are weighted weekly trip totals; HUB converts each weighted target to
# the physical number of synthetic rows to change, retaining row trip weights.
#
# User changes are applied before trip-count changes. The trip targets are
# absolute, so Step 6 reconciles any trips already shifted for new users to the
# final submitted total rather than adding another relative change.

dev_cf_scenario <- list(
  name = "Leeds UI parity: 1,500 cycling and 50,000 walking trips/week",
  relative_change = NA_real_,
  modes = c("cycling", "walking"),
  change_users = TRUE,
  change_trips = TRUE,
  user_targets = c(cycling = 155, walking = 2247),
  weighted_trip_targets = c(cycling = 1500, walking = 50000),
  assump_induced_trips_percent = 10,
  # Optional source-mode shares for the shifted (non-induced) trips entering
  # each target mode. Names use HUB modes and values may be proportions or
  # percentages, for example:
  # list(walking = c(driving = 70, pt = 20, other = 10))
  # An absent target uses the profile/configured source distribution.
  source_mode_shares = list(),
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
      explicit_user_target <- scenario$user_targets[[mode]]
      cf_users <- if (!is.null(explicit_user_target) && is.finite(explicit_user_target)) {
        as.integer(explicit_user_target)
      } else {
        relative_integer_target(ref_users, scenario$relative_change, population_n)
      }
      values[[paste0("users_count_cf_", suffix)]] <- cf_users
      target_rows[[length(target_rows) + 1L]] <- data.frame(
        mode = mode,
        metric = "weekly users",
        reference = ref_users,
        counterfactual = cf_users,
        requested_relative_change = if (ref_users > 0) cf_users / ref_users - 1 else NA_real_,
        realized_relative_change = if (ref_users > 0) cf_users / ref_users - 1 else NA_real_,
        target_basis = "individual rows",
        stringsAsFactors = FALSE
      )
    }

    if (isTRUE(scenario$change_trips)) {
      ref_trips <- ref_values[[paste0("trips_count_ref_", suffix)]]
      if (is.null(ref_trips) || !is.finite(ref_trips)) {
        stop("Missing weighted reference trip count for mode: ", mode, call. = FALSE)
      }
      explicit_trip_target <- scenario$weighted_trip_targets[[mode]]
      cf_trips <- if (!is.null(explicit_trip_target) && is.finite(explicit_trip_target)) {
        as.numeric(explicit_trip_target)
      } else {
        ref_trips * (1 + scenario$relative_change)
      }
      values[[paste0("trips_timeframe_", suffix)]] <- "week"
      values[[paste0("trips_denominator_", suffix)]] <- "total"
      values[[paste0("trips_count_cf_", suffix)]] <- cf_trips
      target_rows[[length(target_rows) + 1L]] <- data.frame(
        mode = mode,
        metric = "weekly active-mode trips",
        reference = ref_trips,
        counterfactual = cf_trips,
        requested_relative_change = if (ref_trips > 0) cf_trips / ref_trips - 1 else NA_real_,
        realized_relative_change = if (ref_trips > 0) cf_trips / ref_trips - 1 else NA_real_,
        target_basis = "weighted weekly trips",
        stringsAsFactors = FALSE
      )
    }

    source_shares <- scenario$source_mode_shares[[mode]]
    if (!is.null(source_shares)) {
      source_names <- c(
        driving = "car", cycling = "bike", ebiking = "ebike",
        walking = "walk", pt = "pt", other = "other"
      )
      source_shares <- source_shares[names(source_shares) != mode]
      if (length(source_shares) == 0 || any(!is.finite(source_shares)) ||
          any(source_shares < 0) || sum(source_shares) <= 0) {
        stop("Invalid source-mode shares for target mode: ", mode, call. = FALSE)
      }
      if (sum(source_shares) <= 1 + sqrt(.Machine$double.eps)) {
        source_shares <- 100 * source_shares
      }
      source_shares <- 100 * source_shares / sum(source_shares)
      values[[paste0("assump_trip_source_shares_", suffix)]] <- stats::setNames(
        lapply(as.numeric(source_shares), function(percent) list(percent = percent)),
        unname(source_names[names(source_shares)])
      )
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
      active <- spec$trip_filter(counterfactual_data$trips) &
        !is.na(counterfactual_data$trips$nts_tripid)
      return(sum(.trip_weights(counterfactual_data$trips)[active], na.rm = TRUE))
    }

    NA_real_
  }, numeric(1))

  tolerance <- ifelse(targets$target_basis == "weighted weekly trips", 0.02, 0)
  relative_error <- ifelse(
    targets$counterfactual == 0,
    abs(realized - targets$counterfactual),
    abs(realized / targets$counterfactual - 1)
  )

  data.frame(
    mode = targets$mode,
    metric = targets$metric,
    expected = targets$counterfactual,
    realized = realized,
    relative_error = relative_error,
    achieved = relative_error <= tolerance,
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
counterfactual_constants$assump_induced_trips_percent_default <-
  dev_cf_scenario$assump_induced_trips_percent

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
# Mirrors the first data stage inside `Hub$build_results()`. Cycle-0 HM states
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
# First converts submitted Tab 2 REF volumes into an assessed population and
# mode-specific scope flags. Without an explicit population total, HUB pools
# requested/source mode rates to estimate the population represented by those
# volumes. REF sampling changes membership only, not behavior or MMETs. CF then
# starts from the same person boundary and changes behavior within it.

reference_data <- apply_reference_appraisal_scope(
  reference_data,
  appraisal_input_values = counterfactual_appraisal_input_values,
  seed = dev_cf_scenario$seed
)
str(reference_data$reference_scope_report)
reference_person_scope <- reference_data$reference_scope_report$person
message(
  "Assessed reference population: ", reference_person_scope$realized,
  " / ", reference_person_scope$donor_population,
  " (", reference_person_scope$method, ")"
)
if (length(reference_person_scope$mode_estimates) > 0) {
  reference_mode_population_estimates <- do.call(rbind, lapply(
    reference_person_scope$mode_estimates,
    function(x) as.data.frame(x[c(
      "mode", "source", "field", "requested", "baseline", "ratio",
      "estimated_people"
    )], stringsAsFactors = FALSE)
  ))
  print(reference_mode_population_estimates, row.names = FALSE)
}

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
counterfactual_data$counterfactual_report$mmet_exposure
glimpse_head(counterfactual_data$ind)
glimpse_head(counterfactual_data$trips)

# 7. Rejoin health outcomes based on updated physical activity levels (mmets) for counterfactual data ----
# -----------------------------------------------------------------------------#
# Uses the updated MIAMA-HM death-share cycle tables, then reconstructs disease
# prevalence and calculates reference/counterfactual HALYs. For
# `dataset_size = "sample"`, Step 7 prefers the sample
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
str(counterfactual_data$counterfactual_health_report$haly)
glimpse_head(counterfactual_data$health_outcomes)
counterfactual_data$health_outcomes |>
  dplyr::summarise(
    haly_ref = sum(.data$haly, na.rm = TRUE),
    haly_cf = sum(.data$haly + .data$d_haly, na.rm = TRUE),
    halys_gained = sum(.data$d_haly, na.rm = TRUE)
  ) |>
  print()
counterfactual_data$counterfactual_health_report$impact_overview |>
  dplyr::arrange(dplyr::desc(abs(delta_total))) |>
  utils::head(30) |>
  print()


# 8. Prepare results data for Tab 5 presentation ----
# -----------------------------------------------------------------------------#
# Builds the compact, filterable result tables used by Tab 5. The UI can apply
# its interactive filter panel to `results_data$plot_data` without rerunning the
# health model. Those later interactive selections currently affect displayed
# plots only; they do not rebuild the static download bundle created in Step 9.

results_data <- prepare_results_data(
  counterfactual_data = counterfactual_data,
  reference_data = reference_data,
  results_request = request$results_request,
  appraisal_input_values = counterfactual_appraisal_input_values,
  cfg = cfg
)

## 8.1 Inspect result summaries and tables ----
str(results_data$headline_metrics)
str(results_data$results_report)
# `delta_value` retains HM's technical cf-ref sign. Benefit-oriented columns
# reverse this for adverse outcomes but retain it for HALYs, so positive values
# consistently represent health gains.
results_data$results_table |>
  dplyr::arrange(dplyr::desc(abs(delta_value))) |>
  utils::head(30) |>
  print()

## 8.2 Inspect mode attribution and reconciliation ----
# Mode health impacts are allocated from each individual's signed contribution
# to the total MMET change. Their deltas must sum back to `all_modes`.
results_data$plot_data$mode_attribution |>
  print()

mode_reconciliation <- results_data$plot_data$health_cube |>
  dplyr::group_by(.data$mode) |>
  dplyr::summarise(delta_value = sum(.data$delta_value, na.rm = TRUE), .groups = "drop")

mode_reconciliation |>
  print()

stopifnot(isTRUE(all.equal(
  mode_reconciliation$delta_value[mode_reconciliation$mode == "all_modes"],
  sum(mode_reconciliation$delta_value[mode_reconciliation$mode != "all_modes"]),
  tolerance = 1e-8
)))

## TODO 8.3.1 Headline results ----

## 8.3.2 Core presentation plots ----
# Core 1: cumulative percentage reduction by selected health outcome.
plot_core_health_by_outcome <- results_plot_health_overview(
  results_data,
  outcomes = c("ihd", "stroke", "diabetes", "depression", "alzheimer", "cancers"),
  impact_type = "attributable",
  metric = "percent_reduction"
)

# Core 2: cumulative prevented health outcomes per 100,000 residents. Cycle 0
# is the baseline state and is excluded; cycle 1 is the first modelled year.
plot_core_health_timeline <- results_plot_health_timeline(
  results_data,
  outcomes = c("mortality", "ihd", "stroke"),
  impact_type = "attributable",
  metric = "prevented_per_100000",
  timeline_type = "cumulative"
)

# Diagnostic companion: annual prevented outcomes. Annual HM results can vary
# between cycles; use the cumulative plot above for the primary presentation.
plot_diagnostic_health_timeline_annual <- results_plot_health_timeline(
  results_data,
  outcomes = c("mortality", "ihd", "stroke"),
  impact_type = "attributable",
  metric = "prevented_per_100000",
  timeline_type = "annual"
)

## 8.4 Advanced presentation plots ----
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

# Advanced 3: health deltas attributed to active modes by MMET contribution.
plot_advanced_health_by_mode <- results_plot_health_impacts(
  results_data,
  outcomes = c("mortality", "ihd", "stroke", "diabetes"),
  modes = c("walking", "cycling"),
  group_by = "mode",
  metric = "prevented"
)

# Advanced 4: reference and counterfactual weighted trip shares by mode.
plot_advanced_travel_by_mode <- results_plot_trip_mode_distribution(
  results_data,
  value = "proportion"
)

plot_core_health_by_outcome
plot_core_health_timeline
plot_diagnostic_health_timeline_annual
plot_advanced_health_by_age
plot_advanced_health_by_gender
plot_advanced_health_by_mode
plot_advanced_travel_by_mode

## 8.5 Inspect the compact plot-data contract ----
# These are the comprehensive source tables retained for plotting and export
# preparation. They are more useful for development inspection than any one
# filtered plot data frame.
names(results_data$plot_data)
glimpse_head(results_data$plot_data$health_cube)
glimpse_head(results_data$plot_data$trip_mode_distribution)

## 8.6 Audit submitted trip targets through the results contract ----
# This table is the quickest regression check for the original 702-cycling-trip
# bug. `direct_cf_weighted` is calculated from counterfactual rows, while
# `plot_data_cf_weighted` is the value passed to plots and exports. Both should
# be close to the submitted weighted target; a small difference is expected
# because the target is realized by sampling indivisible weighted trip rows.
trip_target_rows <- dev_cf_targets[
  dev_cf_targets$metric == "weekly active-mode trips",
  ,
  drop = FALSE
]

trip_results_long <- results_data$plot_data$trip_mode_distribution |>
  dplyr::filter(.data$mode %in% trip_target_rows$mode)
trip_results_wide <- dplyr::full_join(
  trip_results_long |>
    dplyr::filter(.data$scenario == "Reference") |>
    dplyr::transmute(mode = .data$mode, Reference = .data$trips),
  trip_results_long |>
    dplyr::filter(.data$scenario == "Counterfactual") |>
    dplyr::transmute(mode = .data$mode, Counterfactual = .data$trips),
  by = "mode"
)

direct_trip_totals <- do.call(rbind, lapply(trip_target_rows$mode, function(mode) {
  spec <- .miama_tab2_mode_specs()[[mode]]
  ref_active <- spec$trip_filter(reference_data$trips) & !is.na(reference_data$trips$nts_tripid)
  cf_active <- spec$trip_filter(counterfactual_data$trips) & !is.na(counterfactual_data$trips$nts_tripid)
  data.frame(
    mode = mode,
    reference_physical_rows = sum(ref_active, na.rm = TRUE),
    counterfactual_physical_rows = sum(cf_active, na.rm = TRUE),
    direct_ref_weighted = sum(.trip_weights(reference_data$trips)[ref_active], na.rm = TRUE),
    direct_cf_weighted = sum(.trip_weights(counterfactual_data$trips)[cf_active], na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}))

trip_results_audit <- trip_target_rows |>
  dplyr::transmute(
    mode = .data$mode,
    submitted_cf_weighted = .data$counterfactual
  ) |>
  dplyr::left_join(direct_trip_totals, by = "mode") |>
  dplyr::left_join(trip_results_wide, by = "mode") |>
  dplyr::rename(
    plot_data_ref_weighted = "Reference",
    plot_data_cf_weighted = "Counterfactual"
  ) |>
  dplyr::mutate(
    cf_target_difference = .data$plot_data_cf_weighted - .data$submitted_cf_weighted
  )

print(trip_results_audit, row.names = FALSE)

stopifnot(
  isTRUE(all.equal(
    trip_results_audit$direct_cf_weighted,
    trip_results_audit$plot_data_cf_weighted,
    tolerance = 1e-10
  )),
  all(abs(trip_results_audit$cf_target_difference) /
        trip_results_audit$submitted_cf_weighted <= 0.02)
)


# 9. Build the static UI export bundle ----
# -----------------------------------------------------------------------------#
# Mirrors the current MIAMA-UI behavior: immediately after `build_results()`,
# the app calls `build_results_exports()` once with no live Tab 5 filter-panel
# arguments. The bundle therefore uses the initial `results_request` stored in
# `results_data` and remains unchanged when users later filter on-screen plots.
#
# This step only assembles compact tables and ggplot objects in memory. To write
# CSV, Excel, PNG/ZIP, AMAT, and report examples, subsequently run
# `inst/workflows/dev_results_exports.R` in the same R session.

results_exports <- prepare_results_exports(
  results_data = results_data,
  profile = appraisal_inputs,
  cfg = cfg
)

## 9.1 Inspect export bundle structure and selection snapshot ----
names(results_exports)
results_exports$metadata |> as.data.frame() |> print(row.names = FALSE)
results_exports$filters |> as.data.frame() |> print(row.names = FALSE)
results_exports$headline_metrics |> as.data.frame() |> print(row.names = FALSE)

## 9.2 Inspect principal exported data tables ----
glimpse_head(results_exports$results_table, n = 30L)
glimpse_head(results_exports$timeline_annual)
glimpse_head(results_exports$timeline_cumulative)
glimpse_head(results_exports$trip_mode_distribution)
glimpse_head(results_exports$amat_health_timeline)
results_exports$amat_health_summary |> as.data.frame() |> print(row.names = FALSE)

export_trip_audit <- results_exports$trip_mode_distribution |>
  dplyr::filter(.data$mode %in% trip_target_rows$mode) |>
  dplyr::select("scenario", "mode", "trips") |>
  dplyr::arrange(.data$mode, .data$scenario)
print(export_trip_audit, row.names = FALSE)

## 9.3 Inspect static export plots ----
names(results_exports$plots)
results_exports$plots$health_overview
results_exports$plots$health_timeline
results_exports$plots$health_by_age
results_exports$plots$health_by_gender
results_exports$plots$health_by_mode
results_exports$plots$trip_mode_distribution
