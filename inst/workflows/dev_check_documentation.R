# Lightweight source-link and relocation check; run from HUB root.
# Updated 2026-09-11. This does not validate scientific claims or rendered files.
check_documentation <- function(root = ".") {
  root <- normalizePath(root, mustWork = TRUE)
  sources <- c("README.md", "docs/README.md", "docs/archive/README.md",
    list.files(file.path(root, "docs/current"), pattern = "\\.(md|qmd)$",
               recursive = TRUE, full.names = TRUE))
  sources[!startsWith(sources, "/")] <- file.path(root, sources[!startsWith(sources, "/")])
  missing <- character()
  for (path in sources) {
    lines <- readLines(path, warn = FALSE)
    links <- unlist(regmatches(lines, gregexpr("!?\\[[^]]*\\]\\([^)]*\\)", lines)))
    targets <- sub("^.*\\]\\(([^)]*)\\)$", "\\1", links)
    targets <- sub("#.*$", "", targets)
    targets <- targets[nzchar(targets) & !grepl("^([A-Za-z][A-Za-z0-9+.-]*:|/)", targets)]
    targets <- URLdecode(targets)
    for (target in targets) {
      if (!file.exists(file.path(dirname(path), target))) {
        missing <- c(missing, paste(path, "->", target))
      }
    }
  }
  inventory <- read.csv(file.path(root, "docs/inventory.csv"))
  missing <- c(missing, inventory$path[!file.exists(file.path(root, inventory$path))])
  if (length(missing)) stop("Missing documentation targets:\n", paste(unique(missing), collapse = "\n"))
  message("PASS: current source links and ", nrow(inventory), " archived/current inventory entries")
  invisible(TRUE)
}

if (sys.nframe() == 0L) check_documentation()
