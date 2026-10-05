# Milestone 106 — Local 1.2.0 release

The user confirmed normal Finder launch of the CLI-enabled development app after accepting its MP4 and MKV command-line conversions and the preview startup, source-specific model preparation, and frame-memory changes.

Version metadata is 1.2.0, build 12. This release includes:

- A small CLI sharing the GUI's inspection, ordinary conversion, audio gain, output validation, and partial-file behavior.
- Background preview model preparation with a visible preparing state and cancellation.
- Loading only the approved model required for the source.
- Scoped cleanup of temporary AppKit/Core ML objects in synchronous frame operations.

The DMG includes the app, Applications shortcut, executable lowercase CLI launcher, and standalone usage instructions. The launcher defaults to the installed app in `/Applications` and supports an explicit alternate bundle path. Packaging does not install the app or edit the shell's PATH.

Benchmarks on the M6 Mac mini reduced SD setup from approximately 28.6 to 13.3 seconds and held live test-process memory near 141 MiB during a 120-frame SD sample. Restoration speed remained essentially unchanged. These do not establish an episode-length memory bound or an inference speedup.

The release remains local and ad-hoc signed. Earlier releases are retained. AI restoration CLI support, batch restoration, and concurrency experiments remain outside this release.

## Packaging progress

The first release-pipeline run passed all 121 tests in 31 suites, then stopped before the app build because `pkg-config` was absent on the new Mac. Missing pkgconf, CMake, and the Python 3.12 interpreter required by the copied model-validation environment were installed before restarting the existing pipeline. Packaging evidence and installed-app acceptance are recorded below when complete.

## Completed packaging evidence

The restarted release pipeline passed all 121 tests in 31 suites, rebuilt and checked the pinned self-contained media toolchain, validated both pinned model resources, built the signed Release app as 1.2.0 (12), and verified the app both before packaging and from the read-only mounted DMG. The bundled and mounted app's CLI help checks passed, as did the mounted launcher's help check. Signing, architecture, third-party notices, helper linkage, media capabilities, and DMG internal checksum checks passed.

Artifact: `dist/SwiftyTranscoder_1.2.0_arm64.dmg`.

SHA-256: `591c4875d4721a27a2b9cb013a09c74bc03b3ae78ea9a7dfe6b6ee16bf1d99d1`.

Independent `shasum -a 256 -c SHA256SUMS.txt` passed for the retained 1.0, 1.1, and new 1.2 artifacts. A second read-only DMG mount passed actual MP4 gain and MKV hardware-HEVC conversions, output validation, MP4 elementary-stream checksum preservation, existing-output refusal, and active SIGINT cancellation with partial retention. That mount was ejected after verification. Evidence logs and the packaged-CLI harness are retained under `.build/milestone106-evidence/`. Shell syntax checks and `git diff --check` passed.

The app was not installed automatically and no public upload occurred. The next user checkpoint is installing the DMG's app and confirming normal Finder launch of version 1.2.0. Installed GUI/CLI and restoration acceptance remain pending.

## Installed-release acceptance

The user confirmed installation and normal launch, with About showing version 1.2.0. The user copied the packaged CLI launcher to `/usr/local/bin` and confirmed `swiftytranscoder --help` works by command name. The user then confirmed a short AI restoration preview from the installed release completed successfully and looked and sounded good. Together with the packaged CLI conversion checks and earlier hands-on MP4/MKV playback checks, these complete the scoped 1.2.0 release acceptance checkpoint. Episode-length memory behavior and batch restoration remain separate future work.
