# Milestone 125: Reject malformed chapter timelines

Some MKV sources contain chapter markers beyond the movie's actual duration. Copying these into MP4 creates a chapter data track extending past the video and audio. Apple players can then report the chapter track's duration, even when FFprobe's container duration is correct.

Ordinary conversion and full AI restoration now copy chapters only when every chapter has finite, nonnegative, ordered timestamps within the source duration (allowing 0.1 seconds of end rounding). Invalid chapter lists are omitted as a whole; valid lists remain unchanged.

A reported source had 2h25m of video/audio but chapter markers at 10,000, 44,000, and 78,000 seconds. A separate corrected MP4 was made by copying its existing video/audio and omitting chapters, without re-encoding or changing the originals.

Focused chapter tests cover valid lists, the reported timeline, negative/reversed timestamps, chapters starting at the movie end, and missing timestamps. Apple playback inspection confirmed the corrected duration, and the user confirmed corrected playback. This fix is accepted and published in version 1.6.0.
