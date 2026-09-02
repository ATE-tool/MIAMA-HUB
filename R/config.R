# MIAMA-HUB Configuration ----------------------------------------------------
#
# `miama_default_config()` is the single orientation point for runtime choices,
# model assumptions, UI metadata, data locations, and operational settings.
# Most callers should create the defaults once and override only the relevant
# leaf values. `MIAMA_DATASET_SIZE` selects `"sample"`, `"leeds"`, or `"full"` at process
# startup, while an explicit `cfg$workflow$dataset_size` assignment can still
# override it for an individual development run.
#
# Top-level sections:
# - workflow: dataset scope and row limits.
# - arrow: Arrow execution and memory controls.
# - population: synthetic-population scaling assumptions.
# - physical_activity: common timeframe and MMET conversion constants.
# - spread: category definitions used by Tab 3/4 spread controls.
# - results: stable Tab 5 metadata, including filterable health outcomes.
# - options: stable IDs, labels, and defaults for shared UI controls.
# - sources: resolved external or packaged data locations.
# - cache: optional runtime cache behavior.
# - output: generated artifact locations.

`%||%` <- function(x, y) if (is.null(x)) y else x

# Stable Tab 5 outcome definitions. `columns` are reference HM columns; the
# counterfactual health step adds matching `d_*` and `*_cf` columns. Composite
# outcomes deliberately list every component so their meaning is transparent.
.miama_default_health_outcomes <- function() {
  cancer_cols <- c(
    "bladder_cancer", "breast_cancer", "colon_cancer", "endometrial_cancer",
    "esophageal_cancer", "gastric_cardia_cancer", "head_and_neck_cancer",
    "liver_cancer", "lung_cancer", "myeloid_leukemia"
  )

  list(
    halys = list(
      label = "Health-adjusted life years (HALYs)",
      type = "health_years", category = "Summary measures",
      columns = "haly", default = TRUE,
      direction = "higher_is_better", unit = "HALYs"
    ),
    mortality = list(
      label = "All-cause mortality", type = "mortality", category = "Mortality",
      columns = "dead", default = TRUE,
      direction = "lower_is_better", unit = "deaths"
    ),
    cvd = list(
      label = "Cardiovascular disease", type = "disease", category = "Cardiovascular",
      columns = c("coronary_heart_disease", "stroke"), default = TRUE
    ),
    ihd = list(
      label = "Ischaemic heart disease", type = "disease", category = "Cardiovascular",
      columns = "coronary_heart_disease", default = TRUE
    ),
    stroke = list(
      label = "Stroke", type = "disease", category = "Cardiovascular",
      columns = "stroke", default = TRUE
    ),
    diabetes = list(
      label = "Diabetes type 2", type = "disease", category = "Metabolic",
      columns = "diabetes", default = TRUE
    ),
    depression = list(
      label = "Depression", type = "disease", category = "Mental health",
      columns = "depression", default = TRUE
    ),
    alzheimer = list(
      label = "Alzheimer's & dementias", type = "disease", category = "Neurological",
      columns = "all_cause_dementia", default = TRUE
    ),
    cancers = list(
      label = "All cancers", type = "disease", category = "Cancer",
      columns = cancer_cols, default = TRUE
    ),
    breast_cancer = list(
      label = "Breast cancer", type = "disease", category = "Cancer",
      columns = "breast_cancer", default = FALSE
    ),
    colon_cancer = list(
      label = "Colon cancer", type = "disease", category = "Cancer",
      columns = "colon_cancer", default = FALSE
    )
  )
}

# Underlying HM incidence streams counted once for the headline total. These
# are deliberately raw model columns, not UI composites such as CVD or all
# cancers, because combining composites and subtypes would double-count cases.
.miama_default_disease_incidence_columns <- function() {
  c(
    "all_cause_dementia",
    "bladder_cancer", "breast_cancer", "colon_cancer", "endometrial_cancer",
    "esophageal_cancer", "gastric_cardia_cancer", "head_and_neck_cancer",
    "liver_cancer", "lung_cancer", "myeloid_leukemia",
    "coronary_heart_disease", "depression", "diabetes",
    "parkinson.s_disease", "stroke"
  )
}

.miama_default_ui_options <- function() {
  list(
    gender = list(values = c("Male" = "male", "Female" = "female"), default = c("male", "female")),
    trip_purpose_categories = list(
      values = c("Utilitarian" = "utilitarian", "Recreational" = "recreational"),
      default = c("utilitarian", "recreational")
    ),
    trip_purpose_input = list(
      values = c(
        "Utilitarian (commuting, errands)" = "utilitarian",
        "Recreational (leisure, exercise)" = "recreational",
        "Mixed - specify split" = "mixed"
      ),
      default = character(0)
    ),
    setup_modes = list(
      values = c("Walking" = "walk", "Cycling" = "bike", "E-biking" = "ebike", "Walking as part of PT" = "pt"),
      default = c("walk", "bike")
    ),
    results_modes = list(
      values = c("Walking" = "walking", "Cycling" = "cycling", "E-biking" = "ebiking", "Walking as part of PT" = "pt"),
      default = c("walking", "cycling")
    ),
    temporal_aggregation = list(
      values = c("Total (all assessment years)" = "total", "Timeline (year by year)" = "timeline"),
      default = "total"
    ),
    population_aggregation = list(
      values = c("Total" = "total", "By age group" = "age_group", "By gender" = "gender"),
      default = "total"
    ),
    impact_type = list(
      values = c("Attributable cases" = "attributable", "Counterfactual vs. reference" = "cf_vs_ref"),
      default = "attributable"
    ),
    metric = list(
      values = c(
        "Prevented cases per 100,000" = "prevented_per_100000",
        "Prevented cases" = "prevented",
        "Percent reduction" = "percent_reduction"
      ),
      default = "prevented_per_100000"
    ),
    timeline_type = list(
      values = c("Annual difference" = "annual", "Cumulative difference" = "cumulative"),
      default = "cumulative"
    ),
    timeframe = list(
      values = c("Per day" = "day", "Per week" = "week", "Per year" = "year"),
      default = "week"
    )
  )
}

.miama_default_population_refinement <- function() {
  list(
    age = list(
      ids = c(
        "age_under_18", "age_18_29", "age_30_39", "age_40_49",
        "age_50_59", "age_60_plus", "age_other"
      ),
      labels = c(
        "Under 18", "18-29", "30-39", "40-49", "50-59", "60+",
        "Other/unknown"
      ),
      breaks = c(-Inf, 18, 30, 40, 50, 60, Inf),
      other_id = "age_other",
      right = FALSE
    ),
    pa = list(
      ids = c("sedentary", "low", "moderate", "high", "very_high", "unknown"),
      labels = c("Sedentary", "Low", "Moderate", "High", "Very High", "Unknown"),
      breaks = c(-Inf, 0, 10, 25, 50, Inf),
      other_id = "unknown",
      unit = "mmet_wkhr",
      right = TRUE
    )
  )
}

.miama_dataset_size <- function(dataset_size = NULL) {
  if (is.null(dataset_size)) {
    dataset_size <- Sys.getenv("MIAMA_DATASET_SIZE", unset = "sample")
  }
  dataset_size <- tolower(trimws(dataset_size))
  valid_sizes <- c("sample", "leeds", "full")

  if (!dataset_size %in% valid_sizes) {
    stop(
      "MIAMA_DATASET_SIZE must be one of: ",
      paste(valid_sizes, collapse = ", "),
      call. = FALSE
    )
  }

  dataset_size
}

.miama_population_config <- function(dataset_size, paths) {
  default <- list(
    person_weight = MIAMA_SYNTHPOP_PERSON_WEIGHT,
    source = "Census 2021 synthetic population (5% sample)",
    profile = NULL
  )

  if (!identical(dataset_size, "leeds")) {
    return(default)
  }

  metadata_path <- paths$profile_metadata
  if (!file.exists(metadata_path)) {
    stop(
      "The packaged Leeds profile is incomplete: profile metadata was not found at ",
      metadata_path,
      ". Rebuild it with inst/workflows/dev_build_packaged_leeds_profile.R.",
      call. = FALSE
    )
  }

  metadata <- readRDS(metadata_path)
  person_weight <- metadata$effective_person_weight
  if (length(person_weight) != 1L || !is.finite(person_weight) || person_weight <= 0) {
    stop("The packaged Leeds profile has an invalid effective person weight.", call. = FALSE)
  }

  list(
    person_weight = as.numeric(person_weight),
    source = metadata$population_weight_source %||%
      "Leeds profile scaled to the full Leeds synthetic population",
    profile = metadata
  )
}

#' Build the MIAMA-HUB runtime configuration
#'
#' `MIAMA_DATASET_SIZE` controls whether the default configuration uses the
#' packaged sample data, the packaged Leeds profile, or externally configured
#' full data. The explicit
#' `dataset_size` argument takes precedence and should be used by development
#' workflows that switch between data profiles.
#'
#' @param dataset_size Optional `"sample"`, `"leeds"`, or `"full"`. Defaults to the
#'   `MIAMA_DATASET_SIZE` environment variable, or `"sample"` when unset.
#' @return A nested MIAMA-HUB configuration list.
#' @export
miama_default_config <- function(dataset_size = NULL) {
  dataset_size <- .miama_dataset_size(dataset_size)
  p <- miama_paths(dataset_size = dataset_size)
  population <- .miama_population_config(dataset_size, p)

  list(
    # 1. Workflow scope ------------------------------------------------------
    workflow = list(
      dataset_size = dataset_size, # options: "sample", "leeds", "full"
      max_rows     = MIAMA_DEFAULT_MAX_ROWS
    ),
    # 2. Arrow runtime controls ---------------------------------------------
    arrow = list(
      cpu_count      = 1L,
      release_unused = TRUE
    ),
    # 3. Population representation -----------------------------------------
    population = population,
    # 4. Physical-activity model constants ---------------------------------
    physical_activity = list(
      base_timeframe = "week",
      mmet_per_hour = MIAMA_MMET_PER_HOUR
    ),
    # 5. Counterfactual mechanism assumptions ------------------------------
    counterfactual = list(
      modes = list(
        ebiking = list(
          reference_volume = "zero",
          donor_mode = "cycling",
          proxy_distance_factor = 1,
          proxy_duration_factor = 1,
          speed_kmh = 15.7
        ),
        pt = list(
          activity_component = "walking_access",
          access_walk_distance_km_default = 0.8,
          access_walk_minutes_default = 10
        )
      ),
      trips = list(
        # Used unless the profile supplies `induced_trips_percent` (or its
        # mode-specific equivalent). Purpose is a separate trip characteristic
        # and does not determine whether a trip is shifted or induced.
        # Shifted percentage is always the complement (100 - induced).
        induced_trips_percent_default = 10,
        # Source modes apply only to the shifted (non-induced) share of added
        # trips. These are explicit assumptions where no England-derived
        # source-mode evidence is currently available.
        source_mode_shares = list(
          ebiking = c(cycling = 1 / 3, pt = 1 / 3, driving = 1 / 3)
        )
      )
    ),
    # 6. Tab 3/4 spread category definitions -------------------------------
    spread = list(
      age = list(
        ids = c("age_18_29", "age_30_39", "age_40_49", "age_50_59", "age_60_plus"),
        labels = c("18-29", "30-39", "40-49", "50-59", "60+"),
        breaks = c(18, 30, 40, 50, 60, Inf),
        midpoints = c(24, 35, 45, 55, 70),
        right = FALSE
      ),
      trip_distance = list(
        ids = c("dist_0_2", "dist_2_5", "dist_5_10", "dist_10_30", "dist_30_plus"),
        labels = c("0-2km", "2-5km", "5-10km", "10-30km", "30+km"),
        breaks = c(0, 2, 5, 10, 30, Inf),
        midpoints = c(1, 3.5, 7.5, 20, 40),
        right = FALSE
      ),
      pa = list(
        ids = c("sedentary", "low", "moderate", "high", "very_high"),
        labels = c("sedentary", "low", "moderate", "high", "very_high"),
        breaks = c(-Inf, 0, 10, 25, 50, Inf),
        midpoints = c(0, 5, 17.5, 37.5, 65),
        unit = "mmet_wkhr",
        right = TRUE
      )
    ),
    # 7. Exhaustive Tab 3 population-filter categories ----------------------
    # These categories cover every assessed person. They are separate from
    # the fixed five-category spread definitions used by the slider plots.
    population_refinement = .miama_default_population_refinement(),
    # 8. Tab 5 results metadata ---------------------------------------------
    # This catalogue is stable and available before health data are loaded.
    # Use `get_health_outcome_options()` to turn it into a UI-ready table or
    # validate it against the columns of a particular HM outcome source.
    results = list(
      outcomes = .miama_default_health_outcomes(),
      assessment_period_years = 40L,
      headline_disease_columns = .miama_default_disease_incidence_columns(),
      haly = list(
        diseases = .miama_default_disease_incidence_columns(),
        pyld_path = file.path(
          p$packaged_data_dir, "health_data", "haly_parameters", "pyld_table.csv"
        ),
        disability_weights_path = file.path(
          p$packaged_data_dir, "health_data", "haly_parameters", "dw_table.csv"
        )
      )
    ),
    # 9. Stable UI option metadata ------------------------------------------
    # Data-derived reference values remain elsewhere; these are only the
    # canonical IDs, labels, and defaults used to construct controls.
    options = .miama_default_ui_options(),
    # 10. Data sources -------------------------------------------------------
    sources = list(
      sp_attributes = p$sp_attributes,
      sp_trips      = p$sp_trips,
      hm_outcomes = list(
        overall        = p$hm_sp_overall,
        overall_sample = p$hm_sp_overall_sample,
        cycle          = p$hm_sp_cycle,
        cycle_sample   = p$hm_sp_cycle_sample
      ),
      hm_lookup = list(
        overall = p$hm_lookup_overall,
        cycle   = p$hm_lookup_cycle
      ),
      hm_death_share = list(
        cycle        = p$hm_cycle_death_share,
        cycle_sample = p$hm_cycle_sample_death_share,
        lookup_cycle = p$hm_lookup_cycle_death_share
      )
    ),
    # 11. Runtime cache ------------------------------------------------------
    cache = list(
      enabled = TRUE,
      refresh = FALSE,
      dir     = p$cache_dir
    ),
    # 12. Generated output locations ---------------------------------------
    output = list(
      root      = p$output_root,
      lookup    = p$output_lookup,
      reference = p$output_reference
    )
  )
}

miama_hm_suffix_from_request <- function(results_request = list()) {
  aggregation <- results_request$res_aggregation %||% "total"

  switch(
    aggregation,
    total = "overall",
    timeline = "cycle",
    stop("Unsupported res_aggregation: ", aggregation, call. = FALSE)
  )
}

# Validate that the resolved source paths actually exist on disk.
miama_resolve_config <- function(cfg = NULL, results_request = list(), validate_hm = TRUE) {
  cfg <- cfg %||% miama_default_config()

  sp_path <- cfg$sources$sp_attributes$path
  if (!identical(cfg$sources$sp_attributes$format, "parquet") || !dir.exists(sp_path)) {
    stop("Synthpop attributes parquet directory not found: ", sp_path, call. = FALSE)
  }

  sp_trips_path <- cfg$sources$sp_trips$path
  if (!identical(cfg$sources$sp_trips$format, "parquet") || !dir.exists(sp_trips_path)) {
    stop("Synthpop trips parquet directory not found: ", sp_trips_path, call. = FALSE)
  }

  if (identical(cfg$workflow$dataset_size, "full") &&
      .is_packaged_sample_path(sp_path)) {
    stop(
      "dataset_size = 'full' cannot use packaged sample synthpop data. ",
      "Set MIAMA_DATA_ROOT or provide explicit cfg$sources paths to full parquet data.",
      call. = FALSE
    )
  }

  if (isTRUE(validate_hm)) {
    hm_suffix <- miama_hm_suffix_from_request(results_request)
    hm_key <- paste0(
      hm_suffix,
      if (cfg$workflow$dataset_size == "sample") "_sample" else ""
    )
    hm_dir <- cfg$sources$hm_outcomes[[hm_key]]
    hm_path <- .hm_source_path(hm_dir)

    if (!dir.exists(hm_path)) {
      stop("HM outcomes directory not found: ", hm_path, call. = FALSE)
    }
  }

  cfg
}

.is_packaged_sample_path <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  packaged_roots <- c(
    system.file("extdata", "data", package = "MIAMAHUB"),
    file.path(miama_project_root(), "inst", "extdata", "data")
  )
  packaged_roots <- unique(packaged_roots[nzchar(packaged_roots)])
  packaged_roots <- normalizePath(packaged_roots, winslash = "/", mustWork = FALSE)

  any(vapply(packaged_roots, function(root) {
    identical(path, root) || startsWith(path, paste0(root, "/"))
  }, logical(1)))
}

# Load HM outcomes parquet with optional rds caching for faster future loads.
load_hm_outcomes <- function(cfg = NULL, results_request = list(), census_ids = NULL) {
  cfg <- cfg %||% miama_default_config()

  valid_sizes <- c("sample", "leeds", "full")
  if (!cfg$workflow$dataset_size %in% valid_sizes) {
    stop("cfg$workflow$dataset_size must be one of: ",
         paste(valid_sizes, collapse = ", "), call. = FALSE)
  }

  hm_suffix <- miama_hm_suffix_from_request(results_request)
  key <- paste0(
    hm_suffix,
    if (cfg$workflow$dataset_size == "sample") "_sample" else ""
  )
  hm_source <- cfg$sources$hm_outcomes[[key]]
  parquet_path <- .hm_source_path(hm_source)

  cache_file <- file.path(
    cfg$cache$dir,
    paste0("hm_outcomes_", key, ".rds")
  )

  if (isTRUE(cfg$cache$enabled) && is.null(census_ids) && file.exists(cache_file) && !isTRUE(cfg$cache$refresh)) {
    message("Loading HM outcomes from cache: ", cache_file)
    return(readRDS(cache_file))
  }

  if (!dir.exists(parquet_path)) {
    stop("HM outcomes parquet directory not found: ", parquet_path, call. = FALSE)
  }

  source_label <- .hm_source_label(hm_source)
  hm_outcomes <- .with_miama_arrow_runtime(cfg, {
    message("Loading HM outcomes from ", source_label, " parquet: ", parquet_path)
    hm_ds <- arrow::open_dataset(parquet_path, format = "parquet")

    if (!is.null(census_ids)) {
      hm_ds <- dplyr::filter(hm_ds, census_id %in% census_ids)
    }

    dplyr::collect(hm_ds)
  })

  if (isTRUE(cfg$cache$enabled) && is.null(census_ids)) {
    dir.create(cfg$cache$dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(hm_outcomes, cache_file)
    message("Cached HM outcomes to: ", cache_file)
  }

  hm_outcomes
}

.hm_source_path <- function(source) {
  if (is.list(source) && "path" %in% names(source)) {
    return(source$path)
  }

  source
}

.hm_source_label <- function(source) {
  if (is.list(source) && "source" %in% names(source)) {
    return(source$source)
  }

  "configured"
}

# Load mmet lookup table for the requested aggregation.
load_hm_lookup <- function(cfg = NULL, results_request = list()) {
  cfg <- cfg %||% miama_default_config()
  hm_suffix <- miama_hm_suffix_from_request(results_request)

  lookup_path <- cfg$sources$hm_lookup[[hm_suffix]]
  if (is.null(lookup_path)) {
    stop("HM lookup path is unavailable. Set MIAMA_HM_ROOT for lookup suffix: ", hm_suffix, call. = FALSE)
  }
  if (!dir.exists(lookup_path)) {
    stop("HM lookup parquet directory not found: ", lookup_path, call. = FALSE)
  }

  .with_miama_arrow_runtime(cfg, {
    dplyr::collect(arrow::open_dataset(lookup_path, format = "parquet"))
  })
}
