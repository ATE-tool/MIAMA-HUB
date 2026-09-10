# External Review: Current Bugs, Route Differences and Sampling Variance

Assessment date: 9 September 2026. No calculation or UI code changed.

**Implementation update, 10 September:** the historical assessment below is
retained. T2 (inactive Tab 2 inputs at receipt/staging) and T6 (baseline-inclusive
HLY/LY reconstruction) are now implemented locally in HUB dev. The full test
suite passes. A Leeds 695-to-1,390 cycling-trip check produces identical sampled
people, trips and exposure with or without stale 155-to-310 users inputs. Actual
Leeds HLY reconstruction agrees with an independent baseline-inclusive sum.
No UI or assumptions code changed; T3/T4 and the variance work remain deferred.
These changes are not yet packaged into UI's installed 9001 archive.

## 1. Scope and Versions

Reviewed `MIAMAT_users_route_and_bugs.pdf` and
`MIAMAT_vs_AMAT_clean_comparison.pdf`, supplied by the user. Their proposed
fixes are suggestions to assess, not an agreed implementation specification.

The reports identify master and version 0.0.0.9000, but do not supply exact
commit IDs or saved scenario inputs. That version number was reused previously,
so their precise runtime cannot be reconstructed from the PDFs alone.

This assessment distinguishes:

- **Current working UI:** UI dev `bd4f9c3`, using installed and locked HUB
  **0.0.0.9001**, packaged from **2b45a09**.
- **Latest HUB source / optional package:** HUB dev **1e01568**, packaged as
  **0.0.0.9002**. This contains the canonical assumptions contract, but requires
  the corresponding UI integration. It is not the package currently loaded by UI.
- **Verification:** source inspection of both HUB versions and current UI;
  eight fresh API scenario checks using the installed 9001 package and current UI
  schema; small targeted function checks; packaged-data inspection; HM source
  inspection. These are not browser interaction tests or an exhaustive test suite.
- **Not verified:** the AMAT workbook, its calculations, or the original exported
  appraisals used in the PDFs. No claims about exact AMAT equivalence are certified.

## 2. Main Conclusion

**There are genuine remaining state/route bugs. Sampling variance is real, but
it is not an adequate explanation for all differences between routes.**

Distinguish three sources of variation:

1. **Different implied scenarios:** equal total trips can involve different
   people, baseline physical activity, ages, trip durations, and per-person doses.
   These are different health scenarios, even if their total trips match.
2. **Implementation differences:** hidden inputs, staged defaults and final
   reconstruction can alter a scenario merely because of navigation or input route.
   These differences should be eliminated, not averaged away.
3. **Monte Carlo sampling variation:** repeated fresh draws of the same scenario
   select different recipients and trip patterns. This needs quantification after
   the scenario and input-state rules are held constant.

For example, increasing cycling users from 155 to 310 asks for 155 additional
mode users. Increasing trips from 695 to 1,390, with the current 10% default,
mainly increases activity among existing cyclists and recruits a much smaller
group. The second scenario does not assert 310 cyclists. Converting both with
one average trips/user ratio does not make their recipient-level exposures equal.

An appropriate equality test is: **same REF individuals and activity, same CF
individuals and activity, same health inputs and horizon -> same health result**.
Equality of aggregate trip counts alone is not that test.

## 3. Focused Current-Version Checks

Leeds, cycling, default health horizon, source-person weight 1. The trips cases
specify 695 REF and 1,390 CF weekly trips. The users case specifies 155 REF and
310 CF users instead; its realised activity/trips are not forced to match the
trips case. Advanced checks submit generated population/trip table values as
filled, as the UI does. The 100% new-user edit is made after Tab 2 staging.

| Check | HALYs gained | People with changed MMET exposure |
| --- | ---: | ---: |
| Basic trips, seed 1 | 36.5946 | 166 |
| Basic trips, seed 2 | 40.3475 | 170 |
| Basic trips, seed 3 | 37.0658 | 171 |
| Basic users, seed 1 | 9.1311 | 155 |
| Basic trips, stale users fields also submitted, seed 1 | 9.6840 | 164 |
| Advanced trips, accepted tables, new-user slider 10%, seed 1 | 34.7578 | 162 |
| Same advanced case, new-user slider 100% | 34.7578 | 162 |
| Same advanced case, distance refinement method selected without value edits | 34.7578 | 162 |

HALYs above are the sum of `d_haly` retained in the health diagnostic report,
not a sum over the released person-cycle table after `build_results()` returns.
The packaged lookup has zero slopes at cycle 0. These checks are not an exact
reproduction of the PDF's exported 40-year numbers or original UI click sequence.
See [probe results](external_review_route_probes_2026-09-09.csv).

Three seeds are far too few for an uncertainty interval or a stability threshold.
They establish that draws vary. They do not establish that variability is small
for other scenario sizes, populations, constraints or routes.

## 4. Status of the Reported Observations

| PDF observation | Current assessment | Priority / indicative effort |
| --- | --- | --- |
| **A: user recruits weighted toward existing users' age/sex/PA** | Supported by current code. Reference mode-user distributions feed candidate weights even without an explicit advanced distribution edit. Important modelling assumption, not automatically a bug. The claim that it gives almost the smallest possible benefit is not established. | P1 decision and audit, 1-2 days; policy implementation 2-4 days after agreement |
| **A2/J: fixed 10% / 90% allocation** | Partly correct. Ten percent is a configurable preference, not an immutable constant. Its formula uses an equivalent-user count; trips are then assigned across the recipient pool. It is NOT a guaranteed 90:10 split of trips or of actually affected people. | P1 define denominator and recruitment policy; shared with A/B |
| **B: new-user slider ineffective after accepted advanced counts** | Reproduced: 10% and 100% gave identical results. Explicit population targets short-circuit trip-derived recruitment. Current staging reuses snapshots without treating this slider as a population restaging trigger. | P1, 2-4 days with staged-contract regression tests |
| **D: stale users fields affect trips route** | Reproduced. Tab 2 staging already clears stale users for non-users routes, contrary to the report's blanket statement. Final/basic results input resolution still admits them; both handlers can run. Latest HUB has not comprehensively closed this path. | P1, 1-3 days including reverse route and Tab 4 override tests |
| **I: selecting a Tab 4 method changes the answer** | Not reproduced in the focused current lifecycle: results were identical. The setting still clears reference-default caches but does not clear retained Tab 3 snapshots. Broader click/back-navigation coverage remains needed. | P2 regression coverage, 0.5-1 day; fix only if reproduced |
| **F: convex users-route response** | Not reproduced as a complete size series. It cannot be diagnosed as a dose-response bug from changing user counts alone: different recipients, doses, lookup coverage and finite draws are involved. | P1 investigation combined with variance work, 1-2 days of setup |
| **H: changed people exceed n_ind because the frames differ** | The cited health diagnostic computes BOTH quantities from the same exposure frame; `n_changed_ind <= n_ind` there. Comparing against an original source size or UI total is a different question. Donor-copy counts need clearer labels. | P2, 0.5-1.5 days |
| **G: mode-share CF cells not editable** | Report itself says not retested. Source/API functionality does not prove the widget works. Keep as an unconfirmed browser regression, not a confirmed current blocker. | P2 test, 0.5 day; likely 0.5-2 days to fix if reproduced |
| **Healthy life years is a cumulative-incidence mistake** | The report misidentifies the upstream field. HM's `unhealthy` is a NET health-state transition, including death and remission. A separate cycle-0 initial-state bug is reproduced in HUB's HLY export reconstruction. | P1 before relying on absolute HLY exports, 0.5-1.5 days |
| **No seed or uncertainty machinery exists** | Incorrect for HUB/research workflow. Both versions accept seeds; 9002 can persist a seed in the profile. The existing variance QMD already has replicates, SD/bootstrap summaries and other experiments. Production UI still lacks a sampling interval. | P1 refresh research workflow, 1-3 days; production presentation separately 2-4 days |
| **Only long-term closed-cohort health behaviour** | Confirmed limitation; deliberately deferred, not a regression. Shorter reporting horizons do not implement a different cohort/recruitment model. | P3 methodology decision first; implementation likely multiple weeks |
| **Combined modes nearly additive** | A property of the reported example, not an invariant. Shared recipients and nonlinear health response allow non-additivity. Trip locking already prevents re-shifting a physical row. | P2 extend existing joint-mode tests, 1-2 days |

Effort estimates are engineering person-days including focused tests, not
promises. Related tasks overlap; do not add the estimates as independent projects.
P1 means resolve before interpreting route comparisons or affected exports as
validated appraisal results; P2 is follow-on reliability/transparency work.

## 5. Corrections Needed Before Using the Comparison Conclusions

### 5.1 Manchester's denominator

The currently bundled Manchester data contain **10,000 people**, **4,952
walkers** and **711 cyclists**. Those are the very same mode-user counts quoted
in the comparison, but it divides by 5,000:

- Walking prevalence is **49.52%**, not 99%.
- Cycling prevalence is **7.11%**, not 14.2%.
- There are **5,048 source non-walkers**, not approximately 50.

Unless the original run deliberately selected a different 5,000-person assessed
scope, its denominator and pool-exhaustion interpretation are wrong. Obtain the
saved scenario and runtime data identity before deciding which it was. Source
population, assessed population and the eligible new-AT pool are distinct counts.
This discrepancy invalidates the report's explanation of inevitable Manchester
donor exhaustion; it does not, by itself, prove its exported HALY values wrong.

### 5.2 Different recipients, not just different random seeds

The users route selects non-users of the target mode using population weights.
The trips allocator first recruits from people without ANY current active mode
in the assessed scope, normally topping up existing users of the target mode.
Those are different definitions of a new user and different sampling algorithms.
No active travel also does not mean no physical activity: sport and other activity
can remain. Recipient baseline MMETs must be measured, not inferred from mode labels.

The 10% preference multiplies `ceil(extra_trips / trips_per_user)`. It does not
directly divide the trips 90:10. At small increases, a few recruits can join a
large current-user recipient pool, so the implied trip share differs considerably.
The report's dose calculations and statements that this is always a 90:10 split
should therefore be treated as approximations, not the implemented contract.

Population category weights are also not a guarantee of an exact final category
distribution. The sampler multiplies per-row weights by category proportions;
the candidate pool composition still matters. Include target-versus-realised
distributions in the audit before calling the result a match to current users.

### 5.3 Healthy life years: wrong diagnosis, real separate issue

HM `scripts/aggregation.R` explicitly counts unhealthy as diseased OR dead,
then differences that state between cycles. Negative transitions permit recovery.
The packaged Leeds data contain 33,573 negative `unhealthy` transitions, providing
direct evidence against the report's no-recovery interpretation.

However, HUB `.results_amat_years_timeline()` removes cycle 0 before the cumulative
sum. In a minimal test, baseline unhealth 0.30 followed by +0.10 and -0.05 gives
healthy occupancy **0.90 and 0.95**, instead of **0.60 and 0.65**.
In the actual Leeds file, 4,776 of 5,000 people have positive cycle-0 unhealth.

Fix reconstruction to include the initial state, then filter the reported years.
Verify bounds and reconstruction against HM outputs. Equal REF/CF baseline offsets
may cancel from the absolute difference, so this finding does not imply the same
error in HLY gains, and it is not evidence that the separately calculated HALYs
are wrong. HLY and disability-weighted HALYs still need distinct definitions.

### 5.4 The AMAT comparison is not yet a validation benchmark

The reports explicitly leave recipient ages, per-user dose, outcome definitions
and cohort behaviour unmatched. They also quote **48.5** AMAT YLLs for the Leeds
+695 example in the summary, but **43.43** in the detailed 40-year table.
Reconcile the workbook/settings/export before interpreting either ratio.

Do not tune recruitment to make MIAMAT equal AMAT, or adopt an intervention-type
default, a 1.5-2x activity cap, or a default 50% alternative simply because the
report proposes it. Those are policy/model assumptions requiring justification.
Do not directly substitute disability-weighted HALYs for mortality-only YLLs in
an economic calculation without an explicit outcome valuation and discounting
contract. This assessment has not checked that external contract.

## 6. Proposed To-Do List

- [ ] **T1 / P1: establish reproducible comparison inputs.** Record package and
  UI commits, source-data identity, source/assessed REF/CF counts, horizon, seed,
  effective assumptions, supplied versus generated fields, and realised travel.
  Resolve Manchester's denominator and the inconsistent AMAT totals. Effort:
  0.5-1 day plus obtaining the original inputs/workbook.
- [ ] **T2 / P1: complete active-route input isolation.** Ignore stale Tab 2
  inputs on every entry point, including direct basic results. Preserve genuinely
  authoritative downstream person/trip targets. A blanket ban on the users or
  trips handler would break legitimate Tab 3/4 overrides. Effort: 1-3 days.
- [ ] **T3 / P1: preserve the accepted scenario across staging/results.** Default
  basic and advanced paths should not silently choose different recipients or
  doses. Make the new-user control update its derived population before Tab 3
  acceptance, while respecting later manual counts. Freeze the final accepted
  people contract; Tab 4 must not reverse-calculate it. Effort: 2-4 days.
- [ ] **T4 / P1: define and expose allocation semantics.** Decide new-to-mode
  versus new-to-any-AT, the percent denominator, candidate pool/weights, and dose
  assigned to current/new users. Keep induced trips a separate parameter. Show
  realised current/new users, trips per group, MMET increments and donor fallbacks.
  Leverage 9002's persisted assumptions rather than creating another storage path.
  Effort: 1-2 days for agreement/audit; 2-4 days for agreed implementation.
- [ ] **T5 / P1: refresh and extend the existing variance analysis.** Run the
  actual staged UI/HUB lifecycle as well as the low-level sampler; compare fresh
  sessions with route-switch/back-navigation runs. Start with 10 diagnostic draws,
  then 50-100 for selected small/threshold scenarios. Effort: 1-3 days setup plus
  runtime; this is an extension, not a new simulation framework.
- [ ] **T6 / P1 for HLY consumers: fix baseline state reconstruction.** Keep
  cycle 0 for reconstruction, exclude it only from reporting. Test baseline
  disease, remission, death and probability bounds against HM. Clarify HLY versus
  HALY labels rather than deleting a measure on the report's incorrect rationale.
  Effort: 0.5-1.5 days.
- [ ] **T7 / P2: add lifecycle invariants and precision checks.** No-op method
  switches, 100%/all-category refinements, accepted default tables, repeated Next,
  fresh versus reused sessions, all four modes and all four input units. Include
  integer conversion near exact boundaries: the probe reported 156 equivalent
  users for 695 / (695/155), indicating floating-point ceiling sensitivity.
  Effort: 1-2 days; overlaps T2/T3.
- [ ] **T8 / P2: make diagnostics use explicit denominators.** Separate unique
  source donors, appraisal records, REF/CF assessed people, changed people and
  copied records. Do not simply exclude copies from health results: copies are
  intentional appraisal records, but not independent evidence. Effort: 0.5-1.5 days.
- [ ] **T9 / P2: browser-check mode-share editing and assumptions controls.**
  Confirm values survive modal save/reopen and reach HUB. Repeat with distance,
  duration, e-bike and PT. Do not infer widget correctness from API tests.
  Effort: 0.5-1 day testing, fixes contingent on findings.
- [ ] **T10 / P2-P3: define production uncertainty and future cohort scenarios.**
  Separate a Monte Carlo interval from assumption sensitivity and HM parameter
  uncertainty. Only then decide UI presentation, seed averaging and a future
  short-term/open-population model. These are distinct work packages; cohort
  redesign is not required to fix present route/state bugs.

## 7. How to Separate Variance From Route Bugs

1. Create a small canonical scenario with fixed individual IDs, trip IDs,
   baseline activity and CF activity. Feed identical exposure to health calculation
   and verify route-independent results, with no sampling involved.
2. Compare route conversion against the same intended person/trip targets. Record
   realised activity, not just targets. Test users increases AND trip increases;
   they should only be expected to agree when the recipient/dose contract agrees.
3. Hold the scenario and source data fixed and vary seeds in fresh HUB instances.
   Retain recipient/trip identities or a robust hash to prove a new draw occurred.
4. Cross seed with a small set of explicit recruitment/dose assumptions. Plot
   within-assumption seed spread separately from between-assumption shifts.
5. Record total and per-person MMET change, age, baseline MMET, new/current mode
   status, outcome response, recipient count and donor-copy count. Aggregate
   MMET alone cannot explain who receives the health benefit.
6. Use absolute HALY deviations, relative deviations where the mean is not near
   zero, SD/IQR/quantiles and uncertainty in the SD. Paired differences are useful,
   but equal seeds do not guarantee identical samples across different algorithms.
7. Check small appraisals, increases/decreases, zero change with actual submitted
   REF/CF targets, restrictive categories, donor reuse, and combined-mode order.

The existing `sampling_variance_evaluation.qmd` already implements several of
these components. Its main experiment calls low-level CF functions directly,
so it does not test Shiny state or the complete staged lifecycle. Its no-change
case leaves the count target unset, rather than testing all explicit equal-target
UI pathways. Those are important coverage gaps.

Its cache uses a manually selected version and scenario filenames. Invalidate
old caches for this work and add code/data/input/seed identities before trusting
reuse. Its old weighted-trip terminology also needs updating: current
`.trip_weights()` returns one per row. The proposed precision experiment is no
longer a test of survey-weight conversion.

When repeating `build_results(seed=...)` on the same object, do not assume the seed
argument alone invalidates cached results. Use fresh instances or an explicit
refresh and verify changed selection fingerprints. Conditional health outcomes
are deterministic for fixed exposure and lookup tables; there is no fresh
health-model random draw in that conditional step.

## 8. Main Code Pointers

| Concern | Source locations / functions |
| --- | --- |
| All widget values marked filled | UI `utilites/appraisal_list_tools.R:1-23`; `server.R:153-204` |
| New-user slider rendering | UI `modules/tab3/tab3Server.R:378-404` |
| Inactive route cleanup at Tab 2 only | HUB `R/api_refinement_profile_defaults.R:245`, `.tab2_stage_input_values()` |
| Accepted snapshots and rescoping | HUB `R/api_refinement_profile_defaults.R:68`, `prepare_trip_refinement_profile_defaults()` |
| Final table targets / reconstruction | HUB `R/api_hub.R:859`, `.counterfactual_input_values()`; `build_counterfactual_data()` |
| Recipient selection and explicit-count precedence | HUB `R/counterfactual_data_apply_ui_values.R:459`, `:641`, `:1127` |
| Default spread weighting | HUB `R/reference_data_spread_functions.R:113`, `:275`; `R/counterfactual_data_sampling_functions.R:253`, `:456` |
| Single-shift lock and trip reassignment | HUB `R/counterfactual_data_apply_ui_values.R:1427` |
| HLY reconstruction | HUB `R/results_data_prepare.R:159`; HM `scripts/aggregation.R:275-332` |
| Changed-person diagnostic | HUB `R/counterfactual_data_apply_health_outcomes.R:468-484` |
| Donor identities and replication | HUB `R/population_donor_replication.R` |
| Refresh rules | HUB `R/shared_state_invalidation.R`; `R/api_hub.R:284` |
| Existing Monte Carlo study | HUB `docs/sampling_variance_evaluation.qmd:333`, `:472`, `:1620` |

Line numbers refer to inspected source snapshots and may move. HUB 9002 improves
assumption persistence, provenance and API visibility, but does not by itself
resolve the route isolation, accepted-population allocation or HLY initial-state
issues identified here.
