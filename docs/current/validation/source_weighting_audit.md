# Source weights versus appraisal units

*Last content commit: 2026-09-10. Organized: 2026-09-11. Review/validation; conclusions retain their original scope.*

## Current verified contract

Appraisal person weight is one; source expansion metadata remains separate.
Trip counts and mode shares use row counts (`.trip_weights()` returns ones).
The unused `.weighted_sum()` helper still refers to `weight_tripXhh`; it has no
current callers in R and does not establish that source weights are applied.

This is a unit convention, not proof that the empirical donor distribution is
representative without survey corrections. Uniform geographic expansion and
non-uniform survey weights must not be treated as the same issue.

## Leeds trip check

Measured on packaged Leeds trips with nonmissing trip IDs:

| Quantity | Unweighted | Using stored trip weights |
|---|---:|---:|
| Trips | 83,205 | 88,551.01 |
| Walking mode share | 27.9899% | 27.7438% |
| Cycling mode share | 0.8281% | 0.8220% |
| Driving mode share | 62.6861% | 63.0086% |
| PT mode share | 8.4959% | 8.4256% |

Weights range from 0.8135 to 1.3611, mean 1.0643. These are diagnostic contrasts,
not a claim that directly applying the combined weights is the correct estimator
after synthetic-population construction. Mode shares here use main-mode groups.

## Meaning still to establish

Official NTS documentation describes corrections for nonresponse, declining
diary recording across the week, and short-walk recording. See
[NTS notes and definitions](https://www.gov.uk/government/statistics/national-travel-survey-2024/nts-2024-notes-and-definitions).
The local repositories inspected do not contain a definition or construction
formula for `weight_tripXhh`. Its name suggests combined trip/household weights,
but this is not verified. We need the data producer's definition, normalization,
and an account of corrections already incorporated in synthetic individuals,
trip replication and weekly person-level walking/cycling hours.

## Possible unweighted representation

Nonnegative weights can be integerized: for example floor(weight) copies plus
one additional copy with probability equal to the fractional remainder. For a
fixed target size, normalized weighted resampling is another option; it preserves
relative frequencies in expectation but not the absolute weighted total.
Neither creates independent evidence. Person-trip ownership, household structure,
unique generated IDs, donor provenance and consistency with weekly activity and
HM baselines must be retained. Do not apply a household correction a second time
if population synthesis already incorporates it.

Next: resolve provenance, compare weighted/unweighted trip frequency, duration
and individual activity agreement, then decide whether to prepare a calibrated
unweighted donor dataset or retain survey weights in estimation. This is separate
from interpreting user-entered 1000 people as 1000 appraisal people.

## Variance analysis status

The current-code diagnostic completed 180 appraisals: ten seeds, assessed sizes
100/500/1500, walking/cycling/combined, and whole-appraisal/fixed-REF experiments.
All completed without errors or warnings, with canonical assumption values and
provenance unchanged. The matched-route benchmark also completed 112 current
final-results reconstructions; it exposed a separate PT scope-materialization
defect. See `sampling_variance_evaluation.html` and `route_benchmark.html`.
The legacy report is archived. A larger 50-100-draw study remains pending.
Sampling variation conditional on the donor data cannot quantify systematic
error from unresolved source weighting.
