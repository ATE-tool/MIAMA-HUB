# MIAMA-HUB Module: Reference Data / Join HM and Synthetic Population
# Purpose: Join HM outcomes onto SP attributes and align the matching SP trips
#   without repeating wide health-outcome columns on every trip row.
# Inputs:  Named list from `load_reference_sources()`.
# Outputs: Named list with:
#   - `ind`    : individual-level data (hm_outcomes left-joined onto sp_attributes)
#   - `trips`  : matching SP trip rows plus one NA trip row for people without trips
#   - `join_report` : summary of match rates for both joins

join_hm_and_synthpop <- function(reference_sources) {
  assert_named_list(reference_sources, "reference_sources")

  hm  <- reference_sources$hm_outcomes
  spa <- reference_sources$sp_attributes
  spt <- reference_sources$sp_trips

  duplicated_hm_ids <- duplicated(hm$census_id) | duplicated(hm$census_id, fromLast = TRUE)
  if (any(duplicated_hm_ids)) {
    stop(
      "HM reference outcomes must contain one row per `census_id`; found ",
      length(unique(hm$census_id[duplicated_hm_ids])),
      " duplicated IDs. Cycle-level HM outcomes must be joined after ",
      "counterfactual exposure is built, not to individual/trip reference data.",
      call. = FALSE
    )
  }

  # --- Individual-level join: hm_outcomes -> sp_attributes -----------------
  ind <- dplyr::left_join(hm, spa, by = "census_id")

  n_hm        <- nrow(hm)
  n_matched   <- sum(!is.na(ind$nts_id))
  n_unmatched <- n_hm - n_matched
  pct_matched <- round(100 * n_matched / n_hm, 1)

  message(sprintf(
    "HM -> SP attributes join: %d / %d matched (%.1f%%) | %d unmatched",
    n_matched, n_hm, pct_matched, n_unmatched
  ))

  # --- Trip-level alignment ------------------------------------------------
  # SP trips already contains the person attributes needed by trip sampling.
  # Joining the complete HM-enriched individual table here repeats every HM
  # outcome column for every trip and causes severe memory growth on full data.
  # A one-column left join retains one NA trip row for people without trips,
  # matching the previous row contract without duplicating wide person data.
  trips <- dplyr::left_join(
    ind[, "census_id", drop = FALSE],
    spt,
    by = "census_id"
  )

  n_ind           <- nrow(ind)
  n_trips_total   <- nrow(trips)
  n_trips_matched <- sum(!is.na(trips$nts_tripid))
  pct_trips       <- round(100 * n_trips_matched / n_trips_total, 1)

  message(sprintf(
    "Ind -> SP trips join: %d individuals -> %d trip rows | %d matched (%.1f%%)",
    n_ind, n_trips_total, n_trips_matched, pct_trips
  ))

  join_report <- list(
    ind = list(
      n_hm_outcomes = n_hm,
      n_matched = n_matched,
      n_unmatched = n_unmatched,
      pct_matched = pct_matched
    ),
    trips = list(
      n_individuals = n_ind,
      n_trip_rows = n_trips_total,
      n_matched = n_trips_matched,
      pct_matched = pct_trips
    )
  )

  list(
    ind = ind,
    trips = trips,
    join_report = join_report
  )
}
