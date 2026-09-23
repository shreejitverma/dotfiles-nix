---
name: decision-ledger
description: Append-only experiment and decision ledger for repeated searches - parameter sweeps, backtest variants, hyperparameter tuning, strategy research, ensemble comparisons, and any recursive rollout - with accept, watch, reject marks, comparison against the prior accepted winner, a count of every variant tried, and a paper-before-live promotion rule. Use when running many variants of an experiment, tuning a strategy or model, or when conclusions must survive selection bias and later scrutiny.
metadata:
  origin: Adapted from ECC skills/recursive-decision-ledger (MIT, see ../THIRD_PARTY_NOTICES.md)
---

# decision-ledger

Repeated trials are useful; repeated trials that forget their history are how overfit strategies get promoted.
The ledger keeps every run, marks each candidate, and compares against the last accepted winner rather than the last run.

## Ledger contract

One JSON object per line in an append-only file committed next to the research code (for example `research/<study>/ledger.jsonl`), plus a short Markdown summary per rollout.
Every record includes:

```json
{"rollout": 15, "ts": "2026-09-23T14:05:00Z", "code_sha": "9e1c520", "data_snapshot": "bars-2026-09-20",
 "config_hash": "a1b2c3d4", "search_space": "lookback in [5..120], z_entry in [1.0..3.0]",
 "trials": 480, "effective_trials": 37, "prior_winner": "rollout-12/cand-7",
 "candidates": [{"id": "cand-3", "params": {"lookback": 40, "z_entry": 2.0},
                 "metric": {"sharpe_net": 1.41, "ic": 0.031, "turnover": 0.8, "max_dd": 0.07},
                 "mark": "watch", "reason": "beats winner in-sample, fails 2024 window"}],
 "promotion": {"allowed": false, "reason": "holdout not yet run"}}
```

- `trials` is every configuration evaluated, including failures; `effective_trials` estimates independent trials after accounting for correlated variants.
  Both feed the overfitting correction in the `mle-workflow` skill (deflated Sharpe, probability of backtest overfitting).
- Records are appended before any summary is written; nothing is edited in place.

## Marks

- `accept`: beats the prior accepted winner on the primary metric after costs, passes correctness and replay checks, stable across windows.
- `watch`: promising but missing a gate (one bad window, too few trades, not yet replayed).
- `reject`: fails a gate or is dominated.
- `decay-watch`: a previous `watch` or `accept` whose edge has deteriorated on fresh data.
- `needs-replay`: result depends on data or code that has since changed.

## Rollout loop

1. Load the ledger; note the prior accepted winner and the watchlist.
2. Record fresh information at time zero (new data through date X, a fixed bug, a changed cost model).
3. Run the bounded search (budget stated up front, see the `perf-loop` skill for loop discipline).
4. Mark every candidate, with a one-line reason.
5. Compare the best candidate against the prior accepted winner, on the same data window and cost model.
6. Downgrade earlier marks invalidated by drift, stale data, a failed replay, or a bug fix.
7. Append the record, then write the summary.

## Coherence mark

Each summary carries a compact consistency check:

```text
Best candidate matches prior winner: false (cand-3 vs rollout-12/cand-7)
Holds on every walk-forward window: false (2024-H2 negative)
Replay on untouched holdout: not run
Live promotion allowed: false - holdout gate not satisfied
```

## Promotion rules

For trading, capital allocation, production deploys, or migrations, confidence from repeated rollouts is not approval.

- Default to paper, shadow, dry-run, or read-only mode.
- Promote only when the candidate beats the accepted winner after costs, correctness and replay checks pass, risk limits are explicit, the evidence is in the ledger, and a human has approved the live step.
- The untouched holdout is evaluated once per promotion decision; using it to choose between candidates turns it into training data.

## Summary shape

Lead with the decision and its evidence, not the process:

```text
Rollout 15: prior winner (rollout-12/cand-7) still holds.
Best new candidate cand-3 improves net Sharpe 1.22 -> 1.41 in-sample but loses money in 2024-H2.
Status: watch. Next gate: walk-forward rerun with the corrected borrow-cost model.
Trials to date: 1,912 (effective ~140); deflated Sharpe of cand-3 not significant at 5%.
```
