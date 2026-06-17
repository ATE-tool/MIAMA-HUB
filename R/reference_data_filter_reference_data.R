# MIAMA-HUB Module: Reference Data / Filter Reference Data
# Purpose: Trim `reference_data_raw` to the relevant geography, population, or
#   trip scope implied by the current appraisal.
# Inputs: Joined reference data and a `reference_request` spec.
# Outputs: Filtered `reference_data`.
# Notes: This layer should mainly affect rows and columns on the status-quo
#   data, not create counterfactual changes.

filter_reference_data <- function(reference_data_raw, reference_request = list()) {
  assert_named_list(reference_data_raw, "reference_data_raw")
  assert_named_list(reference_request, "reference_request")

  ind <- reference_data_raw$ind
  trips <- reference_data_raw$trips

  geo_level <- reference_request$geo_level
  geo_id <- reference_request$geo_id

  if (!is.null(geo_level) && !identical(geo_level, "eng") && !is.null(geo_id)) {
    geo_col <- switch(
      geo_level,
      reg = "region",
      lad = "lad25cd",
      glads = "lad25cd",
      msoa = "msoa11cd",
      stop("Unsupported geo_level: ", geo_level, call. = FALSE)
    )

    if (!geo_col %in% names(ind)) {
      stop("Geography column not found in individual-level data: ", geo_col, call. = FALSE)
    }
    if (!geo_col %in% names(trips)) {
      stop("Geography column not found in trip-level data: ", geo_col, call. = FALSE)
    }

    ind <- ind[ind[[geo_col]] %in% geo_id, , drop = FALSE]
    trips <- trips[trips[[geo_col]] %in% geo_id, , drop = FALSE]
  }

  list(
    ind = ind,
    trips = trips,
    reference_request = reference_request,
    filter_report = list(
      geo_level = geo_level,
      geo_id = geo_id,
      n_ind = nrow(ind),
      n_trips = nrow(trips)
    )
  )
}
