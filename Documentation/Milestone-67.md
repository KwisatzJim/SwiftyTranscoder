# Milestone 67 — Restoration Job Lifecycle

## Goal

Create one reusable Swift coordinator for restoration work before connecting the research pipeline, user interface, or batch queue.

This milestone still does not make restoration available in the application. It defines and verifies the safety boundary that a later Core ML executor must use.

## Job boundary

`RestorationJob` combines the approved restoration plan with four paths that must never be confused:

- the untouched source file;
- a unique intermediate workspace;
- the clearly labeled `.partial.mp4`; and
- the final `.mp4` destination.

`RestorationJobRunner` coordinates four explicit stages in order:

1. extract source frames;
2. restore those frames;
3. assemble the partial MP4; and
4. independently validate the partial MP4.

The runner promotes the partial file to the final filename only after all four stages return successfully. The stage executor is deliberately replaceable, so the next milestone can connect the proven Core ML and FFmpeg work without placing process details in the coordinator.

## Safety behavior

Before doing any work, the runner verifies that:

- the source still exists;
- the destination is an MP4 and is not the source;
- neither the final nor partial output already exists; and
- a previous workspace will not be silently reused.

Each awaited stage is a cancellation checkpoint. Cancelling asks the active executor to stop immediately and prevents later stages or final promotion. Failures and cancellations retain an existing partial MP4 for diagnosis or deliberate cleanup, while never presenting it as completed output.

Only one job can run through a runner at a time. This gives future single-file and batch callers one consistent lifecycle instead of duplicating safety decisions.

## Verification

Four new automated tests prove that:

- all stages run in order and successful validation promotes the partial file;
- a validation failure keeps the labeled partial file and creates no final file;
- an existing final file is unchanged and no stage begins; and
- cancellation stops a suspended restoration stage and never promotes output.

The complete suite passes 40 tests across 13 suites. The macOS app also builds successfully with Swift 6 complete concurrency checking.

## Result and next gate

Restoration now has a reusable, concurrency-safe lifecycle with the same conservative output rules as the established conversion path. It remains inert because no production stage executor or user-facing control is connected.

The next milestone can implement the first native stage executor for representative preview work, beginning with bounded frame extraction and Core ML invocation while retaining this tested coordinator.
