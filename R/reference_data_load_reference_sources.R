# MIAMA-HUB Module: Reference Data / Load Reference Sources
# Purpose: Load the upstream data sources that feed `reference_data_raw`,
#   especially HM outputs and synthetic population data.
# Inputs: Source configuration or package defaults.
# Outputs: A bundle of raw reference sources, not yet joined.
# Notes: This is one of the first files likely to receive adapted legacy MIAMA
#   code from the current workflow and path-loading logic.
#
# Placeholder for loading HM outputs and synthetic population sources.
load_reference_sources <- function(source_config = list()) {
  list(
    hm_outputs = NULL,
    synthetic_population = NULL,
    source_config = source_config
  )
}
