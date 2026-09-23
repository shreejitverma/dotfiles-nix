---
name: silent-failure-hunt
description: Hunt for silent failures - swallowed exceptions, ignored return codes, fallbacks that hide errors, lost error context, and numerical failures that propagate without raising (NaN and inf, bad fills, empty frames, timezone-naive joins, integer overflow). Covers Python, pandas and numpy, C++, and shell. Use when reviewing a change for error handling, when a pipeline, backtest, or job "succeeded" but produced wrong or empty output, or before shipping code that moves data or money.
metadata:
  origin: Adapted from ECC agents/silent-failure-hunter.md (MIT, see ../THIRD_PARTY_NOTICES.md)
---

# silent-failure-hunt

A crash is a bug you know about; a silent failure is a bug that ships.
The target is any path where something went wrong and the code continued as if it had not, or produced a plausible-looking wrong answer.

## How to hunt

1. Scope: the diff under review (`git diff origin/main...HEAD`), or the pipeline stage that produced bad output.
2. Grep for the patterns below, then read each hit in context; a pattern is only a finding when the surrounding code actually loses the failure.
3. For each real finding, state the concrete failure scenario: which input or condition triggers it, and what wrong output or state results.
4. Report findings ranked by impact; zero findings is a valid result.

## Hunt targets

### Swallowed errors (all languages)
- `except Exception: pass`, bare `except:`, `except ...: return None` or `return []` with no log and no re-raise.
- C++ `catch (...) {}` or a `catch` that logs and continues past a broken invariant.
- Shell scripts without `set -euo pipefail`, `cmd || true` on commands whose failure matters, unchecked `$?`, pipes whose left side can fail silently.
- Logging an error and then returning a success value, or logging at `debug` for something that should page.

### Ignored results and lost context
- C++: discarded return values of functions that report errors (`write`, `fsync`, `pthread_*`, `std::from_chars` result not checked), `errno` read without checking the call failed, missing `[[nodiscard]]` on `std::expected`/status-returning APIs, unchecked `std::optional::operator*`.
- Python: calling a function that returns an error object or status and discarding it; `subprocess.run` without `check=True` or an explicit return-code check.
- `raise NewError("failed")` without `from e`, dropping the cause; generic rethrows that erase the type callers branch on.
- Async: un-awaited coroutines, fire-and-forget tasks whose exceptions are never retrieved, futures never joined.

### Fallbacks that hide failure
- Defaults returned on error that look like real data: `0.0` price, empty list of fills, yesterday's cached value served without a staleness flag.
- `dict.get(key, default)` or `getattr(obj, name, None)` where a missing key means the upstream contract broke.
- Retry loops that exhaust and then fall through to the success path.
- Config lookups that silently fall back to a default environment or account.

### Numerical and data silent failures (Python, pandas, numpy, polars)
- NaN and inf propagation: arithmetic on columns with NaN, division by zero producing inf, `np.log` of non-positive values; check with explicit `isna`/`isfinite` assertions at stage boundaries.
- `fillna(0)` or `fillna(method="ffill")` applied broadly: zero is a real value for returns and positions, and forward fill across a session boundary, halt, or data gap fabricates prices.
- Failed or empty loads becoming empty DataFrames: `read_parquet` on an empty glob, a filter that removes everything, a join that matches nothing; downstream code happily computes on zero rows.
  Assert non-empty and expected row counts after every load, filter, and join.
- Joins that change row counts unexpectedly: `merge` on non-unique keys duplicating rows, `how="left"` hiding unmatched keys as NaN; use `validate="one_to_one"` or `"many_to_one"` and check `indicator=True` counts.
- Timezone-naive versus aware mixing, local time assumed as UTC, DST transitions duplicating or dropping an hour.
- Dtype drift: numeric columns becoming `object` after a bad row, silent downcasting, integer columns turning into float when a NaN appears.
- Index misalignment: arithmetic between Series with different indexes silently aligns and inserts NaN.
- `SettingWithCopyWarning` or chained assignment that modifies a copy, leaving the original unchanged.
- Sorting assumptions: rolling or `diff` on data that is not sorted by time.

### Numerical silent failures (C++)
- Signed overflow (UB) in price times quantity, notional sums, or timestamp arithmetic; unsigned wraparound in sizes and differences.
- Narrowing conversions (`int64_t` to `int`, `double` to `float`), float equality comparisons, accumulating float error in long sums (use integer ticks or compensated summation).
- Uninitialized members in structs sent over the wire or used as defaults.

### Missing guards around effects
- Network, file, and database calls without timeouts, or with timeouts that are caught and ignored.
- Multi-step writes without a transaction, atomic rename, or idempotency key, so a mid-way failure leaves partial state that looks complete.
- Order or position state updated before the confirming acknowledgement arrives, with no reconciliation path.

## Finding format

```text
[severity] path:line - <one-line defect>
Scenario: <input or condition> -> <wrong output or state>
Fix: <specific change: raise, check, assert, validate=, set -e, [[nodiscard]], ...>
```

Severity: CRITICAL when wrong data, money, or orders can result without any signal; HIGH when an operator would find out only much later; MEDIUM when the failure is visible but loses the context needed to diagnose it.

## Fix principles

- Fail loudly at the boundary where the contract breaks, with the context needed to diagnose it (inputs, ids, counts), and let the caller that can actually handle it decide.
- Replace broad catches with the specific exception types that are expected and handled.
- Assert invariants at stage boundaries in data pipelines: row counts, key uniqueness, non-null required columns, time ordering, value ranges.
- Distinguish "no data" from "failed to get data" in types (`None` versus an exception, an empty result versus a `Result` error).
- When a fallback is genuinely correct, make it visible: log at warning with context and emit a metric, so it can be alerted on.
