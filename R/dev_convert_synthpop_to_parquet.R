# MIAMA-HUB Module: Dev Helpers / Convert Synthpop DTA to Parquet
# Purpose: One-time local conversion of large synthpop Stata files to parquet
#   datasets so Arrow can push down geo and ID filters during development.

convert_synthpop_to_parquet <- function(cfg = NULL, overwrite = FALSE) {
  cfg <- cfg %||% miama_default_config()

  .convert_one_synthpop_source(
    dta_path = file.path(dirname(cfg$sources$sp_attributes$path), "SPindivid_CensusNTSALS.dta"),
    parquet_path = file.path(dirname(cfg$sources$sp_attributes$path), "SPindivid_CensusNTSALS_parquet"),
    overwrite = overwrite
  )

  .convert_one_synthpop_source(
    dta_path = file.path(dirname(cfg$sources$sp_trips$path), "SPtrip_CensusNTSALS.dta"),
    parquet_path = file.path(dirname(cfg$sources$sp_trips$path), "SPtrip_CensusNTSALS_parquet"),
    overwrite = overwrite
  )

  invisible(TRUE)
}

.convert_one_synthpop_source <- function(dta_path, parquet_path, overwrite = FALSE) {
  if (!file.exists(dta_path)) {
    stop("DTA source not found: ", dta_path, call. = FALSE)
  }

  if (dir.exists(parquet_path) && !isTRUE(overwrite)) {
    message("Parquet already exists, skipping: ", parquet_path)
    return(invisible(FALSE))
  }

  if (dir.exists(parquet_path) && isTRUE(overwrite)) {
    unlink(parquet_path, recursive = TRUE, force = TRUE)
  }

  message("Reading DTA: ", dta_path)
  df <- haven::read_dta(dta_path)

  message("Writing parquet dataset: ", parquet_path)
  arrow::write_dataset(df, parquet_path, format = "parquet")

  invisible(TRUE)
}
