# Milestone 34 — Duplicate Batch Destination Protection

## Goal

Detect when multiple approved sources would write to the same final output path before the batch starts.

## Step 1 — Canonical destination comparison

At the batch-ready checkpoint, SwiftyTranscoder compares every approved output after standardizing its path, resolving destination-folder symbolic links, normalizing Unicode, and applying a conservative case-insensitive comparison. The checkpoint confirms when every output is unique or identifies each duplicate destination path.

**Start Approved Batch** is disabled while a duplicate remains. The same check runs again on start; the user must reopen one affected plan and choose a different destination folder. No source, partial output, or existing final file is modified by this check.

The Debug build succeeded. Runtime testing used two fully tagged one-second MP4 sources with the same filename in different folders. After both plans were approved, the user confirmed that the batch-ready checkpoint displayed the duplicate destination, disabled **Start Approved Batch**, and did not begin conversion. Milestone 34 is complete.
