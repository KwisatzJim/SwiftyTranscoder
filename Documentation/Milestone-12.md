# Milestone 12 — MP4 Audio-Gain Sources

## Goal

Allow an existing MP4 to receive the protected +6 dB audio treatment without needlessly re-encoding its video.

## Step 1: Safe selection and inspection

The source picker now accepts MKV, MP4, and M4V files. MP4 sources use the same read-only `ffprobe` inspection and human-readable analysis as MKV sources. The proposed destination adds ` - SwiftyTranscoder` before `.mp4`, preventing a same-folder output from colliding with the source filename.

Conversion is deliberately blocked during this first step. The plan explains that MP4 inspection is supported but the video-copy audio path is not enabled yet. The next step will copy compatible video unchanged, process only the primary audio, and add validation specific to copied video.

The user confirmed that a real MP4 could be selected and inspected, its media details were correct, the distinct ` - SwiftyTranscoder.mp4` destination was proposed, and conversion remained blocked during this step.

## Step 2: Copy video and process audio

Compatible MP4 and M4V sources now use FFmpeg video stream copy instead of VideoToolbox encoding. The primary audio follows the same mono, stereo, or 5.1 AC-3 policy and optional protected +6 dB gain as MKV conversion. The plan explicitly says that video will be copied unchanged.

Burn-in is unavailable in this path because it would require decoding and re-encoding video. An MP4 with a selected subtitle track is blocked with an explanation to choose `Omit subtitles`. Untagged MP4 color is also blocked rather than pretending a container metadata change can safely establish its color interpretation.

Output validation compares the copied codec, codec tag, profile, pixel format, color metadata, dimensions, and frame rate against the source. A ten-second smoke test using `Reacher - s04e08 - Cut.no-gain.mp4` produced protected AC-3 5.1 at 48 kHz and 224 kb/s. SHA-256 hashes of the source and output HEVC packet stream were identical (`62b568630f0943030b06aab9c7e77623a9827e25499663303ee414ef306ffa94`), proving that the video was copied rather than re-encoded.

The user then completed the full conversion in SwiftyTranscoder and confirmed successful completion, normal playback, synchronized audio, and a noticeable loudness increase. Independent inspection confirmed HEVC Main `hvc1`, 1920 × 960 `yuv420p`, BT.709 space/transfer/primaries, 24000/1001 fps, and English AC-3 `5.1(side)` at 48 kHz and 224 kb/s. The final duration is 3463.483 seconds. Full source and output HEVC packet-stream hashes were identical (`1c965e0f2c7769b578f54c892145533c0d207140e6ec6a2cabae02a793022d47`), proving that no video re-encoding occurred. Milestone 12 is complete.
