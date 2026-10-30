# SwiftyTranscoder 1.8.3

The GUI now offers **Re-encode video to HEVC** in the proposed conversion. Compatible MP4, M4V, and MOV video can use Apple hardware HEVC at its original size, like MKV conversion. The displayed plan and approved batch settings retain the choice.

The CLI adds `--force-reencode` for ordinary conversion. `--assume-bt709` now accepts untagged MP4 as well as MKV after explicit SDR BT.709 confirmation, and re-encodes the video with BT.709 tags. Existing codec, pixel-format, HDR, and destination protection checks remain in place. Forced ordinary re-encoding cannot be combined with AI restoration.

Distribution: Apple Silicon, macOS 14 or later. Install by opening the DMG and dragging SwiftyTranscoder to Applications. The CLI launcher and usage instructions are included.

Validation: all 202 regression tests passed. The signed release archive passed real MP4 checks for unchanged H.264 copying, forced hardware HEVC encoding, and untagged MP4 confirmation producing HEVC with BT.709 primaries, transfer, and matrix tags. The user confirmed the updated GUI builds in Xcode.
