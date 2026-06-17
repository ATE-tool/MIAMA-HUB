# Workflow configuration object, validator, and HM data loaders

`%||%` <- function(x, y) if (is.null(x)) y else x

miama_default_config <- function() {
  p <- miama_paths()

  list(
    workflow = list(
      dataset_size = "sample",    # options: "sample", "full"
      max_rows     = MIAMA_DEFAULT_MAX_ROWS
    ),
    sources = list(
      sp_attributes = p$sp_attributes,
      sp_trips      = p$sp_trips,
      hm_outcomes = list(
        overall        = p$hm_sp_overall,
        overall_sample = p$hm_sp_overall_sample,
        cycle          = p$hm_sp_cycle,
        cycle_sample   = p$hm_sp_cycle_sample
      ),
      hm_lookup = list(
        overall = p$hm_lookup_overall,
        cycle   = p$hm_lookup_cycle
      )
    ),
    cache = list(
      enabled = TRUE,
      refresh = FALSE,
      dir     = p$cache_dir
    ),
    output = list(
      root      = p$output_root,
      lookup    = p$output_lookup,
      reference = p$output_reference
    )
  )
}

miama_hm_suffix_from_request <- function(results_request = list()) {
  aggregation <- results_request$res_aggregation %||% "total"

  switch(
    aggregation,
    total = "overall",
    timeline = "cycle",
    stop("Unsupported res_aggregation: ", aggregation, call. = FALSE)
  )
}

# Validate that the resolved source paths actually exist on disk.
miama_resolve_config <- function(cfg = NULL, results_request = list()) {
  cfg <- cfg %||% miama_default_config()

  sp_path <- cfg$sources$sp_attributes$path
  if (!file.exists(sp_path) && !dir.exists(sp_path)) {
    stop("Synthpop attributes source not found: ", sp_path, call. = FALSE)
  }

  sp_trips_path <- cfg$sources$sp_trips$path
  if (!file.exists(sp_trips_path) && !dir.exists(sp_trips_path)) {
    stop("Synthpop trips source not found: ", sp_trips_path, call. = FALSE)
  }

  hm_suffix <- miama_hm_suffix_from_request(results_request)
  hm_key <- paste0(
    hm_suffix,
    if (cfg$workflow$dataset_size == "sample") "_sample" else ""
  )
  hm_dir <- cfg$sources$hm_outcomes[[hm_key]]

  if (!dir.exists(hm_dir)) {
    stop("HM outcomes directory not found: ", hm_dir, call. = FALSE)
  }

  cfg
}

# Load HM outcomes parquet with optional rds caching for faster future loads.
load_hm_outcomes <- function(cfg = NULL, results_request = list(), census_ids = NULL) {
  cfg <- cfg %||% miama_default_config()

  valid_sizes <- c("sample", "full")
  if (!cfg$workflow$dataset_size %in% valid_sizes) {
    stop("cfg$workflow$dataset_size must be one of: ",
         paste(valid_sizes, collapse = ", "), call. = FALSE)
  }

  hm_suffix <- miama_hm_suffix_from_request(results_request)
  key <- paste0(
    hm_suffix,
    if (cfg$workflow$dataset_size == "sample") "_sample" else ""
  )
  parquet_path <- cfg$sources$hm_outcomes[[key]]

  if (!dir.exists(parquet_path)) {
    stop("HM outcomes parquet directory not found: ", parquet_path, call. = FALSE)
  }

  cache_file <- file.path(
    cfg$cache$dir,
    paste0("hm_outcomes_", key, ".rds")
  )

  if (isTRUE(cfg$cache$enabled) && is.null(census_ids) && file.exists(cache_file) && !isTRUE(cfg$cache$refresh)) {
    message("Loading HM outcomes from cache: ", cache_file)
    return(readRDS(cache_file))
  }

  message("Loading HM outcomes from parquet: ", parquet_path)
  hm_ds <- arrow::open_dataset(parquet_path, format = "parquet")

  if (!is.null(census_ids)) {
    hm_ds <- dplyr::filter(hm_ds, census_id %in% census_ids)
  }

  hm_outcomes <- dplyr::collect(hm_ds)

  if (isTRUE(cfg$cache$enabled) && is.null(census_ids)) {
    dir.create(cfg$cache$dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(hm_outcomes, cache_file)
    message("Cached HM outcomes to: ", cache_file)
  }

  hm_outcomes
}

# Load mmet lookup table for the requested aggregation.
load_hm_lookup <- function(cfg = NULL, results_request = list()) {
  cfg <- cfg %||% miama_default_config()
  hm_suffix <- miama_hm_suffix_from_request(results_request)

  lookup_path <- cfg$sources$hm_lookup[[hm_suffix]]
  if (is.null(lookup_path)) {
    stop("Unknown HM lookup suffix: ", hm_suffix, call. = FALSE)
  }
  if (!dir.exists(lookup_path)) {
    stop("HM lookup parquet directory not found: ", lookup_path, call. = FALSE)
  }

  dplyr::collect(arrow::open_dataset(lookup_path, format = "parquet"))
}
