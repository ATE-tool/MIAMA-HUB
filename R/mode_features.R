# MIAMA-HUB Mode Features ---------------------------------------------------
#
# Adds the derived columns needed to treat walking, cycling, e-biking, and
# walk-to-public-transport consistently without changing source files.
# E-bike reference volume is deliberately zero because the source combines
# conventional and electric bicycles. Cycling observations remain available as
# donor patterns for counterfactual e-bike changes. PT activity is the walking
# access component of public-transport main-mode trips.

.miama_supported_modes <- function() {
  c("walking", "cycling", "ebiking", "pt")
}

.prepare_mode_features <- function(data) {
  if (is.null(data)) return(data)

  out <- data
  if (!is.null(out$trips)) {
    trips <- out$trips
    n <- nrow(trips)
    if (!"trip_ebikedist_km" %in% names(trips)) {
      trips$trip_ebikedist_km <- rep(0, n)
    }
    if (!"trip_ebiketime_min" %in% names(trips)) {
      trips$trip_ebiketime_min <- rep(0, n)
    }
    out$trips <- trips
  }

  if (!is.null(out$ind)) {
    ind <- out$ind
    n <- nrow(ind)
    if (!"ebiketime_wkhr" %in% names(ind)) {
      ind$ebiketime_wkhr <- rep(0, n)
    }
    if (!"ebikedist_wkkm" %in% names(ind)) {
      ind$ebikedist_wkkm <- rep(0, n)
    }

    if (!"pttime_wkhr" %in% names(ind)) {
      ind$pttime_wkhr <- .person_pt_component(
        ind, out$trips, "trip_walktime_min", divisor = 60
      )
    }
    if (!"ptdist_wkkm" %in% names(ind)) {
      ind$ptdist_wkkm <- .person_pt_component(
        ind, out$trips, "trip_walkdist_km", divisor = 1
      )
    }
    out$ind <- ind
  }

  out
}

.person_pt_component <- function(ind, trips, column, divisor) {
  out <- rep(0, nrow(ind))
  if (is.null(trips) || !"census_id" %in% names(ind) ||
      !"census_id" %in% names(trips) || !column %in% names(trips)) {
    return(out)
  }

  keep <- .pt_trip_filter(trips) & !is.na(trips$census_id)
  values <- .as_plain_numeric(trips[[column]])
  values[!is.finite(values) | values < 0] <- 0
  if (!any(keep & values > 0)) return(out)

  totals <- stats::aggregate(
    values[keep] / divisor,
    by = list(census_id = trips$census_id[keep]),
    FUN = sum,
    na.rm = TRUE
  )
  matched <- match(ind$census_id, totals$census_id)
  found <- !is.na(matched)
  out[found] <- totals$x[matched[found]]
  out
}

.mode_proxy_spec <- function(spec) {
  proxy <- spec$proxy_mode %||% NULL
  if (is.null(proxy)) spec else .counterfactual_mode_spec(proxy)
}

.mode_reference_trip_filter <- function(trips, spec, allow_proxy = FALSE) {
  keep <- spec$trip_filter(trips)
  if (isTRUE(allow_proxy) && !any(keep, na.rm = TRUE) && !is.null(spec$proxy_mode)) {
    keep <- .counterfactual_mode_spec(spec$proxy_mode)$trip_filter(trips)
  }
  keep
}

