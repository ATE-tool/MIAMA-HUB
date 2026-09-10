# Division can place an exact count a few machine-precision steps above its
# integer (e.g. 695 / (695 / 155)). Snap only that numerical noise, not genuine
# fractional users. A positive fraction near zero must still require one user.
.sampling_count_ceiling <- function(x) {
  nearest <- round(x)
  tolerance <- 8 * .Machine$double.eps * pmax(1, abs(x))
  snap <- is.finite(x) & nearest > 0 & abs(x - nearest) <= tolerance
  x[snap] <- nearest[snap]
  as.integer(ceiling(x))
}
