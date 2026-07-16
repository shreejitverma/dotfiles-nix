---
name: ship
description: End-to-end loop for shipping production-quality work with the integrated IC toolchain - check quota headroom, track the task, isolate a worktree, implement with verification, gate through no-mistakes, and stow session knowledge. Use when asked to build, implement, fix, or ship a feature or change, or when the user invokes /ship.
user-invocable: true
---

# ship

The default operating loop for delivering a feature, fix, or change at production quality.
Each phase names the tool that owns it and the exact command to run.
Skip a phase only when it clearly does not apply (for example, no worktree for a one-line docs fix), and say so.

## 0. Check headroom

```sh
quota-axi
```

If the relevant session or weekly window is low, tell the user before starting a long or expensive run and let them decide.

## 1. Track the task

```sh
tasks-axi add <id> "<title>" --start   # if the work is not already in the backlog
tasks-axi start <id>                   # if it is
```

Multi-step work gets a backlog entry so progress and outcomes survive the session.
Trivial one-shot requests can skip this; say so when skipping.

## 2. Isolate the stream

```sh
treehouse
```

One worktree per independent stream of work.
Never develop two streams in the same checkout, and never work directly on the default branch.

## 3. Implement

Follow the global operating manual: understand first, plan briefly, prefer small reversible changes, verify claims locally, root-cause fixes over patches.
Use the specialized tools instead of ad hoc equivalents:

- `gh-axi` for anything GitHub: issues, PRs, CI runs, releases.
- `chrome-devtools-axi` for anything with a web surface: drive the real page, do not guess.
- `lavish-axi` when a plan, diff, or comparison is easier to judge as a rich artifact than as prose.

## 4. Verify end to end

Reproduce bugs in an end-to-end setting before fixing them.
Run the smallest meaningful check first, then broaden.
For product changes, exercise the affected flow in the running app or browser, not just the test suite.
Never claim a verification that was not actually run.

## 5. Gate the ship

```sh
no-mistakes
```

Nontrivial code reaches the remote only through the no-mistakes pipeline: review, tests, lint, docs, push, PR, and CI as one gate.
If the gate fails, fix the finding; do not bypass the gate.

## 6. Close out

```sh
tasks-axi done <id> --pr <url>
```

Record the PR on the task, then sweep durable knowledge (preferences, gotchas, unfinished next steps) to disk with the `stow` skill before the session ends.

## When the toolchain misbehaves

```sh
ic-doctor
```

Read-only health check of the whole system; every FAIL line names the command that fixes it.
