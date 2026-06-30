# Title

Define reusable sampling strategies for counterfactual activity and trip attributes

# Background

The first Step 6 implementation assigns activity values to sampled counterfactual rows by drawing observed values from the relevant reference group. For example, new walking users receive `walktime_wkhr` values sampled from existing reference walking users.

This is reasonable as a first pass, especially for large reference populations where random sampling should return a sufficiently representative and realistic distribution. However, for smaller reference populations, raw sampling can overrepresent a few observed rows. In those cases, assigning average values or sampling from a smoothed distribution may better represent expected or predicted behavior and impacts.

The same issue will apply to trip-level counterfactuals, including shifted trips, induced trips, trip distances, durations, and purpose distributions.

# Proposal

Create a small set of reusable sampling/assignment strategies and route counterfactual handlers through them rather than embedding one-off sampling logic in each handler.

Candidate strategies:

1. `sample_observed`: sample observed values from a reference donor group, with replacement.
2. `assign_mean`: assign the donor-group mean to every selected row.
3. `sample_smoothed`: sample from a smoothed or parametric approximation of the donor distribution.

The strategy should be configurable by value type and eventually by mode:

- individual activity attributes, e.g. `walktime_wkhr`, `cycletime_wkhr`
- trip counts or trip row selection
- trip distance/duration attributes
- trip purpose or diversion distributions

# Acceptance Criteria

- Add a shared assignment helper used by Step 6 counterfactual handlers.
- Support at least `sample_observed` and `assign_mean`.
- Preserve deterministic behavior via explicit seeds where random sampling is used.
- Record the chosen strategy in `counterfactual_report$changes`.
- Add tests comparing `sample_observed` and `assign_mean` behavior.
- Document defaults and rationale in `README.md`.

# Notes

The current implementation lives in `R/counterfactual_data_apply_ui_values.R`, especially `.assign_cf_user_count_delta()` and `.sample_activity_values()`.
