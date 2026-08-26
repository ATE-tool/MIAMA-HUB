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

  package_root <- .miama_loaded_package_root()
  if (!is.null(package_root)) {
    return(package_root)
  }

  miama_find_project_root()
}

.miama_loaded_package_root <- function() {
  ns_path <- tryCatch(
    getNamespaceInfo(asNamespace("MIAMAHUB"), "path"),
    error = function(e) ""
  )
  if (nzchar(ns_path) && file.exists(file.path(ns_path, "DESCRIPTION"))) {
    return(normalizePath(ns_path, winslash = "/", mustWork = FALSE))
  }

  package_path <- system.file(package = "MIAMAHUB")
  if (nzchar(package_path) && file.exists(file.path(package_path, "DESCRIPTION"))) {
    return(normalizePath(package_path, winslash = "/", mustWork = FALSE))
  }

  NULL
}

miama_path <- function(...) {
  file.path(miama_project_root(), ...)
}

miama_runtime_data_dir <- function(project_root = miama_project_root()) {
  external_data <- Sys.getenv("MIAMA_DATA_ROOT", unset = "")
  if (nzchar(external_data)) {
    return(normalizePath(external_data, winslash = "/", mustWork = FALSE))
  }

  miama_packaged_data_dir(project_root)
}

miama_packaged_data_dir <- function(project_root = miama_project_root()) {

  packaged_data <- system.file("extdata", "data", package = "MIAMAHUB")
  if (nzchar(packaged_data) && dir.exists(packaged_data)) {
    return(normalizePath(packaged_data, winslash = "/", mustWork = FALSE))
  }

  # `system.file()` may be empty while the package is loaded from source with
  # devtools. In that case, use the source copy of the same packaged samples.
  source_packaged_data <- file.path(project_root, "inst", "extdata", "data")
  if (dir.exists(source_packaged_data)) {
    return(normalizePath(source_packaged_data, winslash = "/", mustWork = FALSE))
  }

  stop(
    "Packaged sample data were not found. Set MIAMA_DATA_ROOT to the external data directory.",
    call. = FALSE
  )
}

miama_hm_root <- function() {
  root <- miama_hm_root_or_null()
  if (is.null(root)) {
    stop(
      "MIAMA_HM_ROOT is not set and no sibling MIAMA-HM repo was found.",
      call. = FALSE
    )
  }
  root
}

miama_hm_root_or_null <- function() {
  root <- Sys.getenv("MIAMA_HM_ROOT", unset = "")
  if (nzchar(root)) {
    return(normalizePath(root, winslash = "/", mustWork = FALSE))
  }

  .miama_sibling_hm_root_or_null()
}

.miama_sibling_hm_root_or_null <- function() {
  candidate <- file.path(dirname(miama_project_root()), "MIAMA-HM")
  processed <- file.path(candidate, "health_data", "processed")
  if (!dir.exists(processed)) {
    return(NULL)
  }

  normalizePath(candidate, winslash = "/", mustWork = FALSE)
}

# Resolve which synthpop source to use: dev parquet > full parquet.
# Stata `.dta` files are legacy conversion inputs and are not runtime sources.
miama_pick_synthpop_source <- function(data_dir, prefix) {
  dev_parquet <- file.path(data_dir, "synthetic_pop", paste0(prefix, "_dev_parquet"))
  parquet     <- file.path(data_dir, "synthetic_pop", paste0(prefix, "_parquet"))

  if (dir.exists(dev_parquet)) return(list(path = dev_parquet, format = "parquet"))
  if (dir.exists(parquet))     return(list(path = parquet,     format = "parquet"))
  list(path = parquet, format = "parquet")
}

miama_pick_hm_source <- function(data_dir,
                                 hm_processed,
                                 dataset_name,
                                 fallback_data_dirs = character()) {
  hub_path <- file.path(data_dir, "health_data", dataset_name)
  hm_path <- if (is.null(hm_processed)) NULL else file.path(hm_processed, dataset_name)

  if (dir.exists(hub_path)) {
    return(list(path = hub_path, format = "parquet", source = "hub"))
  }
  if (!is.null(hm_path) && dir.exists(hm_path)) {
    return(list(path = hm_path, format = "parquet", source = "hm"))
  }

  fallback_paths <- file.path(fallback_data_dirs, "health_data", dataset_name)
  fallback_match <- fallback_paths[dir.exists(fallback_paths)]
  if (length(fallback_match) > 0) {
    return(list(path = fallback_match[[1]], format = "parquet", source = "hub_shared"))
  }

  list(
    path = hub_path,
    format = "parquet",
    source = if (is.null(hm_path)) "missing_hub" else "missing"
  )
}

miama_paths <- function(dataset_size = NULL) {
  project_root <- miama_project_root()
  hm_root      <- miama_hm_root_or_null()
  uses_packaged_profile <- isTRUE(dataset_size %in% c("sample", "leeds"))
  packaged_data_dir <- if (uses_packaged_profile) {
    miama_packaged_data_dir(project_root)
  } else {
    tryCatch(miama_packaged_data_dir(project_root), error = function(e) NULL)
  }
  data_dir <- if (identical(dataset_size, "sample")) {
    # Sample mode must use a coherent packaged SP/HM sample. Allowing an
    # existing MIAMA_DATA_ROOT to replace only the SP side creates targets from
    # full SP rows that cannot be applied to the much smaller sample HM join.
    packaged_data_dir
  } else if (identical(dataset_size, "leeds")) {
    # The Leeds profile is a self-contained, aligned SP/HM subset intended for
    # realistic local and published-app testing without external full data.
    file.path(packaged_data_dir, "profiles", "leeds")
  } else {
    miama_runtime_data_dir(project_root)
  }
  hm_processed <- if (is.null(hm_root)) NULL else file.path(hm_root, "health_data", "processed")
  profile_hm_processed <- if (identical(dataset_size, "leeds")) NULL else hm_processed

  sp_attributes <- miama_pick_synthpop_source(data_dir, "SPindivid_CensusNTSALS")
  sp_trips      <- miama_pick_synthpop_source(data_dir, "SPtrip_CensusNTSALS")
  hm_sp_overall <- miama_pick_hm_source(data_dir, profile_hm_processed, "sp_overall_outcomes")
  hm_sp_cycle <- miama_pick_hm_source(data_dir, profile_hm_processed, "sp_cycle_outcomes")
  hm_sp_overall_sample <- miama_pick_hm_source(data_dir, profile_hm_processed, "sp_overall_outcomes_sample")
  hm_sp_cycle_sample <- miama_pick_hm_source(data_dir, profile_hm_processed, "sp_cycle_outcomes_sample")
  hm_cycle_death_share <- miama_pick_hm_source(data_dir, profile_hm_processed, "sp_cycle_outcomes_death_share")
  hm_cycle_sample_death_share <- miama_pick_hm_source(
    data_dir,
    profile_hm_processed,
    "sp_cycle_outcomes_sample_death_share"
  )
  hm_lookup_cycle_death_share <- miama_pick_hm_source(
    data_dir,
    profile_hm_processed,
    "mmet_d_cycle_lookup_death_share",
    fallback_data_dirs = if (identical(dataset_size, "leeds")) packaged_data_dir else character()
  )

  list(
    project_root      = project_root,
    hm_root           = hm_root,
    hm_processed_root = hm_processed,
    packaged_data_dir = packaged_data_dir,
    profile_metadata  = file.path(data_dir, "profile.rds"),
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
    hm_sp_overall         = hm_sp_overall,
    hm_sp_cycle           = hm_sp_cycle,
    hm_sp_overall_sample  = hm_sp_overall_sample,
    hm_sp_cycle_sample    = hm_sp_cycle_sample,
    hm_cycle_death_share  = hm_cycle_death_share,
    hm_cycle_sample_death_share = hm_cycle_sample_death_share,
    hm_lookup_cycle_death_share = hm_lookup_cycle_death_share,
    hm_lookup_overall     = if (is.null(hm_processed)) NULL else file.path(hm_processed, "mmet_d_overall_lookup"),
    hm_lookup_cycle       = if (is.null(hm_processed)) NULL else file.path(hm_processed, "mmet_d_cycle_lookup")
  )
}
