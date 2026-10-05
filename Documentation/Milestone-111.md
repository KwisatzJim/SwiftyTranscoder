# Milestone 111 — Profile HD restoration and evaluate lightweight AI

The user authorized stage profiling and one targeted throughput improvement after the compact-model Pilot run reached 13% in approximately 72 minutes. The running full episode is untouched. Work remains sequential, with a picture/sound checkpoint before adopting another model.

## Measured bottleneck

Eight consecutive 1280×720 Pilot frames were processed by the same optimized Swift frame path and hardware encoder. All measurements are short samples on the user's Mac, potentially alongside the ongoing episode; they are not full-episode runtime guarantees.

| Stage, eight frames | Compact Real-ESRGAN | Lightweight FSRCNN |
| --- | ---: | ---: |
| Decode source images | 0.067 s | 0.075 s |
| Prepare model tensors | 0.017 s | 0.017 s |
| Model prediction | 1.296 s | 0.113 s |
| Validate returned tensors | 0.046 s | 0.048 s |
| Blend tiles | 0.085 s | 0.083 s |
| Pack/write restored images | 0.695 s | 0.649 s |
| Total frame processing | 2.212 s | 0.992 s |
| Hardware encoding and validation | 0.244 s | 0.238 s |
| Model preparation | 80.97 s | 9.71 s |

Actual model prediction accounted for about 59% of the compact path's frame processing. Returned-tensor checking was about 2%; blending was about 4%, so removing safety checks or optimizing blending first would give little benefit. The lightweight model cut actual prediction time about 11.5×, while total frame processing improved about 2.23×. Packing/writing images now accounts for about 65% of that faster path. Further throughput work should split pixel packing from PNG encoding/writing and target the largest measured cost.

## Research-only lightweight candidate

The candidate is the Apache-2.0-licensed FSRCNN x2 frozen graph from Saafke's OpenCV contributor repository, trained on ordinary images. It is a lightweight learned luminance upscaler, not an equivalent denoiser or reconstruction model to Real-ESRGAN. RGB is converted to the training model's full-range luminance representation within the Core ML wrapper; chroma differences are scaled bilinearly and combined back into RGB. Existing application SDR tagging and output dimension limits remain enforced.

Primary sources:
- https://github.com/Saafke/FSRCNN_Tensorflow
- https://github.com/Saafke/FSRCNN_Tensorflow/blob/master/fsrcnn.py
- https://github.com/Saafke/FSRCNN_Tensorflow/blob/master/data_utils.py

`Scripts/prepare-fsrcnn-candidate.py` decodes constants from the checksum-pinned frozen graph without executing downloaded Python, reconstructs the documented network, and converts it to the existing `[1,3,522,522] → [1,3,1044,1044]` Float16 contract. Frozen graph SHA256: `366b33f0084c7b3f2bf6724f0a2c77bca94fcec9d7b6d72389d330073b380d5c`. License SHA256: `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`.

The research environment adds `opencv-contrib-python-headless==4.12.0.88` for independent original-graph verification; this is not an application runtime dependency. Original OpenCV/TensorFlow-graph output and reconstructed PyTorch luminance matched with mean absolute difference approximately `4.14e-7` and maximum `6.23e-6` on a seeded test. Converted Core ML RGB and the PyTorch wrapper matched with mean difference approximately `0.000302` and maximum `0.00295`; shape and finite-output checks passed.

Core ML prediction and tensor-check timings are now separately observable for diagnosis. Production behavior and model choices are unchanged by this profiling work. FSRCNN is injected explicitly only in the research tests and is not embedded or exposed in the app yet.

## Complete short output and checkpoint

The existing complete production pipeline restored the 240-frame, ten-second Pilot excerpt with the candidate in 33.972 seconds after model preparation. The pipeline completed output validation and promotion, and the independent final probe confirmed 1920×1080, all 240 frames, AC-3 plus AAC audio, and owned-workspace cleanup. The initial independent probe omitted `-show_chapters`, causing a test JSON decode failure after a successful render; the probe was corrected, the first artifact preserved, and the complete render/test passed on rerun.

The review output is `.build/milestone111-review/Pilot-Lightweight-AI.mp4`, and the input reference is `.build/milestone110-review/inputs/Pilot-HD-10s.mp4`. Evidence is retained in `.build/milestone111-evidence/`.

The user confirmed that the candidate picture and sound are acceptable and authorized app integration. The measured ten-second throughput still implies several hours for an hour-long episode, so the runtime objective remains open; image packing/writing is the next measured bottleneck.
