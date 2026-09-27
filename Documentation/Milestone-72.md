# Milestone 72 — Native Silent HEVC Assembly

## Goal

Assemble an already-restored native PNG sequence into a validated, silent hardware-HEVC MP4 segment while keeping audio and final-output promotion outside this boundary.

This remains internal development infrastructure and is not available in the application interface.

## Assembly contract

`RestorationVideoAssembly` accepts between 1 and 240 restored PNG frames. It requires one complete numeric sequence beginning at frame 1, a shared filename width and directory, positive even output dimensions, a valid rational frame rate, and explicit limited-range SDR color metadata.

`RestorationVideoAssembler` launches the bundled FFmpeg helper without a shell. The command:

- uses the exact approved frame rate;
- limits input to the approved frame count;
- produces no audio, subtitles, or data streams;
- uses `hevc_videotoolbox` with software fallback disabled;
- produces HEVC Main, `yuv420p`, and the `hvc1` compatibility tag;
- passes the approved range, matrix, transfer, and primary metadata through both `setparams` and encoder/container options; and
- writes only `restored-video.partial.mp4` without overwriting an existing file.

Progress is derived from FFmpeg's machine-readable completed-frame count. Cancellation terminates the active media helper. A cancelled or failed encode may retain only the clearly labeled partial MP4 for diagnosis; it is never presented as a completed output.

## Independent validation

After FFmpeg succeeds, the assembler invokes ffprobe and accepts the partial segment only when it has:

- exactly one video stream and no audio or subtitle streams;
- HEVC Main, `hvc1`, and `yuv420p`;
- the exact approved dimensions and average frame rate;
- exact approved SDR color metadata;
- duration consistent with frame count divided by frame rate; and
- a nonzero file size.

Tests cover command construction, incomplete-sequence rejection, process and validation boundaries, existing-output refusal, and cancellation with labeled-partial retention.

The representative four-frame native sequence was encoded with hardware-only VideoToolbox and independently reported:

- HEVC Main, `hvc1`, `yuv420p`;
- 1248×704;
- 24000/1001 fps;
- limited range, SMPTE 170M matrix and primaries, BT.709 transfer;
- no audio or subtitle stream;
- 0.166833 seconds; and
- 51,245 bytes.

The complete test suite passes 64 tests across 18 suites. The full macOS application builds successfully with Swift 6 complete concurrency checking.

## Result and next gate

SwiftyTranscoder can now turn a native restored-frame sequence into a strictly validated silent hardware-HEVC segment without Python. The model and entire restoration path remain unavailable to production UI.

The next milestone can connect extraction, restoration, and silent-video assembly behind one concrete stage executor, with aggregate progress and cancellation across stage transitions. Audio muxing and promotion to a final user output will remain outside that orchestration gate.
