# Health model data contract

## Current release

HUB uses the two standard exports from `MIAMA-HM/scripts/sp_hm_join.R`:

| Export | Grain | Use |
|---|---|---|
| `sp_cycle_outcomes` | Person and model cycle | REF health state, annual outcomes, death shares and reference MMETs |
| `mmet_d_cycle_lookup` | Age, sex, mortality-risk decile, cycle, outcome and MMET interval | Outcome change per MMET |

The September 10 refresh uses files from HM checkout `08e78e2`, containing the
new relative risks. `health_data/release.rds` records the checkout revision,
source-file MD5 checksums and refresh date; `manifest.csv` inventories the
packaged subsets. The later smoothing update is **not** claimed to be included.
The packaged pYLD and disability-weight tables were checked/copied from the same
checkout; their content did not change in this refresh.

## Reference people and health calculation

Reference sampling requires one row per person. HUB selects cycle 0 in Arrow
and loads only `census_id`, `mr_decile` and `mmets_cycle` (renamed `mmets`). It
joins that roster to synthpop attributes and trips. It does not aggregate the
cycle table into an invented overall health record, or join every cycle to
every trip. Config keys called `overall` are internal source aliases for this
baseline loader, not dependencies on optional HM exports.

After sampling, HUB loads complete histories for the donor IDs and applies
MMET changes using the matching cycle lookup. Copies of a donor reuse that
donor's history. The death-share columns are still required for HALY prevalence
reconstruction; removing the filename suffix does not remove those columns.
Existing death-share/HALY, LY/HLY and scheme lifetime math is unchanged.
The internal `*_death_share` loader names describe this calculation contract.

Cycle 0 supplies initial health state, never an appraisal benefit year. Histories
must be contiguous from 0, but older people can have fewer follow-up years at
the health model's age boundary. No rows are invented to extend their history.

## Refresh without changing the sample

From the HUB project, with Arrow/dplyr available:

```r
Sys.setenv(MIAMA_HM_ROOT = "/path/to/MIAMA-HM")
source("inst/workflows/dev_refresh_packaged_health_data.R")
source("inst/workflows/dev_build_packaged_data_manifest.R")
```

The refresh extracts histories for the **existing** sample and LAD person IDs,
checks baseline coverage, unique person/cycle keys, continuous histories and
death-share lookup coverage, and stages the outputs before replacement. It
refreshes the shared lookup and HALY parameters in the same operation. People,
trip rows, seeds, geography and appraisal weight (one person per row) stay fixed.
Old overall/sample/death-share-suffixed exports are removed from packaged data.
Run this with app processes stopped, then restart them; in-memory Hub instances
are not hot-reloaded. Rebuild/install the package to deliver it to UI or hosting.

The input files must come from the same HM release. A matching filename alone
cannot prove that independently copied files belong together. This procedure
records checksums for subsequent audits, including future smoothed releases.
Sample and LAD paths are isolated from the sibling HM checkout; a missing
configured file fails instead of silently falling back to another release.

Baseline-loader caches use a new namespace and source path/file/size/mtime
fingerprints. Changed files invalidate those cached values. For an intentional
replacement preserving timestamps and sizes, force `cfg$cache$refresh = TRUE`.

No UI/default.R changes are needed for this data contract. An already installed
MIAMAHUB package continues to use its old embedded data until updated.

## Verification of this refresh

The complete HUB test suite covers canonical filename resolution, baseline-only
reference loading, missing configured sources, source-aware cache invalidation,
and a no-change calculation against the packaged health data. Full HUB smoke
calculations also completed for Leeds and Manchester: basic cycling trips,
500 REF / 700 CF per week, seed 1, default scheme timeline. Both produced
nonzero impacts with HALYs and all configured disease columns present.

This verifies integration of the supplied HM outputs, not the scientific
validation of the new relative risks or the forthcoming smoothing method.
