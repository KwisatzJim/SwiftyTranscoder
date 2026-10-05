# Milestone 6 — First video-only conversion

## Step 1: Hardware encoder preflight and command policy

### Observed toolchain

- FFmpeg 9.0.2 at `/opt/homebrew/bin/ffmpeg`
- `hevc_videotoolbox` is available
- Main and Main10 HEVC profiles are available
- The encoder supports the source formats needed by the current samples, including 8-bit `yuv420p` and 10-bit `p010le`
- FFmpeg reports VideoToolbox as an available hardware device
- `allow_sw` defaults to false and will also be set explicitly, preventing silent software fallback

FFmpeg's VideoToolbox source confirms constant-quality mode is available on Apple Silicon and converts `-q:v` from a 0–100 scale into VideoToolbox's 0–1 quality value. This permits the existing preset values of 60 for 1080p and 50 for 2160p to be carried into the first controlled test instead of inventing a new rate-control choice.

### Initial video-only command policy

- Invoke FFmpeg directly, never through a shell
- Refuse overwrite with `-n`
- Map only the first video stream; exclude audio, subtitles, and data
- Encode HEVC with `hevc_videotoolbox` and `-allow_sw 0`
- Use Main for 8-bit SDR and Main10 for supported 10-bit sources
- Preserve source dimensions by applying no scale filter
- Preserve timestamps/frame rate rather than requesting 60 fps
- Tag HEVC as `hvc1` for Apple-oriented MP4 compatibility
- Write first to a clearly named `.partial.mp4` path
- Move the completed temporary output to the approved destination only after FFmpeg exits successfully and output validation passes
- Emit machine-readable progress for the app and keep diagnostic error output

No application conversion code or source-media write was added in this step. The next step is a short generated-media hardware smoke test before attempting a real MKV.

## Step 2: Generated-media hardware smoke test

A two-second 1920 × 1080 test pattern at 24000/1001 fps was encoded to a temporary video-only MP4 using:

- `hevc_videotoolbox`
- `-allow_sw 0`
- Main profile and 8-bit `yuv420p`
- Constant quality 60
- `hvc1` sample-entry tag
- Passthrough frame-rate mode
- No-overwrite mode

The restricted command environment initially failed to access the VideoToolbox compression service with error `-12908` and correctly refused software fallback. The unchanged command succeeded when allowed normal access to macOS hardware services. FFmpeg identified the encoder as `com.apple.videotoolbox.videoencoder.ave.hevc` and encoded 48 frames.

Post-encode `ffprobe` validation reported:

- HEVC Main, `hvc1`
- 1920 × 1080, `yuv420p`
- Both reported frame-rate fields: 24000/1001
- Duration: 2.002 seconds
- Frame count: 48
- File size: 1,429,355 bytes

The temporary artifact is `/tmp/SwiftyTranscoderHardwareSmoke-02.partial.mp4`. No user media was read or modified.

## Step 3: Validated command construction

The app now has a non-executing command builder for the first video-only path. It creates FFmpeg arguments only after validating:

- A video stream exists and uses H.264 or HEVC
- The source is explicitly 8-bit `yuv420p` SDR
- An output location is selected
- Neither the final output nor its `.partial.mp4` path exists
- FFmpeg is installed in a supported location

The generated command requires VideoToolbox with software fallback disabled, maps only the first video stream, preserves source size and timestamps, uses the existing quality preference for the source resolution, refuses overwrite, retains metadata and chapters where supported, emits machine-readable progress, and targets the incomplete path first.

This step constructs and validates arguments only; it does not launch FFmpeg or write media.

### Verification

The Debug application build succeeded. The command builder was exercised with the real Reacher inspection result and a nonexistent temporary destination. Assertions confirmed hardware HEVC, disabled software fallback, quality 60, passthrough frame-rate mode, no-overwrite mode, excluded audio and subtitles, and the expected `Reacher-Command-Check.partial.mp4` intermediate path. The command was printed but not executed, and neither output path was created.

## Step 4: Execution controller

The app now exposes an explicitly labeled `Convert Video Only` action when the command preflight succeeds. The controller:

- Runs the validated hardware-only command without a shell
- Parses machine-readable FFmpeg progress
- Supports cancellation by terminating FFmpeg
- Keeps failed or cancelled output clearly labeled `.partial.mp4`
- Probes a successful partial output before promotion
- Requires exactly one HEVC `hvc1` video stream with matching dimensions and frame rate and no audio or subtitles
- Rechecks the final destination immediately before moving the validated output
- Never overwrites an existing final or partial output
- Shows a concise failure plus the last diagnostic lines

### Cancellation verification

The user started a real Reacher video-only conversion and cancelled it after encoding began. The app reported cancellation and retained the incomplete output as:

`Reacher - s04e08 - Cut.partial.mp4`

This confirms that cancellation does not promote an unfinished file to the final `.mp4` name. An initial cleanup implementation only exposed the partial file retained in the current controller session. Runtime testing caught that reopening the app lost that in-memory state even though the partial file remained on disk.

The output preflight now independently derives and checks the expected `.partial.mp4` path whenever an output folder is selected. An existing partial is shown with its full path, and the app offers an explicit, confirmation-gated action to move that exact file to the macOS Trash. This makes retry cleanup work after relaunch without silently deleting output.

The user confirmed the corrected build detected the partial file after relaunch, displayed its exact `.partial.mp4` path, required confirmation, and moved it to the macOS Trash.

### Complete conversion verification

The user completed the full Reacher video-only conversion. The controller validated and promoted the partial output to:

`/path/to/SwiftyTranscoder/Reacher - s04e08 - Cut.mp4`

The user confirmed that the resulting file looks good and plays correctly. A separate `ffprobe` inspection confirmed:

- One HEVC Main video stream with the Apple-compatible `hvc1` tag
- 1920 × 960, 8-bit `yuv420p`
- Source frame rate preserved at 24000/1001
- Duration 3463.46 seconds
- No audio or subtitle streams, as intended for the video-only checkpoint
- File size 598,836,408 bytes

Runtime feedback also exposed a misleading warning after successful promotion: once the final file appeared, the conversion-plan view treated it as a pre-existing conflict. The plan now recognizes an output completed by the current controller session and does not label that successful result as a conflict. A genuinely pre-existing destination remains blocked.
