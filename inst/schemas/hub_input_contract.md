# HUB Input Contract

`MIAMA-HUB` should accept a canonical `appraisal_inputs` object originating
from `MIAMA-UI`.

At scaffold stage, the contract is intentionally lightweight:

- input is expected to be a named list
- each named entry may be either:
  - a raw value, or
  - a list containing an `input_value` field
- package code should treat `appraisal_inputs` as the canonical incoming UI
  payload and should not assume Shiny session objects are available

This contract will be refined in follow-on issues.
