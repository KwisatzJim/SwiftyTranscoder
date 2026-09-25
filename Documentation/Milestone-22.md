# Milestone 22 — Optional Stereo AAC Compatibility Track

## Goal

Optionally add a secondary AAC stereo track for clients that do not directly support the primary AC-3 compatibility track.

## Step 1 — Plan choice and safety block

The proposed conversion now includes an **Add AAC stereo compatibility track** toggle. It is off by default, so existing output remains unchanged.

While the preview option is enabled, conversion is deliberately blocked and the plan explains why. The dual-audio FFmpeg mapping and output validation will be implemented only after the option's wording and placement receive runtime confirmation.

The user confirmed the option's placement and wording, its off-by-default state, warning, and safety block.

## Step 2 — Dual-audio output and validation

When enabled, FFmpeg maps the primary source audio twice. The first output remains the default AC-3 track with the source's supported channel layout. The second output is non-default AAC stereo at 192 kb/s and 48 kHz. Both tracks preserve the source language tag and apply the protected +6 dB path when gain is enabled; the secondary limiter runs after stereo downmixing.

Post-conversion validation now requires exactly two audio tracks when the option is enabled. It verifies AC-3 remains first and default, AAC stereo remains second and non-default, and checks codec tags, channel layouts, sample rates, bit rates, and language metadata before the partial file can become the final output.

A generated three-second smoke test passed with primary AC-3 mono at 96 kb/s marked default and secondary AAC stereo at approximately 192 kb/s marked non-default. Both tracks were 48 kHz, carried the English language tag, and used the protected gain filters. Real application conversion remains pending.

The real MP4 application conversion `Spa Weekend (2026) - SwiftyTranscoder.mp4` completed and passed the app's validation. Independent inspection confirmed primary/default AC-3 5.1(side) at 224 kb/s and secondary/non-default AAC LC stereo at approximately 194 kb/s, both at 48 kHz with matching language metadata and descriptive names. All video and audio streams start at zero, and their durations remain within approximately 0.08 seconds across a 5,835.9-second feature.

The source and output H.264 packet hashes were identical (`0a9924447e5e295dbfb1fcc62fe1f9e8d84a6a25a2600987d9e2fb8e4a0a0cfe`), proving the MP4 video was copied unchanged. Plex client validation remains pending.

Plex playback on local-network Firefox/Rossum initially transcoded both streams to H.264 SD and AAC stereo even with the secondary AAC track selected, Original/Maximum quality selected, and subtitles off. Because Plex reduced the copied 1920×800 H.264 video to SD, this session was a Firefox/Plex client decision rather than evidence of an invalid AAC track.

After the Plex server host received system and kernel updates and rebooted, Safari/MacBook Neo testing became stable enough to compare the two tracks directly. The primary AC-3 5.1 track Direct Played both video and audio. Selecting the secondary AAC stereo track instead caused video Direct Stream and audio Transcode. The optional AAC track therefore provides no compatibility advantage on Safari and is correctly kept non-default.

Plex Web's Direct Play and Direct Stream settings were confirmed enabled in Firefox, with Original/Maximum quality and subtitles off. Both AC-3 and AAC selections still produced video Direct Stream and audio Transcode, so no Firefox setting change resolved the browser-player behavior. The official Plex HTPC application on the same Rossum Linux PC Direct Played both the copied video and the secondary AAC stereo audio. This confirms that the AAC track provides a real compatibility path for Rossum through Plex's native client while the Firefox result is specific to Plex Web.

The Plex application on Roku also Direct Played the same output. Picture, audio, and synchronization had already passed local playback, completing the representative client validation for the optional AAC track. Milestone 22 is complete.
