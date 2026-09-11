# Final results continue the accepted Tab 3/4 cohort. Counts alone cannot
# reproduce independently sampled REF/CF membership by resampling the source.
.finalize_staged_appraisal <- function(reference, counterfactual, values, cfg, seed,
                                      health_reference = reference) {
  # UI staging can be synthpop-only. Attach the already loaded HM baseline by
  # identity (including replicated donors), without selecting any new people.
  if (!"mmets" %in% names(reference$ind)) {
    for (scenario in c("ref", "cf")) {
      ind <- if (scenario == "ref") reference$ind else counterfactual$ind
      ids <- if (".miama_donor_census_id" %in% names(ind)) ind$.miama_donor_census_id else ind$census_id
      rows <- match(ind$census_id, health_reference$ind$census_id)
      missing <- is.na(rows)
      rows[missing] <- match(ids[missing], health_reference$ind$census_id)
      if (anyNA(rows) || !"mmets" %in% names(health_reference$ind)) {
        stop("Accepted people could not be matched to the loaded HM reference.", call. = FALSE)
      }
      ind$mmets <- health_reference$ind$mmets[rows]
      if (scenario == "ref") reference$ind <- ind else counterfactual$ind <- ind
    }
  }
  if (!"cf_mmet_delta" %in% names(counterfactual$ind)) {
    counterfactual <- .recalculate_counterfactual_mmets(counterfactual, reference,
      .assumption_cf_constants(.assumption_values(values), miama_counterfactual_defaults(cfg)))
  }
  accepted_ind <- as.data.frame(counterfactual$ind)
  constants <- .assumption_cf_constants(.assumption_values(values), miama_counterfactual_defaults(cfg))
  # Rescoping can duplicate donor trip patterns. Reconstructing their full
  # historical dose against a newly scoped REF need not reproduce the accepted
  # dose. Measure only the before/after effect of this final trip edit instead.
  before <- as.data.frame(.recalculate_counterfactual_mmets(counterfactual, reference, constants)$ind)
  modes <- normalize_active_modes(.ui_value(values, "modes", .miama_supported_modes()))
  for (scenario in c("ref", "cf")) {
    data <- if (scenario == "ref") reference else counterfactual
    total_field <- paste0("pop_total_", scenario, "_advanced")
    check <- function(field, actual) {
      target <- .ui_value(values, field, NULL)
      if (!is.null(target) && as.numeric(target) != actual) {
        .abort_appraisal_input("Accepted population changed after staging. Return to Tab 3 before calculating results.",
          stage = "accepted_population", fields = field)
      }
      values[[field]] <<- actual
    }
    check(total_field, sum(.true_values(data$ind[[paste0(scenario, "_in_scope")]])))
    for (mode in modes) {
      suffix <- .miama_mode_suffix(mode)
      check(paste0("pop_number_", scenario, "_", suffix, "_advanced"),
        sum(.true_values(data$ind[[.reference_user_scope_col(mode, scenario)]])))
    }
  }

  # REF trip edits can change which donor patterns are retained, not who owns
  # the accepted population contract. Avoid touching an unchanged REF snapshot.
  ref_changed <- any(vapply(modes, function(mode) {
    spec <- .counterfactual_mode_spec(mode)
    target <- .reference_trip_scope_target(values, spec$suffix)
    if (is.null(target$value)) return(FALSE)
    scope <- reference$trips[[.reference_trip_scope_col(mode, "ref")]]
    current <- sum(spec$trip_filter(reference$trips) & .true_values(scope) &
      !is.na(reference$trips$nts_tripid), na.rm = TRUE)
    .reference_trip_target_rows(target) != current
  }, logical(1)))
  if (ref_changed) reference <- apply_reference_appraisal_scope(reference, values,
    seed = seed, cfg = cfg, preserve_person_scope = TRUE)

  # Already assigned new users and their activity are retained. Only the trip
  # handlers run; induced/shifted trip additions use the accepted user masks.
  # Compare edit effects against the same REF, then add only that increment to
  # the accepted dose. This is not a second application of the original scheme.
  counterfactual <- apply_counterfactual_ui_values(counterfactual, values, reference,
    constants = miama_counterfactual_defaults(cfg), seed = seed, preserve_user_scope = TRUE)
  after <- as.data.frame(counterfactual$ind)
  old_rows <- match(after$census_id, accepted_ind$census_id)
  before_rows <- match(after$census_id, before$census_id)
  stopifnot(!anyNA(old_rows), !anyNA(before_rows))
  dose_fields <- intersect(grep("^cf_(user_mmet_delta|trip_mmet_delta|mmet_delta.*)$",
    names(after), value = TRUE), names(accepted_ind))
  for (field in dose_fields) {
    counterfactual$ind[[field]] <- accepted_ind[[field]][old_rows] +
      after[[field]] - before[[field]][before_rows]
  }
  counterfactual$ind$mmets <- accepted_ind$mmets[old_rows] +
    after$cf_mmet_delta - before$cf_mmet_delta[before_rows]
  counterfactual$counterfactual_report <- .counterfactual_report_finalize(
    counterfactual$counterfactual_report, counterfactual, reference)
  list(reference = reference, counterfactual = counterfactual)
}
