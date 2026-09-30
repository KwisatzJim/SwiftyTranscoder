# Milestone 91 — Restore bundled segment joining

The first episode-length restoration reached silent segment assembly, then failed with `Unrecognized option 'safe'`. The bundled minimal FFmpeg executable had been built without the concat demuxer. The assembly command uses `-f concat -safe 0` to join the already encoded HEVC segments without another video encode. Unit tests had previously used a fake FFmpeg helper, so they did not expose the missing runtime capability.

The toolchain build now enables the concat demuxer and verifies that it is present. The release app verifier checks the same capability in the packaged helper. Full-video pipeline construction also checks the selected FFmpeg executable before any frames are restored and reports a clear error if concat support is absent.

A new integration test encodes two short, real HEVC segments with the staged helper and joins them through `RestorationSegmentConcatenator`, including its independent output validation. This test passed. The rebuilt helper was staged, and the Debug app built successfully with that helper embedded; the app's own FFmpeg reports concat support.

The failed episode-length job removed its temporary restoration workspace as part of the existing failure cleanup. Its completed chunks therefore cannot be resumed. Rebuild and launch the updated app before another full-video attempt.
