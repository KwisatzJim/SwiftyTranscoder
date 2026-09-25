# Milestone 31 — Revisit Any Approved Plan

## Goal

Allow corrections to any video at the all-plans-approved checkpoint without rebuilding the queue or losing the other approvals.

## Step 1 — Select, reopen, and reapprove

At the **Batch ready to start** checkpoint, every queue row is selectable. Selecting a row restores that video's exact approved inspection, destination, gain, AAC compatibility, color, and subtitle choices without probing the file again.

**Reopen Selected Plan** removes only the selected approval and unlocks its plan controls. After the corrected plan is approved, SwiftyTranscoder retains every other approval and returns to the ready checkpoint as soon as all queue items are approved again. Initial sequential review behavior is unchanged.

The Debug build succeeded. At a real two-video ready checkpoint, the user selected the first queue row, confirmed its approved source and settings were restored, reopened and changed that plan, and reapproved it. SwiftyTranscoder returned to the ready checkpoint without requiring the unchanged second plan to be reviewed again. Milestone 31 is complete.
