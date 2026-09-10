# Scheme timeline: full-results verification

## Test setup (10 September 2026)

Full `Hub$build_results()` calls using the UI branch's actual `default.R` schema:
Leeds 5,000, basic trips route, cycling REF 695 / CF 1,000 weekly trips,
seed 1, and the configured 40-year assessment period. Only scheme lifetime
fields change. The same Hub instance is reused to exercise cache invalidation.

This test uses the isolated `codex/scheme-effect-app-test` companion build:
tested HUB source `2b45a09` plus the new timeline and baseline health-year
reconstruction fix. It retains UI dev's assumptions contract. The main feature
branch's focused tests cover its newer profile-default accessor too.

## Results

| Timeline | HALYs gained | Deaths prevented |
|---|---:|---:|
| Immediate, permanent | 14.0315967 | 0.755902820 |
| One-year build-up, permanent | 13.9877980 | 0.749141723 |
| Peak year 2, decline year 4, zero effect year 6 | 0.4385658 | 0.041836228 |

The first-year full-effect HALY benefit is 0.08759751. A one-year linear
build-up halves it; subsequent annual benefits remain unchanged. The resulting
0.312% reduction in total HALYs is hidden by whole-number headline rounding:
both permanent-scheme headline values display 14. Detailed tables retain it.

## Checks

- All REF/CF individual and trip tables are identical across runs.
- REF health outcomes are identical across runs.
- Every annual outcome delta equals its immediate-effect counterpart times the
  applicable curve factor (checked at tolerance 1e-10).
- Declining-scheme factors are .25, .75, 1, 1, .75, .25, then zero.
- From year 7 onwards, every annual health delta and exported health-year
  benefit is zero. Earlier cumulative benefits are retained.
- Updating the timeline on the same Hub recomputes results, rather than returning
  the previous timeline's cached results.

This verifies the full calculation pipeline, not automated browser navigation.
UI startup returned HTTP 200; UI component tests separately exercised profile
collection, preview rendering, invalid year ordering, and recovery.

Local reproducible comparison: `/private/tmp/compare-miama-scheme-results.R`.
Detailed annual outputs: `/private/tmp/miama-scheme-comparison.rds`.
