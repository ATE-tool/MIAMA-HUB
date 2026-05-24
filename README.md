# MIAMA-HUB

`MIAMA-HUB` is a standalone R package that acts as the integration layer
between `MIAMA-UI` and `MIAMA-HM`.

The package is intended to:

- receive `appraisal_inputs` from the UI
- join health-model outputs with synthetic population data
- maintain filtered `reference_data`
- initialize and manipulate `counterfactual_data`
- prepare comparative risk assessment inputs and summaries
- return compact UI-ready values and result objects

## Design

`MIAMA-HUB` is a library, not an app. The package should be callable from
`MIAMA-UI`, but also from standalone R workflows when a valid
`appraisal_inputs` object is available.

The current scaffold organizes package code into six responsibilities:

- API
- input mapping
- reference data
- counterfactual data
- CRA
- shared utilities

## Core Objects

The scaffold is built around the following internal objects:

- `appraisal_inputs_in`
- `reference_data_raw`
- `reference_data`
- `reference_ui_values`
- `counterfactual_data`
- `health_impacts`
- `ui_return_payload`

## High-Level Flow

1. Receive `appraisal_inputs`
2. Normalize and map inputs into internal request specs
3. Load HM outputs and synthetic population sources
4. Join those sources into `reference_data_raw`
5. Filter to the relevant `reference_data`
6. Extract compact UI reference values
7. Initialize and manipulate `counterfactual_data`
8. Prepare CRA inputs and health impact summaries
9. Build a compact UI return payload

See [inst/workflows/dev_workflow.R](inst/workflows/dev_workflow.R) for the
intended package orchestration flow.
