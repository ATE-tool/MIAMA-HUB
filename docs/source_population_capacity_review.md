# Source population capacity review

Verified 2026-09-07 against the local `codex/appraisal-report` checkout, which
includes the `codex/assumptions-contract` sampling changes. This is a review of
the pre-fix behavior. **Update:** the replacement mechanism below is now
implemented in `R/population_donor_replication.R`; the historical checks are
retained to explain the defect. Tests cover identities, trip ownership, repeated
staging, all input routes/modes, and copied health histories.

## What the fallback did before this fix

HUB can reuse observed trip patterns with replacement and assign copies to a
fixed assessed set of people. It does not yet copy people to construct an
assessment larger than the geographic source population. CF recruitment can
extend beyond assessed REF, but is still limited to eligible source non-users.

The intended policy is different: the geographic dataset is evidence for a
hypothetical assessment, not its maximum size. Source capacity alone should
trigger a declared reuse fallback, not rejection or silent reduction of inputs.

## Shared paths and limits

- `prepare_refinement_profile_defaults()` is the shared Tab 2 -> Tab 3 entry.
- `.reference_person_scope_target()` rejects explicit REF population above the
  source size and rejects a larger population inferred from positive REF volume.
  A population inferred only from CF volume is instead capped at source size.
- Users, trips, distance/duration and mode-share inputs all reach this function.
  Distance/duration and shares first become per-mode trip-count targets.
- `.sample_reference_people()` requires distinct eligible people, enough observed
  mode users, and sufficient observed cross-mode overlap. There is no person
  sampling with replacement.
- `.assign_cf_user_count_delta()` recruits source non-users and rejects a target
  beyond that eligible pool. One person may use several modes; this is not a
  global one-mode-per-person restriction.
- `.expand_reference_trip_candidates()` samples donor trip patterns with
  replacement, generates new trip IDs and assigns them to scoped recipients.
  This is the already-implemented replacement fallback.

All four modes use these shared mechanisms. E-biking has an additional cycling
trip-pattern proxy, but not a general observed-person proxy for positive REF
user counts where there are no observed e-bike users. Missing donor patterns
and insufficient quantities of existing donor patterns are distinct cases.

## Executed checks

The diagnostic uses a controlled source of 20 people: four users of each active
mode and four car users, with two trips per person. It calls the actual HUB
staging/sampling functions, without loading health outcomes or running Shiny.
Distance and duration are tested separately within the fourth-unit design.

| Check | Coverage | Observed outcome |
| --- | --- | --- |
| Inferred REF population of 200 from increased volume | Basic/advanced x four modes x users/trips/distance/duration/shares (40) | All 40 rejected at population cap |
| Explicit REF population of 30 | Same 40 combinations | All rejected; basic uses explicit cap, advanced Tab 2 discards not-yet-accepted advanced table fields and hits inferred cap |
| Fixed population of 20 with 80 target trips | Basic/advanced x four modes x trips/distance/duration/shares (32), shared sampler layer | All 32 succeeded using trip-pattern replacement |
| No observed e-bike users/trips | Basic/advanced x five routes (10) | Eight trip-derived cases succeeded via cycling patterns; two oversized user cases failed |

These tests establish the distinction between person capacity and trip-pattern
reuse, not correctness of a future expanded-population health calculation.
The fixed-population cases test the sampler directly because advanced person
table values are accepted after Tab 2, not as initial Tab 2 fields.

Local diagnostic artifacts: `/private/tmp/verify-miama-capacity.R` and
`/private/tmp/miama-capacity-review.csv`. They do not modify source data or
application calculations.

## Implemented replacement contract

1. Introduce distinct appraisal-person IDs and retained source-donor IDs. Copy
   eligible source people when necessary, retaining their attributes and behavior.
2. Copy associated trip patterns with unique appraisal-trip IDs and correct new
   owners. REF and CF share appraisal-person identity; a person may participate in
   multiple modes, but each appraisal-trip copy may shift only once.
3. Load health histories through source-donor IDs and expand them once per
   appraisal-person ID. Current joins use `census_id`; duplicating that key would
   create incorrect many-to-many joins, while new unmapped IDs would lose health
   histories.
4. Apply the same expansion layer before basic/advanced staging and final results,
   and for all input units/modes. Honor the accepted Tab 3 person contract and
   Tab 4 trip contract without circular re-inference.
5. Retain hard exclusions and logical consistency: duplication cannot supply an
   excluded/absent category or place positive mode users in zero total people.
   Use an explicit documented proxy when a mode has no observed donor evidence.
6. Record original donor count, unique donors, copied people/trips, proxy use and
   requested/realized totals. Copies are not independent observations and do not
   increase the evidential sample size.
7. Verify population scaling end to end. Current health totals multiply by
   `cfg$population$person_weight`; do not both expand records and multiply by the
   expansion factor again. Keep input record counts versus represented people
   explicit rather than silently changing either convention.

The shared reference constructor now expands eligible donor capacity before
selection, including reserves for explicit CF user targets. It freezes source
rates so added appraisal rows do not alter subsequent population estimates.
Copied people keep donor IDs; copied trips receive unique IDs and new owners.
Health histories are expanded by donor ID exactly once per appraisal person.
Absent native e-bike users use labelled cycling person/trip/health proxies.
Other absent evidence and inconsistent mode-user/total combinations still fail.

## Scaling assessment (historical, superseded)

The subsequent decision uses one real appraisal person per record and sets
default `person_weight = 1` for all datasets. `source_person_weight` retains
geographic expansion as provenance only. Sampling and donor-reuse rules do not
change. The assessment below records the mismatch before that decision.

Tab 2 `users_count_ref_*` and `users_count_cf_*` are passed directly as counts
of individual records. No `person_weight` division is applied. Initial user
defaults likewise count records, not represented real people. Trip targets and
the current travel-by-mode totals count trip rows. Distance/duration and shares
are converted into those trip-row targets.

Health aggregation multiplies outcomes and population denominators by
`cfg$population$person_weight`. The current Leeds profile returns 163.552:
the original factor of 20 adjusted for the 0.122285 Leeds subsampling fraction.
Consequently, 1,000 requested user records correspond to about 163,552 represented
people under that health-output convention, not 1,000 real people. This is an
input/output units mismatch, not solved by person replacement.

Possible later choices: convert all real-person/trip inputs to weighted model
units and consistently label/convert defaults and outputs, or use unweighted
records throughout an appraisal. Changing only the health multiplier or only
one Tab 2 field would not settle the full contract. No scaling policy is changed
in this fix; copies are never multiplied by a second expansion factor.
