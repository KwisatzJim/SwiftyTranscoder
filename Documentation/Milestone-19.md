# Milestone 19 — Batch Queue

## Goal

Allow several MKV/MP4 sources to be selected, reviewed, and converted sequentially without opening another window.

## Step 1 — Multi-file selection and queue preview

The source picker now accepts multiple files. When more than one source is selected, the app shows an ordered queue, marks the first item as current, and marks the remaining items as waiting. The current item uses the existing read-only inspection and single-conversion workflow without changing conversion behavior.

Automatic advancement and unattended queue conversion are deliberately deferred until the queue presentation and selection behavior receive runtime confirmation.

The user confirmed multi-file selection, ordered queue presentation, current/waiting status, and normal inspection of the first source.

## Step 2 — Explicit advancement after completion

When a queued conversion completes and another source is waiting, the completion summary offers **Review Next Video**. The user remains in control of the transition: clicking the button marks the previous item complete, makes the next item current, performs its read-only inspection, and presents a fresh conversion plan. Failed or cancelled conversions do not advance.

The user confirmed that the first item became complete, the next item became current and was inspected, the previous completion summary cleared, and a fresh conversion button appeared.

## Step 3 — Queue completion status

The queue header reports the completed count. A successfully converted current item changes to **Completed** immediately, including the final item when no next-file button is available. Waiting, failed, and cancelled items are never counted as completed.

The user confirmed the final item became complete, both rows displayed green checkmarks, the completed count reached the full queue size, and no next-file button remained.

## Step 4 — Encoding ETA

The running conversion display now places a live estimated time remaining to the right of the percentage. The estimate begins after enough progress and elapsed time are available, and is smoothed to reduce distracting jumps. The display changes to **Finalizing…** after FFmpeg finishes rather than showing a misleading zero ETA during output validation.

The user confirmed that the calculating state, live right-aligned ETA, decreasing estimate, and finalizing state all worked well during a real conversion.

## Result

Multi-file selection, ordered status, explicit safe advancement, full-queue completion reporting, and live conversion ETA have all passed runtime testing. Milestone 19 is complete.
