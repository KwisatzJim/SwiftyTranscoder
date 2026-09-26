# Milestone 36 — Local 0.6.0 Release Candidate

## Goal

Package the runtime-confirmed batch safety and validation-explanation improvements as a new locally installable release candidate.

## Included changes

- Check the conservative storage requirement for the whole approved batch on each destination volume.
- Detect duplicate output paths before a batch starts and keep the start action disabled until they are resolved.
- Display the exact validation reason beneath a disabled approval or conversion button.

## Release identity

The marketing version is `0.6.0` and the build number is `6`. The candidate remains an arm64, locally ad-hoc-signed build rather than a Developer ID signed or notarized public distribution.

## Validation

`Scripts/build-release.sh` completed the Release build, strict app-signature verification, DMG creation, DMG verification, and SHA-256 generation. Independent read-only mounting confirmed that the packaged app is version `0.6.0 (6)`, is arm64, satisfies its designated requirement, and includes the Applications shortcut. The recorded SHA-256 checksum also passed verification.

The user installed the candidate into `/Applications` and confirmed About reports `0.6.0 (6)`. Milestone 36 is complete.
