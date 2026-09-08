# Compatibility entry point for the original Leeds command and overrides.
keys <- c("GEO_ID", "SAMPLE_N", "SEED", "OVERWRITE")
values <- setNames(lapply(keys, function(key)
  Sys.getenv(paste0("MIAMA_LEEDS_", key), unset = NA_character_)),
  paste0("MIAMA_PROFILE_", keys))
values <- values[!vapply(values, is.na, logical(1))]
withr::with_envvar(c(list(MIAMA_PROFILE_ID = "leeds"), values), {
  source("inst/workflows/dev_build_packaged_lad_profile.R", local = TRUE)
})
