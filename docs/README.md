# Documentation and validation index

Organized: **2026-09-11**. Organization dates are not new validation dates.
Documents retain their content dates, scope and limitations. Feature-branch
proposals are not automatically implemented in `dev`.

## Current documentation

Maintained explanations live in `current/documentation/`.

| Question | Source |
|---|---|
| How does the app work? | [Methodology](current/documentation/methodology.qmd) and [slides](current/documentation/methodology_slides.qmd) |
| How are outcomes and plot units aggregated? | [README section 6.1](../README.md#61-health-outcome-units-and-aggregation) |
| How should UI read/edit assumptions? | [Assumption API](current/documentation/appraisal_assumptions_api.md) |
| Which fields and triggers belong to the appraisal? | [Field/dependency catalogue](current/documentation/appraisal_assumptions_field_catalogue.md), including labelled remaining design decisions |
| What HM data are used and how are they refreshed? | [Health data contract](current/documentation/hm_data_contract.md) |
| How does scheme duration affect results? | [Scheme timeline](current/documentation/scheme_effect_timeline.md) |

## Current validation and exploration

These documents are evidence, open investigations, or proposals, not a second
methodology. Their findings apply to the code/data and tests they identify.

| Topic | Source | Status/use |
|---|---|---|
| Users versus trips | [Matched-route benchmark](current/validation/route_benchmark.qmd) | Executable report |
| Sampling variance and sample size | [Variance report](current/validation/sampling_variance_evaluation.qmd) | Executable report; inspect manifests |
| Bug reports and priorities | [Assessment/to-dos, section 6](current/validation/external_review_assessment_2026-09-09.md#6-proposed-to-do-list) | Living task register |
| Source weighting | [Weight audit](current/validation/source_weighting_audit.md) | Open representativeness questions |
| PA/age/sex sampling preferences | [Weighting review](current/validation/population_sampling_weighting_review.md) | Audit and proposal; newer WIP remains separate |
| Summary versus assumptions cards | [Coverage catalogue](current/validation/tab3_tab4_summary_assumptions.md) | Includes UI feature-branch work |
| Basic population and navigation | [Review](current/validation/basic_population_navigation_review_2026-09-10.md) | Open UI issues and documented fixes |
| Distance/duration UI | [Issue description](current/validation/tab2-distance-duration-ui-issue.md) | Unit refresh and PT save investigation |
| UI visibility conditions | [Integration checklist](current/validation/ui_condition_contract_issue.md) | Check against the tested UI version |
| PDF report delivery | [QA/reproduction](current/validation/pdf-report-qa.md) | Backend export checks and limits |

## Historical material

[Archive index](archive/README.md) links old PDFs/HTML, user-testing slides,
workflow diagrams, and completed one-time audits. These are **snapshots, not
current documentation or fresh validation**. Nothing was deleted.

[Inventory](inventory.csv) records every pre-existing tracked document/asset,
its old/new path, last content-commit date and archive status. Binary assets
are dated there without altering their contents.

## Render and rerun

The reorganization was checked by rendering the methodology, route benchmark
and sampling-variance HTML from their new locations. Workflow/helper tests and
the source-link/inventory check passed. Archived rendered/data assets were
checked against their original Git content hashes. Simulations were not rerun.

From the HUB root:

```sh
quarto render docs/current/documentation/methodology.qmd --to html
quarto render docs/current/documentation/methodology_slides.qmd --to html
quarto render docs/current/validation/route_benchmark.qmd --to html
quarto render docs/current/validation/sampling_variance_evaluation.qmd --to html
Rscript --vanilla inst/workflows/dev_check_documentation.R
```

For current README, methodology and health-aggregation PDFs, run in Positron:

```r
options(miama.docs.source = ".")
source("inst/workflows/dev_render_documentation_pdfs.R")
```

PDFs go to `current/documentation/pdf/`; Quarto, Pandoc and LaTeX are required.
Rendering a validation report reads existing results; it does **not** rerun a
simulation. Producers remain `inst/workflows/dev_route_benchmark.R` and
`inst/workflows/dev_sampling_variance.R`, now writing ignored run data under
`docs/current/validation/`. Caches were moved, not recomputed. Read their
manifests before treating earlier runs as evidence for a changed model.
Fresh T3 audits also write to current validation, never over archived CSVs.

## Small maintenance rules

1. Update an existing guide instead of creating competing explanations.
2. Give new documents a content date and status. For analyses record code/data
   versions, inputs, seed/design, and what was actually tested.
3. Keep unresolved reviews current. Archive completed/superseded studies with
   their outputs, assets and a reason for archiving.
4. Update this index and references when moving files; run the link check.
5. Do not commit simulation caches, Quarto scratch folders or Office lock files.
   Current renders are local outputs; deliberately retained snapshots belong in
   a dated archive with provenance.
