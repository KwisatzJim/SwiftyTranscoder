# Milestone 77 — Verified Restoration Model Packaging

## Goal

Promote the hands-on-approved Real-ESRGAN 2× model from an external development dependency into a verified application resource without yet enabling full-file restoration.

## Provenance and license

The model is still produced from the checksum-pinned `RealESRGAN_x2plus.pth` weights published with Real-ESRGAN v0.2.1. Real-ESRGAN uses the BSD 3-Clause license. The exact upstream license from that tag is downloaded and verified with SHA-256 `4a699ec4863d96a91fc265948a0c90033f7e8735d515524dcf3444736406e0c2`.

The Core ML conversion continues to use `real-esrgan-coreml` commit `88b473f383bd69e0e52ea1f266e6585c4fab34bf`, whose pinned project metadata declares the MIT license. Converter source and Python dependencies are build inputs only and are not included in the application.

## Packaging boundary

`Scripts/prepare-restoration-model.sh` now verifies the three files in the generated Core ML package as well as the original weights, converter, and license. The application build phase refuses to continue if any file is missing or its checksum differs.

Verified builds copy the package to `Contents/Resources/Models` and the BSD notice to `Contents/Resources/ThirdPartyNotices`. The preview controller prefers this bundled resource; its ignored development copy remains only a source-tree fallback for Swift package tests and development tools.

The release verifier independently checks all three model-file hashes and the license hash inside the signed application. The release script prepares the model before building, so release packaging uses the same pinned inputs rather than relying on an undocumented local artifact.

## Safety boundary

This milestone changes model availability and packaging only. Restoration remains optional, preview-only, SDR-gated, limited to 2×/1080p, and unavailable to the normal conversion or batch output paths. Full-file output promotion still requires a separate plan-control and storage/cancellation milestone.

## Verification

- Model preparation passed macOS 14 Core ML compilation and three deterministic inference runs at a median 0.168 seconds per tile.
- All 73 tests across 20 suites passed.
- A signed arm64 Release app built successfully and passed the independent release verifier with the model and seven notices inside the bundle.
- The exact bundled model copy passed three additional deterministic inference runs at a median 0.170 seconds per tile.
- The Release application is approximately 55 MB with the 33 MB model included.

## Next gate

The next milestone can add an explicit, off-by-default restoration choice to an eligible conversion plan and calculate full-file temporary storage before allowing execution. It must preserve the normal non-restored option and must not start full-file work until the user approves the plan.
