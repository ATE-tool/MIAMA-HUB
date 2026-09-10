# Diagnostic counts only: never use donor counts to rescale appraisal outcomes.
.appraisal_population_diagnostics <- function(reference_data, counterfactual_data) {
  cf <- counterfactual_data$ind
  ref <- reference_data$ind
  # Runtime loading may return data.table; use data.frame column selection
  # semantics in this reporting-only helper, without changing the snapshots.
  if (!is.null(cf)) cf <- as.data.frame(cf)
  if (!is.null(ref)) ref <- as.data.frame(ref)
  # CF retains the REF boundary even when the original snapshot is not supplied.
  if (is.null(ref) && "ref_in_scope" %in% names(cf)) ref <- cf

  scope <- function(ind, scenario) {
    field <- paste0(scenario, "_in_scope")
    if (field %in% names(ind)) .true_values(ind[[field]]) else rep(TRUE, nrow(ind))
  }
  count_snapshot <- function(ind, scenario) {
    counts <- c(retained_person_records = NA_integer_, assessed_people = NA_integer_,
                retained_unique_source_donors = NA_integer_,
                assessed_unique_source_donors = NA_integer_,
                retained_copied_records = NA_integer_, assessed_copied_records = NA_integer_)
    if (!is.null(ind)) {
      included <- scope(ind, scenario)
      counts[1:2] <- c(nrow(ind), sum(included))
      ids <- ind$census_id
      donors <- ind[[".miama_donor_census_id"]] %||% ids
      # Missing provenance is unknown, not zero independent donors or copies.
      if (length(ids) == nrow(ind) && length(donors) == nrow(ind) &&
          !anyNA(ids) && !anyNA(donors)) {
        copies <- as.character(ids) != as.character(donors)
        counts[3:6] <- c(length(unique(donors)), length(unique(donors[included])),
                         sum(copies), sum(copies & included))
      }
    }
    data.frame(scenario = scenario, as.list(counts), row.names = NULL)
  }

  changes <- list(assessed_union_people = NA_integer_,
                  net_mmet_changed_people = NA_integer_,
                  any_mode_mmet_changed_people = NA_integer_)
  if (!is.null(cf) && !is.null(ref) &&
      "census_id" %in% names(cf) && "census_id" %in% names(ref)) {
    ids <- unique(c(ref$census_id[scope(ref, "ref")], cf$census_id[scope(cf, "cf")]))
    changes$assessed_union_people <- length(ids)
    # Exclude unused reserves; include people leaving the CF boundary. Missing
    # rows/deltas are unknown. A mode switch may have zero net MMET change.
    rows <- match(ids, cf$census_id)
    count_changed <- function(columns) {
      if (!length(ids)) return(0L)
      if (anyNA(rows) || !all(columns %in% names(cf))) return(NA_integer_)
      values <- as.matrix(cf[rows, columns, drop = FALSE])
      if (any(!is.finite(values))) return(NA_integer_)
      sum(rowSums(abs(values) > 1e-10) > 0)
    }
    changes$net_mmet_changed_people <- count_changed("cf_mmet_delta")
    changes$any_mode_mmet_changed_people <- count_changed(paste0(
      "cf_mmet_delta_", c("walking", "cycling", "ebiking", "pt", "other_activity")))
  }
  list(
    populations = rbind(count_snapshot(ref, "ref"), count_snapshot(cf, "cf")),
    exposure_changes = changes,
    notes = c(
      "Counts are unweighted person records, before Tab 5 outcome/year/group filters.",
      "Retained records include unused donor reserves; assessed people use scenario scope flags (all rows when absent).",
      "Unique source donors use .miama_donor_census_id, or census_id when no replication provenance is present.",
      "Copied records have a different appraisal ID from their source donor ID; they remain in health totals when assessed.",
      "Exposure changes count each appraisal person once across the REF/CF union, with absolute MMET tolerance 1e-10; NA means unavailable.",
      "Unique donor counts describe evidence reuse, not statistical independence or an effective sample size."
    )
  )
}
