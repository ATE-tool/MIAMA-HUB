test_that("reference loading needs only cycle outcomes and keeps one baseline row", {
  root <- withr::local_tempdir()
  path <- file.path(root, "sp_cycle_outcomes")
  x <- data.frame(census_id = rep(1:2, each = 3), cycle = rep(0:2, 2),
                  mr_decile = 1, mmets_cycle = c(3, 4, 5, 7, 8, 9), dead = .01)
  arrow::write_dataset(x, path)
  cfg <- miama_default_config("sample")
  cfg$sources$hm_outcomes$overall_sample <- list(path = path)
  cfg$sources$hm_outcomes$cycle_sample <- list(path = path)
  cfg$cache <- list(enabled = TRUE, refresh = FALSE, dir = file.path(root, "cache"))
  ref <- load_hm_outcomes(cfg)
  expect_named(ref, c("census_id", "mr_decile", "mmets"))
  expect_equal(ref$mmets, c(3, 7))
  expect_equal(nrow(load_hm_outcomes(cfg, census_ids = 2)), 1)
  expect_equal(nrow(load_hm_outcomes(cfg, list(res_aggregation = "timeline"))), 6)
  expect_equal(load_hm_outcomes(cfg), ref)
  # A replacement under the same directory must invalidate cached baseline data.
  file <- list.files(path, full.names = TRUE)[1]
  x$mmets_cycle[1] <- 12
  arrow::write_parquet(x, file)
  Sys.setFileTime(file, Sys.time() + 10)
  expect_equal(load_hm_outcomes(cfg)$mmets, c(12, 7))
})

test_that("all packaged runtime sizes use canonical matched health files", {
  for (size in c("sample", "leeds", "manchester")) {
    cfg <- miama_default_config(size)
    key <- if (size == "sample") "cycle_sample" else "cycle"
    expect_equal(basename(cfg$sources$hm_death_share[[key]]$path), "sp_cycle_outcomes")
    expect_equal(basename(cfg$sources$hm_death_share$lookup_cycle$path), "mmet_d_cycle_lookup")
    expect_true(dir.exists(cfg$sources$hm_death_share[[key]]$path))
    schema <- arrow::open_dataset(cfg$sources$hm_death_share[[key]]$path)$schema$names
    expect_true(all(c("death_share_diabetes", "depression_remission", "mmets_cycle") %in% schema))
    expect_null(cfg$sources$hm_lookup$overall)
  }
})

test_that("full source paths resolve the new names without overall or sample exports", {
  root <- withr::local_tempdir()
  processed <- file.path(root, "hm", "health_data", "processed")
  for (name in c("sp_cycle_outcomes", "mmet_d_cycle_lookup"))
    dir.create(file.path(processed, name), recursive = TRUE)
  processed <- normalizePath(processed)
  withr::local_envvar(c(MIAMA_HM_ROOT = file.path(root, "hm"), MIAMA_DATA_ROOT = file.path(root, "sp")))
  cfg <- miama_default_config("full")
  expect_equal(cfg$sources$hm_outcomes$overall$path, file.path(processed, "sp_cycle_outcomes"))
  expect_equal(.hm_death_share_path(cfg, "sp_cycle_outcomes_death_share"),
               cfg$sources$hm_outcomes$overall$path)
  expect_equal(.hm_death_share_path(cfg, "mmet_d_cycle_lookup_death_share"),
               file.path(processed, "mmet_d_cycle_lookup"))
})

test_that("missing configured cycles cannot fall back to a different data release", {
  cfg <- miama_default_config("leeds")
  cfg$sources$hm_death_share$cycle$path <- file.path(withr::local_tempdir(), "missing")
  expect_error(load_hm_cycle_outcomes_death_share(cfg), "directory not found")
})

test_that("current packaged histories and lookup preserve the no-change invariant", {
  cfg <- miama_default_config("sample")
  attrs <- arrow::open_dataset(cfg$sources$sp_attributes$path) |>
    dplyr::select(census_id, age1year, female) |> dplyr::collect()
  attrs <- as.data.frame(attrs[1:3, ])
  baseline <- load_hm_outcomes(cfg, census_ids = attrs$census_id)
  ind <- merge(baseline, attrs, by = "census_id")
  ref <- list(ind = ind)
  result <- apply_counterfactual_health_outcomes(ref, ref, cfg)
  expect_true(result$counterfactual_health_report$haly$available)
  deltas <- result$health_outcomes[grep("^d_", names(result$health_outcomes))]
  expect_true("d_haly" %in% names(deltas))
  expect_true(all(as.matrix(deltas) == 0))
})
