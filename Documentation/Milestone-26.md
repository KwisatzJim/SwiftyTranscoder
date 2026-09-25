# Milestone 26 — Batch-Wide Progress

## Goal

Make an unattended batch's position and total progress clear without weakening the existing per-video progress and ETA reporting.

## Step 1 — Current item and overall completion

During a multi-file batch, the running status now identifies the active item as **Encoding video N of M**. The existing percentage, progress bar, and smoothed ETA continue to describe that individual video.

A second, clearly labeled **Overall batch** progress bar combines the number of validated completed items with the active video's progress. Single-file conversions retain their existing uncluttered presentation.

The Debug build succeeded. The user confirmed that a real two-video batch displayed the correct **video 1 of 2** and **video 2 of 2** positions, retained the current video's percentage and ETA, and advanced the overall batch bar across both conversions. Milestone 26 is complete.
