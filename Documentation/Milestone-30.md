# Milestone 30 — Explicit Batch Start Checkpoint

## Goal

Keep approval of the final source separate from the action that starts an unattended batch.

## Step 1 — All-plans-approved checkpoint

The last review action is now **Approve Final Plan**. It marks the final item approved but does not launch FFmpeg. SwiftyTranscoder then displays a green **Batch ready to start** summary stating that every plan is approved and no encoding has begun.

A separate **Start Approved Batch** button begins the existing sequential conversion workflow. The final plan remains visible but locked at this checkpoint so its displayed settings cannot drift from the stored approval. **Reopen Final Plan** removes only that approval and restores its controls when a correction is needed.

The Debug build succeeded. With a real two-video queue, the user confirmed that **Approve Final Plan** did not begin conversion, the green ready summary and separate start button appeared, and **Start Approved Batch** launched the batch normally. The final plan could also be reopened for editing before launch. Milestone 30 is complete.
