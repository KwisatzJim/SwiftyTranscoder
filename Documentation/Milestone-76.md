# Milestone 76 — Hands-On Restoration Preview

## Goal

Expose the complete native restoration preview pipeline through one bounded, clearly labeled control so picture, sound, synchronization, progress, and cancellation can receive hands-on review before full-file restoration is enabled.

## User interface

Eligible SD sources now show an **AI restoration preview** card on the Plan step. The card displays the model method and exact source/output dimensions, accepts a start time, and offers 2-, 5-, or 10-second lengths. The frame count is derived from the source's rational frame rate and remains capped at the independently verified 240-frame boundary.

The default is a five-second preview beginning at 00:09:00. Start time is clamped to the inspected program duration.

While the preview runs, the card shows the active extraction, restoration, assembly, or audio stage with aggregate percentage and a Cancel button. Normal conversion controls and plan changes are disabled so two heavy media jobs cannot run concurrently. Leaving the Plan step cancels an active preview and safely removes the pipeline-owned workspace.

On success, the card shows the complete temporary path and provides **Play Preview**, **Show in Finder**, and **Create Another** actions. The file remains named `restored-preview.partial.mp4`; no final output is created or promoted.

## Research-model boundary

This review build uses the checksum-pinned model already prepared under `.build/restoration-evaluation`. The 33 MB model remains outside the application bundle and Git history while quality is under review. If it is missing, the UI explains that `Scripts/prepare-restoration-model.sh` must be run.

Bundling, licensing notices, release size, and update policy remain a separate decision after the human quality gate.

## Verification

- The complete suite passes 72 tests across 20 suites.
- The full macOS application builds successfully with Swift 6 complete concurrency checking.
- The ordinary conversion path is unchanged.
- Preview and normal conversion are mutually exclusive.
- Cancellation remains available during every native preview stage.

## Hands-on gate

Use `Alphas - s01e11 - Original Sin.m4v`, continue to the Plan step, leave the default 540-second start and five-second length, and select **Create Restoration Preview**.

Confirm:

1. progress advances and the app remains responsive;
2. **Cancel Preview** works if tested, after which a new preview can be started;
3. the completed clip opens with **Play Preview**;
4. restored picture quality is useful and does not show distracting artifacts;
5. audio is present at the expected protected-gain level; and
6. lip movement and sound remain synchronized.

Do not use the temporary partial as a production output. Full-file restoration remains unavailable until this gate passes.
