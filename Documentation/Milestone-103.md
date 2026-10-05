# Milestone 103 — Source-specific model preparation

Eligible 624×352 sources now construct only the approved SD-frame model when it is available. Other source dimensions and development environments without the optional SD model retain the tiled model. A selected invalid SD model still fails its contract/loading check rather than silently falling back. The shared resource factory supplies both previews and full-video restoration.

The frame processor has a dedicated SD-only initializer. If supplied a frame outside its supported dimensions, it refuses tiled processing instead of invoking the SD model with an incompatible tensor. Existing tiled and dual-model initializers remain available to existing callers and comparison tests. Cancellation reaches whichever processors are present. Resource discovery and release requirements remain unchanged.

## Measured result

The same sequential 120-frame Release benchmark from milestone 102 passed with independent hardware-HEVC output validation on the M6 Mac mini:

| Measurement | Milestone 102 SD repeat | Single-model SD |
| --- | ---: | ---: |
| Model setup | 28.626 s | 13.349 s |
| Restoration | 12.302 s | 12.290 s |
| Total | 41.730 s | 26.430 s |
| Process peak resident memory | 2232.3 MiB | 2149.3 MiB |

Setup decreased approximately 53%, and total short-clip time decreased approximately 37%. Frame inference/output algorithms and compute-unit policy are unchanged. These are single-run comparison figures, not a guarantee for other clips or a prediction of full-episode speedup. Increasing peak memory across frame checkpoints remains unresolved; no concurrency or memory-lifetime changes were included.

## Verification and checkpoint

All eight focused factory tests passed, including a real SD frame restored with a nonexistent tiled model path, selected-invalid-model refusal, missing-SD tiled selection, and a complete short production restoration with audio and independent inspection. The Debug Xcode app build and `git diff --check` passed. Evidence is retained under `.build/milestone103-evidence/`.

The updated test app is `.build/Milestone101DerivedData/Build/Products/Debug/SwiftyTranscoder.app`. Hands-on review of the same SD preview remains pending. The installed 1.1.0 release was not replaced. Investigate frame-memory lifetime as a separate focused step before parallel processing.

The user subsequently confirmed the same SD preview seemed to start and process faster and played with good picture and audio. This completes the hands-on checkpoint for source-specific model preparation.
