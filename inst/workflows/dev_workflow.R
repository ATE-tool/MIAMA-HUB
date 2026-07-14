# MIAMA-HUB Dev Workflow
# Orchestrates the full impact calculation pipeline for development and testing.
# Run interactively, section by section.
#
# Prerequisites: Set env vars in your project .Renviron (usethis::edit_r_environ("project")):
#   MIAMA_PROJECT_ROOT=/path/to/MIAMA-HUB
#   MIAMA_HM_ROOT=/path/to/MIAMA-HM
# Then restart R so the vars are picked up before loading the package.
# `MIAMA_HM_ROOT` is optional in the common dev layout where `MIAMA-HUB` and
# `MIAMA-HM` are sibling repos; HUB will discover `../MIAMA-HM` automatically.

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
cfg$workflow$dataset_size <- "sample"   # "sample" or "full"
cfg$cache$enabled         <- TRUE
cfg$cache$refresh         <- FALSE

## 0.3 Optional one-time conversion of SP DTA -> parquet ----
# Recommended so Arrow can prefilter by geography before collecting to memory.
# convert_synthpop_to_parquet(cfg, overwrite = FALSE)

## 0.4 Build mock appraisal inputs ----
# Temporary development helper until MIAMA-UI calls MIAMA-HUB directly.
appraisal_inputs <- build_mock_appraisal_inputs(
  overrides = list(
    geo_level = list(input_value = "lad"),
    geo_id = list(input_value = "E08000035"),
    modes = list(input_value = c("walking", "cycling")),
    res_aggregation = list(input_value = "total")
  )
)

request <- receive_appraisal_inputs(appraisal_inputs)

# Developer-friendly flat values
str(request$appraisal_input_values)
str(request$reference_request)
str(request$results_request)
str(request$counterfactual_request)


# 1. Load reference sources ----
# -----------------------------------------------------------------------------#
# Loads HM outcomes + synthetic population (attributes and trips).
# Uses request-driven source selection and geography-aware prefiltering where possible.

reference_sources <- load_reference_sources(
  cfg,
  reference_request = request$reference_request,
  results_request = request$results_request
)

## 1.1 Inspect source report ----
str(reference_sources$source_report)

# Quick intake checks
message("HM outcomes rows:    ", nrow(reference_sources$hm_outcomes))
message("SP attributes rows:  ", nrow(reference_sources$sp_attributes))
message("SP trips rows:       ", nrow(reference_sources$sp_trips))


# 2. Inspect loaded data ----
# -----------------------------------------------------------------------------#

## 2.1 HM outcomes ----
dplyr::glimpse(reference_sources$hm_outcomes)

## 2.2 SP attributes ----
dplyr::glimpse(reference_sources$sp_attributes)

## 2.3 SP trips ----
dplyr::glimpse(reference_sources$sp_trips)

## 2.4 Check expected columns are present ----
# Warn if constants diverge from actual data — adjust constants.R if needed.

sp_attr_missing <- setdiff(MIAMA_SP_ATTRIBUTE_COLS, names(reference_sources$sp_attributes))
sp_trip_missing <- setdiff(MIAMA_SP_TRIP_COLS,      names(reference_sources$sp_trips))

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

## 2.5 Check for unexpected NAs in key ID columns ----
key_id_cols <- c("census_id", "nts_id")
for (col in key_id_cols) {
  if (col %in% names(reference_sources$sp_attributes)) {
    n_na <- sum(is.na(reference_sources$sp_attributes[[col]]))
    if (n_na > 0) warning("NA values in sp_attributes$", col, ": ", n_na)
  }
}


# 3. Join HM outputs and synthetic population ----
# -----------------------------------------------------------------------------#

reference_data_raw <- join_hm_and_synthpop(reference_sources)

## 3.1 Inspect join report ----
str(reference_data_raw$join_report)

## 3.2 Peek at joined individual-level data ----
dplyr::glimpse(reference_data_raw$ind)

## 3.3 Peek at joined trip-level data ----
dplyr::glimpse(reference_data_raw$trips)


# 4. Filter reference data by appraisal inputs ----
# -----------------------------------------------------------------------------#
# With parquet-backed synthpop sources, most geographic filtering should already
# have happened during loading. This step still provides a safe downstream filter.

reference_data <- filter_reference_data(
  reference_data_raw,
  request$reference_request
)

## 4.1 Inspect filter report ----
str(reference_data$filter_report)

## 4.2 Peek at filtered individual-level data ----
dplyr::glimpse(reference_data$ind)

## 4.3 Peek at filtered trip-level data ----
dplyr::glimpse(reference_data$trips)


# 5. Extract info from reference data to pre-populate UI input fields ----
# -----------------------------------------------------------------------------#
# Returns compact values for visible Tab 2 reference fields implied by
# appraisal_inputs, plus a report of skipped fields and data limitations.

reference_ui_values <- extract_reference_ui_values(
  reference_data,
  request$reference_request,
  request$appraisal_input_values
)

## 5.1 Inspect UI updates and extraction report ----
str(reference_ui_values$ui_updates)
str(reference_ui_values$extraction_report)

# Development-only example target for Step 6. Real UI calls should provide
# `users_count_cf_walk` or another supported `_cf_` value directly.
request$appraisal_input_values$users_count_cf_walk <- min(
  reference_ui_values$ui_updates$pop_total_ref,
  reference_ui_values$ui_updates$pop_number_ref_walk + 10
)


# --- Full pipeline (commented out until modules are implemented) ----
# -----------------------------------------------------------------------------#

# 6. Create counterfactual data ----
# -----------------------------------------------------------------------------#
# First-pass UI-driven implementation. Starts from a 1:1 copy of reference_data,
# then applies supported `_cf_` values while recording assumptions in
# `counterfactual_report`.

counterfactual_data <- init_counterfactual_data(reference_data)
counterfactual_data <- apply_counterfactual_ui_values(
  counterfactual_data,
  request$appraisal_input_values,
  reference_data = reference_data,
  seed = 1L
)

## 6.1 Inspect counterfactual report and changed data ----
str(counterfactual_data$counterfactual_report)
counterfactual_data$counterfactual_report$comparison$ind
counterfactual_data$counterfactual_report$comparison$trips
counterfactual_data$counterfactual_report$comparison$changed_ind_rows
dplyr::glimpse(counterfactual_data$ind)
dplyr::glimpse(counterfactual_data$trips)

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

## 7.1 Inspect counterfactual health outcomes ----
str(counterfactual_data$counterfactual_health_report)
dplyr::glimpse(counterfactual_data$health_outcomes)
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
  appraisal_input_values = request$appraisal_input_values
)

## 8.1 Inspect result summaries and tables ----
str(results_data$headline_metrics)
str(results_data$results_report)
results_data$results_table |>
  dplyr::arrange(dplyr::desc(abs(delta_value))) |>
  utils::head(30) |>
  print()

## 8.2 Draft presentation plots ----
plot_health_overview <- results_plot_health_overview(results_data, value = "delta")
plot_trip_modes <- results_plot_trip_mode_distribution(results_data)
plot_health_timeline <- results_plot_health_timeline(results_data)

plot_health_overview
plot_trip_modes
plot_health_timeline

# Step X: comparison of reference vs counterfactual data
