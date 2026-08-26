# MIAMA-HUB documentation

- `methodology.qmd`: report-style methods description and implementation audit.
- `methodology_slides.qmd`: presentation summary of the same approach.

Render from the MIAMA-HUB package root:

```sh
quarto render docs/methodology.qmd --to html
quarto render docs/methodology.qmd --to pdf
quarto render docs/methodology_slides.qmd
```

The report produces HTML and PDF. The slide source produces a reveal.js HTML
slide deck.
