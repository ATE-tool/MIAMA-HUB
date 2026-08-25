# MIAMA-HUB Dev Workflow: Tab 5 Result Exports
# -----------------------------------------------------------------------------
# Run after `inst/workflows/dev_workflow.R` has created `results_exports` in
# Step 9. This writes the same static bundle MIAMA-UI creates immediately after
# results are built. Later Tab 5 filter-panel changes currently affect on-screen
# plots only and do not rebuild this download bundle.

if (!exists("results_exports")) {
  stop("Run dev_workflow.R through Step 9 before dev_results_exports.R.", call. = FALSE)
}

export_dir <- file.path(cfg$output$root, "dev_results_exports")
dir.create(export_dir, recursive = TRUE, showWarnings = FALSE)

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
# results_exports$timeline_annual
# results_exports$timeline_cumulative
# results_exports$trip_mode_distribution
# results_exports$amat_inputs
# results_exports$amat_health_timeline
# results_exports$amat_health_summary
# results_exports$report
