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
active development orchestration flow.

## `appraisal_inputs` and the API boundary

For now, the `receive_appraisal_inputs()` function is an **R-level API boundary**,
not a web API. Its job is to accept the canonical `appraisal_inputs` object shape
used by `MIAMA-UI`, normalize it, and expose its values to the rest of
`MIAMA-HUB`.

At the moment, this boundary returns:

- `appraisal_inputs_in`: the normalized canonical object
- `appraisal_input_values`: a developer-friendly plain named list of values
- `reference_request`: the subset of inputs used for reference-data logic
- `counterfactual_request`: the subset of inputs used for counterfactual logic
- `results_request`: the subset of inputs used for output/result logic

This keeps `MIAMA-HUB` focused on calculation and data transformation, while
letting `MIAMA-UI` remain the source of truth for interactive input definition.

## `config` versus `request`

`MIAMA-HUB` now distinguishes between two different concepts:

- `config`: runtime and infrastructure choices
- `request`: appraisal-specific intent coming from `appraisal_inputs`

Examples of **config** concerns:

- file locations
- cache settings
- whether development uses the `sample` or `full` datasets
- whether local synthpop sources are parquet or dta

Examples of **request** concerns:

- geographic scope (`geo_level`, `geo_id`)
- result aggregation (`res_aggregation`)
- selected outcomes and modes
- later, counterfactual population and trip changes

A key recent change is that HM source selection is no longer driven by config.
Instead, `results_request$res_aggregation` maps to the HM dataset suffix:

- `total` -> `overall`
- `timeline` -> `cycle`

This keeps appraisal logic in the request layer and runtime concerns in config.

## Current development workflow for `appraisal_inputs`

Direct package-to-UI wiring is not finished yet. For development, `MIAMA-HUB`
uses a small helper, `build_mock_appraisal_inputs()`, which creates a **minimal
canonical mock** of the UI input object.

That mock is used in [inst/workflows/dev_workflow.R](inst/workflows/dev_workflow.R)
to:

1. create a temporary appraisal input object
2. pass it through `receive_appraisal_inputs()`
3. inspect the flattened values in `request$appraisal_input_values`
4. use those values to build and test downstream modules such as
   `filter_reference_data()` and request-driven source loading

The intent is to expand this mock incrementally as new modules are implemented,
rather than copying the full UI schema into `MIAMA-HUB`.

## Request-driven source loading

`load_reference_sources()` now accepts both config and request sections.

The current loading strategy is:

1. use `reference_request` to prefilter synthetic population attributes by
   geography where possible
2. derive matching `census_id` values from the filtered attributes
3. use those IDs to filter synthpop trips and HM outcomes
4. use `results_request$res_aggregation` to choose whether HM loads the
   `overall` or `cycle` dataset

This is intended to reduce unnecessary data transfer and memory use,
especially once synthetic population data is available in parquet format.

## Reference UI value extraction

`extract_reference_ui_values()` derives compact status-quo values from filtered
`reference_data` for returning to `MIAMA-UI`. The function now accepts the
flattened `appraisal_input_values` from `receive_appraisal_inputs()` so it can
honor Tab 2 UI choices such as selected `modes`, `at_data_unit`, denominators,
units, and timeframes.

The current extractor covers Tab 2 reference fields for:

- user counts (`users_count_ref_*`)
- trip counts (`trips_count_ref_*`)
- distance/duration amounts (`dist_dur_amount_ref_*`)
- mode shares and denominators (`mode_share_ref_*`, `mode_share_total_*`)

It also covers advanced Tab 3 and Tab 4 reference fields:

- population totals and per-mode population counts (`pop_total_ref`,
  `pop_number_ref_*`)
- population distribution anchors (`pop_spread_age_mean_ref`,
  `pop_spread_sex_prop_ref`, `pop_spread_pa_mean_ref`,
  `pop_spread_pa_sex_prop_ref`)
- trip totals and per-mode trip counts (`trips_number_total_ref`,
  `trips_number_ref_*`)
- trip distribution anchors (`trips_spread_mean_ref`,
  `trips_spread_util_prop_ref`)
- diversion denominators (`trips_diversion_total_trips`,
  `trips_diversion_trips_n`, `trips_diversion_distance_total`,
  `trips_diversion_duration_total`)

Individual-only values, such as walking and cycling user counts from
`walktime_wkhr` and `cycletime_wkhr`, can be extracted from `reference_data$ind`
alone. Trip counts, trip-level distance/duration values, and mode-share values
require `reference_data$trips`. The returned `extraction_report` records skipped
fields and notes when a requested UI value cannot be derived from the currently
available columns.

Current data columns distinguish walking and cycling but do not expose a
dedicated e-bike source. Walk-to-public-transport values are derived only when
trip-level data includes recognizable public-transport `trip_mainmode` values.

Current threshold assumptions are deliberately simple:

- walking users are individuals with `walktime_wkhr > 0`
- cycling users are individuals with `cycletime_wkhr > 0`
- walking trips have `trip_walktime_min > 0` or `trip_walkdist_km > 0`
- cycling trips have `trip_cycletime_min > 0` or `trip_cycledist_km > 0`
- walk-to-public-transport trips have recognizable public-transport
  `trip_mainmode` values plus positive walking time or distance

Future refinements should make these thresholds mode-specific and configurable.
Likely examples include defining walking users as `walktime_wkhr > 2`, or using
minimum trip-count thresholds such as more than 10 trips.

The Tab 3 distribution anchors currently use selected-mode current users for
`pop_*_current` choices and selected-mode non-users for `pop_*_new` choices.
If a selected group is empty, the extractor falls back to the filtered
population to avoid returning unusable distribution anchors. One schema issue is
currently unresolved: `pop_spread_pa_mean_ref` is named like a physical-activity
distribution mean, but its UI description, label, and unit describe mean age in
years. The extractor currently follows the UI text and returns mean age.

The Tab 4 trip distribution anchors currently use all trips in the filtered
reference geography. `trips_spread_util_prop_ref` classifies trips as
utilitarian unless `trip_purpose` looks recreational, leisure, sport, exercise,
holiday, visit, or social.

For plausibility checks across all Tab 2-4 reference fields, use
`inst/workflows/dev_reference_ui_values_tab234_all.R`.

The R6 `Hub` wrapper exposes the same output through
`build_reference_ui_values()` / `get_reference_ui_values()`. Call
`get_reference_ui_updates()` for the compact named UI update list, or
`get_reference_ui_value("field_name")` for a single value. `get_population_size()`
is retained only as a convenience wrapper around `pop_total_ref`; new code
should not add one R6 method per UI field.

## Counterfactual data initialization and UI application

`init_counterfactual_data()` starts Step 6 by returning a 1:1 copy of filtered
`reference_data`. The first UI-driven implementation is
`apply_counterfactual_ui_values()`, which applies supported `_cf_` inputs to
that copy and adds a compact `counterfactual_report`.

The current first-pass implementation supports `users_count_cf_*` and
`pop_number_cf_*` for walking and cycling. These fields adjust the number of
individuals with positive mode-specific weekly activity:

- if the counterfactual target is larger than the current reference count,
  existing non-users are sampled as `new_users`
- if the target is smaller, existing users are sampled as `ex_users`
- new users receive mode activity values sampled from the reference users'
  observed activity distribution
- ex-users receive values sampled from current non-users, usually zero
- `mmets` is recalculated when present using HM constants:
  `walktime_wkhr * 2.5 + cycletime_wkhr * 5.8 + sport_wkhr * 7`
- if trip-level data is present, changed individual activity columns are
  mirrored onto matching trip rows; trip rows are not created, deleted, or
  shifted yet

Targets must be finite, non-negative, rounded integer counts and cannot exceed
the filtered reference population size. E-bike and walk-to-public-transport
counterfactual user counts are currently reported as unsupported until the data
contains dedicated activity columns or agreed classification rules.

Parameter naming follows the same distinction used elsewhere in the package:
`*_ref` values are measured from filtered reference data, while `*_default`
values come from internal constants. Those constants are currently returned by
`miama_counterfactual_defaults()` and should be externalized once the defaults
are agreed.

The R6 `Hub` wrapper exposes this step via `build_counterfactual_data()` and
`get_counterfactual_data()`.

`R/counterfactual_data_apply_ui_values.R` is structured as a handler registry:
`apply_counterfactual_ui_values()` builds shared context, then each handler owns
one conceptual family of UI fields. The first implemented handler is active-mode
user-count targets. Future handlers should be added for activity amounts,
population distributions, trip counts, trip mode shifts, trip attributes, and
diversion rates. Keep each handler's assumptions visible near the handler code,
and keep cross-cutting validation, sampling, constants, and report helpers in
their dedicated outline sections.

For validation, every counterfactual run adds
`counterfactual_report$comparison`, with side-by-side reference vs.
counterfactual summaries for key active-travel and physical-activity columns.
The current comparison includes individual-level sums, means, active-row counts,
trip-level sums/means, trip row counts, and a `changed_ind_rows` table showing
affected `census_id` values with `_ref`, `_cf`, and `_delta` columns.

## Synthetic population parquet conversion

To enable Arrow filter pushdown, local synthpop `.dta` files should be converted
into parquet datasets.

A development helper, `convert_synthpop_to_parquet()`, is available for this
one-time local conversion.

Once parquet versions exist, `miama_paths()` will prefer them over the original
Stata files, and `load_reference_sources()` can prefilter by geography before
collecting data into R.

## Later adjustments needed

The current `appraisal_inputs` setup is deliberately temporary and dev-focused.
Later work should:

1. replace the mock helper with direct integration from `MIAMA-UI`
2. decide the runtime interface between UI and HUB (likely via package calls or
   Shiny server integration, not necessarily HTTP)
3. strengthen validation of required fields and allowed values
4. expand mapping from raw UI inputs into explicit reference, counterfactual,
   and results specifications
5. revisit the optimal timing of HM joins relative to counterfactual generation
6. keep `DESCRIPTION` updated whenever new package dependencies are introduced

## Data locations

For local development, large data files should not be tracked in git.
`data/` is git-ignored.

Current expected layout:

- synthetic population files live in `MIAMA-HUB/data/synthetic_pop/`
- HM processed outputs are read from `MIAMA-HM` via `MIAMA_HM_ROOT`

This arrangement is temporary. Longer-term data storage will likely move to a
VPS or another external location.
