# MIAMA-HUB Module: API / Hub R6 Wrapper
# Purpose: Provide a session-scoped stateful wrapper around the package's core
#   functions so Shiny can hold one Hub instance per appraisal session.
# Notes: Keep business logic in the existing functional modules; this class
#   should mainly manage state, sequencing, and user-facing method boundaries.

#' Hub Session Object
#'
#' Stateful wrapper for one MIAMA appraisal session. Stores current inputs,
#' request sections, and loaded reference-side objects. Intended to be created
#' once per Shiny session and called via methods rather than via global state.
#'
#' @export
Hub <- R6::R6Class(
  "Hub",
  public = list(
    cfg = NULL,
    appraisal_inputs = NULL,
    request = NULL,
    reference_sources = NULL,
    reference_data_raw = NULL,
    reference_data = NULL,
    reference_ui_values = NULL,
    counterfactual_data = NULL,

    initialize = function(cfg = NULL, appraisal_inputs = NULL) {
      self$cfg <- cfg %||% miama_default_config()

      if (!is.null(appraisal_inputs)) {
        self$set_appraisal_inputs(appraisal_inputs)
      }
    },

    set_appraisal_inputs = function(appraisal_inputs) {
      self$appraisal_inputs <- appraisal_inputs
      self$request <- receive_appraisal_inputs(appraisal_inputs)
      invisible(self$request)
    },

    update_inputs = function(input_updates) {
      if (is.null(self$appraisal_inputs)) {
        stop("Hub has no appraisal_inputs yet. Call set_appraisal_inputs() first.", call. = FALSE)
      }
      assert_named_list(input_updates, "input_updates")

      changed_fields <- names(input_updates)
      merged <- utils::modifyList(self$appraisal_inputs, input_updates)
      invalidation <- invalidate_hub_state(
        state = list(
          reference_sources = self$reference_sources,
          reference_data_raw = self$reference_data_raw,
          reference_data = self$reference_data,
          reference_ui_values = self$reference_ui_values,
          counterfactual_data = self$counterfactual_data
        ),
        changed_fields = changed_fields
      )

      self$appraisal_inputs <- merged
      self$request <- receive_appraisal_inputs(self$appraisal_inputs)
      self$reference_sources <- invalidation$state$reference_sources
      self$reference_data_raw <- invalidation$state$reference_data_raw
      self$reference_data <- invalidation$state$reference_data
      self$reference_ui_values <- invalidation$state$reference_ui_values
      self$counterfactual_data <- invalidation$state$counterfactual_data

      invisible(self$request)
    },

    get_request = function() {
      private$.require_request()
      self$request
    },

    get_geo_options = function(geo_level, refresh = FALSE) {
      get_geo_options(
        cfg = self$cfg,
        geo_level = geo_level,
        refresh = refresh
      )
    },

    get_geo_name = function(refresh = FALSE, default = NA_character_) {
      private$.require_request()

      value <- tryCatch(
        get_geo_name(
          cfg = self$cfg,
          geo_level = self$request$reference_request$geo_level,
          geo_id = self$request$reference_request$geo_id,
          refresh = refresh
        ),
        error = function(e) default
      )

      if (is.null(value) || length(value) == 0 || is.na(value[1])) {
        return(default)
      }

      value[1]
    },

    load_reference_sources = function() {
      private$.require_request()

      self$reference_sources <- load_reference_sources(
        cfg = self$cfg,
        reference_request = self$request$reference_request,
        results_request = self$request$results_request
      )

      invisible(self$reference_sources)
    },

    build_reference_data = function() {
      private$.require_request()
      private$.require_reference_sources()

      self$reference_data_raw <- join_hm_and_synthpop(self$reference_sources)
      self$reference_data <- filter_reference_data(
        self$reference_data_raw,
        self$request$reference_request
      )

      invisible(self$reference_data)
    },

    build_reference_ui_values = function() {
      private$.require_request()
      private$.require_reference_data()

      self$reference_ui_values <- extract_reference_ui_values(
        self$reference_data,
        self$request$reference_request,
        self$request$appraisal_input_values
      )
      geo_name <- self$get_geo_name(default = self$reference_ui_values$ui_updates$geo_name %||% NA_character_)
      if (!is.na(geo_name)) {
        self$reference_ui_values$ui_updates$geo_name <- geo_name
      }

      self$reference_ui_values
    },

    get_reference_ui_values = function(refresh = FALSE) {
      if (isTRUE(refresh) || is.null(self$reference_ui_values)) {
        return(self$build_reference_ui_values())
      }

      self$reference_ui_values
    },

    get_reference_ui_updates = function(refresh = FALSE) {
      ui_values <- self$get_reference_ui_values(refresh = refresh)
      ui_values$ui_updates
    },

    get_reference_ui_value = function(field_name, refresh = FALSE, default = NULL) {
      updates <- self$get_reference_ui_updates(refresh = refresh)
      value <- updates[[field_name]]

      if (is.null(value)) {
        return(default)
      }

      value
    },

    get_population_size = function() {
      self$get_reference_ui_value("population_size")
    },

    get_appraisal_summary_values = function(refresh = FALSE) {
      private$.require_request()

      ui_updates <- if (!is.null(self$reference_data)) {
        self$get_reference_ui_updates(refresh = refresh)
      } else {
        list()
      }

      list(
        geo_level = self$request$reference_request$geo_level,
        geo_id = self$request$reference_request$geo_id,
        geo_name = self$get_geo_name(default = ui_updates$geo_name %||% NA_character_),
        population_size = ui_updates$population_size %||% ui_updates$pop_total_ref %||% NA_integer_,
        appraisal_name = self$request$appraisal_input_values$appraisal_name %||% NULL
      )
    },

    build_counterfactual_data = function(seed = 1L) {
      private$.require_request()
      private$.require_reference_data()

      self$counterfactual_data <- init_counterfactual_data(self$reference_data)
      self$counterfactual_data <- apply_counterfactual_ui_values(
        self$counterfactual_data,
        self$request$appraisal_input_values,
        reference_data = self$reference_data,
        seed = seed
      )

      self$counterfactual_data
    },

    get_counterfactual_data = function(refresh = FALSE, seed = 1L) {
      if (isTRUE(refresh) || is.null(self$counterfactual_data)) {
        return(self$build_counterfactual_data(seed = seed))
      }

      self$counterfactual_data
    }
  ),
  private = list(
    .require_request = function() {
      if (is.null(self$request)) {
        stop("Hub request is not set. Call set_appraisal_inputs() first.", call. = FALSE)
      }
    },

    .require_reference_sources = function() {
      if (is.null(self$reference_sources)) {
        stop("Reference sources are not loaded. Call load_reference_sources() first.", call. = FALSE)
      }
    },

    .require_reference_data = function() {
      if (is.null(self$reference_data)) {
        stop("Reference data is not built. Call build_reference_data() first.", call. = FALSE)
      }
    }
  )
)
