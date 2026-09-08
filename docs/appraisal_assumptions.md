# Assumptions that complete an appraisal

## Purpose and review status

This is the implementation contract on `codex/assumptions-contract` in HUB and
UI. It replaces the separate Tab 4 read-only assumptions-card proposal. It is
a coordinated draft, not a change to the published app.

An assumption supplies information missing from the user's volume input. It
does not replace a provided user/trip total. Unchanged population distributions
are not listed: CF follows REF unless a refinement says otherwise.

## One place to inspect the implementation

- HUB: `R/appraisal_assumptions.R` owns the catalogue, default provenance,
  applicability, validation and effective distance/time conversions.
- Configuration: `cfg$assumptions` in `R/config.R` holds stored/fixed fallbacks.
- UI: `utilites/assumptions_cards.R` owns the three cards and one editor.
- `schemes/default.R` retains explicit, readable field definitions, including
  the new `default_trip_duration_walk/bike/ebike/pt` entries.
- Existing conversion, sampling and results functions call the shared helpers;
  they do not each implement their own default hierarchy.

## Where the suggested values come from

For frequency, mean distance and mean duration, use the first available positive
value: assessed REF records, geographic source records, a configured stored
England rate, then a fixed fallback. Frequency is trip rows per observed active
user in a reference week. Means exclude missing/nonpositive observations.
Speed always starts from the fixed configuration, not a donor vehicle's speed.

The England rates retain values previously described as England-derived in UI.
They are **stored values, not a new national-data calculation**; their original
provenance still needs verification. No national dataset is loaded by this
resolver. E-bike uses cycling as an observed-data proxy, explicitly labelled.
Fixed e-bike fallbacks are not labelled as observed cycling data.

Defaults are initialized when the geography profile is built. At that point an
assessed REF usually does not exist, so the source population is used. They
remain stable during navigation and CF edits: the act of applying an assumption
must not recalculate that assumption from its own output. The resolver accepts
an assessed REF when explicitly preparing a new default profile; ordinary card
rendering does not automatically rebase defaults after each sampling run.

`default_value` and its `assumption$source` remain separate from `input_value`.
A genuine edit uses the latter and is labelled as a user override. Restore
defaults clears that override. Neither action rewrites source observations.

## Which quantities are shown and used

| Missing quantity | Calculation use |
|---|---|
| Trips per user per week | Complete user/trip allocation where counts do not already bind; scale the expected activity of newly assigned users. |
| Mean distance per trip | Convert an aggregate distance to a trip target; supply a preferred mean for candidate weighting where no explicit distance distribution applies. |
| Mean duration per trip | Convert an aggregate duration to a trip target; together with speed, infer a preferred distance. |
| Speed | Convert sampled changed-trip distance to active minutes, and the expected duration of new-user activity. |

Distance routes use distance and speed: `minutes = km / km_per_hour * 60`.
Duration routes use duration and speed: `km = minutes / 60 * km_per_hour`.
The third quantity is derived, not an independent editable input. The entered
aggregate kilometres/minutes are not themselves repeated as assumptions.

In basic mode the applicable fields live on Tab 2. In advanced mode, frequency
is assigned to Tab 3 and distance/speed to Tab 4; distance/duration and mode-share
routes show their completion fields earlier on Tab 2. A field saved in a Tab 2
data-entry modal is omitted from the bottom cards, but retained in the results
record. New-user and induced-trip percentages already have dedicated controls,
so this draft does not duplicate them. Car speed/distance are not exposed as
active-exposure assumptions.

An explicitly edited advanced distance distribution/mean takes precedence over
the simple distance assumption. The redundant editable mean is omitted from
the card. An unchanged generated distribution does not silently suppress an
editable mean. Advanced category midpoints approximate a mean when needed for
new-user activity; they do not guarantee an exact sampled mean.

## What an edit does, and does not do

Save updates the canonical profile, invalidates CF/results and leaves the
accepted population/trip snapshots intact. Next/Calculate performs the normal
recalculation. An assumption edit alone does not trigger a new geography load.
Returning through Tab 2 Next deliberately stages new estimates when required.

User-provided trip counts remain binding. Distance is a sampling preference,
not an instruction to force every trip to exactly that length. Speed acts on
changed CF trips; existing REF activity is not recalculated. New-user activity
retains donor variation while scaling its expectation by effective frequency
and duration. User-sourced trip rows remain excluded from a second MMET addition
under the existing exposure-source accounting rule.

PT quantities describe **walking to/from PT**, not the vehicle journey. Where
a changed trip lacks an observed walking access distance, the editable access
distance supplies its fallback. Active minutes use walking speed. This replaces
the misleading full-journey PT numbers previously displayed by the UI card.

Changing an assumption need not change an outcome if there is no intervention,
the related count has already been fixed, or the eligible pool cannot provide a
different sampled pattern. Tests must distinguish this from an ignored input.

## Results and inspection

`get_appraisal_assumptions(profile)` returns values, units, default values,
sources and override status. `Hub$build_results_data()` freezes this table in
`results_data$assumptions`; table/report exports append it to their assumptions
section. Later profile edits do not mutate a completed result. This is a first
numeric summary, not yet a complete inventory of all biological and sampling
configuration. Explicit refinements continue to be recorded in their existing
profile/sampling reports.

## Review checklist

- Test Save, Cancel, Restore defaults and reopening the modal for each route.
- Change distance for a distance input, and duration for a duration input:
  inferred trips should change unless an accepted later trip count supersedes it.
- Hold trips fixed and change speed: changed-trip minutes/MMETs should respond;
  person and trip counts should not be re-estimated.
- Check no-change, zero-REF fallback, PT access and e-bike proxy cases.
- Check advanced distance precedence and absence of duplicate editable fields.
- Confirm completed results/export provenance before and after an override.
- Curate exact card inclusion and presentation with the UI maintainer.
- Verify the historic England rates and review the fixed speed values.
- Decide separately whether any later stage should explicitly offer to rebase
  defaults onto the final REF, rather than doing so silently.

The new behavior is registered by assumption metadata in the profile. Existing
low-level calls with plain input lists retain legacy behavior unless they use
`prepare_assumption_profile()` followed by `extract_input_values()`.

## Verification of this draft

The HUB test suite and isolated Shiny controller tests pass. The packaged Leeds
integration workflow (`inst/workflows/dev_verify_assumptions.R`) builds staged
tables and final health/results twice. Doubling walking speed preserves walking
15,000 REF / 20,000 CF trips and cycling 500 / 700, changes CF MMETs and records
the override without mutating the previous results snapshot. Source paths point
to the local source package, not the installed library.

The UI starts successfully with the matching source package. Browser navigation
and visual layout have not been verified in this environment; these remain on
the manual review checklist above. Nothing has been published by this draft.
# E-bike proxy calibration

When native e-bike observations are absent, cycling supplies the donor pattern.
The provisional configuration multiplies cycling distance by 1.30 and speed by
1.20 (18.84 km/h from 15.7 km/h). The duration proxy factor is 1.30 / 1.20;
trip frequency is unchanged. These are transparent calibration assumptions,
not measured e-bike rates. Observed native e-bike values are not multiplied.
The catalogue labels cycling proxies and preserves explicit user overrides.
Changing distance or duration routes still leaves only two independent inputs:
the unused third quantity is derived using speed.
