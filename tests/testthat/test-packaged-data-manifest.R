artifact_checksum <- function(path) {
  files <- if (dir.exists(path)) {
    sort(list.files(path, recursive = TRUE, full.names = TRUE, all.files = FALSE))
  } else {
    path
  }
  files <- files[file.exists(files)]

  checksums <- unname(tools::md5sum(files))
  paste0(basename(files), "=", checksums, collapse = ";")
}

test_that("packaged data manifest covers existing artifacts with current checksums", {
  data_root <- file.path(miama_project_root(), "inst", "extdata", "data")
  manifest <- utils::read.csv(
    file.path(data_root, "manifest.csv"),
    stringsAsFactors = FALSE
  )

  required_columns <- c(
    "artifact", "format", "source", "source_version", "purpose",
    "generated_by", "row_count", "schema", "checksum_algorithm", "checksum"
  )
  expect_true(all(required_columns %in% names(manifest)))
  expect_equal(anyDuplicated(manifest$artifact), 0L)
  expect_true(all(manifest$row_count > 0))
  expect_true(all(nzchar(manifest$schema)))
  expect_true(all(manifest$checksum_algorithm == "MD5"))

  artifact_paths <- file.path(data_root, manifest$artifact)
  expect_true(all(file.exists(artifact_paths) | dir.exists(artifact_paths)))
  expect_equal(
    unname(vapply(artifact_paths, artifact_checksum, character(1))),
    manifest$checksum
  )
})
