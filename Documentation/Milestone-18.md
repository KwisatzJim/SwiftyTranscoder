# Milestone 18 — Repeatable Release Packaging

## Goal

Replace the manual local-release command sequence with one conservative, repeatable script.

## Implementation

`Scripts/build-release.sh` builds the Release configuration in a temporary Derived Data folder using Xcode's local ad-hoc signing, verifies the resulting app, creates an installation DMG with an Applications shortcut, verifies the DMG, and writes its SHA-256 checksum.

The script reads the version, build number, and executable architecture from the built app. It stops on the first failed command, cleans up its temporary workspace, and refuses to replace an existing same-version DMG unless the user explicitly supplies `--force`.

## Validation

The script completed an arm64 `0.1.0 (1)` Release build, strict app-signature verification, DMG creation, DMG checksum verification, and SHA-256 generation. The resulting artifact is `dist/SwiftyTranscoder_0.1.0_arm64.dmg`. Milestone 18 is complete.
