# Milestone 104 — Restoration frame-memory lifetime

The user confirmed milestone 103's preview started and processed sooner and played with good picture and audio. The next focused investigation addressed increasing resident memory before attempting concurrent inference.

## Diagnosis and change

The opt-in Release benchmark now reports current resident memory with Mach task information alongside the cumulative peak from `getrusage`. On the same M6, the unchanged SD path reached 654.1/1180.0/1706.7/2229.4 MiB live resident memory after 30/60/90/120 frames. Live memory dropped to 1084.1 MiB during encoding, showing that peak-only observations understated the distinction between retained temporary allocations and a permanent leak.

Scoped autorelease pools now drain temporary Objective-C framework objects around synchronous image decoding, tensor preparation, Core ML prediction/validation, tensor pixel reading/blending, and PNG encoding. The returned tensor or copied Swift pixel bytes remain owned by their caller. No pool spans an `await`; asynchronous scheduling, frame order, model selection, compute units, and image calculations remain unchanged. An initial image/prediction-only experiment reduced the 120-frame peak to 1068.6 MiB but still showed growth; extending the same cleanup to tensor preparation and reading stabilized this sample.

## Release benchmark evidence

| Measurement | SD before cleanup | SD after cleanup | Tiled after cleanup |
| --- | ---: | ---: | ---: |
| Model setup | 13.422 s | 13.481 s | 15.429 s |
| Restoration of 120 frames | 12.426 s | 12.277 s | 22.411 s |
| Complete benchmark | 26.733 s | 26.550 s | 38.631 s |
| Live resident memory after 120 frames | 2229.4 MiB | 141.2 MiB | 160.5 MiB |
| Process peak resident memory | 2229.4 MiB | 159.1 MiB | 168.4 MiB |

After cleanup, SD live memory at 30/60/90/120 frames was 139.2/140.9/141.2/141.2 MiB; tiled was 158.5/160.2/160.4/160.5 MiB. These measurements cover this test process, not child FFmpeg processes or external Core ML services. Both 120-frame runs independently validated their silent hardware-HEVC output and cleaned their temporary workspace. Runtime was essentially unchanged; this is a memory improvement, not a measured inference speedup. A short benchmark does not establish an episode-length memory bound.

Evidence logs are retained in `.build/milestone104-evidence/`; reproduction uses the milestone 102 commands. App build, complete regression, and hands-on results are recorded below as they complete.

## Verification and user checkpoint

All 117 tests in 30 suites passed in the complete sequential Release regression run, including real Core ML reference comparisons, SD-only resource selection, restoration pipelines, cancellation, and output promotion. Both focused hardware benchmarks passed. The Debug Xcode app build and `git diff --check` passed.

The updated test app is `.build/Milestone101DerivedData/Build/Products/Debug/SwiftyTranscoder.app`. Repeat the same SD preview and confirm picture, sound, completion, and responsiveness before continuing to another change. Hands-on confirmation is pending; the installed 1.1.0 release remains unchanged. The bounded-concurrency experiments remain deferred, and the CLI remains planned as milestone 105.

The user subsequently confirmed the preview checkpoint passed, completing acceptance of this focused memory-lifetime change.
