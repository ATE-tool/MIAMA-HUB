# Central constants for workflow setup

# Synthetic population: individual-level columns
# Source: SPindivid_CensusNTSALS (attributes file)
MIAMA_SP_ATTRIBUTE_COLS <- c(
  # IDs / geography
  "census_id", "nts_id", "lad25cd", "lad25nm", "region",
  # Sociodemographic
  "imd_decile", "urban", "female", "age1year", "nonwhite",
  "limitingcondition", "householdcar", "zerotrips",
  # Activity (hours/week)
  "cycletime_wkhr", "walktime_wkhr", "sport_wkhr"
)

# Synthetic population: trip-level columns (extends attribute columns)
# Source: SPtrip_CensusNTSALS (trips file)
MIAMA_SP_TRIP_COLS <- c(
  MIAMA_SP_ATTRIBUTE_COLS,
  # IDs / weights
  "nts_tripid", "weight_tripXhh",
  # Trip descriptors
  "trip_mainmode", "trip_purpose",
  # Trip totals
  "trip_durationraw_min", "trip_distraw_km",
  # Active-travel components
  "trip_cycledist_km", "trip_cycletime_min",
  "trip_walkdist_km", "trip_walktime_min"
)

# Scenario/output defaults
MIAMA_DEFAULT_SCENARIO  <- "baseline"
MIAMA_SCENARIO_DIRNAME  <- "scenario_analysis"

# Dataset size controls
MIAMA_DEFAULT_MAX_ROWS       <- Inf
MIAMA_SMALL_DATASET_MAX_ROWS <- 100000L
