# SwiftyTranscoder 1.8.2

MP4, M4V, and MOV sources can now burn embedded SubRip or MP4 timed-text (mov_text) subtitles into the picture during ordinary conversion. Selecting a subtitle track automatically re-encodes the video to HEVC using Apple hardware. The proposed conversion explains when subtitle burn-in requires re-encoding.

The bundled FFmpeg now includes the MP4 timed-text decoder. Toolchain and release verification check that the decoder is present.

MP4 video copying remains available when subtitles are omitted and no resizing is requested. Existing SDR requirements and source-file protection remain in place. AI restoration retains its existing SubRip subtitle support.

Validation: all 201 regression tests passed, the app built successfully, a sample MP4 passed burn-in with the rebuilt bundled FFmpeg, and the user confirmed successful conversion of the affected MP4. The mounted DMG passed signature, stapling, Gatekeeper, bundled-resource, CLI-help, and real MP4 subtitle burn-in checks. Installer and third-party source checksums were verified.

Distribution: Apple Silicon, macOS 14 or later. The release app uses Developer ID signing, Hardened Runtime, secure timestamps, and Apple notarization with a stapled ticket. The DMG is signed. Installation: open the DMG and drag SwiftyTranscoder to Applications.
