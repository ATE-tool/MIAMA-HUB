# Path resolution helpers (no hardcoded absolute paths)

miama_find_project_root <- function(start = getwd()) {
  start <- normalizePath(start, winslash = "/", mustWork = FALSE)
  cur <- start

  repeat {
    has_description <- file.exists(file.path(cur, "DESCRIPTION"))
    has_git <- dir.exists(file.path(cur, ".git"))
    has_inst <- dir.exists(file.path(cur, "inst"))

    if (has_description || has_git || has_inst) {
      return(cur)
    }

    parent <- dirname(cur)
    if (identical(parent, cur)) {
      stop(
        "Could not determine project root. Set MIAMA_PROJECT_ROOT env var.",
        call. = FALSE
      )
    }
    cur <- parent
  }
}

miama_project_root <- function() {
  env_root <- Sys.getenv("MIAMA_PROJECT_ROOT", unset = "")
  if (nzchar(env_root)) {
    return(normalizePath(env_root, winslash = "/", mustWork = FALSE))
  }
  miama_find_project_root()
}

miama_path <- function(...) {
  file.path(miama_project_root(), ...)
}

miama_hm_root <- function() {
  root <- Sys.getenv("MIAMA_HM_ROOT", unset = "")
  if (!nzchar(root)) {
    stop(
      "MIAMA_HM_ROOT is not set. Please set it to your external HM data root.",
      call. = FALSE
    )
  }
  normalizePath(root, winslash = "/", mustWork = FALSE)
}

# Resolve which synthpop source to use: dev parquet > full parquet > dta fallback
miama_pick_synthpop_source <- function(data_dir, prefix) {
  dev_parquet <- file.path(data_dir, "synthetic_pop", paste0(prefix, "_dev_parquet"))
  parquet     <- file.path(data_dir, "synthetic_pop", paste0(prefix, "_parquet"))
  dta         <- file.path(data_dir, "synthetic_pop", paste0(prefix, ".dta"))

  if (dir.exists(dev_parquet)) return(list(path = dev_parquet, format = "parquet"))
  if (dir.exists(parquet))     return(list(path = parquet,     format = "parquet"))
  return(list(path = dta, format = "dta"))
}

miama_paths <- function() {
  project_root <- miama_project_root()
  hm_root      <- miama_hm_root()
  data_dir     <- file.path(project_root, "data")
  hm_processed <- file.path(hm_root, "health_data", "processed")

  sp_attributes <- miama_pick_synthpop_source(data_dir, "SPindivid_CensusNTSALS")
  sp_trips      <- miama_pick_synthpop_source(data_dir, "SPtrip_CensusNTSALS")

  list(
    project_root      = project_root,
    hm_root           = hm_root,
    hm_processed_root = hm_processed,
    inst_workflows    = file.path(project_root, "inst", "workflows"),
    data_dir          = data_dir,
    cache_dir         = file.path(data_dir, "cache"),
    output_root       = file.path(data_dir, MIAMA_SCENARIO_DIRNAME),
    output_lookup     = file.path(data_dir, "lookup"),
    output_reference  = file.path(data_dir, "reference"),

    # Synthetic population sources (resolved at call time)
    sp_attributes     = sp_attributes,
    sp_trips          = sp_trips,

    # HM processed dataset directories
    hm_sp_overall         = file.path(hm_processed, "sp_overall_outcomes"),
    hm_sp_cycle           = file.path(hm_processed, "sp_cycle_outcomes"),
    hm_sp_overall_sample  = file.path(hm_processed, "sp_overall_outcomes_sample"),
    hm_sp_cycle_sample    = file.path(hm_processed, "sp_cycle_outcomes_sample"),
    hm_lookup_overall     = file.path(hm_processed, "mmet_d_overall_lookup"),
    hm_lookup_cycle       = file.path(hm_processed, "mmet_d_cycle_lookup")
  )
}
