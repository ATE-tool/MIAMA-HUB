# MIAMA-HUB Dev Workflow: Fill Reference Defaults In A Real MIAMA-UI Profile
# -----------------------------------------------------------------------------
# Purpose:
#   Load the actual MIAMA-UI `schemes/default.R` profile, set the minimum setup
#   fields that a Shiny user would choose, run the HUB reference-data pipeline,
#   and write derived reference values into profile `default_value` fields.
#
# Use:
#   Run this file interactively, section by section. The resulting
#   `profile_with_defaults` object has the same list shape as
#   `mdata[["profile"]]` in MIAMA-UI, with HUB-derived reference defaults added.
#   From a shell, prefer:
#     Rscript --vanilla inst/workflows/dev_profile_defaults_from_ui_default.R
#
# Notes:
#   - This script reads MIAMA-UI but does not edit it.
#   - Set `MIAMA_UI_ROOT` if MIAMA-UI is not a sibling of MIAMA-HUB.
#   - Set `MIAMA_PROJECT_ROOT` if running from outside the MIAMA-HUB repo.


# 0. Setup ----
# -----------------------------------------------------------------------------#

find_miama_hub_root <- function(start = getwd()) {
  env_root <- Sys.getenv("MIAMA_PROJECT_ROOT", unset = "")
  candidates <- unique(c(
    env_root[nzchar(env_root)],
    start,
    file.path(start, "MIAMA-HUB"),
    file.path(dirname(start), "MIAMA-HUB")
  ))

  for (candidate in candidates) {
    desc <- file.path(candidate, "DESCRIPTION")
    if (file.exists(desc) && identical(unname(read.dcf(desc)[1, "Package"]), "MIAMAHUB")) {
      return(normalizePath(candidate, winslash = "/", mustWork = FALSE))
    }
  }

  stop("Could not find MIAMA-HUB package root. Set MIAMA_PROJECT_ROOT.", call. = FALSE)
}

find_miama_ui_root <- function(hub_root) {
  env_root <- Sys.getenv("MIAMA_UI_ROOT", unset = "")
  candidates <- unique(c(
    env_root[nzchar(env_root)],
    file.path(dirname(hub_root), "MIAMA-UI")
  ))

  for (candidate in candidates) {
    default_scheme <- file.path(candidate, "schemes", "default.R")
    constants <- file.path(candidate, "constants.R")
    if (file.exists(default_scheme) && file.exists(constants)) {
      return(normalizePath(candidate, winslash = "/", mustWork = FALSE))
    }
  }

  stop("Could not find MIAMA-UI. Set MIAMA_UI_ROOT to the MIAMA-UI folder.", call. = FALSE)
}

hub_root <- find_miama_hub_root()
ui_root <- find_miama_ui_root(hub_root)

devtools::load_all(hub_root)

cfg <- miama_default_config(
  dataset_size = Sys.getenv("MIAMA_DEV_DATASET_SIZE", "sample")
)
cfg$cache$enabled <- TRUE
cfg$cache$refresh <- FALSE

# Development scenario to inspect. The defaults below mirror the default Tab 2
# path: Leeds, basic UI, trips entered as weekly totals for walking/cycling.
dev_geo_level <- Sys.getenv("MIAMA_DEV_GEO_LEVEL", "lad")
dev_geo_id <- Sys.getenv("MIAMA_DEV_GEO_ID", "E08000035")
dev_ui_version <- Sys.getenv("MIAMA_DEV_UI_VERSION", "basic")
dev_at_data_unit <- Sys.getenv("MIAMA_DEV_AT_DATA_UNIT", "trips")
dev_modes <- strsplit(Sys.getenv("MIAMA_DEV_MODES", "walking,cycling"), ",", fixed = TRUE)[[1]]
dev_trips_timeframe <- Sys.getenv("MIAMA_DEV_TRIPS_TIMEFRAME", "week")
dev_trips_denominator <- Sys.getenv("MIAMA_DEV_TRIPS_DENOMINATOR", "total")


# 1. Load MIAMA-UI default profile ----
# -----------------------------------------------------------------------------#
# Mirrors the relevant part of MIAMA-UI/global.R: load constants first, then
# source `schemes/default.R` in an environment that can see those constants.

load_ui_default_profile <- function(ui_root) {
  ui_env <- new.env(parent = globalenv())
  source(file.path(ui_root, "constants.R"), local = ui_env)

  scheme_env <- new.env(parent = ui_env)
  source(file.path(ui_root, "schemes", "default.R"), local = scheme_env)

  scheme_env$appraisal_inputs
}

profile <- load_ui_default_profile(ui_root)


# 2. Fill minimal setup inputs ----
# -----------------------------------------------------------------------------#
# These are the fields a user would normally select in Tab 1. Values are written
# to `input_value` and marked with `is_filled = TRUE`; reference defaults remain
# separate and will be written later to `default_value`.

set_profile_input <- function(profile, field_name, value) {
  if (!field_name %in% names(profile)) {
    stop("Profile field not found: ", field_name, call. = FALSE)
  }

  profile[[field_name]]$input_value <- value
  profile[[field_name]]$is_filled <- TRUE
  profile
}

set_profile_input_if_present <- function(profile, field_name, value) {
  if (!field_name %in% names(profile)) {
    return(profile)
  }

  set_profile_input(profile, field_name, value)
}

profile <- set_profile_input(profile, "ui_version", dev_ui_version)
profile <- set_profile_input(profile, "ui_input_scope", "counter")
profile <- set_profile_input(profile, "geo_level", dev_geo_level)
profile <- set_profile_input(profile, "geo_id", dev_geo_id)
profile <- set_profile_input(profile, "modes", dev_modes)
profile <- set_profile_input(profile, "intervention_type", "infras")
profile <- set_profile_input(profile, "data_source", "counts")
profile <- set_profile_input(profile, "at_data_unit", dev_at_data_unit)

for (mode_suffix in c("walk", "bike")) {
  profile <- set_profile_input_if_present(
    profile,
    paste0("trips_timeframe_", mode_suffix),
    dev_trips_timeframe
  )
  profile <- set_profile_input_if_present(
    profile,
    paste0("trips_denominator_", mode_suffix),
    dev_trips_denominator
  )
}

# Results defaults are not required for reference extraction, but setting them
# keeps the internal request object close to a real appraisal session.
profile <- set_profile_input_if_present(profile, "res_aggregation", "total")
profile <- set_profile_input_if_present(profile, "res_temp_aggregation", "total")


# 3. Run HUB reference pipeline and fill profile defaults ----
# -----------------------------------------------------------------------------#
# This is the UI-facing call. It loads, joins, filters, and summarizes reference
# data as needed, then writes all matching values into `default_value`.

hub <- Hub$new(cfg = cfg)

setup_profile <- hub$get_appraisal_setup_inputs(profile)
profile_with_defaults <- hub$build_reference_profile_defaults(profile)
reference_defaults_report <- attr(profile_with_defaults, "reference_defaults_report")


# 4. Inspect profile values ----
# -----------------------------------------------------------------------------#
# `profile_with_defaults` is the object to inspect directly. The overview table
# gives a compact view of fields that now have non-null `default_value`s.

format_profile_value <- function(x, digits = 6) {
  if (is.null(x)) {
    return(NA_character_)
  }
  if (is.atomic(x) && length(x) == 1) {
    if (is.numeric(x)) {
      return(format(signif(x, digits), scientific = FALSE, trim = TRUE))
    }
    return(as.character(x))
  }
  if (is.atomic(x)) {
    if (is.numeric(x)) {
      return(paste(format(signif(x, digits), scientific = FALSE, trim = TRUE), collapse = ", "))
    }
    return(paste(as.character(x), collapse = ", "))
  }

  paste(capture.output(str(x, vec.len = 5, give.attr = FALSE)), collapse = " ")
}

profile_defaults_overview <- data.frame(
  field = names(profile_with_defaults),
  is_filled = vapply(profile_with_defaults, function(x) isTRUE(x$is_filled), logical(1)),
  input_value = vapply(profile_with_defaults, function(x) format_profile_value(x$input_value), character(1)),
  default_value = vapply(profile_with_defaults, function(x) format_profile_value(x$default_value), character(1)),
  stringsAsFactors = FALSE
)

profile_defaults_filled <- profile_defaults_overview[
  !is.na(profile_defaults_overview$default_value),
  ,
  drop = FALSE
]

profile_reference_fields <- profile_defaults_filled[
  grepl("_ref_|_ref$|^geo_name$|^population_size$", profile_defaults_filled$field),
  ,
  drop = FALSE
]

geo_details <- get_geo_details(
  cfg,
  profile$geo_id$input_value,
  geo_level = profile$geo_level$input_value
)

reference_context <- data.frame(
  dataset_size = cfg$workflow$dataset_size,
  geo_name = geo_details$geo_name,
  geo_level = geo_details$geo_level,
  geo_id = geo_details$geo_id,
  ui_version = profile$ui_version$input_value,
  at_data_unit = profile$at_data_unit$input_value,
  modes = paste(profile$modes$input_value, collapse = ", "),
  n_reference_ind_rows = nrow(hub$reference_default_data$ind),
  n_reference_trip_rows = nrow(hub$reference_default_data$trips),
  stringsAsFactors = FALSE
)

updated_fields <- reference_defaults_report$updated_fields
reference_defaults_changed <- data.frame(
  field = updated_fields,
  default_value = vapply(
    updated_fields,
    function(field) format_profile_value(profile_with_defaults[[field]]$default_value),
    character(1)
  ),
  stringsAsFactors = FALSE
)

classify_reference_default_field <- function(field) {
  if (field %in% c(
    "geo_name", "population_size", "pop_total_ref_basic", "pop_total_ref_advanced"
  )) {
    return("summary")
  }
  if (grepl("^users_count_ref_|^pop_number_ref_|^pop_spread_", field)) {
    return("users_population")
  }
  if (grepl("^trips_count_ref_|^trips_number_|^trips_spread_|^trips_diversion_", field)) {
    return("trips")
  }
  if (grepl("^dist_dur_", field)) {
    return("distance_duration")
  }
  if (grepl("^mode_share_", field)) {
    return("mode_share")
  }
  "other"
}

reference_defaults_changed$group <- vapply(
  reference_defaults_changed$field,
  classify_reference_default_field,
  character(1)
)
reference_defaults_changed <- reference_defaults_changed[
  order(reference_defaults_changed$group, reference_defaults_changed$field),
  ,
  drop = FALSE
]

trip_count_defaults <- reference_defaults_changed[
  grepl("^trips_count_ref_", reference_defaults_changed$field),
  ,
  drop = FALSE
]

backup_fields <- reference_defaults_report$default_value_backup_fields %||% character(0)
reference_default_backups <- data.frame(
  field = backup_fields,
  default_value = vapply(
    backup_fields,
    function(field) format_profile_value(profile_with_defaults[[field]]$default_value),
    character(1)
  ),
  default_value_backup = vapply(
    backup_fields,
    function(field) {
      format_profile_value(
        profile_with_defaults[[field]]$additional_data$default_value_backup
      )
    },
    character(1)
  ),
  stringsAsFactors = FALSE
)

if (nrow(trip_count_defaults) > 0) {
  trip_count_defaults$timeframe <- vapply(
    sub("^trips_count_ref_", "", trip_count_defaults$field),
    function(mode_suffix) {
      profile[[paste0("trips_timeframe_", mode_suffix)]]$input_value %||% NA_character_
    },
    character(1)
  )
  trip_count_defaults$denominator <- vapply(
    sub("^trips_count_ref_", "", trip_count_defaults$field),
    function(mode_suffix) {
      profile[[paste0("trips_denominator_", mode_suffix)]]$input_value %||% NA_character_
    },
    character(1)
  )
}

message("Reference context:")
print(reference_context, row.names = FALSE)

message("Reference defaults updated: ", length(reference_defaults_report$updated_fields))
message("Reference defaults skipped: ", length(reference_defaults_report$skipped_fields))
if (length(reference_defaults_report$skipped_fields) > 0) {
  message("Skipped fields: ", paste(reference_defaults_report$skipped_fields, collapse = ", "))
}

message("Reference defaults changed in profile:")
print(reference_defaults_changed, row.names = FALSE)

if (nrow(reference_default_backups) > 0) {
  message("Advanced population default backups:")
  print(reference_default_backups, row.names = FALSE)
}

if (nrow(trip_count_defaults) > 0) {
  message("Trip count defaults for Tab 2 modal checks:")
  print(trip_count_defaults, row.names = FALSE)
}

# Useful interactive inspection commands:
# View(profile_defaults_filled)
# View(profile_reference_fields)
# View(reference_defaults_changed)
# View(reference_default_backups)
# View(trip_count_defaults)
# str(profile_with_defaults$geo_name)
# str(profile_with_defaults$population_size)
# str(profile_with_defaults$pop_total_ref_basic)
# str(profile_with_defaults$pop_total_ref_advanced)
# str(profile_with_defaults$users_count_ref_walk)
# str(profile_with_defaults$trips_count_ref_bike)
# reference_defaults_report
