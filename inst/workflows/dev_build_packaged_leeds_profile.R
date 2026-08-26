# MIAMA-HUB Dev Workflow: Build Packaged Leeds Data Profile
# -----------------------------------------------------------------------------
# Purpose:
#   Create an aligned, reproducible Leeds-only runtime profile with enough
#   individuals for meaningful UI and counterfactual testing. The same sampled
#   census IDs are used for attributes, trips, overall HM outcomes, and
#   death-share cycle outcomes.
#
# Output:
#   inst/extdata/data/profiles/leeds/
#     profile.rds
#     synthetic_pop/SPindivid_CensusNTSALS_parquet/part-0.parquet
#     synthetic_pop/SPtrip_CensusNTSALS_parquet/part-0.parquet
#     health_data/sp_overall_outcomes/part-0.parquet
#     health_data/sp_cycle_outcomes_death_share/part-0.parquet
#     lookup/geo_options.rds
#
# Run:
#   MIAMA_LEEDS_OVERWRITE=true \
#     Rscript --vanilla inst/workflows/dev_build_packaged_leeds_profile.R
#
# Optional environment variables:
#   MIAMA_DATA_ROOT          Full HUB runtime data root; defaults to HUB/data.
#   MIAMA_HM_ROOT            MIAMA-HM root; defaults to sibling ../MIAMA-HM.
#   MIAMA_LEEDS_GEO_ID       Defaults to E08000035.
#   MIAMA_LEEDS_SAMPLE_N     Defaults to 5000.
#   MIAMA_LEEDS_SEED         Defaults to 20260826.
#   MIAMA_LEEDS_OVERWRITE    Must be true to replace an existing profile.


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
geo_id <- Sys.getenv("MIAMA_LEEDS_GEO_ID", unset = "E08000035")
sample_n <- as.integer(Sys.getenv("MIAMA_LEEDS_SAMPLE_N", unset = "5000"))
seed <- as.integer(Sys.getenv("MIAMA_LEEDS_SEED", unset = "20260826"))
overwrite <- env_flag("MIAMA_LEEDS_OVERWRITE")

if (is.na(sample_n) || sample_n < 1L) {
  stop("MIAMA_LEEDS_SAMPLE_N must be one positive integer.", call. = FALSE)
}
if (is.na(seed)) {
  stop("MIAMA_LEEDS_SEED must be one integer.", call. = FALSE)
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

profile_root <- file.path(hub_root, "inst", "extdata", "data", "profiles", "leeds")
if (dir.exists(profile_root)) {
  if (!overwrite) {
    stop(
      "Leeds profile already exists. Set MIAMA_LEEDS_OVERWRITE=true to replace it: ",
      profile_root,
      call. = FALSE
    )
  }
  unlink(profile_root, recursive = TRUE, force = TRUE)
}


# 2. Sample Leeds Individuals ----
# -----------------------------------------------------------------------------#
# Sampling occurs at person level. The effective profile weight combines the
# upstream 5% synthpop weight with the inverse of this additional subsampling.

attributes_leeds <- arrow::open_dataset(sp_attributes_source) |>
  dplyr::filter(.data$lad25cd == geo_id) |>
  dplyr::collect()

if (anyDuplicated(attributes_leeds$census_id)) {
  stop("Full synthpop attributes contain duplicate Leeds census_id values.", call. = FALSE)
}

source_individuals <- nrow(attributes_leeds)
if (sample_n > source_individuals) {
  stop(
    "Requested ", sample_n, " individuals but only ", source_individuals,
    " are available for ", geo_id, ".",
    call. = FALSE
  )
}

set.seed(seed)
selected_ids <- sort(sample(attributes_leeds$census_id, sample_n, replace = FALSE))
attributes_sample <- attributes_leeds |>
  dplyr::filter(.data$census_id %in% selected_ids) |>
  dplyr::arrange(.data$census_id)

geo_names <- unique(stats::na.omit(as.character(attributes_sample$lad25nm)))
geo_name <- if (length(geo_names) == 1L) geo_names else "Leeds"


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
      "Leeds profile alignment failed for ", name, ": ",
      length(missing_ids), " missing and ", length(extra_ids), " extra IDs.",
      call. = FALSE
    )
  }
}

if (any(!trips_sample$census_id %in% selected_ids)) {
  stop("Leeds trip subset contains IDs outside the person sample.", call. = FALSE)
}


# 5. Write Packaged Profile And Metadata ----
# -----------------------------------------------------------------------------#

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
  profile_id = "leeds",
  description = "Packaged Leeds-only profile for realistic development and published-app testing",
  geo_level = "lad",
  geo_id = geo_id,
  geo_name = geo_name,
  seed = seed,
  sampling_method = "Simple random sample without replacement from all Leeds synthpop individuals",
  source_individuals = source_individuals,
  sampled_individuals = sample_n,
  sample_fraction = sample_fraction,
  base_person_weight = base_person_weight,
  effective_person_weight = effective_person_weight,
  represented_population = represented_population,
  population_weight_source = paste0(
    "Census 2021 5% synthpop weight (20) adjusted for Leeds profile sampling fraction ",
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

message("Built packaged Leeds profile: ", profile_root)
message("Individuals:             ", format(sample_n, big.mark = ","))
message("Trips:                   ", format(nrow(trips_sample), big.mark = ","))
message("Overall HM rows:         ", format(nrow(hm_overall_sample), big.mark = ","))
message("Death-share cycle rows: ", format(nrow(hm_cycle_sample), big.mark = ","))
message("Effective person weight: ", format(effective_person_weight, digits = 7))
message("Represented population:  ", format(represented_population, big.mark = ","))
