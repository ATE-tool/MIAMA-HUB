# Tab 3 and Tab 4: summaries, assumptions and method inventory

**Status: proposed card coverage for discussion.** This is not a claim that the
full set of rows below is already implemented in UI. Small display/provenance
fixes are separate from the proposed summary redesign.

## 1. A simple rule

- **Summary: what this appraisal specifies.** Show the current REF/CF table
  counts, then only applicable refinements that the user actually changed.
  For a saved distribution refinement, show its brief target indicator(s), not
  the full default distribution or every untouched slider.
- **Assumptions: how sampling completes that specification.** Show effective
  completion parameters and concise rules, including which reference
  distribution supplies the default sampling weights. State the source and
  whether a parameter is user-provided. Do not repeat an input value already
  summarized above; explain its meaning or precedence instead.
- **Sampling audit: what was actually achieved.** Requested and realized counts,
  distribution summaries and fallback warnings are separate from the inputs.
  A target mean is not a guarantee of an identical realized mean.
- **Full method/report inventory: exposure and health calculation assumptions.**
  Include marginal intensity, health-model inputs, time profile, aggregation,
  units and reproducibility settings here. MET/MMET intensity is not a Tab 4
  trip-sampling assumption.

Being visible or `is_filled = TRUE` does not by itself mean a refinement changed:
mounted controls can be collected unchanged. Test applicability, saved state,
and a difference from the generated starting suggestion at the input's display
precision. Canceled modal drafts must never qualify. Inline table edits are
visible immediately, but become the next stage's contract on Next; a report
must use the frozen completed appraisal, not later drafts.

## 2. Proposed card coverage

`*` means a mode suffix (`walk`, `bike`, `ebike`, `pt`). Counts are shown even
when unedited because they define the appraisal; the changed-only rule applies
to the additional refinement indicators.

| Tab / item | Summary: what to show | Assumptions: explanation or default | Canonical fields / evidence |
|---|---|---|---|
| 3: population and users | REF and CF total people, and users by mode, in explicitly labelled columns. | How Tab 2 supplied or estimated these counts. Mode memberships overlap; their sum is not unique people. Final Tab 3 people remain fixed through Tab 4. | `pop_total_{ref,cf}_advanced`, `pop_number_{ref,cf}_*_advanced`; staged person contract. |
| 3: basic scope filters | Changed percentage or included/excluded age/PA categories, plus resulting counts. Omit an unchanged all-category selection. | Filters restrict eligible people; percentage/category refinement applies to both staged REF and CF. These are not the advanced distribution weights. | `pop_refine_method`, `pop_target_percent`, `pop_target_age_groups`, `pop_target_pa_groups`. |
| 3: age and sex distribution | Saved changed target mean age and male percentage, by mode. Label these as targets. | Without edits, use the staged REF age/sex distribution; identify a source-population fallback if needed. With edits, category weights favor the requested distribution among eligible candidates, not exact quotas. | `pop_spread_age_mean_cf_*`, `pop_spread_sex_prop_cf_*`, `pop_spread_bars_{ref,cf}_*`. |
| 3: baseline physical activity | Saved changed target mean weekly MMET-hours; include sex target only when operative. | Weights favor people with the specified baseline PA, not a directly prescribed PA increase. The PA-panel sex input is a fallback when no age/sex target supplies it. | `pop_spread_pa_mean_cf_*`, `pop_spread_pa_sex_prop_cf_*`, `pa_spread_bars_ref_*`. |
| 3: current versus new users | Changed preferred new-user percentage, only on routes where it is used. | Explicit user counts take precedence. The preference helps allocate an inferred increase between current and recruited users; realized shares can differ under feasibility constraints. | `assump_new_user_percent`; `counterfactual_report$changes` allocation diagnostics. |
| 3: activity per person | An explicitly changed completion rate may be identified as an override; avoid repeating it in two places. | Trips/user/week links trip volume and users. New-user activity uses observed donor patterns with applicable mean-duration assumptions; it is not a uniform lowest-quintile allocation. PT walkers can qualify as existing walking recipients while remaining a distinct mode. | `assump_trips_per_user_per_week_*`, `assump_new_user_activity_pattern`; sampling-method reference below. |
| 3: person donor reuse | No new input-summary row. | Reuse eligible source donors when required, with distinct appraisal identities. Reuse does not relax excluded categories. An individual can participate in multiple modes. Report actual reuse separately. | `reference_scope_report`, `population_replication_report`, counterfactual sampling reports. |
| 4: trip totals | Current accepted REF/CF trip counts by mode and the meaning of the total row. | Trip-authoritative Tab 2 targets survive Tab 3 changes until explicitly edited in Tab 4. Tab 4 does not revise accepted person counts. Counts need not sum to the total when only selected modes are displayed. | `trips_number_{ref,cf}_*`, `trips_number_total_{ref,cf}`; staged trip contract. |
| 4: basic trip restrictions | Changed active distance restriction; only show controls actually used by the selected path. | Eligibility restrictions are distinct from the advanced distance weights. Do not describe a visible but unconsumed control as applied. | `trips_refine_method`, `trips_dist_value`; current application needs review before summary expansion. |
| 4: trip-distance distribution | Saved changed target mean km by mode; optionally provide the category distribution in details. | Sample to favor the target distance distribution, or a smooth mean-distance preference where applicable. Neither means exact matching. Use staged REF distribution, with source-population fallback for an empty REF. | `trips_spread_mean_cf_*`, `trips_spread_bars_{ref,cf}_*`. |
| 4: completion parameters | Changed values already entered elsewhere need not be repeated. | Relevant mean distance **or** duration, plus speed; derive the third. An applicable explicit distance refinement supersedes the scalar completion mean. | `assump_trip_distance_km_*`, `assump_trip_duration_min_*`, `assump_trip_speed_kmh_*`. |
| 4: shifted versus induced | Changed requested induced percentage of **additional trips**. | Remainder shifts existing trips. This parameter does not describe all CF trips or decreases. Insufficient eligible shift candidates can increase realized induction; show that in the audit. | `assump_induced_trips_percent`; requested/realized `mode_shift_n`, `induced_n`. |
| 4: source-mode diversion | Changed source percentages, separately for each destination active mode, marked user-provided. | Default source distribution among shifted existing trips, excluding the target mode itself and excluding induced trips. Identify configured rates versus observed trip-mix proxy. Availability and other sampling weights constrain realized shares. | `assump_trip_source_shares_*`, `realized_source_mode_shares`. |
| 4: trip reuse and locks | No new input-summary row. | Donor trip patterns can be reused to meet a fixed trip target within the accepted people. A trip already shifted is not available for another shift. This differs from a person belonging to several active modes. | Reference trip allocation and counterfactual trip-lock/fallback diagnostics. |
| Full method/report: exposure | Not a Tab 3/4 sampling-summary item. | Convert active minutes to weekly marginal MET-hours using mode-specific intensity; document PT access walking and e-bike proxies. | `assump_mmet_per_hour_*`, `appraisal_model_parameters$physical_activity`, mode configuration. |
| Full method/report: health and totals | Appraisal period, scheme timeline and results units belong with results. | Health lookup and HALY/LY conventions, cycle-0 exclusion, timeline scaling, one appraisal record per person, signed impacts, rate denominators and mode attribution. | `scheme_*`, `appraisal_model_parameters`, frozen results profile and health-aggregation documentation. |

## 3. Source labels and diversion interpretation

For a default, show the actual source used, not a list of possible fallbacks:

- `REF population` / `REF trip mix (proxy)` when the assessed REF supplies it;
- `Source population` / `Source trip mix (proxy)` when geographic source data supply it;
- `England population (stored rate)` where the configured stored rate applies;
- `Fixed fallback` or `Fixed assumption (configured source shares)` for a configured value;
- `User provided` when the saved parameter overrides its default. Retain original
  default provenance in the profile so Restore remains meaningful.

Observed donor-trip composition is **not measured causal diversion** for a
scheme. It is an initial source-distribution proxy. A pie of 87% car can therefore
be data-derived without proving that 87% of the scheme's trips would replace car
travel. The e-bike cycling/PT/car thirds are an explicit assumption, distinct
from using cycling as an activity-pattern donor proxy.

The existing last-resort no-data pie is uniform. Replacement target-specific
rates need agreement; do not invent empirical evidence for a more plausible
looking default. Configured per-target shares can already replace it.

## 4. Full inventory and implementation references

The complete reference is the combination of the canonical profile, retained
data/software versions and the method sections below, not just the short cards.
The current report does not serialize every profile entry; its method links
should not be mistaken for a complete appraisal-specific parameter export.

| Inventory group | Where to review the method / parameters |
|---|---|
| Selected geography, donor evidence and data versions | `appraisal_data_sources`; [health-data contract](hm_data_contract.md); methodology **Reference synthetic population**. |
| Tab 2 unit conversion, defaults and e-bike proxies | [Assumption field catalogue](appraisal_assumptions_field_catalogue.md); `R/tab2_input_conversion.R`, `R/appraisal_assumptions.R`, `R/config.R`. |
| Accepted person/trip boundaries and target precedence | Methodology **Continuity from Tab 2 to Tabs 3 and 4**; `R/appraisal_population_contract.R`, `R/finalize_staged_appraisal.R`. |
| Category eligibility, weight construction and fallback sampling | Methodology **Counterfactual sampling and redistribution**; `R/counterfactual_data_sampling_functions.R`, `R/counterfactual_data_apply_ui_values.R`. |
| Person cloning, trip-pattern reuse and cross-mode trip locks | `R/population_donor_replication.R`, `R/reference_data_apply_appraisal_scope.R`; request-specific sampling reports. |
| PT walking, e-bike activity patterns, distance/duration/speed | `R/mode_features.R`, `R/appraisal_assumptions.R`; `appraisal_model_parameters$counterfactual`. |
| Exposure intensities and health lookup / HALYs | Methodology **From physical activity to health trajectories**; `assump_mmet_per_hour_*`; `R/counterfactual_data_apply_health_outcomes.R`, `R/health_outcomes_calculate_halys.R`. |
| Scheme effect over time | Methodology **Scheme build-up, persistence and decline**; `R/scheme_effect_timeline.R`. |
| Aggregation, units, signs, denominators and mode attribution | [README](../README.md) health-outcome aggregation sections; `R/results_data_prepare.R`; [health-outcome reference PDF](pdf/MIAMA-health-outcomes.pdf). |
| Reproducibility and uncertainty | `appraisal_sampling_seed`, `appraisal_model_parameters`, `appraisal_schema_version`; [assumption API contract](appraisal_assumptions_api.md); sampling-variance reports. |

See the [full methodology](methodology.qmd) and [README](../README.md).

## 5. Decisions before implementing the full cards

1. Confirm whether live inline edits need a pending marker before Next accepts
   them. Saved modal refinements and canceled drafts must remain distinct.
2. Confirm brief indicators: age + male %, baseline PA, mean trip km, and
   percentages for new users, induced trips and source modes. Keep full bars
   available in details rather than repeat them on every card.
3. Review purpose controls and the two sex-distribution controls. Purpose and
   induction are not interchangeable; some legacy UI labels no longer describe
   independent sampling behavior. Avoid adding them to summaries prematurely.
4. Agree target-specific no-data diversion priors. Keep the supplied data mix
   clearly labelled as a proxy where no direct diversion evidence is supplied.
5. Choose where to show realized-versus-requested diagnostics and material
   fallbacks. A complete distribution-achievement audit is not yet a UI feature.
