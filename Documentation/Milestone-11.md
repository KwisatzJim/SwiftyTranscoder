# Milestone 11 — Destination Space Preflight

## Goal

Prevent a conversion from starting when the selected destination cannot safely hold the incomplete output.

## Policy

SwiftyTranscoder reads the source size reported by `ffprobe` and requires free destination capacity equal to the source size plus a safety reserve. The reserve is the larger of 50 percent of the source size or 1 GB. This deliberately allows room for hardware constant-quality output to vary with source complexity.

The conversion plan shows both available and required storage after an output folder is selected. If capacity cannot be read, or available capacity is below the requirement, the plan shows a warning and the Convert button remains disabled. The command repeats the same check immediately before launch so a stale UI value cannot bypass the preflight. No space is reserved and no files are removed.

The Debug build succeeds. The user confirmed that the real conversion plan displays both available destination capacity and the required minimum after an output folder is selected. Milestone 11 is complete.
