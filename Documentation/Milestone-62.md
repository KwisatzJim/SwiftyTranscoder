# Milestone 62 — Restoration Model Evaluation Harness

## Goal

Create a repeatable, offline-after-preparation gate for a possible AI-upscaling model without adding restoration to the application or changing the version 1.0 conversion path.

## Provisional candidate

[Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) `RealESRGAN_x2plus` is the first candidate. Its upstream project uses the BSD 3-Clause license and publishes the original PyTorch weights. It enlarges each dimension by 2×, which matches the conservative limit set in Milestone 61.

This is only a **provisional still-frame candidate**. It has not passed representative-image quality, color, memory, or video temporal-consistency testing and is not yet approved for product use.

The evaluation uses the conversion implementation from [real-esrgan-coreml](https://github.com/hanxiao/real-esrgan-coreml) at commit `88b473f383bd69e0e52ea1f266e6585c4fab34bf`. That converter is MIT-licensed. The downloaded converter and model weights are independently checksum-verified before use:

| Input | SHA-256 |
| --- | --- |
| `RealESRGAN_x2plus.pth` | `49fafd45f8fd7aa8d31ab2a22d14d91b536c34494a5cfe31eb5d89c2fa266abb` |
| pinned `convert.py` | `152404e3021958c6e51edcde9fd17f2757ccf15f0e0d4e5c485495fd852b4af4` |

## Reproducible gate

Run:

```fish
Scripts/prepare-restoration-model.sh
```

The script:

1. downloads and verifies the two pinned inputs;
2. creates an ignored Python 3.12 environment with pinned `coremltools`, NumPy, and the PyTorch version officially tested by that `coremltools` release;
3. changes only the converter's declared deployment target from macOS 15 to the application's macOS 14 target;
4. produces a fixed-shape FP16 Core ML package for `1 × 3 × 522 × 522` input and `1 × 3 × 1044 × 1044` output;
5. asks Apple's `coremlcompiler` to compile it explicitly for macOS 14; and
6. runs repeated local inference, checking dimensions, finite numeric output, and exact repeatability.

All downloaded dependencies, the Python environment, and the generated model remain under ignored `.build/restoration-evaluation`. Nothing is embedded in SwiftyTranscoder.

## Initial evidence

On the Apple Silicon development Mac with macOS 27.0 and Xcode 27.0:

- the locally converted model compiled with a macOS 14 deployment target;
- Core ML accepted the expected input and produced the expected 2× output;
- repeated zero-frame inference was deterministic; and
- three measured warm-cache runs took approximately 0.166–0.171 seconds per 522-pixel tile.

A preconverted package from the converter project's release was deliberately rejected because it declared macOS 15. SwiftyTranscoder does not need to raise its macOS 14 requirement: converting the pinned upstream weights locally produces a package that passes the macOS 14 compiler gate.

Apple's Core ML compiler must read and write this package on the local startup disk. When the source package was on the external project volume, the compiler produced a misleading permission error while creating intermediate model files. The harness works around that tool limitation by copying the research package to a private temporary directory for compilation and inference only.

## Result and next gate

The candidate passes the license, provenance, checksum, conversion, fixed-dimension, macOS 14 compilation, and basic deterministic-inference gates. It remains excluded from the app.

The next milestone will extract a small, read-only set of representative SDR frames and build side-by-side comparisons against ordinary Lanczos scaling. Only measured visual quality can determine whether this candidate is worth continuing into short video clips.
