# Run with the UI schema PR checkout, not an older default.R.
# MIAMA_UI_SCHEMA_ROOT=/path/to/UI Rscript inst/workflows/dev_verify_assumption_contract.R
ui <- Sys.getenv("MIAMA_UI_SCHEMA_ROOT", unset = "../MIAMA-UI")
schema <- new.env(parent = globalenv())
sys.source(file.path(ui, "constants.R"), envir = schema)
sys.source(file.path(ui, "schemes", "default.R"), envir = schema)
p <- schema$appraisal_inputs
stopifnot("assump_trip_duration_min_pt" %in% names(p))
put <- function(name, value) {
  stopifnot(name %in% names(p))
  p[[name]]$input_value <<- value
  p[[name]]$is_filled <<- TRUE
}
put("geo_level", "lad")
put("geo_id", "E08000035")
put("ui_version", "advanced")
put("modes", c("walk", "bike", "ebike", "pt"))
put("at_data_unit", "trips")
cfg <- MIAMAHUB::miama_default_config("leeds")
hub <- MIAMAHUB::Hub$new(cfg)
p <- hub$build_reference_profile_defaults(p)
stopifnot(all(MIAMAHUB::get_appraisal_assumption_dependencies(p) %in% names(p)))
for (mode in c("walk", "bike", "ebike", "pt")) {
  put(paste0("trips_timeframe_", mode), "week")
  put(paste0("trips_denominator_", mode), "total")
  put(paste0("trips_count_ref_", mode), if (mode == "ebike") 0 else 100)
  put(paste0("trips_count_cf_", mode), if (mode == "ebike") 20 else 120)
}
p <- hub$build_refinement_profile_defaults(p)
p <- hub$build_trip_refinement_profile_defaults(p)
assumptions <- MIAMAHUB::get_appraisal_assumptions(p)
stopifnot(all(names(assumptions) %in% names(p)))
reloaded <- unserialize(serialize(p, NULL))
stopifnot(identical(assumptions, MIAMAHUB::get_appraisal_assumptions(reloaded)))
result <- hub$build_results(reloaded)
stopifnot(is.list(result$results_data$assumptions), !is.null(result$results_data$appraisal_profile))
cat("Four-mode Leeds staging, profile serialization and health-results build passed.\n")
