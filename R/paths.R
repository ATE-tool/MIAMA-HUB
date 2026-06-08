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

miama_paths <- function() {
  project_root <- miama_project_root()
  hm_root <- miama_hm_root()

  list(
    project_root = project_root,
    hm_root = hm_root,
    hm_processed_root = file.path(hm_root, "processed"),
    inst_workflows = file.path(project_root, "inst", "workflows"),
    data_dir = file.path(project_root, "data"),
    output_root = file.path(project_root, "data", MIAMA_SCENARIO_DIRNAME),
    output_lookup = file.path(project_root, "data", "lookup"),
    output_reference = file.path(project_root, "data", "reference")
  )
}
# R/paths.R ---------------------------------------------------------------
# Project-local locations and fallbacks copied from POC_impact_workflow.R

MIAMA_HM_ROOT <- "../MIAMA-HM"
HM_PROCESSED_ROOT <- file.path(MIAMA_HM_ROOT, "health_data", "processed")

SP_ATTRIBUTES_DTA_LOC <- file.path("data", "synthetic_pop", "SPindivid_CensusNTSALS.dta")
SP_TRIPS_DTA_LOC <- file.path("data", "synthetic_pop", "SPtrip_CensusNTSALS.dta")
SP_ATTRIBUTES_PARQUET_LOC <- file.path("data", "synthetic_pop", "SPindivid_CensusNTSALS_parquet")
SP_TRIPS_PARQUET_LOC <- file.path("data", "synthetic_pop", "SPtrip_CensusNTSALS_parquet")
SP_ATTRIBUTES_DEV_PARQUET_LOC <- file.path("data", "synthetic_pop", "SPindivid_CensusNTSALS_dev_parquet")
SP_TRIPS_DEV_PARQUET_LOC <- file.path("data", "synthetic_pop", "SPtrip_CensusNTSALS_dev_parquet")

# choose development parquet if present, then regular parquet, else original dta
SP_ATTRIBUTES_LOC <- dplyr::case_when(
  dir.exists(SP_ATTRIBUTES_DEV_PARQUET_LOC) ~ SP_ATTRIBUTES_DEV_PARQUET_LOC,
  dir.exists(SP_ATTRIBUTES_PARQUET_LOC) ~ SP_ATTRIBUTES_PARQUET_LOC,
  TRUE ~ SP_ATTRIBUTES_DTA_LOC
)

SP_TRIPS_LOC <- dplyr::case_when(
  dir.exists(SP_TRIPS_DEV_PARQUET_LOC) ~ SP_TRIPS_DEV_PARQUET_LOC,
  dir.exists(SP_TRIPS_PARQUET_LOC) ~ SP_TRIPS_PARQUET_LOC,
  TRUE ~ SP_TRIPS_DTA_LOC
)

# Health-model processed outputs
SP_JOINED_OVERALL_LOC <- file.path(HM_PROCESSED_ROOT, "sp_overall_outcomes")
SP_JOINED_CYCLE_LOC <- file.path(HM_PROCESSED_ROOT, "sp_cycle_outcomes")
SP_JOINED_OVERALL_SAMPLE_LOC <- file.path(HM_PROCESSED_ROOT, "sp_overall_outcomes_sample")
SP_JOINED_CYCLE_SAMPLE_LOC <- file.path(HM_PROCESSED_ROOT, "sp_cycle_outcomes_sample")
LOOKUP_OVERALL_LOC <- file.path(HM_PROCESSED_ROOT, "mmet_d_overall_lookup")
LOOKUP_CYCLE_LOC <- file.path(HM_PROCESSED_ROOT, "mmet_d_cycle_lookup")

# Scenario outputs
SCENARIO_OUTPUT_ROOT <- file.path("outputs", "scenarios")
SCENARIO_OVERALL_LOC <- file.path(SCENARIO_OUTPUT_ROOT, "sample_scenario_overall")
SCENARIO_CYCLE_LOC <- file.path(SCENARIO_OUTPUT_ROOT, "sample_scenario_cycle")

dir.create(SCENARIO_OUTPUT_ROOT, recursive = TRUE, showWarnings = FALSE)
