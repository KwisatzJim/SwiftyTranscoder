# Milestone 16 — Application Icon and Identity

## Goal

Replace the generic executable icon with a distinctive SwiftyTranscoder identity suitable for Finder, the Dock, and the native About panel.

## Design

The approved icon combines a film frame, circular teal-blue conversion arrows, and a warm amber audio waveform on a midnight-blue macOS-style tile. The three elements represent video conversion and the application's accessibility-oriented audio gain feature without using text or imitating another media application.

The original generated master is preserved at `Documentation/Artwork/SwiftyTranscoder-AppIcon-Master.png`. A complete macOS `AppIcon.appiconset` contains the required 16, 32, 128, 256, 512, and 1024-pixel representations. Both Debug and Release configurations use the `AppIcon` asset.

The asset catalog compiled successfully and produced a valid `AppIcon.icns` with the expected generated Info.plist keys. Initial runtime testing nevertheless showed the generic icon in both the Dock and About panel, consistent with macOS retaining the application image for repeatedly rebuilt development bundles. Explicitly loading the bundled icon into `NSApplication.applicationIconImage` at startup corrected the Dock icon. The automatically generated About panel still omitted it, so SwiftyTranscoder now replaces only the standard app-info menu command with AppKit's native About panel while explicitly supplying the same bundled icon and current bundle version. After closing older instances and launching the corrected build, the user confirmed the approved icon appears in both the Dock and About panel. Milestone 16 is complete.
