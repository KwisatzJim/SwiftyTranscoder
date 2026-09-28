# Milestone 83 — Safe restoration destination promotion

Milestone 83 defines the final handoff from the validated restoration workspace to the user-selected destination.

## Two-step handoff

The final validated workspace file is never moved directly onto the finished filename.

1. Only `restored-audio.partial.mp4` from the approved restoration workspace may enter the handoff.
2. The destination folder, finished filename, and adjacent `.partial.mp4` filename are checked again.
3. The destination volume must report enough free space for the validated file plus a 1 GiB safety reserve.
4. The validated file is copied to the adjacent `.partial.mp4` filename.
5. The staged copy must be a nonempty regular file with the same byte count as the validated workspace file.
6. The finished destination is checked one final time and the adjacent partial file is renamed atomically.

The workspace result remains available during staging. If copying fails, any incomplete destination output remains clearly labeled `.partial.mp4`. If another process creates the finished filename after staging, that file is preserved and promotion stops.

## Path safety

Canonical path comparisons prevent the final or partial destination from resolving to the source. The workspace output also cannot resolve to either destination filename. Existing final and partial files are never overwritten.

## Safety status

Full-video restoration remains disabled in the interface. The isolated stages now cover chunking, restoration, video assembly, audio, subtitles, chapters, metadata, destination staging, and final promotion. The next milestone connects these boundaries into one cancellable full-video pipeline before the feature can be enabled for hands-on testing.
