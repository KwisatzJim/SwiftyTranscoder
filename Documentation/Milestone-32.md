# Milestone 32 — Local 0.5.0 Release Candidate

## Goal

Package the runtime-confirmed post-conversion and batch-review improvements as a new locally installable release candidate.

## Included changes

- Reveal a successfully validated output directly in Finder.
- Separate final-plan approval from the action that starts batch encoding.
- Show an explicit all-plans-approved checkpoint before launch.
- Select, reopen, revise, and reapprove any queued plan without losing the other approvals.

## Release identity

The marketing version is `0.5.0` and the build number is `5`. The candidate remains an arm64, locally ad-hoc-signed build rather than a Developer ID signed or notarized public distribution.

## Validation

`Scripts/build-release.sh` completed the Release build, strict app-signature verification, DMG creation, DMG verification, and SHA-256 generation. Independent read-only mounting confirmed that the packaged app is version `0.5.0 (5)`, is arm64, satisfies its designated requirement, and includes the Applications shortcut. The recorded SHA-256 checksum also passed verification.

The user installed the candidate into `/Applications`, confirmed About reports `0.5.0 (5)`, confirmed normal launch, confirmed **Show in Finder** appears after completion, and confirmed both the explicit batch-ready checkpoint and approved-row selection are present. Milestone 32 is complete.
