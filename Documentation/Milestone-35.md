# Milestone 35 — Explained Disabled Approval

## Goal

Make a disabled approval or conversion button explain the exact unresolved requirement.

## Step 1 — Reuse command validation

The interface now asks the same `VideoConversionCommand` validation used at conversion time for its current blocking error. When the primary button is disabled by that validation, the localized explanation appears immediately beneath it. This avoids maintaining a separate list of UI-only rules that could drift away from the actual safety checks.

The Debug build succeeded. Using an intentionally untagged one-second MP4, the user confirmed that the disabled **Convert Approved Plan** button now displays the exact SDR/color safety explanation beneath it. Milestone 35 is complete.
