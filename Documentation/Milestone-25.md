# Milestone 25 — Keep the Mac Awake During Conversion

## Goal

Prevent idle system sleep from interrupting a long conversion or unattended batch while still allowing normal sleep whenever SwiftyTranscoder is idle.

## Step 1 — Conversion-scoped system activity

The conversion controller now begins a macOS system activity immediately before launching FFmpeg. The activity identifies the work as user-initiated and disables idle system sleep only while that conversion is active.

The activity ends after successful output validation, cancellation, failure, or failure to launch FFmpeg. Each item in an unattended batch owns only its individual conversion activity, so the protection follows the same safe lifecycle as the existing FFmpeg process. The running view displays **Keeping this Mac awake until conversion stops** while protection is active.

The Debug build succeeded. During a real conversion, the user confirmed that the keep-awake message appeared while encoding and disappeared when conversion stopped. This verifies that the visible state follows the conversion lifecycle; the underlying state uses macOS's conversion-scoped `ProcessInfo` activity API. Milestone 25 is complete.
