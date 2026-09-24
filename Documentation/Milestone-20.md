# Milestone 20 — Local 0.2.0 Release Candidate

## Goal

Package the confirmed post-0.1.0 improvements as a new locally installable release candidate.

## Included changes

- Reset conversion state when a different source is selected.
- Select and review multiple MKV/MP4 sources in an ordered queue.
- Advance explicitly between completed queue items.
- Report completed/current/waiting queue status.
- Display a smoothed live encoding ETA and finalization state.
- Build, verify, and package releases through `Scripts/build-release.sh`.

## Release identity

The marketing version is `0.2.0` and the build number is `2`. The candidate remains an arm64, locally ad-hoc-signed build rather than a Developer ID signed or notarized public distribution.

## Validation

`Scripts/build-release.sh` completed the Release build, strict app-signature verification, DMG creation, DMG verification, and SHA-256 generation. Independent read-only mounting confirmed that the packaged app is version `0.2.0 (2)`, is arm64, satisfies its designated requirement, and includes the Applications shortcut. The recorded SHA-256 checksum also passed verification.

The user installed the candidate into `/Applications`, confirmed About reports `0.2.0 (2)`, and confirmed multi-file selection displays the queue. Independent verification of the installed app passed strict signature checks and confirmed the arm64 architecture and version/build metadata. Milestone 20 is complete.
