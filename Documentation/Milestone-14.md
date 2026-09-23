# Milestone 14 — Release Build Baseline

## Goal

Verify that the complete application builds and launches under Xcode's optimized Release configuration before packaging or signing decisions are made.

## Current release identity

- Display name: SwiftyTranscoder
- Bundle identifier: `com.jimkelley.SwiftyTranscoder`
- Version/build: `0.1.0 (1)`
- Minimum macOS: 14.0
- Application category: Video
- Architecture: Apple Silicon `arm64`
- Hardened runtime: enabled in project settings

Version `0.1.0` is retained while Roku validation remains pending and Homebrew FFmpeg dependencies are still external.

## Build verification

An optimized Release build completed successfully at `/tmp/SwiftyTranscoder-ReleaseDerivedData/Build/Products/Release/SwiftyTranscoder.app`. The only warning is the expected App Intents metadata notice because the project does not use App Intents. Binary inspection shows only Apple system frameworks and Swift runtime libraries linked directly; FFmpeg remains a separately launched Homebrew dependency rather than a linked library.

The user confirmed that the optimized Release build opened normally and that MKV/MP4 selection, inspection, and the conversion plan still worked. The Release build baseline is complete.
