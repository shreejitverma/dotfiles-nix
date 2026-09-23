---
name: data-backfill
description: Fast and provably correct bulk data movement - historical backfills of ticks, bars, or events, ETL and warehouse loads, exports, manifest catch-up, and table synchronization. Separates backlog from live tail, makes every write idempotent, and ends with a hard accounting block. Use when a large ingest, backfill, or load is slow, stuck, behind, or needs to be run and proven complete.
metadata:
  origin: Adapted from ECC skills/data-throughput-accelerator (MIT, see ../THIRD_PARTY_NOTICES.md)
---

# data-backfill

The goal is not speed alone: it is correct data landed in the right place, with proof, as fast as possible.
A backfill that is fast but silently skipped a day is worse than a slow one.

## First, separate the problems

Measure each before optimizing any of them:

- Source extraction (vendor API rate limits, S3/GCS listing, database read).
- Transfer (network, compression, file size).
- Transform (parsing, normalization, joins).
- Load (warehouse or file-format write, index and partition maintenance).
- Live tail: new data arriving while the job runs.

A pipeline can be fast and still look behind if the live tail grows faster than the final catch-up window; report backlog and tail separately.

## Contracts to read first

- Source: file or partition naming, completeness signal (a `_SUCCESS` marker, a manifest, an end-of-day record count), known late or corrected data.
- Target: schema, primary or natural key, partitioning, and the dedup rule.
- Manifest or checkpoint: what "done" means for one unit of work (a file, a symbol-day, a partition).

## Fast path heuristics

- Move compute to the data: warehouse-native scans and inserts (`COPY`, `INSERT ... SELECT`, external tables) beat pulling rows through Python.
- Columnar formats (Parquet, Arrow IPC) with partitioning that matches both the write and the dominant read pattern (usually date, then symbol or venue).
- Batch small things: many small files into fewer large ones (target hundreds of MB per file), many small requests into bulk ones.
- Parallelize across independent units (symbol-days, partitions) with a bounded worker pool sized by the real bottleneck (vendor rate limit, disk, or warehouse slots), not by core count.
- Vectorized transforms (polars or pyarrow compute) over per-row Python loops.

## Correctness mechanics

- Idempotent writes: each unit writes to a staging location and is atomically swapped or merged by key, so a retry never duplicates rows.
- Manifest per unit: status, source checksum or size, row count, min and max event timestamp, and run id; completed units are skipped on rerun.
- Failures are recorded and surfaced, never skipped: a failed unit stays `failed` in the manifest and fails the job summary.
- Raw, derived, and serving tables are accounted for separately; a derived table catching up does not prove the raw layer is complete.
- For market data specifically: validate per symbol-day against an independent count or the vendor's end-of-day totals, check for gaps in sequence numbers or timestamps during trading hours, and keep the session calendar (holidays, half days, DST) explicit.

## Workflow

1. Read the source, target, and manifest contracts.
2. Measure the backlog: units discovered, units done, rows in raw and derived layers, min and max timestamps, units failed.
3. Benchmark one representative unit and a small parallel batch; find the bottleneck (see the `perf-loop` skill).
4. Compare variants one at a time: batch size, worker count, file grouping, warehouse-native SQL versus client-side transform.
5. Promote the fastest variant whose counts and timestamps reconcile.
6. Codify it as a CLI, scheduled job, or runbook entry, with the manifest as its source of truth.
7. Run it, then rerun the accounting from the target, not from the job's own log.

## Accounting block

End every run with this, read back from the target and manifest:

```text
Backfill result:
- Units discovered: 2,520 symbol-days (2026-01-02 .. 2026-06-30)
- Units completed this run: 2,516   failed: 4 (listed in manifest, run id 01J...)
- Raw rows added: 1,284,993,118    derived bars added: 9,683,598
- Target min/max event time: 2026-01-02T14:30:00Z / 2026-06-30T20:59:59Z
- Gap check: 0 missing minutes in regular sessions except 4 failed units
- Live tail at readback: 3 units behind (today, in progress)
- Runtime: 41m12s on 16 workers (bottleneck: vendor rate limit)
- Correctness gate: manifest counts == target counts per unit: PASS for 2,516, FAIL for 4
```

## Guardrails

- Never delete or overwrite raw data to make counts line up.
- Never mark a unit done without a row count and timestamp range read back from the target.
- Never mix historical backfill status with live-tail freshness in one number.
- The job is complete only when target tables and manifest agree; say which units do not.
- For regulated, client, or trading data, keep replay evidence and get approval before any destructive target operation.
