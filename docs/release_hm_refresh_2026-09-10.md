# Compatible published release 0.0.0.9003

This release starts from the previously published `4e43b99` interface. It adds:

- `89b3ba7`: inactive Tab 2 input isolation and health-year reconstruction tests.
- `9796294`: scheme lifetime scaling, zero-effect lookup exclusion and summary API.
- `c6dafc9`: baseline-inclusive LY/HLY results and 0-40-year scheme input bounds.
- `6b50ecf`: new relative-risk HM data from `08e78e2`, canonical filenames,
  cycle-0 reference loading, data provenance and cache invalidation.

The published assumptions cards, reports, e-bike proxies, two-city selector and
plot layout are retained. The canonical assumption-field migration on HUB dev
is deliberately excluded until its matching UI is ready. This branch must not
replace HUB dev or be merged back wholesale. UI dev's installed package is not
changed by preparing this release.

The source tarball omits repository documentation/presentations, which are not
runtime dependencies. The documentation remains available in Git. Runtime data
include the same 1,000-person sample, Leeds 5,000 and Manchester 10,000 sources.

The release test suite passes, including assumptions, reports, HM file contracts,
baseline health years, unchanged exposure and lifetime scaling. The publishing
UI must additionally be checked against this exact package before deployment.
