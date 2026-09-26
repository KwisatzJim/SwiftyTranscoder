# Milestone 40 — Duplicate-Destination Regression Tests

## Goal

Protect the batch duplicate-output safety rule against subtle path-comparison regressions.

## Implementation

Canonical output-path comparison now lives in a Foundation-only model shared by the application and Swift package tests. Automated cases verify conservative case-insensitive matching, canonically equivalent composed and decomposed Unicode filenames, and separation of genuinely different filenames.

All three canonical-path tests pass alongside the five queue-state tests, for eight passing tests across two suites. The full Debug application build also succeeds after switching the production duplicate check to the shared tested implementation. Milestone 40 is complete.
