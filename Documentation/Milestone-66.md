# Milestone 66 — Restoration Eligibility Planning

## Goal

Move the proven restoration limits into a small, testable Swift planning layer before adding any controls or running the model from the application.

This milestone does not change the current interface or conversion path. AI restoration remains unavailable in production use and off by default.

## Planning boundary

`RestorationPlanner` now evaluates the inspected primary video and returns either an exact `RestorationPlan` or a plain-language reason that restoration is unavailable.

An eligible source must have:

- exactly one H.264 or HEVC video stream;
- 8-bit 4:2:0 (`yuv420p`) video;
- known positive dimensions below 1920 × 1080;
- a known, valid frame rate;
- limited-range SDR color; and
- identified BT.709 or SMPTE 170M matrix, transfer, and primary metadata.

The plan records the model name, source and output dimensions, frame rate, and all color tags that a later execution layer must preserve. Scaling is limited to 2× and 1920 × 1080. For example:

- 624 × 352 becomes 1248 × 704 at 2×; and
- 1280 × 720 becomes 1920 × 1080 at 1.5×.

Sources at or above 1080p are rejected rather than being needlessly processed. HDR, 10-bit, unknown-color, malformed-frame-rate, and unsupported-codec inputs are also rejected rather than guessed.

## Verification

The Swift test suite now checks both proven eligible plans and each important refusal boundary. All 36 tests across 12 suites pass.

The full macOS application also builds successfully with code signing disabled for this development verification.

## Result and next gate

The application now has one authoritative, side-effect-free answer to two questions: whether restoration is safe for an inspected source, and exactly what dimensions and color metadata a later restoration job must use.

The next milestone can connect this plan to a reusable restoration service while keeping it isolated from the normal conversion path and unavailable in the interface until execution, cancellation, metadata, subtitle, chapter, and batch boundaries are verified.
