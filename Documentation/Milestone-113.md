# Milestone 113 — Faster temporary frame images

The user confirmed milestone 112's integrated lightweight preview. Split the existing output timing into pixel packing and PNG writing before changing behavior. Eight real Pilot HD frames with FSRCNN measured 0.0802 seconds packing, 0.5699 seconds PNG writing, and 0.9919 seconds total frame processing. PNG writing was about 57% of frame-processing time.

A fixed Sub-filter/level-1 zlib trial did not improve throughput (0.5703 seconds writing, 0.9874 seconds total). The accepted implementation uses filter None and zlib level 0 (stored DEFLATE blocks). It keeps standard 8-bit RGBA PNGs and the previous sRGB/perceptual color declaration, retaining every pixel. This targets short-lived working files, whose smaller compressed size does not justify the CPU cost. Source extraction and final video encoding are unchanged.

The stored-PNG trial measured 0.0343 seconds PNG writing and 0.4870 seconds total for the same eight frames: about 16.6× faster writing and 2.04× faster frame processing. Video assembly/validation took 0.1440 seconds compared with 0.2370 seconds in the baseline. This is a short local measurement, not a full-episode runtime guarantee. AI prediction is now the largest measured processing stage again.

`RestorationPNGEncoder` writes PNG signature, IHDR, sRGB, IDAT, IEND with zlib checksums. Integer/dimension/byte-count validation and zlib compression bounds prevent invalid buffer sizes. The frame processor retains its existing non-overwriting write and sequential bounded workspace. System zlib is supplied by the macOS SDK; no added runtime download.

Uncompressed restored HD images are approximately 14.75 MB each (2560×1440). The 120-frame limit bounds this sequence to about 1.77 GB, plus extracted source frames. Storage preflight now estimates the actual 2× source frame dimensions before the later 1080p video cap, includes zlib/container overhead and source metadata allowance, and retains encoded-working-file allowance plus 1 GiB reserve. This corrects the previous use of capped output dimensions for intermediate HD images.

Validation includes independent AppKit decoding against original bytes and the prior AppKit encoder for narrow, uneven, random, and >64 KiB images; color-space equivalence; invalid/overflowing inputs; SD and capped-HD storage estimates; and complete production HD restoration. The PNG layout follows [W3C PNG specification](https://www.w3.org/TR/png-3/); zlib API contracts were checked against the installed SDK header.

Separate optimized app: `.build/Milestone113DerivedData/Build/Products/Release/SwiftyTranscoder.app`. No installed-app replacement or intervention in an active episode. Evidence resides in `.build/milestone111-evidence/fsrcnn-png-baseline.json`, `fsrcnn-fast-png.json`, and `fsrcnn-stored-png.json`; the full validation output is `.build/milestone113-review/Pilot-Lightweight-AI.mp4`.

Final validation: 32 tests in seven suites passed, including a complete 240-frame HD output (1920×1080, AC-3 plus AAC, owned-workspace cleanup), real SD chunks and a two-job batch, cancellation, output promotion, exact PNG pixels/color, and disk estimates. The ten-second Pilot run took 18.237 seconds after preparation, versus 34.322 seconds in milestone 112 (about 1.88× faster). Tests shared the machine; full-episode results are recorded below. Optimized Xcode build, strict deep signature verification, and whitespace checks passed. Eight final-profile stored PNGs occupied 117,985,968 bytes.

The user confirmed on October 4, 2026 that the short Lightweight AI preview in the milestone 113 app looks and sounds good. The short-preview checkpoint is accepted. The subsequent full Pilot run completed, and the user confirmed good playback. The full-episode performance and playback checkpoint is accepted.


## Full-episode user observation — October 4, 2026

The user reports the Lightweight AI Pilot run started at 7:21 am and completed at 9:08 am (America/Chicago), for 107 minutes elapsed. At 8:02 am (41 minutes elapsed), progress was 35% and app memory was 288.9 MB. After completion, app memory was 159.1 MB. These are observed samples, not a measured peak or proof of constant memory throughout the run. The previous compact-model Pilot run projected approximately 9.2 hours total from its early progress; this completed run is about 5.2× faster than that projection, not a comparison against a completed compact-model run.

Full-episode completion and practical elapsed time are confirmed by the user. After being asked to check picture, sound, and audio synchronization near the beginning, middle, and end, the user confirmed playback is good. Milestone 113 is accepted for this full-episode test. Results establish performance and quality for this tested source and machine; the two-file batch acceptance is recorded below, and release packaging remains a separate checkpoint.


## Two-file Lightweight AI batch — October 4, 2026

The user tested `Alphas - s01e11 - Original Sin.m4v` and a copy of the same source. The batch started at 12:03 pm and both files completed at 12:53 pm (America/Chicago), for 50 minutes total. The first video showed an estimated 27 minutes remaining; the user specifically liked this display. At 12:05 pm, observed app memory was 108.1 MB. This single observation does not establish peak memory or memory release between files, and individual file completion times were not reported.

The user confirmed good playback on both outputs. Two-file batch completion and playback are accepted. Together with the accepted full Pilot run, this completes the planned performance and playback acceptance checks for milestone 113. The 108.1 MB observation is a sample, not a measured memory peak. Release packaging remains the next separate checkpoint.
