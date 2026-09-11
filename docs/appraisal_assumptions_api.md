# Assumption API for UI developers

HUB dev now implements the canonical profile-based assumption contract. The UI
schema PR changes `schemes/default.R` only; existing modules still need the
matching field renames and reactive integration before that PR is deployable.
HUB rejects obsolete assumption IDs with an explicit schema-upgrade message.
There is no legacy saved-appraisal migration or alias layer.

## Prepare once, read reactively

```r
# Existing Tab 1 transition: returns defaults and assumption provenance.
profile <- hub$build_reference_profile_defaults(profile)

# Each card reads the current canonical profile; neither call changes it.
fields <- MIAMAHUB::get_appraisal_assumptions(profile, tab = 2)
dependencies <- MIAMAHUB::get_appraisal_assumption_dependencies(profile, tab = 2)

# Explicit reset only: caller stores the returned profile.
profile <- hub$prepare_assumptions(profile, restore = TRUE)
```

The same getters are available as `hub$get_appraisal_assumptions(profile, tab)`
and `hub$get_appraisal_assumption_dependencies(profile, tab)`.
`prepare_assumption_profile()` is the stateless default-preparation equivalent.

All returned names are profile field IDs. Each assumption entry retains
`default_value`, `input_value`, `is_filled`, label/unit and `additional_data`.
Its read-only `display` component adds `value`, owning `tab` (possibly several),
`used`, `collected_elsewhere`, `editable`, `source`, and `reason`.
Do not persist `display` as a second parameter source.

`tab = NULL` returns all assumptions for selected modes, including unused ones
marked `display$used = FALSE`. A tab-specific call filters applicability and
parameters already collected by that tab's active inputs.

## Single UI trigger pattern

Persist control changes in the canonical profile, then rerender affected cards
with the getter. The dependency helper returns a conservative union of concrete
existing schema IDs, not wildcard names. Its scope is intentionally the same
across tabs initially. Profile replacement, changed default values, restore and
reload must also refresh cards even if a visible widget did not change.

No card call loads data, changes defaults or runs sampling. No caller must decide
which numerical conversion to perform merely to refresh a card. Do not mutate
the profile from inside a card render callback.

HUB controls default refresh: unresolved fields are initialized from assessed REF,
source observations, stored national rates or configured fallbacks. Resolved
defaults stay stable through normal navigation. Geography changes refresh
geography-dependent suggestions while retaining explicit overrides. Restore
defaults deliberately clears overrides. Source/proxy details are stored under
`additional_data`; the source datasets themselves remain external.

## Canonical fields

For each `walk`, `bike`, `ebike`, `pt`:

- `assump_trips_per_user_per_week_[mode]`
- `assump_trip_distance_km_[mode]`
- `assump_trip_duration_min_[mode]`
- `assump_trip_speed_kmh_[mode]`
- `assump_trip_source_shares_[mode]`
- `assump_mmet_per_hour_[mode]` (full inventory/results methodology, not a Tab 2-4 card)

Shared: `assump_new_user_percent`, `assump_induced_trips_percent`, and
`assump_new_user_activity_pattern` (only `observed_donor_patterns` supported).
The schema also declares `appraisal_model_parameters`, `appraisal_sampling_seed`,
`appraisal_data_sources`, and `appraisal_schema_version`.

`default_*` names are replaced, not maintained as aliases. `default_value` remains
the suggestion property of every field. Explicit overrides use `is_filled`,
even if their value equals the default. Source-mode shares remain a named list
of source modes with `percent` values, matching the existing pie shape.

Distance/time conversions and changed CF exposure consume these IDs. The unused
trip-size quantity is deterministically derived from the selected trip-size
assumption and speed; distance/duration/speed are not three independent inputs.
Explicit active advanced distance refinements supersede the scalar distance
assumption. Tab 3/4 person/trip authority is retained during assumption edits.

## Reproducibility and limits

The profile snapshots effective model settings; HUB restores those sections of
config when receiving the profile. The top-level stage/results methods use the
profile sampling seed unless an explicit method argument overrides it, and record
the used seed back into the profile. Completed `results_data` includes the profile
and named assumption entries. No new UI export/download implementation is included.

External source paths are recorded, but files must still be retained/versioned
to reproduce results: a path is not a content hash. Health lookup/software
version pinning remains a deployment responsibility. Metadata does not guarantee
bitwise reproduction after external data or RNG/software changes.

The population estimator and donor-reuse policies are unchanged, not newly exposed
as adjustable controls. New-user activity has one supported policy; lower-quartile
patterns are not implemented. Card applicability is conservatively route-based:
some allocation parameters can remain listed for a no-change scenario, although
no trips ultimately use them. No claim of exact sampled distance/minute totals
is made; see the methodology's sampling limitations.

## Verification

Run `tests/testthat/test-appraisal-assumptions.R` for naming, purity, applicability,
overrides, serialization, conversion and configuration-snapshot checks. With the
schema PR checkout, `inst/workflows/dev_verify_assumption_contract.R` runs a
four-mode Leeds appraisal through Tab 2/3/4 staging and health results.
