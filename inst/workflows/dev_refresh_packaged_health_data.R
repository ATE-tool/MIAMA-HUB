# Refresh only HM data, preserving every packaged person/trip sample.
# Run from HUB: Rscript --vanilla inst/workflows/dev_refresh_packaged_health_data.R
# Sources must be the matching sp_cycle_outcomes / mmet_d_cycle_lookup exports.
# Staging and validation complete before any packaged health files are replaced.
suppressPackageStartupMessages({ library(arrow); library(dplyr) })
arrow::set_cpu_count(1L)
hub_root <- normalizePath(getwd())
stopifnot(file.exists(file.path(hub_root, "DESCRIPTION")))
hm_root <- Sys.getenv("MIAMA_HM_ROOT", file.path(dirname(hub_root), "MIAMA-HM"))
processed <- file.path(hm_root, "health_data", "processed")
data_root <- file.path(hub_root, "inst", "extdata", "data")
cycles <- arrow::open_dataset(file.path(processed, "sp_cycle_outcomes"))
lookup <- arrow::open_dataset(file.path(processed, "mmet_d_cycle_lookup"))
stopifnot(all(c("census_id", "cycle", "mr_decile", "mmets_cycle",
                "death_share_diabetes", "depression_remission") %in% cycles$schema$names))
stopifnot(all(c("age1year", "female", "mr_decile", "cycle", "outcome",
                "mmets_lo", "mmets_hi", "slope") %in% lookup$schema$names))
roots <- c(data_root, list.dirs(file.path(data_root, "profiles"), recursive = FALSE))
ids <- lapply(roots, function(root) {
  arrow::open_dataset(file.path(root, "synthetic_pop", "SPindivid_CensusNTSALS_parquet")) |>
    select(census_id) |> collect() |> pull(census_id)
})
selected <- unique(unlist(ids))
message("Extracting new HM histories for ", length(selected), " existing donor IDs")
health <- cycles |> filter(census_id %in% selected) |> collect()
stopifnot(!anyDuplicated(health[c("census_id", "cycle")]))
stopifnot(setequal(health$census_id, selected))
stopifnot(setequal(health$census_id[health$cycle == 0], selected))
# Older people legitimately have shorter histories at the HM age boundary.
# Require contiguous histories from baseline, not 41 rows for every person.
coverage <- health |> group_by(census_id) |> summarise(n = n(), last = max(cycle))
stopifnot(all(coverage$n == coverage$last + 1), setequal(health$cycle, 0:40))
lookup_data <- collect(lookup)
stopifnot(all(paste0("d_", grep("^death_share_", names(health), value = TRUE)) %in%
                sub("_per_mmet$", "", lookup_data$outcome)))
stage <- tempfile("hm-refresh-", tmpdir = data_root)
dir.create(stage)
write_dataset <- function(x, path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(x, file.path(path, "part-0.parquet"), compression = "zstd")
}
for (i in seq_along(roots)) {
  x <- health[health$census_id %in% ids[[i]], ]
  x <- x[order(x$census_id, x$cycle), ]
  write_dataset(x, file.path(stage, as.character(i), "sp_cycle_outcomes"))
}
write_dataset(lookup_data, file.path(stage, "mmet_d_cycle_lookup"))
for (name in c("pyld_table.csv", "dw_table.csv")) {
  stopifnot(file.copy(file.path(processed, name), file.path(stage, name)))
}
source_files <- sort(c(list.files(file.path(processed, "sp_cycle_outcomes"), full.names = TRUE),
                       list.files(file.path(processed, "mmet_d_cycle_lookup"), full.names = TRUE),
                       file.path(processed, c("pyld_table.csv", "dw_table.csv"))))
release <- list(
  hm_commit = system2("git", c("-C", shQuote(hm_root), "rev-parse", "HEAD"), stdout = TRUE),
  refreshed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  source_files = substring(source_files, nchar(processed) + 2L),
  source_md5 = unname(tools::md5sum(source_files)),
  cycle_rows = nrow(health), lookup_rows = nrow(lookup_data),
  contract = "cycle outcomes and matching lookup, including death shares"
)
# Replace generated health artifacts only. SP rows, geography and weights stay put.
obsolete <- c("sp_overall_outcomes", "sp_overall_outcomes_sample",
              "sp_cycle_outcomes_sample", "sp_cycle_outcomes_death_share",
              "sp_cycle_outcomes_sample_death_share", "mmet_d_cycle_lookup_death_share")
for (i in seq_along(roots)) {
  destination <- file.path(roots[[i]], "health_data")
  unlink(file.path(destination, c("sp_cycle_outcomes", obsolete)), recursive = TRUE)
  stopifnot(file.rename(file.path(stage, as.character(i), "sp_cycle_outcomes"),
                       file.path(destination, "sp_cycle_outcomes")))
  metadata_path <- file.path(roots[[i]], "profile.rds")
  if (file.exists(metadata_path)) {
    metadata <- readRDS(metadata_path)
    metadata$sources$hm_overall <- metadata$sources$hm_cycle_death_share <- NULL
    metadata$sources$hm_cycle <- "MIAMA_HM_ROOT/health_data/processed/sp_cycle_outcomes"
    metadata$rows$hm_overall <- metadata$rows$hm_cycle_death_share <- NULL
    metadata$rows$hm_cycle <- sum(health$census_id %in% ids[[i]])
    metadata$hm_commit <- release$hm_commit
    saveRDS(metadata, metadata_path, version = 3)
  }
}
destination <- file.path(data_root, "health_data")
unlink(file.path(destination, "mmet_d_cycle_lookup"), recursive = TRUE)
stopifnot(file.rename(file.path(stage, "mmet_d_cycle_lookup"), file.path(destination, "mmet_d_cycle_lookup")))
for (name in c("pyld_table.csv", "dw_table.csv")) {
  stopifnot(file.copy(file.path(stage, name), file.path(destination, "haly_parameters", name), overwrite = TRUE))
}
saveRDS(release, file.path(destination, "release.rds"), version = 3)
unlink(stage, recursive = TRUE)
message("Refreshed packaged HM data from ", release$hm_commit,
        "; now rebuild the packaged data manifest.")
