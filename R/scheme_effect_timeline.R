# Scheme lifetime is an appraisal parameter, not a sampling constraint or a
# financial discount rate. Tab 2 volumes describe the maximum-effect snapshot.
.scheme_effect_parameters <- function(profile) {
  values <- if (any(vapply(profile, is.list, logical(1)))) extract_input_values(profile) else profile
  read_year <- function(id, fallback) {
    x <- values[[id]] %||% fallback
    if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x < 0 || x != floor(x)) {
      stop(id, " must be a non-negative whole year since scheme start.", call. = FALSE)
    }
    x
  }
  peak <- read_year("scheme_peak_year", 1)
  permanent <- values$scheme_no_decline %||% TRUE
  if (!is.logical(permanent) || length(permanent) != 1L || is.na(permanent)) {
    stop("scheme_no_decline must be TRUE or FALSE.", call. = FALSE)
  }
  decline <- end <- Inf
  if (!permanent) {
    decline <- read_year("scheme_decline_year", 10)
    end <- read_year("scheme_end_year", 20)
    if (decline < peak || end <= decline) {
      stop("Scheme years must satisfy: maximum effect <= decline starts < zero effect.", call. = FALSE)
    }
  }
  list(peak = peak, permanent = permanent, decline = decline, end = end)
}

# Read-only, field-keyed summary of the same effective settings used for math.
get_scheme_effect_summary <- function(profile = list()) {
  p <- .scheme_effect_parameters(profile)
  peak <- if (p$peak == 0) "Maximum effect immediately" else paste("Maximum effect at year", p$peak)
  if (p$permanent) {
    return(c(scheme_peak_year = peak, scheme_no_decline = "No decline"))
  }
  c(scheme_peak_year = peak,
    scheme_decline_year = paste("Decline starts at year", p$decline),
    scheme_end_year = paste("Zero effect at year", p$end))
}

get_scheme_effect_timeline <- function(profile = list(), cycles = 0:40) {
  p <- .scheme_effect_parameters(profile)
  peak <- p$peak
  permanent <- p$permanent
  decline <- p$decline
  end <- p$end
  if (!is.numeric(cycles) || any(!is.finite(cycles) | cycles < 0 | cycles != floor(cycles))) {
    stop("Scheme cycles must be non-negative whole years.", call. = FALSE)
  }
  # With integer breakpoints, trapezoidal integration is exact for each year.
  effect <- function(t) {
    growth <- if (peak == 0) rep(1, length(t)) else pmin(t / peak, 1)
    if (permanent) growth else pmax(0, pmin(growth, (end - t) / (end - decline)))
  }
  factor <- (effect(pmax(0, cycles - 1)) + effect(cycles)) / 2
  factor[cycles == 0] <- 0 # Baseline informs health state, never scheme benefit.
  data.frame(cycle = cycles, effect_factor = factor, effect_at_year_end = effect(cycles))
}

# Apply the curve once, AFTER full-effect HALYs have been calculated. Scaling
# exposure before a nonlinear health lookup would be a different model.
.scale_scheme_health_outcomes <- function(x, timeline) {
  factor <- timeline$effect_factor[match(x$cycle, timeline$cycle)]
  if (anyNA(factor)) stop("Scheme timeline does not cover every health cycle.", call. = FALSE)
  x$scheme_effect_factor <- factor
  # LY/HLY exports reconstruct occupancy from net transitions. Keep full-effect
  # transitions so those exports can scale annual occupancy differences, rather
  # than accidentally accumulating scaled transitions past the scheme end.
  for (outcome in c("dead", "unhealthy")) {
    delta <- paste0("d_", outcome)
    if (delta %in% names(x)) x[[paste0("scheme_full_", delta)]] <- x[[delta]]
  }
  for (delta in grep("^d_", names(x), value = TRUE)) {
    x[[delta]] <- x[[delta]] * factor
    x[[delta]][factor == 0] <- 0
    ref <- sub("^d_", "", delta)
    cf <- paste0(ref, "_cf")
    if (cf %in% names(x) && ref %in% names(x)) x[[cf]] <- x[[ref]] + x[[delta]]
  }
  x
}
