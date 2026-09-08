# Inspect actual source quantities, not just UI labels. Run with HUB loaded.
# Optional: set audit_health_data to a completed run's health_outcomes first.
if (!exists("cfg")) cfg <- MIAMAHUB::miama_default_config("leeds")
if (!exists("audit_output_dir")) audit_output_dir <- file.path(tempdir(), "miama-health-units-audit")
dir.create(audit_output_dir, recursive = TRUE, showWarnings = FALSE)
audit_source <- if (exists("audit_health_data")) {
  "Supplied health outcome table"
} else {
  path <- cfg$sources$hm_death_share$cycle$path
  if (is.null(path)) stop("Set audit_health_data or configure cfg$sources$hm_death_share$cycle$path")
  audit_health_data <- as.data.frame(arrow::open_dataset(path))
  path
}
catalogue <- MIAMAHUB::get_health_outcome_options(cfg, health_data = audit_health_data)
utils::write.csv(catalogue, file.path(audit_output_dir, "outcome_catalogue.csv"), row.names = FALSE)
columns <- names(audit_health_data)[vapply(audit_health_data, is.numeric, logical(1))]
columns <- setdiff(columns, c("census_id", "cycle", "age1year", "female", "mr_decile", "mmets", "mmets_cycle"))
field_summary <- do.call(rbind, lapply(columns, function(field) {
  x <- audit_health_data[[field]]
  ok <- is.finite(x)
  data.frame(field = field, rows = length(x), nonfinite = sum(!ok),
    minimum = if (any(ok)) min(x[ok]) else NA_real_,
    maximum = if (any(ok)) max(x[ok]) else NA_real_,
    mean = if (any(ok)) mean(x[ok]) else NA_real_)
}))
utils::write.csv(field_summary, file.path(audit_output_dir, "source_field_ranges.csv"), row.names = FALSE)
rows <- table(audit_health_data$cycle, useNA = "ifany")
utils::write.csv(as.data.frame(rows), file.path(audit_output_dir, "rows_by_cycle.csv"), row.names = FALSE)
writeLines(c(paste("Source:", audit_source),
  paste("Person weight:", cfg$population$person_weight),
  "Ranges do not establish units: use the HM aggregation equations and HUB catalogue.",
  "No individual IDs are exported. Source tables have no d_* or HALY fields until calculated by HUB."),
  file.path(audit_output_dir, "README.txt"))
message("Health units audit written to: ", normalizePath(audit_output_dir))
