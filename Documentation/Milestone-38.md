# Milestone 38 — Automated Queue-State Regression Tests

## Goal

Protect batch queue removal and index reordering with repeatable automated tests.

## Implementation

The index-remapping rules are now isolated in a small Foundation-only model used by the app. A lightweight Swift package test harness verifies removal from dictionaries and sets, plus current-selection behavior when an item before, at, or after the current item is removed.

All five queue-state regression tests pass with `swift test`, covering dictionary and set reindexing plus current-item selection before, after, and at the removed position. The full Debug application build also succeeds. Milestone 38 is complete.
