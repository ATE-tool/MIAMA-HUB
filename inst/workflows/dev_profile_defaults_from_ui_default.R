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

cfg <- miama_default_config()
cfg$workflow$dataset_size <- "sample"
cfg$cache$enabled <- TRUE
cfg$cache$refresh <- FALSE


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

profile <- set_profile_input(profile, "ui_version", "advanced")
profile <- set_profile_input(profile, "ui_input_scope", "counter")
profile <- set_profile_input(profile, "geo_level", "lad")
profile <- set_profile_input(profile, "geo_id", "E08000035")
profile <- set_profile_input(profile, "modes", c("walking", "cycling"))
profile <- set_profile_input(profile, "intervention_type", "infras")
profile <- set_profile_input(profile, "data_source", "counts")

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

format_profile_value <- function(x) {
  if (is.null(x)) {
    return(NA_character_)
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
  grepl("_ref$|^geo_name$|^population_size$|^pop_total_ref$", profile_defaults_filled$field),
  ,
  drop = FALSE
]

message("Reference defaults updated: ", length(reference_defaults_report$updated_fields))
message("Reference defaults skipped: ", length(reference_defaults_report$skipped_fields))
if (length(reference_defaults_report$skipped_fields) > 0) {
  message("Skipped fields: ", paste(reference_defaults_report$skipped_fields, collapse = ", "))
}

profile_reference_fields |>
  utils::head(60) |>
  print(row.names = FALSE)

# Useful interactive inspection commands:
# View(profile_defaults_filled)
# View(profile_reference_fields)
# str(profile_with_defaults$geo_name)
# str(profile_with_defaults$population_size)
# str(profile_with_defaults$pop_total_ref)
# str(profile_with_defaults$users_count_ref_walk)
# str(profile_with_defaults$trips_count_ref_bike)
# reference_defaults_report
