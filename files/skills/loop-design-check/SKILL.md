---
name: loop-design-check
description: Design or review a goal-oriented agent loop (write-test-fix, overnight gnhf runs, nightly green-keepers, scheduled maintainers, plan-build-judge pipelines) so it neither spins burning tokens, games its own verifier, nor runs a wrong answer to completion. Covers the build-or-not gate, machine-decidable goals with boundaries, reconciliation over assertion, loop type, skeleton, damping, and a five-failure-mode review. Use when about to hand a repeating task to an autonomous agent, or when an existing loop might spin, cheat, or drift.
metadata:
  origin: Adapted from ECC skills/loop-design-check (MIT, see ../THIRD_PARTY_NOTICES.md)
---

# loop-design-check

A model has no built-in steering toward a goal across turns; a loop wrapped around it supplies that feedback.
This skill covers the judgment layer of a loop (is the goal right, will it run away), not the plumbing.

## Two levels of feedback

| Level | Owner | Role |
|---|---|---|
| Execution | The agent | Measures distance from the literal goal and drives it to zero. |
| Judgment | The human | Decides whether the goal is right, should change, or should stop. |

A thermostat can drive toward 26 degrees; it cannot decide that today the right target is 28.
Handing the judgment level to the loop removes the only feedback that questions the goal.

## Action 1: write a loop

### Step 0: should it exist at all

All four must hold, or do the task another way:

1. The task repeats (weekly or more often).
2. Verification can be automated.
3. The token and quota budget can carry it (check `quota-axi`; a long run can drain a window).
4. The agent has tools that actually run the work and observe the result.

A repository that deserves a loop already has a reconciliation baseline (golden outputs, an upstream total), tests, and a lint guard.
A loop in a repository without them amplifies its errors.

### Step 1: a machine-decidable goal

The loop lives or dies on its exit check being answerable yes or no by a program.

- Undecidable: "make it good", "clean up the pipeline".
- Decidable: "all 96 tests pass, no test file deleted or weakened, and a change list is produced".

Five properties of a good goal:

1. The done criterion is machine-verifiable.
2. Boundaries are stated with it: what the loop must not do (delete or skip tests, loosen assertions, edit lint or gate config, widen tolerances).
   Missing boundaries are a license to game the check.
3. A failure fallback: a retry cap, then escalation to a human.
4. Layered: small verifiable sub-goals rather than one large leap.
5. Reconciliation over assertion: anchor "done" to an external fact (a golden output, a vendor total, a replayed backtest matching to the tick) before your own asserts.
   "Tests pass" can be gamed; "diff against the reference is empty" cannot.

Self-check: could someone outside the domain run one command and tell whether it is done?
If not, the goal is not decidable yet.

### Step 2: loop type

| Task | Type | Stops when |
|---|---|---|
| Clear finish line (implement to spec, process a batch) | Servo (closed loop to a goal) | The goal check passes, or the retry cap hits. |
| No endpoint, maintain a state (health check, data freshness) | Regulator (thermostat) | Never; acts only on change, with a dead band against noise. |
| Watch until a condition (PR until CI is green) | Regulator with exit | The exit condition holds. |
| Must happen on time | Either of the above, wrapped in a scheduler (cron, `/loop`, a scheduled job) | Per the wrapped type. |

### Step 3: skeleton

**Maintenance work: document-driven dispatch.**
The loop reads a document (the queue and state machine) on a schedule and acts only when it changed.
The problem column is human-written, the result column loop-written, state only moves forward, the exit code of the check is final, and the loop advances items only to "awaiting verification": a human flips "done".

**Greenfield work: plan, build, judge.**

| Role | Does | Rule |
|---|---|---|
| Plan | Writes the spec and decidable acceptance checks | Acceptance must be runnable. |
| Build | Implements to the spec | Must not edit the acceptance checks. |
| Judge | Runs acceptance independently; fail returns the reason to Build | Independent of Build, and deterministic (tests, reconciliation diff, type check), never "looks right". |

In this toolchain the natural judge is the `no-mistakes` gate or CI, never the building agent itself.
Three failed rounds escalate to a human.

### Step 4: damping

Retry caps, hard wall-clock and token limits, and a human on the last switch.
Negative feedback without damping oscillates: the loop that keeps "fixing" the same thing.

### Step 5: land it in stages

1. Run it once by hand, which forces you to state exactly how the judge decides.
2. Harden it into a skill, a firstmate brief, or subagents (plan, build, judge as separate agents).
3. Only then schedule it unattended.

## Action 2: review a loop

Any hit sends the loop back.

| # | Failure mode | Review question | Antidote |
|---|---|---|---|
| 1 | The goal is a correct platitude, so it spins and burns quota | Can the exit be judged yes or no by a machine? | Replace with a decidable result condition. |
| 2 | Verification is "check it looks fine", so the agent declares victory | Is the judge the builder itself, or based on appearance? | Reconciliation, exit codes, an independent judge. |
| 3 | Only "all tests pass" gates it, so the agent deletes or weakens tests | Is there a boundary as well as a done criterion? | Done criterion plus explicit boundaries. |
| 4 | It relies on the agent asking mid-run, which it will not | Is any clarification deferred to runtime? | Front-load every clarification before launch. |
| 5 | Stale or bloated instructions and memory, so faster loops err faster | Are the docs it reads current, and who maintains them? | Layered memory, `stow` curation, periodic cleanup. |

Three red lines; violating any means the loop may not run unattended:

- Judgment stays with the human: the loop never flips "done", merges, or publishes on its own authority.
- Responsibility does not transfer: anything whose failure you cannot afford (merging, releasing, moving money, touching production) needs a human approval gate before the action.
- The more a loop rewrites its own rules or prompts, the stricter the review it needs, and that review must sit before the action, not after.

## Worked example: a nightly green-keeper

Naive goal "make all tests pass" fails failure mode 3.
Decidable goal: "all tests green, no test deleted, skipped, or loosened, lint and gate configs untouched, coverage not lowered, change list produced".
Type: servo with a retry cap of 3.
Skeleton: plan, build, judge, with CI as the independent judge.
Review catches: mode 3 (the boundary blocks deleting tests; the `guard` hook also denies unattended edits to lint and gate configs), mode 2 (CI judges, not the fixer), mode 4 (ambiguous fixes are left for the human, not guessed at 2 a.m.), and the red line (it opens a PR through `no-mistakes`; a human merges).

The naive and reviewed loops differ by four lines of constraints, which is the difference between waking up to a deleted test suite and waking up to a clean PR.

Lineage: Wiener's two-level feedback (*The Human Use of Human Beings*, 1950), and the plan, build, judge pattern from the loop-engineering literature, via ECC.
