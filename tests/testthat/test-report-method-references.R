test_that("reports point to the full method and assumption inventory", {
  exports <- list(generated_at_utc = "test", report = list(
    title = "Test", summary = character(), methods = character(),
    metadata = data.frame(), filters = data.frame(), results = data.frame(),
    assumptions = data.frame()))
  markdown <- paste(.results_export_markdown(exports), collapse = "\n")
  expect_match(markdown, "## Full method and assumptions reference", fixed = TRUE)
  expect_match(markdown, "[MIAMA-HUB methodology](https://github.com/ATE-tool/MIAMA-HUB/blob/dev/docs/current/documentation/methodology.qmd)", fixed = TRUE)
  expect_match(markdown, "appraisal_assumptions_field_catalogue.md)", fixed = TRUE)
  expect_match(markdown, "not a full serialized appraisal profile", fixed = TRUE)
})
