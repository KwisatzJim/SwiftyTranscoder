# Milestone 23 — Review-First Unattended Batch Conversion

## Goal

Review and approve every queued source before encoding begins, then convert the approved plans sequentially without requiring interaction between files.

## Step 1 — Review-first queue and automatic advancement

For a multi-file selection, the conversion button now approves the current plan and advances to the next source without beginning an encode. Queue rows distinguish **Reviewing**, **Waiting**, and **Approved** states. Approving the final plan starts the batch from its first item.

Each approved plan retains its own inspection, destination, gain choice, AAC compatibility choice, color decision, and subtitle choice. After each output passes the existing post-conversion validation and is promoted from its partial filename, the next approved plan starts automatically. A cancellation, failure, missing plan, or newly conflicting destination stops the batch instead of skipping ahead. Plan controls and source replacement are disabled while the batch is running.

The Debug build succeeds. The user then confirmed the complete workflow with a multi-file queue: all plans could be reviewed first, approving the final plan started the batch, and the approved conversions ran sequentially without requiring another review between files. Milestone 23 is complete.
