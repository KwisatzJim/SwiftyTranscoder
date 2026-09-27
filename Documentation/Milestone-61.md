# Milestone 61 — Version 1.1 Restoration Architecture

## Goal

Define a safe path toward optional AI-assisted upscaling and restoration without changing the confirmed 1.0 conversion path or describing conventional image filters as AI.

## Framework findings

Apple's frameworks divide the work into distinct responsibilities:

- [Core ML](https://developer.apple.com/documentation/coreml/) runs a selected machine-learning model locally using the CPU, GPU, or Neural Engine. Core ML is an execution framework; it does not supply a general video-restoration model by itself.
- [MPSImageLanczosScale](https://developer.apple.com/documentation/metalperformanceshaders/mpsimagelanczosscale) performs high-quality conventional Lanczos resizing. It is useful as a comparison or fallback but is not AI upscaling.
- [CINoiseReduction](https://developer.apple.com/documentation/coreimage/cinoisereduction) provides conventional noise reduction and sharpening controls. It must not be labeled AI restoration.
- [AVAssetReader](https://developer.apple.com/documentation/avfoundation/avassetreader) and [AVAssetWriter](https://developer.apple.com/documentation/avfoundation/avassetwriter) provide frame-oriented reading and MP4 writing for formats AVFoundation supports. SwiftyTranscoder still needs its focused FFmpeg layer to accept MKV sources and preserve the established subtitle and audio behavior.

## Product boundaries for 1.1

Restoration will be visibly optional and off by default. The app will never silently upscale, denoise, sharpen, crop, or replace the normal 1.0 path.

The first restoration workflow will:

- remain fully local and require no upload;
- present a before/after still-frame preview before a plan can be approved;
- identify the exact processing method and model rather than using a vague **Enhance** label;
- keep ordinary Metal/Core Image processing clearly separate from Core ML processing;
- reject HDR, HLG, Dolby Vision, or unidentified color until a color-safe path is proven;
- preserve aspect ratio and frame rate;
- limit the first AI-upscale target to 1080p and never enlarge either dimension by more than 2×;
- avoid upscaling sources already at or above 1080p;
- retain the original source untouched and use the same partial-output, cancellation, and final-validation protections as version 1.0; and
- require a normal non-restored conversion option to remain available for every supported source.

These initial limits deliberately prioritize older SD and 720p SDR material, where a 1080p restoration option is useful and computational cost is bounded. A later evidence-based milestone may consider 4K output.

## Model acceptance gate

No model will be embedded or downloaded until it has a documented license permitting redistribution, a pinned checksum and version, a known input/output color and pixel range, acceptable memory use on the target Apple Silicon Mac, and repeatable quality tests that do not invent distracting facial or text detail.

Candidate evaluation will compare the model against ordinary Lanczos scaling and the unchanged 1.0 output. Tests will include faces, film grain, animation, titles, subtitles, dark scenes, motion, and compression artifacts. A model that looks impressive on selected still images but flickers between video frames will be rejected.

## Proposed implementation sequence

1. Build an offline model-evaluation harness and select a redistributable Core ML model from measured evidence.
2. Add read-only representative-frame extraction and a before/after preview surface.
3. Prove deterministic Core ML processing on still frames, including color and dimension validation.
4. Prove a short-clip frame pipeline with bounded memory, cancellation, progress, and temporal-consistency checks.
5. Reintegrate the established audio gain, subtitle, chapter, metadata, and partial-output safeguards.
6. Add explicit plan controls and batch behavior only after the short-clip pipeline passes.
7. Validate representative full outputs through Safari, Plex HTPC, Firefox/Plex Web, and Roku before packaging version 1.1.

## Result

The 1.1 restoration boundary and implementation order are defined without changing runtime behavior. The next focused milestone is the model-evaluation harness and acceptance report; application controls will not be added until there is an honestly labeled, redistributable model worth selecting.
