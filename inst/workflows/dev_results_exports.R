# MIAMA-HUB Dev Workflow: Tab 5 Result Exports
# -----------------------------------------------------------------------------
# Run after `inst/workflows/dev_workflow.R` has created `results_data`, `request`,
# and `cfg`. This script assembles the same filtered export bundle MIAMA-UI will
# use and writes example CSV, Excel, PNG/ZIP, AMAT draft, and report artifacts.

if (!exists("results_data")) {
  stop("Run dev_workflow.R through Step 8 before dev_results_exports.R.", call. = FALSE)
}

profile_for_export <- if (exists("appraisal_inputs")) appraisal_inputs else NULL
export_dir <- file.path(cfg$output$root, "dev_results_exports")
dir.create(export_dir, recursive = TRUE, showWarnings = FALSE)

results_exports <- prepare_results_exports(
  results_data = results_data,
  profile = profile_for_export,
  cfg = cfg,
  outcomes = c("mortality", "ihd", "stroke", "diabetes"),
  aggregation = "total",
  group_by = "outcome",
  timeline_type = "cumulative",
  impact_type = "attributable",
  metric = "prevented_per_100000"
)

write_results_csv(results_exports, file.path(export_dir, "results.csv"))
write_results_xlsx(results_exports, file.path(export_dir, "results.xlsx"))
write_results_plot_pngs(results_exports, file.path(export_dir, "plots"))
write_results_plots_zip(results_exports, file.path(export_dir, "plots.zip"))
write_results_amat_csv(results_exports, file.path(export_dir, "amat_health_timeline_DRAFT.csv"))
write_results_report(results_exports, file.path(export_dir, "report.md"), "markdown")

if (rmarkdown::pandoc_available()) {
  write_results_report(results_exports, file.path(export_dir, "report.docx"), "docx")
}

message("Result export examples written to: ", normalizePath(export_dir, winslash = "/"))

# Inspect the in-memory contract:
# names(results_exports)
# results_exports$metadata
# results_exports$filters
# results_exports$headline_metrics
# results_exports$results_table
# results_exports$amat_inputs
# results_exports$amat_health_timeline
# results_exports$amat_health_summary
# results_exports$report
