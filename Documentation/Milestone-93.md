# Milestone 93 — Consecutive-frame restoration profiling

The user's optimized episode run completed successfully and played well. Its approximately 04:45 start and 11:34 modification time imply about 6 hours 49 minutes. Inspection confirmed that the running application was the Milestone 92 Release executable, built with Swift `-O` optimization.

The earlier four-frame result was 1.516 seconds, or 0.379 seconds per frame. Multiplying that rate by the source's 64,797 frames predicts approximately 6 hours 49 minutes of restoration. The short benchmark therefore agrees with this completed run; describing the full run as evidence of failed optimization was incorrect. Earlier progress observations do not establish a reliable comparable full-run baseline.

## Longer benchmark

The opt-in `RestorationPerformanceTests` benchmark extracts 120 consecutive frames from 600 seconds into the Alphas episode, restores every frame with the production model, then performs real hardware HEVC encoding and independent validation. It uses staged helpers directly. Its temporary workspace is removed after the benchmark.

An isolated optimized run with the production `.all` Core ML setting measured:

| Stage | Seconds |
| --- | ---: |
| Frame extraction | 0.623 |
| Model setup | 2.735 |
| Restoration of 120 frames | 44.518 |
| HEVC encoding and validation | 0.534 |
| Entire benchmark | 48.410 |

Restoration averaged 0.3710 seconds per frame. Model processing and validation accounted for 39.816 seconds, about 89 percent of restoration time. Decoding, input preparation, blending, and PNG output together accounted for 4.672 seconds. The measured chunk stages, excluding one-time model setup, project to approximately 6 hours 51 minutes for 64,797 frames, before final joining and audio processing. This is an estimate, not a timing guarantee.

## Hardware comparison and next experiment

The same 120-frame sample with `.cpuAndGPU` took 173.430 seconds for restoration (1.4453 seconds per frame), versus 44.518 seconds with `.all`. Model processing and validation accounted for 167.025 seconds. Restricting the hardware was approximately 3.9 times slower, so production continues to use `.all`. These timings establish which configuration was faster; they do not identify the exact devices Core ML assigned to individual model operations.

Both opt-in benchmarks passed, including output encoding and validation. No production model, output algorithm, or hardware configuration changed in this milestone.

For this 624×352 source, the fixed 522×522 model processes two tiles, or 544,968 input pixels per frame, to cover 219,648 source pixels. Padding and overlapping tiles therefore increase model input work by about 2.48 times relative to source area. A useful next experiment is evaluating a model shape that fits this SD frame more efficiently, with the same learned weights. Any adoption requires measured runtime and picture/edge comparison; area ratios alone do not establish a speedup or image equivalence.

## Reproduction

```sh
env SWIFTY_RESTORATION_BENCHMARK=1 swift test -c release --filter profilesConsecutiveRestorationFrames
env SWIFTY_RESTORATION_BENCHMARK=1 SWIFTY_RESTORATION_COMPUTE=gpu swift test -c release --filter profilesConsecutiveRestorationFrames
```

The second command tests Core ML's CPU/GPU setting in isolation. It does not alter the production application's `.all` setting. Run these sequentially. Without the opt-in environment variable, the long benchmark does no work during ordinary regression testing.
