# MIAMA-HUB Dev Workflow: Build Packaged Data Manifest
# -----------------------------------------------------------------------------
# Purpose:
#   Inventory every packaged runtime artifact under `inst/extdata/data`, record
#   its source, source version, row count, schema, and MD5 checksum, and write a
#   reproducible manifest alongside the packaged data.
#
# Run after intentionally replacing or regenerating a packaged artifact:
#   Rscript --vanilla inst/workflows/dev_build_packaged_data_manifest.R
#
# Source-version values marked `unrecorded` require an authoritative upstream
# release identifier before production data governance is considered complete.


# 0. Setup ----
# -----------------------------------------------------------------------------#

find_miama_hub_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = FALSE)
  repeat {
    description <- file.path(current, "DESCRIPTION")
    if (file.exists(description) &&
        identical(unname(read.dcf(description)[1, "Package"]), "MIAMAHUB")) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find the MIAMA-HUB package root.", call. = FALSE)
    }
    current <- parent
  }
}

hub_root <- find_miama_hub_root()
data_root <- file.path(hub_root, "inst", "extdata", "data")
manifest_path <- file.path(data_root, "manifest.csv")

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})


# 1. Artifact Definitions ----
# -----------------------------------------------------------------------------#

release <- readRDS(file.path(data_root, "health_data", "release.rds"))
artifacts <- data.frame(
  artifact = c(
    "synthetic_pop/SPindivid_CensusNTSALS_parquet",
    "synthetic_pop/SPtrip_CensusNTSALS_parquet",
    "health_data/sp_cycle_outcomes",
    "health_data/mmet_d_cycle_lookup",
    "health_data/haly_parameters/pyld_table.csv",
    "health_data/haly_parameters/dw_table.csv",
    "health_data/release.rds",
    "lookup/geo_options.rds",
    "lookup/england_mode_default_candidates.csv",
    "lookup/england_schema_default_candidates.csv"
  ),
  format = c(rep("parquet", 4), "csv", "csv", "rds", "rds", "csv", "csv"),
  source = c(
    rep("MIAMA synthetic population: Census/NTS/ALS", 2),
    "MIAMA-HM cycle outcomes including death shares",
    "MIAMA-HM matching MMET cycle lookup",
    "MIAMA-HM residual pYLD", "MIAMA-HM adjusted disability weights",
    "MIAMA-HM source checksums and revision",
    rep("Derived from full MIAMA synthetic population", 3)
  ),
  source_version = c(rep("unrecorded", 2), rep(release$hm_commit, 5),
                     "Census 2021 5% synthpop scale", rep("unrecorded", 2)),
  purpose = c(
    "Packaged sample individual attributes", "Packaged sample trip records",
    "Baseline person roster and annual health outcomes",
    "Counterfactual health recalculation", "Residual disability parameters",
    "Comorbidity-adjusted disability weights", "Health release provenance",
    "Full-derived geography options", "England mode evidence", "England defaults"
  ),
  generated_by = c(
    rep("upstream sample extraction", 2),
    rep("inst/workflows/dev_refresh_packaged_health_data.R", 5),
    "build_geo_lookup()",
    rep("inst/workflows/dev_extract_england_schema_default_values.R", 2)
  ),
  stringsAsFactors = FALSE
)
# Discover the same independently packaged LAD profiles as before the refresh.
for (profile_dir in list.dirs(file.path(data_root, "profiles"),
                             full.names = TRUE, recursive = FALSE)) {
  metadata <- readRDS(file.path(profile_dir, "profile.rds"))
  relative <- c("profile.rds",
                "synthetic_pop/SPindivid_CensusNTSALS_parquet",
                "synthetic_pop/SPtrip_CensusNTSALS_parquet",
                "health_data/sp_cycle_outcomes",
                "lookup/geo_options.rds")
  artifacts <- rbind(artifacts, data.frame(
    artifact = file.path("profiles", metadata$profile_id, relative),
    format = c("rds", rep("parquet", 3), "rds"),
    source = paste(metadata$geo_name, c("sampling metadata", "synthpop attributes",
                   "synthpop trips", "HM cycles including death shares",
                   "geography lookup")),
    source_version = ifelse(grepl("^health_data/", relative), metadata$hm_commit,
                           paste("Census 2021 synthpop; profile seed", metadata$seed)),
    purpose = paste(metadata$sampled_individuals, "person", metadata$geo_name,
                    "profile:", relative),
    generated_by = "inst/workflows/dev_build_packaged_lad_profile.R",
    stringsAsFactors = FALSE
  ))
}


# 2. Inspection Helpers ----
# -----------------------------------------------------------------------------#

schema_from_arrow <- function(dataset) {
  fields <- vapply(dataset$schema$names, function(name) {
    field <- dataset$schema$GetFieldByName(name)
    paste0(name, ":", field$type$ToString())
  }, character(1))
  paste(fields, collapse = "|")
}

schema_from_data_frame <- function(data) {
  fields <- vapply(names(data), function(name) {
    paste0(name, ":", paste(class(data[[name]]), collapse = "/"))
  }, character(1))
  paste(fields, collapse = "|")
}

artifact_checksum <- function(path) {
  files <- if (dir.exists(path)) {
    sort(list.files(path, recursive = TRUE, full.names = TRUE, all.files = FALSE))
  } else {
    path
  }
  files <- files[file.exists(files)]
  if (length(files) == 0) return(NA_character_)

  checksums <- unname(tools::md5sum(files))
  paste0(basename(files), "=", checksums, collapse = ";")
}

inspect_artifact <- function(relative_path, format) {
  path <- file.path(data_root, relative_path)
  if (!file.exists(path) && !dir.exists(path)) {
    stop("Packaged artifact not found: ", relative_path, call. = FALSE)
  }

  if (identical(format, "parquet")) {
    dataset <- arrow::open_dataset(path, format = "parquet")
    row_count <- dataset |>
      dplyr::summarise(n = dplyr::n()) |>
      dplyr::collect() |>
      dplyr::pull(.data$n)
    schema <- schema_from_arrow(dataset)
  } else if (identical(format, "rds")) {
    data <- readRDS(path)
    row_count <- if (is.data.frame(data) || is.matrix(data)) nrow(data) else length(data)
    schema <- if (is.data.frame(data)) schema_from_data_frame(data) else paste(class(data), collapse = "/")
  } else if (identical(format, "csv")) {
    data <- utils::read.csv(path, stringsAsFactors = FALSE)
    row_count <- nrow(data)
    schema <- schema_from_data_frame(data)
  } else {
    stop("Unsupported manifest format: ", format, call. = FALSE)
  }

  list(
    row_count = as.numeric(row_count),
    schema = schema,
    checksum_algorithm = "MD5",
    checksum = artifact_checksum(path)
  )
}


# 3. Build Manifest ----
# -----------------------------------------------------------------------------#

inspection <- Map(inspect_artifact, artifacts$artifact, artifacts$format)
artifacts$row_count <- vapply(inspection, `[[`, numeric(1), "row_count")
artifacts$schema <- vapply(inspection, `[[`, character(1), "schema")
artifacts$checksum_algorithm <- vapply(inspection, `[[`, character(1), "checksum_algorithm")
artifacts$checksum <- vapply(inspection, `[[`, character(1), "checksum")

utils::write.csv(artifacts, manifest_path, row.names = FALSE, na = "")
message("Wrote packaged data manifest: ", manifest_path)
print(artifacts[, c("artifact", "source_version", "row_count", "checksum")])
