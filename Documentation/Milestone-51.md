# Milestone 51 — Confirmation-Only Likely-Forced Subtitles

## Goal

Help identify a short “foreign parts only” English subtitle track when the source does not mark it as forced, without silently guessing or burning it.

## Evidence

SwiftyTranscoder now reads existing Matroska `NUMBER_OF_FRAMES` and `DURATION` subtitle statistics. Technical Details shows the event count and track span for each subtitle stream. The track span is labeled carefully because it is the final subtitle timestamp, not the total time text remains visible.

This uses metadata already returned by the normal read-only inspection. It does not add a slow full-file packet scan.

## Conservative recommendation

Explicit Matroska forced disposition and clearly forced titles retain priority. Statistical analysis runs only when neither identifies a forced track.

A track is presented as **Likely forced—please confirm** only when:

- It is an English SubRip text track.
- It is not marked or titled as SDH, hearing-impaired, or closed captions.
- It contains no more than 200 subtitle events.
- Another English track contains at least 300 events and at least three times as many events.
- Exactly one track satisfies all of those conditions.

A lone sparse track, multiple sparse candidates, unsupported image subtitles, and missing or malformed statistics produce no statistical recommendation.

## User control

A likely-forced result is evidence, not approval. The Review page names the possible stream and explains the event-count comparison. The Plan page remains at **Choose a track…**, and conversion approval remains disabled until the user explicitly chooses that stream, another stream, or **Omit subtitles**.

## Verification

The Debug application builds successfully. All 30 automated tests across 10 suites pass, including evidence parsing, a single strong likely-forced candidate, a lone sparse track, and multiple ambiguous sparse candidates.

Runtime verification used `Likely Forced Subtitle Test.mkv`, a small synthetic source with two unflagged English subtitle tracks. The user confirmed that Review displayed **Likely forced—please confirm**, explained the 17-versus-814 event comparison, and that Plan still required an explicit subtitle choice before approval.

The duplicate Technical Details disclosure discovered during testing was removed and confirmed corrected. Milestone 51 is complete.
