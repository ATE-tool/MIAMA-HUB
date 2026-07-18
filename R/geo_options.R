# MIAMA-HUB Module: Geo Options
# Purpose: Provide lightweight geography level and option lookups for MIAMA-UI.
# Inputs: Cached lookup table or the synthetic-population attributes parquet source.
# Outputs: Small data frames for UI select controls.
# Notes: The lookup is built from unfiltered synthpop attributes once and cached
#   under `cfg$output$lookup`. This avoids loading full reference data only to
#   populate geography controls.

#' Get Supported Geography Levels
#'
#' Returns the geography levels currently available from the cached geo lookup.
#' If the lookup does not exist, it is built from the synthpop attributes source.
#'
#' @param cfg MIAMA-HUB configuration object. Defaults to `miama_default_config()`.
#' @param refresh Rebuild the cached lookup before returning levels.
#'
#' @return A data frame with `geo_level`, `geo_label`, and `n_options`.
#' @export
get_geo_levels <- function(cfg = NULL, refresh = FALSE) {
  lookup <- .load_geo_lookup(cfg = cfg, refresh = refresh)
  levels <- .geo_level_specs()

  out <- data.frame(
    geo_level = names(levels),
    geo_label = vapply(levels, `[[`, character(1), "label"),
    stringsAsFactors = FALSE
  )

  counts <- stats::setNames(
    as.integer(table(lookup$geo_level)),
    names(table(lookup$geo_level))
  )
  out$n_options <- unname(counts[out$geo_level])
  out$n_options[is.na(out$n_options)] <- 0L
  out
}

#' Get Geography Options
#'
#' Returns selectable geography IDs and labels for one geography level.
#'
#' @param cfg MIAMA-HUB configuration object. Defaults to `miama_default_config()`.
#' @param geo_level Geography level. Currently supports `eng`, `reg`, and `lad`.
#'   The alias `region` is also accepted and normalized to `reg`.
#' @param refresh Rebuild the cached lookup before returning options.
#'
#' @return A data frame with `geo_level`, `geo_id`, `geo_name`, and `n_individuals`.
#' @export
get_geo_options <- function(cfg = NULL, geo_level, refresh = FALSE) {
  if (missing(geo_level) || is.null(geo_level) || length(geo_level) != 1) {
    stop("`geo_level` must be one geography level.", call. = FALSE)
  }

  geo_level <- .normalize_geo_level(as.character(geo_level))
  .assert_supported_geo_level(geo_level)

  lookup <- .load_geo_lookup(cfg = cfg, refresh = refresh)
  out <- lookup[lookup$geo_level == geo_level, , drop = FALSE]
  row.names(out) <- NULL
  out
}

#' Get Geography Name
#'
#' Resolve a selected geography ID to its display name using the cached geo
#' lookup. For England-wide appraisals, `geo_id` may be omitted.
#'
#' @param cfg MIAMA-HUB configuration object. Defaults to `miama_default_config()`.
#' @param geo_level Geography level.
#' @param geo_id Geography ID selected by the UI. Optional for `geo_level = "eng"`.
#' @param refresh Rebuild the cached lookup before resolving the name.
#'
#' @return A length-one character vector, or `NA_character_` if the ID is not found.
#' @export
get_geo_name <- function(cfg = NULL, geo_level, geo_id = NULL, refresh = FALSE) {
  if (missing(geo_level) || is.null(geo_level) || length(geo_level) != 1) {
    stop("`geo_level` must be one geography level.", call. = FALSE)
  }

  geo_level <- .normalize_geo_level(as.character(geo_level))
  .assert_supported_geo_level(geo_level)

  options <- get_geo_options(cfg = cfg, geo_level = geo_level, refresh = refresh)

  if (identical(geo_level, "eng")) {
    return(options$geo_name[1] %||% "England")
  }

  if (is.null(geo_id) || length(geo_id) == 0 || is.na(geo_id[1])) {
    return(NA_character_)
  }

  geo_id <- as.character(geo_id[1])
  matched <- options[options$geo_id == geo_id, , drop = FALSE]
  if (nrow(matched) == 0) {
    matched <- options[options$geo_name == geo_id, , drop = FALSE]
  }
  if (nrow(matched) == 0) {
    return(NA_character_)
  }

  matched$geo_name[1]
}

#' Get Geography Details
#'
#' Resolve a selected geography ID to the compact metadata needed by the Tab 1
#' summary panel. This is intentionally independent of the `Hub` R6 object so
#' early setup UI can stay lightweight.
#'
#' @param cfg MIAMA-HUB configuration object. Defaults to `miama_default_config()`.
#' @param geo_id Geography ID selected by the UI. For England-wide appraisals,
#'   `geo_id = "eng"` is supported.
#' @param geo_level Optional geography level. If omitted, the ID is resolved
#'   across all supported levels. The alias `region` is normalized to `reg`.
#' @param refresh Rebuild the cached lookup before resolving details.
#'
#' @return A one-row data frame with canonical lookup columns plus UI summary
#'   aliases: `location`, `geographic_scale`, and
#'   `administrative_location_id`. Returns a zero-row data frame if no match is
#'   found.
#' @export
get_geo_details <- function(cfg = NULL, geo_id, geo_level = NULL, refresh = FALSE) {
  if (missing(geo_id) || is.null(geo_id) || length(geo_id) == 0 || is.na(geo_id[1])) {
    stop("`geo_id` must be one selected geography ID.", call. = FALSE)
  }

  lookup <- .load_geo_lookup(cfg = cfg, refresh = refresh)
  levels <- .geo_level_specs()

  if (!is.null(geo_level)) {
    if (length(geo_level) != 1 || is.na(geo_level[1])) {
      stop("`geo_level` must be one geography level when supplied.", call. = FALSE)
    }

    geo_level <- .normalize_geo_level(as.character(geo_level))
    .assert_supported_geo_level(geo_level)
    lookup <- lookup[lookup$geo_level == geo_level, , drop = FALSE]
  }

  geo_id <- as.character(geo_id[1])
  matched <- lookup[lookup$geo_id == geo_id, , drop = FALSE]
  if (nrow(matched) == 0) {
    matched <- lookup[lookup$geo_name == geo_id, , drop = FALSE]
  }

  out <- matched[seq_len(min(nrow(matched), 1L)), , drop = FALSE]
  out$geo_label <- unname(vapply(out$geo_level, function(level) levels[[level]]$label, character(1)))
  out$location <- out$geo_name
  out$geographic_scale <- out$geo_label
  out$administrative_location_id <- out$geo_id
  if ("population_size_synth_scaled" %in% names(out)) {
    out$population_size <- out$population_size_synth_scaled
  }

  row.names(out) <- NULL
  out
}

build_geo_lookup <- function(cfg = NULL, overwrite = FALSE) {
  cfg <- cfg %||% miama_default_config()
  lookup_path <- .geo_lookup_path(cfg)

  if (file.exists(lookup_path) && !isTRUE(overwrite)) {
    message("Geo lookup already exists, skipping: ", lookup_path)
    return(readRDS(lookup_path))
  }

  source <- cfg$sources$sp_attributes
  source_path <- source$path
  source_format <- source$format

  if (!identical(source_format, "parquet") || !dir.exists(source_path)) {
    stop("Synthpop attributes parquet directory not found: ", source_path, call. = FALSE)
  }

  message("Building geo lookup from synthpop attributes: ", source_path)
  ind_geo <- .read_synthpop_geo_columns(source_path, source_format)
  lookup <- .summarize_geo_lookup(ind_geo)

  dir.create(dirname(lookup_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(lookup, lookup_path)
  message("Cached geo lookup to: ", lookup_path)

  lookup
}

.load_geo_lookup <- function(cfg = NULL, refresh = FALSE) {
  cfg <- cfg %||% miama_default_config()
  lookup_path <- .geo_lookup_path(cfg)

  if (file.exists(lookup_path) && !isTRUE(refresh)) {
    return(readRDS(lookup_path))
  }

  build_geo_lookup(cfg = cfg, overwrite = TRUE)
}

.geo_lookup_path <- function(cfg) {
  file.path(cfg$output$lookup, "geo_options.rds")
}

.read_synthpop_geo_columns <- function(source_path, source_format) {
  geo_cols <- c("region", "lad25cd", "lad25nm")

  if (identical(source_format, "parquet")) {
    ds <- arrow::open_dataset(source_path, format = "parquet")
    missing_cols <- setdiff(geo_cols, names(ds))
    if (length(missing_cols) > 0) {
      stop("Synthpop attributes source is missing geo columns: ",
           paste(missing_cols, collapse = ", "), call. = FALSE)
    }

    return(dplyr::collect(dplyr::select(ds, dplyr::all_of(geo_cols))))
  }

  stop("Unsupported synthpop attributes format: ", source_format,
       ". Runtime synthpop sources must be parquet.", call. = FALSE)
}

.summarize_geo_lookup <- function(ind_geo) {
  required <- c("region", "lad25cd", "lad25nm")
  missing_cols <- setdiff(required, names(ind_geo))
  if (length(missing_cols) > 0) {
    stop("Geo lookup input is missing columns: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  ind_geo$region <- as.character(ind_geo$region)
  ind_geo$lad25cd <- as.character(ind_geo$lad25cd)
  ind_geo$lad25nm <- as.character(ind_geo$lad25nm)

  england <- data.frame(
    geo_level = "eng",
    geo_id = "eng",
    geo_name = "England",
    n_individuals = nrow(ind_geo),
    stringsAsFactors = FALSE
  )

  regions <- stats::aggregate(
    rep(1L, nrow(ind_geo)),
    by = list(geo_id = ind_geo$region, geo_name = ind_geo$region),
    FUN = sum
  )
  names(regions)[names(regions) == "x"] <- "n_individuals"
  regions$geo_level <- "reg"
  regions <- regions[, c("geo_level", "geo_id", "geo_name", "n_individuals")]

  lads <- stats::aggregate(
    rep(1L, nrow(ind_geo)),
    by = list(geo_id = ind_geo$lad25cd, geo_name = ind_geo$lad25nm),
    FUN = sum
  )
  names(lads)[names(lads) == "x"] <- "n_individuals"
  lads$geo_level <- "lad"
  lads <- lads[, c("geo_level", "geo_id", "geo_name", "n_individuals")]

  out <- rbind(england, regions, lads)
  out <- out[order(match(out$geo_level, names(.geo_level_specs())), out$geo_name, out$geo_id), ]
  out$person_weight <- MIAMA_SYNTHPOP_PERSON_WEIGHT
  out$population_size_synth_scaled <- out$n_individuals * out$person_weight
  out$population_source <- "Census 2021 5% synthpop scale"
  out <- out[, c(
    "geo_level", "geo_id", "geo_name", "n_individuals",
    "person_weight", "population_size_synth_scaled", "population_source"
  )]
  row.names(out) <- NULL
  out
}

.geo_level_specs <- function() {
  list(
    eng = list(label = "England"),
    reg = list(label = "Region"),
    lad = list(label = "Local authority district")
  )
}

.normalize_geo_level <- function(geo_level) {
  if (identical(geo_level, "region")) {
    return("reg")
  }

  geo_level
}

.assert_supported_geo_level <- function(geo_level) {
  supported <- names(.geo_level_specs())
  if (!geo_level %in% supported) {
    stop("Unsupported geo_level: ", geo_level,
         ". Supported levels: ", paste(supported, collapse = ", "), call. = FALSE)
  }

  invisible(TRUE)
}
