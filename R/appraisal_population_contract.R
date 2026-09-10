# Explicit totals constrain assessed people, never the size of the donor reserve.
# Call after UI extraction: generated suggestions must not be submitted here as
# overrides until accepted by the Tab 3 table contract.
.explicit_population_contract <- function(values) {
  version <- if (identical(.ui_value(values, "ui_version", "basic"), "advanced")) "advanced" else "basic"
  get <- function(scenario) .first_reference_target(
    values, paste0("pop_total_", scenario, "_", version),
    label = paste(scenario, "population"), integer = TRUE)
  ref <- get("ref")
  cf <- get("cf")
  if (version == "basic" && !is.null(ref$value) && !is.null(cf$value) && ref$value != cf$value) {
    .abort_appraisal_input(
      "Basic population totals must be the same for REF and CF.",
      stage = "population_contract", fields = c(ref$field, cf$field),
      hint = "Enter one shared population total; mode-user counts may differ.")
  }
  if (version == "basic" && is.null(ref$value)) ref <- cf
  if (is.null(cf$value)) cf <- ref
  list(ref = ref, cf = cf)
}

.validate_population_user_counts <- function(values, contract, modes) {
  for (scenario in c("ref", "cf")) {
    total <- contract[[scenario]]
    if (is.null(total$value)) next
    for (mode in modes) {
      spec <- .counterfactual_mode_spec(mode)
      target <- if (scenario == "ref") .reference_user_scope_target(values, spec$suffix) else .cf_user_target(values, spec$suffix)
      requested <- if (is.null(target$value)) NULL else .validate_cf_user_target(target$value, spec)
      if (!is.null(requested) && requested > total$value) {
        .abort_appraisal_input(
          paste0("The ", toupper(scenario), " ", mode, " user target (", target$value,
                 ") cannot exceed the fixed population total (", total$value, ")."),
          stage = "population_contract", fields = c(total$field, target$field),
          hint = "Increase the population total or reduce this mode-user count. Donor reuse cannot fit more users inside a smaller total.")
      }
    }
  }
}

.set_fixed_cf_population <- function(data, total, values, constants, seed) {
  if (is.null(total$value)) return(data)
  ind <- data$ind
  inside <- if ("cf_in_scope" %in% names(ind)) .true_values(ind$cf_in_scope) else rep(TRUE, nrow(ind))
  if (sum(inside) != total$value) {
    population_target <- cf_population_sampling_target(values, spread = constants$spread,
      population_refinement = constants$population_refinement)
    eligible <- cf_population_candidate_filter(ind, seq_len(nrow(ind)), population_target, select_inside = TRUE)
    # A deliberate Tab 3 total edit may resize the CF boundary. Retain current
    # members where possible; mode targets are subsequently applied within it.
    keep <- intersect(which(inside), eligible)
    if (length(keep) > total$value) keep <- .sample_reference_rows(keep, total$value, seed)
    selected <- .sample_reference_people(ind, total$value, list(), seed,
      eligible_rows = eligible, required_rows = keep)
    inside <- seq_len(nrow(ind)) %in% selected
  }
  data$ind$cf_in_scope <- inside
  for (field in grep("^cf_user_scope_", names(ind), value = TRUE)) {
    data$ind[[field]] <- .true_values(ind[[field]]) & inside
  }
  if (!is.null(data$trips)) {
    data$trips$cf_in_scope <- data$trips$census_id %in% ind$census_id[inside]
    for (field in grep("^cf_trip_scope_", names(data$trips), value = TRUE)) {
      data$trips[[field]] <- .true_values(data$trips[[field]]) & data$trips$cf_in_scope
    }
  }
  data
}
