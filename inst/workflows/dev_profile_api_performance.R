# MIAMA-HUB Dev Workflow: Profile The UI-Facing API Pipeline
# -----------------------------------------------------------------------------
# Purpose:
#   Measure elapsed time, process memory, retained HUB object sizes, and R call
#   stacks for the same two heavy API methods used by MIAMA-UI:
#   `build_reference_profile_defaults()` and `build_results()`.
#
# Full-data use:
#   MIAMA_PROFILE_DATASET_SIZE=full \
#   MIAMA_PROFILE_GEO_ID=E08000025 \
#   Rscript --no-init-file inst/workflows/dev_profile_api_performance.R
#
# Configuration:
#   - MIAMA_PROFILE_DATASET_SIZE: sample (default) or full.
#   - MIAMA_PROFILE_GEO_LEVEL: lad (default), reg, msoa, or eng.
#   - MIAMA_PROFILE_GEO_ID: E08000035 (Leeds, default).
#   - MIAMA_PROFILE_OUTPUT_DIR: optional report directory; defaults to tempdir().
#   - MIAMA_UI_ROOT: needed only when MIAMA-UI is not a sibling of MIAMA-HUB.
#
# `--no-init-file` bypasses project renv activation (and possible lock waits)
# while retaining values from the user's/project `.Renviron`.
#
# Output:
#   CSV summaries plus the raw Rprof file are written to the output directory.
#   Boundary RSS is useful for retained memory; Rprof's memory output identifies
#   allocation-heavy call stacks but is not a precise operating-system peak.


# 0. Locate Repositories -----------------------------------------------------

find_miama_hub_root <- function(start = getwd()) {
  env_root <- Sys.getenv("MIAMA_PROJECT_ROOT", unset = "")
  candidates <- unique(c(
    env_root[nzchar(env_root)], start, file.path(start, "MIAMA-HUB"),
    file.path(dirname(start), "MIAMA-HUB")
  ))

  for (candidate in candidates) {
    desc <- file.path(candidate, "DESCRIPTION")
    if (file.exists(desc) &&
        identical(unname(read.dcf(desc)[1, "Package"]), "MIAMAHUB")) {
      return(normalizePath(candidate, winslash = "/", mustWork = FALSE))
    }
  }
  stop("Could not find MIAMA-HUB. Set MIAMA_PROJECT_ROOT.", call. = FALSE)
}

find_miama_ui_root <- function(hub_root) {
  env_root <- Sys.getenv("MIAMA_UI_ROOT", unset = "")
  candidates <- unique(c(
    env_root[nzchar(env_root)], file.path(dirname(hub_root), "MIAMA-UI")
  ))

  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "schemes", "default.R")) &&
        file.exists(file.path(candidate, "constants.R"))) {
      return(normalizePath(candidate, winslash = "/", mustWork = FALSE))
    }
  }
  stop("Could not find MIAMA-UI. Set MIAMA_UI_ROOT.", call. = FALSE)
}

hub_root <- find_miama_hub_root()
ui_root <- find_miama_ui_root(hub_root)
devtools::load_all(hub_root)


# 1. Runtime Configuration --------------------------------------------------

dataset_size <- Sys.getenv("MIAMA_PROFILE_DATASET_SIZE", unset = "sample")
geo_level <- Sys.getenv("MIAMA_PROFILE_GEO_LEVEL", unset = "lad")
geo_id <- Sys.getenv("MIAMA_PROFILE_GEO_ID", unset = "E08000035")
if (identical(geo_level, "eng")) geo_id <- NULL

output_dir <- Sys.getenv("MIAMA_PROFILE_OUTPUT_DIR", unset = "")
if (!nzchar(output_dir)) {
  output_dir <- file.path(
    tempdir(), paste0("miama-api-profile-", format(Sys.time(), "%Y%m%d-%H%M%S"))
  )
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cfg <- miama_default_config(dataset_size = dataset_size)
cfg$cache$enabled <- TRUE
cfg$cache$refresh <- FALSE


# 2. Load A Real UI Profile -------------------------------------------------

load_ui_default_profile <- function(ui_root) {
  ui_env <- new.env(parent = globalenv())
  source(file.path(ui_root, "constants.R"), local = ui_env)
  scheme_env <- new.env(parent = ui_env)
  source(file.path(ui_root, "schemes", "default.R"), local = scheme_env)
  scheme_env$appraisal_inputs
}

set_profile_input <- function(profile, field, value) {
  if (!field %in% names(profile)) {
    stop("Profile field not found: ", field, call. = FALSE)
  }
  profile[[field]]$input_value <- value
  profile[[field]]$is_filled <- TRUE
  profile
}

profile <- load_ui_default_profile(ui_root)
profile <- set_profile_input(profile, "ui_version", "advanced")
profile <- set_profile_input(profile, "ui_input_scope", "counter")
profile <- set_profile_input(profile, "geo_level", geo_level)
profile <- set_profile_input(profile, "geo_id", geo_id)
profile <- set_profile_input(profile, "modes", c("walking", "cycling"))
profile <- set_profile_input(profile, "intervention_type", "infras")
profile <- set_profile_input(profile, "data_source", "counts")
if ("res_aggregation" %in% names(profile)) {
  profile <- set_profile_input(profile, "res_aggregation", "total")
}
if ("res_temp_aggregation" %in% names(profile)) {
  profile <- set_profile_input(profile, "res_temp_aggregation", "total")
}


# 3. Measurement Helpers ----------------------------------------------------

rss_mb <- function() {
  value <- suppressWarnings(system2(
    "ps", c("-o", "rss=", "-p", Sys.getpid()), stdout = TRUE, stderr = FALSE
  ))
  if (length(value) == 0L) return(NA_real_)
  as.numeric(trimws(value[[1L]])) / 1024
}

object_mb <- function(x) {
  if (is.null(x)) return(0)
  as.numeric(utils::object.size(x)) / 1024^2
}

measurements <- list()
measure_stage <- function(label, code) {
  invisible(gc(verbose = FALSE))
  before <- rss_mb()
  timing <- system.time(value <- force(code))
  after <- rss_mb()
  measurements[[length(measurements) + 1L]] <<- data.frame(
    stage = label,
    elapsed_seconds = unname(timing[["elapsed"]]),
    user_seconds = unname(timing[["user.self"]]),
    system_seconds = unname(timing[["sys.self"]]),
    rss_before_mb = before,
    rss_after_mb = after,
    rss_change_mb = after - before,
    stringsAsFactors = FALSE
  )
  value
}

hub_state_sizes <- function(hub, stage) {
  fields <- c(
    "reference_default_data", "reference_default_ui_values",
    "reference_sources", "reference_data_raw", "reference_data",
    "counterfactual_data", "health_impacts", "results_data"
  )
  data.frame(
    stage = stage,
    object = fields,
    size_mb = vapply(fields, function(field) object_mb(hub[[field]]), numeric(1)),
    stringsAsFactors = FALSE
  )
}

hub_table_inventory <- function(hub, stage) {
  tables <- list(
    reference_default_ind = hub$reference_default_data$ind,
    reference_default_trips = hub$reference_default_data$trips,
    reference_ind = hub$reference_data$ind,
    reference_trips = hub$reference_data$trips,
    counterfactual_ind = hub$counterfactual_data$ind,
    counterfactual_trips = hub$counterfactual_data$trips,
    health_outcomes = hub$counterfactual_data$health_outcomes,
    results_table = hub$results_data$results_table,
    health_cube = hub$results_data$plot_data$health_cube
  )
  tables <- tables[!vapply(tables, is.null, logical(1))]
  out <- if (length(tables) == 0L) {
    data.frame(
      stage = character(0), table = character(0), rows = integer(0),
      columns = integer(0), size_mb = numeric(0)
    )
  } else {
    data.frame(
      stage = stage,
      table = names(tables),
      rows = vapply(tables, nrow, integer(1)),
      columns = vapply(tables, ncol, integer(1)),
      size_mb = vapply(tables, object_mb, numeric(1)),
      stringsAsFactors = FALSE
    )
  }
  if (!is.null(hub$health_impacts) &&
      !isTRUE(hub$health_impacts$cycle_data_retained)) {
    out <- rbind(out, data.frame(
      stage = stage,
      table = "health_outcomes_released",
      rows = hub$health_impacts$n_cycle_rows,
      columns = hub$health_impacts$n_cycle_columns,
      size_mb = hub$health_impacts$cycle_data_size_mb,
      stringsAsFactors = FALSE
    ))
  }
  out
}

state_sizes <- list()
table_inventories <- list()
profile_file <- file.path(output_dir, "api_pipeline.Rprof")


# 4. Profile UI-Facing API Calls --------------------------------------------

run_api_profile <- function() {
  utils::Rprof(profile_file, interval = 0.02, memory.profiling = TRUE)
  on.exit(utils::Rprof(NULL), add = TRUE)

  hub <- Hub$new(cfg = cfg)
  profile_with_defaults <- measure_stage(
    "build_reference_profile_defaults",
    hub$build_reference_profile_defaults(profile)
  )
  state_sizes[[length(state_sizes) + 1L]] <<-
    hub_state_sizes(hub, "after_reference_defaults")
  table_inventories[[length(table_inventories) + 1L]] <<-
    hub_table_inventory(hub, "after_reference_defaults")

  # Exercise a realistic but bounded scenario: increase physical active-mode
  # trip rows by approximately 10% for each mode. Physical rows are used here
  # because they are the direct target of the current sampling mechanism.
  for (mode in c("walking", "cycling")) {
    suffix <- .miama_mode_suffix(mode)
    spec <- .miama_tab2_mode_specs()[[mode]]
    trips <- hub$reference_default_data$trips
    ref_rows <- sum(spec$trip_filter(trips) & !is.na(trips$nts_tripid), na.rm = TRUE)
    target_rows <- as.integer(max(ref_rows, round(ref_rows * 1.10)))

    profile_with_defaults <- set_profile_input(
      profile_with_defaults, paste0("trips_timeframe_", suffix), "week"
    )
    profile_with_defaults <- set_profile_input(
      profile_with_defaults, paste0("trips_denominator_", suffix), "total"
    )
    profile_with_defaults <- set_profile_input(
      profile_with_defaults, paste0("trips_count_cf_", suffix), target_rows
    )
  }

  results <- measure_stage(
    "build_results",
    hub$build_results(profile_with_defaults, seed = 1L)
  )
  state_sizes[[length(state_sizes) + 1L]] <<-
    hub_state_sizes(hub, "after_results")
  table_inventories[[length(table_inventories) + 1L]] <<-
    hub_table_inventory(hub, "after_results")

  list(hub = hub, profile = profile_with_defaults, results = results)
}

profile_run <- run_api_profile()


# 5. Save And Print Reports -------------------------------------------------

stage_timings <- do.call(rbind, measurements)
state_size_report <- do.call(rbind, state_sizes)
table_inventory_report <- do.call(rbind, table_inventories)
profile_summary <- summaryRprof(profile_file, memory = "both")

utils::write.csv(
  stage_timings, file.path(output_dir, "stage_timings.csv"), row.names = FALSE
)
utils::write.csv(
  state_size_report, file.path(output_dir, "hub_state_sizes.csv"), row.names = FALSE
)
utils::write.csv(
  table_inventory_report,
  file.path(output_dir, "table_inventory.csv"),
  row.names = FALSE
)
utils::write.csv(
  profile_summary$by.total,
  file.path(output_dir, "rprof_by_total.csv"), row.names = TRUE
)
utils::write.csv(
  profile_summary$by.self,
  file.path(output_dir, "rprof_by_self.csv"), row.names = TRUE
)
saveRDS(
  list(
    settings = list(
      dataset_size = dataset_size, geo_level = geo_level, geo_id = geo_id
    ),
    stage_timings = stage_timings,
    hub_state_sizes = state_size_report,
    table_inventory = table_inventory_report,
    rprof = profile_summary
  ),
  file.path(output_dir, "profile_summary.rds")
)

message("\nAPI performance profile written to: ", output_dir)
print(stage_timings, row.names = FALSE)
print(state_size_report, row.names = FALSE)
print(table_inventory_report, row.names = FALSE)
message("\nTop calls by total sampled time:")
print(utils::head(profile_summary$by.total, 20))
