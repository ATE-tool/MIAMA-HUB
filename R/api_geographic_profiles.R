# Packaged city selection: metadata only until the chosen source is loaded.
get_packaged_geo_options <- function(cfg, geo_level = "lad") {
  if (!cfg$workflow$dataset_size %in% c("leeds", "manchester")) {
    return(get_geo_options(cfg, geo_level))
  }
  do.call(rbind, lapply(c("leeds", "manchester"), function(id) {
    out <- get_geo_options(miama_default_config(id), geo_level)
    out$profile_id <- rep(id, nrow(out))
    out
  }))
}

select_geographic_profile <- function(cfg, geo_id, geo_level = "lad") {
  if (!cfg$workflow$dataset_size %in% c("leeds", "manchester")) return(cfg)
  options <- get_packaged_geo_options(cfg, geo_level)
  selected <- options$profile_id[options$geo_id == geo_id]
  if (length(selected) != 1L) stop("Select an available packaged LAD.", call. = FALSE)
  if (identical(selected, cfg$workflow$dataset_size)) return(cfg)
  fresh <- miama_default_config(selected)
  # Preserve model settings and operational cache flags, replace every
  # geography-dependent source/path and the source population metadata together.
  cfg$workflow$dataset_size <- selected
  cfg$sources <- fresh$sources
  cfg$population <- fresh$population
  cfg$cache$dir <- fresh$cache$dir
  cfg$output <- fresh$output
  cfg
}
