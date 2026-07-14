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
    if ("is_filled" %in% names(field) && !isTRUE(field$is_filled)) {
      return(default)
    }
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

# Flattens a canonical `appraisal_inputs` object into a plain named list of
# values. Raw named lists are returned unchanged.
extract_input_values <- function(appraisal_inputs_in, drop_null = FALSE) {
  assert_named_list(appraisal_inputs_in, "appraisal_inputs_in")

  values <- lapply(appraisal_inputs_in, function(field) {
    if (is_input_field(field)) {
      if ("is_filled" %in% names(field) && !isTRUE(field$is_filled)) {
        return(NULL)
      }
      return(field$input_value)
    }
    field
  })

  if (isTRUE(drop_null)) {
    values <- values[!vapply(values, is.null, logical(1))]
  }

  values
}

# Normalizes active-mode identifiers used by MIAMA-UI and MIAMA-HUB.
# MIAMA-UI currently uses short keys such as `walk` and `bike`, while several
# HUB internals use descriptive keys such as `walking` and `cycling`.
normalize_active_modes <- function(modes) {
  if (is.null(modes) || length(modes) == 0) {
    return(character(0))
  }

  x <- tolower(as.character(modes))
  aliases <- c(
    walk = "walking",
    walking = "walking",
    bike = "cycling",
    bicycle = "cycling",
    cycling = "cycling",
    cycle = "cycling",
    ebike = "ebiking",
    e_bike = "ebiking",
    ebiking = "ebiking",
    pt = "pt",
    public_transport = "pt",
    walk_to_pt = "pt"
  )

  out <- unname(aliases[x])
  out[is.na(out)] <- x[is.na(out)]
  unique(out)
}
