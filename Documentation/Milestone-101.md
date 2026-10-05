# Milestone 101 — Restoration preview startup responsiveness

The installed 1.1.0 release passed user review of three ordinary conversions and a short AI restoration preview. The preview initially made the interface unresponsive for several seconds on the user's reported Mac mini M6 with 24 GB RAM.

Code inspection found synchronous Core ML model compilation and loading in `RestorationPreviewController.start`, which runs on the main actor that services the interface. This is a likely explanation for the observed freeze, rather than a measured timing diagnosis.

Preview resource lookup and frame-processor construction now run in a detached background task. The interface immediately enters a preparing state with a Cancel control. Cancellation propagates to preparation and is checked before extraction starts; an already-running synchronous Core ML compile/load call must return before cancellation completes. Progress monitoring preserves the cancelling state.

The Debug Xcode app build passed, and `git diff --check` passed. Hands-on confirmation of responsive startup, successful output, and cancellation during preparation remains pending. The test app is `.build/Milestone101DerivedData/Build/Products/Debug/SwiftyTranscoder.app`; it is not a newly packaged release. This change is limited to the preview controller and its preparing display.

The user subsequently confirmed the preview test passed. Responsive startup and successful preview output are accepted; cancellation during preparation was not separately reported.
