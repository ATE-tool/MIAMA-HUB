# Branch integration and release preparation

Prepared 2026-09-07. No history rewrite, worktree removal or publication is
part of this cleanup.

## Current branches

HUB `codex/appraisal-report` is the consolidated implementation branch in the
main `MIAMA-HUB` checkout. It extends `codex/assumptions-contract` (6cefb65).
Its focused commits cover population donor reuse, health aggregation and unit
person weights, and frozen appraisal reports. Documentation follows separately.

UI `codex/appraisal-report` lives at `/private/tmp/MIAMA-UI-appraisal-report`.
It extends UI `codex/assumptions-contract` (a0d966a), adding the report download
and corrected health labels in c955fc9. The UI assumptions worktree does not
contain these report controls.

The older HUB dev worktree at `/private/tmp/MIAMA-HUB-ebike-fix` contains pending
e-bike fixes already included in the consolidated branch. The implementation
and regression tests were compared; one test differs only by a blank line.
Leave that worktree intact until integration is accepted; do not recommit the
same fixes from there into the integrated branch.

## Merge order

1. Review and merge the paired HUB/UI assumptions PRs into their respective dev
   branches. They establish editable assumptions and the staged user defaults.
2. Review each `codex/appraisal-report` branch against its repository's dev.
   Once the assumptions commits are in dev, those prerequisite changes no longer
   appear as new work in the report PRs. Avoid cherry-picking them twice.
3. Merge HUB before enabling the new UI HTML download. Donor reuse and unit
   weights do not themselves require the new report controls; HTML reporting
   does require the matching HUB implementation.
4. Rebuild/install HUB and refresh dev-pub only after local acceptance. Existing
   packages, sessions and results do not automatically gain the new unit weight.

Alternatively, a single combined PR per repository can include assumptions and
the follow-on commits; explicitly supersede the older assumptions PRs in that
case. Do not merge both approaches independently.

## Local test

Use the UI report worktree with the current HUB source checkout. Confirm the
existing `global.R` load_all path resolves to that checkout, restart R and run
the app. A new `miama_default_config(dataset_size = "leeds")` must return
`population$person_weight == 1`; source_person_weight remains 163.552 metadata.

Check a normal Leeds scenario and a scenario requiring donor reuse; inspect
Tab 3/4 counts, absolute health results, percentages and report downloads.
Enter 1,000 users: the request remains 1,000 user records, not six weighted rows.
Confirm assumptions edits are reflected after recalculation and that later
plot filters do not silently change the frozen report. Full automated HUB tests
cover sampling and aggregation; live UI report-download acceptance is still due.

## Suggested PR summaries

HUB title: **Support larger appraisals, real-person totals and auditable reports**

- Reuse eligible source donors with unique identities and copied health histories.
- Default to one real appraisal person per record without reducing sampling pools.
- Correct initial health-state and cumulative population-denominator handling.
- Export frozen inputs, assumptions, parameters and results; document source units.
- Retain source expansion as metadata; existing configurations must be recreated.

UI title: **Add appraisal report downloads and clarify health result labels**

- Replace the PDF placeholder with the HUB self-contained HTML report download.
- Keep Word export and use the completed appraisal's frozen export bundle.
- Remove stale placeholder and incidence-only wording from health result labels.
- Requires the matching HUB report implementation and the assumptions prerequisite.
