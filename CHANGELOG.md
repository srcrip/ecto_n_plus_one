# Changelog

## Unreleased

- Added `EctoNPlusOne.Test` for detecting n+1 queries in tests, including LiveView and controller tests.
  `assert_no_n_plus_one/2` runs a block and fails when the same query runs from the same callsite with
  distinct parameter sets; `detect_n_plus_one_queries/2` returns the same detections without raising.

## 0.1.0 - 2026-08-24

- Initial version created
