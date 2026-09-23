# Milestone 1 — Project foundation

## Goal

Create the smallest native macOS SwiftUI application that builds and opens one window. No media processing belongs in this milestone.

## Implemented

- A macOS application target named `SwiftyTranscoder`
- A SwiftUI application entry point
- One simple introductory window
- A minimum deployment target of macOS 14
- Basic build and run instructions in the project README

## Verification

Command-line Debug build with Xcode 27:

```sh
xcodebuild \
  -project SwiftyTranscoder.xcodeproj \
  -scheme SwiftyTranscoder \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/SwiftyTranscoder-DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Observed result: `BUILD SUCCEEDED`.

The initial SwiftUI `#Preview` block could not run its macro plug-in inside the restricted command-line build environment. Because the preview is optional and does not affect the application at runtime, it was removed. The app view itself was unchanged.

## Expected runtime result

Running the app should open one window containing the SwiftyTranscoder name, a film icon, and a short description.

## Follow-up

The user confirmed that the initial window launched successfully on the intended Mac on 2026-09-21. Milestone 1 is complete.
