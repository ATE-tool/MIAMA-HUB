# MIAMA-HUB Dev Workflow: England-Derived Assumption Candidates
# -----------------------------------------------------------------------------
# Purpose:
#   Derive stable, reviewable candidates for numeric MIAMA-UI defaults from the
#   full England synthetic population. This workflow is run explicitly when the
#   source data or assumptions change; app sessions only consume the packaged
#   outputs and never recreate them.
#
# Outputs:
#   - `inst/extdata/data/lookup/england_mode_default_candidates.csv`: source
#     metrics by mode and measurement basis.
#   - `inst/extdata/data/lookup/england_schema_default_candidates.csv`:
#     candidate values mapped to current UI field names, with review status.
#
# Important definitions:
#   - Walking/cycling "active_component" metrics use the mode-specific distance
#     and duration components, matching existing HUB reference calculations.
#   - Car/PT "main_mode" metrics use mutually exclusive NTS MainMode_B04 codes
#     and raw trip distance/duration.
#   - E-bike cannot be separated from bicycle in MainMode_B04 and is reported as
#     unavailable rather than assigned the bicycle result automatically.
#   - `distdur_default_*` currently represents both distance and duration in the
#     UI. Both candidates are emitted and marked `needs_schema_split`.
#
# Memory:
#   Filtering and aggregation stay in Arrow. Only one-row summaries and distinct
#   user counts are collected into R, avoiding full England materialization.
#
# Run:
#   Rscript --vanilla inst/workflows/dev_extract_england_schema_default_values.R


# 0. Setup ----
# -----------------------------------------------------------------------------#

find_miama_hub_root <- function(start = getwd()) {
  env_root <- Sys.getenv("MIAMA_PROJECT_ROOT", unset = "")
  candidates <- unique(c(
    env_root[nzchar(env_root)], start, file.path(start, "MIAMA-HUB"),
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

external_data_root <- Sys.getenv("MIAMA_DATA_ROOT", unset = "")
if (!nzchar(external_data_root)) {
  stop(
    "Set MIAMA_DATA_ROOT to the external directory containing full synthpop data.",
    call. = FALSE
  )
}
external_data_root <- normalizePath(external_data_root, winslash = "/", mustWork = FALSE)

sp_attributes_path <- file.path(external_data_root, "synthetic_pop", "SPindivid_CensusNTSALS_parquet")
sp_trips_path <- file.path(external_data_root, "synthetic_pop", "SPtrip_CensusNTSALS_parquet")
output_dir <- file.path(hub_root, "inst", "extdata", "data", "lookup")

if (!dir.exists(sp_attributes_path)) stop("Full SP attributes parquet not found: ", sp_attributes_path, call. = FALSE)
if (!dir.exists(sp_trips_path)) stop("Full SP trips parquet not found: ", sp_trips_path, call. = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

sp_attributes <- arrow::open_dataset(sp_attributes_path, format = "parquet")
sp_trips <- arrow::open_dataset(sp_trips_path, format = "parquet")


# 1. Arrow Summary Helpers ----
# -----------------------------------------------------------------------------#

count_attribute_users <- function(data, activity_col) {
  data |>
    dplyr::filter(.data[[activity_col]] > 0) |>
    dplyr::summarise(n_users = dplyr::n()) |>
    dplyr::collect() |>
    dplyr::pull(n_users)
}

summarise_mode <- function(
    mode,
    analysis_basis,
    trips,
    filter_expression,
    distance_col,
    duration_col,
    mode_definition,
    n_week_users_ind = NA_real_
) {
  distance_sym <- rlang::sym(distance_col)
  duration_sym <- rlang::sym(duration_col)
  filtered <- trips |>
    dplyr::filter(!is.na(.data$nts_tripid), !!filter_expression)

  summary <- filtered |>
    dplyr::summarise(
      n_trip_rows = dplyr::n(),
      total_week_trips_weighted = sum(.data$weight_tripXhh, na.rm = TRUE)
    ) |>
    dplyr::collect()

  # The parquet source uses IEEE NaN as well as Arrow nulls. Filtering finite
  # measurements before summing avoids NaN propagation and Arrow conditional
  # aggregation differences.
  distance_summary <- filtered |>
    dplyr::filter(is.finite(!!distance_sym), is.finite(.data$weight_tripXhh)) |>
    dplyr::summarise(
      total = sum((!!distance_sym) * .data$weight_tripXhh, na.rm = TRUE),
      weight = sum(.data$weight_tripXhh, na.rm = TRUE)
    ) |>
    dplyr::collect()

  duration_summary <- filtered |>
    dplyr::filter(is.finite(!!duration_sym), is.finite(.data$weight_tripXhh)) |>
    dplyr::summarise(
      total = sum((!!duration_sym) * .data$weight_tripXhh, na.rm = TRUE),
      weight = sum(.data$weight_tripXhh, na.rm = TRUE)
    ) |>
    dplyr::collect()

  n_trip_users <- filtered |>
    dplyr::distinct(.data$census_id) |>
    dplyr::summarise(n_users = dplyr::n()) |>
    dplyr::collect() |>
    dplyr::pull(n_users)

  n_rate_users <- if (is.finite(n_week_users_ind) && n_week_users_ind > 0) {
    n_week_users_ind
  } else {
    n_trip_users
  }

  mean_distance <- distance_summary$total / distance_summary$weight
  mean_duration <- duration_summary$total / duration_summary$weight

  data.frame(
    mode = mode,
    analysis_basis = analysis_basis,
    mode_definition = mode_definition,
    availability = "derived",
    n_trip_rows = summary$n_trip_rows,
    n_week_users_ind = n_week_users_ind,
    n_week_users_from_trips = n_trip_users,
    total_week_trips_weighted = summary$total_week_trips_weighted,
    trips_per_week_user = summary$total_week_trips_weighted / n_rate_users,
    mean_trip_distance_km = mean_distance,
    mean_trip_duration_min = mean_duration,
    mean_speed_kmh = mean_distance / (mean_duration / 60),
    total_distance_week_km = distance_summary$total,
    total_duration_week_min = duration_summary$total,
    distance_per_week_user_km = distance_summary$total / n_rate_users,
    duration_per_week_user_min = duration_summary$total / n_rate_users,
    stringsAsFactors = FALSE
  )
}


# 2. England Mode Metrics ----
# -----------------------------------------------------------------------------#

n_walk_users <- count_attribute_users(sp_attributes, "walktime_wkhr")
n_bike_users <- count_attribute_users(sp_attributes, "cycletime_wkhr")

mode_candidates <- dplyr::bind_rows(
  summarise_mode(
    "walk", "active_component", sp_trips,
    rlang::expr(.data$trip_walktime_min > 0 | .data$trip_walkdist_km > 0),
    "trip_walkdist_km", "trip_walktime_min",
    "Positive walking component; distance/time from walking component columns.",
    n_walk_users
  ),
  summarise_mode(
    "bike", "active_component", sp_trips,
    rlang::expr(.data$trip_cycletime_min > 0 | .data$trip_cycledist_km > 0),
    "trip_cycledist_km", "trip_cycletime_min",
    "Positive cycling component; distance/time from cycling component columns.",
    n_bike_users
  ),
  summarise_mode(
    "walk", "main_mode", sp_trips,
    rlang::expr(.data$trip_mainmode == !!MIAMA_NTS_MAINMODE_B04[["walk"]]),
    "trip_distraw_km", "trip_durationraw_min", "NTS MainMode_B04ID 1 (walk)."
  ),
  summarise_mode(
    "bike", "main_mode", sp_trips,
    rlang::expr(.data$trip_mainmode == !!MIAMA_NTS_MAINMODE_B04[["bicycle"]]),
    "trip_distraw_km", "trip_durationraw_min", "NTS MainMode_B04ID 2 (bicycle)."
  ),
  summarise_mode(
    "car", "main_mode", sp_trips,
    rlang::expr(.data$trip_mainmode %in% c(3, 4)),
    "trip_distraw_km", "trip_durationraw_min",
    "NTS MainMode_B04ID 3-4 (car/van driver or passenger)."
  ),
  summarise_mode(
    "pt", "main_mode", sp_trips,
    rlang::expr(.data$trip_mainmode %in% !!MIAMA_NTS_MAINMODE_PT_CODES),
    "trip_distraw_km", "trip_durationraw_min",
    "NTS MainMode_B04 public-transport codes 7-11 and 13."
  )
)

ebike_unavailable <- mode_candidates[1, , drop = FALSE]
ebike_unavailable[1, ] <- NA
ebike_unavailable$mode <- "ebike"
ebike_unavailable$analysis_basis <- "unavailable"
ebike_unavailable$mode_definition <- paste(
  "E-bike is included in NTS MainMode_B04 bicycle code 2 and cannot be",
  "separated in the current synthetic-population trip data."
)
ebike_unavailable$availability <- "not_derivable"
mode_candidates <- dplyr::bind_rows(mode_candidates, ebike_unavailable)


# 3. Map Metrics To Current UI Fields ----
# -----------------------------------------------------------------------------#

pick_metric <- function(mode, basis, metric) {
  row <- mode_candidates[
    mode_candidates$mode == mode & mode_candidates$analysis_basis == basis,
    ,
    drop = FALSE
  ]
  if (nrow(row) == 0) return(NA_real_)
  as.numeric(row[[metric]][1])
}

candidate_row <- function(
    field,
    mode,
    metric,
    basis,
    status = "candidate_for_review",
    note = ""
) {
  raw_value <- pick_metric(mode, basis, metric)
  if (!is.finite(raw_value)) status <- "not_derivable"
  data.frame(
    schema_field = field,
    mode = mode,
    source_metric = metric,
    analysis_basis = basis,
    raw_candidate_value = raw_value,
    suggested_rounded_value = if (is.finite(raw_value)) round(raw_value, 2) else NA_real_,
    status = status,
    review_note = note,
    stringsAsFactors = FALSE
  )
}

schema_candidates <- list()
add_candidate <- function(...) {
  schema_candidates[[length(schema_candidates) + 1L]] <<- candidate_row(...)
}

for (mode in c("walk", "bike", "pt", "ebike")) {
  basis <- if (mode %in% c("walk", "bike")) "active_component" else if (mode == "pt") "main_mode" else "unavailable"
  unavailable_note <- if (mode == "ebike") {
    "Current MainMode_B04 data combine e-bike with bicycle; retain an explicit reviewed assumption."
  } else ""

  add_candidate(paste0("default_trips_per_user_per_week_", mode), mode, "trips_per_week_user", basis, note = unavailable_note)

  add_candidate(
    paste0("distdur_default_", mode), mode, "distance_per_week_user_km", basis,
    status = "needs_schema_split",
    note = paste("Distance candidate in km per weekly user.", unavailable_note)
  )
  add_candidate(
    paste0("distdur_default_", mode), mode, "duration_per_week_user_min", basis,
    status = "needs_schema_split",
    note = paste("Duration candidate in minutes per weekly user; the current field cannot represent both units.", unavailable_note)
  )
}

for (mode in c("walk", "bike", "pt", "car", "ebike")) {
  basis <- if (mode %in% c("walk", "bike")) "active_component" else if (mode %in% c("pt", "car")) "main_mode" else "unavailable"
  unavailable_note <- if (mode == "ebike") {
    "Not separately observable; do not copy the bicycle value without an explicit assumption decision."
  } else ""

  add_candidate(paste0("default_trip_distance_", mode), mode, "mean_trip_distance_km", basis, note = unavailable_note)
  add_candidate(paste0("assump_trip_speed_", mode), mode, "mean_speed_kmh", basis, note = unavailable_note)
}

schema_candidates <- dplyr::bind_rows(schema_candidates)


# 4. Write Review Tables ----
# -----------------------------------------------------------------------------#

mode_output <- file.path(output_dir, "england_mode_default_candidates.csv")
schema_output <- file.path(output_dir, "england_schema_default_candidates.csv")

utils::write.csv(mode_candidates, mode_output, row.names = FALSE)
utils::write.csv(schema_candidates, schema_output, row.names = FALSE)

message("Wrote England mode metrics to: ", mode_output)
message("Wrote UI schema candidates to: ", schema_output)
print(mode_candidates)
print(schema_candidates)
