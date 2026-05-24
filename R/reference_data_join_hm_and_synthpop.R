# MIAMA-HUB Module: Reference Data / Join HM and Synthetic Population
# Purpose: Join raw HM outputs and synthetic population data into
#   `reference_data_raw`.
# Inputs: Bundle of reference source objects returned by
#   `load_reference_sources()`.
# Outputs: Joined raw reference data object.
# Notes: This is the clearest early migration target from legacy MIAMA. The
#   HM+synthpop join should be adapted here explicitly rather than left in a
#   workflow script.
#
# Placeholder for joining HM outputs and synthetic population data.
join_hm_and_synthpop <- function(reference_sources) {
  assert_named_list(reference_sources, "reference_sources")

  list(
    reference_data_raw = data.frame(),
    hm_outputs = reference_sources$hm_outputs,
    synthetic_population = reference_sources$synthetic_population
  )
}
