# Milestone 92 — Restoration performance baseline

The user confirmed completed episode restoration, good picture and audio, and Direct Play on both reviewed Plex players.

The native frame processor now records decoding, input tensor preparation, model processing, tile blending, and output image creation times. The existing representative four-frame integration check prints these measurements without setting hardware-dependent performance pass/fail thresholds.

Isolated runs used the same four 624×352 source frames and pinned Core ML model, with no concurrent restoration tests:

| Measurement | Debug | Release |
| --- | ---: | ---: |
| Model setup | 2.814 s | 2.788 s |
| Four-frame processing | 8.909 s | 1.516 s |
| Last-frame decoding | 0.008 s | 0.008 s |
| Last-frame input preparation | 0.209 s | 0.001 s |
| Last-frame model processing and validation | 0.778 s | 0.331 s |
| Last-frame blending | 0.802 s | 0.003 s |
| Last-frame output creation | 0.433 s | 0.030 s |

The optimized Release build processed this sample approximately 5.9 times faster. This is a short sample, not an episode runtime prediction. Setup, extraction, encoding, audio, storage, thermal conditions, and content can affect full-job results. Timing instrumentation excludes buffer allocation and some small bookkeeping operations, so individual categories are not a complete sum of frame processing time.

The first speed improvement is to use the existing optimized Release configuration for restoration. No model or image algorithm changes are needed. A locally ad-hoc-signed app is built at `.build/Milestone92ReleaseDerivedData/Build/Products/Release/SwiftyTranscoder.app` for a focused preview and playback review.

Reproduction commands:

```sh
swift test --filter restoresRepresentativeSequenceWhenResearchModelIsAvailable
swift test -c release --filter restoresRepresentativeSequenceWhenResearchModelIsAvailable
```

Run these sequentially so they do not compete for the same hardware. Research frames and the model must be present; the integration test skips when those resources are absent.

All 110 tests passed in Release. The optimized application build passed the release app verifier, including its signature, bundled media helpers, concat capability, model checksums, and notices.
