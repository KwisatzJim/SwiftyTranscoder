# Milestone 86 — Production restoration construction

Milestone 86 adds one production factory that constructs the complete full-video restoration pipeline from the application resources already approved and packaged in earlier milestones.

## One validated resource set

Before a pipeline is created, the factory locates and validates:

- executable FFmpeg and FFprobe helpers, preferring the copies inside the application;
- the `RealESRGAN_x2plus_522_fp16.mlpackage` directory inside the application; and
- the ignored development model only as a source-tree fallback for local development and tests.

Missing FFmpeg, FFprobe, and model resources produce separate plain-language errors. No restoration workspace or destination output is created during resource discovery or pipeline construction.

The bounded preview now uses this same resource locator, removing its duplicate model-location rule.

## Concrete production graph

For one approved full-video request, the factory constructs:

1. the Core ML tile and complete-frame processors;
2. the sequential restored-frame processor;
3. bundled-FFmpeg frame extraction and subtitle-aware hardware-HEVC segment assembly;
4. bounded chunk coordination;
5. copy-only segment concatenation;
6. compatible audio, chapter, and metadata muxing; and
7. capacity-checked destination staging and atomic promotion.

The request now carries its optional approved subtitle stream ordinal. A negative value is refused; `nil` remains the explicit omit-subtitles choice. That source-specific value is passed to every production chunk and is never inferred or reused from another source.

## Verification

Focused tests verify bundled-resource precedence and independent failure for each missing resource. A representative construction test loads the real Core ML model and builds the complete concrete production graph with the real media helpers and a subtitle-aware request. Construction does not start conversion.

## Current boundary

Full-video restoration remains disabled in the interface. The next milestone can add an application controller that creates a validated request from the currently approved plan, starts this factory-built pipeline, publishes stage and progress updates, forwards cancellation, and reports final or partial output. The start control should remain unavailable until that controller has isolated automated coverage.
