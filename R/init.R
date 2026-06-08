# Session/bootstrap initialization for dev workflow

miama_init <- function(cfg = NULL, create_dirs = TRUE) {
  cfg <- miama_resolve_config(cfg)

  if (create_dirs) {
    dir.create(cfg$output$root, recursive = TRUE, showWarnings = FALSE)
    dir.create(cfg$output$lookup, recursive = TRUE, showWarnings = FALSE)
    dir.create(cfg$output$reference, recursive = TRUE, showWarnings = FALSE)
  }

  list(
    config = cfg,
    paths = miama_paths(),
    timestamp = Sys.time()
  )
}