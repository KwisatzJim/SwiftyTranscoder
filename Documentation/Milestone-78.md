# Milestone 78 — Full-Video Restoration Planning

## Goal

Add an explicit, off-by-default restoration choice and a conservative full-file storage estimate without allowing the preview pipeline to create or promote a production output yet.

## Plan interface

Eligible SDR sources now show a **Full-video AI restoration** card on the Plan step. The switch is off whenever a source is loaded. Turning it on changes the proposed video method and dimensions to the exact `Real-ESRGAN x2plus` restoration plan while leaving frame rate, audio, gain, subtitle, color, and destination choices visible.

The ordinary non-restored conversion remains available by turning the switch off. The app does not remember restoration as a default and does not carry it to another queue item.

Because full-file execution is deliberately not connected in this milestone, enabling restoration disables plan approval or conversion with a plain-language explanation. This prevents the existing conversion button from accidentally running the ordinary path while the interface displays a restored plan.

## Conservative temporary-storage estimate

The currently proven pipeline retains a complete extracted PNG sequence and a complete restored PNG sequence until video assembly finishes. The planner therefore estimates the frame count from the exact rational source cadence and program duration, then budgets four bytes for every source and output pixel in every frame. It adds two source-file sizes for encoded working media and a 1 GiB reserve.

This intentionally conservative figure is separate from the existing final-output destination requirement. The card compares it with currently available capacity on macOS's temporary volume and clearly warns when that volume is insufficient. Invalid metadata or arithmetic overflow produces no guess and keeps restoration blocked.

For the automated 45-minute 624×352 test case at `24000/1001`, the planner counts 64,736 frames and requires 289,456,400,384 bytes for the 1248×704 restoration workspace.

## Verification

- New tests cover exact frame counting, conservative byte calculation, invalid inputs, and overflow refusal.
- All 75 tests across 21 suites pass, including the two focused storage tests.
- The full macOS application builds successfully with the new plan card and bundled model.
- The normal conversion command and preview pipeline are unchanged.

## Next gate

The next milestone should replace full-sequence retention with a bounded streaming/chunk workspace so an episode does not require hundreds of gigabytes. Only after chunk cleanup, cancellation, final assembly, subtitles, chapters, metadata, and storage enforcement are tested should the full-video switch be allowed to start production restoration.
