---
name: mle-workflow
description: Production ML and quantitative-research workflow - prediction and data contracts, point-in-time correctness and time-series leakage (walk-forward splits, purging and embargo, survivorship, look-ahead in features and labels), reproducible training, evaluation and promotion gates, backtest overfitting controls, error analysis, and serving parity. Use when building, reviewing, or hardening a model, signal, forecast, or feature pipeline beyond a one-off notebook, or when a backtest or offline metric looks too good.
metadata:
  origin: Adapted from ECC skills/mle-workflow (MIT, see ../THIRD_PARTY_NOTICES.md)
---

# ML and research workflow

The goal is a model or signal whose offline evidence predicts its live behavior.
Most failures are not modeling failures: they are leakage, non-reproducibility, and train/serve mismatch.
Check those first, every time.

## Iteration compact

Before touching model code, write this in the PR or experiment note; it is the design doc.

```text
Goal / decision changed by the model:
Decision owner:
Target and horizon (what is predicted, over what window, known when):
Success metric (and why it maps to money or product value):
Guardrails (turnover, capacity, drawdown, latency, calibration, slices):
Unacceptable mistakes / acceptable mistakes:
Data snapshot or version:
Split policy (walk-forward windows, purge, embargo):
Baseline to beat:
Hypothesis for this iteration (falsifiable):
Eval slices (regime, venue, instrument bucket, time of day):
Known risks:
Rollback or fallback:
```

## Prediction and data contracts

Prediction contract: target, horizon, output schema (point estimate, probability, confidence), latency budget, serving mode (batch, online, streaming), and the fallback when the model or a feature is unavailable.

Data contract, per source:

- Entity grain and key, units, currency, and adjustment basis (split- and dividend-adjusted or raw).
- Event time versus availability time: when the value happened, and when you could first have known it (publication lag, vendor delay, restatements).
- Required columns, allowed nulls, ranges, and categories, validated at load (pandera, pydantic, or explicit asserts), failing loudly.
- The snapshot or version id used, so any result can be regenerated exactly.

## Leakage and point-in-time correctness

Leakage is the default outcome unless something prevents it.
Every item here is a review blocker.

**Features**
- Every feature is computed only from data available at decision time, using availability time, not event time.
  Joins use as-of semantics (`pd.merge_asof(..., direction="backward", allow_exact_matches=...)` with a deliberate choice about same-timestamp data, or polars `join_asof`).
- Rolling and expanding windows end at the decision timestamp inclusive or exclusive by an explicit choice; `center=True` is forbidden in features.
- Normalization, scaling, winsorization bounds, PCA, and target encodings are fit on the training window only, then applied forward.
- Revised data (fundamentals, macro releases) uses as-first-reported vintages, not today's restated values.
- Forward fill never crosses a session, trading halt, or data gap longer than the feature's stated tolerance.

**Labels**
- A label over horizon `h` overlaps the next `h` periods; adjacent samples are not independent.
- Labels use prices that were tradeable at the stated time (next open or VWAP after the signal, not the close that produced it).

**Universe**
- Point-in-time universe membership: include delisted, bankrupt, and merged names as of each date; survivorship bias makes every long-only backtest look better.
- Corporate actions applied as of their effective dates.

**Splits**
- Never shuffle time series.
  Use walk-forward (rolling or expanding) splits in time order.
- Purge training samples whose label window overlaps the test window, and embargo a gap after each test window at least as long as the label horizon plus any feature lookback that could carry test information.
- Hold out a final untouched period that is evaluated once, at the end, after all selection is done.

Quick leakage probes: shuffle the labels and confirm the metric collapses to chance; shift features one period into the past and confirm performance degrades rather than improves; check that test performance is not suspiciously close to train performance.

## Reproducible pipeline

- Typed config (frozen dataclass or pydantic model) for every path and hyperparameter; no notebook state.
- Pinned dependencies (lockfile), recorded code SHA, config hash, and data snapshot id with every artifact and metric.
- Seeds set and passed explicitly; document any nondeterministic GPU kernels.
- One transformation code path shared by training, backtest, and serving; preprocessing is saved with the model artifact.
- Steps are idempotent: rerunning a stage rewrites the same output, never appends duplicates.

## Evaluation and promotion

Declare promotion criteria before looking at the test results.

- Compare against the naive baseline (zero, last value, simple momentum, logistic regression) and against the current production model; beating nothing is not a result.
- Report the metric that maps to value: for signals, information coefficient and its t-stat, turnover, and net-of-cost PnL; for classifiers, a confusion matrix and calibration, not only AUC.
- Costs are part of the model: include spread, fees, slippage, and market impact at realistic size; a signal that only works before costs does not work.
- Stability: metric per walk-forward window and per slice (regime, volatility bucket, instrument group, time of day), not just the pooled average; one great year hiding four flat ones is a finding.
- Multiple-testing discipline: record every variant tried (see the `decision-ledger` skill); the best of N backtests is biased upward by selection, so deflate it (deflated Sharpe ratio, probability of backtest overfitting via combinatorially symmetric cross-validation) or confirm on the untouched holdout.
- Capacity and turnover limits stated, with the size at which performance degrades.

Promotion gate: beats baseline and production on the primary metric after costs, no guardrail regressed, stable across windows and slices, holdout confirmed once, artifact reproducible from the recorded SHA, config, and snapshot, and rollback is a config flip.

## Error analysis loop

After each run:

1. Split mistakes by type (false positives and negatives, large-loss trades, abstentions) and by slice.
2. Separate model error from data bugs, label ambiguity, stale features, and serving mismatch; most "model" problems are the latter.
3. Turn each major cluster into one next move: better labels, better features, better threshold or sizing, or a product fallback.
4. Pin every real bug as a regression test or eval slice (see the `python-testing` skill).
5. Write the next iteration as a falsifiable hypothesis, not "improve the model".

## Serving and operation

- Train/serve parity test: the same inputs through the offline pipeline and the serving path produce identical features and predictions, checked in CI on a fixed fixture.
- Paper or shadow run before capital: live data, no orders, predictions logged and compared with the backtest's expectation for the same period.
- Monitor feature freshness and null rates, prediction distribution drift, realized versus expected performance, and latency; alert on staleness before it becomes a wrong trade.
- Kill switch and rollback to the previous artifact are tested, not assumed.
- Artifacts load safely: no unpickling of untrusted files; prefer safetensors, ONNX, or explicit formats with checksums.

## Review checklist

- Any feature, scaler, or encoder fit on data after the decision time? (blocker)
- Split shuffled, or missing purge and embargo for overlapping labels? (blocker)
- Universe not point in time, or restated data used as first reported? (blocker)
- Costs, slippage, and capacity missing from the headline number? (blocker)
- Number of variants tried unrecorded, holdout used more than once? (high)
- Metrics only pooled, no per-window or per-slice breakdown? (high)
- Artifact not reproducible from recorded SHA, config, and snapshot? (high)
- No train/serve parity test or shadow period? (high)
