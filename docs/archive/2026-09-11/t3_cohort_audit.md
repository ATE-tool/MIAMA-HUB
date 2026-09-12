# T3: realistic-size cohort reconstruction check

*Last content commit: 2026-09-10. Organized: 2026-09-11. Historical snapshot; not current guidance.*

## Method

Used observed individual and trip records from packaged Leeds 5000, with real
packaged HM outcomes. Fixed random subsets of 500 and 2000 people were selected
using seed 20260910. Walking REF trips were measured from each subset; CF trips
were set 20% higher. After Tab 2 staging, Tab 3 total and walking-user counts were
manually reduced to 75% of their suggestions, independently for REF and CF.
Tab 4's generated trip table was accepted unchanged. Final results ran through
`Hub$build_results()`, including health lookup and aggregation.

This is a controlled advanced-workflow scenario, not a browser test or an audit
of every mode/refinement. Three sampling seeds were tested for each sample size.

## Results

| Source sample | Seed | Accepted/final CF people | People replaced | Accepted/final walkers | Walking members replaced |
|---|---:|---:|---:|---:|---:|
| 500 | 1 | 375 | 89 | 159 | 48 |
| 500 | 13 | 375 | 87 | 160 | 43 |
| 500 | 27 | 375 | 83 | 158 | 51 |
| 2000 | 1 | 1500 | 342 | 689 | 196 |
| 2000 | 13 | 1500 | 341 | 694 | 220 |
| 2000 | 27 | 1500 | 331 | 692 | 204 |

Counts agree in every case, but 22-24% of the accepted CF cohort is replaced.
Walking membership also changes. This is not a small-fixture edge case.
The run emitted donor-trip-reuse warnings. Rechecking the 500-person seed-1
case with immediate warnings confirmed replacement trip patterns were used to
keep fixed trip totals after reducing users, as intended; this is distinct from
the unintended person re-selection.
People replaced means staged IDs absent from final scope; equal counts imply
the same number of incoming replacements, not twice the reported number.

The CSV also records retained-row MMET-delta sums as diagnostic information.
These can include donor-reserve rows and are NOT a comparison of scoped health
benefits. The impact of this defect on final health totals has not been quantified.

## Cause and proposed fix

Tab 4 staging re-scopes the staged REF and CF independently, including a different
CF seed. In `R/api_hub.R`, final calculation reads accepted table counts through
`.counterfactual_input_values()`, but `build_counterfactual_data()` re-scopes
source REF and initializes a new CF copy. It does not use the accepted staged
cohort as its starting state. Matching counts and seeds cannot recover that
cohort through a different sequence of sampling calls.

The fix should be in HUB, without new UI controls:

1. When valid staged snapshots exist, retain their person IDs, population masks,
   and mode-user membership as the accepted contract.
2. If Tab 4 is unchanged, use its staged travel state. If trip targets or trip
   refinements change, apply only those changes within the accepted people.
3. Keep health exposure relative to the original matched REF. Do not add a staged
   activity change again or treat staged CF activity as a new baseline.
4. Invalidate/rebuild staging after upstream edits; never reuse it just because
   a snapshot object exists. Keep the standalone/basic unstaged path available.
5. Require the existing identity regression and this larger audit to pass, plus
   repeated results and Tab 4 changes that preserve the accepted person contract.

## Repair verification

The accepted-snapshot finalization path is now implemented in
`R/finalize_staged_appraisal.R`. Repeating all six scenarios yields **zero person
replacements and zero walking-membership replacements**. Retained-row staged
and final MMET-delta totals also agree for these unchanged Tab 4 tables.
See [post-fix CSV](t3_cohort_audit_after.csv); the earlier CSV is preserved as
the before-fix evidence. The manual-cohort identity regression now passes.
Focused tests cover REF trip edits, shifted versus induced additions, repeated
calculation, and rejection of population counts inconsistent with staging.
The full HUB suite passes with one existing expected donor-reuse warning.
Additional focused tests verify later reductions can undo accepted trips without
unlocking them as donors for additional shifts. Duration-route final-results
tests also cover synthpop-only staging followed by matched HM baseline attachment.
UI/browser integration and new-user-control refresh remain separate work.

Reproduce after loading HUB with `pkgload::load_all(".")`:

```r
source("inst/workflows/dev_t3_cohort_audit.R")
run_t3_cohort_audit()
```

Results: [CSV](t3_cohort_audit.csv).
