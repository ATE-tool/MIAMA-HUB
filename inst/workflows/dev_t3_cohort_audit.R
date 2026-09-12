# Run after pkgload::load_all(".") from the HUB root. This diagnostic uses
# observed Leeds travel and real HM outcomes; it does not change runtime defaults.
run_t3_cohort_audit <- function(sizes = c(500L, 2000L), seeds = c(1L, 13L, 27L),
                                output = "docs/current/validation/t3_cohort_audit_after.csv") {
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  source("inst/workflows/dev_route_benchmark.R", local = TRUE)
  cfg <- miama_default_config("leeds")
  hub <- Hub$new(cfg)
  p <- build_mock_appraisal_inputs(overrides = list(
    geo_id = bm_field(cfg$population$profile$geo_id), geo_level = bm_field("lad"),
    modes = bm_field("walking"), ui_version = bm_field("advanced"),
    at_data_unit = bm_field("trips")))
  hub$build_reference_profile_defaults(p)
  hub$build_reference_data_from_defaults()
  full <- hub$reference_data
  results <- list()
  for (n in sizes) for (seed in seeds) {
    source_data <- full
    set.seed(20260910)
    rows <- sort(sample.int(nrow(full$ind), n))
    source_data$ind <- as.data.frame(full$ind)[rows, ]
    source_data$trips <- as.data.frame(full$trips)[full$trips$census_id %in% source_data$ind$census_id, ]
    spec <- .counterfactual_mode_spec("walking")
    trips <- sum(spec$trip_filter(source_data$trips) & !is.na(source_data$trips$nts_tripid))
    counts <- c(people = n, trips = trips)
    profile <- bm_profile("walking", "trips", "advanced", counts,
      c(people = n, trips = round(trips * 1.2)), cfg)
    tab3 <- prepare_refinement_profile_defaults(source_data, profile, cfg = cfg, seed = seed)
    profile <- tab3$profile
    for (scenario in c("ref", "cf")) {
      field <- paste0("pop_total_", scenario, "_advanced")
      profile[[field]]$input_value <- round(n * .75)
      profile[[field]]$is_filled <- TRUE
      field <- paste0("pop_number_", scenario, "_walk_advanced")
      profile[[field]]$input_value <- round(profile[[field]]$default_value * .75)
      profile[[field]]$is_filled <- TRUE
    }
    tab4 <- prepare_trip_refinement_profile_defaults(source_data, profile, cfg = cfg, seed = seed,
      staged_reference_data = tab3$reference_data, staged_counterfactual_data = tab3$counterfactual_data)
    final_hub <- Hub$new(cfg)
    final_hub$reference_data <- source_data
    final_hub$refinement_reference_data <- tab4$reference_data
    final_hub$refinement_counterfactual_data <- tab4$counterfactual_data
    out <- final_hub$build_results(tab4$profile, seed = seed)
    a <- as.data.frame(tab4$counterfactual_data$ind)
    b <- as.data.frame(out$counterfactual_data$ind)
    aid <- a$census_id[a$cf_in_scope]
    bid <- b$census_id[b$cf_in_scope]
    row <- data.frame(source_people = n, seed = seed,
      staged_people = length(aid), final_people = length(bid),
      people_replaced = length(setdiff(aid, bid)),
      staged_walkers = sum(a$cf_user_scope_walk), final_walkers = sum(b$cf_user_scope_walk),
      walking_members_replaced = length(setdiff(a$census_id[a$cf_user_scope_walk], b$census_id[b$cf_user_scope_walk])),
      # These retained-row sums diagnose reconstruction, not aggregate health
      # benefits: retained rows can include donor reserves outside the scope.
      staged_total_mmet_delta = sum(a$cf_mmet_delta, na.rm = TRUE),
      final_total_mmet_delta = sum(b$cf_mmet_delta, na.rm = TRUE),
      final_health_cycle_rows = out$health_impacts$n_cycle_rows)
    results[[length(results) + 1L]] <- row
    print(row)
    utils::write.csv(do.call(rbind, results), output, row.names = FALSE)
  }
  invisible(do.call(rbind, results))
}
