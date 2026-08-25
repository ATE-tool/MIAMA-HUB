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

## Profile objects and the API boundary

For now, the `receive_appraisal_inputs()` function is an internal **R-level API
boundary**, not a web API. Its job is to accept the active MIAMA-UI profile
object, normalize it, and expose its submitted values to the rest of
`MIAMA-HUB`.

In MIAMA-UI, the active profile is created from `schemes/default.R`:

```r
mdata[["profile"]] <- mdata$schemes$default$appraisal_inputs
```

HUB expects that same canonical parameter-list shape. The field contract is:

- `input_value`: value submitted by the user or Shiny input binding
- `is_filled`: `TRUE` only when `input_value` should be treated as a submitted
  appraisal value
- `default_value`: UI prefill/default value, including HUB-derived reference
  values

`default_value` is deliberately not promoted into `input_value`. This prevents
reference defaults from being mistaken for user-supplied counterfactual or
results inputs.

At the moment, this boundary returns:

- `appraisal_inputs_in`: the normalized canonical object
- `appraisal_input_values`: a developer-friendly plain named list of values
- `reference_request`: the subset of inputs used for reference-data logic
- `counterfactual_request`: the subset of inputs used for counterfactual logic
- `results_request`: the subset of inputs used for output/result logic

This keeps `MIAMA-HUB` focused on calculation and data transformation, while
letting `MIAMA-UI` remain the source of truth for interactive input definition.
The `request` object is therefore a HUB-internal convenience view, not an object
that MIAMA-UI needs to manage directly.

## R6 Hub method outline

The R6 `Hub` object is the intended session-scoped interface for MIAMA-UI. It is
initialized with runtime configuration only. Profile objects are supplied to
UI-facing methods when needed; HUB then stores the active profile, the internal
request view derived from that profile, and any intermediate data objects built
during the appraisal.

Primary UI-facing methods:

- `get_appraisal_setup_inputs(profile = NULL)`: returns the setup subset of the
  profile, currently `ui_version`, `ui_input_scope`, `geo_level`, `geo_id`,
  `modes`, `intervention_type`, and `data_source`.
- `build_reference_profile_defaults(profile = NULL, refresh = FALSE)`: loads
  and filters synthpop reference data for the selected geography, summarizes
  reference values, and writes matching values into each profile field's
  `default_value`.
- `build_results(profile = NULL, seed = 1L, refresh = FALSE)`: runs the current
  end-to-end calculation from the fully filled profile. It builds
  counterfactual data from the synthpop reference data, applies the HM
  death-share cycle lookup to ref/cf physical-activity exposure, and returns
  the updated `profile`, `reference_data`, `counterfactual_data`, compact
  `health_impacts`, and `results_data`. The full person-cycle table is released
  after these compact result objects have been built.
- `get_results_highlights()`: after `build_results()`, returns the three
  assessment-period totals for prevented deaths, saved life-years, and
  prevented disease cases.
- `get_results_options()` / `get_ui_options(option)`: return lightweight,
  configured IDs and labels for UI controls without loading appraisal data.
- `get_assessment_period()`: returns the canonical model/result horizon.

The intended Shiny flow is:

```r
hub <- MIAMAHUB::Hub$new(cfg = hub_cfg)

setup_profile <- hub$get_appraisal_setup_inputs(mdata[["profile"]])

mdata[["profile"]] <- hub$build_reference_profile_defaults(mdata[["profile"]])
attr(mdata[["profile"]], "reference_defaults_report")

# After the UI has collected Tab 2 or Tab 3/4 counterfactual inputs:
result <- hub$build_results(mdata[["profile"]])
```

For inspection during development:

```r
names(hub$get_profile())
str(hub$get_profile()$pop_total_ref_basic)
str(hub$get_profile()$pop_total_ref_advanced)
hub$get_request()$appraisal_input_values
hub$get_reference_ui_updates()
result$results_data$results_table
```

For a more realistic profile test that reads the actual MIAMA-UI
`schemes/default.R`, fills a LAD selection, runs the reference-data pipeline,
and creates an inspectable `profile_with_defaults` object, run:

```r
source("inst/workflows/dev_profile_defaults_from_ui_default.R")
```

Developer helpers such as `load_reference_sources()`, `build_reference_data()`,
`build_counterfactual_data()`, and `build_results_data()` remain available for
workflow scripts and targeted testing. New MIAMA-UI integration should prefer
the primary methods above, with `request` treated as HUB-internal state.

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
- `get_geo_details(cfg, geo_id, geo_level = NULL)` resolves one selected option
  to summary fields for Tab 1: `location`, `geographic_scale`, and
  `administrative_location_id`.
- `get_geo_name(cfg, geo_level, geo_id)` resolves one selected geography to its
  display name.
- `Hub$get_geo_options(geo_level)` exposes the same options through the
  session object.
- `Hub$get_geo_name()` resolves the current session's selected geography.

The current lookup is built from the full synthpop individual attributes parquet
source and cached at `data/lookup/geo_options.rds`. The same full-derived lookup
is also stored at `inst/extdata/data/lookup/geo_options.rds` for installed
package deployments. If the cache is missing, the first call builds it from
`cfg$sources$sp_attributes`; subsequent calls read the small RDS lookup instead
of loading full reference data. The returned table includes:

- `n_individuals`: synthetic rows in the full 5% sample
- `person_weight`: currently `20`
- `population_size_synth_scaled`: `n_individuals * person_weight`
- `population_source`: `"Census 2021 5% synthpop scale"`

The currently supported levels are:

- `eng`: one England-wide option
- `reg`: English regions, using `region`
- `lad`: local authority districts, using `lad25cd` and `lad25nm`

The alias `region` is accepted by `get_geo_options()` and normalized to `reg`.
Grouped LAD and MSOA options are not derived yet because the current synthpop
attributes source only exposes `region`, `lad25cd`, and `lad25nm`.

Tab 1 can call the lightweight geography helpers directly, without creating a
`Hub` object:

```r
lad_options <- MIAMAHUB::get_geo_options(mdata[["hub_cfg"]], "lad")
geo_details <- MIAMAHUB::get_geo_details(mdata[["hub_cfg"]], input$geo_id)

geo_details$location
geo_details$geographic_scale
geo_details$administrative_location_id
geo_details$population_size_synth_scaled
```

## Timeframe value conversion

`convert_timeframe_value()` is the shared HUB/UI converter for values expressed
per day, week, or year. It is exported and does not require a `Hub` object or
loaded reference data:

```r
annual_trips <- MIAMAHUB::convert_timeframe_value(
  old_timeframe = "week",
  old_value = 100,
  new_timeframe = "year",
  datatype = "trips"
)
```

The equivalent session method is `hub$convert_timeframe_value(...)`. Both use
the same implementation. For `datatype = "trips"`, the factors are day =
`1 / 7` week, week = `1`, and year = `52.1775` weeks. This datatype is also used
for total distance and total duration, which accumulate linearly over time.

For `datatype = "users"`, the current conversion factor is `1` for every
day/week/year combination. This is a documented provisional assumption because
distinct people do not scale linearly with the observation period. The API lets
us replace those factors later without changing UI call sites. HUB reference
extraction and counterfactual normalization call the same function, preventing
UI display conversions from diverging from calculation conversions.

## Tab 1 appraisal summary values

The Tab 1 summary should reuse canonical user-selected fields where they already
exist, rather than creating duplicate summary-only parameter names. In
particular, `geo_level` and `geo_id` remain the source of truth for the selected
geography.

Summary-only fields should be reserved for values that are derived or displayed:

- `geo_name`: display name resolved from `geo_level` / `geo_id`
- `population_size`: display alias for the filtered reference population size
- `appraisal_name`: user-entered nickname for the appraisal

`geo_name` / `location` is available from the lightweight geography lookup and
can be resolved before full reference data is built. Prefer
`get_geo_details(cfg, geo_id)` for Tab 1 summary panels. `population_size` is
the canonical summary value corresponding to both `pop_total_ref_basic` and
`pop_total_ref_advanced`; it is available after reference data has been filtered
and `extract_reference_ui_values()` has run. The R6 API still exposes a compact
development helper:

```r
hub$get_appraisal_summary_values()
```

which returns `geo_level`, `geo_id`, `geo_name`, `population_size`, and
`appraisal_name`.

In `appraisal_inputs`, `input_source` is optional metadata used by HUB
normalization: when omitted it defaults to `"user"`. For fields populated by HUB
rather than typed by the user, set it explicitly to `"derived"` so UI code and
developers can distinguish display values from user inputs.

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

## Configuration orientation

`miama_default_config()` is the main developer-facing index of configurable
HUB behavior. Its top-level sections distinguish workflow controls (`workflow`,
`arrow`), model assumptions (`population`, `physical_activity`, `spread`),
stable presentation metadata (`results`), and infrastructure (`sources`,
`cache`, `output`). Override individual leaf values rather than replacing the
whole config wherever possible.

Tab 5 health outcome definitions live in `cfg$results$outcomes`. Each named
definition records its UI label, outcome type, category, reference HM source
columns, and whether it is selected by default. Composite outcomes such as CVD
and all cancers explicitly list all columns that are summed. Results
preparation consumes this same catalogue, so UI choices and calculations do
not maintain separate hard-coded mappings.

## Request-driven source loading

`load_reference_sources()` now accepts both config and request sections.

The current loading strategy is:

1. use `reference_request` to prefilter synthetic population attributes by
   geography where possible
2. derive matching `census_id` values from the filtered attributes
3. filter synthpop trips by the same geography when possible; for unscoped or
   England-wide requests, use the matched `census_id` values to keep trips
   aligned with loaded attributes
4. load one-row-per-person HM `overall` outcomes only when results are built;
   cycle/death-share outcomes remain deferred to the counterfactual health step

This is intended to reduce unnecessary data transfer and memory use,
especially once synthetic population data is available in parquet format.

Parquet reads run through a small Arrow runtime wrapper. By default
`miama_default_config()` sets `cfg$arrow$cpu_count = 1L` during HUB source
loading, restores the previous Arrow thread setting afterwards, and triggers
garbage collection after the read block. This avoids large parallel decode
buffers in memory-constrained Shiny/Connect sessions. Set
`cfg$arrow$cpu_count = NULL` to leave Arrow's current thread setting unchanged.

## Reference UI value extraction

`extract_reference_ui_values()` derives compact status-quo values from filtered
`reference_data`. The low-level function still returns a named `ui_updates`
list for developer inspection and tests. The UI-facing R6 method is
`Hub$build_reference_profile_defaults(profile)`: it runs the synthpop-only
reference-default pipeline and writes all matching reference values into the
profile's `default_value` fields. HM outcome data are not loaded for this step;
health-model data are first needed when `build_results()` applies ref/cf health
outcome calculations.

The extraction and profile-write responsibilities are intentionally separated:

- [reference_data_extract_reference_ui_values.R](R/reference_data_extract_reference_ui_values.R)
  derives all reference values that HUB currently knows how to calculate.
- [api_reference_profile_defaults.R](R/api_reference_profile_defaults.R)
  writes each derived value into `default_value` when the matching profile field
  exists.

Intended UI usage:

```r
hub <- MIAMAHUB::Hub$new(cfg = hub_cfg)
mdata[["profile"]] <- hub$build_reference_profile_defaults(mdata[["profile"]])
```

Before this call, MIAMA-UI must copy the selected Tab 1 setup values into
`mdata[["profile"]]`, especially `geo_level`, `geo_id` for non-England
geographies, `ui_version`, `modes`, `intervention_type`, and `data_source`.
The R6 method now fails fast if reference geography is missing, because an
unscoped call can otherwise trigger a much larger parquet load than intended.

The returned profile keeps `input_value` and `is_filled` unchanged. Fields that
do not exist in the UI profile are skipped and listed in the diagnostic
`reference_defaults_report` attribute. This attribute is not part of the
appraisal schema and does not drive UI or HUB behavior. It records
`updated_fields`, `mirrored_cf_fields`, `mirrored_cf_sources`, `skipped_fields`,
and their counts so developers can reconcile calculated HUB values with fields
available in the UI profile. HUB writes broad defaults and leaves conditional
display choices to MIAMA-UI.

### HUB session state and refresh behavior

`Hub$new(cfg = hub_cfg)` creates a session-scoped object. Construction is light:
it stores configuration only and does not load parquet data. Synthpop reference
default data are first loaded when `build_reference_profile_defaults()` calls
`build_reference_default_data()`. HM outcome data are loaded later by
`build_results()` / `build_counterfactual_health_outcomes()`.

The object keeps intermediate reference objects only while they remain useful:

- `reference_default_data`: synthpop-only reference data for UI defaults and
  counterfactual construction
- `reference_default_ui_values`: compact extracted defaults for the active
  profile
- `reference_sources`, `reference_data_raw`, `reference_data`: HM-enriched
  reference objects used by lower-level workflow scripts and result building

When `build_results()` follows reference-default extraction, it reuses the
already geography-filtered synthpop rows and loads only matching HM outcomes.
It does not read the attributes and trips parquet sources a second time. Once
compact defaults and health-enriched reference data exist, redundant source and
default row tables are released before the counterfactual and cycle objects are
materialized. Trip data retain the SP person/trip fields needed by sampling but
do not repeat wide HM outcome columns on every trip row.

When `build_reference_profile_defaults(profile)` receives a profile, HUB
compares the new flattened input values with the previous request and
invalidates cached state as needed:

- Changes to `geo_level`, `geo_id`, or `res_aggregation` clear reference data
  caches, so the next call reloads/rebuilds reference data.
- Lighter changes such as `modes`, `ui_version`, denominators, units, or
  timeframes keep loaded reference data but clear extracted default values, so
  defaults are recalculated from the same data.
- Counterfactual and results objects are cleared whenever submitted profile
  values change. Counterfactual and Tab 5-only changes retain the compact
  reference defaults; only inputs that affect reference extraction clear and
  recompute them.

Use `refresh = TRUE` only for an explicit forced recomputation when the inputs
have not changed, for example during debugging or after replacing source files
on disk. Normal UI navigation from Tab 2 back to Tab 1 and selecting a different
location should not require `refresh = TRUE`; the geography change should
invalidate and reload automatically.

The extractor accepts the flattened submitted values from
`receive_appraisal_inputs()` so it can honor selected denominators, units, and
timeframes. The default UI schema should use `week` as the baseline timeframe;
year/day conversions are lightweight display recalculations and should not
force a full reference-data reload.

Broad default-writing rules:

- `build_reference_profile_defaults(profile)` calculates the available
  reference defaults broadly and writes every matching field in the profile.
- It does not filter default writes by `ui_version`, `at_data_unit`, selected
  `modes`, or `trips_refine_method`; those profile fields control what the UI
  displays, not what HUB is allowed to precompute.
- All supported active modes are calculated where the required reference columns
  exist. Unsupported or unavailable mode fields are returned as `NA` and listed
  in the extraction report.
- Mode share defaults include both scalar fields (`mode_share_ref_*`,
  `mode_share_total_*`) and the aggregate `mode_share_ref` list used by the UI
  pie-input schema.

This broad-default approach minimizes UI/HUB round trips after Tab 1. Dedicated
small methods can still be added for cheap recalculations, such as changing a
trip count from week to year or day without reloading parquet data.

The current extractor covers Tab 2 reference fields for:

- user counts (`users_count_ref_*`)
- trip counts (`trips_count_ref_*`)
- distance/duration amounts (`dist_dur_amount_ref_*`)
- mode shares and denominators (`mode_share_ref`, `mode_share_ref_*`,
  `mode_share_total_*`)

It also covers advanced Tab 3 and Tab 4 reference fields:

- basic and advanced population totals and per-mode population counts
  (`pop_total_ref_basic`, `pop_total_ref_advanced`,
  `pop_number_ref_*_basic`, and `pop_number_ref_*_advanced`) plus the canonical
  `population_size` summary value
- mode-specific population distribution anchors (`pop_spread_age_mean_ref_*`,
  `pop_spread_sex_prop_ref_*`, `pop_spread_pa_mean_ref_*`,
  `pop_spread_pa_sex_prop_ref_*`)
- mode-specific compact population spread bars (`pop_spread_bars_ref_*`)
- mode-specific compact PA spread bars (`pa_spread_bars_ref_*`, plus temporary
  `pop_spread_pa_bars_ref_*` aliases while the UI field names settle)
- trip totals and per-mode trip counts (`trips_number_total_ref`,
  `trips_number_ref_*`)
- mode-specific trip distribution anchors (`trips_spread_mean_ref_*`,
  `trips_spread_util_prop_ref_*`)
- mode-specific compact trip spread bars (`trips_spread_bars_ref_*`)
- diversion denominators (`trips_diversion_total_trips`,
  `trips_diversion_trips_n`, `trips_diversion_distance_total`,
  `trips_diversion_duration_total`)

Individual-only values, such as walking and cycling user counts from
`walktime_wkhr` and `cycletime_wkhr`, can be extracted from `reference_data$ind`
alone. Trip counts, trip-level distance/duration values, and mode-share values
require `reference_data$trips`. The returned `extraction_report` records skipped
fields and notes when a requested UI value cannot be derived from the currently
available columns. It also includes `spread_bar_values`, a flattened report
table of every compact reference spread bar payload with its source profile
field, category, plotted variable, percent, and proportion.

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

### Spread plot payloads and slider redistribution

MIAMA-UI still owns modal presentation and plotting. HUB owns the data
calculation. The intended split is:

- UI uses its plotting function, currently derived from the POC
  `plot_dist_bars()` implementation.
- HUB provides mode-specific reference slider anchors, such as
  `pop_spread_age_mean_ref_bike` and `trips_spread_mean_ref_walk`.
- HUB also provides compact reference bar values in profile `default_value`
  fields.
- UI can call `hub$get_spread_bar_values(...)` or
  `MIAMAHUB::spread_bar_values_from_slider(...)` to update counterfactual bars
  interactively when the user moves a slider. These cf bars are for display;
  UI only needs to submit the cf mean/proportion slider scalar fields.
- `Hub$build_results()` also attaches the same ref/cf spread payloads at
  `result$spread_data` and `result$results_data$plot_data$spreads`.

The compact spread bar object is a 10-row data frame: five categories crossed
with two plotted variables. It contains `topic`, `scenario`, `category_order`,
`category`, `category_midpoint`, `variable_order`, `variable`, `percent`, and
`proportion`. This object is intentionally small and independent of raw
individual/trip rows, so Shiny can update plots without keeping the full
synthpop in memory.

Current reference spread topics:

- `pop`: five configured age categories crossed with `male` / `female`, based
  on selected-mode users. Defaults follow the POC labels: `18-29`, `30-39`,
  `40-49`, `50-59`, `60+`.
- `trips`: five configured trip-distance categories crossed with `utilitarian` /
  `recreational`, based on selected active-mode trips. Defaults follow the POC
  labels: `0-2km`, `2-5km`, `5-10km`, `10-30km`, `30+km`.
- `pa`: five configured physical-activity categories crossed with `male` /
  `female`, based on selected-mode users and available `mmets` / `mmet_wkhr`
  values; if needed, HUB reconstructs a pragmatic MMET-like value from walking,
  cycling, and sport hours. Defaults use the current POC category wording:
  `sedentary`, `low`, `moderate`, `high`, `very_high`.

#### Tab 3 population and PA spread lifecycle

Tab 3 spread controls are mode-specific. Profile field suffixes follow the UI
mode naming convention: `walking -> walk`, `cycling -> bike`, `ebiking ->
ebike`, and public transport/walking-to-PT -> `pt`. Walking and cycling are the
currently supported production paths; other modes are populated only when the
required source columns are available.

At the end of Tab 1, UI calls:

```r
mdata[["profile"]] <- mdata[["hub"]]$build_reference_profile_defaults(
  mdata[["profile"]]
)
```

That call loads the location-specific synthetic population once, derives all
supported reference spreads, and writes them into matching profile
`default_value` fields. The Tab 3 UI then reads the following fields for each
mode suffix:

| Topic | Reference bars | Reference mean slider | Reference proportion slider | Counterfactual mean input | Counterfactual proportion input |
|---|---|---|---|---|---|
| Age and gender | `pop_spread_bars_ref_{mode}` | `pop_spread_age_mean_ref_{mode}` | `pop_spread_sex_prop_ref_{mode}` | `pop_spread_age_mean_cf_{mode}` | `pop_spread_sex_prop_cf_{mode}` |
| PA and gender | `pa_spread_bars_ref_{mode}` | `pop_spread_pa_mean_ref_{mode}` | `pop_spread_pa_sex_prop_ref_{mode}` | `pop_spread_pa_mean_cf_{mode}` | `pop_spread_pa_sex_prop_cf_{mode}` |

`pop_spread_pa_bars_ref_{mode}` is a temporary alias for
`pa_spread_bars_ref_{mode}`. New UI code should use the shorter canonical
`pa_spread_bars_ref_{mode}` name.

Reference population bars are calculated from current users of the selected
mode. A user is identified from the positive mode-specific weekly activity
column, or from linked mode-specific trips when that individual column is not
available. The population spread uses one unweighted row per synthetic person.
The PA spread uses the same mode-user filter and the individual's total weekly
MMET exposure. If joined HM `mmets` are unavailable during reference-default
extraction, HUB reconstructs the exposure from walking, cycling, and sport
hours using the configured activity intensities.

Each reference bar payload is a joint distribution that totals 100 percent.
The reference mean slider is derived from the five category totals and their
configured midpoints, so it is a grouped-data approximation rather than the
raw arithmetic mean. The reference proportion slider is the total share of the
first variable (`male`).

The current profile distinguishes modal choices for distributions among
current users versus new users, but HUB currently has one reference spread per
mode and that spread describes current mode users. For a new-user modal, it is
therefore the observed current-user pattern used as the starting assumption.
The submitted counterfactual sliders constrain which non-users are sampled as
new users. A separate empirical reference distribution of prospective new
users is not currently available.

When `Hub$build_reference_profile_defaults(profile)` writes a mode-specific
spread slider's observed `_ref_` value, it also writes that value to the paired
`_cf_` field's `default_value`. The counterfactual slider therefore starts at
the no-change reference position. HUB does not set `input_value` or
`is_filled`, and an existing user-submitted counterfactual value is preserved.
This applies to age mean, sex proportion, PA mean, PA sex proportion, trip
distance mean, and trip utilitarian proportion for each supported mode.

#### Slider redistribution logic

`spread_bar_values_from_slider()` receives the compact reference bars and the
two counterfactual slider values. Reference bar payloads also carry the
reference mean and proportion as compact anchor columns. It does not load or
retain raw synthetic population data.

1. HUB sums the 10 reference cells into a five-category marginal and a
   two-variable marginal.
2. The five-category marginal is exponentially tilted until its midpoint-based
   mean matches `cf_mean`. This preserves the reference shape as far as the
   requested mean allows and avoids generating one artificial average category.
3. `cf_prop` sets the first variable's share exactly; the second share is
   `1 - cf_prop`. Values may be supplied as `0-1` proportions or `0-100`
   percentages and are clamped to the valid range.
4. HUB combines the two counterfactual marginals with an outer product. The
   counterfactual joint bars therefore assume independence between age and sex,
   or between PA category and sex.
5. The function returns the same 10-row schema as the reference bars, with
   `scenario = "cf"`.

If one slider argument is `NULL`, its reference marginal is retained. If both
are `NULL`, the exact reference joint cells are returned with only the scenario
label changed. The same exact return now applies when the supplied CF slider
values equal the reference anchors. Consequently the initial CF plot is an
exact copy of the reference plot. The outer-product independence assumption is
applied only after at least one slider moves away from its reference anchor.

Category labels, breaks, and slider midpoints live in `cfg$spread`, which is
created by `miama_default_config()`. The current defaults are intentionally easy
to override:

- `cfg$spread$age`
- `cfg$spread$trip_distance`
- `cfg$spread$pa`

The synthetic population stores single-year age (`age1year`), not a native age
group. HUB therefore derives one canonical set of adult appraisal groups from
`cfg$spread$age`: `18-29`, `30-39`, `40-49`, `50-59`, and `60+` (IDs
`age_18_29` through `age_60_plus`). These same definitions drive Tab 3 counts
and spread bars, counterfactual sampling constraints, the Tab 5 health cube,
plot labels, and the static `res_age_groups` options in MIAMA-UI `default.R`.
Ages below 18 remain outside these adult groups; they are not folded into the
`18-29` category.

Other shared category contracts are:

- trip distance: `[0,2)`, `[2,5)`, `[5,10)`, `[10,30)`, and `30+` km
- weekly PA: `(-Inf,0]`, `(0,10]`, `(10,25]`, `(25,50]`, and `(50,Inf]`
  MMET-hours, labelled `sedentary`, `low`, `moderate`, `high`, and `very_high`
- sex/gender: source `female = 0/1`, presented as `male` / `female`
- trip purpose: `utilitarian` / `recreational`; `mixed` is a UI input option
  that resolves to proportions of those two categories
- source trip modes: NTS codes are mapped through the constants in
  `R/constants.R`; walking, cycling, public transport, and car/private motor are
  the broad presentation groups, with unrecognised values retained as `other`
- setup-mode UI IDs are `walk`, `bike`, `ebike`, and `pt`; HUB normalizes these
  to `walking`, `cycling`, `ebiking`, and `pt` at the API boundary

The UI schema is intentionally static, so changes to configured IDs or labels
must be mirrored in `MIAMA-UI/schemes/default.R`. Tests assert the current age
boundaries to prevent Tab 3 and Tab 5 from drifting apart again.

The PA cutoffs are provisional weekly MMET-hour cutoffs:
`(-Inf, 0]`, `(0, 10]`, `(10, 25]`, `(25, 50]`, and `(50, Inf]`. These should be
reviewed against the intended PA exposure definition before production use.

The slider redistribution helper uses exponential tilting for the five-category
numeric marginal. When the cf mean equals the reference mean, the category
shape is unchanged; shifting the mean moves mass across categories while
preserving a smooth version of the reference shape. The second slider sets the
first plotted variable's proportion: male for `pop`/`pa`, utilitarian for
`trips`.

#### Concise MIAMA-UI implementation

The recommended UI call is the exported stateless function. The R6 method
`hub$get_spread_bar_values()` delegates to the same function and is equivalent,
but no Hub state is needed for a slider-only recalculation.

Age/gender example for cycling (`mode_suffix = "bike"`):

```r
pop_cf_bars <- shiny::reactive({
  ref_bars <- mdata[["profile"]][["pop_spread_bars_ref_bike"]]$default_value
  cf_mean <- input[["pop_spread_age_mean_cf_bike"]]
  cf_prop <- input[["pop_spread_sex_prop_cf_bike"]]
  if (is.null(cf_mean)) {
    cf_mean <- mdata[["profile"]][["pop_spread_age_mean_ref_bike"]]$default_value
  }
  if (is.null(cf_prop)) {
    cf_prop <- mdata[["profile"]][["pop_spread_sex_prop_ref_bike"]]$default_value
  }

  MIAMAHUB::spread_bar_values_from_slider(
    ref_bars = ref_bars,
    cf_mean = cf_mean,
    cf_prop = cf_prop,
    topic = "pop"
  )
})

output[["pop_cf_plot_bike"]] <- plotly::renderPlotly({
  plot_dist_bars(pop_cf_bars())
})
```

The reference anchors are included in `ref_bars`, so UI does not need to pass
them separately. For manually constructed/legacy bar payloads, the optional
`ref_mean` and `ref_prop` arguments provide the same no-change check.

PA/gender uses the same pattern with these substitutions:

```r
ref_bars <- mdata[["profile"]][["pa_spread_bars_ref_bike"]]$default_value
cf_mean  <- input[["pop_spread_pa_mean_cf_bike"]]
cf_prop  <- input[["pop_spread_pa_sex_prop_cf_bike"]]

pa_cf_bars <- MIAMAHUB::spread_bar_values_from_slider(
  ref_bars = ref_bars,
  cf_mean = cf_mean,
  cf_prop = cf_prop,
  topic = "pa"
)
```

The exact plotting call depends on the UI-owned `plot_dist_bars()` signature.
HUB returns long-format data with `category`, `variable`, `percent`, and ordering
columns; UI should use `category_order` and `variable_order` rather than relying
on alphabetical order.

Counterfactual bar data are display-only and are not written to a profile
field. UI stores/submits only the mode-specific counterfactual mean and
proportion fields by setting their `input_value` and `is_filled` values. During
`Hub$build_results(profile)`, HUB calls the same redistribution function again,
uses the reconstructed bars as sampling constraints, and returns the compact
reference/counterfactual pairs at:

```r
result$spread_data$by_mode$bike$pop$ref
result$spread_data$by_mode$bike$pop$cf
result$spread_data$by_mode$bike$pa$ref
result$spread_data$by_mode$bike$pa$cf
```

If the current UI schema does not yet include one of these ref bar fields,
`build_reference_profile_defaults()` reports it in
`reference_defaults_report$skipped_fields`. That is expected during migration:
HUB can calculate the value before MIAMA-UI has a place to store/display it.

Applying these counterfactual spread percentages back to actual individual/trip
rows is separate from plotting. The UI does not submit cf bar payloads. During
counterfactual/result building, HUB reconstructs internal cf bars from the
mode-specific ref bar defaults plus submitted cf mean/proportion scalar fields;
the sampling code then treats those internal compact bar payloads as
higher-priority constraints:

- `pop_spread_bars_cf_*` supplies the cf age-category marginal and male
  proportion for mode-specific individual sampling.
- `pa_spread_bars_cf_*` supplies the cf PA-category marginal for
  mode-specific individual sampling, while its male/female split is available
  for display and reporting.
- `trips_spread_bars_cf_*` supplies the cf distance-category marginal and
  utilitarian proportion for mode-specific trip-shift sampling.
- If those compact payloads are absent, the older permissive hooks remain:
  `agecat_1_prop_cf` ... `agecat_5_prop_cf` and `distcat_1_prop_cf` ...
  `distcat_5_prop_cf`.

This is still a sampling approximation: candidate rows remain real rows, and the
category proportions are used as sampling weights rather than as exact integer
constraints. For large samples, weighted row sampling should usually move the
selected-row distribution close to the target. Exact quota sampling would only
become important if the UI/reporting contract requires the final sampled rows to
match each five-category marginal exactly, or if small samples produce visibly
unstable modal summaries.

Combined constraints can assign zero probability to most candidates in a small
sample. If fewer positive-weight candidates remain than requested rows, HUB
selects all positive-weight candidates first and samples only the unavoidable
remainder uniformly from the zero-weight pool. This prevents `sample()` failures
without discarding the constraints entirely. The affected change records
`sampling_fallback` or `trip_sampling_fallback`, and the counterfactual report
notes the number of relaxed rows.

Reference spread defaults also guard against sparse packaged samples. If a
mode-specific subset has no usable observations inside the configured
categories, HUB returns the filtered geography's overall population or trip
spread instead of zero bars and an `NA` slider mean. The extraction report
records this fallback. This keeps Tab 3/4 controls renderable while making clear
that the displayed distribution is not mode-specific in that edge case.

The counterfactual report records which sampling constraints were active for a
change in `sampling_constraints`, e.g. `sex`, `age`, `pa`, `distance`, or
`purpose`.

Remaining clarifications:

- Final age, PA, and trip-distance category definitions can now be changed in
  `cfg$spread`, but the production defaults still need review.
- The PA modal now has a real PA-value basis in HUB, but the exact PA exposure
  definition and cutoffs still need review.
- Field names for the UI schema are mode-specific in both
  `MIAMA-UI/schemes/default.R` and `MIAMA-UI/schemes/appraisal_inputs.R`.
  Current suffixes are `_walk`, `_bike`, `_ebike`, and `_pt`. Aggregate
  unsuffixed fields still exist as backward-compatible selected-mode summaries,
  but mode-specific modals should read/write the suffixed fields.

`trips_spread_util_prop_ref` classifies trips as utilitarian unless
`trip_purpose` looks recreational, leisure, sport, exercise, holiday, visit, or
social.

For plausibility checks against the real MIAMA-UI profile object, use
`inst/workflows/dev_profile_defaults_from_ui_default.R`. It loads
`MIAMA-UI/schemes/default.R`, fills minimal Tab 1 setup inputs, runs
`build_reference_profile_defaults()`, and shows fields populated in
`default_value`. From a shell, run workflow scripts with `Rscript --vanilla` to
avoid unrelated project startup/renv activation.

To test reference defaults against the full synthpop source without editing the
workflow script:

```sh
MIAMA_DEV_DATASET_SIZE=full \
MIAMA_DEV_GEO_ID=E08000025 \
Rscript --vanilla inst/workflows/dev_profile_defaults_from_ui_default.R
```

`build_reference_profile_defaults()` uses a synthpop-only reference-default path,
so full-data Tab 2/3/4 defaults do not require full HM outcomes.
`pop_total_ref_basic` and `pop_total_ref_advanced` remain the filtered synthetic-
population row count; `population_size` is overridden from the geography
lookup's scaled population where available.

`pop_total_cf_basic` and `pop_total_cf_advanced` are currently retained as
separate UI/profile values. They do not add or remove synthetic-population rows:
counterfactual user targets are validated against the fixed filtered reference
population until an explicit total-population scaling mechanism is introduced.

For England-wide schema default review values, use
`inst/workflows/dev_extract_england_schema_default_values.R`. It reads the full
local synthpop parquet sources and performs filtering and aggregation lazily in
Arrow. It writes two compact, package-bundled lookup files. This is an explicit
developer regeneration step; app startup and appraisal sessions only read the
resulting constants:

- `inst/extdata/data/lookup/england_mode_default_candidates.csv` contains the
  underlying England metrics by mode and measurement basis: trips per weekly
  user, trip distance, trip duration, speed, and weekly distance/duration per
  user.
- `inst/extdata/data/lookup/england_schema_default_candidates.csv` maps those
  metrics to current MIAMA-UI field names and labels each value as a review
  candidate, unavailable, or requiring a schema decision.

The canonical editable assumptions are
`default_trips_per_user_per_week_*` and `default_trip_distance_*`. One weekly
trip rate supports both conversions: `trips = users * rate` and
`users = trips / rate`; HUB does not store a separate inverse rate. For a trip
target, the implied weekly user count is retained in the counterfactual report;
trip rows remain the operative sampling unit. Basic trip sampling uses
`default_trip_distance_*` as its preferred mean while retaining the observed raw
distance of each selected reference trip. Advanced Tab 4 mean distance inputs
override that basic default. The Tab 2 user and trip modals intentionally edit
the same weekly-rate profile field because they expose the same assumption and
are not displayed simultaneously.

Installed-package code can resolve these files with
`system.file("extdata", "data", "lookup", ..., package = "MIAMAHUB")`.

Walking and cycling use their active-trip component columns. Car and public
transport use mutually exclusive numeric NTS main-mode codes and raw trip
distance/duration. The available `MainMode_B04` field does not separate e-bike
from bicycle, so e-bike candidates remain explicitly unavailable. The current
`distdur_default_*` field is also ambiguous because it is used for either
distance or duration; the output reports both candidates with
`needs_schema_split` rather than selecting one silently. Review these CSVs after
regeneration before promoting values into MIAMA-UI schema defaults.

The R6 `Hub` wrapper still exposes developer helpers
`build_reference_ui_values()` / `get_reference_ui_values()` /
`get_reference_ui_updates()` for inspection. New MIAMA-UI integration should use
`build_reference_profile_defaults()` as the single call for populating reference
fields. `get_population_size()` and `get_appraisal_summary_values()` are
convenience helpers for development and summary displays.

## Counterfactual data initialization and UI application

### Initialize counterfactual data
`init_counterfactual_data()` starts Step 6 by returning a 1:1 copy of filtered
`reference_data`. The first UI-driven implementation is
`apply_counterfactual_ui_values()`, which applies supported `_cf_` inputs to
that copy and adds a compact `counterfactual_report`.

### Users: derive counterfactual number of active mode users
The current implementation supports `users_count_cf_*` in the basic UI,
`pop_number_cf_*_basic` as the basic population-modal alternative, and
`pop_number_cf_*_advanced` in the advanced UI for walking and cycling. HUB uses
`ui_version` to select the applicable field family. These fields adjust the
number of individuals with positive mode-specific weekly activity while keeping
the individual population fixed:

- if the counterfactual target is larger than the current reference count,
  existing non-users are sampled as `new_users`
- if the target is smaller, existing users are sampled as `ex_users`
- new users receive mode activity values sampled from observed current users
- ex-users receive configured near-zero defaults, currently `0`
- returned individual data includes explicit `user_walk` / `user_bike`
  indicators and `cf_user_change`
- `mmets` is recalculated when present using HM constants:
  changes in `walktime_wkhr`, `cycletime_wkhr`, and `sport_wkhr` are converted
  to MMET deltas using factors 2.5, 5.8, and 7 respectively. These deltas are
  added to each individual's HM reference MMET value; unchanged individuals
  retain their reference exposure.
- if trip-level data is present, ex-users' active trips are shifted away from
  the active mode; new users trigger sampling of plausible non-active trips for
  mode shift where matching trip rows exist
- new-user trip shifts use the canonical mode-specific
  `default_trips_per_user_per_week_*` rate supplied by the appraisal profile.
  HUB calculates `new trips = new users * weekly trips per user`. If that
  assumption is absent, observed current-user trip counts remain the fallback.

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

For increases, Tab 4 may specify a small source-by-target diversion matrix using
`trips_diversion_car_perc_walk` and `trips_diversion_car_perc_bike`. Each value
is the expected percentage of mode-shift trips into that active target mode
whose reference mode was car. The residual percentage is sampled from all
other plausible non-target-mode trips. Distance, purpose, and car-source
weights are combined when candidates are sampled, so realized percentages are
approximate in finite samples. Each counterfactual change report records
`car_diversion_field`, the requested `car_diversion_percent`, and the observed
`realized_car_diversion_percent` among shifted trips.

Decreases do not delete utilitarian travel demand. Instead, sampled active trips
are shifted away from the active mode using the configured default destination,
currently `car`. This reverse-direction assumption is deliberately separate
from the car-to-active-mode percentages. A future full diversion matrix can add
other source-by-target fields without changing the target-specific field
convention.

Returned trip data includes explicit `trip_activemode`, `trip_utilitarian`,
`cf_trip_change`, `cf_mode_shift`, and `cf_induced` indicators. The change
report records actual `mode_shift_n` and `induced_n`, and
`counterfactual_report$comparison$changed_trip_rows` lists switched or induced
trip rows.

Active-trip changes feed the physical-activity exposure used by the health
model. For independent trip-count targets, HUB compares reference and
counterfactual active minutes by `(census_id, nts_tripid)`, converts the weekly
minute difference to hours, and applies the configured MMET intensity (walking
2.5; cycling 5.8). Induced trips contribute their full active duration. Trip
changes made only to mirror a new-user or ex-user status are excluded from this
trip component because changed individual weekly activity already represents
that exposure. The individual table exposes `cf_user_mmet_delta`,
`cf_trip_mmet_delta`, and `cf_mmet_delta`, together with the attribution
components `cf_mmet_delta_walking`, `cf_mmet_delta_cycling`, and
`cf_mmet_delta_other_activity`. The report summarizes these components under
`counterfactual_report$mmet_exposure`.

Advanced Tab 4 fields such as `trips_dist_value`, `trips_purpose_type`,
`trips_spread_mean_cf`, `trips_spread_util_prop_cf`, and the diversion
percentage fields are parsed and recorded. When compact cf spread bars are
available, distance-based candidate selection uses the configured five-category
distance distribution. Older direct category controls can still plug into the
`agecat_1_prop_cf` ... `agecat_5_prop_cf` and `distcat_1_prop_cf` ...
`distcat_5_prop_cf` hooks, or the corresponding `_perc_cf` fields.

Basic Tab 2 currently has two additional target forms that are not yet applied
to counterfactual rows:

- `mode_share_cf` can be implemented as a thin conversion step: multiply each
  requested share by the selected total-trip denominator, then pass the derived
  per-mode counts to the existing trip sampling path. It does not require a new
  sampling algorithm.
- `dist_dur_amount_cf_*` is an exposure target rather than a row-count target.
  Implementing it requires an allocation rule for the number of affected users
  or trips and the distance/time assigned to each. With trip data, a defensible
  first version can estimate a trip count from the target exposure and sampled
  mode-specific trip distance/duration, then reuse the existing constrained
  sampler. Individual-only appraisals need a separate activity-allocation rule.

The UI presents count, distance/duration, and mode share as alternative input
units, so no precedence rule is needed while exactly one branch is filled. The
distance/duration allocation rule still requires an explicit modelling decision
before it should affect health outcomes.

TODO: Important limitation: the draft trip handler currently changes physical rows,
not weighted `weight_tripXhh` totals. Existing shifted rows keep their existing
weights; induced trip rows receive `weight_tripXhh = 1` when that column exists.
This is useful for validating the manipulation flow, but the weighted-data
behavior needs to be resolved before using these trip changes for final impact
calculations.

Parameter naming follows the same distinction used elsewhere in the package:
`*_ref` values are measured from filtered reference data, while `*_default`
values come from configured constants. `miama_default_config()` records the
weekly activity timeframe, MMET intensities, and synthetic-population person
weight; `miama_counterfactual_defaults()` exposes the counterfactual subset.

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
adds `d_*` outcome columns. Counterfactual values are derived as `ref + delta`;
redundant `*_cf` columns are not materialized by default.

The death-share MMET lookup is much larger in memory than its parquet file.
HUB derives the required `(age1year, female, mr_decile, cycle)` scope from the
filtered people and cycle outcomes, applies Arrow filters before collection,
and removes residual Cartesian combinations in R. Sample-mode calculations
therefore do not materialize the complete England lookup table.

The low-level function returns `counterfactual_data` with:

- `health_outcomes`: full cycle-level reference and delta outcome table
- `counterfactual_health_report`: counts, MMET-delta summary, terminology, and
  summed outcome deltas
- `counterfactual_health_report$impact_overview`: compact outcome-level totals
  with `ref_total`, `cf_total`, `delta_total`, and `delta_per_1000_people`

Pass `include_cf_columns = TRUE` only for targeted model debugging that requires
explicit `*_cf` columns. The high-level `Hub$build_results()` method consumes
and releases `health_outcomes` after constructing compact `health_impacts` and
`results_data`; plots and exports do not require the raw cycle table afterward.

Future work: add `scheme_effect_duration = "shortterm"`.

## Results data and Tab 5 plots

`prepare_results_data()` prepares compact Step 8 outputs for MIAMA-UI. The
expensive reference, counterfactual, and HM steps run before this function;
interactive Tab 5 filters operate on compact result tables and do not rerun the
health model.

Cycle 0 is the without-scheme baseline state and is excluded from presented
impact totals and timelines. Cycle 1 is the first modelled year. Raw HM `d_*`
columns retain the technical convention `counterfactual - reference`; UI-facing
`prevented_value`, `prevented_per_100000`, and `percent_reduction` use
`reference - counterfactual`, so positive values consistently indicate a
health gain.

Expected health outcomes are scaled from synthetic rows to represented
residents using `cfg$population$person_weight` (default 20 for the 5% Census
synthetic population). The factor and source are recorded in `results_report`.
Packaged development samples remain partial subsets and therefore do not yield
location-wide absolute totals; use full location data for those totals.

### Tab 5 health outcome choices

The exported helper returns the stable configured choices without loading HM
data:

```r
outcome_options <- MIAMAHUB::get_health_outcome_options(hub_cfg)

# Named vector suitable for a Shiny checkbox/select control.
outcome_choices <- stats::setNames(
  outcome_options$outcome,
  outcome_options$label
)
default_outcomes <- outcome_options$outcome[outcome_options$default]
```

For development or source validation, pass a health data frame, Arrow dataset,
parquet directory, or character vector of column names. Parquet inspection
reads only the schema and does not collect rows:

```r
checked_options <- MIAMAHUB::get_health_outcome_options(
  cfg = hub_cfg,
  health_data = health_outcomes,
  available_only = TRUE
)
```

`available` confirms that all configured reference columns exist.
`delta_available` and `counterfactual_available` separately report whether the
matching `d_*` and `*_cf` columns have already been produced. The equivalent
R6 call is `hub$get_health_outcome_options()`.

### Shared UI option catalogues

Stable control IDs and labels live in `miama_default_config()`, rather than in
plot functions or server conditionals. The catalogues cover age groups, gender,
PA and trip-distance categories, trip purpose, setup/result modes, timeframes,
temporal and population aggregation, impact presentation, plot metric, and
annual versus cumulative timelines.

```r
MIAMAHUB::get_ui_options() # discover available catalogues
age_choices <- MIAMAHUB::get_ui_options("age_groups", hub_cfg)
metric_choices <- MIAMAHUB::get_ui_options("metric", hub_cfg)

result_options <- MIAMAHUB::get_results_options(hub_cfg)
result_options$assessment_period_years
result_options$impact_type
```

Each option table has `value`, `label`, `order`, and `default` columns. UI can
construct a named Shiny choices vector with
`setNames(options$value, options$label)`. Equivalent R6 methods are
`hub$get_ui_options()` and `hub$get_results_options()`.

The canonical assessment period is
`cfg$results$assessment_period_years` (currently 40 years), available through
`get_assessment_period(cfg)` or `hub$get_assessment_period()`. UI titles,
summary cards, total aggregation labels, AMAT exports, and report text should
all use this value rather than embedding a number.

### Tab 5 UI integration lifecycle

Tab 5 has one expensive calculation boundary and a separate lightweight
presentation layer. UI should call `Hub$build_results(profile)` once after all
counterfactual inputs have been submitted. That method builds counterfactual
rows, converts changed weekly activity to MMET exposure, applies the HM cycle
lookup, and prepares compact result tables:

```r
mdata[["result"]] <- mdata[["hub"]]$build_results(
  profile = mdata[["profile"]],
  seed = 1L
)
```

Do not call `build_results()` again when a user changes only a Tab 5 display
control. Keep `mdata[["result"]]$results_data` in session state and filter that
compact object reactively. The large synthetic-population and HM calculations
do not need to rerun.

The primary returned objects are:

| Object | Purpose |
|---|---|
| `result$highlights` | Three-row, display-ready headline table for the Highlights Card. |
| `result$results_data$headline_metrics` | Internal named values supporting the three unfiltered assessment-period highlights. |
| `result$results_data$results_table` | Table aggregated according to the profile's initial Tab 5 selections. Useful for exports and initial tables. |
| `result$plot_data$health_cube` | Canonical interactive health source, grouped by outcome, cycle, age group, gender, and mode. It contains `all_modes` rows and attributed mode rows. |
| `result$plot_data$mode_attribution` | Compact audit table of mode-specific MMET changes and their shares of the net MMET change. |
| `result$plot_data$trip_mode_distribution` | Reference/counterfactual weighted trip totals and shares by broad mode. |
| `result$plot_data$spreads` | Reference/counterfactual spread payloads described in the Tab 3/4 section. |

`result$plot_data` and `result$results_data$plot_data` refer to the same compact
plot payload. HUB plotting and filtering functions expect the enclosing
`result$results_data` object, not the bare `health_cube` data frame.

#### Headline health outcomes

After `build_results()`, UI can populate the three highlight figures with one
method call:

```r
highlights <- mdata[["hub"]]$get_results_highlights()
# The same table is returned directly as mdata[["result"]]$highlights.
# Stateless equivalent: get_results_highlights(mdata[["result"]]$results_data)
```

The returned rows are `premature_deaths_prevented`, `life_years_saved`, and
`disease_cases_prevented`, with display labels, units, assessment period, and
availability status. These totals intentionally ignore interactive Tab 5
filters. The disease total sums each underlying HM incidence stream once;
presentation composites such as CVD/all cancers and their subtypes are not
double-counted. It is a total of prevented disease events, not unique people.

#### Tab 5 profile fields and function arguments

| Profile/UI field | HUB plotting argument or behavior |
|---|---|
| `res_outcomes` | `outcomes`; filters health outcome IDs. |
| `res_age_groups` | `age_groups`; filters the five result age strata. |
| `res_gender` | `gender`; filters `male` / `female`. |
| `res_temp_aggregation` | Selects total versus timeline presentation. `res_aggregation` is accepted as a legacy/internal alias. |
| `res_pop_aggregation` | Selects `group_by = "none"`, `"age_group"`, `"gender"`, or `"mode"`. |
| `res_impact_type` | `impact_type = "attributable"` or `"cf_vs_ref"`. |
| `res_modes_filter` | `modes` for health and trip plots. `all_modes` selects canonical combined health impacts; `walking`, `cycling`, and other attributed components select the corresponding health allocation. |

Two useful presentation choices are not currently separate profile fields,
but their canonical values and labels are exposed by `get_ui_options()`:

- `metric`: `"prevented"`, `"prevented_per_100000"`, or
  `"percent_reduction"`; each plot function has a documented default.
- `timeline_type`: `"cumulative"` (default in the timeline plot) or
  `"annual"`. A future UI toggle can pass this directly without rebuilding
  results.

The current `res_impact_type` UI label still describes attributable cases as
counterfactual minus reference. Internally, raw `delta_value` retains that
technical `cf - ref` convention, but all user-facing attributable metrics use
`ref - cf`: positive `prevented_value`, `prevented_per_100000`, and
`percent_reduction` mean a health gain. UI labels should follow the latter
presentation convention.

#### Recommended reactive plot calls

For a simple outcome overview, call the HUB plotting function inside
`renderPlot()`. It returns a ggplot object:

```r
output[["results_health_overview"]] <- shiny::renderPlot({
  shiny::req(mdata[["result"]])

  MIAMAHUB::results_plot_health_overview(
    results_data = mdata[["result"]]$results_data,
    outcomes = input[["res_outcomes"]],
    age_groups = input[["res_age_groups"]],
    gender = input[["res_gender"]],
    modes = input[["res_modes_filter"]],
    impact_type = input[["res_impact_type"]],
    metric = "percent_reduction"
  )
})
```

For the primary cumulative timeline:

```r
output[["results_health_timeline"]] <- shiny::renderPlot({
  shiny::req(mdata[["result"]])

  MIAMAHUB::results_plot_health_timeline(
    results_data = mdata[["result"]]$results_data,
    outcomes = input[["res_outcomes"]],
    age_groups = input[["res_age_groups"]],
    gender = input[["res_gender"]],
    modes = input[["res_modes_filter"]],
    impact_type = "attributable",
    metric = "prevented_per_100000",
    timeline_type = "cumulative"
  )
})
```

For advanced age or gender views, use the detailed plot only when
`res_pop_aggregation` requests a stratum; use the overview plot for `"total"`:

```r
shiny::req(input[["res_pop_aggregation"]] %in% c("age_group", "gender"))
group_by <- switch(
  input[["res_pop_aggregation"]],
  age_group = "age_group",
  gender = "gender"
)

MIAMAHUB::results_plot_health_impacts(
  results_data = mdata[["result"]]$results_data,
  outcomes = input[["res_outcomes"]],
  age_groups = input[["res_age_groups"]],
  gender = input[["res_gender"]],
  modes = input[["res_modes_filter"]],
  group_by = group_by,
  metric = "prevented_per_100000"
)
```

For weighted trip-mode shares:

```r
MIAMAHUB::results_plot_trip_mode_distribution(
  results_data = mdata[["result"]]$results_data,
  modes = input[["res_modes_filter"]],
  value = "proportion"
)
```

Use `plotly::ggplotly(plot)` if Tab 5 requires Plotly interaction. HUB does not
require Plotly and returns ordinary ggplot objects so UI controls the rendering
technology.

#### UI-owned plotting alternative

MIAMA-UI may reproduce the plots rather than call HUB's ggplot functions. In
that case, use the exported filtering function so aggregation and sign
conventions remain identical:

```r
plot_df <- MIAMAHUB::results_filter_health_data(
  results_data = mdata[["result"]]$results_data,
  outcomes = input[["res_outcomes"]],
  age_groups = input[["res_age_groups"]],
  gender = input[["res_gender"]],
  modes = input[["res_modes_filter"]],
  aggregation = "timeline",
  group_by = "outcome",
  timeline_type = "cumulative"
)
```

The returned data include `ref_value`, `cf_value`, internal `delta_value`,
`population`, `prevented_value`, `prevented_per_100000`,
`percent_reduction`, and display labels. UI should plot the benefit-oriented
columns unless it is explicitly presenting both reference and counterfactual
levels.

Plot/filter calls do not modify the profile and return no profile fields. The
UI may store Tab 5 selections in their existing profile `input_value` fields,
but changing those display controls does not require a HUB round trip or a new
health-model run.

Mode selections have two aggregation behaviors. For `group_by = "mode"`, HUB
returns one attributed series per selected mode; `modes = NULL` or
`modes = "all_modes"` displays every available attributed mode separately. For
outcome, age, gender, and timeline views, multiple selected modes are summed
into one `selected_modes` series; selecting one mode returns that mode alone.
Leaving `modes = NULL` in those combined views uses the canonical `all_modes`
health result.

The central UI plotting contract is returned directly by `Hub$build_results()`
as `result$plot_data` and is also available as
`result$results_data$plot_data`. Both names refer to the same compact object in
the R session; HUB does not recalculate or copy the underlying values.

The payload intentionally contains shared source tables rather than one data
frame per plot:

- `health_cube` is aggregated by outcome, model cycle, age group, gender, and
  mode. It contains canonical `all_modes` rows plus mode-attributed delta rows
  and is the comprehensive source for the health overview, timeline, age,
  gender, and mode plots.
- `mode_attribution` is the compact audit table behind the mode split. It
  reports changed individuals, MMET deltas, and net MMET shares by mode.
- `trip_mode_distribution` contains reference and counterfactual weighted trip
  totals and proportions for Walking, Cycling, Public transport, Driving, and
  Other. It remains separate because its rows represent travel modes and
  scenarios, whereas `health_cube` rows represent health-model strata.
- `spreads` contains compact reference/counterfactual spread-bar data produced
  by `build_results()` for the population, trip, and physical-activity spread
  views.
- `health_overview` and `health_timeline` remain convenience tables for current
  request defaults and exports. UI does not need them for interactive plotting
  when it uses `health_cube`.

Combining health and trip data into one data frame would create sparse columns
and ambiguous units. Producing one table per plot would repeat the same health
values and allow the views to drift apart. Two canonical analytical tables,
plus the distinct spread payload, preserve each table's grain while supporting
all current Tab 5 interactions.

```r
result <- hub$build_results(profile)

# Direct reactive filtering in UI.
health_cube <- result$plot_data$health_cube
trip_modes <- result$plot_data$trip_mode_distribution

# Or use HUB's filter and plotting functions against the enclosing object.
health_by_age <- results_filter_health_data(
  result$results_data,
  outcomes = c("mortality", "ihd", "stroke"),
  modes = "all_modes",
  aggregation = "total",
  group_by = "age_group"
)
plot <- results_plot_health_impacts(
  result$results_data,
  outcomes = c("mortality", "ihd", "stroke"),
  modes = "all_modes",
  group_by = "age_group"
)

# Allocate combined health deltas to the active modes that supplied the MMET
# change. This contains attributable changes, not mode-specific reference and
# counterfactual disease totals.
plot_by_mode <- results_plot_health_impacts(
  result$results_data,
  outcomes = c("mortality", "ihd", "stroke"),
  modes = c("walking", "cycling"),
  group_by = "mode",
  metric = "prevented"
)
```

#### Mode attribution contract

The health model is run once for the combined counterfactual exposure. HUB then
allocates each individual's resulting health delta using that individual's
signed MMET components: `mode share = mode MMET delta / total MMET delta` and
`mode health delta = combined health delta * mode share`. Walking, cycling,
other activity, and any numerical residual are retained so their attributed
health deltas reconcile exactly to the canonical `all_modes` result.

This is an attribution of the combined model result, not a separate health-model
run for each mode. Shares can be negative or greater than one when one mode
offsets another. Mode rows therefore contain attributable deltas only;
`ref_value` and `cf_value` are `NA`. Direct reference-versus-counterfactual
totals and percentage reductions require the canonical `all_modes` rows.
Headline figures and AMAT exports also remain canonical all-mode totals to avoid
double counting.

For a lean Shiny reactive, UI can retain `result$results_data` (or only
`result$plot_data` when it performs its own filtering) instead of retaining the
large `reference_data` and `counterfactual_data` objects returned for current
development inspection.

### Tab 5 result exports

The export buttons currently drafted in MIAMA-UI are presentation stubs. HUB
now provides one filtered export bundle and file writers so UI does not need to
reimplement result semantics. Build the bundle after `build_results()` and
whenever a Tab 5 filter changes; this filters compact result data and does not
rerun the counterfactual or health model:

```r
results_exports <- hub$build_results_exports(
  outcomes = input[["res_outcomes"]],
  age_groups = input[["res_age_groups"]],
  gender = input[["res_gender"]],
  modes = input[["res_modes_filter"]],
  aggregation = input[["res_temp_aggregation"]],
  group_by = switch(
    input[["res_pop_aggregation"]],
    age_group = "age_group",
    gender = "gender",
    "outcome"
  ),
  timeline_type = "cumulative",
  impact_type = input[["res_impact_type"]],
  metric = "prevented_per_100000"
)
```

The equivalent stateless function is `prepare_results_exports(results_data,
profile, cfg, ...)`. Its return value contains:

| Object | Draft export content |
|---|---|
| `metadata` | Appraisal name, geography, modes, UI version, population scaling, and result conventions. |
| `filters` | Exact Tab 5 selections applied to every exported product. |
| `headline_metrics` | Mortality, disease, and cumulative life-year headline fields. |
| `results_table` | The currently filtered/grouped health result table. |
| `timeline_annual` / `timeline_cumulative` | Both timeline representations, independent of the displayed table. |
| `trip_mode_distribution` | Reference/counterfactual weighted trips and mode shares. |
| `assumptions` | Sign conventions, population scaling, cycle handling, and current limitations. |
| `amat_inputs` | Explicitly provisional field/value mapping pending the agreed AMAT schema. |
| `amat_health_timeline` | Annual ref/cf values, technical differences, benefit-oriented differences, and cumulative differences for deaths, diseases, LY, and HLY. |
| `amat_health_summary` | Final cumulative row for every AMAT health measure. |
| `report` | Report-ready title, summary text, methods, metadata, tables, and assumptions. |
| `plots` | Six ggplot objects built from the same filters, including a mode-attributed health plot. |

Available writers are:

```r
write_results_csv(results_exports, "results.csv")
write_results_xlsx(results_exports, "results.xlsx")
write_results_plot_pngs(results_exports, "plots", dpi = 300)
write_results_plots_zip(results_exports, "plots.zip", dpi = 300)
write_results_amat_csv(results_exports, "amat_health_timeline_DRAFT.csv")
write_results_report(results_exports, "report.md", format = "markdown")
write_results_report(results_exports, "report.docx", format = "docx")
write_results_report(results_exports, "report.pdf", format = "pdf")
```

The Excel workbook contains separate sheets for the displayed results,
headline metrics, annual and cumulative timelines, trip modes, metadata,
filters, assumptions, AMAT metadata, and AMAT health timeline/summary sheets.
The plot package contains 300-dpi PNG
files for health overview, health timeline, health by age, health by gender,
and trip mode distribution, plus `plot_manifest.csv`.

Word report generation requires Pandoc. PDF additionally requires a working
PDF engine/LaTeX installation in the deployment environment; UI should disable
or handle that download gracefully until Connect has been verified. The first
report draft includes pre-filled text and tables; plot embedding and final
branding remain report-template work.

The AMAT health timeline uses the canonical assessment period configured at
`cfg$results$assessment_period_years` (currently 40 years).
It implements the MIAMA-HM definitions `LY[t] = 1 - cumulative deaths[t]` and
`HLY[t] = 1 - cumulative unhealth incidence[t]`. For every measure it exposes
both `annual_delta_cf_minus_ref` and `cumulative_delta_cf_minus_ref`, plus
benefit-oriented columns where positive consistently means improvement. For
deaths and diseases, benefit is `ref - cf`; for LY and HLY it is `cf - ref`.
HALYs are not yet available because their calculation additionally requires
disease prevalence and disability weights. AMAT field names and the required
disease subset remain provisional until the formal specification is supplied.

The same health contract can be prepared without the rest of the export bundle:

```r
amat <- prepare_results_amat_outputs(
  result$results_data,
  horizon_years = 40
)
amat$timeline
amat$summary
```

Minimal Shiny handlers can delegate directly to HUB:

```r
output[["download_results_csv"]] <- shiny::downloadHandler(
  filename = function() "miama-results.csv",
  content = function(file) write_results_csv(results_exports(), file)
)

output[["download_results_xlsx"]] <- shiny::downloadHandler(
  filename = function() "miama-results.xlsx",
  content = function(file) write_results_xlsx(results_exports(), file)
)

output[["download_plots"]] <- shiny::downloadHandler(
  filename = function() "miama-plots.zip",
  content = function(file) write_results_plots_zip(results_exports(), file)
)

output[["download_amat"]] <- shiny::downloadHandler(
  filename = function() "miama-amat-inputs-DRAFT.csv",
  content = function(file) write_results_amat_csv(results_exports(), file)
)

output[["download_report_docx"]] <- shiny::downloadHandler(
  filename = function() "miama-report.docx",
  content = function(file) write_results_report(results_exports(), file, "docx")
)
```

Run [inst/workflows/dev_results_exports.R](inst/workflows/dev_results_exports.R)
after Step 8 of the main development workflow to generate and inspect all draft
artifacts locally.

`results_filter_health_data()` is the non-plot interface UI can use to obtain a
filtered data frame. Its arguments mirror the Tab 5 controls:

```r
plot_df <- results_filter_health_data(
  results_data,
  outcomes = c("mortality", "ihd", "stroke"),
  age_groups = c("age_40_49", "age_50_59", "age_60_plus"),
  gender = c("male", "female"),
  modes = "all_modes",
  aggregation = "timeline",
  group_by = "age_group",
  timeline_type = "cumulative"
)
```

Development plotting functions consume the same compact data. The intended
Tab 5 structure is deliberately limited to two core and four advanced views:

- Core 1, `results_plot_health_overview()`: cumulative health impact by outcome,
  shown as prevented outcomes, prevented outcomes per 100,000 residents, or
  percentage reduction. Direct reference/counterfactual totals remain an
  optional diagnostic because their lines often overlap at realistic effects.
- Core 2, `results_plot_health_timeline()`: cumulative impact from cycle 1 by
  default, with annual impact available through `timeline_type = "annual"`.
- Advanced 1 and 2, `results_plot_health_impacts()`: cumulative health impacts
  split by age group or by gender and faceted by outcome.
- Advanced 3, `results_plot_health_impacts(group_by = "mode")`: combined
  health deltas attributed to walking, cycling, and other activity according to
  their individual-level MMET contributions.
- Advanced 4, `results_plot_trip_mode_distribution()`: reference and
  counterfactual weighted trip shares or weekly weighted totals by mode.

Each function provides data-aware defaults for `title`, `subtitle`, `caption`,
`x_label`, and `y_label`; callers can override any of them. `NULL` uses the
semantic default and `NA_character_` suppresses the label. Units are selected
from the plot request and data: health plots distinguish deaths, disease cases,
and mixed health outcomes; total plots are cumulative across the available
model cycles; timeline plots are annual or cumulative according to
`timeline_type`; trip shares are displayed as
percentages; and trip totals are weighted trips per reference week. Label
overrides change presentation only and never transform the numeric values.

For attributable health plots, `prevented_value = reference - counterfactual`
and `percent_reduction = 100 * (reference - counterfactual) / reference`.
`prevented_per_100000` divides prevented outcomes by the represented population.
Positive values therefore indicate a health gain. Plot captions state this sign
convention and define reference as without scheme and counterfactual as with
scheme.

These ggplot functions currently live in HUB so the result contract and example
presentation can be developed together. MIAMA-UI can call them directly or
reproduce their styling from the returned data frames. Omit `modes`, or use
`modes = "all_modes"`, for the canonical combined health result. Pass
`modes = c("walking", "cycling")` for attributed health deltas. Because mode
rows do not have separate reference denominators, mode-specific requests use
prevented counts or prevented counts per 100,000 rather than direct scenario
totals or percentage reduction.

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
`data/lookup/geo_options.rds`. For package deployments, a copy of the
full-derived lookup is stored under `inst/extdata/data/lookup/geo_options.rds`.

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

Dataset scope is a runtime/deployment setting, not an appraisal input. Set it
before creating the HUB configuration:

```r
# Project .Renviron (restart R after editing)
MIAMA_DATASET_SIZE=sample
```

`MIAMA_DATASET_SIZE=sample` is the default. It uses the packaged synthetic
population sample and packaged HM sample/death-share artifacts, so a developer
does not need a local MIAMA-HM checkout to test the complete UI workflow. Sample
mode deliberately ignores `MIAMA_DATA_ROOT`; this prevents a full external
synthpop from being combined with packaged sample HM outcomes. Explicit
`cfg$sources` overrides remain available for controlled development tests.

Full-data testing requires external data that are deliberately excluded from
the package and git repository:

```r
MIAMA_DATASET_SIZE=full
MIAMA_DATA_ROOT=/absolute/path/to/miama-runtime-data
MIAMA_HM_ROOT=/absolute/path/to/MIAMA-HM
```

`MIAMA_DATA_ROOT` must contain the full synthpop parquet directories under
`synthetic_pop/`. `MIAMA_HM_ROOT` must contain
`health_data/processed/sp_cycle_outcomes_death_share/`. The common death-share
MMET lookup is packaged with HUB and may also be supplied from MIAMA-HM. Setting
a root only points HUB at existing files; it does not download them.

The UI should construct its shared config once with
`MIAMAHUB::miama_default_config()` and should not subsequently hard-code
`cfg$workflow$dataset_size`. This lets local `.Renviron` files and deployment
environment variables select sample or full data without exposing that
operational choice in the appraisal profile.

Development scripts that intentionally choose the scope should pass it while
constructing the configuration, because source paths are resolved at that time:

```r
cfg <- MIAMAHUB::miama_default_config(dataset_size = "sample")
```

For local development, large data files must not be tracked in git or included
in package builds. Set `MIAMA_DATA_ROOT` to an external/local data directory.
The legacy project-root `data/` path is ignored by both git and `R CMD build`,
but is no longer selected implicitly.

`inst/extdata/` is different: files under this directory are bundled when
MIAMA-HUB is installed as an R package. To keep the package publishable, it
contains small runtime/sample data, plus small lookup artifacts that the UI can
load without full data access.

Current expected layout:

- full synthetic population files live under
  `$MIAMA_DATA_ROOT/synthetic_pop/`
- packaged sample synthetic population files live in
  `MIAMA-HUB/inst/extdata/data/synthetic_pop/`
- the packaged `geo_options.rds` is intentionally full-derived because it is
  small and needed for complete UI geography dropdowns and population labels
- packaged HM sample processed outputs live under
  `MIAMA-HUB/inst/extdata/data/health_data/`
- packaged HM sample results support includes
  `sp_cycle_outcomes_sample_death_share/` and
  `mmet_d_cycle_lookup_death_share/`
- full HM processed outputs are read from `MIAMA-HM` via `MIAMA_HM_ROOT`

HM outcome loading follows this hierarchy:

1. cached RDS files in `cfg$cache$dir` when cache is enabled and no
   census-id prefilter is requested
2. packaged sample parquet directories such as
   `inst/extdata/data/health_data/sp_overall_outcomes_sample/`
3. external MIAMA-HM parquet directories under `MIAMA_HM_ROOT/health_data/processed/`

Reference and counterfactual individual/trip data use the HM `overall` table,
which has one row per individual. A timeline results request does not join the
cycle table to trips: death-share cycle outcomes are loaded and filtered by
`census_id` only after counterfactual MMET exposure has been created. This
avoids an invalid cycle-by-trip row expansion.

During `Hub$build_results()`, source and pre-filter row tables are released once
the filtered reference and counterfactual objects have been built. The
death-share lookup is evaluated in bounded chunks with MMET-band overlap inside
the join, preventing full-data scenarios from materializing all lookup bands
for every changed person-cycle row.

The cycle calculation retains reference outcome columns plus `d_* = cf - ref`
columns while it runs. Redundant `*_cf` columns are disabled by default because
all consumers derive them as `ref + d_*`. After result preparation, the full
person-cycle table is removed from `counterfactual_data`; `health_impacts`
retains its row/column/size audit and health report. Compact health cubes, AMAT
timelines, and headline metrics live only in `results_data`, avoiding duplicate
UI/export payloads. This keeps plot and export functionality while substantially
reducing per-session retained memory. Low-level calls to
`apply_counterfactual_health_outcomes()` still return the cycle table for model
development; pass `include_cf_columns = TRUE` only when explicit convenience
columns are needed.

### Profiling full-data API performance

[inst/workflows/dev_profile_api_performance.R](inst/workflows/dev_profile_api_performance.R)
profiles the two UI-facing data calls against the real MIAMA-UI default profile.
It records stage elapsed time, process RSS at API boundaries, retained R6 object
sizes, and `Rprof` call-stack summaries. Run sample mode first, then a full-data
LAD after configuring `MIAMA_DATA_ROOT` and `MIAMA_HM_ROOT`:

```sh
Rscript --no-init-file inst/workflows/dev_profile_api_performance.R

MIAMA_PROFILE_DATASET_SIZE=full \
MIAMA_PROFILE_GEO_LEVEL=lad \
MIAMA_PROFILE_GEO_ID=E08000025 \
Rscript --no-init-file inst/workflows/dev_profile_api_performance.R
```

Set `MIAMA_PROFILE_OUTPUT_DIR` to retain reports at a specific path. The script
applies an approximately 10% increase in walking and cycling trip rows so the
counterfactual and health stages do real work. `stage_timings.csv` identifies
the expensive API stage, `hub_state_sizes.csv` identifies retained large
objects, and `rprof_by_total.csv` / `rprof_by_self.csv` identify expensive call
stacks. RSS is sampled at stage boundaries; it should not be interpreted as an
exact transient peak.
`table_inventory.csv` adds row counts, column counts, and retained sizes for the
major person, trip, health-cycle, and result tables.

Without `MIAMA_DATA_ROOT`, HUB deliberately uses the packaged sample data.
`dataset_size = "full"` fails clearly when only packaged sample synthpop data
are available. Callers can also provide explicit `cfg$sources` paths. Longer-
term external storage may be a VPS or another managed data service.

`inst/extdata/data/manifest.csv` inventories every packaged artifact with its
source, source version, purpose, row count, schema, and checksum. Regenerate it
after intentional packaged-data changes with:

```sh
Rscript --vanilla inst/workflows/dev_build_packaged_data_manifest.R
```

`source_version = "unrecorded"` identifies artifacts for which an authoritative
upstream release identifier still needs to be supplied; it is not silently
treated as a known version.
