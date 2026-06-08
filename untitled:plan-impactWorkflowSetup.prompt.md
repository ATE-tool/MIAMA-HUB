## Plan: Rebuild Impact Workflow Setup

Implement the new workflow foundation without touching `inst/workflows/POC_impact_workflow.R`. The new maintained orchestrator remains `inst/workflows/dev_workflow.R`, while setup concerns are extracted into dedicated `R/` modules and dependency management is initialized with `renv`. This keeps legacy as a cheatsheet, improves maintainability, and makes execution reproducible. Given unresolved items from discovery, this plan assumes full parity intent, recreates missing helper behavior from legacy logic where possible, and uses explicit package imports in `DESCRIPTION`.

**Steps**
1. Preserve legacy reference: keep `inst/workflows/POC_impact_workflow.R` unchanged and exclude it from active orchestration paths.
2. Implement setup modules:
   - Add `R/constants.R` with fixed workflow constants (scenario toggles/defaults, `sp_cols`, file/row limits, stable names).
   - Add `R/paths.R` with path constructors/resolvers for HM roots, SP input/output locations, lookup files, and scenario output paths.
   - Add `R/config.R` with runtime configuration objects and validators (HM outcome loading and scenario run options).
   - Add `R/init.R` with bootstrap helpers to initialize libraries, config, paths, and required directories.
3. Implement executable orchestration in `inst/workflows/dev_workflow.R`:
   - Wire initialization via `R/init.R`.
   - Recreate legacy workflow stages using extracted setup modules and existing package functions.
   - Replace legacy inline setup blocks with module calls.
4. Handle missing sourced dependencies:
   - Recreate equivalents for missing `R/run_scenario_functions.R` and `helpers/build_mock_case_study_profile.R` behavior from legacy script semantics, or provide package-local replacements used by `dev_workflow.R`.
5. Align package dependencies:
   - Update `DESCRIPTION` with explicit runtime `Imports` for packages actually used by the new orchestration path (instead of umbrella-only dependencies).
6. Initialize reproducibility:
   - Add renv bootstrap files (`renv/activate.R`, root `.Rprofile` hook) and create `renv.lock` via initial snapshot from active workflow dependencies.
7. Document active workflow entrypoint:
   - Update `README.md` to state `inst/workflows/dev_workflow.R` is the maintained orchestrator and `POC_impact_workflow.R` is legacy reference.

**Verification**
- Confirm no git diff on `inst/workflows/POC_impact_workflow.R`.
- Run `inst/workflows/dev_workflow.R` end-to-end and verify expected output directories/files are created.
- Validate setup modules load cleanly when sourced independently.
- Run `renv::status()` and ensure lockfile/bootstrap are consistent.
- Check `DESCRIPTION` dependency declarations match packages imported/used by the new path.

**Decisions**
- Keep `POC_impact_workflow.R` immutable as legacy cheatsheet.
- Use `inst/workflows/dev_workflow.R` as sole maintained orchestrator.
- Prefer explicit package `Imports` in `DESCRIPTION` over `tidyverse` umbrella.
- Reconstruct missing helper behavior from legacy semantics to avoid blocking progress.