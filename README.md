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
- which parquet directories provide local synthpop sources

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

## Geographic levels and options

`MIAMA-HUB` exposes lightweight geography helpers for UI select controls:

- `get_geo_levels(cfg)` returns available levels.
- `get_geo_options(cfg, geo_level)` returns selectable `geo_id` / `geo_name`
  rows for one level.
- `Hub$get_geo_options(geo_level)` exposes the same options through the
  session object.

The current lookup is built from the synthpop individual attributes parquet
source and cached at `data/lookup/geo_options.rds`. If the cache is missing, the
first call builds it from `cfg$sources$sp_attributes`; subsequent calls read the
small RDS lookup instead of loading full reference data. The currently supported
levels are:

- `eng`: one England-wide option
- `reg`: English regions, using `region`
- `lad`: local authority districts, using `lad25cd` and `lad25nm`

The alias `region` is accepted by `get_geo_options()` and normalized to `reg`.
Grouped LAD and MSOA options are not derived yet because the current synthpop
attributes source only exposes `region`, `lad25cd`, and `lad25nm`.

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

### Initialize counterfactual data
`init_counterfactual_data()` starts Step 6 by returning a 1:1 copy of filtered
`reference_data`. The first UI-driven implementation is
`apply_counterfactual_ui_values()`, which applies supported `_cf_` inputs to
that copy and adds a compact `counterfactual_report`.

### Users: derive counterfactual number of active mode users
The current implementation supports `users_count_cf_*` and `pop_number_cf_*`
for walking and cycling. These fields adjust the number of individuals with
positive mode-specific weekly activity while keeping the individual population
fixed:

- if the counterfactual target is larger than the current reference count,
  existing non-users are sampled as `new_users`
- if the target is smaller, existing users are sampled as `ex_users`
- new users receive mode activity values sampled from observed current users
- ex-users receive configured near-zero defaults, currently `0`
- returned individual data includes explicit `user_walk` / `user_bike`
  indicators and `cf_user_change`
- `mmets` is recalculated when present using HM constants:
  `walktime_wkhr * 2.5 + cycletime_wkhr * 5.8 + sport_wkhr * 7`
- if trip-level data is present, ex-users' active trips are shifted away from
  the active mode; new users trigger sampling of plausible non-active trips for
  mode shift where matching trip rows exist
- new-user trip shifts use current-user active trip rates: active trip counts
  are computed for current users and sampled onto new users, rather than
  assuming exactly one shifted trip per new user

Targets must be finite, non-negative, rounded integer counts and cannot exceed
the filtered reference population size. E-bike and walk-to-public-transport
counterfactual user counts are currently reported as unsupported until the data
contains dedicated activity columns or agreed classification rules.

### Trips: derive counterfactual number of active mode trips
The trip-count handler supports `trips_count_cf_*` and `trips_number_cf_*` for
active-mode trip rows. It converts Tab 2 targets from total or mean-per-person
values into a base-week trip count. Increases are split into two mechanisms:

- `mode_shift`: existing non-active, utilitarian trips are switched to the
  active mode. Raw trip distance is preserved, and the active-mode
  distance/duration columns are populated from raw distance/duration.
- `induced_recreational_active`: a default 10% of additional active trips are
  treated as newly induced discretionary trips and added as new trip rows with
  recreational purpose.

Decreases do not delete utilitarian travel demand. Instead, sampled active trips
are shifted away from the active mode using the configured default diversion
mode, currently `car`. If Tab 4 provides diversion percentages, the HUB parses
the current simple `trips_diversion_car_perc` field and future mode-specific
fields such as `trips_diversion_walk_perc`, `trips_diversion_bike_perc`,
`trips_diversion_ebike_perc`, and `trips_diversion_pt_perc`.

Returned trip data includes explicit `trip_activemode`, `trip_utilitarian`,
`cf_trip_change`, `cf_mode_shift`, and `cf_induced` indicators. The change
report records actual `mode_shift_n` and `induced_n`, and
`counterfactual_report$comparison$changed_trip_rows` lists switched or induced
trip rows.

Advanced Tab 4 fields such as `trips_dist_value`, `trips_purpose_type`,
`trips_spread_mean_cf`, `trips_spread_util_prop_cf`, and
`trips_diversion_car_perc` are parsed and recorded. Distance-based candidate
selection currently uses active-mode reference trip-distance quintiles; future
UI category controls can plug into the `agecat_1_prop_cf` ...
`agecat_5_prop_cf` and `distcat_1_prop_cf` ... `distcat_5_prop_cf` hooks, or
the corresponding `_perc_cf` fields.

TODO: Important limitation: the draft trip handler currently changes physical rows,
not weighted `weight_tripXhh` totals. Existing shifted rows keep their existing
weights; induced trip rows receive `weight_tripXhh = 1` when that column exists.
This is useful for validating the manipulation flow, but the weighted-data
behavior needs to be resolved before using these trip changes for final impact
calculations.

Parameter naming follows the same distinction used elsewhere in the package:
`*_ref` values are measured from filtered reference data, while `*_default`
values come from internal constants. Those constants are currently returned by
`miama_counterfactual_defaults()` and should be externalized once the defaults
are agreed.

Sampling is centralized in `R/counterfactual_data_sampling_functions.R`.
Sampling now means selecting existing candidate rows "as is"; the previous
average-row and synthetic-distribution options were removed because they
conflicted with the fixed-population mechanism. Candidate individual selection
can be weighted by sex and five age-category targets. Candidate trip selection
can be weighted by active-mode distance categories derived from local reference
quintiles until final category breaks are available.

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
It also includes `changed_trip_rows` for trip mode switches and induced trips.

### Counterfactual health outcomes
`apply_counterfactual_health_outcomes()` is the Step 7 bridge from changed
counterfactual physical activity to health model outcomes. It uses the updated
MIAMA-HM death-share cycle artifacts:

- `sp_cycle_outcomes_death_share`
- `mmet_d_cycle_lookup_death_share`

Those artifacts are produced by `MIAMA-HM/scripts/sp_hm_join.R`. HUB does not
source or duplicate that script; it reads the processed artifacts and reproduces
the scenario lookup-application logic documented in
`MIAMA-HM/scenario_verification/scen_30to45_2mmets.qmd`.

Terminology in this step is explicit:

- `ref`: without-scheme/reference scenario
- `cf`: with-scheme/counterfactual scenario
- `delta`: `cf - ref`
- `baseline`: avoided here except when referring to HM source tables, because it
  can also mean the first simulation year

The function keeps all filtered individuals and all HM cycle rows. For the
current `scheme_effect_duration = "longterm"` setting, the individual-level
MMET delta from Step 6 is applied to every model cycle:

```r
mmets_delta = mmets_cf_ind - mmets_ref
mmets_new   = mmets_cycle + mmets_delta
```

It then caps MMETs to the lookup maximum, overlaps the changed MMET interval
with lookup bands, multiplies overlap width by per-MMET outcome slopes, and
adds `d_*` outcome columns. Convenience `*_cf` columns are also added as
`ref + delta` for plotting and inspection.

The returned `counterfactual_data` gains:

- `health_outcomes`: full cycle-level reference, delta, and counterfactual
  outcome table
- `counterfactual_health_report`: counts, MMET-delta summary, terminology, and
  summed outcome deltas
- `counterfactual_health_report$impact_overview`: compact outcome-level totals
  with `ref_total`, `cf_total`, `delta_total`, and `delta_per_1000_people`

Future work: add `scheme_effect_duration = "shortterm"` and decide whether
large production runs should keep all `*_cf` columns or compute them lazily for
plotting to reduce data volume.

## Synthetic population parquet conversion

Runtime synthpop sources are parquet datasets. Legacy `.dta` files are only
supported as optional local conversion inputs and are not required by the HUB
pipeline.

A development helper, `convert_synthpop_to_parquet()`, is available for this
one-time local conversion.

`miama_paths()` resolves to `SPindivid_CensusNTSALS_dev_parquet` when present,
otherwise `SPindivid_CensusNTSALS_parquet`, with the equivalent trip paths for
`SPtrip_CensusNTSALS`. `load_reference_sources()` then prefilters by geography
before collecting data into R.

The geography option lookup is a second small one-time/cacheable artifact. It is
created by `build_geo_lookup(overwrite = TRUE)` or lazily by
`get_geo_levels()` / `get_geo_options()`, and is stored at
`data/lookup/geo_options.rds`.

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
- HM sample processed outputs may live in `MIAMA-HUB/data/health_data/`
- full HM processed outputs are read from `MIAMA-HM` via `MIAMA_HM_ROOT`

HM outcome loading follows this hierarchy:

1. cached RDS files in `MIAMA-HUB/data/cache/` when cache is enabled and no
   census-id prefilter is requested
2. HUB-local sample parquet directories such as
   `data/health_data/sp_overall_outcomes_sample/`
3. external MIAMA-HM parquet directories under `MIAMA_HM_ROOT/health_data/processed/`

This arrangement is temporary. Longer-term data storage will likely move to a
VPS or another external location.
