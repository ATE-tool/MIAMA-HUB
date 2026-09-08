test_that("Manchester uses isolated packaged sources and unit person weight", {
  withr::local_envvar(c(MIAMA_DATA_ROOT = tempdir(), MIAMA_HM_ROOT = tempdir()))
  cfg <- miama_default_config("manchester")
  expect_match(cfg$sources$sp_attributes$path, "profiles/manchester/synthetic_pop")
  expect_match(cfg$sources$hm_outcomes$overall$path, "profiles/manchester/health_data")
  expect_match(cfg$sources$hm_death_share$cycle$path, "profiles/manchester/health_data")
  expect_equal(cfg$sources$hm_death_share$lookup_cycle$source, "hub_shared")
  expect_equal(cfg$population$person_weight, 1)
  expect_equal(cfg$population$source_person_weight, 55.728)
  expect_equal(cfg$population$profile$geo_id, "E08000003")
  expect_equal(cfg$population$profile$sampled_individuals, 10000)
  expect_false(identical(cfg$cache$dir, miama_default_config("leeds")$cache$dir))
  expect_equal(get_geo_options(cfg, "lad")$geo_id, "E08000003")
  expect_equal(get_geo_options(cfg, "lad")$geo_name, "Manchester")
})

test_that("Manchester people, trips and health histories remain aligned", {
  cfg <- miama_default_config("manchester")
  ids <- function(path) arrow::open_dataset(path) |>
    dplyr::select(census_id) |> dplyr::collect() |> as.data.frame()
  people <- ids(cfg$sources$sp_attributes$path)$census_id
  expect_length(people, 10000)
  expect_equal(anyDuplicated(people), 0L)
  expect_setequal(ids(cfg$sources$hm_outcomes$overall$path)$census_id, people)
  expect_setequal(ids(cfg$sources$hm_death_share$cycle$path)$census_id, people)
  expect_true(all(ids(cfg$sources$sp_trips$path)$census_id %in% people))
  expect_equal(nrow(load_hm_outcomes(cfg, census_ids = people[1:3])), 3)
})
test_that("city selection swaps all data sources without changing model assumptions", {
  cfg <- miama_default_config("leeds")
  cfg$counterfactual$population$new_user_percent_default <- 17
  expect_setequal(get_packaged_geo_options(cfg)$geo_name, c("Leeds", "Manchester"))
  man <- select_geographic_profile(cfg, "E08000003")
  expect_equal(man$population$profile$sampled_individuals, 10000)
  expect_equal(man$counterfactual$population$new_user_percent_default, 17)
  expect_match(man$sources$hm_death_share$cycle$path, "manchester")
  expect_equal(select_geographic_profile(man, "E08000035"), cfg)
  expect_error(select_geographic_profile(cfg, "unknown"), "available packaged LAD")
})
