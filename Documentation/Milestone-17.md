# Milestone 17 — Local 0.1.0 Release Candidate

## Goal

Produce a locally installable first release candidate with the completed icon, validated media workflow, and clear separation between personal signing and public Developer ID distribution.

## Signing status

The Xcode target now uses the `Jim Kelley (Personal Team)` development team identifier `MV65BFBFT7` with automatic signing. Xcode provisioned an `Apple Development` signature and completed a Release build, but strict verification rejected its certificate chain with `CSSMERR_TP_NOT_TRUSTED`, while command-line keychain inspection continued to report zero valid identities. That build was rejected and was not packaged.

The local-only candidate was rebuilt explicitly with Xcode's `Sign to Run Locally` ad-hoc identity. Strict deep verification reports that the app is valid on disk and satisfies its designated requirement. It is arm64, version `0.1.0 (1)`, uses bundle identifier `com.jimkelley.SwiftyTranscoder`, includes the approved icon, and has the hardened runtime enabled. This is not Developer ID signing or Apple notarization.

`dist/SwiftyTranscoder_0.1.0_arm64.dmg` contains the verified app and an Applications shortcut. `hdiutil verify` confirmed a valid disk-image checksum, and the app was mounted back from the DMG and passed strict signature verification again. The DMG SHA-256 is recorded in `dist/SHA256SUMS.txt`.

Roku, Safari/MacBook, and Firefox/Rossum/HomePod Plex validation is complete. The DMG candidate was installed into `/Applications`, launched successfully, displayed version `0.1.0 (1)`, and found the external `ffprobe` tool when a source file was selected.

The installed `/Applications/SwiftyTranscoder.app` also passed direct verification: it is a valid arm64 ad-hoc-signed app, satisfies its designated requirement, uses bundle identifier `com.jimkelley.SwiftyTranscoder`, declares the `AppIcon` asset, and has the hardened runtime enabled.
