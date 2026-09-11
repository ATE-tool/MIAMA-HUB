pdf_report_fixture <- function() {
  cfg <- miama_default_config()
  health <- data.frame(census_id = c(1, 2), cycle = 1L, age1year = c(35, 60),
    female = c(0, 1), dead = 10, d_dead = -1, dead_cf = 9,
    diabetes = 4, d_diabetes = -0.5, diabetes_cf = 3.5,
    stroke = 2, d_stroke = -0.25, stroke_cf = 1.75)
  trips <- data.frame(trip_mainmode = c("Walk", "Cycle"), weight_tripXhh = c(2, 3))
  data <- prepare_results_data(list(health_outcomes = health, trips = trips),
    reference_data = list(trips = trips), cfg = cfg,
    results_request = list(res_outcomes = c("mortality", "diabetes", "stroke")))
  prepare_results_exports(data, cfg = cfg, include_plots = FALSE,
    profile = list(appraisal_name = "PDF report QA", geo_name = "Test place"))
}

pdf_report_prerequisites <- function() {
  skip_if_not(rmarkdown::pandoc_available(), "Pandoc is required")
  skip_if_not(nzchar(Sys.which("pdflatex")), "pdflatex is required")
}

test_that("PDF formatting preserves all table rows/columns without changing Word content", {
  exports <- pdf_report_fixture()
  before <- serialize(exports, NULL)
  table <- data.frame(first = paste0("entry", 1:105), second = 1:105,
                      third = "text", last_column = "last value")
  pdf <- paste(.results_export_markdown_table(table, pdf = TRUE), collapse = "\n")
  expect_match(pdf, "entry105", fixed = TRUE)
  expect_match(pdf, "last column", fixed = TRUE)
  expect_match(pdf, "Panel 2 of 2", fixed = TRUE)
  expect_identical(.results_export_markdown_table(table),
                   .results_export_markdown_table(table, pdf = FALSE))
  expect_false(grepl("entry105", paste(.results_export_markdown_table(table), collapse = "\n")))
  .results_export_markdown(exports, pdf = TRUE)
  expect_identical(serialize(exports, NULL), before)
})

test_that("existing report renders as PDF to an extensionless path and Word still works", {
  pdf_report_prerequisites()
  exports <- pdf_report_fixture()
  directory <- withr::local_tempdir()
  pdf <- file.path(directory, "download")
  write_results_report(exports, pdf, "pdf")
  expect_identical(readChar(pdf, 5, useBytes = TRUE), "%PDF-")
  expect_gt(file.info(pdf)$size, 1000)
  docx <- file.path(directory, "word-download")
  write_results_report(exports, docx, "docx")
  expect_true("word/document.xml" %in% utils::unzip(docx, list = TRUE)$Name)
  if (nzchar(Sys.which("pdftotext"))) {
    text <- paste(system2("pdftotext", c(shQuote(pdf), "-"), stdout = TRUE), collapse = "\n")
    for (section in c("Summary", "Appraisal metadata", "Applied result filters", "Methods",
                      "Results", "Assumptions and limitations", "Panel 5 of 5")) {
      expect_match(text, section, fixed = TRUE)
    }
  }
  qa <- Sys.getenv("MIAMA_PDF_QA_DIR")
  if (nzchar(qa)) {
    dir.create(qa, recursive = TRUE, showWarnings = FALSE)
    file.copy(pdf, file.path(qa, "miama-report.pdf"), overwrite = TRUE)
  }
})

test_that("PDF multipage tables retain the final row and escape literal text", {
  pdf_report_prerequisites()
  exports <- pdf_report_fixture()
  exports$report$title <- "Report & QA: 10% <test> $5"
  exports$report$results <- data.frame(
    result = paste0("entry", 1:105), reference = 10, counterfactual = 9,
    detail = paste0("finalvalue", 1:105))
  directory <- withr::local_tempdir()
  pdf <- file.path(directory, "multipage.pdf")
  write_results_report(exports, pdf, "pdf")
  expect_identical(readChar(pdf, 5, useBytes = TRUE), "%PDF-")
  if (nzchar(Sys.which("pdftotext"))) {
    text <- paste(system2("pdftotext", c(shQuote(pdf), "-"), stdout = TRUE), collapse = "\n")
    expect_match(text, "entry105", fixed = TRUE)
    expect_match(text, "finalvalue105", fixed = TRUE)
    expect_match(text, "10% <test> $5", fixed = TRUE)
  }
  qa <- Sys.getenv("MIAMA_PDF_QA_DIR")
  if (nzchar(qa)) file.copy(pdf, file.path(qa, "multipage.pdf"), overwrite = TRUE)
})

test_that("invalid bundles fail before creating a report", {
  file <- withr::local_tempfile()
  expect_error(write_results_report(list(), file, "pdf"), "exports must be created")
  expect_false(file.exists(file))
})

test_that("converter failures clean temporary files without replacing the destination", {
  pdf_report_prerequisites()
  rendered <- NULL
  local_mocked_bindings(pandoc_convert = function(input, to, output, options) {
    rendered <<- output
    writeLines("partial conversion", output)
    stop("Converter failed")
  }, .package = "rmarkdown")
  destination <- withr::local_tempfile()
  writeLines("existing report", destination)
  expect_error(write_results_report(pdf_report_fixture(), destination, "pdf"), "Converter failed")
  expect_identical(readLines(destination), "existing report")
  expect_false(dir.exists(dirname(rendered)))
})

test_that("a converter returning non-PDF content is rejected centrally", {
  pdf_report_prerequisites()
  rendered <- NULL
  local_mocked_bindings(pandoc_convert = function(input, to, output, options) {
    rendered <<- output
    writeLines("This is not a PDF", output)
  }, .package = "rmarkdown")
  destination <- withr::local_tempfile()
  expect_error(write_results_report(pdf_report_fixture(), destination, "pdf"), "did not produce a PDF")
  expect_false(file.exists(destination))
  expect_false(dir.exists(dirname(rendered)))
})
