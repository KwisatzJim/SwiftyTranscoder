# Milestone 28 — Local 0.4.0 Release Candidate

## Goal

Package the runtime-confirmed unattended-conversion improvements as a new locally installable release candidate.

## Included changes

- Prevent automatic idle system sleep only while a conversion is active.
- Show the current video's batch position while retaining its percentage and ETA.
- Show a separate overall batch progress bar.
- Optionally notify the user when an unattended batch completes, fails, or is cancelled.
- Explain how to enable SwiftyTranscoder in macOS Notification settings when permission is unavailable.

## Release identity

The marketing version is `0.4.0` and the build number is `4`. The candidate remains an arm64, locally ad-hoc-signed build rather than a Developer ID signed or notarized public distribution.

## Validation

`Scripts/build-release.sh` completed the Release build, strict app-signature verification, DMG creation, DMG verification, and SHA-256 generation. Independent read-only mounting confirmed that the packaged app is version `0.4.0 (4)`, is arm64, satisfies its designated requirement, and includes the Applications shortcut. The recorded SHA-256 checksum also passed verification.

The user installed the candidate into `/Applications`, confirmed About reports `0.4.0 (4)`, confirmed normal launch, confirmed the multi-file notification and batch-progress controls are present, and confirmed the notification preference remained enabled. Milestone 28 is complete.
