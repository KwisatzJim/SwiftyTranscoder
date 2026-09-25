# Milestone 33 — Whole-Batch Destination Space Preflight

## Goal

Prevent a reviewed batch from starting when its combined conservative storage requirement exceeds the space available on any destination volume.

## Step 1 — Aggregate approved-plan requirements

The batch-ready checkpoint now groups approved outputs by destination volume and adds their existing per-file conservative requirements. For each volume, it shows available space alongside the total required for every approved output assigned there.

**Start Approved Batch** is disabled if space cannot be checked or any volume is short. The same aggregate check runs again when the user starts the batch so a stale visible result cannot bypass the safety block. Existing per-video checks still run immediately before each FFmpeg process begins.

The Debug build succeeded. At a real two-video ready checkpoint, the user confirmed that SwiftyTranscoder displayed the destination volume's available capacity and combined conservative batch requirement, and that **Start Approved Batch** remained enabled when the available amount exceeded the total requirement. Milestone 33 is complete.
