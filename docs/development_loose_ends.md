# Development loose ends

Updated 2026-09-07. The current decision is one appraisal record per real person.
Default health person weight is now 1 for all datasets; source expansion is
metadata only. Sampling is unchanged. The conversion proposal below is retained
as historical discussion, not an implementation plan.

## Open work

- **Editable assumptions:** coordinated HUB/UI work is on the assumptions
  branches; complete review of included parameters, edit/restore behavior and
  end-to-end calculation effects before considering the contract settled.
- **Appraisal report with assumptions:** local draft on `codex/appraisal-report`
  in HUB and the matching UI worktree. Includes inputs, effective assumptions,
  configured parameters and results. Still needs live download review, decisions
  on report presentation/plots and complete realized sampling diagnostics.
- **Population/trip units:** real-person counts map directly to record targets;
  health totals now use unit person weight, and trip totals count rows. Review
  source-default labelling (example appraisal versus full LAD), legacy saved
  configurations/results and trip-weight semantics before a wider release.
- **Person replacement:** local implementation and tests now support larger
  populations, unique copied identities, donor health histories and e-bike
  cycling proxies. Needs manual Leeds validation and release review. Copies
  increase appraisal capacity, not the independent source evidence sample.
- **Release coordination:** the implementation is organized into local commits
  on `codex/appraisal-report` in HUB and UI. UI report work is separate from the
  UI assumptions worktree used for testing. See [branch integration](branch_integration.md).
  These branches are not yet merged into dev or published.

## Historical conversion proposal (superseded)

1. UI profiles contain real units only: input_value, default_value,
   additional_data category counts and default_value_backup share that convention.
   Keep existing field IDs. Add quantity/basis/scale metadata in one field
   catalogue (or schema metadata), not duplicate mutable real/synth values.
2. HUB produces a separate calculation-input object in synthetic row units.
   Normalize timeframe and denominator explicitly, convert once, then sample.
   Generated Tab 3/4 defaults return through the inverse boundary. Never apply
   conversion to an already-converted object.
3. Freeze a conversion context for the appraisal from the source geography and
   dataset. Keep provenance and version; do not recompute weights using a
   filtered/resampled/duplicated appraisal population.
4. Population conversion can use real = records * person_weight while a uniform
   person weight is the chosen model. Leeds currently uses 163.552, calculated
   as 20 divided by the profile sampling fraction. represented_population is
   derived from source record counts times 20, not a newly verified independent
   official population total.
5. Verify the meaning and normalization of weight_tripXhh before defining real
   trip totals. It exists, but is not currently used by trip targets or plots.
   Do not assume it is an additional population expansion factor. Variable
   trip weights do not have one exact count-only inverse.
6. To keep internal sampling row-based, choose and document fixed calibrated
   trip conversion factors by the necessary mode/measure context, accepting
   approximate inversion. Exact variable-weight totals would instead require
   weighted target allocation, beyond a small conversion helper.
7. Mode-share percentages remain user percentages: apply them to the real total
   first, then convert each mode's target. Different mode weights mean synthetic
   row shares need not equal real shares. Trips/person rates likewise cannot be
   assumed invariant if person and trip conversion factors differ.
8. Distinguish total distance/duration (extensive quantities needing conversion)
   from per-trip distance/duration and speed (physical quantities). Per-person
   amounts need an explicitly converted population denominator. Do not scale
   all numeric fields indiscriminately.
9. Convert public counts/aggregates consistently in Tabs 2-5 and exports. Retain
   clearly labelled synthetic diagnostics separately. Existing health totals
   are already weighted and must not be multiplied again. Preserve entered
   requests alongside realized rounded/sampled totals in the report.

## Historical questions for a weighted alternative

- Validate population coverage and trip-weight semantics; choose the conversion
  factors and whether weighted totals are exact or approximate.
- Define behavior below one synthetic record. At the present Leeds weight,
  1,000 real users imply about 6.1 records; rounding and simulation stability
  become material. Higher computational resolution requires a separate rule
  adjusting representation weights, not the capacity-copying mechanism alone.
- Decide how legacy saved appraisals are identified and migrated. Existing
  numeric fields have synthetic semantics; silently treating them as real would
  change appraisals. Store a units-contract version.
- Test every route through Tab 2 -> 3 -> 4 -> results/export: defaults,
  manual edits, restore, category subtotals, percentage refinement, mode shares,
  zero/small targets and copied donors. Confirm units cannot be converted twice.

## Historical caution before the unit-weight decision

Do not deploy a partial conversion that fixes one modal but leaves tables,
assumptions or exports in another scale. Either complete the coherent boundary
and regression matrix, or explicitly conduct workflow-only testing without
claiming the numerical outputs describe entered real populations. Setting
person_weight to one alone does not validate source-population defaults or
establish correct real-world trip units.
