# MIAMA-HUB Module: Shared / Field Checks
# Purpose: Hold small validation helpers used across the package.
# Inputs: Generic package objects.
# Outputs: Validation side effects or informative errors.
# Notes: Keep these checks lightweight and dependency-free where possible.
#
# Validates that an object is a named list.
assert_named_list <- function(x, object_name = "object") {
  if (!is.list(x) || is.null(names(x))) {
    stop("`", object_name, "` must be a named list.")
  }

  invisible(TRUE)
}
