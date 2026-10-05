# Milestone 114 — Local 1.3.0 release

The user authorized release packaging after accepting the full Lightweight AI Pilot output (107 minutes) and both outputs from a two-file Original Sin batch (50 minutes). Version metadata is 1.3.0, build 13.

The release includes reviewed sequential restoration batches, numeric batch/current-video progress, a measured current-video remaining-time estimate, detailed/compact/lightweight model choices, correct assembly of capped-HD frames, and faster lossless temporary PNG writing with storage preflight based on full intermediate dimensions. Ordinary conversion and the existing CLI remain available; AI restoration remains a GUI feature. The default detailed model is preserved.

All four prepared model packages are now mandatory app resources. Embedding and release verification check their pinned manifests, model definitions, and weights. The FSRCNN Apache license and source attribution are bundled, raising the expected notice count from seven to nine. No optional build flag is needed to obtain the accepted model choices in a release.

Packaging uses the existing local ad-hoc signing policy and preserves older installers. It includes the app, Applications shortcut, lowercase CLI launcher, and CLI usage instructions. Packaging does not install the app, modify `/usr/local/bin`, or upload a public release.

Completed artifact: `dist/SwiftyTranscoder_1.3.0_arm64.dmg` (approximately 73 MB).

SHA-256: `ab424c103f95cde571a17b40062b52f85ce832bb83c8c380d4b37b74d2214ac3`.

All 151 regression tests in 37 suites passed. The release pipeline rebuilt and verified the self-contained media toolchain, validated pinned detailed/SD resources, built 1.3.0 (13), checked all four models and nine notices, verified strict signing, helper linkage and capabilities, and checked the DMG internally and through a read-only mount. The packaged app and lowercase launcher passed CLI help checks.

A second read-only mount passed actual MP4 gain and MKV hardware-HEVC conversion, dry-run behavior, final output validation, unchanged MP4 video elementary-stream hash, existing-output refusal, source/output collision refusal, and active SIGINT cancellation with a labeled partial retained. The production restoration test located resources only inside the mounted app (no development or helper fallback) and selected FSRCNN explicitly. It restored a ten-second Pilot clip in 18.049 seconds after preparation; output validation confirmed 1920×1080, all 240 frames, AC-3 plus AAC, and workspace cleanup. The mount was ejected afterward.

Independent `shasum -a 256 -c SHA256SUMS.txt` passed for retained 1.0, 1.1, 1.2, and new 1.3 installers. Shell syntax and whitespace checks passed. Evidence logs and the mounted-media harness are retained under `.build/milestone114-evidence/`, including the validated clip under `review/`. Installed-release acceptance is recorded below.

## Installed-release acceptance

The user confirmed both final checkpoints: About shows 1.3.0 and a short Lightweight AI preview from the installed app works. Together with the accepted full Pilot episode, two-file batch playback, and packaged app/CLI verification, this completes the scoped local 1.3.0 release milestone.
