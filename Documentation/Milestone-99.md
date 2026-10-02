# Milestone 99 — Version 1.1 readiness checkpoint

The user confirmed the faster model's 10-second preview and full Alphas episode looked good. The remembered start was approximately 8:19 pm and completion was 11:44 pm, giving an approximate 3 hours 25 minutes, versus the earlier 6 hours 49 minutes. This is user-reported timing with an approximate start, not an instrumented runtime measurement. It is consistent with the native benchmark's approximately 2× improvement.

Saved AAC defaults, folder selection, and Finder drag and drop each passed their separate hands-on checkpoints. README capability descriptions now distinguish the packaged 1.0 release from the restoration-enabled development builds.

The complete Release regression suite passed: 116 tests in 30 suites, including real Core ML processing and a short production restoration. The Milestone 98 Release app had already passed its Xcode build and signed-bundle/resource verification. No runtime code changed in this readiness checkpoint.

## Remaining release gates

1. Confirm the newly restored full episode on the representative Plex clients, including audio synchronization, seeking, and Direct Play/Stream behavior. Earlier restoration outputs passed playback checks, but those do not establish the new model output's client behavior.
2. Set the 1.1 version/build metadata and write the release notes, including single-source restoration, eligibility limits, and the measured SD performance scope. Do not imply arbitrary SD sizes share the faster shape-specific path.
3. Build the self-contained release DMG, verify its mounted app and checksums, and perform a launch check from the packaged app. Preserve the existing 1.0 DMG.

Batch restoration, 4K output, HDR restoration, OCR, automatic cropping, and public notarized distribution remain outside this release checkpoint. The currently built applications still identify as 1.0.0 (10); they are development artifacts, not a published 1.1 release.
