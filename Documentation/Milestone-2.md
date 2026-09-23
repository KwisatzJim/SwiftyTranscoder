# Milestone 2 — Choose and inspect one MKV

## Step 1: Native MKV selection

### Goal

Allow the user to select one MKV using the standard macOS file picker, without inspecting or modifying the media yet. Keeping selection separate from inspection makes file-access problems easier to identify.

### Expected result

Selecting an MKV should return to the main window and show its filename and containing folder. Cancelling the picker should leave the app unchanged.

### Safety

This step does not open, inspect, or modify the selected file. `ffprobe` integration belongs to the next step after file selection is confirmed.

### Verification

The Debug application build completed successfully with Xcode 27. The first restricted build attempt could not start Xcode's compiler helper for SwiftUI's `@State`; rebuilding with the compiler helper permitted succeeded without a source change. The only warning reported was the expected absence of App Intents metadata.

## Step 2: Read-only typed inspection

### Implemented

- Runs `ffprobe` directly without invoking a command shell
- Requests container, stream, chapter, and attachment metadata as JSON
- Decodes the JSON into typed Swift models
- Shows the first video's codec and resolution plus stream and chapter counts
- Reports the affected filename and reason when launching, probing, or decoding fails

No output file or media-writing operation exists in this step.

### Verification

The Debug application build succeeded. A separate integration check compiled the same Swift models and probe service, then inspected `Reacher - s04e08 - Cut.mkv`. It decoded 1 video stream, 1 audio stream, 38 subtitle streams, 0 chapters, and 0 attachments, matching the existing media analysis.

The user confirmed that the app successfully inspected the Reacher sample at runtime.

## Step 3: Complete technical report

### Implemented

- Container format, duration, file size, and overall bitrate
- Counts for video, audio, subtitle, chapter, and attachment records
- Expandable per-stream details, including language, title, codec, dimensions, frame rate, channel layout, bitrate, and relevant dispositions when available
- Explicit `Unknown`, `None`, or `No additional metadata` labels instead of invented values

The details are collapsed by default so subtitle-heavy sources do not overwhelm the main screen.

### Verification

The Debug application build succeeded. The Swift probe integration check also decoded `Designated Survivor - s01e11 - Warriors.mkv` as 1 video stream, 1 audio stream, 2 subtitle streams, 7 chapters, and 0 attachments, matching the prior analysis. Runtime confirmation of the expanded details remains pending.
