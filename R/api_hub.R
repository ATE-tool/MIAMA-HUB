# MIAMA-HUB Module: API / Hub R6 Wrapper
# Purpose: Session-scoped interface between MIAMA-UI profile objects and HUB
#   calculation modules.
#
# Primary UI workflow:
# 1. `get_appraisal_setup_inputs()` returns the setup subset of the active
#    profile: UI mode, geography, modes, and intervention descriptors.
# 2. `build_reference_profile_defaults()` loads/builds reference data as needed
#    and writes derived reference values into matching `default_value` fields.
# 3. `build_results()` receives the filled profile after UI counterfactual
#    inputs have been collected, then runs the current end-to-end calculation
#    and returns profile, data objects, result tables, and plot-ready data.
#
# Developer helpers remain available below the primary methods. They expose
# intermediate objects for testing, debugging, and workflow scripts.

#' Hub Session Object
#'
#' Stateful wrapper for one MIAMA appraisal session. The object is initialized
#' with runtime configuration only; MIAMA-UI profile objects are supplied to
#' profile-aware methods or set explicitly with `set_appraisal_inputs()`.
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
    results_data = NULL,

    # Lifecycle --------------------------------------------------------------
    # Create one Hub per Shiny appraisal/session. Construction is config-only;
    # pass the active MIAMA-UI profile to UI-facing methods such as
    # `build_reference_profile_defaults(profile)` or call
    # `set_appraisal_inputs(profile)` before using stateful developer helpers.

    initialize = function(cfg = NULL) {
      self$cfg <- cfg %||% miama_default_config()
    },

    set_appraisal_inputs = function(appraisal_inputs) {
      self$request <- receive_appraisal_inputs(appraisal_inputs)
      self$appraisal_inputs <- self$request$appraisal_inputs_in
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
          counterfactual_data = self$counterfactual_data,
          results_data = self$results_data
        ),
        changed_fields = changed_fields
      )

      self$request <- receive_appraisal_inputs(merged)
      self$appraisal_inputs <- self$request$appraisal_inputs_in
      self$reference_sources <- invalidation$state$reference_sources
      self$reference_data_raw <- invalidation$state$reference_data_raw
      self$reference_data <- invalidation$state$reference_data
      self$reference_ui_values <- invalidation$state$reference_ui_values
      self$counterfactual_data <- invalidation$state$counterfactual_data
      self$results_data <- invalidation$state$results_data

      invisible(self$request)
    },

    # Primary UI Methods -----------------------------------------------------
    # These are the intended high-level calls for MIAMA-UI.

    get_appraisal_setup_inputs = function(profile = NULL) {
      if (!is.null(profile)) {
        self$set_appraisal_inputs(profile)
      }
      private$.require_profile()

      private$.profile_subset(.hub_appraisal_setup_fields())
    },

    build_reference_profile_defaults = function(profile = NULL, refresh = FALSE) {
      if (!is.null(profile)) {
        self$set_appraisal_inputs(profile)
      }
      private$.require_request()

      if (isTRUE(refresh) || is.null(self$reference_sources)) {
        self$load_reference_sources()
      }
      if (isTRUE(refresh) || is.null(self$reference_data)) {
        self$build_reference_data()
      }

      reference_ui_values <- self$build_reference_ui_values()
      updated_profile <- apply_reference_defaults_to_profile(
        profile = self$appraisal_inputs,
        ui_updates = reference_ui_values$ui_updates
      )
      defaults_report <- attr(updated_profile, "reference_defaults_report")

      self$request <- receive_appraisal_inputs(updated_profile)
      self$appraisal_inputs <- self$request$appraisal_inputs_in
      attr(self$appraisal_inputs, "reference_defaults_report") <- defaults_report

      self$appraisal_inputs
    },

    build_results = function(profile = NULL, seed = 1L, refresh = FALSE) {
      if (!is.null(profile)) {
        self$set_appraisal_inputs(profile)
      }
      private$.require_request()

      if (isTRUE(refresh) || is.null(self$reference_sources)) {
        self$load_reference_sources()
      }
      if (isTRUE(refresh) || is.null(self$reference_data)) {
        self$build_reference_data()
      }
      if (isTRUE(refresh) || is.null(self$counterfactual_data)) {
        self$build_counterfactual_data(seed = seed)
      }
      if (isTRUE(refresh) || is.null(self$counterfactual_data$health_outcomes)) {
        self$build_counterfactual_health_outcomes()
      }

      self$build_results_data()

      list(
        profile = self$appraisal_inputs,
        reference_data = self$reference_data,
        counterfactual_data = self$counterfactual_data,
        results_data = self$results_data
      )
    },

    # Geography Helpers ------------------------------------------------------
    # Lightweight helpers for geography select controls and summary labels.

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

    # Developer Helpers: Request/Profile Inspection --------------------------
    # These are useful for testing and debugging. UI code should usually pass
    # around the profile object instead of using the internal request directly.

    get_request = function() {
      private$.require_request()
      self$request
    },

    get_profile = function() {
      private$.require_profile()
      self$appraisal_inputs
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

    # Developer Helpers: Reference Pipeline ----------------------------------
    # Expose intermediate reference objects for scripts and tests.

    load_reference_sources = function() {
      private$.require_request()
      private$.require_reference_scope()

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

    # Developer Helpers: Counterfactual And Results Pipeline ------------------
    # These remain callable for dev workflows, while `build_results()` is the
    # preferred high-level UI method.

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
    },

    build_counterfactual_health_outcomes = function(scheme_effect_duration = "longterm") {
      private$.require_counterfactual_data()
      private$.require_reference_data()

      self$counterfactual_data <- apply_counterfactual_health_outcomes(
        counterfactual_data = self$counterfactual_data,
        reference_data = self$reference_data,
        cfg = self$cfg,
        scheme_effect_duration = scheme_effect_duration
      )

      self$counterfactual_data
    },

    build_results_data = function() {
      private$.require_request()
      private$.require_reference_data()
      private$.require_counterfactual_data()

      self$results_data <- prepare_results_data(
        counterfactual_data = self$counterfactual_data,
        reference_data = self$reference_data,
        results_request = self$request$results_request,
        appraisal_input_values = self$request$appraisal_input_values
      )

      self$results_data
    },

    get_results_data = function(refresh = FALSE) {
      if (isTRUE(refresh) || is.null(self$results_data)) {
        return(self$build_results_data())
      }

      self$results_data
    }
  ),

  private = list(
    .require_profile = function() {
      if (is.null(self$appraisal_inputs)) {
        stop("Hub profile is not set. Call set_appraisal_inputs() first.", call. = FALSE)
      }
    },

    .require_request = function() {
      if (is.null(self$request)) {
        stop("Hub request is not set. Call set_appraisal_inputs() first.", call. = FALSE)
      }
    },

    .require_reference_scope = function() {
      geo_level <- self$request$reference_request$geo_level %||% NULL
      geo_id <- self$request$reference_request$geo_id %||% NULL

      if (is.null(geo_level) || length(geo_level) == 0 || !nzchar(as.character(geo_level)[1])) {
        stop(
          "Reference geography is not set. Update the profile fields `geo_level`",
          " and, unless `geo_level = \"eng\"`, `geo_id` before calling HUB reference loading.",
          call. = FALSE
        )
      }

      if (!identical(as.character(geo_level)[1], "eng") &&
          (is.null(geo_id) || length(geo_id) == 0 || !nzchar(as.character(geo_id)[1]))) {
        stop(
          "Reference geography ID is not set. Update the profile field `geo_id`",
          " before calling HUB reference loading.",
          call. = FALSE
        )
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
    },

    .require_counterfactual_data = function() {
      if (is.null(self$counterfactual_data)) {
        stop("Counterfactual data is not built. Call build_counterfactual_data() first.", call. = FALSE)
      }
    },

    .profile_subset = function(fields) {
      fields <- fields[fields %in% names(self$appraisal_inputs)]
      self$appraisal_inputs[fields]
    }
  )
)

.hub_appraisal_setup_fields <- function() {
  c(
    "ui_version", "ui_input_scope", "geo_level", "geo_id", "modes",
    "intervention_type", "data_source"
  )
}
