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
# table for all filtered individuals. Reference outcome columns are retained and
# `d_*` delta columns are added. Redundant `*_cf` columns are optional and are
# disabled by default because callers can derive them as `ref + delta`.

apply_counterfactual_health_outcomes <- function(
    counterfactual_data,
    reference_data,
    cfg = NULL,
    scheme_effect_duration = "longterm",
    include_cf_columns = FALSE,
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
    lookup_scope <- .counterfactual_health_lookup_scope(hm_cycle_outcomes, exposure)
    hm_cycle_lookup <- load_hm_cycle_lookup_death_share(
      cfg,
      strata = lookup_scope$strata,
      cycles = lookup_scope$cycles
    )
  }

  health_outcomes <- .apply_mmet_delta_lookup(
    hm_cycle_outcomes = hm_cycle_outcomes,
    hm_cycle_lookup = hm_cycle_lookup,
    exposure = exposure,
    include_cf_columns = include_cf_columns
  )

  haly <- .try_add_haly_outcomes(
    health_outcomes,
    cfg = cfg %||% miama_default_config(),
    include_cf_columns = include_cf_columns
  )
  health_outcomes <- haly$data

  counterfactual_data$health_outcomes <- health_outcomes
  counterfactual_data$counterfactual_health_report <- .counterfactual_health_report(
    exposure = exposure,
    health_outcomes = health_outcomes,
    scheme_effect_duration = scheme_effect_duration,
    include_cf_columns = include_cf_columns,
    haly_report = haly$report
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

load_hm_cycle_lookup_death_share <- function(cfg = NULL,
                                             strata = NULL,
                                             cycles = NULL) {
  cfg <- cfg %||% miama_default_config()
  path <- .hm_death_share_path(cfg, "mmet_d_cycle_lookup_death_share")
  if (!dir.exists(path)) {
    stop("HM cycle death-share lookup directory not found: ", path, call. = FALSE)
  }

  ds <- arrow::open_dataset(path, format = "parquet")
  if (is.null(strata) || nrow(strata) == 0) {
    return(dplyr::collect(ds))
  }

  required <- c("age1year", "female", "mr_decile")
  missing <- setdiff(required, names(strata))
  if (length(missing) > 0) {
    stop(
      "Health lookup strata are missing required columns: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  strata <- unique(as.data.frame(strata[, required, drop = FALSE]))
  cycles <- unique(.as_plain_numeric(cycles))
  cycles <- cycles[is.finite(cycles)]

  age_values <- unique(.as_plain_numeric(strata$age1year))
  female_values <- unique(.as_plain_numeric(strata$female))
  mr_values <- unique(.as_plain_numeric(strata$mr_decile))
  query <- dplyr::filter(
    ds,
    .data$age1year %in% age_values,
    .data$female %in% female_values,
    .data$mr_decile %in% mr_values
  )
  if (length(cycles) > 0) {
    query <- dplyr::filter(query, .data$cycle %in% cycles)
  }

  candidates <- dplyr::collect(query)
  key <- function(data) paste(data$age1year, data$female, data$mr_decile, sep = "\r")
  candidates[key(candidates) %in% key(strata), , drop = FALSE]
}

.hm_death_share_path <- function(cfg, dataset_name) {
  cfg <- cfg %||% miama_default_config()
  dataset_candidates <- .hm_death_share_dataset_candidates(cfg, dataset_name)

  configured_key <- if (identical(dataset_name, "mmet_d_cycle_lookup_death_share")) {
    "lookup_cycle"
  } else if (identical(cfg$workflow$dataset_size, "sample")) {
    "cycle_sample"
  } else {
    "cycle"
  }
  configured_source <- cfg$sources$hm_death_share[[configured_key]]
  configured_path <- if (is.null(configured_source)) NULL else .hm_source_path(configured_source)
  if (!is.null(configured_path) && dir.exists(configured_path)) {
    return(normalizePath(configured_path, winslash = "/", mustWork = FALSE))
  }

  # A normal resolved config returns above. For a deliberately minimal config,
  # preserve the legacy fallback order: an explicit/sibling MIAMA-HM checkout
  # takes precedence over whatever package happens to be installed locally.
  hm_processed <- miama_paths()$hm_processed_root
  if (!is.null(hm_processed)) {
    hm_paths <- file.path(hm_processed, dataset_candidates)
    for (path in hm_paths) {
      if (dir.exists(path)) {
        return(normalizePath(path, winslash = "/", mustWork = FALSE))
      }
    }
  }

  hub_paths <- file.path(miama_runtime_data_dir(), "health_data", dataset_candidates)
  for (path in hub_paths) {
    if (dir.exists(path)) {
      return(normalizePath(path, winslash = "/", mustWork = FALSE))
    }
  }

  if (is.null(hm_processed)) {
    stop(
      "Death-share HM data was not found locally and MIAMA_HM_ROOT is not set. ",
      "Set MIAMA_HM_ROOT to the MIAMA-HM repo, place death-share data under ",
      "`MIAMA_DATA_ROOT/health_data`, or keep MIAMA-HM as a sibling repo.",
      call. = FALSE
    )
  }

  normalizePath(file.path(hm_processed, dataset_candidates[1]), winslash = "/", mustWork = FALSE)
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

.health_plain_numeric_columns <- function(data, columns, integer_columns = character()) {
  data <- as.data.frame(data)
  for (col in intersect(columns, names(data))) {
    values <- .as_plain_numeric(data[[col]])
    if (col %in% integer_columns) {
      values <- as.integer(values)
    }
    data[[col]] <- values
  }
  data
}

.counterfactual_health_exposure <- function(reference_ind, counterfactual_ind) {
  reference_ind <- .health_plain_numeric_columns(
    reference_ind,
    c("age1year", "female", "mmets"),
    integer_columns = "age1year"
  )
  counterfactual_ind <- .health_plain_numeric_columns(counterfactual_ind, "mmets")

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

.counterfactual_health_lookup_scope <- function(hm_cycle_outcomes, exposure) {
  cycle_keys <- .health_plain_numeric_columns(
    hm_cycle_outcomes,
    c("census_id", "mr_decile", "cycle"),
    integer_columns = c("mr_decile", "cycle")
  )
  exposure_keys <- .health_plain_numeric_columns(
    exposure,
    c("census_id", "age1year", "female"),
    integer_columns = "age1year"
  )

  required_cycle <- c("census_id", "mr_decile", "cycle")
  required_exposure <- c("census_id", "age1year", "female")
  if (!all(required_cycle %in% names(cycle_keys)) ||
      !all(required_exposure %in% names(exposure_keys))) {
    return(list(strata = NULL, cycles = NULL))
  }

  scope <- dplyr::inner_join(
    unique(cycle_keys[, required_cycle, drop = FALSE]),
    unique(exposure_keys[, required_exposure, drop = FALSE]),
    by = "census_id"
  )

  list(
    strata = unique(scope[, c("age1year", "female", "mr_decile"), drop = FALSE]),
    cycles = unique(scope$cycle)
  )
}

# Delta Lookup Application ---------------------------------------------------
# This mirrors `scenario_verification/scen_30to45_2mmets.qmd`: cap MMETs,
# overlap changed intervals with lookup bands, multiply by per-MMET slopes, and
# return reference, delta, and counterfactual outcome values by cycle.

.apply_mmet_delta_lookup <- function(hm_cycle_outcomes, hm_cycle_lookup, exposure, include_cf_columns) {
  hm_cycle_outcomes <- .health_plain_numeric_columns(
    hm_cycle_outcomes,
    c("mr_decile", "cycle", "mmets_cycle"),
    integer_columns = c("mr_decile", "cycle")
  )
  hm_cycle_lookup <- .health_plain_numeric_columns(
    hm_cycle_lookup,
    c("age1year", "female", "mr_decile", "cycle", "mmets_lo", "mmets_hi", "slope"),
    integer_columns = c("age1year", "mr_decile", "cycle")
  )
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

.calculate_mmet_delta_wide <- function(changed_cycle_data,
                                       hm_cycle_lookup,
                                       chunk_size = 25000L) {
  calc_columns <- c(
    "census_id", "cycle", "mmets_cycle", "mmets_new", "age1year",
    "female", "mr_decile", "mmets_min", "mmets_max"
  )
  changed_cycle_data <- as.data.frame(changed_cycle_data)
  DT_scen <- data.table::as.data.table(changed_cycle_data[, calc_columns, drop = FALSE])
  DT_lookup <- data.table::as.data.table(hm_cycle_lookup)

  if (nrow(DT_scen) == 0) {
    return(data.frame(census_id = changed_cycle_data$census_id[0], cycle = changed_cycle_data$cycle[0]))
  }

  chunk_size <- max(1L, as.integer(chunk_size[1]))
  chunk_id <- ceiling(seq_len(nrow(DT_scen)) / chunk_size)
  wide_chunks <- lapply(split(seq_len(nrow(DT_scen)), chunk_id), function(rows) {
    .calculate_mmet_delta_chunk(DT_scen[rows], DT_lookup)
  })
  wide_chunks <- Filter(function(x) nrow(x) > 0, wide_chunks)
  if (length(wide_chunks) == 0) {
    return(data.frame(census_id = changed_cycle_data$census_id[0], cycle = changed_cycle_data$cycle[0]))
  }

  wide <- data.table::rbindlist(wide_chunks, use.names = TRUE, fill = TRUE)

  delta_cols <- setdiff(names(wide), c("census_id", "cycle"))
  data.table::setnames(wide, delta_cols, sub("_per_mmet$", "", delta_cols))
  as.data.frame(wide)
}

.calculate_mmet_delta_chunk <- function(DT_scen, DT_lookup) {
  # Include the MMET overlap predicates in the data.table join. The previous
  # equality-only join materialized all five MMET bands for all 35 outcomes
  # before filtering, which was prohibitive for full-data scenarios.
  overlap <- DT_lookup[
    DT_scen,
    on = .(
      age1year,
      female,
      mr_decile,
      cycle,
      mmets_hi >= mmets_min,
      mmets_lo <= mmets_max
    ),
    nomatch = 0L,
    allow.cartesian = TRUE,
    .(
      census_id = i.census_id,
      cycle = i.cycle,
      mmets_cycle = i.mmets_cycle,
      mmets_new = i.mmets_new,
      mmets_min = i.mmets_min,
      mmets_max = i.mmets_max,
      mmets_lo = x.mmets_lo,
      mmets_hi = x.mmets_hi,
      outcome = x.outcome,
      slope = x.slope
    )
  ]

  if (nrow(overlap) == 0) {
    return(data.table::data.table(census_id = numeric(0), cycle = integer(0)))
  }

  overlap[, overlap_width := pmin(mmets_max, mmets_hi) - pmax(mmets_min, mmets_lo)]
  overlap[, sign_change := ifelse(mmets_new < mmets_cycle, -1, 1)]
  delta <- overlap[
    overlap_width > 0,
    .(delta = sum(slope * overlap_width * sign_change)),
    by = .(census_id, cycle, outcome)
  ]
  data.table::dcast(delta, census_id + cycle ~ outcome, value.var = "delta")
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

.counterfactual_health_report <- function(exposure,
                                          health_outcomes,
                                          scheme_effect_duration,
                                          include_cf_columns,
                                          haly_report = NULL) {
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
    haly = haly_report,
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
