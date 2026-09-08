# Review PDFs

Rendered from `codex/release-advanced`, HUB commit `4e43b99`, on 2026-09-07.
The full health aggregation section is on that branch, not yet on HUB `dev`.
These are documentation exports, not a new validation of model calculations.

Start with **MIAMA-health-outcomes.pdf** (six pages):

- Pages 1-2: applying the health lookup and constructing HALYs.
- Pages 2-4: source units, aggregation formulas, denominators and mode attribution.
- Pages 5-6: headline totals and the reporting units selected in plot filters.

**MIAMA-README.pdf** is the complete developer reference. See section 6.1,
"Health outcome units and aggregation", and "Reporting units in the current UI".
**MIAMA-methodology.pdf** describes the broader workflow, including physical
activity, the health lookup and HALYs.

In the Positron R console, with MIAMA-HUB as the working directory:

```r
options(miama.docs.source = "/private/tmp/MIAMA-HUB-release")
source("inst/workflows/dev_render_documentation_pdfs.R")
```

This reads the release worktree without switching either repository's branch.
PDFs are written to `docs/pdf` in the current project. The rendering script
requires Quarto, Pandoc and LaTeX (already available on this machine).
After the aggregation documentation is merged into `dev`, use
`options(miama.docs.source = ".")` to render the current project instead.
