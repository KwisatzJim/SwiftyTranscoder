# Milestone 50 — Local 0.8.0 Release Candidate

## Goal

Package the confirmed multi-step wizard and its navigation polish as a locally installable release candidate.

## Included changes

- Separate the workflow into focused **Choose**, **Review**, **Plan**, and **Convert** pages.
- Allow approved batch videos to be revisited without losing the other approvals.
- Keep large queues compact and automatically keep the current video visible.
- Preserve a loaded video or batch when revisiting **Choose**.
- Reset page scroll position between steps and clearly report the current video context.
- Add a larger minimum window, subtle page transitions, Return-key actions, and safeguards against replacing or reopening a completed batch accidentally.

## Release identity

The marketing version is `0.8.0` and the build number is `8`. The candidate remains an arm64, locally ad-hoc-signed build rather than a Developer ID signed or notarized public distribution.

## Validation

All 24 automated tests across 9 suites pass. `Scripts/build-release.sh` completed the optimized Release build, strict app-signature verification, DMG creation, image verification, and SHA-256 generation.

Independent read-only mounting confirmed that the packaged app is version `0.8.0 (8)`, contains an arm64 executable, satisfies its designated requirement, and includes the Applications shortcut. The independently calculated SHA-256 matched `dist/SHA256SUMS.txt`:

```text
9ca5fcab4f66b51c31a44b4803352d8be95ce1a356bc6caac18511cdaf5a9665  SwiftyTranscoder_0.8.0_arm64.dmg
```

Milestone 50 is complete; installation over the current app remains the final optional hands-on validation.
