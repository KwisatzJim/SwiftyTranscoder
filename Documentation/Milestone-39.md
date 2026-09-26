# Milestone 39 — Accessible Batch Queue Controls

## Goal

Make queue review, status, and removal understandable when using VoiceOver instead of relying on visual icons.

## Implementation

Each queue row exposes a combined filename-and-status label. At the ready checkpoint, the review action announces the filename and explains that it opens the approved plan. The icon-only remove control now announces the filename and explains that it asks for confirmation without deleting the source. Decorative status icons are hidden from VoiceOver to avoid redundant announcements.

The full Debug app build succeeds, and all five queue-state regression tests still pass. Source inspection confirms that every icon-only removal control and ready-state review action has a filename-specific accessibility label and explanatory hint, while decorative queue icons are excluded from the accessibility tree. Milestone 39 is complete.
