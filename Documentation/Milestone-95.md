# Milestone 95 — Approved SD model integration

The user approved the Milestone 94 side-by-side comparison. Preview and full-video restoration now share a model-selection boundary: exactly 624×352 source frames use the rectangular single-frame model, while other dimensions retain the established tiled model. If the optional rectangular model is absent in a development environment, the tiled path remains available. An invalid selected model fails its contract check rather than silently changing processing.

The new path preserves the research geometry: 16 pixels of reflected input context, a 656×384 Float16 input, a 1312×768 output, and a 32-pixel output-border crop to 1248×704. Tensor access respects memory strides; shape, element type, finite pixel values, exact source dimensions, and cancellation are checked. Ordinary conversion, audio, subtitle handling, chunk boundaries, and final-output validation are unchanged.

Both packages are bundled and checksum-verified during build and release verification. The preparation script can create the additional model from the existing pinned research inputs without downloading anything. Package manifest identifiers are canonicalized because conversion otherwise generates random identifiers. The original model and license remain included.

## Verification

- All 113 Release tests passed, including a real short production restoration using the SD model.
- The native first-frame output has the expected dimensions and orientation and was visually inspected.
- Its normalized mean RGB difference from the approved Python research frame is 3.253 on the 0–255 scale. Native AppKit and Python image decoding are not pixel-identical; the regression bound is 5, not a claim of perceptual equivalence. Comparing raw bitmap storage initially produced an invalid large difference; comparison now normalizes both images to the same RGBA layout.
- The Release Xcode application built successfully, including the preview service outside the core test package. The release verifier passed both model checksum gates, app/helper signatures, and required media capabilities. Shell syntax checks passed for the changed packaging scripts.

## Native performance evidence

The same 120 consecutive Alphas frames at 600 seconds were measured in Release with Core ML `.all`:

| Stage | New SD path |
| --- | ---: |
| Extraction | 0.604 s |
| Model setup | 5.412 s |
| Restoration | 22.425 s |
| Encoding and validation | 0.536 s |
| Total | 28.977 s |

Restoration is 0.1869 seconds/frame, compared with Milestone 93's 44.518 seconds for the same 120-frame tiled benchmark: approximately 1.99× faster. Model inference and validation account for 17.900 seconds; output construction and PNG writing account for 3.933 seconds. This is a bounded benchmark, not a measured full-episode runtime or a guaranteed completion estimate.

```sh
env SWIFTY_RESTORATION_BENCHMARK=1 SWIFTY_RESTORATION_SD=1 swift test -c release --filter profilesConsecutiveRestorationFrames
```

## Hands-on checkpoint

Quit the previous application and open `.build/Milestone95ReleaseDerivedData/Build/Products/Release/SwiftyTranscoder.app`. Generate and play a 10-second Alphas restoration preview, checking picture, motion, and synchronized audio before undertaking another full episode. The existing completed episode is not modified by this milestone.
