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

### Bundled-helper correction

The first hands-on attempt exposed a packaging gap: backend tests had used a development FFmpeg with PNG support, while the deliberately narrow bundled helper did not yet include PNG or the `image2` sequence format. FFmpeg therefore could not infer an output format for `frame-%08d.png` and stopped with exit code 234.

The narrow toolchain now explicitly includes only the additional restoration capabilities it needs: PNG encode/decode and `image2` mux/demux. Both the toolchain build and release-app verification scripts require those capabilities, preventing a future package from silently omitting them. A fresh application build's own bundled FFmpeg successfully extracted four numbered, nonempty PNG frames from the representative source using the exact application command.

## Hands-on result

Use `Alphas - s01e11 - Original Sin.m4v`, continue to the Plan step, leave the default 540-second start and five-second length, and select **Create Restoration Preview**.

The representative five-second preview completed after correcting two packaging/validation issues found by the hands-on run: the bundled FFmpeg initially lacked PNG/image-sequence support, and MP4 represented the approved cadence with a numerically equivalent but textually different fraction. The corrected build accepts only a tightly bounded container rounding difference while still rejecting a genuine cadence change.

The completed preview played successfully and its restored picture was confirmed to look good. This passes the required picture, audio, synchronization, progress, and playback gate for advancing beyond preview-only research.

The review covered:

1. progress advances and the app remains responsive;
2. **Cancel Preview** works if tested, after which a new preview can be started;
3. the completed clip opens with **Play Preview**;
4. restored picture quality is useful and does not show distracting artifacts;
5. audio is present at the expected protected-gain level; and
6. lip movement and sound remain synchronized.

The reviewed temporary partial remains a preview rather than a production output. Full-file restoration stays unavailable until its separate plan, storage, cancellation, and final-output boundary is implemented.
