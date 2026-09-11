# Current-code sampling study. Run from HUB root after pkgload::load_all(".").
# Defaults request 100 draws; pass a smaller n_replicates for a diagnostic run.
# Source files, assumptions and counts are held fixed within each scenario.
sv_trip_input_rows <- function(profile, population, modes) {
  suffixes <- c(walking = "walk", cycling = "bike", ebiking = "ebike", pt = "pt")
  selected <- strsplit(modes, "+", fixed = TRUE)[[1]]
  dplyr::bind_rows(lapply(selected, function(mode) {
    if (!mode %in% names(suffixes)) stop("Unknown variance-study mode: ", mode)
    target <- function(scenario) {
      field <- paste0("trips_count_", scenario, "_", suffixes[[mode]])
      entry <- profile[[field]]
      value <- if (isTRUE(entry$is_filled)) entry$input_value else entry$default_value
      if (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value < 0)
        stop("Missing or invalid weekly trip target: ", field)
      value
    }
    ref <- target("ref"); cf <- target("cf")
    data.frame(population, modes, mode, ref_weekly_trips = ref,
      cf_weekly_trips = cf, additional_weekly_trips = cf - ref)
  }))
}

# Read the actual saved profiles, not population-based approximations. Verify
# that both experiments and every successful seed used the same mode targets.
sv_trip_inputs <- function(runs, data_dir) {
  keys <- sv_scenario_keys(runs)
  completed <- unique(runs[runs$status == "ok", c("id", keys)])
  rows <- dplyr::bind_rows(lapply(seq_len(nrow(completed)), function(i) {
    run <- completed[i, ]
    record <- readRDS(file.path(data_dir, paste0(run$id, ".rds")))
    rows <- sv_trip_input_rows(record$profile, run$population, run$modes)
    if ("additional_cycling_trips" %in% keys)
      rows$additional_cycling_trips <- run$additional_cycling_trips
    rows
  })) |> dplyr::distinct()
  counts <- rows |> dplyr::count(dplyr::across(dplyr::all_of(c(keys, "mode"))))
  if (any(counts$n != 1L)) stop("Trip targets vary across seeds or experiments.")
  rows |> dplyr::arrange(dplyr::across(dplyr::all_of(c(keys, "mode"))))
}

sv_scenario_keys <- function(data) {
  c("population", "modes", intersect("additional_cycling_trips", names(data)))
}

sv_assumption_signature <- function(profile) {
  entries <- MIAMAHUB::get_appraisal_assumptions(profile)
  digest::digest(lapply(entries, function(x) list(value = x$display$value,
    source = x$display$source)))
}

sv_summary <- function(runs) {
  runs |>
    dplyr::filter(status == "ok") |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(sv_scenario_keys(runs), "experiment", "outcome")))) |>
    dplyr::summarise(n = dplyr::n(), mean = mean(benefit), median = median(benefit),
      sd = stats::sd(benefit), q025 = stats::quantile(benefit, .025),
      q975 = stats::quantile(benefit, .975),
      relative_sd_percent = if (abs(mean(benefit)) > 1e-8) 100 * stats::sd(benefit) / abs(mean(benefit)) else NA_real_,
      opposite_sign_fraction = if (abs(mean(benefit)) > 1e-8) mean(sign(benefit) != sign(mean(benefit)) & abs(benefit) > 1e-8) else NA_real_,
      distinct_exposures = dplyr::n_distinct(exposure_hash), .groups = "drop")
}

run_sampling_variance <- function(n_replicates = 100L, sizes = c(100L, 500L, 1500L),
                                  mode_sets = list("walking", "cycling", c("walking", "cycling")),
                                  master_seed = 20260911L,
                                  output_dir = "docs/_sampling_variance_current",
                                  additional_cycling_trips = NULL) {
  stopifnot(n_replicates >= 2L, all(sizes > 0))
  trip_scale_design <- !is.null(additional_cycling_trips)
  if (trip_scale_design) stopifnot(length(additional_cycling_trips) > 0,
    all(is.finite(additional_cycling_trips)), all(additional_cycling_trips > 0),
    all(additional_cycling_trips == round(additional_cycling_trips)),
    !anyDuplicated(additional_cycling_trips))
  source("inst/workflows/dev_route_benchmark.R", local = TRUE)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  cfg <- MIAMAHUB::miama_default_config("leeds")
  hub <- MIAMAHUB::Hub$new(cfg)
  setup <- bm_hub("build_mock_appraisal_inputs", overrides = list(
    geo_id = bm_field(cfg$population$profile$geo_id), geo_level = bm_field("lad"),
    modes = bm_field(c("walking", "cycling")), ui_version = bm_field("advanced"),
    at_data_unit = bm_field("trips")))
  hub$build_reference_profile_defaults(setup)
  hub$build_reference_data_from_defaults()
  source_data <- hub$reference_data
  # The trip-scale study changes intervention volume, not population. Use all
  # source people so a small cycling subset cannot define the assessed scope.
  if (trip_scale_design) {
    sizes <- nrow(source_data$ind)
    mode_sets <- list("cycling")
  }
  stopifnot(max(sizes) <= nrow(source_data$ind))
  set.seed(master_seed)
  seeds <- sample.int(.Machine$integer.max, n_replicates)
  runs <- list(); diagnostics <- list(); assumptions <- list()
  increments <- if (trip_scale_design) additional_cycling_trips else NA_real_
  for (population in sizes) for (modes in mode_sets) for (increment in increments) {
    scenario <- paste(population, paste(modes, collapse = "+"), sep = "_")
    if (trip_scale_design) scenario <- paste0(scenario, "_plus", increment)
    # Derive plausible fixed input counts from one observed subset; changing
    # replicate seed must never change the user inputs or assumption defaults.
    set.seed(master_seed)
    ids <- sample(source_data$ind$census_id, population)
    observed <- source_data
    observed$ind <- as.data.frame(source_data$ind)[source_data$ind$census_id %in% ids, ]
    observed$trips <- as.data.frame(source_data$trips)[source_data$trips$census_id %in% ids, ]
    profile <- NULL
    for (mode in modes) {
      spec <- bm_hub(".counterfactual_mode_spec", mode)
      n <- sum(spec$trip_filter(observed$trips) & !is.na(observed$trips$nts_tripid))
      part <- bm_profile(mode, "trips", "advanced", c(people = population, trips = n),
        c(people = population, trips = if (trip_scale_design) n + increment else round(n * 1.2)), cfg)
      profile <- if (is.null(profile)) part else utils::modifyList(profile, part, keep.null = TRUE)
    }
    profile <- bm_override(profile, "modes", modes)
    # Unlike the matched shift-only benchmark, this experiment uses the normal
    # configured new-user and induced-trip assumptions, resolved into the profile.
    profile$assump_induced_trips_percent <- bm_field()
    for (mode in modes) profile[[paste0("assump_trip_source_shares_", bm_hub(".miama_mode_suffix", mode))]] <- bm_field()
    profile <- bm_hub("prepare_assumption_profile", profile, observed, source_data, cfg)
    assumption_hash <- sv_assumption_signature(profile)
    assumptions[[scenario]] <- MIAMAHUB::get_appraisal_assumptions(profile)
    anchor <- bm_hub("prepare_refinement_profile_defaults", source_data, profile, cfg = cfg, seed = master_seed)
    for (experiment in c("whole_appraisal", "fixed_ref")) for (seed in seeds) {
      id <- paste(scenario, experiment, seed, sep = "_")
      message(id)
      warnings <- character()
      result <- tryCatch(withCallingHandlers({
        if (experiment == "whole_appraisal") {
          tab3 <- bm_hub("prepare_refinement_profile_defaults", source_data, profile, cfg = cfg, seed = seed)
        } else {
          ref <- anchor$reference_data
          cf <- bm_hub("apply_counterfactual_ui_values", bm_hub("init_counterfactual_data", ref),
            bm_hub("extract_input_values", profile), ref,
            constants = bm_hub("miama_counterfactual_defaults", cfg), seed = seed)
          ref_ui <- bm_hub("extract_reference_ui_values", bm_hub("materialize_appraisal_scope", ref, "ref"), cfg = cfg)
          cf_ui <- bm_hub("extract_reference_ui_values", bm_hub("materialize_appraisal_scope", cf, "cf"), cfg = cfg)
          p <- bm_hub("apply_refinement_defaults_to_profile", profile,
            bm_hub(".refinement_profile_updates", ref_ui$ui_updates, cf_ui$ui_updates))
          tab3 <- list(profile = p, reference_data = ref, counterfactual_data = cf)
        }
        tab4 <- bm_hub("prepare_trip_refinement_profile_defaults", source_data, tab3$profile, cfg = cfg,
          seed = seed, staged_reference_data = tab3$reference_data,
          staged_counterfactual_data = tab3$counterfactual_data)
        final <- bm_final_results(source_data, tab4$profile, cfg, seed, tab4)
        stopifnot(identical(sv_assumption_signature(final$profile), assumption_hash))
        a <- as.data.frame(final$reference_data$ind)
        b <- as.data.frame(final$counterfactual_data$ind)
        ref_hash <- digest::digest(list(a$census_id[a$ref_in_scope],
          final$reference_data$trips[, grep("census_id|nts_tripid|^ref_trip_scope_", names(final$reference_data$trips)), drop = FALSE]))
        if (experiment == "fixed_ref") stopifnot(identical(final$reference_data, anchor$reference_data))
        delta <- b$cf_mmet_delta
        changed <- is.finite(delta) & abs(delta) > 1e-10 & (b$cf_in_scope | b$ref_in_scope)
        matched <- match(b$census_id, a$census_id)
        record <- list(profile = final$profile, assumptions = MIAMAHUB::get_appraisal_assumptions(final$profile),
          people = b[, intersect(c("census_id", "age1year", "mmets", "cf_mmet_delta", "ref_in_scope", "cf_in_scope"), names(b))],
          report = final$counterfactual_data$counterfactual_report,
          trip_identity_hash = digest::digest(final$counterfactual_data$trips))
        saveRDS(record, file.path(output_dir, paste0(id, ".rds")))
        diagnostics[[id]] <- data.frame(id, ref_hash, assessed_ref = sum(a$ref_in_scope),
          assessed_cf = sum(b$cf_in_scope), changed_people = sum(changed),
          mean_changed_age = if (any(changed)) mean(b$age1year[changed]) else NA_real_,
          mean_changed_baseline_mmet = if (any(changed)) mean(a$mmets[matched[changed]]) else NA_real_,
          total_mmet_delta = sum(delta[changed]),
          sd_individual_delta = if (sum(changed) > 1) sd(delta[changed]) else NA_real_,
          donor_copies = if (".miama_donor_census_id" %in% names(b)) sum(b$census_id != b$.miama_donor_census_id) else 0,
          extra_trip_rows = nrow(final$counterfactual_data$trips) - nrow(source_data$trips))
        cube <- final$results_data$plot_data$health_cube
        cube <- cube[cube$mode == "all_modes" & cube$cycle > 0 & cube$cycle <= 40, ]
        cube |> dplyr::group_by(outcome) |>
          dplyr::summarise(benefit = sum(delta_value) * if (dplyr::first(outcome) %in% c("halys", "life_years", "healthy_life_years")) 1 else -1, .groups = "drop") |>
          dplyr::mutate(status = "ok", exposure_hash = digest::digest(b[, c("census_id", "cf_mmet_delta")]))
      }, warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }),
      error = function(e) data.frame(status = "error", error = conditionMessage(e), outcome = NA_character_, benefit = NA_real_))
      runs[[id]] <- cbind(data.frame(id, population, modes = paste(modes, collapse = "+"), experiment, seed,
        assumption_hash, warnings = paste(unique(warnings), collapse = " | ")), as.data.frame(result))
      if (trip_scale_design) runs[[id]]$additional_cycling_trips <- increment
      utils::write.csv(dplyr::bind_rows(runs), file.path(output_dir, "runs.csv"), row.names = FALSE)
    }
  }
  runs <- dplyr::bind_rows(runs)
  utils::write.csv(dplyr::bind_rows(diagnostics), file.path(output_dir, "diagnostics.csv"), row.names = FALSE)
  utils::write.csv(sv_summary(runs), file.path(output_dir, "summary.csv"), row.names = FALSE)
  saveRDS(assumptions, file.path(output_dir, "assumptions.rds"))
  files <- c(list.files("R", full.names = TRUE), "inst/workflows/dev_route_benchmark.R", "inst/workflows/dev_sampling_variance.R")
  data_files <- list.files("inst/extdata/data/profiles/leeds", recursive = TRUE, full.names = TRUE)
  data_files <- unique(c(data_files, list.files(cfg$sources$hm_lookup$cycle,
    recursive = TRUE, full.names = TRUE)))
  saveRDS(list(timestamp = Sys.time(), commit = system2("git", c("rev-parse", "HEAD"), stdout = TRUE),
    code_md5 = tools::md5sum(files), data_md5 = tools::md5sum(data_files),
    source_hash = digest::digest(source_data), cfg = cfg, seeds = seeds, sizes = sizes,
    design = if (trip_scale_design) "cycling_trip_increments" else "population_sizes",
    additional_cycling_trips = additional_cycling_trips,
    n_replicates = n_replicates, session = sessionInfo(), master_seed = master_seed),
    file.path(output_dir, "manifest.rds"))
  invisible(runs)
}
