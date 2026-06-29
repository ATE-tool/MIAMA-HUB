# MIAMA-HUB API Integration Notes For MIAMA-UI

This note summarizes the current architecture decision and gives concrete R
examples for calling `MIAMA-HUB` from `MIAMA-UI`.

## Architecture Decision

`MIAMA-HUB` is currently designed as an R package API, not as a separate web
service.

The intended Shiny architecture is:

- `MIAMA-UI` owns the interactive UI state in canonical `appraisal_inputs`.
- `MIAMA-HUB` receives that canonical object through R function calls.
- One `Hub` R6 object should be created per Shiny session.
- The `Hub` object stores session-scoped calculation state:
  - normalized request
  - loaded source data
  - filtered `reference_data`
  - extracted `reference_ui_values`
  - generated `counterfactual_data`
- Expensive data loading and reference-data construction are cached inside that
  session object and invalidated when relevant inputs change.

The boundary object is the canonical `appraisal_inputs` list from
`MIAMA-UI/schemes/appraisal_inputs.R`. HUB does not need Shiny `input` directly;
UI should update `appraisal_inputs[[field]]$input_value`, then pass the object or
small update lists to HUB.

## Environment Setup

For local development, these environment variables must be set before loading
the package:

```r
Sys.setenv(MIAMA_PROJECT_ROOT = "/path/to/MIAMA-HUB")
Sys.setenv(MIAMA_HM_ROOT = "/path/to/MIAMA-HM")
```

In normal project use, put them in the project `.Renviron`.

## Example 1: Stateless Functional Pipeline

This is useful for tests, scripts, and debugging.

```r
library(MIAMAHUB)

cfg <- miama_default_config()
cfg$workflow$dataset_size <- "sample"  # "sample" or "full"
cfg$cache$enabled <- TRUE
cfg$cache$refresh <- FALSE

appraisal_inputs <- build_mock_appraisal_inputs(
  overrides = list(
    geo_level = list(input_value = "lad"),
    geo_id = list(input_value = "E08000035"),
    modes = list(input_value = c("walking", "cycling")),
    at_data_unit = list(input_value = "trips"),
    res_aggregation = list(input_value = "total")
  )
)

request <- receive_appraisal_inputs(appraisal_inputs)

reference_sources <- load_reference_sources(
  cfg,
  reference_request = request$reference_request,
  results_request = request$results_request
)

reference_data_raw <- join_hm_and_synthpop(reference_sources)

reference_data <- filter_reference_data(
  reference_data_raw,
  request$reference_request
)

reference_ui_values <- extract_reference_ui_values(
  reference_data,
  request$reference_request,
  request$appraisal_input_values
)

reference_ui_values$ui_updates
reference_ui_values$extraction_report
```

## Example 2: Stateful Shiny Session API

This is the preferred UI integration shape.

```r
library(MIAMAHUB)

cfg <- miama_default_config()
cfg$workflow$dataset_size <- "sample"

# In Shiny, create one Hub per user session.
hub <- Hub$new(cfg = cfg, appraisal_inputs = appraisal_inputs)

# Load and build reference data after required setup fields are available:
hub$load_reference_sources()
hub$build_reference_data()

# Get UI-ready values for Tabs 2-4 reference fields:
ui_updates <- hub$get_reference_ui_updates(refresh = TRUE)

# Example Shiny-side use:
# updateNumericInput(session, "pop_total_ref", value = ui_updates$pop_total_ref)
# updateNumericInput(session, "trips_number_total_ref", value = ui_updates$trips_number_total_ref)

# Get one value:
hub$get_reference_ui_value("pop_total_ref")
```

When a user changes inputs, call `update_inputs()` with a named list in the same
field shape as `appraisal_inputs`:

```r
hub$update_inputs(list(
  modes = list(input_value = c("walking", "cycling")),
  at_data_unit = list(input_value = "users")
))

# If the change only affects UI extraction, reference data is retained and
# reference UI values are invalidated.
ui_updates <- hub$get_reference_ui_updates(refresh = TRUE)
```

If geography or result aggregation changes, HUB invalidates heavier state and
the UI should rebuild reference data:

```r
hub$update_inputs(list(
  geo_level = list(input_value = "lad"),
  geo_id = list(input_value = "E08000035")
))

hub$load_reference_sources()
hub$build_reference_data()
ui_updates <- hub$get_reference_ui_updates(refresh = TRUE)
```

## Example 3: Counterfactual Data

Counterfactual generation currently starts from the filtered `reference_data`
and applies supported `_cf_` values.

```r
hub$update_inputs(list(
  users_count_cf_walk = list(input_value = 10000),
  trips_count_cf_walk = list(input_value = 200000),
  trips_timeframe_walk = list(input_value = "year"),
  trips_denominator_walk = list(input_value = "total")
))

counterfactual_data <- hub$build_counterfactual_data(seed = 1)

# Inspect what changed:
counterfactual_data$counterfactual_report$changes
counterfactual_data$counterfactual_report$comparison$ind
counterfactual_data$counterfactual_report$comparison$trips
counterfactual_data$counterfactual_report$comparison$changed_ind_rows
```

## Getting Geographic Levels And Geographic Options

### Current State

Geographic levels are currently defined by the UI schema:

```r
c(
  "England" = "eng",
  "Region" = "reg",
  "Grouped LADs" = "glads",
  "LAD" = "lad",
  "MSOA" = "msoa"
)
```

HUB already knows how to map these levels to source columns:

```r
eng  -> no geography column
reg  -> region
lad  -> lad25cd
glads -> lad25cd
msoa -> msoa11cd
```

There is not yet a dedicated exported HUB function like
`hub$get_geo_options("lad")`. The current implementation can derive options from
synthetic population attributes, but this should be formalized before UI wiring.

### Proposed HUB Helper

Suggested API:

```r
get_geo_levels <- function() {
  c(
    "England" = "eng",
    "Region" = "reg",
    "Grouped LADs" = "glads",
    "LAD" = "lad",
    "MSOA" = "msoa"
  )
}

get_geo_options <- function(cfg = NULL, geo_level) {
  cfg <- miama_resolve_config(cfg)

  if (identical(geo_level, "eng")) {
    return(data.frame(label = "England", value = "eng"))
  }

  geo_col <- switch(
    geo_level,
    reg = "region",
    lad = "lad25cd",
    glads = "lad25cd",
    msoa = "msoa11cd",
    stop("Unsupported geo_level: ", geo_level, call. = FALSE)
  )

  # Implementation should read only the required geography/name columns from
  # `cfg$sources$sp_attributes`, preferably through Arrow when parquet-backed.
  # Return a small UI-ready table:
  # data.frame(label = ..., value = ...)
}
```

For LADs, use `lad25nm` as label and `lad25cd` as value when available. For
regions, label and value can both be `region`. For MSOA, use `msoa11cd` until a
name column is available.

### Current Workaround

Until that helper exists, UI can keep using hard-coded level choices and call
HUB only once `geo_level` and `geo_id` are selected.

## Minimal Shiny Server Sketch

This is illustrative only. It should live in `MIAMA-UI`, not in HUB.

```r
server <- function(input, output, session) {
  hub <- reactiveVal(NULL)

  observeEvent(TRUE, {
    cfg <- MIAMAHUB::miama_default_config()
    cfg$workflow$dataset_size <- "sample"

    ai <- appraisal_inputs
    hub(MIAMAHUB::Hub$new(cfg = cfg, appraisal_inputs = ai))
  }, once = TRUE)

  observeEvent(input$geo_id, {
    h <- hub()
    req(h)

    h$update_inputs(list(
      geo_level = list(input_value = input$geo_level),
      geo_id = list(input_value = input$geo_id),
      modes = list(input_value = input$modes),
      at_data_unit = list(input_value = input$at_data_unit),
      res_aggregation = list(input_value = input$res_aggregation)
    ))

    h$load_reference_sources()
    h$build_reference_data()

    updates <- h$get_reference_ui_updates(refresh = TRUE)

    # Then update UI fields that exist and are visible.
    # updateNumericInput(session, "pop_total_ref", value = updates$pop_total_ref)
  })
}
```

## Output Objects The UI Should Expect

`reference_ui_values`:

```r
list(
  reference_request = list(...),
  appraisal_input_values = list(...),
  ui_updates = list(
    pop_total_ref = ...,
    users_count_ref_walk = ...,
    trips_count_ref_walk = ...,
    pop_number_ref_walk = ...,
    trips_number_total_ref = ...,
    ...
  ),
  extraction_report = list(
    at_data_unit = ...,
    modes = ...,
    skipped_fields = ...,
    notes = ...
  )
)
```

`counterfactual_data$counterfactual_report`:

```r
list(
  changes = list(...),
  notes = character(),
  n_ind = ...,
  n_trips = ...,
  comparison = list(
    ind = data.frame(...),
    trips = data.frame(...),
    changed_ind_rows = data.frame(...)
  )
)
```

## Recommended Next API Additions

1. Export `get_geo_levels()`.
2. Export `get_geo_options(cfg, geo_level)`.
3. Add a method `Hub$get_geo_options(geo_level)` that calls the functional
   helper.
4. Add a high-level method like `Hub$build_reference()` that combines
   `load_reference_sources()` and `build_reference_data()` for UI convenience.
5. Add a compact payload method that returns only UI-facing values, not large
   datasets.
