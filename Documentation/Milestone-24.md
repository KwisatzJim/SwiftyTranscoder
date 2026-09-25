# Milestone 24 — Local 0.3.0 Release Candidate

## Goal

Package the runtime-confirmed AAC compatibility and unattended batch features as a new locally installable release candidate.

## Included changes

- Optionally add a secondary, non-default AAC stereo compatibility track while retaining primary/default AC-3.
- Validate both audio tracks before promoting an output to its final filename.
- Review and approve every queued conversion before encoding starts.
- Run an approved batch sequentially without interaction between successful conversions.
- Stop the batch safely on cancellation, failure, a missing plan, or a newly conflicting destination.

## Release identity

The marketing version is `0.3.0` and the build number is `3`. The candidate remains an arm64, locally ad-hoc-signed build rather than a Developer ID signed or notarized public distribution.

## Validation

`Scripts/build-release.sh` completed the Release build, strict app-signature verification, DMG creation, DMG verification, and SHA-256 generation. Independent read-only mounting confirmed that the packaged app is version `0.3.0 (3)`, is arm64, satisfies its designated requirement, and includes the Applications shortcut. The recorded SHA-256 checksum also passed verification.

The user installed the candidate into `/Applications`, confirmed About reports `0.3.0 (3)`, confirmed normal launch, and confirmed that selecting multiple videos presents the review-first queue. Independent inspection of the installed application confirmed version `0.3.0 (3)`, arm64 architecture, a valid on-disk signature, and satisfaction of its designated requirement. Milestone 24 is complete.
