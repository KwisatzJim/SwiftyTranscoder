# Milestone 48 — Local 0.7.0 Release Candidate

## Goal

Package the batch-removal improvement and the new automated safety net as a locally installable release candidate.

## Included changes

- Remove a source safely from a reviewed batch while preserving the other approvals.
- Add filename-specific queue accessibility metadata.
- Add 24 automated tests covering queue reindexing, duplicate paths, output naming, video and audio summaries, subtitle recommendations, audio compatibility, and storage requirements.

## Release identity

The marketing version is `0.7.0` and the build number is `7`. The candidate remains an arm64, locally ad-hoc-signed build rather than a Developer ID signed or notarized public distribution.

## Validation

`Scripts/build-release.sh` completed the Release build, strict app-signature verification, DMG creation, image verification, and SHA-256 generation. Independent read-only mounting confirmed that the packaged app is version `0.7.0 (7)`, is arm64, satisfies its designated requirement, and includes the Applications shortcut. The recorded checksum passed verification. Milestone 48 is complete; installation over the current app remains optional user validation.
