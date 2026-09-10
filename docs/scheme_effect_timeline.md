# Scheme effect over time

## Profile contract

All four fields live in UI `schemes/default.R`, with normal `default_value`,
`input_value`, and `is_filled` semantics. No separate mutable settings store.

| Field | Default | Meaning |
|---|---:|---|
| `scheme_peak_year` | 1 | Years from start until maximum effect; 0 means immediate |
| `scheme_no_decline` | TRUE | Keep the maximum effect for the rest of the assessment |
| `scheme_decline_year` | 10 | Year decline starts; ignored when no decline is selected |
| `scheme_end_year` | 20 | Year effect reaches zero; ignored when no decline is selected |

Years must be whole numbers from 0 to 40 inclusive. For declining schemes:
`peak <= decline < end`. Settings apply equally to basic/advanced routes,
all Tab 2 input units, and all active modes. They do not modify Tab 3/4 targets.

`get_scheme_effect_timeline(profile, cycles = 0:40)` accepts a profile or flat
values and returns `cycle`, `effect_factor` (annual average), and
`effect_at_year_end` (for the preview). It is read-only and validates the inputs.
`get_scheme_effect_summary(profile)` returns human-readable descriptions keyed
by the applicable profile field IDs. Tab 5 uses the calculated result's profile,
so its summary cannot describe unsaved edits from a later visit to Tab 2.
Calling with no settings uses the same defaults as UI. Profile defaults remain
effective even before a field is marked filled.

## Calculation sequence

1. Build the maximum-effect person/trip snapshot and MMET differences once.
2. Build the scheme curve over available health cycles.
3. Skip the MMET-change lookup for cycles whose annual factor is zero.
4. Calculate full-effect annual health outcomes and HALYs.
5. Multiply annual outcome differences by the factor, then aggregate as usual.

For every annual outcome, `CF_scaled = REF + factor * (CF_full - REF)`.
Scaling happens after the health lookup, not on its nonlinear MMET input. The
factor is the integral of the piecewise-linear curve over each reporting year.
The default first-year factor is 0.5; a peak of zero restores immediate effect.
Cycle 0 receives zero benefit. Zero-effect years have CF = REF, not zero REF
deaths/cases. Existing activity is not removed. Previously accumulated benefits
remain; no residual annual benefits are modelled after cessation.

LY/HLY exports reconstruct occupancy from full-effect net death/unhealthy
transitions before applying the annual factor. HALYs are already annual values
and are scaled only once. Audit data are available in
`counterfactual_health_report$scheme_effect_timeline` and the temporary health
table's `scheme_effect_factor`. Full transition columns retained for LY/HLY are
internal reconstruction data, not extra reportable health outcomes.

This is a deliberately simple outcome-scaling approximation, not a fresh health
simulation for a variable exposure history. The underlying HM lookup still uses
its long-term model. The assessment horizon remains unchanged. Travel tables
show peak-effect snapshots; they are not annual trip time series.

## UI handoff and verification

The UI branch adds four dictionary entries, a first-input Tab 2 section, and a
live preview. Existing wrappers and `update_all_appraisal_inputs()` save values
on navigation. The preview calls HUB's public API rather than duplicating math.
The ggplot preview spans years 0-40. Numeric controls use the same bounds;
HUB defensively validates bounds and ordering before calculation. There is no
separate timeline-specific UI error handler: the UI's shared validity system
will own user-facing validation. Both branch versions are required for the widget;
the installed 9001/9002 packages do not contain this API.

The UI feature patch is based on UI dev. That branch still uses legacy
assumption IDs rejected by current HUB dev; full-app testing also requires the
separate canonical-assumptions UI integration. The timeline component can be
tested independently, without changing the installed package or those fields.

Manual checks: default -> first-year half effect; peak 0 -> immediate effect;
peak 2 / decline 4 / end 6 -> factors .25, .75, 1, 1, .75, .25, 0 thereafter.
Use an identical sampling seed when comparing results. Person/trip snapshot
counts must remain identical, REF health values unchanged, annual benefits zero
after cessation, and cumulative benefit flat thereafter. Repeat a basic and an
advanced appraisal. Invalid year ordering must produce a validation message.
