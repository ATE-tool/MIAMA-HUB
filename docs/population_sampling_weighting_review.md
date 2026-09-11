# Population sampling: eligibility, PA preferences and configuration

Assessment of HUB dev and the combined assumptions test backend, 11 September
2026. This describes current code, not a proposed matching algorithm already
implemented. No sampling behavior was changed for this review.

## What physical activity means

PA is the candidate person's weekly marginal MET-hours: `.spread_pa_values()`
uses `mmets`, then `mmet_wkhr`, otherwise a sum of walking, cycling and sport
time multiplied by their intensities. It is not just the activity of the target
travel mode. Selection reads the supplied person table before assigning that
user change; a reused CF snapshot is not necessarily an untouched baseline.

Two separate mechanisms must not be called simply "matching":

| Mechanism | What happens | Does it exclude people? |
|---|---|---|
| Basic age/PA category selection | Restricts eligible donor identities in REF and CF scopes. | Yes. A hard category filter is not relaxed by the zero-weight fallback. |
| Advanced age/sex/PA distribution target | Supplies relative probabilities when a CF user-status sampler actually runs. | Zero category weights suppress candidates initially, but shortfalls can admit zero-weight rows. No exact quotas. |
| Trip sampling | Uses trip distances, source modes, ownership and locks. | Separate eligibility/weights; no direct call to the person PA-weight function. |

## Whose distribution supplies the target?

`reference_pa_spread_bars()` normally measures current users of the selected
mode in the REF data passed to it. If unavailable, extraction tries a mode proxy
(cycling for e-bike), the assessed population, and then the geographic source
population. Thus it is not always the entire source population and is not
normally the PA distribution of eligible non-users.

`derive_counterfactual_spread_values()` copies the REF bars when sliders are
unchanged, or redistributes them around the supplied mean/sex target. The direct
HUB results route calls this even without an explicit PA edit. When those bars
reach `cf_population_sampling_target()`, their PA marginal supplies weights.
This can favour new users resembling current mode users in pre-change PA.
It does NOT set their resulting PA to that level.

Separately, newly recruited users can receive a weekly mode-activity amount
drawn from observed users of that mode. That activity-dose donor assumption is
independent of PA-based selection of recipients. Disabling PA preference should
not silently disable activity-dose assignment, new-user counts or induction.

## Route differences: not applied always

| Path | Current behavior |
|---|---|
| Tab 2 -> Tab 3 staging | `.tab2_stage_input_values()` drops downstream spread inputs; it does not derive default CF PA bars here. No automatic mode-specific PA preference is added by this staging step. |
| Tab 3 accepted unchanged | Existing REF/CF snapshots are retained; there is no new weighted person draw. |
| Tab 3 changed advanced mean/distribution | Triggers `.rescope_staged_snapshot()`, which calls the reference scope sampler. That sampler applies category eligibility and count/ownership requirements, but not `cf_individual_candidate_weights()`. A scalar PA mean alone is not converted into PA weights on this route. |
| Advanced results with staged snapshots | `.finalize_staged_appraisal()` preserves accepted people and runs trip handlers with `preserve_user_scope=TRUE`. It does not repair the missing person-distribution targeting by recruiting again. |
| Basic/direct results without staged advanced finalization | `Hub` derives CF spread bars and the user-change handler can use them. Weights matter only if people are actually selected for a nonzero user-count change. |
| Low-level direct sampler call | Weights depend on the supplied targets; absent targets mean unit weights. No automatic REF matching is performed inside the weight function itself. |

**Consequently, the dynamic cards' statements that saved PA targets inform
sampling weights are too broad for staged advanced appraisals.** A changed PA
slider can trigger re-scoping without its requested mean steering that draw.
This must be resolved before presenting advanced PA targeting as fully wired.
It is not evidence that the advanced route is universally too restrictive.

## How the weights behave

`cf_individual_candidate_weights()` multiplies sex, age and PA factors when
available. Each factor is the target category proportion, not target proportion
divided by the category's availability in the donor pool. Marginals are multiplied;
this is not joint-distribution calibration.

For one draw, 80 low-PA and 20 high-PA candidates with weights 0.8 and 0.2 give:

```
P(low PA) = 80 * 0.8 / (80 * 0.8 + 20 * 0.2) = 94.1%
```

So a target resembling current users can amplify a common candidate category.
For multi-person sampling without replacement, composition also depends on the
sample fraction and depletion. Neither the target mean nor its histogram is
guaranteed to be reproduced.

The same weight helper is used for recruiting non-users and choosing current
users who stop that mode. The removal path does not invert weights to preserve
the target distribution among those remaining. Hard-category removal selection
also has its own inside/outside logic. This is another reason to specify whether
a target describes new users, changed users, or all final CF users.

If all weights are zero, selection falls back to equal probabilities. If fewer
positive-weight candidates exist than the required non-replacement sample, all
positive candidates are included and the remainder is sampled from zero-weight
eligible candidates. These relaxations are recorded, but they do not override
explicit age/PA exclusions or person contracts.

## What can be configured now?

Config defines age/PA categories and cut points (`spread`,
`population_refinement`), not an enabled-variable list for person weighting.
The only accepted named strategy is `random_sample_as_is_rows`; despite its
name, it can use weights. There is no supported "turn PA weighting off" switch.
Deleting a PA field manually is unreliable because HUB can reconstruct it from
REF bars. Equal category weights are a diagnostic workaround, not a clean policy.
The AMAT/TAG/MIAMA preset currently selects fallback assumptions, not this policy.

## Recommended next implementation

Small HUB-only configuration/API addition, with a separate staged-route fix:

1. Separate hard eligibility from optional distribution preferences. Keep user
   category exclusions binding even when automatic weighting is disabled.
2. Add an explicit variable list, such as `automatic_person_weights =
   c("sex", "age", "pa")`, supporting an empty list or omission of PA. This is
   proposed syntax, not an existing config field.
3. Define automatic target origin separately: current mode users versus eligible
   recipients. Prefer eligible recipients/no PA preference for an exploratory
   comparison rather than assuming recruitment mirrors current cyclists.
4. Keep explicit user refinements distinct from automatic defaults; an automatic
   PA-off setting must not silently discard a user-specified PA target.
5. Decide target audience (new users only, all changed users, or all final users)
   and baseline timing. Implement targeting at the appropriate Tab 3 boundary,
   preserving accepted person/trip counts rather than resampling at results.
6. Retain policy and provenance in `appraisal_model_parameters`, update card
   descriptions from the effective policy, and record variables actually used.
7. Test fixed-seed comparisons: no weights, age/sex only, age/sex/PA, explicit
   low/high PA targets, recruitment/removal and staged versus direct routes.

Adding variable switches is narrow. Correctly wiring advanced PA targets and
choosing/calibrating their semantics is a moderate change with higher scientific
risk. Do not combine that with purpose removal or distance-checkbox redesign.

## Verification and code pointers

- Read both dev and current combined-backend implementations; the relevant
  person-weight/staging architecture is shared.
- Ran an isolated 20-person staged REF re-scope with fixed counts/seed and PA
  scalar targets 2 versus 30: identical selected person masks. The scalar alone
  yielded NULL PA category proportions. This is an isolated route check, not
  an end-to-end browser or health-impact test.
- Ran the candidate-weight function on the 80/20 fixture: 0.9411765 low-PA
  single-draw probability.
- `R/reference_data_spread_functions.R`: PA measurement, REF bars, derived CF bars.
- `R/reference_data_extract_reference_ui_values.R`: mode/proxy/population fallbacks.
- `R/counterfactual_data_sampling_functions.R`: filters, weights, shortage fallback.
- `R/counterfactual_data_apply_ui_values.R`: recruitment/removal call sites.
- `R/api_refinement_profile_defaults.R`: staging and reference re-scoping.
- `R/finalize_staged_appraisal.R`: accepted population protection.

## Deferred UI tasks

- Separate PR: deactivate purpose-related controls/text after checking which
  fields still affect processing. Purpose metadata can remain in source data.
- Replace the basic trip-distance slider with category inclusion checkboxes;
  agree categories and eligibility semantics before implementation.
- Make the review cards describe actual applied weights, not merely a saved
  target; the staged advanced wiring gap takes priority over broader polish.
