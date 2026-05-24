# MIAMA-HUB Module: Shared / Schema Accessors
# Purpose: Provide low-level helpers for working with canonical
#   `appraisal_inputs` fields and related payload structures.
# Inputs: Named lists and field names.
# Outputs: Extracted or inferred field values.
# Notes: Keep these helpers generic. They should be reusable across API,
#   mapping, reference, and counterfactual modules.
#
# Returns TRUE when a field looks like a canonical appraisal input entry.
is_input_field <- function(x) {
  is.list(x) && "input_value" %in% names(x)
}

# Extracts an input value from either a canonical field or a raw scalar value.
get_input_value <- function(appraisal_inputs_in, field_name, default = NULL) {
  if (!field_name %in% names(appraisal_inputs_in)) {
    return(default)
  }

  field <- appraisal_inputs_in[[field_name]]
  if (is_input_field(field)) {
    if (is.null(field$input_value)) {
      return(default)
    }
    return(field$input_value)
  }

  if (is.null(field)) {
    return(default)
  }

  field
}
