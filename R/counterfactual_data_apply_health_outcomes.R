# MIAMA-HUB Module: Counterfactual Data / Apply Health Outcomes
# Purpose: Recalculate cycle-level health outcomes for `counterfactual_data`
#   after Step 6 has changed physical-activity exposure (`mmets`).
#
# Terminology:
# - `ref` means the without-scheme/reference scenario.
# - `cf` means the with-scheme/counterfactual scenario.
# - `delta` means `cf - ref`.
# - `baseline` is avoided here except when describing HM source tables, because
#   it can also mean the first simulation year.
#
# Method:
# The function follows the MIAMA-HM scenario-verification workflow documented in
# `MIAMA-HM/scenario_verification/scen_30to45_2mmets.qmd`. The baseline HM
# cycle tables and MMET-delta lookup are produced by
# `MIAMA-HM/scripts/sp_hm_join.R`; HUB reads those artifacts and reproduces the
# scenario lookup application locally. It does not source or duplicate the HM
# script.
#
# Outputs:
# The returned `counterfactual_data` gains `health_outcomes`, a full cycle-level
# table for all filtered individuals. Reference outcome columns are retained,
# `d_*` delta columns are added, and `*_cf` columns are added for convenience.

apply_counterfactual_health_outcomes <- function(
    counterfactual_data,
    reference_data,
    cfg = NULL,
    scheme_effect_duration = "longterm",
    include_cf_columns = TRUE,
    hm_cycle_outcomes = NULL,
    hm_cycle_lookup = NULL
) {
  assert_named_list(counterfactual_data, "counterfactual_data")
  assert_named_list(reference_data, "reference_data")

  if (!identical(scheme_effect_duration, "longterm")) {
    stop("Only `scheme_effect_duration = \"longterm\"` is currently implemented.", call. = FALSE)
  }
  if (is.null(counterfactual_data$ind) || is.null(reference_data$ind)) {
    stop("Counterfactual health outcomes require `ind` data in both reference and counterfactual data.", call. = FALSE)
  }

  exposure <- .counterfactual_health_exposure(reference_data$ind, counterfactual_data$ind)
  census_ids <- unique(exposure$census_id)

  if (is.null(hm_cycle_outcomes)) {
    hm_cycle_outcomes <- load_hm_cycle_outcomes_death_share(cfg, census_ids = census_ids)
  }
  if (is.null(hm_cycle_lookup)) {
    hm_cycle_lookup <- load_hm_cycle_lookup_death_share(cfg)
  }

  health_outcomes <- .apply_mmet_delta_lookup(
    hm_cycle_outcomes = hm_cycle_outcomes,
    hm_cycle_lookup = hm_cycle_lookup,
    exposure = exposure,
    include_cf_columns = include_cf_columns
  )

  counterfactual_data$health_outcomes <- health_outcomes
  counterfactual_data$counterfactual_health_report <- .counterfactual_health_report(
    exposure = exposure,
    health_outcomes = health_outcomes,
    scheme_effect_duration = scheme_effect_duration,
    include_cf_columns = include_cf_columns
  )

  counterfactual_data
}

# Data Loading ---------------------------------------------------------------
# These helpers deliberately use the updated death-share cycle tables, because
# those support health-adjusted life years and the full current outcome set.

load_hm_cycle_outcomes_death_share <- function(cfg = NULL, census_ids = NULL) {
  cfg <- cfg %||% miama_default_config()
  path <- .hm_death_share_path(cfg, "sp_cycle_outcomes_death_share")
  if (!dir.exists(path)) {
    stop("HM cycle death-share outcomes directory not found: ", path, call. = FALSE)
  }

  ds <- arrow::open_dataset(path, format = "parquet")
  if (!is.null(census_ids)) {
    ds <- dplyr::filter(ds, census_id %in% census_ids)
  }

  dplyr::collect(ds)
}

load_hm_cycle_lookup_death_share <- function(cfg = NULL) {
  cfg <- cfg %||% miama_default_config()
  path <- .hm_death_share_path(cfg, "mmet_d_cycle_lookup_death_share")
  if (!dir.exists(path)) {
    stop("HM cycle death-share lookup directory not found: ", path, call. = FALSE)
  }

  dplyr::collect(arrow::open_dataset(path, format = "parquet"))
}

.hm_death_share_path <- function(cfg, dataset_name) {
  cfg <- cfg %||% miama_default_config()
  dataset_candidates <- .hm_death_share_dataset_candidates(cfg, dataset_name)

  hub_paths <- file.path(miama_project_root(), "data", "health_data", dataset_candidates)
  for (path in hub_paths) {
    if (dir.exists(path)) {
      return(normalizePath(path, winslash = "/", mustWork = FALSE))
    }
  }

  hm_processed <- miama_paths()$hm_processed_root
  if (is.null(hm_processed)) {
    stop(
      "Death-share HM data was not found locally and MIAMA_HM_ROOT is not set. ",
      "Set MIAMA_HM_ROOT to the MIAMA-HM repo, place death-share data under ",
      "`data/health_data`, or keep MIAMA-HM as a sibling repo.",
      call. = FALSE
    )
  }

  hm_paths <- file.path(hm_processed, dataset_candidates)
  for (path in hm_paths) {
    if (dir.exists(path)) {
      return(normalizePath(path, winslash = "/", mustWork = FALSE))
    }
  }

  normalizePath(hm_paths[1], winslash = "/", mustWork = FALSE)
}

.hm_death_share_dataset_candidates <- function(cfg, dataset_name) {
  if (identical(dataset_name, "sp_cycle_outcomes_death_share") &&
      identical(cfg$workflow$dataset_size, "sample")) {
    return(c("sp_cycle_outcomes_sample_death_share", dataset_name))
  }

  dataset_name
}

# Exposure Preparation -------------------------------------------------------
# The long-term effect assumes the individual-level MMET delta applies to every
# HM cycle. Cycle-specific reference MMETs still come from the HM joined table.

.counterfactual_health_exposure <- function(reference_ind, counterfactual_ind) {
  reference_ind <- as.data.frame(reference_ind)
  counterfactual_ind <- as.data.frame(counterfactual_ind)

  required <- c("census_id", "age1year", "female", "mmets")
  missing_ref <- setdiff(required, names(reference_ind))
  missing_cf <- setdiff(c("census_id", "mmets"), names(counterfactual_ind))
  if (length(missing_ref) > 0) {
    stop("Reference `ind` is missing required health exposure columns: ",
         paste(missing_ref, collapse = ", "), call. = FALSE)
  }
  if (length(missing_cf) > 0) {
    stop("Counterfactual `ind` is missing required health exposure columns: ",
         paste(missing_cf, collapse = ", "), call. = FALSE)
  }

  ref <- reference_ind[, c("census_id", "age1year", "female", "mmets"), drop = FALSE]
  names(ref)[names(ref) == "mmets"] <- "mmets_ref"
  cf <- counterfactual_ind[, c("census_id", "mmets"), drop = FALSE]
  names(cf)[names(cf) == "mmets"] <- "mmets_cf_ind"

  exposure <- dplyr::left_join(ref, cf, by = "census_id")
  exposure$mmets_delta <- exposure$mmets_cf_ind - exposure$mmets_ref
  exposure
}

# Delta Lookup Application ---------------------------------------------------
# This mirrors `scenario_verification/scen_30to45_2mmets.qmd`: cap MMETs,
# overlap changed intervals with lookup bands, multiply by per-MMET slopes, and
# return reference, delta, and counterfactual outcome values by cycle.

.apply_mmet_delta_lookup <- function(hm_cycle_outcomes, hm_cycle_lookup, exposure, include_cf_columns) {
  hm_cycle_outcomes <- as.data.frame(hm_cycle_outcomes)
  hm_cycle_lookup <- as.data.frame(hm_cycle_lookup)
  exposure <- as.data.frame(exposure)

  required_cycle <- c("census_id", "mr_decile", "cycle", "mmets_cycle")
  required_lookup <- c("age1year", "female", "mr_decile", "cycle", "mmets_lo", "mmets_hi", "outcome", "slope")
  missing_cycle <- setdiff(required_cycle, names(hm_cycle_outcomes))
  missing_lookup <- setdiff(required_lookup, names(hm_cycle_lookup))
  if (length(missing_cycle) > 0) {
    stop("HM cycle outcomes are missing required columns: ", paste(missing_cycle, collapse = ", "), call. = FALSE)
  }
  if (length(missing_lookup) > 0) {
    stop("HM cycle lookup is missing required columns: ", paste(missing_lookup, collapse = ", "), call. = FALSE)
  }

  cycle_data <- dplyr::left_join(hm_cycle_outcomes, exposure, by = "census_id")
  if (any(is.na(cycle_data$mmets_delta))) {
    stop("Some HM cycle rows did not match counterfactual exposure rows by `census_id`.", call. = FALSE)
  }

  lookup_max <- max(hm_cycle_lookup$mmets_hi, na.rm = TRUE)
  cycle_data$mmets_cycle <- pmin(cycle_data$mmets_cycle, lookup_max)
  cycle_data$mmets_new <- pmin(cycle_data$mmets_cycle + cycle_data$mmets_delta, lookup_max)
  cycle_data$mmets_min <- pmin(cycle_data$mmets_cycle, cycle_data$mmets_new)
  cycle_data$mmets_max <- pmax(cycle_data$mmets_cycle, cycle_data$mmets_new)

  delta_cols <- .lookup_delta_columns(hm_cycle_lookup)
  for (col in delta_cols) {
    cycle_data[[col]] <- 0
  }

  changed <- cycle_data$mmets_new != cycle_data$mmets_cycle
  if (any(changed, na.rm = TRUE)) {
    delta_wide <- .calculate_mmet_delta_wide(cycle_data[changed, , drop = FALSE], hm_cycle_lookup)
    cycle_data <- dplyr::left_join(cycle_data, delta_wide, by = c("census_id", "cycle"), suffix = c("", "_calc"))
    for (col in delta_cols) {
      calc_col <- paste0(col, "_calc")
      if (calc_col %in% names(cycle_data)) {
        cycle_data[[col]] <- ifelse(is.na(cycle_data[[calc_col]]), cycle_data[[col]], cycle_data[[calc_col]])
        cycle_data[[calc_col]] <- NULL
      }
    }
  }

  if (isTRUE(include_cf_columns)) {
    cycle_data <- .add_cf_outcome_columns(cycle_data, delta_cols)
  }

  drop_cols <- c("mmets_ref", "mmets_cf_ind", "mmets_delta", "mmets_min", "mmets_max")
  cycle_data <- as.data.frame(cycle_data)
  cycle_data[, setdiff(names(cycle_data), drop_cols), drop = FALSE]
}

.calculate_mmet_delta_wide <- function(changed_cycle_data, hm_cycle_lookup) {
  calc_columns <- c(
    "census_id", "cycle", "mmets_cycle", "mmets_new", "age1year",
    "female", "mr_decile", "mmets_min", "mmets_max"
  )
  changed_cycle_data <- as.data.frame(changed_cycle_data)
  DT_scen <- data.table::as.data.table(changed_cycle_data[, calc_columns, drop = FALSE])
  DT_lookup <- data.table::as.data.table(hm_cycle_lookup)

  DT_scen[, `:=`(
    age1year = as.integer(age1year),
    female = as.numeric(female),
    mr_decile = as.integer(mr_decile),
    cycle = as.integer(cycle)
  )]
  DT_lookup[, `:=`(
    age1year = as.integer(age1year),
    female = as.numeric(female),
    mr_decile = as.integer(mr_decile),
    cycle = as.integer(cycle)
  )]

  overlap <- DT_lookup[
    DT_scen,
    on = .(age1year, female, mr_decile, cycle),
    allow.cartesian = TRUE
  ][
    mmets_min <= mmets_hi & mmets_max >= mmets_lo
  ]

  if (nrow(overlap) == 0) {
    return(data.frame(census_id = changed_cycle_data$census_id[0], cycle = changed_cycle_data$cycle[0]))
  }

  overlap[, overlap := pmin(mmets_max, mmets_hi) - pmax(mmets_min, mmets_lo)]
  overlap[, sign_change := ifelse(mmets_new < mmets_cycle, -1, 1)]
  delta <- overlap[, .(delta = sum(slope * overlap * sign_change)), by = .(census_id, cycle, outcome)]
  wide <- data.table::dcast(delta, census_id + cycle ~ outcome, value.var = "delta")

  delta_cols <- setdiff(names(wide), c("census_id", "cycle"))
  data.table::setnames(wide, delta_cols, sub("_per_mmet$", "", delta_cols))
  as.data.frame(wide)
}

.lookup_delta_columns <- function(hm_cycle_lookup) {
  paste0(sub("_per_mmet$", "", unique(hm_cycle_lookup$outcome)))
}

.add_cf_outcome_columns <- function(cycle_data, delta_cols) {
  for (delta_col in delta_cols) {
    ref_col <- sub("^d_", "", delta_col)
    cf_col <- paste0(ref_col, "_cf")
    if (ref_col %in% names(cycle_data)) {
      cycle_data[[cf_col]] <- cycle_data[[ref_col]] + cycle_data[[delta_col]]
    }
  }

  cycle_data
}

.counterfactual_health_report <- function(exposure, health_outcomes, scheme_effect_duration, include_cf_columns) {
  changed <- !is.na(exposure$mmets_delta) & exposure$mmets_delta != 0
  delta_cols <- grep("^d_", names(health_outcomes), value = TRUE)
  delta_sums <- vapply(delta_cols, function(col) sum(health_outcomes[[col]], na.rm = TRUE), numeric(1))
  impact_overview <- .counterfactual_health_impact_overview(health_outcomes, nrow(exposure))

  list(
    scheme_effect_duration = scheme_effect_duration,
    terminology = list(
      ref = "without-scheme/reference scenario",
      cf = "with-scheme/counterfactual scenario",
      delta = "cf - ref"
    ),
    n_ind = nrow(exposure),
    n_changed_ind = sum(changed, na.rm = TRUE),
    n_cycle_rows = nrow(health_outcomes),
    include_cf_columns = isTRUE(include_cf_columns),
    mmets_delta_summary = summary(exposure$mmets_delta),
    outcome_delta_sums = delta_sums,
    impact_overview = impact_overview
  )
}

.counterfactual_health_impact_overview <- function(health_outcomes, n_ind) {
  delta_cols <- grep("^d_", names(health_outcomes), value = TRUE)
  rows <- lapply(delta_cols, function(delta_col) {
    ref_col <- sub("^d_", "", delta_col)
    cf_col <- paste0(ref_col, "_cf")

    ref_total <- if (ref_col %in% names(health_outcomes)) {
      sum(health_outcomes[[ref_col]], na.rm = TRUE)
    } else {
      NA_real_
    }
    delta_total <- sum(health_outcomes[[delta_col]], na.rm = TRUE)
    cf_total <- if (cf_col %in% names(health_outcomes)) {
      sum(health_outcomes[[cf_col]], na.rm = TRUE)
    } else if (!is.na(ref_total)) {
      ref_total + delta_total
    } else {
      NA_real_
    }

    data.frame(
      outcome = ref_col,
      ref_total = ref_total,
      cf_total = cf_total,
      delta_total = delta_total,
      delta_per_1000_people = delta_total / n_ind * 1000,
      row.names = NULL
    )
  })

  if (length(rows) == 0) {
    return(data.frame(
      outcome = character(0),
      ref_total = numeric(0),
      cf_total = numeric(0),
      delta_total = numeric(0),
      delta_per_1000_people = numeric(0)
    ))
  }

  do.call(rbind, rows)
}
