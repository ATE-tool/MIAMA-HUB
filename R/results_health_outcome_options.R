# MIAMA-HUB Results: Health Outcome Options
#
# Tab 5 outcome choices are stable metadata in `cfg$results$outcomes`. This
# module exposes them in a UI-ready table and can cheaply verify the catalogue
# against a health data object, an Arrow dataset, a parquet directory, or a
# character vector of column names. Schema inspection does not collect rows.


# Public outcome catalogue --------------------------------------------------

get_health_outcome_options <- function(cfg = NULL,
                                       health_data = NULL,
                                       available_only = FALSE) {
  cfg <- cfg %||% miama_default_config()
  specs <- .miama_health_outcome_specs(cfg)
  health_columns <- .miama_health_column_names(health_data)
  checked <- !is.null(health_columns)

  rows <- lapply(names(specs), function(outcome) {
    spec <- specs[[outcome]]
    reference_columns <- as.character(spec$columns)
    delta_columns <- paste0("d_", reference_columns)
    counterfactual_columns <- paste0(reference_columns, "_cf")

    missing_reference <- if (checked) setdiff(reference_columns, health_columns) else character(0)
    missing_delta <- if (checked) setdiff(delta_columns, health_columns) else character(0)
    missing_counterfactual <- if (checked) setdiff(counterfactual_columns, health_columns) else character(0)

    data.frame(
      outcome = outcome,
      label = spec$label,
      type = spec$type,
      category = spec$category,
      direction = spec$direction %||% "lower_is_better",
      unit = spec$unit %||% if (identical(spec$type, "mortality")) "deaths" else "disease cases",
      default = isTRUE(spec$default),
      available = if (checked) length(missing_reference) == 0 else TRUE,
      delta_available = if (checked) length(missing_delta) == 0 else NA,
      counterfactual_available = if (checked) length(missing_counterfactual) == 0 else NA,
      source_columns = paste(reference_columns, collapse = ","),
      missing_source_columns = paste(missing_reference, collapse = ","),
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  if (isTRUE(available_only)) {
    out <- out[out$available, , drop = FALSE]
  }
  out
}


# Internal configuration access --------------------------------------------

.miama_health_outcome_specs <- function(cfg = NULL) {
  cfg <- cfg %||% miama_default_config()
  specs <- cfg$results$outcomes %||% .miama_default_health_outcomes()

  if (!is.list(specs) || is.null(names(specs)) || any(!nzchar(names(specs)))) {
    stop("cfg$results$outcomes must be a named list of outcome definitions.", call. = FALSE)
  }

  required <- c("label", "type", "category", "columns", "default")
  invalid <- names(specs)[vapply(specs, function(spec) {
    !is.list(spec) || length(setdiff(required, names(spec))) > 0 ||
      length(spec$columns) == 0 || any(!nzchar(as.character(spec$columns)))
  }, logical(1))]

  if (length(invalid) > 0) {
    stop(
      "Invalid cfg$results$outcomes definitions: ",
      paste(invalid, collapse = ", "),
      ". Required fields are: ", paste(required, collapse = ", "), ".",
      call. = FALSE
    )
  }

  specs
}


# Health schema inspection --------------------------------------------------

.miama_health_column_names <- function(health_data) {
  if (is.null(health_data)) {
    return(NULL)
  }

  if (is.character(health_data)) {
    if (length(health_data) == 1L && dir.exists(health_data)) {
      return(names(arrow::open_dataset(health_data, format = "parquet")))
    }
    return(unique(health_data))
  }

  columns <- names(health_data)
  if (is.null(columns) || length(columns) == 0) {
    stop(
      "health_data must be a data frame, Arrow dataset, parquet directory, ",
      "or character vector of column names.",
      call. = FALSE
    )
  }

  unique(columns)
}
