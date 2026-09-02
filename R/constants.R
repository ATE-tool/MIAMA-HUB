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

# The full synthetic population is a random 5% Census 2021 sample.
# Each synthetic individual therefore represents approximately 20 residents.
MIAMA_SYNTHPOP_PERSON_WEIGHT <- 20

# Physical-activity intensities used by MIAMA-HM to convert weekly activity
# hours into MMET-hours. Counterfactual exposure calculations use the same
# constants so trip and individual activity changes enter the HM lookup on a
# common scale.
MIAMA_MMET_PER_HOUR <- c(
  walking = 2.5,
  cycling = 5.8,
  # Until e-bike-specific evidence is adopted, use cycling intensity 1:1.
  ebiking = 5.8,
  # Only walking access to public transport contributes physical activity.
  pt = 2.5,
  vigorous = 7
)

# NTS MainMode_B04ID: publication-table breakdown used by `trip_mainmode` in
# the synthetic-population parquet. The source contains numeric codes without
# retained value labels, so HUB must classify both these codes and readable
# labels introduced in tests or counterfactual rows.
MIAMA_NTS_MAINMODE_B04 <- c(
  walk = 1,
  bicycle = 2,
  car_driver = 3,
  car_passenger = 4,
  motorcycle = 5,
  other_private = 6,
  bus_london = 7,
  bus_other_local = 8,
  bus_nonlocal = 9,
  underground = 10,
  surface_rail = 11,
  taxi_minicab = 12,
  other_public = 13
)

# Broad four-mode presentation groups. The UI's aggregate mode-share control
# has no separate motorcycle/taxi/other category, so these are retained in the
# broad car/private-motor group, matching the prior text classifier.
MIAMA_NTS_MAINMODE_CAR_CODES <- unname(MIAMA_NTS_MAINMODE_B04[c(
  "car_driver", "car_passenger", "motorcycle", "other_private", "taxi_minicab"
)])
MIAMA_NTS_MAINMODE_PT_CODES <- unname(MIAMA_NTS_MAINMODE_B04[c(
  "bus_london", "bus_other_local", "bus_nonlocal", "underground",
  "surface_rail", "other_public"
)])
