# Milestone 102 — M6 restoration performance baseline

Measured October 3, 2026 on the local Apple M6 Mac mini with 24 GB RAM and 12 CPU cores. Hardware information was obtained locally. The existing opt-in benchmark ran in optimized Swift Release mode, sequentially, on 120 frames from 600 seconds into `Alphas - s01e11 - Original Sin.m4v`, at 624×352 input and 1248×704 output. Each run independently validated its silent hardware-HEVC output and cleaned its temporary workspace. No production processing behavior changed.

The benchmark now reports macOS `getrusage` process high-water resident memory at stage boundaries and every 30 frames. These are cumulative peak values, not current live memory, and exclude FFmpeg children and external Core ML services. The optional CPU/GPU benchmark selection now applies consistently to the SD model as well as the tiled model; all runs below used `.all`.

| Measurement | SD model first run | SD model repeat | Tiled model |
| --- | ---: | ---: | ---: |
| Extraction | 0.630 s | 0.452 s | 0.439 s |
| Model setup | 28.722 s | 28.626 s | 15.458 s |
| Restore 120 frames | 12.500 s | 12.302 s | 22.235 s |
| Encode and validate | 0.425 s | 0.349 s | 0.431 s |
| Total, excluding Swift build | 42.278 s | 41.730 s | 38.562 s |
| Restoration seconds/frame | 0.1042 | 0.1025 | 0.1853 |
| Test-process peak resident memory | 2232.3 MiB | 2232.3 MiB | 3148.7 MiB |

The SD path restored frames approximately 1.81× faster than the tiled path on this sample. Setup nevertheless made its short total run longer. Both models are eagerly constructed for the SD path, while tiled mode constructs only the tiled model. Each fresh process compiles the source packages before loading; setup timings do not separate compilation from loading. A repeated fresh-process run did not materially reduce this cost. These results do not establish a fully cold OS-cache measurement or predict all source dimensions.

For the repeated SD run, cumulative frame timings were decoding 0.398 s, tensor preparation 0.040 s, model processing and validation 8.326 s, blending 0 s, and output image creation/writing 3.533 s. Model work comprised approximately 68% of restoration time and output approximately 29%. Tiled model processing and validation took 17.810 s, approximately 80% of restoration time.

Peak memory increased at successive checkpoints. SD repeat values at 30/60/90/120 frames were 654.3/1180.2/1707.0/2232.2 MiB; tiled values were 929.8/1711.2/2446.5/3148.5 MiB. This warrants live-memory and object-lifetime investigation before concurrency experiments. It does not establish a leak or production episode-length growth: this benchmark loops directly over the frame processor and does not exercise multi-chunk cleanup or the application's complete lifecycle.

## Reproduction

Run one at a time with Xcode's developer directory selected:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTY_RESTORATION_BENCHMARK=1 SWIFTY_RESTORATION_SD=1 \
swift test -c release --filter profilesConsecutiveRestorationFrames

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SWIFTY_RESTORATION_BENCHMARK=1 \
swift test -c release --filter profilesConsecutiveRestorationFrames
```

All three focused benchmark runs passed, including output validation; `git diff --check` passed. Repeat SD and tiled logs are retained in `.build/milestone102-evidence/`. The first SD figures were captured from its completed tool output before the repeat reused the log path. The installed app and source media were unchanged.

## Next focused step

Milestone 103 should begin by loading only the model required for the source, with the existing model-contract checks and fallback eligibility preserved. Compare setup and output against this baseline. Investigate live memory and frame-object lifetimes before adding parallel inference; consider compiled-model packaging as a subsequent discrete change.
