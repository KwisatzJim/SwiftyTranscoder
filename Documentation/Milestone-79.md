# Milestone 79 — Bounded Restoration Chunks

## Goal

Replace the full-sequence storage assumption with a deterministic chunk plan that never requires all source and restored PNG frames to coexist.

## Chunk boundary

A full-video plan is divided into consecutive chunks of at most 120 frames. Chunk start times are derived from the exact rational source cadence, not a rounded display value. The final chunk contains only the remaining frames.

The coordinator processes one chunk at a time. A completed encoded segment must live outside its disposable frame workspace. Only after that condition is verified does the coordinator remove the chunk's source and restored frame folders and advance to the next chunk. Failure or cancellation also removes the active chunk workspace without touching completed segments or unrelated files.

The 240-frame hard ceiling already enforced by extraction and assembly remains in place. The lower 120-frame production default provides a tighter storage bound and more frequent cancellation checkpoints.

## Storage planning

The plan interface now reports a **Bounded workspace** estimate. It budgets source and restored pixels for no more than 120 resident frames, compressed working media, and a 1 GiB reserve. It also shows the total number of chunks so the user can see that the estimate covers a full-video plan rather than only a preview.

For the existing 45-minute 624×352 test case at `24000/1001`, the plan contains 64,736 frames in 540 chunks. Its conservative temporary-space estimate falls from 289,456,400,384 bytes under full-sequence retention to 5,600,897,024 bytes with bounded chunks.

## Safety state

Full-file execution remains disabled. This milestone establishes and tests the storage lifecycle but does not yet concatenate encoded chunk segments or perform final container validation. The ordinary conversion path and the approved restoration preview are unchanged.

## Next gate

The next milestone should encode each restored chunk as a timestamp-safe silent HEVC segment, concatenate the segments without retaining frame folders, and independently validate duration, cadence, dimensions, codec, and color metadata before audio or subtitle integration.
