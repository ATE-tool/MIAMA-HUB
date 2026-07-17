# MIAMA-HUB Module: Arrow Runtime Helpers
# Purpose: Keep parquet reads predictable in memory-constrained Shiny/runtime
#   sessions without changing the public API of the data-loading functions.

# Internal: run an expression with configured Arrow runtime settings.
#
# Arrow can inflate memory sharply when multiple files are decoded in parallel
# and then collected into R data frames. The HUB still needs R objects for the
# current join/reporting code, so this helper limits read parallelism during
# source loading and restores the previous session setting afterwards.
.with_miama_arrow_runtime <- function(cfg, expr) {
  old_cpu_count <- tryCatch(arrow::cpu_count(), error = function(e) NULL)
  requested_cpu_count <- cfg$arrow$cpu_count %||% NULL

  if (!is.null(requested_cpu_count)) {
    try(
      arrow::set_cpu_count(as.integer(requested_cpu_count)),
      silent = TRUE
    )
  }

  on.exit({
    if (!is.null(old_cpu_count)) {
      try(arrow::set_cpu_count(old_cpu_count), silent = TRUE)
    }
    .release_miama_arrow_memory(cfg)
  }, add = TRUE)

  force(expr)
}

# Internal: ask R/Arrow to release memory after large parquet materializations.
#
# Arrow's memory-pool release API differs by package version. We call ordinary
# R garbage collection unconditionally and then attempt known Arrow pool APIs
# defensively when they exist.
.release_miama_arrow_memory <- function(cfg) {
  if (!isTRUE(cfg$arrow$release_unused)) {
    return(invisible(FALSE))
  }

  invisible(gc())

  pool <- NULL
  if (exists("default_memory_pool", envir = asNamespace("arrow"), inherits = FALSE)) {
    pool <- tryCatch(arrow::default_memory_pool(), error = function(e) NULL)
  } else if (exists("arrow_memory_pool", envir = asNamespace("arrow"), inherits = FALSE)) {
    pool <- tryCatch(arrow::arrow_memory_pool(), error = function(e) NULL)
  }

  if (!is.null(pool) && is.function(pool$ReleaseUnused)) {
    try(pool$ReleaseUnused(), silent = TRUE)
  }

  invisible(TRUE)
}
