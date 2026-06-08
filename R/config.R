# Workflow configuration object + loader/validator

miama_default_config <- function() {
  p <- miama_paths()

  list(
    workflow = list(
      scenario = MIAMA_DEFAULT_SCENARIO,
      max_rows = MIAMA_DEFAULT_MAX_ROWS
    ),
    sources = list(
      synthpop = list(
        dev_parquet = file.path(p$data_dir, "synthpop_dev.parquet"),
        parquet = file.path(p$data_dir, "synthpop.parquet"),
        dta = file.path(p$data_dir, "synthpop.dta")
      ),
      hm_outcomes = list(
        path = file.path(p$hm_processed_root, "hm_outcomes.parquet"),
        format = "parquet"
      )
    ),
    output = list(
      root = p$output_root,
      lookup = p$output_lookup,
      reference = p$output_reference
    )
  )
}

miama_pick_existing_source <- function(candidates) {
  hits <- candidates[file.exists(candidates)]
  if (length(hits) == 0L) {
    stop("No source file found in candidates.", call. = FALSE)
  }
  hits[[1]]
}

miama_resolve_config <- function(cfg = NULL) {
  cfg <- cfg %||% miama_default_config()

  synthpop_candidates <- c(
    cfg$sources$synthpop$dev_parquet,
    cfg$sources$synthpop$parquet,
    cfg$sources$synthpop$dta
  )

  cfg$sources$synthpop$selected <- miama_pick_existing_source(synthpop_candidates)

  if (!file.exists(cfg$sources$hm_outcomes$path)) {
    stop(
      paste0("HM outcomes source not found: ", cfg$sources$hm_outcomes$path),
      call. = FALSE
    )
  }

  cfg
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
# MIAMA-HUB: Health-model outcomes configuration and loader
# Migrated from POC_impact_workflow.R section 0.3

hm_outcomes_cfg <- list(
  base_dir = HM_PROCESSED_ROOT,
  granularity = "overall", # options: "overall", "cycle"
  dataset_size = "sample", # options: "sample", "full"
  cache_as_rds = TRUE,
  refresh_cache = FALSE,
  cache_dir = file.path("data", "cache")
)

# Load health model outcomes from parquet with optional rds caching.
load_hm_outcomes <- function(cfg = hm_outcomes_cfg) {
  valid_granularity <- c("overall", "cycle")
  valid_sizes <- c("sample", "full")

  if (!cfg$granularity %in% valid_granularity) {
    stop("cfg$granularity must be one of: ", paste(valid_granularity, collapse = ", "))
  }
  if (!cfg$dataset_size %in% valid_sizes) {
    stop("cfg$dataset_size must be one of: ", paste(valid_sizes, collapse = ", "))
  }

  dataset_dir <- paste0(
    "sp_",
    cfg$granularity,
    "_outcomes",
    if (cfg$dataset_size == "sample") "_sample" else ""
  )

  parquet_path <- file.path(cfg$base_dir, dataset_dir)
  if (!dir.exists(parquet_path)) {
    stop("Parquet dataset directory not found: ", parquet_path)
  }

  cache_file <- file.path(
    cfg$cache_dir,
    paste0("hm_outcomes_", cfg$granularity, "_", cfg$dataset_size, ".rds")
  )

  if (isTRUE(cfg$cache_as_rds) && file.exists(cache_file) && !isTRUE(cfg$refresh_cache)) {
    message("Loading health model outcomes from cached rds: ", cache_file)
    return(readRDS(cache_file))
  }

  message("Loading health model outcomes from parquet: ", parquet_path)
  hm_outcomes <- dplyr::collect(
    arrow::open_dataset(parquet_path, format = "parquet")
  )

  if (isTRUE(cfg$cache_as_rds)) {
    dir.create(cfg$cache_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(hm_outcomes, cache_file)
    message("Saved health model outcomes cache: ", cache_file)
  }

  hm_outcomes
}

# Load lookup table for the given granularity
load_hm_lookup <- function(granularity = "overall") {
  lookup_path <- switch(granularity,
    overall = LOOKUP_OVERALL_LOC,
    cycle   = LOOKUP_CYCLE_LOC,
    stop("granularity must be 'overall' or 'cycle'")
  )

  if (!dir.exists(lookup_path)) {
    stop("Lookup parquet directory not found: ", lookup_path)
  }

  dplyr::collect(arrow::open_dataset(lookup_path, format = "parquet"))
}