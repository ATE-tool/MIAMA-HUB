# Tab 5 population summary: realized CF appraisal people, not source geography.
.appraisal_population_summary <- function(counterfactual_data) {
  fields <- paste0("res_population_cf_", c("total", "walk", "bike", "ebike", "pt"))
  values <- setNames(as.list(rep(NA_real_, length(fields))), fields)
  if (is.null(counterfactual_data$ind)) return(values)

  view <- materialize_appraisal_scope(counterfactual_data, "cf")
  if (!is.null(view$trips) && "census_id" %in% names(view$trips)) {
    view$trips <- view$trips[view$trips$census_id %in% view$ind$census_id, , drop = FALSE]
  }
  values$res_population_cf_total <- nrow(view$ind)
  modes <- c(walk = "walking", bike = "cycling", ebike = "ebiking", pt = "pt")
  for (mode in names(modes)) {
    # Scope flags take precedence over activity-derived defaults, including zero.
    values[[paste0("res_population_cf_", mode)]] <- if (nrow(view$ind) == 0L) {
      0L
    } else {
      .reference_users_count(view$ind, view$trips, modes[[mode]])$value
    }
  }
  values
}

.populate_appraisal_summary_defaults <- function(profile, values) {
  # Output fields are never user targets. Do not alter any Tab 2-4 input field.
  for (field in intersect(names(values), names(profile))) {
    profile[[field]]$default_value <- values[[field]]
  }
  profile
}
