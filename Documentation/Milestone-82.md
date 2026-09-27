# Milestone 82 — Restoration subtitles, chapters, and metadata

Milestone 82 defines how an approved full-video restoration keeps subtitle timing and useful container information without adding a second lossy picture encode.

## Subtitle boundary

- An approved burn-in subtitle is applied while each restored chunk is encoded to HEVC.
- The subtitle filter temporarily moves the chunk onto the source video's absolute timeline, renders the selected subtitle stream, and then resets the chunk timestamps before encoding.
- An approved omit choice adds no subtitle filter.
- A subtitle choice that still needs user review must remain blocked when the full pipeline is connected.
- The later assembly and audio stages copy the already-encoded restored picture. They do not encode it again.

This placement matters because burning subtitles after chunk assembly would require another lossy video encode and would discard some of the restoration quality.

## Chapter and metadata boundary

The full-duration audio/container stage copies source chapters and container metadata into the restored MP4 while it copies the restored HEVC picture unchanged. Validation now requires:

- the approved video-and-audio stream layout;
- the expected chapter count;
- the original container title when one is present;
- HEVC with the `hvc1` compatibility tag;
- the approved primary AC-3 and optional AAC stereo tracks; and
- valid duration and file size.

Subtitles are not copied as separate streams. They are either already burned into the restored picture or intentionally omitted according to the approved plan.

## Safety status

Full-video restoration remains disabled in the interface. This milestone completes another isolated boundary; final destination validation and end-to-end pipeline coordination still have to be added before production execution can be enabled.
