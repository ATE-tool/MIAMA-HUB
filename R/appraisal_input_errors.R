# MIAMA-HUB Module: Appraisal Input Errors
# Purpose: Raise user-facing errors for incompatible appraisal inputs while
# retaining structured context that MIAMA-UI can catch and display.

.abort_appraisal_input <- function(message,
                                   stage,
                                   fields = character(0),
                                   hint = NULL,
                                   details = list()) {
  full_message <- paste0(
    message,
    if (!is.null(hint) && nzchar(hint)) paste0(" ", hint) else ""
  )
  condition <- structure(
    c(
      list(
        message = full_message,
        call = NULL,
        stage = stage,
        fields = unique(fields),
        hint = hint
      ),
      details
    ),
    class = c("miama_appraisal_input_error", "error", "condition")
  )
  stop(condition)
}

