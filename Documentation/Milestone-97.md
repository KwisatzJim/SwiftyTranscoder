# Milestone 97 — Folder selection

The Choose step now offers **Choose Folder…** alongside individual file selection. It loads immediate, visible, regular MKV, MP4, and M4V files in natural filename order (Episode 2 before Episode 10), accepting uppercase extensions too. Directories, hidden files, symbolic links, and unrelated files are excluded; canonical duplicate paths are skipped. It does not search subfolders or alter source files.

Like existing file selection, choosing a folder replaces the current queue and starts review of the first source. The UI states this explicitly. Empty or unreadable folders show an explanation without replacing the existing selection. Encoding still requires review and approval of each plan.

Both automated tests passed, covering filtering, natural ordering, nested-directory exclusion, symbolic-link exclusion, empty folders, and missing-folder errors. The Release Xcode build, release-app verification, and whitespace checks passed. Hands-on checkpoint: choose a folder containing several videos and verify the queue and review navigation. No conversion is required to check import behavior.

Milestone 96's saved AAC stereo setting passed user confirmation before this change.
