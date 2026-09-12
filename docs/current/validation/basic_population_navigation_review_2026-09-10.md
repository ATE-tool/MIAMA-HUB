# Basic population modal and Tab 2 navigation

*Last content commit: 2026-09-10. Organized: 2026-09-11. Review/validation; conclusions retain their original scope.*

Assessment of 10 September 2026, updated after the targeted HUB fixes below.
The UI modal/navigation findings remain assessment-only; assumptions are unchanged.

## Runtime distinction

| Runtime | Source | Inactive Tab 2 volume isolation fix |
|---|---|---|
| HUB dev | `9796294`, includes `89b3ba7` | Present |
| Normal UI dev | UI `bd4f9c3`, installed HUB 9001 from `2b45a09` | Absent |
| Full-app timeline launcher | `/private/tmp/MIAMA-HUB-scheme-app-test`, based on `2b45a09` with lifetime feature and targeted fixes | Present after follow-up backport |

The isolated test build deliberately retains UI dev's older assumptions
contract. It is not the whole of latest HUB dev. The stale-input fix was missing
during the initial assessment; it is now backported, along with the LY/HLY caller
fix and 40-year bounds. Normal UI's installed package is unchanged.

## What is wired correctly

- The modal is offered for basic workflow and non-users units. Users inputs
  already specify mode-user counts, so that route does not show it.
- On opening, `tab2Server.R` calls `Hub$build_refinement_profile_defaults()`.
  This is the same staging API that initializes advanced Tab 3.
- HUB estimates population from REF mode volume relative to source mode volume,
  pooling mode-implied estimates by observed baseline volume. A zero REF can use
  the CF estimate, with source-population fallback when evidence is unavailable.
  A mode share alone does not identify population without a volume denominator.
- The same staged REF/CF snapshots supply basic and advanced default fields.
- Modal Save sends the basic total and selected modes' REF/CF user fields via
  `miama_modal_inputs` into the profile. Basic values are read by HUB sampling;
  they are not merely display fields.
- Supplied trip targets still constrain trips when the user specifies mode-user
  counts in the population modal. This changes the allocation across people,
  rather than granting permission to overwrite the trip target.

Focused HUB probe: six source people, three walkers, three walking trip rows.
Equivalent source-volume requests of two REF users/trips/km produce an inferred
four-person REF population in both basic and advanced. Tested users, trips,
distance and mode-share formats, for walking with seed 2. Each format's basic
and advanced results agree before optional overrides. This is not a full
all-modes/browser matrix or a separate duration-subroute test.

With explicitly entered basic total 3, REF users 2, CF users 3, and trips 2/3,
HUB produces populations 3/3, mode users 2/3 and trip-plot values 2/3.
Equal volume formats do not assert equal user growth: in this small probe the
users route specifies three CF walkers, whereas trip-derived routes retain two.
This is the previously identified recipient/allocation distinction, not a
basic-versus-advanced population-estimation discrepancy.

## Confirmed concerns

### 1. Modal opens from a potentially stale profile

The population-modal observer stages `mdata$profile` without first synchronizing
the live Tab 2 route/modes. Saving a data-entry modal stores its visible values,
not necessarily the outside `at_data_unit` selector. Consequently, the saved
volume fields and saved route selector need not describe the same state.

A controlled `shiny::testServer()` probe of the actual Tab 2 observer, with HUB
stubbed only to capture its argument, submits saved route `users` while the live
route is `trips`. The modal may therefore show stale or inappropriate estimates.
This needs a UI boundary fix, not a change to the population-estimation formula.

### 2. Generic Next collection can override modal Save/Discard semantics

`update_all_appraisal_inputs()` iterates over all registered Shiny input IDs
that exist in the profile. It does not distinguish visible inputs, saved modal
inputs, or a value left by a modal closed without saving.

Controlled collector probe: saved CF trips 3, retained browser input 2, no Save
event. The next collection stores 2. This establishes the overwrite mechanism;
it does not reproduce the exact original browser sequence or prove the registry
state after every possible modal removal/recreation. A modal cancel/reopen/Next
browser test is still required. Hidden inputs also become explicit filled
values, which can unintentionally freeze generated basic population estimates.

Do not solve this by filtering every hidden input indiscriminately: legitimately
saved modal values must persist. Define which fields are committed on modal Save
and which are collected from live non-modal controls on Next.

### 3. The shared fixed-total promise is not enforced

The basic modal says the same fixed population is used for REF/CF and mode counts
cannot exceed that population. But the general CF recruitment code can add
eligible source non-users to `cf_in_scope` when needed.

Reproduced in current HUB: explicit basic total 3, REF walking users 2, CF users 4
(and enough trip volume) produces REF population 3 and CF population 4, rather
than rejecting/reconciling the request. There is no source-population ceiling
being proposed here: the question is whether the user's explicitly entered total
is binding, distinct from an inferred REF scope. Clarify that rule before changing
recruitment. More complex multimode/constraint cases also need tests.

## Equal REF/CF trips after navigation

**Not reproduced in HUB dev.** A fresh trips case and a trips -> users -> trips
sequence on one Hub, retaining stale users fields, both return walking trip
counts 2 REF / 3 CF with seed 2. Current active-route filtering works in this
controlled case.

Tab 5's trip plot reads `mdata$results$results_data`; HUB constructs its trip
distribution from scenario scope flags and active-mode trip evidence, not
directly from unscaled source defaults. Plain back-navigation hides later tabs;
the navigation observer itself does not reload source defaults or rewrite Tab 2
inputs. Subsequent Next/modal rendering/collection can still alter state.

The plot and other Tab 5 outputs are bound to button/filter events while the
result object is stored in a plain environment. Output refresh ordering is worth
testing, but a stale-plot race has NOT been reproduced here.

Equal trip counts can legitimately coexist with health changes if the changed
inputs alter duration, recipients, or activity per trip. They are not legitimate
for an unchanged selected mode whose explicitly authoritative REF/CF trip
targets differ, absent a documented target reconciliation.

For a recurrence retain: exact runtime/commit, route, modal Save/Cancel sequence,
the submitted result `profile`, `plot_data$trip_mode_distribution`, selected plot
modes and `counterfactual_report`. Those distinguish overwritten inputs, stale
rendering and a correct equal-count/different-exposure result.

## Next work without UI dependencies

1. Completed: backport active-route isolation to the compatible full-app test
   build. Normal UI's package still awaits coordinated integration.
2. Completed: HLY/LY baseline handling in top-level result preparation. The
   caller now passes baseline-inclusive rows, with a top-level regression.
3. Extend HUB lifecycle and integer-rounding invariants, then refresh the variance
   analysis with runtime, inputs, seed and timeline recorded for every run.

The HLY proof calls `prepare_results_data()` with baseline unhealthy .30,
then +.10 and -.05. Before the fix, reference HLY values were .90/.95; they now
correctly equal .60/.65. The helper-only test had missed this integration gap.
Baseline death similarly affects absolute LY levels. Equal baseline offsets may
cancel from gains; this is not evidence that the independently computed HALYs
have this error.

Local reproducible probes: `/private/tmp/review-basic-population.R` and
`/private/tmp/review-ui-input-state.R`. These are synthetic fixtures and Shiny
server tests, not a recreation of the original PDF or an automated browser run.
