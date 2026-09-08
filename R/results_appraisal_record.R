# Completed-run appraisal record. Keep this separate from rendering and never
# export profile additional_data, source paths, or individual/trip records.
.appraisal_record_table <- function(values, prefix = "") {
  empty <- data.frame(parameter = character(), value = character())
  if (is.null(values) || !length(values)) return(empty)
  rows <- lapply(names(values), function(name) {
    key <- if (nzchar(prefix)) paste(prefix, name, sep = ".") else name
    value <- values[[name]]
    if (is.list(value) && !is.data.frame(value)) {
      return(.appraisal_record_table(value, key))
    }
    if (!is.atomic(value) || !length(value)) return(empty)
    if (!is.null(names(value))) value <- paste(names(value), value, sep = "=")
    data.frame(parameter = key, value = paste(value, collapse = "; "),
               stringsAsFactors = FALSE)
  })
  if (!length(rows)) empty else do.call(rbind, rows)
}

.prepare_appraisal_record <- function(values, cfg) {
  # Calculation values have already passed the input mapper. Retain the
  # contract, not browser action buttons, display state or nested source data.
  keys <- grep(paste0("^(appraisal_name$|geo_|modes$|ui_version$|at_|",
                     "users_|trips_|pop_|default_|assump_|scheme_|",
                     "new_user_|induced_|sampling_|seed$)"),
               names(values), value = TRUE)
  keys <- keys[!grepl("(_save|_close|_output|_show|_additional_data)$", keys)]
  config <- cfg[intersect(c("workflow", "population", "physical_activity",
                            "counterfactual"), names(cfg))]
  config$population <- cfg$population[intersect(
    c("person_weight", "source", "units_contract", "source_person_weight",
      "source_population_description"), names(cfg$population))]
  config$assessment_period_years <- get_assessment_period(cfg)
  list(
    captured_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    export_config = list(population = config$population,
                        results = list(assessment_period_years = get_assessment_period(cfg))),
    calculation_inputs = .appraisal_record_table(values[keys]),
    model_parameters = .appraisal_record_table(config)
  )
}

.appraisal_submitted_settings <- function(profile) {
  keys <- names(profile)[vapply(profile, function(x) {
    is_input_field(x) && isTRUE(x$is_filled) && !is.null(x$input_value)
  }, logical(1))]
  # Use the same allowlist as the calculation record. Inactive saved settings
  # may appear here; they are deliberately not labelled as effective inputs.
  values <- lapply(profile[keys], function(x) x$input_value)
  .prepare_appraisal_record(values, list())$calculation_inputs
}

.results_report_sections <- function(exports) {
  record <- exports$appraisal_record
  list(
    "Appraisal metadata" = exports$metadata,
    "Submitted settings (may include inactive settings)" = record$submitted_settings,
    "Effective calculation inputs and accepted table values" = record$calculation_inputs,
    "Realized population counts (unscaled records)" = record$population_counts,
    "Person donor reuse (copies are not independent evidence)" = record$donor_reuse,
    "Realized travel by mode" = exports$trip_mode_distribution,
    "Health results" = exports$results_table,
    "Annual health impacts" = exports$amat_health_timeline,
    "Effective completion assumptions and provenance" = exports$assumption_details,
    "Configured model parameters (defaults may be overridden above)" = record$model_parameters,
    "Health calculation diagnostics" = record$health_diagnostics,
    "Export selection" = exports$filters,
    "Conventions and limitations" = exports$assumptions
  )
}

.appraisal_population_counts <- function(reference_data, counterfactual_data) {
  scopes <- list(Reference = reference_data, Counterfactual = counterfactual_data)
  do.call(rbind, lapply(names(scopes), function(scenario) {
    people <- scopes[[scenario]]$ind
    modes <- c("walk", "bike", "ebike", "pt")
    counts <- vapply(modes, function(mode) {
      flag <- people[[paste0(".miama_user_scope_", mode)]]
      if (is.null(flag)) NA_integer_ else sum(flag %in% TRUE)
    }, integer(1))
    data.frame(scenario = scenario, group = c("Total", modes),
               records = c(if (is.null(people)) NA_integer_ else nrow(people), counts))
  }))
}

# HTML needs no Pandoc/LaTeX and remains a single downloadable, printable file.
.results_export_html <- function(exports) {
  esc <- function(x) {
    x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    gsub(">", "&gt;", x, fixed = TRUE)
  }
  table <- function(data) {
    if (is.null(data) || !nrow(data)) return("<p>Not recorded for this run.</p>")
    cells <- apply(data, 1, function(row) paste0("<tr><td>",
      paste(esc(ifelse(is.na(row), "", row)), collapse = "</td><td>"), "</td></tr>"))
    paste0("<div class='table-wrap'><table><thead><tr><th>",
      paste(esc(names(data)), collapse = "</th><th>"),
      "</th></tr></thead><tbody>", paste(cells, collapse = "\n"),
      "</tbody></table></div>")
  }
  sections <- .results_report_sections(exports)
  c("<!doctype html><html lang='en'><head><meta charset='utf-8'>",
    "<meta name='viewport' content='width=device-width, initial-scale=1'>",
    paste0("<title>", esc(exports$report$title), "</title>"),
    "<style>body{font:15px/1.5 sans-serif;margin:32px auto;padding:0 24px;max-width:1200px;color:#222}h1,h2{color:#176351}h2{margin-top:36px}.table-wrap{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13px}td,th{padding:8px;text-align:left;border-bottom:1px solid #ddd;overflow-wrap:anywhere}th{background:#eee}@media print{body{margin:0;padding:0}table{font-size:9px}thead{display:table-header-group}.table-wrap{overflow:visible}}</style></head><body>",
    paste0("<h1>", esc(exports$report$title), "</h1><p>Generated: ",
           esc(exports$generated_at_utc), "</p>"),
    paste0("<p>", esc(exports$report$summary), "</p>"),
    "<h2>Approach</h2>", paste0("<p>", esc(exports$report$methods), "</p>"),
    unlist(lapply(names(sections), function(name) {
      c(paste0("<h2>", esc(name), "</h2>"), table(sections[[name]]))
    }), use.names = FALSE), "</body></html>")
}
