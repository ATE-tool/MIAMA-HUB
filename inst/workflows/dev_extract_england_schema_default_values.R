# MIAMA-HUB Dev Workflow: Extract Candidate Schema Defaults From England Data
# -----------------------------------------------------------------------------
# Purpose:
#   Produce review tables for UI schema defaults such as average active trip
#   lengths, speeds, and trips per active user. This script is exploratory: it
#   reads the full England synthetic-population parquet data when available and
#   writes compact CSV outputs under `data/lookup/` for review before any values
#   are copied into MIAMA-UI `schemes/default.R`.
#
# Notes:
#   - This script reads full local data from `data/synthetic_pop/`.
#   - It ignores population scaling and uses `weight_tripXhh` where available
#     for trip totals and means.
#   - It does not edit MIAMA-UI.
#   - From a shell, prefer:
#       Rscript --vanilla inst/workflows/dev_extract_england_schema_default_values.R


# 0. Setup ----
# -----------------------------------------------------------------------------#

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

  stop("Could not find MIAMA-HUB package root. Set MIAMA_PROJECT_ROOT.", call. = FALSE)
}

hub_root <- find_miama_hub_root()
devtools::load_all(hub_root)

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

cfg <- miama_default_config()
cfg$workflow$dataset_size <- "full"

sp_attributes_path <- file.path(hub_root, "data", "synthetic_pop", "SPindivid_CensusNTSALS_parquet")
sp_trips_path <- file.path(hub_root, "data", "synthetic_pop", "SPtrip_CensusNTSALS_parquet")
output_dir <- file.path(hub_root, "data", "lookup")

if (!dir.exists(sp_attributes_path)) {
  stop("Full SP attributes parquet not found: ", sp_attributes_path, call. = FALSE)
}
if (!dir.exists(sp_trips_path)) {
  stop("Full SP trips parquet not found: ", sp_trips_path, call. = FALSE)
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)


# 1. Load Compact England Tables ----
# -----------------------------------------------------------------------------#
# Collect only columns needed for review summaries. This keeps the review script
# smaller than a full reference-data build.

sp_attributes <- arrow::open_dataset(sp_attributes_path, format = "parquet") |>
  dplyr::select(census_id, walktime_wkhr, cycletime_wkhr) |>
  dplyr::collect()

sp_trips <- arrow::open_dataset(sp_trips_path, format = "parquet") |>
  dplyr::select(
    census_id,
    nts_tripid,
    weight_tripXhh,
    trip_mainmode,
    trip_walkdist_km,
    trip_walktime_min,
    trip_cycledist_km,
    trip_cycletime_min,
    trip_distraw_km,
    trip_durationraw_min
  ) |>
  dplyr::collect()


# 2. Define Mode Classifiers ----
# -----------------------------------------------------------------------------#

positive <- function(x) !is.na(x) & x > 0

mode_trip_flags <- list(
  walk = positive(sp_trips$trip_walktime_min) | positive(sp_trips$trip_walkdist_km),
  bike = positive(sp_trips$trip_cycletime_min) | positive(sp_trips$trip_cycledist_km)
)

mode_user_flags <- list(
  walk = positive(sp_attributes$walktime_wkhr),
  bike = positive(sp_attributes$cycletime_wkhr)
)

trip_weights <- if ("weight_tripXhh" %in% names(sp_trips)) {
  weights <- as.numeric(sp_trips$weight_tripXhh)
  weights[is.na(weights)] <- 0
  weights
} else {
  rep(1, nrow(sp_trips))
}


# 3. Summarise Candidate Defaults ----
# -----------------------------------------------------------------------------#

weighted_sum <- function(x, keep) {
  sum(as.numeric(x)[keep] * trip_weights[keep], na.rm = TRUE)
}

weighted_mean <- function(x, keep) {
  denom <- sum(trip_weights[keep], na.rm = TRUE)
  if (denom == 0) return(NA_real_)
  weighted_sum(x, keep) / denom
}

candidate_defaults <- do.call(
  rbind,
  lapply(names(mode_trip_flags), function(mode) {
    trip_keep <- mode_trip_flags[[mode]] & !is.na(sp_trips$nts_tripid)
    user_keep <- mode_user_flags[[mode]]
    user_ids_from_trips <- unique(sp_trips$census_id[trip_keep])
    n_users <- sum(user_keep, na.rm = TRUE)
    n_trip_users <- length(user_ids_from_trips)
    n_users_for_rate <- if (n_users > 0) n_users else n_trip_users

    distance_col <- switch(
      mode,
      walk = "trip_walkdist_km",
      bike = "trip_cycledist_km"
    )
    duration_col <- switch(
      mode,
      walk = "trip_walktime_min",
      bike = "trip_cycletime_min"
    )

    total_trips <- weighted_sum(rep(1, nrow(sp_trips)), trip_keep)
    mean_distance_km <- weighted_mean(sp_trips[[distance_col]], trip_keep)
    mean_duration_min <- weighted_mean(sp_trips[[duration_col]], trip_keep)

    data.frame(
      mode = mode,
      n_week_users_ind = n_users,
      n_week_users_from_trips = n_trip_users,
      total_week_trips_weighted = total_trips,
      trips_per_week_user = total_trips / n_users_for_rate,
      mean_trip_distance_km = mean_distance_km,
      mean_trip_duration_min = mean_duration_min,
      mean_speed_kmh = if (is.na(mean_duration_min) || mean_duration_min == 0) {
        NA_real_
      } else {
        mean_distance_km / (mean_duration_min / 60)
      },
      stringsAsFactors = FALSE
    )
  })
)

output_path <- file.path(output_dir, "england_schema_default_candidates.csv")
utils::write.csv(candidate_defaults, output_path, row.names = FALSE)

message("Wrote candidate defaults to: ", output_path)
print(candidate_defaults)
