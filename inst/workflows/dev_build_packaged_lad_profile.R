# Build an aligned packaged LAD profile from existing synthpop and HM outputs.
# Run from HUB with MIAMA_PROFILE_ID=manchester (or leeds).
# Defaults: Leeds 5000 / E08000035 / seed 20260826;
# Manchester 10000 / E08000003 / seed 20260908.
# Overrides: MIAMA_PROFILE_GEO_ID, MIAMA_PROFILE_SAMPLE_N, MIAMA_PROFILE_SEED.
# MIAMA_PROFILE_OVERWRITE=true permits replacing the target profile.
# Sources: MIAMA_DATA_ROOT (HUB/data), MIAMA_HM_ROOT (sibling MIAMA-HM).
# Output: inst/extdata/data/profiles/<profile_id>.
# Source expansion is provenance; appraisal person weight remains one.

# 0. Setup ----
# -----------------------------------------------------------------------------#

find_miama_hub_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = FALSE)
  repeat {
    description <- file.path(current, "DESCRIPTION")
    if (file.exists(description) &&
        identical(unname(read.dcf(description)[1, "Package"]), "MIAMAHUB")) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find the MIAMA-HUB package root.", call. = FALSE)
    }
    current <- parent
  }
}

env_flag <- function(name, default = FALSE) {
  value <- tolower(trimws(Sys.getenv(name, unset = as.character(default))))
  value %in% c("1", "true", "yes", "y")
}

require_directory <- function(path, label) {
  if (!dir.exists(path)) {
    stop(label, " not found: ", path, call. = FALSE)
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

hub_root <- find_miama_hub_root()
data_root <- Sys.getenv("MIAMA_DATA_ROOT", unset = file.path(hub_root, "data"))
hm_root <- Sys.getenv("MIAMA_HM_ROOT", unset = file.path(dirname(hub_root), "MIAMA-HM"))
profile_id <- Sys.getenv("MIAMA_PROFILE_ID", unset = "leeds")
if (!grepl("^[a-z][a-z0-9_]*$", profile_id)) stop("Invalid MIAMA_PROFILE_ID.")
default_geo <- switch(profile_id, leeds = "E08000035", manchester = "E08000003", "")
geo_id <- Sys.getenv("MIAMA_PROFILE_GEO_ID", unset = default_geo)
if (!nzchar(geo_id)) stop("Set MIAMA_PROFILE_GEO_ID for this profile.")
sample_n <- as.integer(Sys.getenv("MIAMA_PROFILE_SAMPLE_N", unset = if (profile_id == "manchester") "10000" else "5000"))
seed <- as.integer(Sys.getenv("MIAMA_PROFILE_SEED", unset = if (profile_id == "manchester") "20260908" else "20260826"))
overwrite <- env_flag("MIAMA_PROFILE_OVERWRITE")

if (is.na(sample_n) || sample_n < 1L) {
  stop("MIAMA_PROFILE_SAMPLE_N must be one positive integer.", call. = FALSE)
}
if (is.na(seed)) {
  stop("MIAMA_PROFILE_SEED must be one integer.", call. = FALSE)
}

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

arrow::set_cpu_count(1L)


# 1. Resolve Full Sources ----
# -----------------------------------------------------------------------------#
# Only current parquet sources are accepted. Legacy DTA/RDS synthpop files are
# intentionally excluded from this reproducible packaged-data workflow.

sp_attributes_source <- require_directory(
  file.path(data_root, "synthetic_pop", "SPindivid_CensusNTSALS_parquet"),
  "Full synthpop attributes parquet"
)
sp_trips_source <- require_directory(
  file.path(data_root, "synthetic_pop", "SPtrip_CensusNTSALS_parquet"),
  "Full synthpop trips parquet"
)
hm_overall_source <- require_directory(
  file.path(hm_root, "health_data", "processed", "sp_overall_outcomes"),
  "Full overall HM outcomes parquet"
)
hm_cycle_source <- require_directory(
  file.path(hm_root, "health_data", "processed", "sp_cycle_outcomes_death_share"),
  "Full death-share cycle HM outcomes parquet"
)

profile_root <- file.path(hub_root, "inst", "extdata", "data", "profiles", profile_id)
if (dir.exists(profile_root)) {
  if (!overwrite) {
    stop(
      "LAD profile already exists. Set MIAMA_PROFILE_OVERWRITE=true to replace it: ",
      profile_root,
      call. = FALSE
    )
  }
}


# 2. Sample LAD Individuals ----
# -----------------------------------------------------------------------------#
# Sampling occurs at person level. The effective profile weight combines the
# upstream 5% synthpop weight with the inverse of this additional subsampling.

attributes_lad <- arrow::open_dataset(sp_attributes_source) |>
  dplyr::filter(.data$lad25cd == geo_id) |>
  dplyr::collect()

if (anyDuplicated(attributes_lad$census_id)) {
  stop("Full synthpop attributes contain duplicate LAD census_id values.", call. = FALSE)
}

source_individuals <- nrow(attributes_lad)
if (sample_n > source_individuals) {
  stop(
    "Requested ", sample_n, " individuals but only ", source_individuals,
    " are available for ", geo_id, ".",
    call. = FALSE
  )
}

set.seed(seed)
selected_ids <- sort(sample(attributes_lad$census_id, sample_n, replace = FALSE))
attributes_sample <- attributes_lad |>
  dplyr::filter(.data$census_id %in% selected_ids) |>
  dplyr::arrange(.data$census_id)

geo_names <- unique(stats::na.omit(as.character(attributes_sample$lad25nm)))
if (length(geo_names) != 1L) stop("Expected exactly one LAD name.")
geo_name <- geo_names[[1]]


# 3. Subset Trips And Health Outcomes ----
# -----------------------------------------------------------------------------#
# Geography is pushed into the trip scan first. ID filtering then keeps only
# trips belonging to sampled people. Health tables are filtered by the same IDs.

trips_sample <- arrow::open_dataset(sp_trips_source) |>
  dplyr::filter(.data$lad25cd == geo_id, .data$census_id %in% selected_ids) |>
  dplyr::collect() |>
  dplyr::arrange(.data$census_id, .data$nts_tripid)

hm_overall_sample <- arrow::open_dataset(hm_overall_source) |>
  dplyr::filter(.data$census_id %in% selected_ids) |>
  dplyr::collect() |>
  dplyr::arrange(.data$census_id)

hm_cycle_sample <- arrow::open_dataset(hm_cycle_source) |>
  dplyr::filter(.data$census_id %in% selected_ids) |>
  dplyr::collect() |>
  dplyr::arrange(.data$census_id, .data$cycle)


# 4. Validate Cross-Table Alignment ----
# -----------------------------------------------------------------------------#
# Every sampled person must have overall and cycle HM records. Trip records are
# optional because people with no observed travel legitimately have no rows.

id_sets <- list(
  attributes = unique(attributes_sample$census_id),
  hm_overall = unique(hm_overall_sample$census_id),
  hm_cycle = unique(hm_cycle_sample$census_id)
)

for (name in names(id_sets)) {
  missing_ids <- setdiff(selected_ids, id_sets[[name]])
  extra_ids <- setdiff(id_sets[[name]], selected_ids)
  if (length(missing_ids) > 0L || length(extra_ids) > 0L) {
    stop(
      "LAD profile alignment failed for ", name, ": ",
      length(missing_ids), " missing and ", length(extra_ids), " extra IDs.",
      call. = FALSE
    )
  }
}

if (any(!trips_sample$census_id %in% selected_ids)) {
  stop("LAD trip subset contains IDs outside the person sample.", call. = FALSE)
}
if (anyDuplicated(hm_overall_sample$census_id) ||
    anyDuplicated(hm_cycle_sample[c("census_id", "cycle")])) {
  stop("Health outcomes contain duplicate person or person-cycle records.", call. = FALSE)
}


# 5. Write Packaged Profile And Metadata ----
# -----------------------------------------------------------------------------#

# Replace only after validating every source table.
if (dir.exists(profile_root)) unlink(profile_root, recursive = TRUE, force = TRUE)

write_profile_parquet <- function(data, relative_dir) {
  output_dir <- file.path(profile_root, relative_dir)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(
    data,
    file.path(output_dir, "part-0.parquet"),
    compression = "zstd"
  )
}

write_profile_parquet(
  attributes_sample,
  file.path("synthetic_pop", "SPindivid_CensusNTSALS_parquet")
)
write_profile_parquet(
  trips_sample,
  file.path("synthetic_pop", "SPtrip_CensusNTSALS_parquet")
)
write_profile_parquet(
  hm_overall_sample,
  file.path("health_data", "sp_overall_outcomes")
)
write_profile_parquet(
  hm_cycle_sample,
  file.path("health_data", "sp_cycle_outcomes_death_share")
)

base_person_weight <- 20
sample_fraction <- sample_n / source_individuals
effective_person_weight <- base_person_weight / sample_fraction
represented_population <- source_individuals * base_person_weight

metadata <- list(
  profile_id = profile_id,
  description = paste("Packaged", geo_name, "profile for development and published-app testing"),
  geo_level = "lad",
  geo_id = geo_id,
  geo_name = geo_name,
  seed = seed,
  sampling_method = paste("Simple random sample without replacement from all", geo_name, "synthpop individuals"),
  source_individuals = source_individuals,
  sampled_individuals = sample_n,
  sample_fraction = sample_fraction,
  base_person_weight = base_person_weight,
  effective_person_weight = effective_person_weight,
  represented_population = represented_population,
  population_weight_source = paste0(
    "Census 2021 5% synthpop weight (20) adjusted for ", geo_name, " profile sampling fraction ",
    format(sample_fraction, digits = 6)
  ),
  generated_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  sources = list(
    sp_attributes = "MIAMA_DATA_ROOT/synthetic_pop/SPindivid_CensusNTSALS_parquet",
    sp_trips = "MIAMA_DATA_ROOT/synthetic_pop/SPtrip_CensusNTSALS_parquet",
    hm_overall = "MIAMA_HM_ROOT/health_data/processed/sp_overall_outcomes",
    hm_cycle_death_share = "MIAMA_HM_ROOT/health_data/processed/sp_cycle_outcomes_death_share"
  ),
  rows = list(
    attributes = nrow(attributes_sample),
    trips = nrow(trips_sample),
    hm_overall = nrow(hm_overall_sample),
    hm_cycle_death_share = nrow(hm_cycle_sample)
  )
)
saveRDS(metadata, file.path(profile_root, "profile.rds"), version = 3)

lookup_dir <- file.path(profile_root, "lookup")
dir.create(lookup_dir, recursive = TRUE, showWarnings = FALSE)
geo_options <- data.frame(
  geo_level = "lad",
  geo_id = geo_id,
  geo_name = geo_name,
  geo_label = geo_name,
  n_individuals = sample_n,
  person_weight = effective_person_weight,
  population_size_synth_scaled = represented_population,
  population_source = metadata$population_weight_source,
  stringsAsFactors = FALSE
)
saveRDS(geo_options, file.path(lookup_dir, "geo_options.rds"), version = 3)


# 6. Report ----
# -----------------------------------------------------------------------------#

message("Built packaged ", geo_name, " profile: ", profile_root)
message("Individuals:             ", format(sample_n, big.mark = ","))
message("Trips:                   ", format(nrow(trips_sample), big.mark = ","))
message("Overall HM rows:         ", format(nrow(hm_overall_sample), big.mark = ","))
message("Death-share cycle rows: ", format(nrow(hm_cycle_sample), big.mark = ","))
message("Source expansion (metadata only): ", format(effective_person_weight, digits = 7))
message("Represented population:  ", format(represented_population, big.mark = ","))
