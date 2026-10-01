# Milestone 94 — SD frame model experiment

This research experiment reuses the pinned Real-ESRGAN x2plus weights and converter architecture to prepare a fixed rectangular input suited to Alphas' 624×352 frames. A 16-pixel reflected border gives the model context at the image boundaries. The model input is 656×384; inference produces 1312×768, then the border is cropped to the approved 1248×704 picture. The production application and its bundled model are unchanged.

`Scripts/evaluate-sd-restoration-shape.py` verifies the original converter and PyTorch weights against their existing SHA-256 pins. Conversion uses the installed research environment, Float16, and macOS 14 deployment support. The experimental package and its file checksums are retained under the ignored `.build/restoration-evaluation/sd-shape-experiment` directory.

## Comparison evidence

Both models use Core ML's `.all` hardware setting. Each shape is warmed before timing. Three source intervals contain 24 consecutive frames each: face at 540 seconds, motion at 1350 seconds, and dark imagery at 1890 seconds. Every candidate output is checked for expected shape and finite values. This is Python research-harness timing, not yet a benchmark of a native Swift integration or a full episode.

| Scene | Current tiled processing | Single frame processing | Speedup | Mean RGB difference | Edge RGB difference |
| --- | ---: | ---: | ---: | ---: | ---: |
| Face | 8.683 s | 3.852 s | 2.25× | 1.295 | 1.486 |
| Motion | 8.803 s | 3.906 s | 2.25× | 1.007 | 0.902 |
| Dark | 8.702 s | 3.857 s | 2.26× | 1.095 | 1.169 |

RGB differences are average absolute channel differences on a 0–255 scale, relative to the current model rather than a ground-truth restored image. The edge measurement uses the outer 32 output pixels. Temporal delta differences are retained in `report.json` for further analysis; they are not a proof that flicker is absent.

The three first-frame comparisons were visually inspected. They have matching dimensions and orientation, and no obvious new edge artifact was apparent at the inspected display size. The outputs are similar but not pixel-identical. Hands-on playback review is required before changing the application's image-processing path.

The review video places the current model on the left and the candidate on the right. It repeats the three approximately one-second samples four times for a 12-second review. It is silent. Independent FFprobe inspection confirms HEVC, 2496×740 including labels, 288 frames, and 12.012 seconds. This is a comparison artifact, not an episode conversion.

## Reproduction and next checkpoint

```sh
.build/restoration-evaluation/venv/bin/python Scripts/evaluate-sd-restoration-shape.py prepare
.build/restoration-evaluation/venv/bin/python Scripts/evaluate-sd-restoration-shape.py evaluate
```

The converter requires existing verified research inputs; it downloads nothing. Model conversion and clip generation refuse to replace existing outputs. The `reel` mode can assemble already generated scene comparisons when a review reel does not yet exist. Temporary local model copies are removed after evaluation, while evidence and model files remain in the ignored research directory.

After the user reviews motion, faces, and edges in `sd-shape-experiment/review.mp4`, the next milestone can implement and validate a narrowly scoped native Swift path for this frame shape with a fallback to the current tiled model for other sizes.
