# nolint

# MIAMA Impact Calculation Workflow
#
# Initial code implementation based on Steve's code in sp_hm_join.R

# 0 Setup ----
# -----------------------------------------------------------------------------#

## 0.1 Libraries ----
# -------------------------------------#

library(tidyverse)
library(haven)
library(data.table)
library(arrow)

## 0.2 Constants ----
# -------------------------------------#

# Paths in MIAMA
MIAMA_HM_ROOT <- "../MIAMA-HM"
HM_PROCESSED_ROOT <- file.path(MIAMA_HM_ROOT, "health_data", "processed")

# Synthetic population input datasets for England 
# TODO:(currently from local data folder, but could be fetched from MIAMA-HM in future if synced/available there)
# Synthetic population schema reference
  # Individual-level columns (SP_ATTRIBUTES_LOC):
    # ids/geography: census_id, nts_id, lad25cd, lad25nm, region
    # sociodemographic: imd_decile, urban, female, age1year, nonwhite, limitingcondition, householdcar, zerotrips
    # activity (hours/week): cycletime_wkhr, walktime_wkhr, sport_wkhr
  # Trip-level columns (SP_TRIPS_LOC; in addition to individual-level columns above):
    # ids/weights: nts_tripid, weight_tripXhh
    # trip descriptors: trip_mainmode, trip_purpose
    # trip totals: trip_durationraw_min, trip_distraw_km
    # trip active-travel components: trip_cycledist_km, trip_cycletime_min, trip_walkdist_km, trip_walktime_min
SP_ATTRIBUTES_DTA_LOC <- file.path("data", "synthetic_pop", "SPindivid_CensusNTSALS.dta")
SP_TRIPS_DTA_LOC <- file.path("data", "synthetic_pop", "SPtrip_CensusNTSALS.dta")
SP_ATTRIBUTES_PARQUET_LOC <- file.path("data", "synthetic_pop", "SPindivid_CensusNTSALS_parquet")
SP_TRIPS_PARQUET_LOC <- file.path("data", "synthetic_pop", "SPtrip_CensusNTSALS_parquet")
SP_ATTRIBUTES_DEV_PARQUET_LOC <- file.path("data", "synthetic_pop", "SPindivid_CensusNTSALS_dev_parquet")
SP_TRIPS_DEV_PARQUET_LOC <- file.path("data", "synthetic_pop", "SPtrip_CensusNTSALS_dev_parquet")
SP_ATTRIBUTES_LOC <- dplyr::case_when(
  dir.exists(SP_ATTRIBUTES_DEV_PARQUET_LOC) ~ SP_ATTRIBUTES_DEV_PARQUET_LOC,
  dir.exists(SP_ATTRIBUTES_PARQUET_LOC) ~ SP_ATTRIBUTES_PARQUET_LOC,
  TRUE ~ SP_ATTRIBUTES_DTA_LOC
)
SP_TRIPS_LOC <- dplyr::case_when(
  dir.exists(SP_TRIPS_DEV_PARQUET_LOC) ~ SP_TRIPS_DEV_PARQUET_LOC,
  dir.exists(SP_TRIPS_PARQUET_LOC) ~ SP_TRIPS_PARQUET_LOC,
  TRUE ~ SP_TRIPS_DTA_LOC
)

# Health-Model-Outcomes Input parquet datasets produced in MIAMA-HM
# include mmets, aggregated health outcomes ("overall") and annual outcomes ("cycle")
# SAMPLE is a smaller dataset for testing and development; 
SP_JOINED_OVERALL_LOC <- file.path(HM_PROCESSED_ROOT, "sp_overall_outcomes")
SP_JOINED_CYCLE_LOC <- file.path(HM_PROCESSED_ROOT, "sp_cycle_outcomes")
SP_JOINED_OVERALL_SAMPLE_LOC <- file.path(HM_PROCESSED_ROOT, "sp_overall_outcomes_sample")
SP_JOINED_CYCLE_SAMPLE_LOC <- file.path(HM_PROCESSED_ROOT, "sp_cycle_outcomes_sample")
LOOKUP_OVERALL_LOC <- file.path(HM_PROCESSED_ROOT, "mmet_d_overall_lookup")
LOOKUP_CYCLE_LOC <- file.path(HM_PROCESSED_ROOT, "mmet_d_cycle_lookup")

# Scenario outputs written in MIAMA
SCENARIO_OUTPUT_ROOT <- file.path("outputs", "scenarios")
SCENARIO_OVERALL_LOC <- file.path(SCENARIO_OUTPUT_ROOT, "sample_scenario_overall")
SCENARIO_CYCLE_LOC <- file.path(SCENARIO_OUTPUT_ROOT, "sample_scenario_cycle")
dir.create(SCENARIO_OUTPUT_ROOT, recursive = TRUE, showWarnings = FALSE)

## 0.3 Health-model-outcomes inputs (parquet -> optional rds cache) ----
# -------------------------------------#

# configure which health model outcomes dataset to load and whether to cache as rds for faster loading in future runs
hm_outcomes_cfg <- list(
  base_dir = HM_PROCESSED_ROOT,
  granularity = "overall", # options: "overall", "cycle"
  dataset_size = "sample", # options: "sample", "full"
  cache_as_rds = TRUE,
  refresh_cache = FALSE,
  cache_dir = file.path("data", "cache")
)
# Function to load health model outcomes from parquet with optional caching as rds for faster loading in future runs.
load_hm_outcomes <- function(cfg = hm_outcomes_cfg) {
  valid_granularity <- c("overall", "cycle")
  valid_sizes <- c("sample", "full")

  if (!cfg$granularity %in% valid_granularity) {
    stop("cfg$granularity must be one of: ", paste(valid_granularity, collapse = ", "))
  }
  if (!cfg$dataset_size %in% valid_sizes) {
    stop("cfg$dataset_size must be one of: ", paste(valid_sizes, collapse = ", "))
  }

  dataset_dir <- paste0(
    "sp_",
    cfg$granularity,
    "_outcomes",
    if (cfg$dataset_size == "sample") "_sample" else ""
  )

  parquet_path <- file.path(cfg$base_dir, dataset_dir)
  if (!dir.exists(parquet_path)) {
    stop("Parquet dataset directory not found: ", parquet_path)
  }

  cache_file <- file.path(
    cfg$cache_dir,
    paste0("hm_outcomes_", cfg$granularity, "_", cfg$dataset_size, ".rds")
  )

  if (isTRUE(cfg$cache_as_rds) && file.exists(cache_file) && !isTRUE(cfg$refresh_cache)) {
    message("Loading health model outcomes from cached rds: ", cache_file)
    return(readRDS(cache_file))
  }

  message("Loading health model outcomes from parquet: ", parquet_path)
  hm_outcomes <- dplyr::collect(
    arrow::open_dataset(parquet_path, format = "parquet")
  )

  if (isTRUE(cfg$cache_as_rds)) {
    dir.create(cfg$cache_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(hm_outcomes, cache_file)
    message("Saved health model outcomes cache: ", cache_file)
  }

  hm_outcomes
}

# Load health model outcomes into R (with caching for faster future loads)
hm_outcomes <- load_hm_outcomes()

## 0.4 Scenario functions and usage from workflow ----
# -------------------------------------#

source("R/run_scenario_functions.R")
source(file.path("..", "MIAMA-UI", "schemes", "appraisal_inputs.R")) # canonical UI input scheme; serves as profile template
source("helpers/build_mock_case_study_profile.R")

# 1. Load UI input ----
## Mock profiles
case_study_profile_overall <- build_mock_case_study_profile(
  appraisal_inputs = appraisal_inputs,
  res_aggregation = "total"
)
case_study_profile_cycle <- build_mock_case_study_profile(
  appraisal_inputs = appraisal_inputs,
  res_aggregation = "timeline"
)


# 2. Run scenario(s) ----

# Sample scenario runs are controlled from this workflow file.
# Keep FALSE during regular development to avoid heavy execution.
RUN_SAMPLE_SCENARIO_OVERALL <- TRUE
RUN_SAMPLE_SCENARIO_CYCLE <- FALSE
# Temporary shim: add `_bl` suffix to mutable baseline columns on load.
# Set FALSE (or remove) once source data files already use `_bl` naming.
NORMALIZE_BASELINE_COLS <- TRUE

if (RUN_SAMPLE_SCENARIO_OVERALL) {
  build_res_overall <- build_scenario(
    sp_joined_loc = SP_JOINED_OVERALL_SAMPLE_LOC,
    sp_attributes_loc = SP_ATTRIBUTES_LOC,
    sp_cols = c("census_id", "nts_id", "lad25cd", "lad25nm", "region", "imd_decile", "female", "age1year", "householdcar", "zerotrips"),
    normalize_bl_cols = NORMALIZE_BASELINE_COLS,
    case_study_profile = case_study_profile_overall
  )

  scenario_updated_overall <- run_scenario(
    scenario_arrow = build_res_overall$scenario_arrow,
    lookup_loc = LOOKUP_OVERALL_LOC,
    outcome_format = case_study_profile_overall$scenario$outcome_format
  )

  arrow::write_dataset(
    scenario_updated_overall,
    SCENARIO_OVERALL_LOC,
    max_rows_per_file = 1000000
  )
}

if (RUN_SAMPLE_SCENARIO_CYCLE) {
  build_res_cycle <- build_scenario(
    sp_joined_loc = SP_JOINED_CYCLE_SAMPLE_LOC,
    sp_attributes_loc = SP_ATTRIBUTES_LOC,
    sp_cols = c("census_id", "nts_id", "lad25cd", "lad25nm", "region", "imd_decile", "female", "age1year", "householdcar", "zerotrips"),
    normalize_bl_cols = NORMALIZE_BASELINE_COLS,
    case_study_profile = case_study_profile_cycle
  )

  scenario_updated_cycle <- run_scenario(
    scenario_arrow = build_res_cycle$scenario_arrow,
    lookup_loc = LOOKUP_CYCLE_LOC,
    outcome_format = case_study_profile_cycle$scenario$outcome_format
  )

  arrow::write_dataset(
    scenario_updated_cycle,
    SCENARIO_CYCLE_LOC,
    max_rows_per_file = 2000000
  )
}

# --- End of workflow setup ---









# Inspect scenario outputs (for testing purposes) ----
library(arrow)
library(dplyr)

# 1) Open whole dataset folder
#ds <- open_dataset("outputs/scenarios/sample_scenario_overall")

# quick peek
#ds %>% slice_head(n = 20) %>% collect()
#ds %>% summarise(n = n()) %>% collect()

#df <- ds %>% collect()
#View(df)
