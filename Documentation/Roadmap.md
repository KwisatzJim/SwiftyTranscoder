# Roadmap after milestone 101

These are planned milestones, not completed features. Work proceeds one focused change and user checkpoint at a time.

## 102 — Performance baseline on the current Mac

Measure an optimized Release build on a fixed representative clip. Record model preparation, extraction, image decoding, tensor preparation, inference, output writing, encoding, and peak memory. Compare the SD-frame and tiled paths where applicable. Core ML already uses `.all`, allowing CPU, GPU, and Neural Engine execution; device placement is managed by Core ML and is not established by that setting alone. Retain the baseline and repeatable benchmark command before changing concurrency.

## 103 — Model preparation overhead

Milestone 102 found repeatable approximately 28.6-second SD setup and increasing test-process peak memory across frame checkpoints. Begin with source-specific model loading; investigate live memory and frame-object lifetimes before proceeding to concurrency experiments.

Evaluate selecting only the model required by the source rather than eagerly loading both models for eligible SD frames. Evaluate shipping compiled models or safely reusing compiled resources, with model-contract and release-resource validation. Measure cold and repeated starts and preserve cancellation and failure reporting. Adopt one measured improvement at a time.

## 104 — Frame-memory lifetime

Milestone 104 focuses on the live-memory growth found in milestone 102. Measure live and peak resident memory, bound temporary AppKit/Core ML object lifetimes in synchronous sections, and verify SD and tiled output, cancellation, and performance before user acceptance.

### Subsequent performance experiments

Measure small, bounded worker counts and overlapping CPU image preparation with inference or encoding. Investigate PNG intermediate-file overhead and hardware decoding only where profiling justifies it. Preserve exact frame ordering, color, cancellation, storage limits, and output validation. Do not assume additional simultaneous Core ML predictions improve throughput or that maximum hardware utilization is the goal. Compare elapsed time and peak memory with the sequential baseline; retain only demonstrated improvements.

## 105 — Small command-line interface

Provide a local command-line entry point using the application's established inspection, planning, conversion, and validation logic:

```sh
swiftytranscoder "/path/to/input.mkv" \
    --preset plex \
    --output "/path/to/output.mp4"

swiftytranscoder "/path/to/input.mp4" \
    --preset plex \
    --gain-db 6 \
    --output "/path/to/output.mp4"
```

Accept compatible MKV, MP4, and M4V sources. For MP4/M4V audio processing, copy compatible video unchanged and apply the existing peak-protected +6 dB gain with audio re-encoding. This behavior already exists in the GUI; the CLI exposes it. Initially support the established 0 or +6 dB choices rather than implying arbitrary gain support. Define deterministic preset defaults, explicit gain control, help, progress, exit codes, interruption handling, and actionable errors for unresolved color or subtitle choices. Refuse overwriting sources or existing destinations. Validate before final promotion. Define CLI installation/discovery alongside packaged-app resources. AI restoration CLI controls can follow separately.

## 106 — Local 1.2.0 release

Package the accepted CLI, preview startup, source-specific model preparation, and frame-memory changes as 1.2.0 (12). Include the command launcher and usage instructions in the DMG, verify the mounted bundle's CLI, preserve previous releases, and complete installed-app acceptance.

## 107 — Batch restoration backend

Add sequential restoration jobs with source-specific plans, capacity checks, cancellation, and per-file results. Preserve the existing ordinary-conversion queue and single-source restoration behavior.

The isolated backend is implemented and verified in `Milestone-107.md`, including two short real-resource jobs. It remains unavailable in the interface until milestone 108.

## 108 — Batch restoration interface and acceptance

Expose reviewed restoration plans in the queue and verify multiple episodes end to end, including playback, memory/storage bounds, and cancellation. Package a release only after the focused changes pass their checkpoints.

The restoration-only batch interface is implemented and verified in `Milestone-108.md`. The user accepted short and one-minute batch playback and cancellation. Observed restoration memory stayed around 306–313 MB and dropped between jobs. All prepared milestone 108 checkpoints passed; full-episode batch acceptance remains a separate checkpoint before release packaging.

## 109 — Capped restoration dimensions

Full-episode testing exposed a missing resize from the model's 2× HD frames to the approved 1080p cap. The assembly correction passed regression and real HD integration tests; the user accepted the short mixed HD/SD batch with expected memory usage and good playback. See `Milestone-109.md`. Retry the original full-episode batch before release packaging.

## 110 — Visible progress and faster AI evaluation

Full HD testing continued to advance but proved too slow. Numeric batch/current-video percentages and a measured current-video time estimate are implemented. An experimental compact general-purpose AI choice measured about 2.07× faster on four HD frames, with approximately 79 seconds of preparation; a short complete production output retained all 48 frames and passed validation. The user accepted the optimized test app's short faster-AI playback. A full Pilot run reached 13% after approximately 72 minutes, projecting about 9.2 hours total if that rate holds. Full-episode completion remains pending. Further throughput work should profile real HD frame preparation, inference, blending, and image-file handling against the user's acceptable runtime rather than assume another model swap alone will suffice. See `Milestone-110.md`.

## 111 — Measured HD bottleneck and lightweight candidate

Profiling identified actual prediction as about 59% of compact-model frame processing. A separately verified, licensed FSRCNN candidate cut prediction time about 11.5× and total frame processing about 2.23×, rendering a validated ten-second Pilot clip in about 34 seconds after preparation. This is a lighter learned upscaler with different restoration strength; the user accepted picture and sound and authorized app integration. The current episode is untouched. Image packing/writing now accounts for about 65% of the candidate's frame processing and is the next profiling target. Runtime work remains open; see `Milestone-111.md`.


## 112 — Selectable lightweight AI

Integrate the accepted FSRCNN model into the development app, preserve the selected model through preview and reviewed batches, and validate a complete short output using bundled resources. This remains a separate optimized test app; installed 1.2.0 is unchanged. Image packing/writing remains the next measured performance target.


## 113 — Faster lossless working images

The user accepted the integrated lightweight preview. Measured PNG saving took 57% of FSRCNN frame-processing time. Stored PNGs retain exact pixels while trading larger bounded temporary files for speed; eight-frame testing measured about 16.6× faster writing and 2.04× faster overall frame processing. Storage preflight now accounts for full 2× intermediate dimensions and PNG overhead before the 1080p cap. The complete ten-second output validated in 18.237 seconds after preparation, versus 34.322 seconds before this change; 32 focused regression tests passed. The user accepted the optimized app preview on October 4, 2026. The full Lightweight AI Pilot run completed in 107 minutes (7:21–9:08 am). Observed app memory was 288.9 MB at 35% and 159.1 MB after completion. The user confirmed good full-output playback; this full-episode performance and playback checkpoint is accepted. A two-file Lightweight AI batch using Original Sin and a copy completed in 50 minutes (12:03–12:53 pm); observed memory at 12:05 pm was 108.1 MB. The user liked the first-video remaining-time estimate. The user confirmed good playback on both batch outputs. Full-episode and two-file batch acceptance checks are complete; release packaging is the next checkpoint. See `Milestone-113.md`.


## 114 — Local 1.3.0 release

The user authorized release packaging after accepting the full episode and two-file Lightweight AI batch. Version 1.3.0 (13) is packaged with all accepted model resources. The full 151-test suite, mounted-DMG resource/signature/CLI checks, real CLI conversions and cancellation, and complete short Lightweight AI restoration using mounted resources passed. Installer checksums passed alongside retained older releases. The user confirmed installed About shows 1.3.0 and the short Lightweight AI preview works. The scoped local release milestone is complete. See `Milestone-114.md`.


## 115 — Restoration completion summary

After installed 1.3.0 acceptance, the user authorized a focused completion-summary improvement. Completed single videos and batch rows now report whole-job elapsed time, average frames/s, and the selected AI model; batches also report total elapsed time. All 25 focused tests and the optimized app build passed. The user accepted the short full-restoration completion summary. See `Milestone-115.md`.


## 116 — Remember the AI model choice

The model picker now saves the user's explicit choice and restores it for new sources and across launches, while reviewed batch plans keep their own models. The optimized app build passed. The user confirmed the saved choice after relaunch; this checkpoint is accepted. See `Milestone-116.md`.


## 117 — Lightweight AI from the CLI

The explicit `--restore lightweight` flag uses the accepted GUI restoration engine, with plan/storage preflight, dry-run inspection, progress/time estimate, cancellation, validation, and completion statistics. Parser, real CLI restoration, and ordinary CLI regression checks passed. The installed 1.3.0 release is unchanged. The user accepted the CLI dry-run and restored test clip playback; this checkpoint is complete. See `Milestone-117.md`.


## 118 — Local 1.4.0 release

After acceptance of completion summaries, saved model preferences, and CLI Lightweight AI, the user authorized packaging version 1.4.0 (14). The installer passed 154 regression tests, resource/signature/integrity checks, and mounted real ordinary/AI CLI conversions, completion-statistics, refusal, and cancellation checks. Earlier installers are retained and checksum verified. The user confirmed installed version and CLI option availability. The scoped local release milestone is complete. See `Milestone-118.md`.


## 119 — Saved restoration progress foundation

After installed 1.4.0 acceptance, the user authorized resumable restoration. An isolated versioned checkpoint store fingerprints source/settings and records/verifies completed block hashes. Five persistence/refusal tests passed. Live restoration behavior is unchanged. Retention, exclusive ownership, real resume integration, and a user-facing resume action remain required. See `Milestone-119.md`.


## 120 — Resumable backend and CLI

Explicit persistent saved jobs now retain and verify validated blocks, lock out concurrent writers, safely discard interrupted work, and resume a matching source/settings/model through `--checkpoint-dir` and `--resume`. Complete regression and real interruption/reuse/output checks are automated. See `Milestone-120.md`.


## 121 — Single-video resume workflow

The development app exposes opt-in saved progress beside the output and a Resume action, with reused-frame reporting and timing based on new work. Build/resource/signature checks and 165 regression tests passed; 29 final focused tests cover lifecycle, persistence, refusal, and timing. The user confirmed resumed playback and the interface; these checkpoints are accepted. Version 1.5.0 packaging is the next step. Batch resume remains a later enhancement. See `Milestone-121.md`.


## 122 — Local 1.5.0 release

After the user accepted resumed playback and the single-video interface, version 1.5.0 (15) was packaged. All 165 tests, toolchain/model/resource/signature checks, DMG integrity, ordinary packaged CLI conversions/cancellation, and packaged Ctrl-C/force-quit/all-blocks resume checks passed. All completed outputs retain 240 frames and AC-3/AAC audio; saved blocks were reused unchanged and saved workspaces cleaned after success. Earlier installer checksums remain valid. The user confirmed installed 1.5.0 acceptance; this local release milestone is complete. See `Milestone-122.md`.


## 123 — Public GitHub repository and 1.5.0 release

The user authorized the public `KwisatzJim/SwiftyTranscoder` repository and MIT license for original code. Source and the `v1.5.0` tag are published, with the accepted installer, third-party component source bundle, and checksums attached to the GitHub Release. A clean source build passed, build/download instructions are current, and GitHub asset digests/sizes match local verified files. Publication is complete. See `Milestone-123.md`.


## 124 — Remove audio for support videos

Explicit per-file video-only ordinary conversion is implemented in GUI and CLI (`--audio omit`). MP4/M4V video is copied unchanged; MKV retains hardware encoding. Gain/AAC options are ignored, reviewed ordinary batch choices are retained, and validation requires zero output audio tracks. All 169 tests, ordinary-conversion regression checks, app verification, and real video/size/hash/refusal checks passed. The user confirmed playback and interface acceptance; packaging is underway. See `Milestone-124.md`.

## 125 — Correct malformed chapter duration

Chapter lists extending beyond the movie are omitted during ordinary conversion and full AI restoration. Corrected-copy duration and playback were confirmed by the user; focused tests and the app build passed. See `Milestone-125.md`.

## 126 — Detect delayed audio layouts

Bounded, expanded inspection identifies 5.1 E-AC-3 layouts missed by the default scan. The affected full conversion and playback were confirmed by the user. See `Milestone-126.md`.

## 127 — Local 1.6.0 release

Version 1.6.0 (16) packages accepted audio removal and both movie fixes. All 172 tests, installer integrity/signatures/resources, packaged conversion/refusal/cancellation checks, and retained-installer checksums passed. The user confirmed installed-version acceptance; GitHub publication and remote asset checksum verification are complete. See `Milestone-127.md`.

## 129 — Smaller output for support videos

Ordinary conversion has per-file Original/720p/480p size choices and CLI `--resolution`, with no upscaling, preserved proportions, hardware encoding when reducing size, reviewed batch retention, and validation of output dimensions. Short conversion checks show reduced file sizes and correct landscape/portrait output. The user confirmed controls and playback; local release packaging is authorized. See `Milestone-129.md`.


## 130 — Local 1.7.0 release

Version 1.7.0 (17) packages the accepted lower-resolution choices. All 175 tests, signature/resource/model checks, installer integrity, packaged ordinary/resolution/audio/cancellation checks, and retained-installer checksums passed. Installed-version acceptance, GitHub publication, fresh-source verification, and remote asset checksums are complete. See `Milestone-130.md`.
