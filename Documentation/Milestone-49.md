# Milestone 49 — Focused Multi-Step Wizard

## Goal

Keep the growing conversion workflow comfortable without requiring one tall, densely packed screen.

## Four focused steps

The main window now separates the workflow into **Choose**, **Review**, **Plan**, and **Convert** pages. A persistent step indicator shows the current position, and short transitions make page changes clear without slowing the workflow. Review keeps the human-readable summary prominent and places technical stream details behind a disclosure control.

Multi-file review continues through the same pages for every source. Approved queue rows can be revisited before conversion, and the batch-ready summary remains a distinct checkpoint so approving the final plan never starts encoding unexpectedly.

## Queue and navigation polish

Large queues use their own compact scrolling area, automatically keep the current video visible, and allow returning to any approved item. The main page returns to its top when the wizard advances. Revisiting **Choose** offers a safe return to the loaded video or batch instead of forcing replacement, while source replacement is hidden at the fully approved checkpoint. Completed queues cannot reopen the editable approval workflow.

The window now has an 820 × 620 point minimum size, primary actions respond to the Return key, selection context reports the current video's position, and notification controls appear only on the conversion page where they are relevant.

## Verification

The Debug application builds successfully, and all 24 automated tests across 9 suites pass. A launched Debug build confirmed the initial wizard layout and Return-key source selection behavior. The user separately confirmed the multi-page flow, navigation back to the first video, compact queue, current-item visibility, selection context, and preserved-batch return behavior during the incremental milestone reviews.

Milestone 49 is complete and ready for final visual review.
