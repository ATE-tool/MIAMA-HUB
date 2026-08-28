# MIAMA-HUB documentation

- `methodology.qmd`: report-style methods description and implementation audit.
- `methodology_slides.qmd`: presentation summary of the same approach.
- `sampling_variance_evaluation.qmd`: executable Leeds simulation study of
  variance introduced by counterfactual person/trip sampling.

Render from the MIAMA-HUB package root:

```sh
quarto render docs/methodology.qmd --to html
quarto render docs/methodology.qmd --to pdf
quarto render docs/methodology_slides.qmd
quarto render docs/sampling_variance_evaluation.qmd --to html
```

The report produces HTML and PDF. The slide source produces a reveal.js HTML
slide deck.

The sampling-variance report defaults to a 440-run, 10-year pilot design: 400
positive-change assessments plus 40 no-change invariants. It caches each
completed run under `docs/_sampling_variance_cache/`. Use Quarto parameters to
reduce the replicate count or effect-size set for a smoke test. An additional
controlled sample-size experiment is implemented but disabled by default
because its standard configuration adds 600 health-model runs. A paired
combined-mode ordering experiment is also implemented and disabled by default;
its standard configuration adds 120 runs.
