# Milestone 59 — Release Gate Hardening

## Goal

Turn the checks used manually for the `0.9.0` candidate into repeatable release requirements before assigning the `1.0.0` version.

## Release gate

`Scripts/build-release.sh` now:

- runs the complete Swift regression suite before building release artifacts;
- verifies the outer application and both bundled helpers with strict code-signature checks;
- requires an arm64 application, both executable helpers, all six third-party notices, FFmpeg and FFprobe 9.0.2, subtitle rendering, and VideoToolbox HEVC encoding;
- rejects Homebrew or `/usr/local` runtime-library paths in either bundled helper;
- mounts the newly created DMG read-only and repeats the application verification from the packaged copy; and
- requires the Applications shortcut before publishing the DMG and checksum to `dist`.

The shared checks live in `Scripts/verify-release-app.sh`, so the built application and the independently mounted application are evaluated by the same rules. Cleanup detaches a mounted image even when a later verification fails.

## Validation

Both release scripts pass Bash syntax validation. The verifier rejects missing arguments with its documented usage status. Its complete positive path will run as part of the `1.0.0` release build, first against the Release application and again against the mounted DMG.

Milestone 59 is complete. The next milestone assigns the `1.0.0 (10)` identity and runs this strengthened gate to create the final local release.
