# Milestone 3 — Human-readable analysis

## Step 1: Video and audio overview

### Goal

Present the most useful source facts in ordinary language while retaining the complete expandable technical report from Milestone 2.

### Implemented

- Video resolution, familiar codec name, frame rate, and SDR/HDR classification
- Primary audio layout, familiar codec name, language, and an Atmos note only when metadata explicitly indicates it
- A visible subtitle state that says recommendations have not yet been evaluated
- Unknown metadata is reported as `Unknown` or `Not identified`, never inferred

Subtitle selection rules remain out of scope until Milestone 4.

### Verification

The Debug application build succeeded. The summary model was also exercised with the real probe results for two representative sources:

- `Reacher - s04e08 - Cut.mkv`: H.264, 1920 × 960, 23.976 fps, SDR; Dolby Digital Plus 5.1 with Atmos indicated by metadata; 38 subtitle tracks.
- `Designated Survivor - s01e11 - Warriors.mkv`: H.264, 1920 × 1080, 23.976 fps, picture range not identified; DTS 5.1; 2 subtitle tracks.

The second result verifies that missing color declarations remain visibly unknown rather than being classified as SDR. Runtime layout confirmation remains pending.

The user confirmed that the overview facts were correct and the cards rendered properly, but reported that the initial window required scrolling. The default window was enlarged to 900 × 760 points, outer spacing was tightened, and the video and audio cards were placed side by side. The window remains user-resizable; scrolling is retained for smaller windows and expanded technical details.

After reviewing the revised layout, the user requested a more compact row. The subtitle card was moved to the right of Primary Audio, placing all three overview cards in one row.

The user confirmed the three-column layout. Milestone 3 is complete.
