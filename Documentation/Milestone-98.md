# Milestone 98 — Finder drag and drop

The Choose screen has a labeled, highlighted drop area accepting local video files, folders, or a mixture. Folder expansion uses the same immediate-file filtering as the folder picker. Mixed drops are deduplicated by canonical path and sorted in natural filename order. Unsupported files and remote URLs are ignored; a drop with no supported sources shows an explanation and preserves the current queue. Read failures likewise preserve the current selection.

A successful drop replaces the queue, just like the pickers, and opens the first source for review. Dropping never starts encoding. Drops are refused during inspection, batch execution, or active restoration preview. Symbolic links are not followed. Files are read, not moved or deleted.

All three import tests passed. Coverage checks a folder plus a directly dropped copy of one of its videos, repeated folders, unrelated files, and a remote URL. The Release Xcode build, release-app verification, and whitespace checks passed. Finder delivery and target highlighting require hands-on confirmation: drop two videos, then return to Choose and drop a folder. Check the queue before encoding.

Milestone 97 folder selection passed user confirmation before this change.
