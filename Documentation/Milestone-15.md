# Milestone 15 — Remember Output Folder

## Goal

Remove repetitive output-folder selection for the user's normal workflow, where every completed video is written to the same directory.

## Behavior

When an output folder is chosen, SwiftyTranscoder stores its path in the application's preferences. The next selected source automatically receives a proposed filename in that folder, including after the application is relaunched. Choosing another folder replaces the saved preference.

The preference stores only the folder path. It does not create files or bypass safety checks. Every proposed output still receives existing-file, incomplete-file, and destination-capacity validation. If the saved directory no longer exists, the app ignores it and asks for a folder normally.

The Debug build succeeded. The user selected the normal output folder, quit the application completely, reopened the updated build, and selected a different source. SwiftyTranscoder automatically proposed the new output filename inside the previously chosen folder without requiring another folder selection. Milestone 15 is complete.
