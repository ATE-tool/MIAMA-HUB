# Run from the HUB root after loading its dependencies:
# Rscript inst/workflows/dev_route_benchmark.R [number-of-seeds] [population-size]
# Research workflow only. No appraisal defaults or production algorithms change.
bm_hub <- function(name, ...) get(name, envir = asNamespace("MIAMAHUB"))(...)
bm_field <- function(value = NULL) list(input_value = value, is_filled = !is.null(value))

bm_override <- function(profile, field, value) {
  profile[[field]]$input_value <- value
  profile[[field]]$is_filled <- TRUE
  profile
}

# Both experiments use the production final-results entry point, not rounded
# headline metrics or a separate approximation of health aggregation.
bm_final_results <- function(source, profile, cfg, seed, staged = NULL) {
  hub <- MIAMAHUB::Hub$new(cfg)
  hub$reference_data <- source
  if (!is.null(staged)) {
    hub$refinement_reference_data <- staged$reference_data
    hub$refinement_counterfactual_data <- staged$counterfactual_data
  }
  hub$build_results(profile, seed = seed)
}

bm_health_totals <- function(result, horizon = 40L) {
  cube <- result$results_data$plot_data$health_cube
  cube <- cube[cube$mode == "all_modes" & cube$cycle > 0 & cube$cycle <= horizon, ]
  benefit <- function(outcome, direction) {
    x <- cube$delta_value[cube$outcome == outcome]
    if (!length(x)) NA_real_ else direction * sum(x)
  }
  c(halys = benefit("halys", 1), deaths_prevented = benefit("mortality", -1))
}

bm_measure <- function(data, mode) {
  spec <- bm_hub(".counterfactual_mode_spec", mode)
  scope <- paste0("cf_user_scope_", spec$suffix)
  users <- if (scope %in% names(data$ind)) data$ind[[scope]] else data$ind[[spec$activity_col]] > 0
  active <- spec$trip_filter(data$trips) & !is.na(data$trips$nts_tripid)
  c(people = nrow(data$ind), users = sum(users, na.rm = TRUE),
    trips = sum(active, na.rm = TRUE),
    trip_minutes = sum(data$trips[[spec$trip_duration_col]][active], na.rm = TRUE),
    individual_minutes = sum(data$ind[[spec$activity_col]], na.rm = TRUE) * 60,
    mmet_delta = sum(data$ind$cf_mmet_delta, na.rm = TRUE))
}

bm_profile <- function(mode, route, workflow, ref_counts, cf_counts, cfg) {
  suffix <- bm_hub(".counterfactual_mode_spec", mode)$suffix
  values <- list(ui_version = workflow, modes = mode, at_data_unit = route,
    geo_level = "lad", geo_id = cfg$population$profile$geo_id,
    scheme_peak_year = 0, scheme_no_decline = TRUE,
    assump_induced_trips_percent = 0)
  values[[paste0("pop_total_ref_", workflow)]] <- unname(ref_counts["people"])
  values[[paste0("pop_total_cf_", workflow)]] <- unname(ref_counts["people"])
  stem <- if (route == "users") "users_count_" else "trips_count_"
  quantity <- if (route == "users") "users" else "trips"
  values[[paste0(stem, "ref_", suffix)]] <- unname(ref_counts[quantity])
  values[[paste0(stem, "cf_", suffix)]] <- unname(cf_counts[quantity])
  values[[paste0("trips_timeframe_", suffix)]] <- "week"
  values[[paste0("trips_denominator_", suffix)]] <- "total"
  values[[paste0("assump_trip_source_shares_", suffix)]] <- list(car = list(percent = 100))
  profile <- lapply(values, bm_field)
  # Include schema entries needed to stage accepted advanced tables and resolve
  # completion assumptions, but never prefill the OTHER route's volume target.
  fields <- c(paste0(bm_hub(".assumption_catalogue")$prefix, suffix),
    "assump_new_user_percent", "assump_new_user_activity_pattern",
    "pop_total_ref_advanced", "pop_total_cf_advanced",
    paste0("pop_number_", c("ref_", "cf_"), suffix, "_advanced"),
    paste0("trips_number_", c("ref_", "cf_"), suffix),
    "trips_number_total_ref", "trips_number_total_cf", "appraisal_model_parameters",
    "appraisal_sampling_seed", "appraisal_data_sources", "appraisal_schema_version")
  for (field in setdiff(fields, names(profile))) profile[[field]] <- bm_field()
  profile
}

bm_benchmark <- function(ref, mode, scenario, constants, seed, n_changed = 5L) {
  spec <- bm_hub(".counterfactual_mode_spec", mode)
  cf <- bm_hub("init_counterfactual_data", ref)
  users <- ref$ind[[paste0("ref_user_scope_", spec$suffix)]]
  any_at <- Reduce(`|`, lapply(c("walking", "cycling", "ebiking", "pt"), function(m) {
    s <- bm_hub(".counterfactual_mode_spec", m)$suffix
    ref$ind[[paste0("ref_user_scope_", s)]]
  }))
  eligible_people <- if (scenario == "new_users") !any_at else users
  # Short, existing utilitarian car journeys only; no copies or induced trips.
  trips <- cf$trips
  candidates <- which(bm_hub(".results_trip_mode_group", trips$trip_mainmode) == "driving" &
    trips$trip_utilitarian & is.finite(trips$trip_distraw_km) &
    trips$trip_distraw_km > 0 & trips$trip_distraw_km <= 5 &
    trips$census_id %in% ref$ind$census_id[eligible_people])
  owners <- unique(trips$census_id[candidates])
  if (!length(owners)) stop("No eligible current users/car-trip owners for this benchmark.")
  set.seed(seed)
  chosen <- owners[sample.int(length(owners), min(n_changed, length(owners)))]
  rows <- unlist(lapply(chosen, function(id) {
    pool <- candidates[trips$census_id[candidates] == id]
    pool[sample.int(length(pool), min(2L, length(pool)))]
  }))
  cf$trips <- bm_hub(".switch_trips_to_active_mode", trips, rows, spec, constants)
  cf$trips$cf_trip_exposure_source[rows] <- "trip_target"
  cf$trips$cf_trip_change[rows] <- "shifted"
  cf <- bm_hub(".set_cf_mode_user_scope", cf, spec,
    unique(c(ref$ind$census_id[users], chosen)))
  cf <- bm_hub(".recalculate_counterfactual_mmets", cf, ref, constants)
  stopifnot(nrow(cf$ind) == nrow(ref$ind), nrow(cf$trips) == nrow(ref$trips),
    !anyDuplicated(cf$ind$census_id),
    identical(cf$trips[, c("census_id", "nts_tripid")], ref$trips[, c("census_id", "nts_tripid")]))
  list(data = cf, rows = rows, changed_ids = chosen)
}

run_route_benchmark <- function(n_seeds = 10L, population_size = 500L,
                                output_dir = "docs/current/validation/_route_benchmark", master_seed = 20260910L) {
  stopifnot(n_seeds >= 2, population_size >= 10)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  cfg <- bm_hub("miama_default_config", dataset_size = "leeds")
  hub <- MIAMAHUB::Hub$new(cfg)
  p <- bm_hub("build_mock_appraisal_inputs", overrides = list(
    geo_id = bm_field(cfg$population$profile$geo_id), geo_level = bm_field("lad"),
    modes = bm_field(c("walking", "cycling", "ebiking", "pt")),
    ui_version = bm_field("basic"), at_data_unit = bm_field("trips")))
  hub$build_reference_profile_defaults(p)
  hub$build_reference_data_from_defaults()
  source <- hub$reference_data
  stopifnot(population_size <= nrow(source$ind))
  set.seed(master_seed)
  rows <- sort(sample.int(nrow(source$ind), population_size))
  source$ind <- source$ind[rows, , drop = FALSE]
  source$trips <- source$trips[source$trips$census_id %in% source$ind$census_id, , drop = FALSE]
  modes <- c("walking", "cycling", "ebiking", "pt")
  source <- bm_hub("apply_reference_appraisal_scope", source,
    list(modes = modes, pop_total_ref_basic = population_size), cfg = cfg, seed = master_seed)
  source <- bm_hub("cf_add_key_indicators", source, modes)
  hm <- bm_hub("load_hm_cycle_outcomes_death_share", cfg, census_ids = source$ind$census_id,
               cycles = 0:40)
  exposure <- bm_hub(".counterfactual_health_exposure", source$ind, source$ind)
  lookup_scope <- bm_hub(".counterfactual_health_lookup_scope", hm, exposure)
  lookup <- bm_hub("load_hm_cycle_lookup_death_share", cfg,
                   strata = lookup_scope$strata, cycles = lookup_scope$cycles)
  stopifnot(all(source$ind$census_id %in% hm$census_id))
  health_cache <- new.env(parent = emptyenv())
  health <- function(data) {
    # Health depends on these exposures with fixed HM data/config/timeline.
    # Reuse identical exposures within THIS run only, not stale disk caches.
    key <- digest::digest(as.data.frame(data$ind)[, c("census_id", "mmets")])
    if (exists(key, health_cache, inherits = FALSE)) return(health_cache[[key]])
    out <- bm_hub("apply_counterfactual_health_outcomes", data, source, cfg = cfg,
      hm_cycle_outcomes = hm, hm_cycle_lookup = lookup,
      scheme_profile = list(scheme_peak_year = 0, scheme_no_decline = TRUE))
    h <- out$health_outcomes
    stopifnot("d_haly" %in% names(h))
    value <- c(halys = sum(h$d_haly[h$cycle > 0]), deaths_prevented = -sum(h$d_dead[h$cycle > 0]))
    health_cache[[key]] <- value
    value
  }
  # Fixed-exposure no-change control, separate from route reconstruction.
  control <- health(bm_hub("init_counterfactual_data", source))
  stopifnot(all(abs(control) < 1e-10))
  results <- list(); artifacts <- list(); benchmarks <- list(); unavailable <- list()
  set.seed(master_seed + 1L)
  seeds <- sample.int(.Machine$integer.max, n_seeds)
  for (mode in modes) for (scenario in c("new_users", "existing_users")) {
    key <- paste(mode, scenario, sep = "_")
    ref_counts <- bm_measure(source, mode)
    base_profile <- bm_profile(mode, "users", "basic", ref_counts, ref_counts, cfg)
    base_profile <- bm_hub("prepare_assumption_profile", base_profile, source, source, cfg)
    constants <- bm_hub(".assumption_cf_constants", bm_hub("extract_input_values", base_profile),
                        bm_hub("miama_counterfactual_defaults", cfg))
    benchmark <- tryCatch(bm_benchmark(source, mode, scenario, constants, master_seed + 2L),
                          error = function(e) e)
    if (inherits(benchmark, "error")) {
      if (!grepl("^No eligible current users", conditionMessage(benchmark))) stop(benchmark)
      unavailable[[key]] <- data.frame(mode, scenario, reason = conditionMessage(benchmark))
      next
    }
    cf_counts <- bm_measure(benchmark$data, mode)
    benchmark_health <- health(benchmark$data)
    benchmarks[[key]] <- c(list(mode = mode, scenario = scenario),
                           stats::setNames(as.list(ref_counts), paste0("ref_", names(ref_counts))), as.list(cf_counts),
                           as.list(benchmark_health))
    artifacts[[key]] <- benchmark
    for (workflow in c("basic", "advanced")) for (route in c("users", "trips")) {
      for (assumptions in c("defaults", "benchmark_informed")) for (seed in seeds) {
        id <- paste(key, workflow, route, assumptions, seed, sep = "_")
        message(id)
        warnings <- character()
        result <- tryCatch(withCallingHandlers({
          profile <- bm_profile(mode, route, workflow, ref_counts, cf_counts, cfg)
          profile <- bm_hub("prepare_assumption_profile", profile, source, source, cfg)
          if (assumptions == "benchmark_informed") {
            suffix <- bm_hub(".counterfactual_mode_spec", mode)$suffix
            # Supply completion assumptions only, never the other route's target.
            profile <- bm_override(profile, "assump_new_user_percent", if (scenario == "new_users") 100 else 0)
            rows <- benchmark$rows
            spec <- bm_hub(".counterfactual_mode_spec", mode)
            profile <- bm_override(profile, paste0("assump_trips_per_user_per_week_", suffix),
              length(rows) / length(benchmark$changed_ids))
            profile <- bm_override(profile, paste0("assump_trip_distance_km_", suffix),
              mean(benchmark$data$trips[[spec$trip_distance_col]][rows]))
          }
          profile <- bm_hub("prepare_assumption_profile", profile, source, source, cfg)
          if (workflow == "advanced") {
            tab3 <- bm_hub("prepare_refinement_profile_defaults", source, profile, cfg = cfg, seed = seed)
            tab4 <- bm_hub("prepare_trip_refinement_profile_defaults", source, tab3$profile, cfg = cfg,
              staged_reference_data = tab3$reference_data, staged_counterfactual_data = tab3$counterfactual_data,
              seed = seed)
            final <- bm_final_results(source, tab4$profile, cfg, seed, tab4)
          } else {
            final <- bm_final_results(source, profile, cfg, seed)
          }
          data <- final$counterfactual_data
          staged_ref <- final$reference_data
          final_profile <- final$profile
          # Fail rather than silently letting REF sampling become another source
          # of variation. Fixed person and trip identities are the experiment.
          stopifnot(identical(staged_ref$ind$census_id, source$ind$census_id),
                    all(staged_ref$ind$ref_in_scope), all(data$ind$cf_in_scope),
                    nrow(data$ind) == population_size)
          measured <- bm_measure(data, mode)
          h <- bm_health_totals(final)
          delta <- data$ind$cf_mmet_delta
          matched <- match(data$ind$census_id, benchmark$data$ind$census_id)
          artifacts[[id]] <- list(profile = final_profile,
            assumptions = bm_hub("get_appraisal_assumptions", final_profile),
            people = as.data.frame(data$ind)[, intersect(c("census_id", "age1year", "mmets", "cf_mmet_delta"), names(data$ind))],
            trip_ids = data$trips[, c("census_id", "nts_tripid")],
            report = data$counterfactual_report)
          c(as.list(measured), as.list(h), list(
            changed_people = sum(abs(delta) > 1e-10),
            mean_changed_age = if (any(abs(delta) > 1e-10)) mean(data$ind$age1year[abs(delta) > 1e-10]) else NA_real_,
            person_mmet_mae = mean(abs(delta - benchmark$data$ind$cf_mmet_delta[matched])),
            exposure_hash = digest::digest(data$ind[, c("census_id", "cf_mmet_delta")]),
            donor_copies = if (".miama_donor_census_id" %in% names(data$ind))
              sum(data$ind$census_id != data$ind[[".miama_donor_census_id"]]) else 0L,
            extra_trip_rows = nrow(data$trips) - nrow(source$trips),
            haly_difference = unname(h["halys"] - benchmark_health["halys"]), status = "ok"))
        }, warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }),
        error = function(e) list(status = "error", error = conditionMessage(e)))
        results[[id]] <- c(list(mode = mode, scenario = scenario, workflow = workflow,
          route = route, assumptions = assumptions, seed = seed), result,
          list(warnings = paste(unique(warnings), collapse = " | ")))
      }
    }
  }
  tab <- dplyr::bind_rows(results)
  bench <- dplyr::bind_rows(benchmarks)
  utils::write.csv(tab, file.path(output_dir, "runs.csv"), row.names = FALSE)
  utils::write.csv(bench, file.path(output_dir, "benchmarks.csv"), row.names = FALSE)
  utils::write.csv(dplyr::bind_rows(unavailable), file.path(output_dir, "unavailable.csv"), row.names = FALSE)
  saveRDS(list(source = source, runs = artifacts), file.path(output_dir, "snapshots.rds"))
  code <- c(list.files("R", full.names = TRUE), "inst/workflows/dev_route_benchmark.R")
  manifest <- list(timestamp = Sys.time(), commit = system2("git", c("rev-parse", "HEAD"), stdout = TRUE),
    code_md5 = tools::md5sum(code), source_hash = digest::digest(source),
    hm_hash = digest::digest(hm), lookup_hash = digest::digest(lookup), cfg = cfg,
    master_seed = master_seed, seeds = seeds, population_size = population_size,
    zero_change_health = control, distinct_health_evaluations = length(ls(health_cache)), session = sessionInfo(),
    boundary = "Fixed source sample; canonical persisted assumptions; basic and advanced paths through Hub$build_results; no browser")
  saveRDS(manifest, file.path(output_dir, "manifest.rds"))
  invisible(tab)
}

if (sys.nframe() == 0L) {
  pkgload::load_all(".", quiet = TRUE)
  args <- commandArgs(trailingOnly = TRUE)
  run_route_benchmark(if (length(args)) as.integer(args[1]) else 10L,
    if (length(args) > 1) as.integer(args[2]) else 500L)
}
