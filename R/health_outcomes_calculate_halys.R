# MIAMA-HUB Health Outcomes: Health-Adjusted Life Years ---------------------
#
# Implements the prevalence reconstruction and HALY calculation documented in
# MIAMA-HM/scenario_verification/scen_30to45_2mmets.qmd. The calculation uses
# reference and counterfactual incidence, death, death-share, and depression
# remission streams after the MMET lookup has been applied.


#' Calculate reference and counterfactual HALYs
#'
#' For each person and model cycle, chronic-disease prevalence is reconstructed
#' as `P[t] = P[t-1] + incidence[t] - deaths[t] * death_share[t]`. Depression
#' instead subtracts the modelled remission/exits stream. Prevalence is
#' converted to a share of people alive and combined with residual pYLD and
#' comorbidity-adjusted disability weights:
#' `HALY = LY * (1 - pyld_rate) * (1 - sum(prevalence * dw_adj))`.
#'
#' @param health_outcomes Cycle-level health table containing reference and
#'   `d_*` counterfactual-minus-reference outcome columns.
#' @param pyld Residual-disability table with `age`, `sex`, and `pyld_rate`.
#' @param disability_weights Disease disability-weight table with `age`, `sex`,
#'   `disease`, and `dw_adj`.
#' @param diseases Character vector of model disease column names.
#' @param include_cf_columns Whether to retain the redundant `haly_cf` column.
#' @return The input table with `haly`, `d_haly`, and optionally `haly_cf`.
#' @export
calculate_health_adjusted_life_years <- function(
    health_outcomes,
    pyld,
    disability_weights,
    diseases = .miama_default_disease_incidence_columns(),
    include_cf_columns = FALSE
) {
  x <- as.data.frame(health_outcomes)
  pyld <- as.data.frame(pyld)
  disability_weights <- as.data.frame(disability_weights)

  if (nrow(x) == 0) {
    x$haly <- numeric(0)
    x$d_haly <- numeric(0)
    if (isTRUE(include_cf_columns)) x$haly_cf <- numeric(0)
    return(x)
  }

  base_required <- c(
    "census_id", "cycle", "age1year", "female", "dead", "d_dead",
    "depression_remission", "d_depression_remission"
  )
  disease_required <- unique(c(
    diseases,
    paste0("d_", diseases),
    paste0("death_share_", setdiff(diseases, "depression")),
    paste0("d_death_share_", setdiff(diseases, "depression"))
  ))
  missing <- setdiff(c(base_required, disease_required), names(x))
  if (length(missing) > 0) {
    stop(
      "HALY calculation is missing required health columns: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  .validate_haly_parameter_columns(
    pyld, c("age", "sex", "pyld_rate"), "pyld"
  )
  .validate_haly_parameter_columns(
    disability_weights, c("age", "sex", "disease", "dw_adj"),
    "disability_weights"
  )

  calculation_columns <- unique(c(base_required, disease_required))
  original_order <- seq_len(nrow(x))
  order_index <- order(as.character(x$census_id), .as_plain_numeric(x$cycle))
  # Keep the ordered working table to the columns needed by the recurrence.
  # The complete cycle table can be large and includes unrelated result fields.
  z <- x[order_index, calculation_columns, drop = FALSE]
  ids <- as.character(z$census_id)
  first_cycle <- c(TRUE, ids[-1] != ids[-length(ids)])
  current_age <- .as_plain_numeric(z$age1year) + .as_plain_numeric(z$cycle)
  female <- .as_plain_numeric(z$female)
  sex <- ifelse(female == 1, 2, 1)

  parameter_key <- paste(current_age, sex, sep = "\r")
  pyld_key <- paste(.as_plain_numeric(pyld$age), .as_plain_numeric(pyld$sex), sep = "\r")
  pyld_rate <- .as_plain_numeric(pyld$pyld_rate)[match(parameter_key, pyld_key)]
  if (anyNA(pyld_rate)) {
    missing_keys <- unique(parameter_key[is.na(pyld_rate)])
    stop(
      "HALY pYLD parameters do not cover age/sex keys: ",
      paste(utils::head(missing_keys, 10), collapse = ", "),
      call. = FALSE
    )
  }

  dead_ref <- .as_plain_numeric(z$dead)
  dead_cf <- dead_ref + .as_plain_numeric(z$d_dead)
  alive_ref <- 1 - .results_grouped_cumsum(dead_ref, ids)
  alive_cf <- 1 - .results_grouped_cumsum(dead_cf, ids)
  prev_dw_ref <- numeric(nrow(z))
  prev_dw_cf <- numeric(nrow(z))

  dw_disease <- .normalize_haly_disease_name(disability_weights$disease)
  diseases_normalized <- .normalize_haly_disease_name(diseases)

  for (i in seq_along(diseases)) {
    disease <- diseases[[i]]
    disease_key <- diseases_normalized[[i]]
    incidence_ref <- .as_plain_numeric(z[[disease]])
    incidence_cf <- incidence_ref + .as_plain_numeric(z[[paste0("d_", disease)]])

    if (identical(disease, "depression")) {
      exits_ref <- .as_plain_numeric(z$depression_remission)
      exits_cf <- exits_ref + .as_plain_numeric(z$d_depression_remission)
      change_ref <- incidence_ref - ifelse(first_cycle, 0, exits_ref)
      change_cf <- incidence_cf - ifelse(first_cycle, 0, exits_cf)
    } else {
      share_ref <- .as_plain_numeric(z[[paste0("death_share_", disease)]])
      share_cf <- share_ref + .as_plain_numeric(z[[paste0("d_death_share_", disease)]])
      change_ref <- incidence_ref - ifelse(first_cycle, 0, dead_ref * share_ref)
      change_cf <- incidence_cf - ifelse(first_cycle, 0, dead_cf * share_cf)
    }

    prevalence_ref <- .results_grouped_cumsum(change_ref, ids)
    prevalence_cf <- .results_grouped_cumsum(change_cf, ids)
    prevalence_alive_ref <- .haly_divide_prevalence(prevalence_ref, alive_ref)
    prevalence_alive_cf <- .haly_divide_prevalence(prevalence_cf, alive_cf)

    rows <- dw_disease == disease_key
    dw_key <- paste(
      .as_plain_numeric(disability_weights$age[rows]),
      .as_plain_numeric(disability_weights$sex[rows]),
      sep = "\r"
    )
    dw <- .as_plain_numeric(disability_weights$dw_adj[rows])[match(parameter_key, dw_key)]
    if (anyNA(dw)) {
      stop("HALY disability weights do not cover disease `", disease, "`.", call. = FALSE)
    }
    prev_dw_ref <- prev_dw_ref + prevalence_alive_ref * dw
    prev_dw_cf <- prev_dw_cf + prevalence_alive_cf * dw
  }

  haly_ref <- alive_ref * (1 - pyld_rate) * (1 - prev_dw_ref)
  haly_cf <- alive_cf * (1 - pyld_rate) * (1 - prev_dw_cf)
  calculated <- data.frame(
    original_order = original_order[order_index],
    haly = haly_ref,
    d_haly = haly_cf - haly_ref,
    haly_cf = haly_cf
  )
  calculated <- calculated[order(calculated$original_order), , drop = FALSE]

  x$haly <- calculated$haly
  x$d_haly <- calculated$d_haly
  if (isTRUE(include_cf_columns)) x$haly_cf <- calculated$haly_cf
  x
}

.validate_haly_parameter_columns <- function(data, required, name) {
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop(name, " is missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
}

.normalize_haly_disease_name <- function(x) {
  x <- iconv(as.character(x), from = "", to = "ASCII//TRANSLIT")
  x <- gsub("'", ".", x, fixed = TRUE)
  gsub("[^a-z0-9._]", "_", tolower(x))
}

.haly_divide_prevalence <- function(prevalence, alive) {
  out <- numeric(length(prevalence))
  valid <- is.finite(prevalence) & is.finite(alive) & alive > 0
  out[valid] <- prevalence[valid] / alive[valid]
  out
}

.load_haly_parameters <- function(cfg = NULL) {
  cfg <- cfg %||% miama_default_config()
  spec <- cfg$results$haly %||% miama_default_config()$results$haly
  if (is.null(spec$pyld_path) || !file.exists(spec$pyld_path)) {
    stop("HALY pYLD parameter file not found: ", spec$pyld_path %||% "<not configured>", call. = FALSE)
  }
  if (is.null(spec$disability_weights_path) || !file.exists(spec$disability_weights_path)) {
    stop(
      "HALY disability-weight parameter file not found: ",
      spec$disability_weights_path %||% "<not configured>",
      call. = FALSE
    )
  }
  list(
    pyld = utils::read.csv(spec$pyld_path, stringsAsFactors = FALSE),
    disability_weights = utils::read.csv(
      spec$disability_weights_path, stringsAsFactors = FALSE
    ),
    diseases = as.character(spec$diseases)
  )
}

.haly_required_health_columns <- function(diseases) {
  c(
    "census_id", "cycle", "age1year", "female", "dead", "d_dead",
    "depression_remission", "d_depression_remission",
    diseases, paste0("d_", diseases),
    paste0("death_share_", setdiff(diseases, "depression")),
    paste0("d_death_share_", setdiff(diseases, "depression"))
  )
}

.try_add_haly_outcomes <- function(health_outcomes, cfg, include_cf_columns) {
  spec <- cfg$results$haly %||% miama_default_config()$results$haly
  diseases <- as.character(spec$diseases)
  missing <- setdiff(.haly_required_health_columns(diseases), names(health_outcomes))
  if (length(missing) > 0) {
    return(list(
      data = health_outcomes,
      report = list(available = FALSE, missing_health_columns = missing)
    ))
  }

  params <- .load_haly_parameters(cfg)
  out <- calculate_health_adjusted_life_years(
    health_outcomes,
    pyld = params$pyld,
    disability_weights = params$disability_weights,
    diseases = params$diseases,
    include_cf_columns = include_cf_columns
  )
  list(
    data = out,
    report = list(
      available = TRUE,
      method = "prevalence reconstruction with residual pYLD and adjusted disability weights",
      diseases = params$diseases,
      delta_total = sum(out$d_haly, na.rm = TRUE)
    )
  )
}
