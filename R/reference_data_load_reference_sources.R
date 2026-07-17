# MIAMA-HUB Module: Reference Data / Load Reference Sources
# Purpose: Load the upstream data sources that feed `reference_data_raw`:
#   HM outcomes and synthetic population (attributes + trips).
# Inputs: A resolved config plus request sections used for source selection and
#   parquet pushdown filters.
# Outputs: A named list with `hm_outcomes`, `sp_attributes`, `sp_trips`, `cfg`.

load_reference_sources <- function(cfg = NULL, reference_request = list(), results_request = list()) {
  cfg <- miama_resolve_config(cfg, results_request = results_request)

  source_data <- .with_miama_arrow_runtime(cfg, {
    sp_attributes <- .load_synthpop_source(
      cfg$sources$sp_attributes,
      reference_request = reference_request
    )

    matched_ids <- unique(stats::na.omit(sp_attributes$census_id))
    sp_trip_census_ids <- .synthpop_trip_census_ids_filter(
      reference_request = reference_request,
      matched_ids = matched_ids
    )

    sp_trips <- .load_synthpop_source(
      cfg$sources$sp_trips,
      reference_request = reference_request,
      census_ids = sp_trip_census_ids
    )

    list(
      sp_attributes = sp_attributes,
      matched_ids = matched_ids,
      sp_trips = sp_trips,
      sp_trip_census_id_filter_applied = !is.null(sp_trip_census_ids)
    )
  })

  hm_outcomes <- load_hm_outcomes(
    cfg,
    results_request = results_request,
    census_ids = source_data$matched_ids
  )

  list(
    hm_outcomes = hm_outcomes,
    sp_attributes = source_data$sp_attributes,
    sp_trips = source_data$sp_trips,
    cfg = cfg,
    source_report = list(
      n_matched_ids = length(source_data$matched_ids),
      geo_level = reference_request$geo_level %||% NULL,
      geo_id = reference_request$geo_id %||% NULL,
      hm_suffix = miama_hm_suffix_from_request(results_request),
      arrow_cpu_count = cfg$arrow$cpu_count %||% NULL,
      arrow_release_unused = isTRUE(cfg$arrow$release_unused),
      sp_trip_census_id_filter_applied = source_data$sp_trip_census_id_filter_applied
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

# Internal: decide whether trip parquet needs a second census-id filter.
#
# For LAD/region/MSOA requests, trips carry the same geography columns as
# attributes, so filtering by geography directly is cheaper than constructing a
# large `census_id %in% ...` Arrow expression. For England-wide or unscoped
# requests, keep the ID filter so trips stay aligned to the loaded attributes.
.synthpop_trip_census_ids_filter <- function(reference_request = list(), matched_ids) {
  geo_col <- .miama_geo_column(reference_request$geo_level %||% NULL)
  geo_id <- reference_request$geo_id %||% NULL

  if (!is.null(geo_col) && !is.null(geo_id)) {
    return(NULL)
  }

  matched_ids
}

# Internal: read a synthpop parquet source given a list(path, format).
.load_synthpop_source <- function(source, reference_request = list(), census_ids = NULL) {
  path   <- source$path
  format <- source$format

  if (!identical(format, "parquet")) {
    stop("Unsupported synthpop source format: ", format,
         ". Runtime synthpop sources must be parquet.", call. = FALSE)
  }

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

  dplyr::collect(ds)
}
