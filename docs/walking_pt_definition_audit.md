# Walking versus PT access: matched-route audit

## Finding

The T5 Leeds benchmark's 210 versus 197 walking-user discrepancy is explained
by mode definitions, not random sampling or missing person records.
Verified against `docs/_route_benchmark/snapshots.rds` (fixed 500-person sample):

| Definition | People |
|---|---:|
| Positive individual `walktime_wkhr` | 210 |
| Owners of walking trips excluding PT trips | 197 |
| Owners of PT trips with a walking component | 33 |
| Owners in both trip groups | 20 |
| PT-access-only walkers | 13 |

Thus, 197 + 33 - 20 = 210. All 13 people have observed PT access walking
(52 trip rows in total), and no qualifying non-PT walking trips. They have
not disappeared from the assessed population.

## Why the routes differ

`R/reference_data_extract_reference_ui_values.R`, `.miama_tab2_mode_specs()`,
excludes PT trips from walking trip counts. This keeps walking and PT-access
trip categories separate. However, its individual walking measure remains
`walktime_wkhr`, which includes these PT-access-only walkers.

`R/reference_data_apply_appraisal_scope.R`, `apply_reference_appraisal_scope()`,
initially identifies walkers from positive individual activity. For an explicit
trip target without an explicit user target, it subsequently replaces the mode
user scope with the owners of selected trips. Consequently, even an unchanged
walking trip total establishes 197 users rather than the individual-route 210.
The CF allocation starts from that reconstructed REF definition; it is not
randomly removing 13 users during CF sampling.

This can affect trips-per-user assumptions and recipient selection, as well as
displayed counts. It explains this count discrepancy, not all health-result
differences between routes.

## Agreed sampling rule

Walking and PT access remain distinct trip categories. PT-access users qualify
as existing walkers when sampling additional walking trips, including when the
trip-derived walking-user scope contains only separate walking-trip owners.
HUB now supplies this wider recipient pool without automatically promoting all
eligible PT users into the displayed walking-user scope. Actual assigned trips
establish additional walking users. Explicit accepted user scopes remain binding;
population exclusions still apply. Unchanged or decreasing trip targets do not
expand eligibility. This does not reclassify PT trips or add baseline MMETs.

The earlier recommendation below is superseded by this clarification: do not
remove PT walkers from eligibility simply to make the two baseline counts equal.

## Earlier proposal (superseded)

1. Use the same separate walking and PT-access definitions for users, trips,
   and mode-specific completion assumptions. For this sample, separate walking
   users should be 197 and PT-access users 33, with overlap allowed.
2. Keep original total walking activity and HM reference exposure intact. Derive
   a separate mode-specific walking measure for sampling and assumptions;
   changing the source `walktime_wkhr` in place risks changing health deltas.
3. Prefer classified trip evidence when available. Define and document an
   explicit fallback for individuals without trip evidence.
4. Test PT-only, walking-only, mixed walking/PT, missing-trip, no-change, and
   combined walking/PT interventions; rerun the matched benchmark afterwards.

Do not implement this by subtracting raw PT hours and testing whether the
remainder is positive. Among these 13 PT-only people, individual walking hours
minus summed PT walking hours ranges from zero to 0.175 hours/week. The origin
of these small aggregate differences (for example weighting) has not been
established by this audit. A residual-based test would still classify some as
separate walkers.

Regression coverage: `tests/testthat/test-pt-walking-recipients.R` checks existing
PT eligibility, out-of-scope exclusion, no automatic promotion, explicit user
contracts, unchanged/decreasing targets, and a PT-only recipient pool.
