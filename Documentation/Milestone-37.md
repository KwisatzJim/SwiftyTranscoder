# Milestone 37 — Remove a Video from a Batch

## Goal

Remove an unwanted source from a batch before encoding without rebuilding the queue or discarding unrelated approvals.

## Step 1 — Safe queue removal

Each queue row now has a remove control while the batch is not running. A confirmation names the affected video and explicitly states that its source file will not be changed or deleted.

Removing an entry reindexes the remaining queue state and approved plans. At the all-plans-approved checkpoint, the remaining approvals stay intact and the batch returns ready when appropriate. If only one source remains, it becomes an ordinary single-file plan. Removal is unavailable after encoding begins.

The Debug build succeeded. At a three-video batch-ready checkpoint, the user confirmed that the removal dialog named the selected video and stated that its source would not be changed or deleted. After removing one of two same-named sources, the other two rows remained approved, the duplicate-destination warning disappeared, and **Start Approved Batch** became enabled. Milestone 37 is complete.
