# SwiftyTranscoder 1.8.1

MP4 conversions now keep the source filename when the destination is a different folder. For example, `Source/Movie.mp4` becomes `Output/Movie.mp4` without the SwiftyTranscoder suffix.

When the proposed MP4 output would use the source path, the suffix remains to protect the original. MKV and M4V naming is unchanged. Explicit CLI output paths, including the Hopper-to-Plex automation, are unchanged.

Distribution: Apple Silicon, macOS 14 or later. The release app uses Developer ID signing, Hardened Runtime, secure timestamps, and Apple notarization with a stapled ticket. The DMG is signed. Installation: open the DMG and drag SwiftyTranscoder to Applications.
