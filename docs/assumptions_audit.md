# Assumptions across Tabs 2-5

Historical pre-implementation audit. For the subsequent coordinated branch
draft, see [Assumptions that complete an appraisal](appraisal_assumptions.md).

Code review dated 2026-09-06. This is an implementation audit and proposed
contract, not a claim that all proposed controls are functional. No UI or HUB
calculation code was changed for this review.

## Current position

UI `dev` and refreshed `origin/dev` are at `7c63fb8`. The worktree is clean.
The dynamic Tab 4 card remains on `codex/tab4-assumptions-card`, commit
`07ebe08`, and is not merged into remote `dev`. That change reads current
distance/speed entries, shows selected modes and units, and labels speed as
not applied. It is a read-only display improvement, not a complete assumptions
implementation. It does not resolve advanced distance overrides.

For implementation, start a new UI branch `codex/assumptions-contract` from
current `origin/dev`. Reuse the small renderer where useful, but update its
semantics as part of the broader change. Do not merge both competing card
implementations independently. Keep HUB changes separate on a branch from
HUB `dev`, with a coordinated UI PR. Neither branch has been created by this
audit.

## How values currently travel

1. `schemes/default.R` supplies field definitions and initial values.
2. `utilites/inputs_wrapper.R` initializes controls from `input_value` when
   `is_filled` is true, otherwise from `default_value`.
3. HUB writes geography-derived reference values and staged refinement values
   to matching profile defaults. This does not mean every field in default.R
   is populated from the selected geography.
4. At Next/Results, `server.R` calls `update_all_appraisal_inputs()`, then passes
   the profile to the relevant HUB staging/results method. The collector stores
   live, named Shiny inputs found in the profile and marks them filled.
5. HUB extracts inputs and applies route-specific defaults and precedence.
   An input can be collected and invalidate cached state without being consumed
   by a calculation. Speed is an example.

This establishes a save path for the editable assumptions; it does not prove
that typing in a field immediately rebuilds all displayed estimates. It also
does not distinguish a genuine manual edit from an unchanged live control
marked filled during bulk collection. This review inspected code; it did not
run a browser regression of save, restore, modal reopening and navigation.

## Tab 2 inventory

| Parameter | Where its initial value comes from | Current calculation role |
|---|---|---|
| `default_trips_per_user_per_week_*` | Fixed UI defaults labelled as England-derived, with an e-bike fallback. Walk 10.93, bike 6.20, e-bike 7.50, PT 5.64. | Used in user/trip inference and allocation. These controls already occur inside Tab 2 input modals, but not in the bottom assumptions card. |
| `default_trip_distance_*` | Fixed UI values: walk 1.15, bike 5.33, e-bike 5.7, PT 19.63, car 13.73 km. No reference-update producer for these field names was found. | A preferred mean for CF candidate weighting when no distance distribution is supplied. In advanced mode a `trips_spread_mean_cf_*` value takes precedence; category distributions take precedence over mean-distance weighting. Not a universal conversion factor or exact sampled mean. |
| `assump_trip_speed_*` | Fixed UI values: walk 5, bike/e-bike 15.7, PT 12, car 25 km/h. | No HUB calculation consumer of these field names. They are included in invalidation patterns, which does not make them operational. |
| Mean trip duration | No equivalent editable assumption field. | Observed mode-specific mean duration converts Tab 2 duration volumes and duration-based mode shares into trip-row targets. Individual trip durations also determine physical-activity changes. |
| Observed mean trip distance | Calculated from the reference trip data by `.tab2_reference_mode_mean()`, including mode proxy handling. | Converts distance inputs and distance-based mode shares into trip counts. This is a different value/source from the displayed `default_trip_distance_*`. |

Consequences:

- The screenshot's distance and speed values are stored defaults, not proof of
  a fresh Leeds calculation. The description 'derived from England data' is
  metadata, not a live data-source link.
- Edits to trip frequency can affect calculations. Distance edits affect only
  applicable sampling paths. Speed edits currently have no calculation effect.
- Trip duration belongs in the inventory. Initially expose the duration actually
  used for the route, with its source and units. Do not add an editable field
  until its effect on conversions and assigned CF activity is defined.
- For walking and cycling mode switches, `.switch_trips_to_active_mode()` copies
  raw donor distance and duration into the target mode. It does not recalculate
  walking/cycling time using the displayed speed. A car-to-walk switch can
  therefore retain the donor duration. This is a methodological issue to resolve,
  beyond merely wiring the card.
- E-bike switches derive minutes from raw distance and configured e-bike speed.
  The editable e-bike speed field and the effective config speed are separate.
- PT preserves positive access-walking distance/time where available and uses
  configured fallbacks otherwise. The UI labels a 19.63 km trip distance as PT,
  but the mode title refers to walking to/from PT; these are distinct quantities.

Recommended bottom-card contents: applicable weekly trips/user, the distance
and duration used in conversion, and any separately applied trip-distance
sampling preference. Show mode-specific proxy/fallback provenance. Resolve the
speed/duration contract before promising editable speed functionality.

## Tab 3 inventory

The bottom card is static explanatory prose. It does not expose quantitative
values, their sources, or whether a parameter was superseded.

Useful quantities and policies to present:

- New-user percentage (`pop_new_current_perc`). UI and config start at 10%.
  HUB staging may update its default from the realized split. It applies when
  user counts are inferred; explicit user counts supersede this preference.
  Show requested/effective/realized values separately where they differ.
- Weekly trips per user where it informs the people inferred from trips.
- New-user activity pattern: observed activity values sampled from current
  users of that mode, with cycling as an e-bike proxy. This is a named sampling
  policy, not necessarily a single editable mean or a fixed lowest quintile.
- Fallback activity when no positive observed pattern exists: walk/cycle/e-bike
  currently default to one hour/week in `miama_counterfactual_defaults()`;
  PT uses its configured access-walking minutes converted to hours. These are
  conditional fallbacks and should not be presented as universally applied.
- Optional compact read-only summaries of the age, sex and PA targets already
  selected in advanced controls, identifying their role as sampling preferences.

Excluded age/PA categories, final REF/CF counts and scope selections belong in
the input summary card. They are explicit appraisal choices, rather than hidden
assumptions. Do not create another independently editable copy of each slider
in the assumptions card; display the canonical value or edit through one
shared mechanism.

## Tab 4 inventory

Current `dev` still contains hardcoded distance/speed lists. The unmerged card
branch replaces the literal values but does not provide the effective sampling
parameters or edit handling needed here.

Recommended contents:

- Effective distance distribution or preferred mean, with its precedence and
  source. A displayed default mean should say when advanced distributions
  supersede it.
- Requested and realized induced-trip percentage, distinct from new users.
  UI/config default to 10%, but staging currently prefers a realized induced
  split and otherwise initializes it from the effective new-user percentage.
  This initialization coupling is an existing rule that should be explicit.
- Per-target-mode source-mode diversion shares. HUB uses configured shares when
  supplied, otherwise observed source-trip shares, then fallback data. E-bike
  config supplies equal cycling/PT/driving shares. These are assumptions about
  donors, not the Tab 2 overall modal shares.
- Applicable duration/speed or PT access assumptions, with unambiguous labels
  separating whole PT trips from active access legs.
- Conditional sampling policies: distance plausibility, donor-pattern reuse,
  fallback to induced trips and relaxation of weights within eligibility. The
  constants include a plausibility multiplier of 1.2 and default diversion mode
  'car'. Surface policy descriptions first; do not expose every internal
  constant as a routine numeric control.

Trip counts, excluded categories and the selected refinement method belong in
the summary. The legacy basic `trips_dist_value` remains report-only in the
current path and must not be labelled as an applied quantitative assumption.

## Results already have a partial foundation

`.results_export_assumptions()` produces an Assumptions export table and report
section. Currently it contains cycle-zero handling, population scaling, sign
conventions, mode attribution and results notes. It is not an inventory of
effective Tab 2-4 assumptions or overrides.

Extend this existing surface, rather than adding an unrelated export. Freeze
the assumptions used by a completed run alongside its results. Later profile
edits must not relabel old results with new assumptions.

Suggested plain-text form (placeholders, not calculated values):

> This assessment used [data profile] for [geography]. Travel inputs were
> supplied as [unit and timeframe]. People/trips were inferred using
> [mode-specific rates and sources]. The requested new-user share was [x%]
> [or: explicit user counts determined it]. Trip sampling used [distance
> targets] and [source-mode shares]. The requested induced-trip share was [y%],
> with [z%] realized after allocation. The run applied [proxy assumptions and
> fallbacks actually used]. Health results cover [years] with [population
> factor and activity-intensity settings].

Also disclose the applicable e-bike proxy, PT access definition, exposure
duration policy and HALY method. Keep raw engine parameters and seed in an
expandable audit/export section rather than crowding the main results card.

## Proposed consistent contract

For each relevant parameter, HUB should return a compact record containing:

- ID, label, mode, unit and owning tab;
- default value and source (local data, configured fallback or stored default);
- requested override and effective value used by the calculation;
- applicability/status: applied, superseded, informational or fallback-only;
- realized value where sampling can differ from the target;
- effect description, and any associated fallback/adjustment note.

Resolve each parameter once and reuse the resolved values for conversion,
sampling, cards and the completed-results record. UI default.R remains the
human-readable schema and label source, but should not independently duplicate
model assumptions that HUB already defines in config. Local defaults should
refresh deliberately on source/geography changes; CF-only edits should not
silently recompute their own reference assumptions.

For editable numeric fields, the lifecycle should be explicit: restore the
source default, validate an override, send it through the profile, invalidate
dependent staged data, recompute, then display what was actually used. Avoid
duplicate Shiny input IDs across cards and modals.

## Decisions before implementing

1. Distance/duration/speed: define which two are independent and when the third
   is derived. Recommended: retain observed REF travel as evidence and apply
   explicit overrides at defined inference or CF-allocation stages. Do not
   independently edit all three without a consistency rule.
2. Walking/cycling switches: decide whether target-mode duration should be
   calculated from trip distance and target-mode speed instead of retaining
   raw donor duration. This affects physical activity and health results.
3. Default provenance: prefer geography-specific observed rates where suitable,
   with explicit configurable fallback values and e-bike/PT handling.
4. Advanced precedence: display supersession when an advanced distribution
   makes a scalar default inactive. Editing that inactive default should not
   silently override a deliberately selected distribution.
5. Separate parameter input from realized outcome. A realized new/induced share
   can be reported without silently becoming the next requested assumption.

## Suggested implementation order and checks

1. Agree the above semantics and implement a HUB assumption resolver/report.
2. Wire editable operational values to their consumers and test each input
   route, including advanced overrides and unchanged-controls cases.
3. On the fresh UI branch, unify cards using that report; retain single owners
   for editable controls and list category exclusions in summaries.
4. Extend the existing results assumptions table with an immutable run snapshot.
5. Verify save/reopen/Next/Results, defaults restoration, changed geography,
   basic/advanced transitions, PT/e-bike proxies, and cache invalidation.
6. Update README and methodology when the implementation semantics are settled.

## Main code locations

- UI: `schemes/default.R`, `modules/tab2/tab2Server.R`,
  `modules/tab3/tab3Server.R`, `modules/tab4/tab4UI.R`,
  `utilites/inputs_wrapper.R`, `utilites/appraisal_list_tools.R`, `server.R`.
- HUB: `R/api_reference_profile_defaults.R`,
  `R/reference_data_extract_reference_ui_values.R`,
  `R/api_refinement_profile_defaults.R`, `R/tab2_input_conversion.R`,
  `R/counterfactual_data_sampling_functions.R`,
  `R/counterfactual_data_apply_ui_values.R`, `R/config.R`,
  `R/shared_state_invalidation.R`, `R/results_data_export_functions.R`.
