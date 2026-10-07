# Milestone 126: Identify delayed audio layout information

An MKV with E-AC-3 audio reported six channels but no speaker layout during the default FFprobe scan. The app correctly refused an unknown layout, but a longer scan identified supported 5.1(side) audio at 48,000 Hz.

Media inspection now allows FFprobe to examine up to 20 seconds of media timing and 20 MB of packets. These are scan limits, not a mandatory delay. Compatibility checks remain unchanged; unsupported or unidentified layouts are still refused.

The affected source was inspected read-only with the expanded limits. A short audio conversion and an optimized app build verified the change. The user confirmed successful full-file GUI conversion and good playback. This fix is accepted and published in version 1.6.0.

Pre-release regression verification passed all 172 tests in 42 suites, including real AI model and batch checks. The separate audio-removal feature is also accepted; packaging is authorized.
