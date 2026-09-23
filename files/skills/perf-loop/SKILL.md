---
name: perf-loop
description: Bounded, measured optimization loop for latency, throughput, memory, or cost - baseline and correctness gate first, one hypothesis per variant, noise-controlled repeated measurement, tail-latency (p50/p99/p99.9) reporting without coordinated omission, hot-path mapping, and a promotion gate. Includes the C++ and Python profiling toolbox for macOS and Linux. Use when asked to make something faster, compare implementations, investigate a latency regression or tail spike, benchmark a change, or tune a hot path such as a feed handler, order book, or strategy loop.
metadata:
  origin: Adapted from ECC skills/benchmark-optimization-loop and skills/latency-critical-systems (MIT, see ../THIRD_PARTY_NOTICES.md)
---

# perf-loop

"Make it faster" becomes a bounded experiment with a correctness gate, a baseline, and a written result.
The word "faster" never appears in a conclusion without the numbers and the command that produced them.

## 1. Frame it before touching code

Write these down, in the task or PR:

- Operation: exactly what is measured (one `on_market_data` call, one backtest day, one batch job).
- Metric: p50/p99/p99.9 latency, throughput, peak RSS, allocations per op, or cost per run.
  Latency work reports percentiles, never only a mean.
- Correctness gate: the tests, golden outputs, or replay diff that must stay identical.
- Baseline: the current number, measured the same way the variants will be.
- Budget: maximum variants, wall time, and blast radius.
- Expected bottleneck: a named hypothesis ("allocation in the book update", "GIL contention", "cache misses walking levels") that the profile will confirm or kill.

## 2. Map the hot path

Draw the path from event to effect and measure each segment separately, because the total hides where the time goes:

```text
NIC / feed -> decode -> book update -> signal -> risk check -> order encode -> gateway send
```

Instrument segment boundaries with a monotonic, low-overhead clock (`std::chrono::steady_clock`, `rdtsc`/`cntvct_el0` calibrated at startup, `time.perf_counter_ns`), record into a histogram (HdrHistogram or a preallocated bucket array), and dump off the hot path.

## 3. Profile, then hypothesize

| Question | macOS | Linux |
|---|---|---|
| Where does CPU time go? | `xctrace record --template 'Time Profiler' --launch -- ./bin`, or Instruments | `perf record -g --call-graph dwarf ./bin`, then `perf report` |
| Cache misses, IPC, branch misses | Instruments "CPU Counters" template | `perf stat -e cycles,instructions,cache-misses,branch-misses ./bin` |
| False sharing | Instruments counters plus padding experiments | `perf c2c record` then `perf c2c report` |
| Allocations | Instruments "Allocations", `MallocStackLogging=1` + `malloc_history` | `heaptrack ./bin`, or `valgrind --tool=massif` |
| Whole-command timing | `hyperfine --warmup 3 --runs 30 'cmd A' 'cmd B'` | same |
| Python CPU | `py-spy record -o prof.svg -- python run.py` (needs `sudo` on macOS) | same, no sudo with ptrace allowed |
| Python CPU + memory, line level | `scalene run.py` or `pyinstrument run.py` | same |
| Python allocations | `python -X tracemalloc` / `memray run run.py` | same |

Read the profile before writing a variant.
If the profile contradicts the hypothesis, the hypothesis was wrong; update it rather than optimizing what you guessed.

## 4. Control noise

A difference smaller than the run-to-run spread is not a result.

- Release build with production flags (`-O2`/`-O3`, same `-march`, LTO if production uses it); never benchmark Debug or with sanitizers.
- Warm up, then repeat: at least 20 repetitions for microbenchmarks, 10 for end-to-end runs, reported as median plus spread (IQR or min/max) or a confidence interval.
- Same input, same machine, same power state, nothing else heavy running.
- macOS cannot isolate cores or pin threads to a specific core; treat laptop numbers as directional, and take final latency numbers on the Linux target with `isolcpus`/`nohz_full`, `taskset -c`, the performance governor, and turbo either fixed or disabled.
- Interleave A and B runs (ABAB) rather than running all of A then all of B, so drift hits both.
- For Google Benchmark, compare with `compare.py` (Mann-Whitney U) instead of eyeballing means.

## 5. Measure tails honestly

- Coordinated omission: a closed-loop client that waits for each response before sending the next hides stalls.
  Drive latency tests at a fixed arrival rate (open loop) and record latency from the intended send time, or replay a captured feed at its original timestamps.
- Report p50, p99, p99.9, and max with the sample count; p99.9 needs well over 1,000 samples to mean anything, so size runs accordingly.
- Look at the latency over time, not just the histogram: periodic spikes point at GC, page faults, timers, logging flushes, or other tenants.

## 6. Variants: one hypothesis each

```text
variant      | hypothesis                        | command                          | p50    | p99    | correct | notes
baseline     | current                           | ./bench --benchmark_filter=Add   | 182 ns | 410 ns | yes     | 20 reps, IQR 6 ns
pool-alloc   | malloc on every add               | same, -DUSE_POOL                 | 121 ns | 190 ns | yes     | winner so far
soa-levels   | level walk misses cache           | same, -DLEVELS_SOA               | 118 ns | 185 ns | yes     | within noise of pool-alloc
flat-map     | node map chases pointers          | same, -DFLAT_MAP                 |  96 ns | 160 ns | no      | breaks FIFO priority test
```

- Change one variable per variant, so a win is attributable.
- Compare each candidate against the accepted winner, not only the previous run.
- A variant that fails the correctness gate is rejected however fast it is.
- Stop when gains fall within noise, the budget is spent, or you are changing more variables than you can explain.

## Optimization order

Most wins come from the top of this list:

1. Do less: remove work, round trips, copies, and redundant validation of already-validated data.
2. Algorithm and data structure (asymptotics, then constant factors).
3. Data layout: contiguous storage, struct-of-arrays for scans, hot/cold field split, no false sharing.
4. Allocation: preallocate, pool, reuse buffers; zero allocations in steady state on the hot path.
5. I/O and syscalls: batch, avoid per-message syscalls, move logging off the hot path.
6. Concurrency: fewer handoffs, SPSC queues between pinned threads, no locks held across I/O.
7. Only then micro-level work: branch layout, inlining, SIMD, compiler flags, PGO.

For Python specifically: vectorize with numpy/polars before anything else, then move the true hot loop to numba, Cython, or C++ via pybind11/nanobind, measuring each step.

## Promotion gate

A variant becomes the default only when:

- The correctness gate passes and any golden or replay diff is empty or explained.
- The improvement is repeated (a second, independent measurement run agrees) and exceeds the noise.
- Rollback is a revert or a flag.
- The PR states the command, machine, build flags, sample counts, and before/after percentiles.

Say "best measured variant under these conditions", never "optimal", unless the search space was exhaustive.

## Guardrails

- Never trade away validation, risk checks, or error handling for latency.
- Never report a laptop microbenchmark as production latency.
- Stale data served fast is a correctness bug; measure freshness (event age at decision time) alongside latency.
- Keep secrets and customer or venue payloads out of profiles, flame graphs, and benchmark artifacts.
