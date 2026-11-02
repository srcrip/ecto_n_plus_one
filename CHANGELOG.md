# Changelog

## Unreleased

- The telemetry handler is about 7x faster per query and allocates about a tenth of the memory.
  `operation/1` no longer runs regexes over the whole query, it runs once per query instead of twice,
  and the application module names are converted to strings once per query rather than once per frame.
- Queries with whitespace between leading comments are now classified by their first SQL keyword
  instead of as `:other`.

- Added `EctoNPlusOne.Test` for detecting n+1 queries in tests, including LiveView and controller tests.
  `assert_no_n_plus_one/2` runs a block and fails when the same query runs from the same callsite with
  distinct parameter sets; `detect_n_plus_one_queries/2` returns the same detections without raising.

## 0.1.0 - 2026-08-24

- Initial version created
