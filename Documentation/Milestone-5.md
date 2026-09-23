# Milestone 5 — Conversion plan preview

## Step 1: Visible proposed actions

### Goal

Show the proposed output behavior before adding any controls or conversion implementation. Missing required choices must be visible rather than silently defaulted.

### Initial plan

- MP4 container
- HEVC video using Apple hardware
- Preserve source dimensions without upscaling
- Preserve source frame rate
- AC-3 5.1 compatibility audio at 224 kb/s
- +6 dB gain with peak protection
- Burn the deterministic forced-English recommendation, or explicitly omit/require selection
- No output path until the user chooses one

The preview warns when an output location is missing, a subtitle choice is ambiguous, required streams are absent, or Atmos will be lost from the compatibility audio track.

This step contains no conversion button and no media-writing code.

## Step 2: Gain control

The +6 dB preference is now a visible switch in the plan. It defaults on and explicitly includes peak protection. Turning it off immediately changes the plan to `Gain: Off`. Choosing a different source resets the gain preference to its normal enabled default.

## Step 3: Subtitle control

The deterministic subtitle recommendation now initializes an editable menu. The user can burn any discovered subtitle stream or explicitly omit subtitles. The default Reacher choice remains stream 2. An ambiguous recommendation initially displays `Choose a track…` and continues to warn until the user chooses a stream or omission; it never selects a candidate silently.

## Step 4: Output folder and conflict preflight

The user chooses a destination folder, and the app proposes the source basename with an `.mp4` extension. Choosing a folder does not create or modify any file. If the proposed destination already exists, the plan displays a blocking conflict warning and does not silently overwrite it.

### Verification

The Debug application build succeeded. A preflight check pointed the same plan model at a temporary file that already existed. The model reported `outputConflict`, added the explicit existing-file warning, and left the file unchanged at 26 bytes.

The user confirmed gain changes, subtitle changes and reset behavior, and output-folder selection with predictable filename generation. Milestone 5 is complete.
