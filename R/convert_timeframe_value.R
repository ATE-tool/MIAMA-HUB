# MIAMA-HUB Module: Timeframe Value Converter
# Purpose: Provide one public day/week/year conversion used by HUB and MIAMA-UI.
#
# Trip values and other quantities that accumulate linearly over time use
# calendar conversion factors. Distinct-user values currently use factor 1 for
# every timeframe; this explicit assumption can be replaced when empirical
# user-period conversion factors become available.

#' Convert A Period-Based Value Between Timeframes
#'
#' Converts a numeric value expressed per day, week, or year to another of
#' those timeframes. Trip values use calendar conversion factors. User values
#' currently remain unchanged across timeframes under the provisional factor-1
#' assumption. HUB and UI use this function as the single source of truth.
#'
#' @param old_timeframe Timeframe currently represented by `old_value`.
#'   One of `"day"`, `"week"`, or `"year"`.
#' @param old_value One finite numeric linearly accumulating value.
#' @param new_timeframe Desired timeframe. One of `"day"`, `"week"`, or
#'   `"year"`.
#' @param datatype Type of value being converted. `"trips"` applies linear
#'   calendar conversion and is also appropriate for total distance or duration.
#'   `"users"` currently applies factor 1 across all timeframes.
#'
#' @return A length-one numeric value in `new_timeframe` units.
#' @export
convert_timeframe_value <- function(old_timeframe,
                                    old_value,
                                    new_timeframe,
                                    datatype = c("trips", "users")) {
  old_timeframe <- .validate_timeframe_value(old_timeframe, "old_timeframe")
  new_timeframe <- .validate_timeframe_value(new_timeframe, "new_timeframe")
  datatype <- match.arg(datatype)

  if (!is.numeric(old_value) || length(old_value) != 1 ||
      !is.finite(old_value)) {
    stop("`old_value` must be one finite numeric value.", call. = FALSE)
  }

  if (identical(datatype, "users")) {
    return(as.numeric(old_value))
  }

  weekly_value <- as.numeric(old_value) / .timeframe_value_factor(old_timeframe)
  weekly_value * .timeframe_value_factor(new_timeframe)
}

.validate_timeframe_value <- function(timeframe, argument) {
  if (is.null(timeframe) || length(timeframe) != 1 || is.na(timeframe)) {
    stop("`", argument, "` must be one of: day, week, year.", call. = FALSE)
  }

  timeframe <- tolower(trimws(as.character(timeframe)))
  if (!timeframe %in% c("day", "week", "year")) {
    stop("`", argument, "` must be one of: day, week, year.", call. = FALSE)
  }
  timeframe
}

.timeframe_value_factor <- function(timeframe) {
  switch(
    timeframe,
    day = 1 / 7,
    week = 1,
    year = 52.1775
  )
}
