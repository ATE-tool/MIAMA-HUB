# Central constants for workflow setup

# Synthetic population columns expected downstream (adjust from legacy POC as needed)
MIAMA_SP_COLS <- c(
  "person_id",
  "household_id",
  "age",
  "sex",
  "trip_id",
  "trip_mode",
  "trip_distance_km",
  "trip_duration_min"
)

# Scenario/output defaults
MIAMA_DEFAULT_SCENARIO <- "baseline"
MIAMA_SCENARIO_DIRNAME <- "scenario_analysis"

# Dataset controls
MIAMA_DEFAULT_MAX_ROWS <- Inf
MIAMA_SMALL_DATASET_MAX_ROWS <- 100000L