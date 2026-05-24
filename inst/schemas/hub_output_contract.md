# HUB Output Contract

`MIAMA-HUB` should return compact objects suitable for reuse by `MIAMA-UI`.

At scaffold stage, the intended return shape is:

```r
list(
  ui_updates = list(...),
  reference_summaries = list(...),
  counterfactual_summaries = list(...),
  health_impacts = data.frame(),
  state = list(...)
)
```

The package should avoid returning large datasets to the UI by default.

This contract will be refined in follow-on issues.
