# MIAMA-HUB Module: Reference Data / Load Reference Sources
# Purpose: Load the upstream data sources that feed `reference_data_raw`:
#   HM outcomes and synthetic population (attributes + trips).
# Inputs: A resolved config plus request sections used for source selection and
#   parquet pushdown filters.
# Outputs: A named list with `hm_outcomes`, `sp_attributes`, `sp_trips`, `cfg`.

load_reference_sources <- function(cfg = NULL, reference_request = list(), results_request = list()) {
  cfg <- miama_resolve_config(cfg, results_request = results_request)

  sp_attributes <- .load_synthpop_source(
    cfg$sources$sp_attributes,
    reference_request = reference_request
  )

  matched_ids <- unique(stats::na.omit(sp_attributes$census_id))

  sp_trips <- .load_synthpop_source(
    cfg$sources$sp_trips,
    reference_request = reference_request,
    census_ids = matched_ids
  )

  hm_outcomes <- load_hm_outcomes(
    cfg,
    results_request = results_request,
    census_ids = matched_ids
  )

  list(
    hm_outcomes = hm_outcomes,
    sp_attributes = sp_attributes,
    sp_trips = sp_trips,
    cfg = cfg,
    source_report = list(
      n_matched_ids = length(matched_ids),
      geo_level = reference_request$geo_level %||% NULL,
      geo_id = reference_request$geo_id %||% NULL,
      hm_suffix = miama_hm_suffix_from_request(results_request)
    )
  )
}

# Internal: map UI/request geo level to source column names.
.miama_geo_column <- function(geo_level) {
  if (is.null(geo_level) || identical(geo_level, "eng")) {
    return(NULL)
  }

  switch(
    geo_level,
    reg = "region",
    lad = "lad25cd",
    glads = "lad25cd",
    msoa = "msoa11cd",
    stop("Unsupported geo_level: ", geo_level, call. = FALSE)
  )
}

# Internal: read a synthpop source given a list(path, format).
.load_synthpop_source <- function(source, reference_request = list(), census_ids = NULL) {
  path   <- source$path
  format <- source$format

  if (format == "parquet") {
    message("Loading synthpop parquet: ", path)
    ds <- arrow::open_dataset(path, format = "parquet")

    geo_col <- .miama_geo_column(reference_request$geo_level %||% NULL)
    geo_id <- reference_request$geo_id %||% NULL

    if (!is.null(geo_col) && !is.null(geo_id)) {
      ds <- dplyr::filter(ds, .data[[geo_col]] %in% geo_id)
    }

    if (!is.null(census_ids)) {
      ds <- dplyr::filter(ds, census_id %in% census_ids)
    }

    return(dplyr::collect(ds))
  }

  if (format == "dta") {
    message("Loading synthpop Stata file: ", path)
    df <- haven::read_dta(path)

    geo_col <- .miama_geo_column(reference_request$geo_level %||% NULL)
    geo_id <- reference_request$geo_id %||% NULL

    if (!is.null(geo_col) && !is.null(geo_id)) {
      df <- df[df[[geo_col]] %in% geo_id, , drop = FALSE]
    }

    if (!is.null(census_ids)) {
      df <- df[df$census_id %in% census_ids, , drop = FALSE]
    }

    return(df)
  }

  stop("Unknown synthpop source format: ", format, call. = FALSE)
}
