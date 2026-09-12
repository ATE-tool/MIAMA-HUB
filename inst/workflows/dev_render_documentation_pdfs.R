# Run from the MIAMA-HUB project in Positron (paths updated 2026-09-11).
# source("inst/workflows/dev_render_documentation_pdfs.R")
# Optional: options(miama.docs.source = "/path/to/another/HUB/worktree")
# Requires Quarto, Pandoc and a working LaTeX installation.
source_root <- normalizePath(getOption("miama.docs.source", "."), mustWork = TRUE)
output_dir <- file.path(getwd(), "docs", "current", "documentation", "pdf")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_dir <- normalizePath(output_dir)

run_document_command <- function(command, args) {
  executable <- Sys.which(command)
  if (!nzchar(executable)) stop("Required program not found: ", command)
  status <- system2(executable, shQuote(args))
  if (status != 0L) stop(command, " failed with status ", status)
}

readme <- readLines(file.path(source_root, "README.md"), warn = FALSE)
extract_section <- function(start, end) {
  first <- grep(start, readme)
  last <- grep(end, readme)
  if (length(first) != 1L || length(last) != 1L || last <= first) {
    stop("Selected README lacks the expected health-documentation headings. ",
         "Set options(miama.docs.source = '/path/to/HUB/worktree') to a branch ",
         "containing the aggregation documentation, or update section boundaries.")
  }
  readme[seq.int(first, last - 1L)]
}

# Extract existing documentation, not a second independently maintained method.
health <- extract_section("^### Counterfactual health outcomes$", "^## 6\\.")
aggregation <- extract_section("^### 6\\.1 Health outcome units and aggregation$",
                               "^### Tab 5 health outcome choices$")
headlines <- extract_section("^#### Headline health outcomes$",
                            "^#### Tab 5 profile fields and function arguments$")
reporting <- extract_section("^#### Reporting units in the current UI$",
                            "^#### Mode attribution contract$")
# Keep the reader-facing unit explanation, not the subsequent UI payload example.
reporting <- reporting[seq_len(grep("^The central UI plotting contract", reporting) - 1L)]
health <- sub("^### ", "# ", health)
aggregation <- sub("^### ", "# ", sub("^#### ", "## ", aggregation))
headlines <- sub("^#### ", "# ", headlines)
reporting <- sub("^#### ", "# ", reporting)
health_pack <- tempfile(fileext = ".md")
writeLines(c(
  "# Reading guide", "",
  "This extract covers health calculation and aggregation from the MIAMA-HUB README.",
  "Read **Health outcome units and aggregation** for the meanings of plot values:",
  "expected deaths/cases, life-years/HALYs, absolute benefit, percent improvement,",
  "per-100,000 denominators, time aggregation and mode attribution.", "",
  paste0("Documentation source: `", source_root, "`."), "",
  health, "", aggregation, "", headlines, "", reporting
), health_pack)

# Wrap long code examples in the PDF rather than clipping them at the margin.
header <- tempfile(fileext = ".tex")
writeLines(c(
  "\\usepackage{fvextra}",
  "\\DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,commandchars=\\\\\\{\\},fontsize=\\footnotesize}",
  "\\fvset{breaklines=true,fontsize=\\footnotesize}",
  "\\emergencystretch=3em"
), header)
render_markdown <- function(input, output, title) {
  run_document_command("pandoc", c(
    input, "--from=markdown+gfm_auto_identifiers", "--standalone", "--toc", "--toc-depth=3",
    "--pdf-engine=xelatex", "--highlight-style=tango", "--include-in-header", header,
    "-V", "geometry:margin=20mm", "-V", "fontsize:10pt",
    "-V", "documentclass:scrartcl", "-V", "colorlinks:true",
    "-M", paste0("title:", title), "-M", paste0("date:", Sys.Date()),
    "-o", file.path(output_dir, output)
  ))
}
render_markdown(file.path(source_root, "README.md"), "MIAMA-README.pdf", "MIAMA-HUB developer reference")
render_markdown(health_pack, "MIAMA-health-outcomes.pdf", "MIAMA health outcomes: calculation and plot aggregation")
render_methodology <- function() {
  # Stage the self-contained QMD so Quarto cannot overwrite tracked PDFs/caches.
  stage <- tempfile("miama-methodology-")
  dir.create(stage)
  file.copy(file.path(source_root, "docs", "current", "documentation", "methodology.qmd"), stage)
  previous_dir <- setwd(stage)
  on.exit({ setwd(previous_dir); unlink(stage, recursive = TRUE) })
  writeLines(c(
    "function Image(image)",
    "  return pandoc.RawInline('latex', '\\\\includegraphics[width=5.5in,height=7in,keepaspectratio]{\\\\detokenize{' .. image.src .. '}}')",
    "end"
  ), "pdf-image-size.lua")
  run_document_command("quarto", c(
    "render", "methodology.qmd", "--to", "pdf", "--output", "MIAMA-methodology.pdf",
    "--lua-filter=pdf-image-size.lua"
  ))
  if (!file.copy("MIAMA-methodology.pdf", file.path(output_dir, "MIAMA-methodology.pdf"),
                 overwrite = TRUE)) stop("Could not copy the rendered methodology PDF.")
}
render_methodology()
unlink(c(health_pack, header))
message("PDFs saved in: ", output_dir)
