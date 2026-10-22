# SwiftyTranscoder 1.8.0 (18)

## Changes

- Help Choose Settings proposes an output size for manual review. Common smaller-for-Plex requests use tested sizing rules; audio settings remain unchanged.
- Explain Error uses Apple Intelligence on this Mac to explain an ordinary conversion failure and suggest a safe next step. Model-generated advice requires macOS 26 or later and an available on-device model. Ordinary conversion still supports macOS 14 and later.
- Incomplete color metadata triggers bounded decoded-frame sampling near the beginning, middle, and end. Only consistent explicit tags fill gaps. Missing information remains unknown; HDR evidence and conflicting tags cannot silently become SDR.
- The GUI remembers explicit SDR/BT.709 confirmation for an exact unchanged file using its path, file metadata, and full SHA-256 checksum. Forget Saved SDR Confirmation clears it. Fingerprinting reads the entire file and can increase load time for large untagged sources.
- Xcode launch arguments no longer mistakenly trigger CLI conversion. Script sandbox inputs, signing temporary files, and model copying support repeated signed builds.
- Inspection request IDs prevent results from an older source selection from replacing the current source's state.

## Validation

- Full sequential regression suite: 200 tests in 50 suites passed.
- Signed Debug build passed after the final GUI inspection guard and wording changes.
- Real-app confirmation covered sizing advice, saved SDR confirmation reload, and Explain Error after a controlled missing-source failure. Temporary test media was restored afterward.
- Metadata sampling was exercised on a temporary untagged video and correctly retained unknown color status. Tests cover HDR, conflicting tags, and changed-content invalidation even when file size and modification timestamp match.

## Distribution

The release is built for Apple Silicon, signed with Developer ID, and must pass fresh notarization, stapling, deep signature verification, Gatekeeper assessment, and mounted-DMG checks before publication. The installer includes FFmpeg, the four restoration models, the CLI launcher, and license notices. Release assets include a SHA-256 checksum and the matching third-party source archive.
