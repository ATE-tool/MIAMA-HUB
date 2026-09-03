# UI conditions recently changed in `default.R`

This is a short implementation reference for the conditions recently changed
in the profile schema. How these conditions are implemented in MIAMA-UI is left
to the UI maintainer; the list below only defines the intended behavior.

## 1. Tab 2 assessed-population modal

The population modal is relevant only when population values are needed to
interpret a non-user input route.

**Show when:**

```text
ui_version == "basic" AND
at_data_unit is one of: "trips", "distance", "mode_share"
```

**Do not show when:**

```text
at_data_unit == "users"
```

This applies to:

- `pop_total_ref_basic`
- `pop_number_ref_[walk|bike|ebike|pt]_basic`
- `pop_number_cf_[walk|bike|ebike|pt]_basic`

The mode-specific fields additionally require the corresponding mode to be
selected. There is no separate `pop_total_cf_basic`; REF and CF use the same
fixed assessed population.

## 2. Aggregate mode-share fields

**Fields:**

- `mode_share_ref`
- `mode_share_cf`

**Show when:**

```text
at_data_unit == "mode_share" AND at least one assessed mode is selected
```

The condition must not require walking specifically. It should work when the
selected assessment contains cycling, e-biking, or public transport without
walking.

## 3. Percentage of people who are new users

**Field:** `pop_new_current_perc`

**Show when:**

```text
ui_pop_refine_show_options == TRUE AND at_data_unit != "users"
```

The field is used only when mode-user counts must be inferred from trips,
distance/duration, or mode share. It is not needed for the `users` route because
explicit REF and CF user counts take precedence.

## 4. Percentage of trips that are induced

**Field:** `induced_trips_percent`

**Show when:**

```text
ui_trips_refine_show_options == TRUE
```

This is the explicit split between:

- existing utilitarian trips that switch mode; and
- newly induced trips, normally treated as recreational.

The old trip-purpose controls should not be used to define this split. Their
removal or commenting-out should be coordinated between UI and HUB separately.

## Quick checks

- Selecting only cycling, e-biking, or PT still exposes mode-share entry.
- Selecting `users` does not expose the Tab 2 population modal or
  `pop_new_current_perc`.
- Selecting trips, distance/duration, or mode share exposes the population
  modal and permits `pop_new_current_perc` when Tab 3 refinements are opened.
- Opening Tab 4 trip refinements exposes `induced_trips_percent`.
- Mode-specific population rows appear only for selected modes.
