# External Review: Current Bugs, Route Differences and Sampling Variance

*Last content commit: 2026-09-10. Organized: 2026-09-11. Review/validation; conclusions retain their original scope.*

Original assessment: 9 September 2026. Status refreshed 10 September after
HUB dev `9796294`; UI dev remains `bd4f9c3`. This refresh changes documentation
only, not calculation, UI, or assumptions code.

## Current priorities

- **T2 completed in HUB dev (`89b3ba7`):** inactive Tab 2 volume fields are
  filtered at receipt and staging. This does not solve UI modal save/discard
  semantics. UI's installed 9001 archive does not yet contain the fix. The
  isolated full-app timeline test build initially lacked it; it now includes
  the backport, alongside the LY/HLY caller fix and 40-year timeline bounds.
- **T6 fixed, including caller:** `prepare_results_data()` now passes baseline
  state to LY/HLY reconstruction. Its regression checks HLY .60/.65 and LY
  .88/.85, while cycle 0 remains excluded from reported events and years.
  Earlier helper-only tests missed this integration gap.
- **T7 HUB checks implemented:** machine-precision-safe user ceilings and
  lifecycle regression tests across all four modes and Tab 2 units, including
  both distance and duration. Browser state/collector behaviour remains T9/T11.
- **T3/T4 remain deferred:** accepted-count/allocation policy and assumptions
  integration are not resolved by the timeline feature.
- **Scheme lifetime implemented (`9796294`):** build-up/decline scales annual
  health impacts, including zero-effect years. This is not a new dynamic cohort
  model. Variance comparisons must hold timeline settings constant.
- **T12 implemented in HUB:** an explicitly entered basic
  population total is binding for REF and CF. Accepted Tab 3 overrides become
  the binding downstream population targets. See Section 6 for the distinction
  between assessed people and the retained donor pool. T11's UI save/discard
  handling remains separate; see the [focused follow-up](basic_population_navigation_review_2026-09-10.md).

The version table and numerical probes below describe the original review
unless explicitly updated. No original PDF scenario has been reconstructed.

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
See [probe results](../../archive/2026-09-11/external_review_route_probes_2026-09-09.csv).

Three seeds are far too few for an uncertainty interval or a stability threshold.
They establish that draws vary. They do not establish that variability is small
for other scenario sizes, populations, constraints or routes.

## 4. Status of the Reported Observations

| PDF observation | Current assessment | Priority / indicative effort |
| --- | --- | --- |
| **A: user recruits weighted toward existing users' age/sex/PA** | Supported by current code. Reference mode-user distributions feed candidate weights even without an explicit advanced distribution edit. Important modelling assumption, not automatically a bug. The claim that it gives almost the smallest possible benefit is not established. | P1 decision and audit, 1-2 days; policy implementation 2-4 days after agreement |
| **A2/J: fixed 10% / 90% allocation** | Partly correct. Ten percent is a configurable preference, not an immutable constant. Its formula uses an equivalent-user count; trips are then assigned across the recipient pool. It is NOT a guaranteed 90:10 split of trips or of actually affected people. | P1 define denominator and recruitment policy; shared with A/B |
| **B: new-user slider ineffective after accepted advanced counts** | Reproduced: 10% and 100% gave identical results. Explicit population targets short-circuit trip-derived recruitment. Current staging reuses snapshots without treating this slider as a population restaging trigger. | P1, 2-4 days with staged-contract regression tests |
| **D: stale users fields affect trips route** | Originally reproduced in 9001; fixed at receipt/staging in HUB dev `89b3ba7`. Fresh-vs-reused trips/users/trips probe now agrees. UI save/discard state is a separate unresolved concern. | Completed in source; package deployment separate |
| **I: selecting a Tab 4 method changes the answer** | Not reproduced in the focused current lifecycle: results were identical. The setting still clears reference-default caches but does not clear retained Tab 3 snapshots. Broader click/back-navigation coverage remains needed. | P2 regression coverage, 0.5-1 day; fix only if reproduced |
| **F: convex users-route response** | Not reproduced as a complete size series. It cannot be diagnosed as a dose-response bug from changing user counts alone: different recipients, doses, lookup coverage and finite draws are involved. | P1 investigation combined with variance work, 1-2 days of setup |
| **H: changed people exceed n_ind because the frames differ** | The cited health diagnostic computes BOTH quantities from the same exposure frame; `n_changed_ind <= n_ind` there. Comparing against an original source size or UI total is a different question. Donor-copy counts need clearer labels. | P2, 0.5-1.5 days |
| **G: mode-share CF cells not editable** | Report itself says not retested. Source/API functionality does not prove the widget works. Keep as an unconfirmed browser regression, not a confirmed current blocker. | P2 test, 0.5 day; likely 0.5-2 days to fix if reproduced |
| **Healthy life years is a cumulative-incidence mistake** | Incorrect diagnosis of the HM field. The separate baseline-state omission is now fixed in helper and caller, with a top-level regression. | Fixed; retain HM reconciliation checks |
| **No seed or uncertainty machinery exists** | Incorrect for HUB/research workflow. Both versions accept seeds; 9002 can persist a seed in the profile. The existing variance QMD already has replicates, SD/bootstrap summaries and other experiments. Production UI still lacks a sampling interval. | P1 refresh research workflow, 1-3 days; production presentation separately 2-4 days |
| **Only long-term closed-cohort health behaviour** | Scheme build-up/decline is now implemented as annual outcome scaling. Dynamic exposure history, cohort entry/exit and residual health benefits remain outside this approximation. | Lifetime curve done; cohort redesign remains P3 |
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

Originally, `.results_amat_years_timeline()` removed cycle 0 before the cumulative
sum. The helper was fixed first, but `prepare_results_data()` still removed
that cycle before calling the export builder. In the pre-fix top-level test,
baseline unhealth 0.30 followed by +0.10 and -0.05 gives
healthy occupancy **0.90 and 0.95**, instead of **0.60 and 0.65**.
In the actual Leeds file, 4,776 of 5,000 people have positive cycle-0 unhealth.

The caller integration is now fixed: reconstruction receives the initial state,
then filters the reported years. A top-level regression checks both LY and HLY.
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
- [x] **T2 / P1: complete active-route input isolation (HUB dev).** Ignore stale Tab 2
  inputs on every entry point, including direct basic results. Preserve genuinely
  authoritative downstream person/trip targets. A blanket ban on the users or
  trips handler would break legitimate Tab 3/4 overrides. Implemented in
  `89b3ba7`; installed UI package and UI save/discard behaviour are separate.
- [ ] **T3 / P1: preserve the accepted scenario across staging/results.** Default
  basic and advanced paths should not silently choose different recipients or
  doses. Make the new-user control update its derived population before Tab 3
  acceptance, while respecting later manual counts. Freeze the final accepted
  people contract; Tab 4 must not reverse-calculate it. Effort: 2-4 days.
  **HUB final-results tests now implemented:**
  `tests/testthat/test-t3-final-results.R` uses fixed travel records linked to
  eight packaged HM identities and runs real health lookup/aggregation.
  Twenty unchanged-table scenarios (four modes, users/trips/distance/duration/
  mode shares) pass, including staged versus final person-level MMET deltas,
  repeated builds, accepted counts, and Tab 4 trip overrides without changing
  person membership. Manual Tab 3 reduction from eight to six retains totals
  and two walking users but FAILS exact CF membership: staged person 735482 is
  replaced by 1963634 at results reconstruction, both with six and nine CF trips.
  This was the pre-fix reproduction. The accepted-snapshot finalizer now fixes
  those identity failures without re-running recruitment. The larger six-case
  audit now has zero person or walking-member replacements, and unchanged
  staged/final activity totals agree. HUB cohort preservation is implemented;
  the wider T3 UI control-refresh/browser work remains open.
  Source travel is a controlled fixture, not those people's observed behaviour.
  Browser wiring and the new-user control remain outside this HUB test boundary.
  **Realistic-size check confirms the defect:** observed Leeds subsets of 500
  and 2000 people, reduced to 375/1500 through Tab 3, replace 22-24% of accepted
  CF members during final reconstruction across three seeds each. Counts agree.
  See [larger cohort audit](../../archive/2026-09-11/t3_cohort_audit.md) for results and the HUB-only
  repair plan. This is not a measured percentage error in health benefits.
- [ ] **T4 / P1: define and expose allocation semantics.** Decide new-to-mode
  versus new-to-any-AT, the percent denominator, candidate pool/weights, and dose
  assigned to current/new users. Keep induced trips a separate parameter. Show
  realised current/new users, trips per group, MMET increments and donor fallbacks.
  Leverage 9002's persisted assumptions rather than creating another storage path.
  Effort: 1-2 days for agreement/audit; 2-4 days for agreed implementation.
- [x] **T5: matched-route diagnostic benchmark.** Completed the agreed fixed-
  population comparison of users/trips inputs, all four modes where source
  evidence permits, basic/advanced staging, and 10 diagnostic sampling draws.
  The broader original variance/lifecycle scope is tracked separately in T5b.
  A matched-snapshot pilot is now implemented in `docs/current/validation/route_benchmark.qmd` and
  `inst/workflows/dev_route_benchmark.R`: one fixed population, explicit car-to-AT
  switches, users-only/trips-only reconstructions, normal and benchmark-informed
  completion assumptions, basic and advanced staging, and repeated seeds.
  This is a controlled diagnostic, not the complete browser/final-results
  lifecycle requested above. Detailed profiles, exposure records and source/code
  fingerprints accompany the report. Source-sample uncertainty is held fixed.
  First completed run: 500 Leeds people, 10 seeds, 560 successful reconstructions.
  Matched basic/advanced staging HALYs were identical. Existing-e-biker scenarios
  were unavailable because the sample had no native e-bikers. No extra person or
  trip rows were needed. A reporting-only data.table compatibility bug in T8
  was fixed and regression-tested during the pilot.
  Follow-up: 210 walking users were counted from individual activity, but only
  197 owned observed walking trips. All 13 additional people have PT access
  walking only: 197 walking-trip owners + 33 PT-access owners - 20 overlapping
  owners = 210. This is a mode-definition mismatch, not random loss. See
  [walking/PT audit](../../archive/2026-09-11/walking_pt_definition_audit.md) for the agreed rule:
  trip categories remain separate, but PT walkers qualify as existing recipients
  of additional walking trips. The eligibility change has focused regression
  coverage. The original 560-run report predates that change.
  Current-code refresh: 112 successful reconstructions (two seeds) now run both
  workflows through `Hub$build_results()` with canonical persisted assumptions.
  Walking, cycling and e-biking match between basic and advanced. PT does not:
  advanced generated Tab 4 defaults become zero despite REF/CF trip targets
  of 85/94, and final CF trips become zero. Maximum paired HALY difference is
  1.429874. This is a correctness finding, not an estimate of sampling variance;
  resolve it before treating PT route comparisons as valid.
  See `docs/archive/2026-09-11/route_benchmark.html` for the completed diagnostic report.
- [ ] **T5b: expanded variance and integrated lifecycle verification.** The
  matched benchmark has been refreshed after PT eligibility changes and now
  includes final `Hub$build_results()` reconstruction. A new variance runner
  compares repeated whole appraisals with repeated CF allocation conditional
  on one fixed REF, keeping canonical assumption values/provenance unchanged.
  Completed diagnostic: 180 appraisals, ten seeds, assessed sizes 100/500/1500,
  walking/cycling/combined; no failures or warnings. The report is refreshed in
  `docs/archive/2026-09-11/sampling_variance_evaluation.html`. Sixteen analysis-helper assertions pass.
  The report now verifies and displays mode-specific REF/CF weekly trip counts
  and increments across all saved runs. The 100-person cycling pilot adds only
  five trips/week, so population-only comparisons overstate comparability with
  walking. Health-relative SD must not be interpreted as trip-count variability.
  A separate full-source (5,000 people) follow-up now tests +100/+500/+1,000
  weekly cycling trips: 60 successful appraisals, ten seeds per scenario/path,
  no warnings, exact agreement between paths and matching Tab 4 trip defaults.
  HALY relative SD is 15.6%/6.7%/5.6%; do not pool the duplicate path checks as
  independent draws. See `docs/archive/2026-09-11/cycling_trip_scale_variance.pdf` and `.html`.
  Remaining: resolve the PT finding above, increase to 50-100 draws for selected
  small/threshold scenarios, and test browser route switching/back-navigation
  when UI changes are integrated (T9/T11). These are conditional sampling
  diagnostics, not source-data or health-model uncertainty intervals.
- [ ] **T5c: preserve PT access walking in staged default views (high priority).**
  A real-data replay retains 85 REF / 94 CF PT access-walking trips in staged
  data but loses their walking activity in `materialize_appraisal_scope()`.
  The walking-scope pass zeros shared component columns; PT's later pass cannot
  restore them. This makes Tab 4 defaults zero and changes advanced final results.
  Add a regression with distinct walking/PT scope masks and numeric NTS modes,
  preserve both modes' activity, then rerun the matched-route benchmark.
  Expected scope: narrow HUB-only fix plus focused and real-data tests; no UI
  schema change indicated. Not fixed as part of the variance runner refresh.
- [x] **T6: baseline state reconstruction, including the results caller.**
  Unfiltered health rows feed LY/HLY reconstruction; ordinary event reporting
  still excludes baseline. Regression calls `prepare_results_data()` and checks
  disease, remission, death, REF/CF occupancy and exclusion of cycle 0. Broader
  reconciliation with HM remains part of continuing verification.
- [x] **T7 / P2: HUB lifecycle invariants and precision checks.** Both equivalent
  user ceilings now snap only machine-precision noise near positive integers:
  `695 / (695/155)` gives 155, while genuine fractional counts still round up.
  Tests cover all four modes and users/trips/distance/duration/mode-share routes:
  repeated builds, fresh/reused Hub instances, reverse route traversal,
  100%/all-age/all-PA no-ops, and accepting/re-entering staged advanced snapshots.
  Tests explicitly supply source data at the API boundary; they do not establish
  browser save/discard, reload, or installed-package correctness (T9/T11).
  E-bike conversion now prefers valid native observations for each measure,
  using cycling and proxy factors only as fallback. Native-only, proxy-only,
  mixed and invalid/missing evidence are tested for distance and duration.
  Lifecycle fixtures no longer need artificial cycling donors. The full HUB
  suite passes with the existing expected donor-reuse warning.
- [x] **T8 / P2: make diagnostics use explicit denominators.** Shared
  `population_diagnostics` now accompanies counterfactual and results reports:
  retained/assessed records, unique donors, copied records, and distinct net/any
  mode MMET-change counts across the assessed union. Results refresh these from
  final snapshots. Counts are unweighted and independent of Tab 5 filters;
  copies remain in health calculations. README and methodology document the
  definitions. UI presentation is separate, not part of this HUB-only task.
- [ ] **T9 / P2: browser-check mode-share editing and assumptions controls.**
  Confirm values survive modal save/reopen and reach HUB. Repeat with distance,
  duration, e-bike and PT. Do not infer widget correctness from API tests.
  Effort: 0.5-1 day testing, fixes contingent on findings.
- [ ] **T10 / P2-P3: define production uncertainty and future cohort scenarios.**
  Separate a Monte Carlo interval from assumption sensitivity and HM parameter
  uncertainty. Only then decide UI presentation, seed averaging and a future
  short-term/open-population model. These are distinct work packages; cohort
  redesign is not required to fix present route/state bugs.
- [ ] **T11 / P1, UI boundary: basic population modal and save/discard state.**
  Before staging the modal, synchronize the current route/modes with the saved
  volume inputs. Prevent generic Next collection from committing discarded or
  stale modal values. Preserve genuinely saved population overrides; provide
  an explicit way to return to inferred counts. This needs concise UI work, not
  an assumptions rewrite. Controlled observer/collector probes reproduce the
  stale-route and overwrite mechanisms; full browser navigation is unverified.
- [x] **T12 / P1: enforce explicitly entered basic population.**
  An explicitly entered basic total is binding for both REF and CF. It counts
  assessed person records, not trip rows or every retained source donor. The
  source remains available for donor patterns and reuse; its size is not an
  appraisal ceiling. An inferred total is not an explicit user constraint.
  In advanced mode, accepted Tab 3 totals and mode-user counts supersede the
  initial suggestions and remain binding through Tab 4 and results.
  `R/appraisal_population_contract.R` validates explicit totals and mode counts,
  reserves donors without expanding REF, and sets the accepted CF boundary before
  allocation. Fixed-population user allocation cannot recruit outside it.
  The former reproduction (total 3, REF users 2, CF users 4) now gives an input
  error instead of silently producing populations 3 and 4. Explicit zero total
  with positive users is also contradictory; zero REF activity without an
  explicit total still uses the CF-based population fallback.

  Implementation/acceptance checks:
  - Keep explicit basic REF/CF totals unchanged during CF allocation. New mode
    users must be accommodated within that assessed population, not silently
    added on top. Audit fallback behaviour when its observed patterns are sparse.
  - Reject contradictory explicit counts with an actionable input error:
    four cyclists cannot fit in three people. Do not silently clamp a user's
    mode count or increase their total.
  - Allow cross-mode overlap: walking and cycling counts need not sum to the
    total, and a person may belong to both groups.
  - Distinguish explicit overrides from generated defaults and preserve the
    existing zero-REF-volume fallback. Zero active users is not zero population.
  - Test direct basic results, advanced staging/results, multiple modes, donor
    reuse above source size, and explicit Tab 3 overrides. A final count check
    alone is insufficient: the allocation must respect the contract throughout.

### Suggested Next Small Work Packages

1. **T8 completed: explicit diagnostic counts.** Available in existing HUB
   reports without changing sampling or assumptions; UI presentation can follow
   later. Regression coverage includes overlapping mode changes, copies,
   reserves, empty/missing data, and refreshed results-report counts.
2. **T12 completed in HUB: binding population totals.** Boundary enforcement
   and validation are implemented separately from the wider T3 review. UI
   modal save/discard handling remains T11; test the integrated UI as well.
3. **T7 HUB work completed:** precision fix and cross-mode/unit lifecycle
   regression coverage. Browser integration verification remains separate.
   **E-bike fallback correction completed:** native distance/duration evidence
   now precedes cycling proxies, with proxy factors limited to fallback values.
   No UI schema change is needed.
4. **T3: split before implementation.** Start with tests showing where accepted
   population targets change between staging and results. Updating the new-user
   control and freezing the complete accepted scenario is a larger follow-up.
   Final-results coverage now exists in `test-t3-final-results.R`. It confirms
   an identity mismatch after manual population reduction despite correct counts.
   Accepted-cohort reconstruction is now fixed in HUB and those assertions
   pass. UI control-refresh/browser verification remains separate.
5. **T9: coordinate with UI assumptions work.** A focused manual/browser test
   pass is useful, but this is not a HUB-only fix. Test the intended integrated
   branch; avoid diagnosing a known older installed package as current code.

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

The legacy low-level experiment has been archived under `docs/archive/`.
`sampling_variance_evaluation.qmd` now consumes fresh whole-appraisal and fixed-REF
runs through the current staged/final-results lifecycle. Its companion workflow
freezes canonical assumptions and checks their effective-value/provenance signature.
It saves input profiles, seeds, source/code/data fingerprints and person-level
exposure diagnostics. No old caches are reused. Explicit no-change invariants
are covered by HUB regression tests, not a separate factorial arm of this study.
Browser state, higher-repetition precision estimates and source-weight validity
remain separate limitations. Current trip counts are rows, not weighted totals.

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
| Inactive route cleanup at receipt and staging | HUB `R/tab2_input_conversion.R`, `.active_tab2_input_values()`; `R/api_receive_appraisal_inputs.R`; `R/api_refinement_profile_defaults.R` |
| Accepted snapshots and rescoping | HUB `R/api_refinement_profile_defaults.R:68`, `prepare_trip_refinement_profile_defaults()` |
| Final table targets / reconstruction | HUB `R/api_hub.R:859`, `.counterfactual_input_values()`; `build_counterfactual_data()` |
| Recipient selection and explicit-count precedence | HUB `R/counterfactual_data_apply_ui_values.R:459`, `:641`, `:1127` |
| Default spread weighting | HUB `R/reference_data_spread_functions.R:113`, `:275`; `R/counterfactual_data_sampling_functions.R:253`, `:456` |
| Single-shift lock and trip reassignment | HUB `R/counterfactual_data_apply_ui_values.R:1427` |
| HLY reconstruction | HUB `R/results_data_prepare.R:159`; HM `scripts/aggregation.R:275-332` |
| Changed-person diagnostic | HUB `R/counterfactual_data_apply_health_outcomes.R:468-484` |
| Donor identities and replication | HUB `R/population_donor_replication.R` |
| Refresh rules | HUB `R/shared_state_invalidation.R`; `R/api_hub.R:284` |
| Current Monte Carlo study | HUB `docs/current/validation/sampling_variance_evaluation.qmd`, `inst/workflows/dev_sampling_variance.R`; previous study archived under `docs/archive/` |

Line numbers refer to inspected source snapshots and may move. HUB 9002 improved
assumption persistence, provenance and API visibility; later HUB dev fixes route
isolation and adds the lifetime curve. The HLY initial-state caller is now fixed;
accepted-population allocation remains open as described above.
