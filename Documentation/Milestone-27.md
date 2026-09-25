# Milestone 27 — Optional Batch Notifications

## Goal

Let the user leave an unattended batch running and receive a clear macOS notification when it completes or stops.

## Step 1 — Permission and lifecycle-aware notifications

Multi-file queues now offer **Notify when this batch finishes or stops**. The option is off by default and asks macOS for notification permission only when the user enables it. The preference is remembered for future queues.

A successful final validation sends the completed video count. Failure, cancellation, a missing approved plan, or inability to start the next conversion sends a stopped notification naming the affected source. Notification problems never alter conversion results; the app reports them separately and turns the preference off when initial permission is denied.

The Debug build succeeded. On the first runtime test, macOS reported that notifications were not allowed and then registered SwiftyTranscoder in Notification settings. After the user enabled notifications there, the queue option remained checked and a real batch produced the expected completion notification while another application was active. This confirms both the denied-permission guidance and successful completion-delivery paths. Milestone 27 is complete.
