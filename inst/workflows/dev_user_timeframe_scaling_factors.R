# MIAMA-HUB Dev Workflow: Estimate User Timeframe Scaling Factors
# -----------------------------------------------------------------------------
# Purpose:
#   Explore pragmatic scaling factors for distinct active-mode users when UI
#   users_count values are requested for day/week/year. The current synthetic
#   population contains one-week travel patterns, so this script estimates daily
#   and yearly distinct-user counts from weekly trip counts using explicit
#   assumptions.
#
# Assumptions:
#   - Use the full England synthetic-population trips parquet, not the packaged
#     sample data.
#   - Ignore `weight_tripXhh` for now.
#   - One active day is represented by at least `trips_per_active_day` trips in
#     that mode; default is 2 trips/day.
#   - There are `active_weeks_per_year` exposure weeks; default is 48.
#   - Weekly user status is observed as `trips_per_week > 0`.
#   - Yearly user status is modelled as `1 - (1 - p_active_week)^active_weeks`.
#
# Outputs:
#   - `user_timeframe_scaling_summary`: compact national factors for walk/bike.
#   - `user_timeframe_scaling_detail`: per-person intermediate values.


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
  library(dplyr)
  library(tidyr)
  library(arrow)
})

sp_trips_path <- file.path(
  hub_root,
  "data",
  "synthetic_pop",
  "SPtrip_CensusNTSALS_parquet"
)

if (!dir.exists(sp_trips_path)) {
  stop("Full SP trips parquet not found: ", sp_trips_path, call. = FALSE)
}

trips_per_active_day <- 2
active_weeks_per_year <- 48


# 1. Load Weekly Mode Trip Counts ----
# -----------------------------------------------------------------------------#
# Count physical trip rows per synthetic individual and mode. We intentionally
# ignore `weight_tripXhh` in this exploration.

sp_trips <- arrow::open_dataset(sp_trips_path, format = "parquet")

trip_counts <- sp_trips |>
  dplyr::transmute(
    census_id,
    walk_trip = !is.na(nts_tripid) &
      ((trip_walktime_min > 0) | (trip_walkdist_km > 0)),
    bike_trip = !is.na(nts_tripid) &
      ((trip_cycletime_min > 0) | (trip_cycledist_km > 0))
  ) |>
  dplyr::group_by(census_id) |>
  dplyr::summarise(
    walk_trips_week = sum(walk_trip, na.rm = TRUE),
    bike_trips_week = sum(bike_trip, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::collect()


# 2. Estimate Daily And Yearly User Probabilities ----
# -----------------------------------------------------------------------------#
# Daily use is estimated from active days implied by weekly trips. Yearly use is
# a deliberately simple repeated-week model using the observed weekly user
# probability proxy.

user_timeframe_scaling_detail <- trip_counts |>
  tidyr::pivot_longer(
    cols = c(walk_trips_week, bike_trips_week),
    names_to = "mode",
    values_to = "trips_week"
  ) |>
  dplyr::mutate(
    mode = dplyr::recode(
      mode,
      walk_trips_week = "walk",
      bike_trips_week = "bike"
    ),
    user_week = trips_week > 0,
    active_days_week = pmin(trips_week / trips_per_active_day, 7),
    p_active_day = active_days_week / 7,
    p_active_week_proxy = pmin(active_days_week / 7, 1),
    p_active_year = 1 - (1 - p_active_week_proxy) ^ active_weeks_per_year
  )


# 3. Summarise Scaling Factors ----
# -----------------------------------------------------------------------------#

user_timeframe_scaling_summary <- user_timeframe_scaling_detail |>
  dplyr::group_by(mode) |>
  dplyr::summarise(
    n_individuals = dplyr::n(),
    users_week = sum(user_week),
    users_day_est = sum(p_active_day),
    users_year_est = sum(p_active_year),
    factor_week_to_day = users_day_est / users_week,
    factor_week_to_year = users_year_est / users_week,
    mean_trips_week_among_week_users = mean(trips_week[user_week]),
    median_trips_week_among_week_users = stats::median(trips_week[user_week]),
    trips_per_active_day_assumption = trips_per_active_day,
    active_weeks_per_year_assumption = active_weeks_per_year,
    .groups = "drop"
  )

print(user_timeframe_scaling_summary)


# 4. Optional Inspection ----
# -----------------------------------------------------------------------------#

user_timeframe_scaling_quantiles <- user_timeframe_scaling_detail |>
  dplyr::filter(user_week) |>
  dplyr::group_by(mode) |>
  dplyr::summarise(
    trips_week_p25 = unname(stats::quantile(trips_week, 0.25, na.rm = TRUE)),
    trips_week_p50 = unname(stats::quantile(trips_week, 0.50, na.rm = TRUE)),
    trips_week_p75 = unname(stats::quantile(trips_week, 0.75, na.rm = TRUE)),
    active_days_week_p25 = unname(stats::quantile(active_days_week, 0.25, na.rm = TRUE)),
    active_days_week_p50 = unname(stats::quantile(active_days_week, 0.50, na.rm = TRUE)),
    active_days_week_p75 = unname(stats::quantile(active_days_week, 0.75, na.rm = TRUE)),
    .groups = "drop"
  )

print(user_timeframe_scaling_quantiles)
