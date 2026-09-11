# Existing report PDF support

This change is confined to `R/results_data_export_functions.R` and focused
tests. It reuses the existing report content and writer. There are no changes
to results preparation, aggregation, input/assumption handling, export-bundle
assembly, or the Word/Markdown formatting path.

Pandoc compiles PDF only when its destination ends in `.pdf`. The writer now
renders into a private temporary directory using the correct suffix, verifies
the PDF signature, and copies the completed file to the requested destination,
including Shiny's extensionless path. Conversion failures leave an existing
destination untouched and remove temporary files.

PDF-only formatting splits wide tables into panels of three original columns
plus a stable row number. It wraps schema identifiers, repeats table headers
across pages, uses readable 10pt type and 0.7-inch margins, and retains every
report-table row. This avoids overlapping 13-column tables. Existing Word and
Markdown behavior (including their 100-row table limit) is unchanged.

## Reproduction

Run from `/private/tmp/MIAMA-HUB-report-current`:

```sh
R_LIBS_USER=/Users/thomasgotschi/Github/MIAMA-UI/renv/library/macos/R-4.6/aarch64-apple-darwin23 \
MIAMA_PDF_QA_DIR=/private/tmp/miama-report-current-final \
Rscript --vanilla -e 'pkgload::load_all(".", quiet=TRUE); testthat::test_file("tests/testthat/test-report-pdf.R", stop_on_failure=TRUE)'
```

Requires `rmarkdown`, Pandoc, and LaTeX with `pdflatex`. Poppler enables text
verification and visual QA. Tests cover real PDF/Word output, extensionless
paths, literal text escaping, a 105-row table, invalid bundles, converter
errors, non-PDF output rejection, cleanup, and destination preservation.

QA files are `miama-report.pdf` (three pages, the existing 13-column results
contract) and `multipage.pdf` (six pages, a 105-row pagination/escaping fixture)
in the output directory above. Both are synthetic test reports, not actual
appraisal results. Existing `test-results-data.R` also passes (157 assertions).
All nine final PDF pages were rendered and visually inspected: no overlapping
cells, clipped text, or detached panel captions. The focused PDF tests pass
28 assertions, with no failures, warnings, or skips.

## Deferred content work

HUB dev already supports report production. Its report content includes a
summary, selected metadata, filters, methods, results, and results-contract
assumptions/limitations. Full frozen input/assumption inventories are not
currently emitted by that template. The prior report branch was assessed;
broader reconstruction was deliberately excluded per the final scope request.
No legacy report pipeline or compatibility layer was added.
