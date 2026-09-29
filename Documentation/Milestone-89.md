# Milestone 89 — Real production completion proof

Milestone 89 verifies the complete production restoration path with real source media, the real Core ML model, hardware HEVC encoding, and the real FFmpeg and FFprobe helpers before asking for an unattended episode-length run.

## Short but complete production job

The integration check reads the first two frames of `Alphas - s01e11 - Original Sin.m4v` and sends them through the same concrete pipeline used by the application:

1. bounded source-frame extraction;
2. native Real-ESRGAN Core ML restoration;
3. hardware HEVC segment assembly with the reviewed cadence and SDR color metadata;
4. copy-only silent-video concatenation;
5. protected-gain AC-3 and AAC stereo creation;
6. independent audio and video validation;
7. destination capacity checking and adjacent staging; and
8. atomic final-output promotion.

This is deliberately a short source interval, but it does not replace any production stage with a mock.

## Independent completion assertions

After the pipeline reports completion, a separate FFprobe inspection confirms:

- HEVC video at 1248×704;
- the exact `24000/1001` source cadence;
- primary AC-3 and secondary AAC audio; and
- the primary audio track remains the default.

The check also confirms that the private restoration workspace was removed, the final MP4 exists, aggregate progress reached 100%, and no adjacent `.partial.mp4` remains.

## Verification

The focused real-production completion test passed in approximately eight seconds. The complete suite then passed with 107 tests across 28 suites, including all existing cancellation, safety, representative-model, and native-pipeline checks.

## Next hands-on checkpoint

The completion path is ready for an episode-length run of the SD source in the application. Let the job finish, then confirm that the interface reports **Restored conversion completed** and that the resulting MP4 opens and plays. Picture, audio synchronization, available audio tracks, and Plex behavior can then be reviewed as separate focused checks.
