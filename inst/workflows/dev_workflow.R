# Dev workflow placeholder for MIAMA-HUB.
#
# Intended high-level package flow:
# 1. receive `appraisal_inputs`
# 2. normalize/map inputs
# 3. load + join reference sources
# 4. filter `reference_data`
# 5. extract reference UI values
# 6. initialize/apply counterfactual changes
# 7. run CRA
# 8. build UI return payload

# Example pseudo-flow:
#
# request <- receive_appraisal_inputs(appraisal_inputs)
# reference_sources <- load_reference_sources()
# reference_data_raw <- join_hm_and_synthpop(reference_sources)
# reference_data <- filter_reference_data(reference_data_raw, request$reference_request)
# reference_ui_values <- extract_reference_ui_values(reference_data, request$reference_request)
# counterfactual_data <- init_counterfactual_data(reference_data)
# counterfactual_data <- apply_ind_rows_changes(counterfactual_data, request$counterfactual_request)
# counterfactual_data <- apply_ind_attribute_changes(counterfactual_data, request$counterfactual_request)
# counterfactual_data <- apply_trip_rows_changes(counterfactual_data, request$counterfactual_request)
# counterfactual_data <- apply_trip_attribute_changes(counterfactual_data, request$counterfactual_request)
# cra_inputs <- prepare_cra_inputs(reference_data, counterfactual_data, request$results_request)
# health_impacts <- run_cra(cra_inputs)
# build_ui_return_payload(
#   ui_updates = reference_ui_values,
#   reference_summaries = summarize_reference_data(reference_data),
#   counterfactual_summaries = summarize_health_impacts(health_impacts, request$results_request),
#   health_impacts = health_impacts,
#   state = list(reference_data = reference_data, counterfactual_data = counterfactual_data)
# )
