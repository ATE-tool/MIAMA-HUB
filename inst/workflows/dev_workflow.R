# MIAMA-HUB Dev Workflow
# Orchestrates the full impact calculation pipeline for development and testing.
# Run interactively, section by section.
#
# Prerequisites: Set env vars in your project .Renviron (usethis::edit_r_environ("project")):
#   MIAMA_PROJECT_ROOT=/path/to/MIAMA-HUB
#   MIAMA_HM_ROOT=/path/to/MIAMA-HM
# Then restart R so the vars are picked up before loading the package.

# 0. Setup ----
# -----------------------------------------------------------------------------#

## 0.1 Load package ----
devtools::load_all()

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


# --- Full pipeline (commented out until modules are implemented) ----
# -----------------------------------------------------------------------------#

# 6. Create counterfactual data ----
# counterfactual_data <- init_counterfactual_data(reference_data)
# counterfactual_data <- apply_ind_rows_changes(counterfactual_data, request$counterfactual_request)
# counterfactual_data <- apply_ind_attribute_changes(counterfactual_data, request$counterfactual_request)
# counterfactual_data <- apply_trip_rows_changes(counterfactual_data, request$counterfactual_request)
# counterfactual_data <- apply_trip_attribute_changes(counterfactual_data, request$counterfactual_request)

# Step X: comparison of reference vs counterfactual data
# cra_inputs          <- prepare_cra_inputs(reference_data, counterfactual_data, request$results_request)
# health_impacts      <- run_cra(cra_inputs)
# build_ui_return_payload(
#   ui_updates               = reference_ui_values,
#   reference_summaries      = summarize_reference_data(reference_data),
#   counterfactual_summaries = summarize_health_impacts(health_impacts, request$results_request),
#   health_impacts           = health_impacts,
#   state                    = list(reference_data = reference_data, counterfactual_data = counterfactual_data)
# )
