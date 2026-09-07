# Reuse source people as appraisal records, not as additional evidence.
# census_id remains the unique appraisal key; donor ID resolves HM histories.
.append_person_donors <- function(data, rows) {
  if (!length(rows)) return(data)
  ind <- data$ind
  if (anyDuplicated(ind$census_id) || anyNA(ind$census_id)) {
    stop("Person replication requires unique, non-missing appraisal IDs.", call. = FALSE)
  }
  donor_col <- ".miama_donor_census_id"
  if (!donor_col %in% names(ind)) ind[[donor_col]] <- ind$census_id
  if (!".miama_parent_census_id" %in% names(ind)) ind$.miama_parent_census_id <- ind$census_id
  copies <- ind[rows, , drop = FALSE]
  old_ids <- copies$census_id
  copies$.miama_parent_census_id <- old_ids
  if (is.numeric(ind$census_id)) {
    copies$census_id <- min(c(0, ind$census_id)) - seq_along(rows)
  } else {
    prefix <- ".miama_person_copy_"
    while (any(startsWith(as.character(ind$census_id), prefix))) prefix <- paste0(prefix, "_")
    copies$census_id <- paste0(prefix, seq_along(rows))
  }
  # Copies are a donor reserve until the scope sampler explicitly selects them.
  flags <- grep("^(ref|cf)_(in_scope|user_scope_)", names(copies), value = TRUE)
  for (field in flags) copies[[field]] <- FALSE
  data$ind <- rbind(ind, copies)

  trips <- data$trips
  if (!is.null(trips) && nrow(trips)) {
    owner_rows <- split(seq_len(nrow(trips)), as.character(trips$census_id))
    selected <- lapply(as.character(old_ids), function(id) owner_rows[[id]])
    index <- unlist(selected, use.names = FALSE)
    if (length(index)) {
      new_trips <- trips[index, , drop = FALSE]
      new_trips$census_id <- rep(copies$census_id, lengths(selected))
      new_trips <- .assign_new_trip_ids(trips, new_trips)
      flags <- grep("^(ref|cf)_(in_scope|trip_scope_)", names(new_trips), value = TRUE)
      for (field in flags) new_trips[[field]] <- FALSE
      data$trips <- rbind(trips, new_trips)
    }
  }
  data
}

.expand_person_donor_pool <- function(data, target_n, user_targets,
                                      cf_user_targets, population_target, seed) {
  original_n <- nrow(data$ind)
  events <- list()
  eligible <- function() cf_population_candidate_filter(
    data$ind, seq_len(nrow(data$ind)), population_target, select_inside = TRUE)
  add <- function(pool, n, reason) {
    if (n <= 0) return(invisible(NULL))
    if (!length(pool)) {
      .abort_appraisal_input(
        paste0("No eligible source people are available for ", reason, "."),
        stage = "reference_scope", fields = "pop_total_ref_advanced",
        hint = "Include an eligible population category or supply a supported donor proxy. Repetition cannot create missing donor evidence.")
    }
    set.seed(seed + length(events) + 7000L)
    donor_ids <- data$ind$.miama_donor_census_id %||% data$ind$census_id
    pool <- pool[!duplicated(donor_ids[pool])]
    rows <- pool[sample.int(length(pool), n, replace = TRUE)]
    data <<- .append_person_donors(data, rows)
    events[[length(events) + 1L]] <<- list(reason = reason, records_added = n,
                                         eligible_donors = length(pool))
  }
  # Fill rare-mode margins before the overall size. Modes share person rows;
  # donors are never removed merely because another mode already used them.
  for (mode in names(user_targets)) {
    target <- user_targets[[mode]]$value
    if (is.null(target)) next
    if (target > target_n) {
      .abort_appraisal_input(paste0("Reference ", mode, " users (", target,
        ") cannot exceed the assessed population (", target_n, ")."),
        stage = "reference_scope", fields = user_targets[[mode]]$field,
        hint = "Increase the total population or reduce the mode-user count.")
    }
    pool <- eligible()
    spec <- .counterfactual_mode_spec(mode)
    pool <- pool[.positive_col(data$ind, spec$activity_col)[pool]]
    if (!length(pool) && target > 0 && identical(mode, "ebiking")) {
      # No native e-bike people: copy the same cycling proxy used for trip
      # patterns. The copied REF history is explicitly a cycling-health proxy;
      # it is not evidence of observed e-bike use in the source population.
      donors <- eligible()
      donors <- donors[.positive_col(data$ind, "cycletime_wkhr")[donors]]
      if (!".miama_reference_mode_proxy" %in% names(data$ind)) {
        data$ind$.miama_reference_mode_proxy <- NA_character_
      }
      before <- nrow(data$ind)
      add(donors, target, "ebiking reference users (cycling proxy)")
      added <- seq.int(before + 1L, nrow(data$ind))
      data$ind$ebiketime_wkhr[added] <- data$ind$cycletime_wkhr[added]
      data$ind$cycletime_wkhr[added] <- 0
      data$ind$.miama_reference_mode_proxy[added] <- "cycling"
      if (!is.null(data$trips)) {
        donor_spec <- .counterfactual_mode_spec("cycling")
        trip_rows <- which(data$trips$census_id %in% data$ind$census_id[added] &
                             donor_spec$trip_filter(data$trips))
        data$trips <- .switch_trips_to_active_mode(data$trips, trip_rows, spec)
      }
      pool <- added
    }
    add(pool, target - length(pool), paste(mode, "reference users"))
  }
  pool <- eligible()
  add(pool, target_n - length(pool), "reference population")

  # Keep enough baseline non-users in reserve for explicit CF user targets.
  # They join CF only if selected, so reserving them does not inflate REF totals.
  for (mode in names(cf_user_targets)) {
    target <- cf_user_targets[[mode]]$value
    if (is.null(target)) next
    needed <- max(0, target - (user_targets[[mode]]$value %||% 0))
    pool <- eligible()
    spec <- .counterfactual_mode_spec(mode)
    pool <- pool[!.positive_col(data$ind, spec$activity_col)[pool]]
    add(pool, needed - length(pool), paste(mode, "counterfactual non-users"))
  }
  if (length(events)) {
    names(events) <- paste0("allocation_", seq_along(events))
    data$population_replication_report <- list(
      input_pool_records = original_n, expanded_pool_records = nrow(data$ind),
      unique_source_people = length(unique(data$ind$.miama_donor_census_id)),
      records_added = nrow(data$ind) - original_n, events = events,
      seed = seed, method = "eligible_donor_people_with_replacement",
      scaling = "Existing person_weight unchanged; no additional replication multiplier")
    warning("HUB reused eligible source people to supply ", nrow(data$ind) - original_n,
      " additional donor records. Copies do not increase the independent evidence sample.", call. = FALSE)
  }
  data
}

.expand_hm_donor_histories <- function(hm, people, appraisal_ids) {
  donor_col <- ".miama_donor_census_id"
  if (!donor_col %in% names(people)) return(hm)
  people <- people[people$census_id %in% appraisal_ids, , drop = FALSE]
  by_donor <- split(seq_len(nrow(hm)), as.character(hm$census_id))
  rows <- lapply(as.character(people[[donor_col]]), function(id) by_donor[[id]])
  out <- hm[unlist(rows, use.names = FALSE), , drop = FALSE]
  out$census_id <- rep(people$census_id, lengths(rows))
  out
}
