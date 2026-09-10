# Appraisal assumptions: proposed fields, rules and UI dependencies

Status: design catalogue, 2026-09-09. The core contract is now implemented;
see [the API handoff](appraisal_assumptions_api.md) for the exact supported
fields, calls and remaining limitations. Proposed policy extensions below are
not all separate editable fields. Based on HUB dev,
the assumptions branch and UI dev. No saved-appraisal compatibility is required:
rename fields consistently across HUB and UI; do not retain aliases or migrations.

## 1. One appraisal record

`schemes/default.R` declares the appraisal schema. The instantiated profile is
the appraisal record: submitted inputs, effective assumption defaults, overrides,
provenance and necessary reproducibility metadata live there.

Config supplies initial defaults, not a second authority during calculation.
Resolve missing values into the profile before using them. Reloading a completed
profile must not replace its saved values with today's config or source summaries.
Temporary widget values, caches and deterministically derived calculation arrays
may exist outside the profile; they must not supply otherwise unrecorded decisions.

## 2. What each tab establishes

### Tab 2: complete the picture of activity and people

For each selected mode and scenario, establish:

- Total active-travel time, in minutes per reference week.
- Mode-user count: people undertaking that mode.
- Total assessed population, including non-users, shared across overlapping modes.
- Trip count, as an intermediate quantity needed by the trip sampler.

The number receiving *additional* activity is a further allocation quantity. It
is neither total population nor necessarily all mode users. Keep all three
person-count meanings distinct. Walking and cycling users may overlap.

These are provided targets or initial estimates, not four independent targets
to force simultaneously. Current HUB converts distance/duration to trip-row
targets; exact realized distance/minute calibration is not implied by this draft.

### Tabs 3 and 4: define scope and selection preferences

- Tab 3 basic refinements determine person scope; advanced refinements specify
  how selected people should be distributed across the chosen characteristics.
- Tab 4 basic refinements determine trip scope; advanced refinements specify
  donor-trip selection preferences and distributions.
- A distribution entered by the user is an explicit refinement, not an additional
  assumption. A default mechanism filling a missing decision is an assumption.
- Authoritative Tab 2 trip totals remain fixed through Tab 3. After Tab 3,
  accepted person counts remain fixed through Tab 4. Do not feed derived values
  backwards and silently replace those contracts.

## 3. Naming and value semantics

Use `assump_*` for model/completion parameters, including parameters exposed by
a slider or modal. Editing an assumption does not change its identity or ID.
Use ordinary domain IDs for supplied quantities, such as `users_count_ref_walk`.

`default_value` is a property of either kind of field: it is the suggested value,
not a separate class of parameter. Retire the ambiguous `default_*` prefixes.

Each assumption has `default_value`, `input_value`, `is_filled`, `unit` and
`additional_data`. Effective value is the valid `input_value` when filled,
otherwise the populated `default_value`. Explicitly saving the same value as a
default still counts as an explicit edit; equality is not an override detector.

`additional_data` holds origin, source/version identifiers and derivation details.
It must distinguish an observed value, proxy, fixed fallback and derived quantity.
Avoid a duplicate writable `effective_value`: it would create synchronization
problems. The getter can expose a calculated display value without persisting it.

## 4. Canonical parameter catalogue

`[mode]` expands to `walk`, `bike`, `ebike`, `pt`. This is a proposed naming
contract, not a list of fields already implemented in dev.

| Proposed field | Current location/name | Meaning and card rule |
| --- | --- | --- |
| `assump_trips_per_user_per_week_[mode]` | `default_trips_per_user_per_week_[mode]` | Weekly frequency among mode users; show when needed to connect trips and users, unless collected in the active input modal. |
| `assump_trip_distance_km_[mode]` | `default_trip_distance_[mode]` | Mean active distance per trip; show when used to complete volume/exposure and not superseded by an explicit trip-distance refinement. |
| `assump_trip_duration_min_[mode]` | `default_trip_duration_[mode]` on assumptions branch; absent in dev schema | Mean active minutes per trip; use on duration-based completion routes. Do not offer it as independent of distance and speed. |
| `assump_trip_speed_kmh_[mode]` | `assump_trip_speed_[mode]` | Fixed-default active speed; show only when distance/time conversion uses it. For PT, this is access-walking speed, not vehicle speed. |
| `assump_new_user_percent` | `pop_new_current_perc` | Preferred new-user share of the affected-person allocation; show when that allocation uses it and it is not already collected by an active control. Explicit user targets take precedence. Not a percent increase in all users. |
| `assump_induced_trips_percent` | `induced_trips_percent` | Newly induced share of additional active trips; complement is shifted trips. Independent of the new-user share and of purpose. |
| `assump_trip_source_shares_[mode]` | `trips_diversion_sources_[mode]`, plus config fallbacks | Source-mode shares for trips switching *to* this mode. Store one distribution per target mode; show when used and not already collected by its diversion modal. Not Tab 2 mode shares. |
| `assump_new_user_activity_pattern` | Existing donor-pattern behavior; not a uniform profile field | Named policy for assigning activity to new users. Initially observed donor patterns; a future lower-quartile alternative is not implemented. Show a short read-only description while there is only one policy. |
| `assump_mmet_per_hour_[mode]` | `cfg$physical_activity$mmet_per_hour` / constants | Marginal activity intensity applied to active hours. Include as a read-only exposure assumption when used; no newly editable physiology control is implied. |

The first seven families are the initial UI/HUB contract. The final two require
an audit of every consumer before wiring them as canonical calculation inputs.
Do not claim that adding schema entries alone activates the behavior.

### Population estimation and proxy parameters

There are additional assumptions outside the four original travel quantities:

- Total population cannot be inferred from percentages alone. Keep the actual
  supplied/estimated totals in existing `pop_total_*` fields and record how the
  estimate was obtained. An unprovided total using source population is a visible
  assumption, not a hidden denominator.
- If estimating total population uses source mode-user prevalence or a multi-mode
  combination rule, record the effective rates and the named rule in the profile.
  Do not invent a second total-population estimator in the assumptions module.
  Proposed metadata field: `appraisal_population_estimation` (method and inputs).
- E-bike proxy mode and effective distance/duration factors must be recorded in
  profile metadata when used to initialize assumptions. Proposed field:
  `assump_ebike_proxy`, with donor mode and factors in its structured value.
  The resulting effective means remain in the canonical per-mode fields; do not
  multiply the proxy factors again during calculation.
- For PT, distinguish active access-leg distances/minutes from total vehicle
  journey distances/minutes. The canonical per-mode fields refer to walking
  access. Any rule converting vehicle travel into access activity must be an
  explicit recorded parameter, not inferred from the label "PT".
- Remove `distdur_default_*`: these placeholders are not a sound population
  contract. Do not leave an editable value presented as functional without a
  calculation consumer. Car distance/speed fields also need a consumer audit;
  do not add them to the active-mode cards merely because they exist in schema.

## 5. Tab 2 dependency rules

Normalize units/timeframes before applying these illustrative completion
identities. Let Q = weekly trips, U = mode users, F = trips/user/week,
D = km/trip, S = km/hour, T = minutes/trip and V = total active minutes/week.
Use T = 60 D / S or D = T S / 60, never three independently editable values.

| Active input path | Supplied information | Missing information / assumptions |
| --- | --- | --- |
| Users | U for REF and CF | F estimates Q; D and S estimate T, then V = Q T. Observed donor variation is retained in sampling; these means are completion assumptions. |
| Trips | Q for REF and CF | D and S estimate V; F helps estimate REF users and CF affected-person allocation. |
| Total distance | Weekly km | S estimates V; D estimates Q; F helps estimate REF users and CF allocation. |
| Total duration | Weekly active minutes | V is supplied; T estimates Q and F helps estimate users/allocation. S is not required to calculate supplied minutes, but may be needed later for trip construction/conversion. |
| Mode shares of trips | Shares plus total Q | Per-mode Q = share x total; continue as trips. |
| Mode shares of distance | Shares plus total distance | Per-mode distance = share x total; continue as distance, respecting the PT access distinction. |
| Mode shares of duration | Shares plus total duration | Per-mode minutes = share x total; continue as duration, respecting the PT access distinction. |
| Per-person distance/duration | An average plus an assessed population denominator | Resolve N first, then multiply by N and use the corresponding total route. Current HUB's denominator is assessed people, not mode users. |

Important qualifications:

- U approximately equals Q/F for a REF completion estimate, not a mandatory CF
  identity. Increasing trips may principally increase activity among existing
  users. The new-user allocation rule and accepted explicit user counts govern CF.
- Mode share without a total cannot determine an absolute volume or population.
  If the source supplies the denominator, that assumption must be visible in the
  input modal or card, and persisted in the denominator field.
- Explicit population input can remove an estimation dependency. It does not
  necessarily remove frequency from later sampling if that step still uses it.
- Show assumptions for their actual downstream use, not merely because a path
  name mentions distance. A duration input does not automatically require speed
  for health exposure; the current implementation must be checked for uses of
  speed in sampling before deciding it is entirely inactive.
- For REF = 0 and positive CF, population fallback remains necessary; neither
  division by a zero REF count nor zero mode-user prevalence is a valid estimate.

## 6. Tabs 3 and 4: what belongs in the cards?

| Setting | How to present it |
| --- | --- |
| Population/trip counts, percentages and selected categories | Explicit scope inputs; list in the appraisal summary, not again as assumptions. |
| Explicit advanced age/sex/PA/distance distributions | Inputs defining sampling weights; summary only while active. |
| Unchanged donor distributions | General statement: retain donor patterns unless refined. No repeated numeric distribution cards. |
| New-user split | Tab 3 assumption if used and not already collected above; show as a preference, not a guaranteed realized split. Hide if an explicit user contract renders it unused. |
| New-user activity pattern | Tab 3 read-only policy when new users need assigned activity. |
| Induced-trip split | Tab 4 assumption if used and not already collected above. Do not equate it with recreational purpose. |
| Shift-source distribution | Tab 4 assumption for each target mode with shifted trips, unless the diversion modal already owns that input. |
| Frequency, trip-size, speed | Include only those still used to complete missing information or assign activity. Existing explicit user/trip contracts must not be overwritten. |
| MMET intensity | Read-only exposure assumption; show once at the stage completing exposure (Tab 2 basic; normally Tab 4 advanced). |
| Donor reuse / replacement policy | Short methodology explanation and report metadata, not another percentage slider. |

Preferences, hard filters and realized outcomes are different. Store requested
preferences and report realized allocations separately. A 10% preferred split
must never be described as an observed 10% result without measuring it.

## 7. One simple reactive contract

Yes: all relevant UI changes can lead to the same call:

```r
get_appraisal_assumptions(profile, tab = 2)
```

It returns a named list of existing profile entries, keyed by schema field ID.
The getter resolves applicability and presentation only. It must not load
geography, resample people/trips, change defaults, or write to reactive state.
Its result is a read-only view, not a second appraisal record.

The colleague's UI job is: persist current control values to the canonical
profile, then refresh the cards. Input values not yet written to the profile
cannot affect a getter that reads that profile. Temporary modal previews may use
a copy of the same schema, discarded on Cancel and committed on Save.

Different changes have different *HUB meanings*, but they need not have different
UI card handlers. A route change selects a different set of fields; an assumption
edit changes a displayed value. Both refresh the same getter.

Default resolution is a separate HUB operation at well-defined existing stages:
initial geography preparation, initialization of missing fields, and explicit
restore-defaults. It returns an updated profile for UI to store. Do not refresh
data-derived defaults merely because a card renders or a sampled REF changes.
Freeze them through ordinary navigation and refinement to avoid circular updates.
Geography changes need an explicit reset policy for old geography-derived values.

### Trigger catalogue

The proposed helper `get_appraisal_assumption_dependencies(profile, tab)` returns
concrete schema IDs, not wildcard strings or callback code. Populate it from the
same HUB catalogue used for applicability. Initially a broad dependency set is
acceptable: the getter is cheap, and avoiding missed updates matters more than
minimizing card refreshes. No need for clever inference from executed R code.

| Trigger family | Actual/current field IDs or expansion rule |
| --- | --- |
| Route and placement | `at_data_unit`, `modes`, `ui_version` |
| Distance/duration interpretation | `ui_dist_dur_type_[mode]`, `distance_unit_[mode]`, `duration_unit_[mode]`, `dist_dur_timeframe_[mode]`, `dist_dur_denominator_[mode]` |
| Mode-share interpretation | `ui_mode_share_show_options`, `mode_share_total_unit`, `mode_share_ref`, `mode_share_cf`, `mode_share_total_trips_basic`, `mode_share_total_trips`, `mode_share_total_dist`, `mode_share_total_dur` |
| Submitted travel | `users_count_ref/cf_[mode]`, `trips_count_ref/cf_[mode]`, `dist_dur_amount_ref/cf_[mode]`, plus the route's schema-defined timeframe/denominator controls |
| Population contracts | Schema entries for `pop_total_ref/cf_basic`, `pop_total_ref/cf_advanced`, `pop_number_ref/cf_[mode]_basic/advanced` |
| Population refinements | `ui_pop_refine_show_options`, `pop_refine_method`, `pop_target_percent`, `pop_target_age_groups`, `pop_target_pa_groups`, `ui_pop_refine_show_advanced`, `pop_refine_choice`, and the actual schema-defined population/PA spread inputs |
| Trip contracts/refinements | `trips_number_total_ref/cf`, `trips_number_ref/cf_[mode]`, `ui_trips_refine_show_options`, `trips_refine_method`, `trips_dist_value`, `ui_trips_refine_show_chars`, `trips_refine_choice`, and actual schema-defined trip spread inputs |
| Effective parameters | All canonical `assump_*` IDs, including those supplied through ordinary sliders/modals |
| Geography | `geo_level`, `geo_id`; refresh after new defaults are committed, not against old-city values |
| Restore/import/staged preparation | A changed profile, including default/provenance changes even where no widget value changed |

`ref/cf` and `[mode]` above are documentation shorthand only. Implementation must
expand and validate every name against `names(profile)`. A hidden UI version flag
or permanent "provided_above" flag is not enough to prove an input is currently
authoritative: applicability and ownership must be recomputed for the active path.

## 8. Saved metadata beyond assumption cards

Reproducibility also needs declared profile fields for seed, schema version,
data/model versions, assessment horizon and effect-duration policy. Snapshot
effective non-card model parameters (e.g. category midpoints and sampling-policy
settings) in a declared structured field, rather than relying on a changed config.
Large source datasets and HM lookup tables remain external, with stable version
identifiers. Bit-for-bit replay additionally depends on the software/RNG versions.
Do not expose every technical setting as an editable assumption card.

## 9. Implementation sequence and acceptance checks

1. Agree canonical names and explicitly name unresolved population-estimation and
   activity-allocation policies. Audit calculation consumers, not only existing cards.
2. Complete `default.R`; rename HUB/UI consumers together without legacy aliases.
   Add provenance structures and declare required reproducibility metadata.
3. Add one HUB catalogue describing dependencies, use conditions, card ownership
   and parameter precedence. Implement read-only getter and dependency helper.
4. Integrate preparation at explicit stage boundaries; calculations consume the
   persisted profile. UI uses canonical IDs and one card-refresh pattern.
5. Verify all four modes and input formats; Basic/Advanced; zero REF; manual
   overrides; route changes; repeated card rendering; explicit Tab 3/4 contracts.
   Verify getter/dependency names exist in schema, Cancel has no effect, Save
   affects calculation, and serialization/reload preserves effective parameters.

Remaining decisions are about model policy, not reactive plumbing: precisely how
total population is estimated across modes, which activity-assignment policies
are configurable, and whether later REF stages ever offer an explicit
"re-estimate assumptions" action. No automatic resampling-based refresh is proposed.
