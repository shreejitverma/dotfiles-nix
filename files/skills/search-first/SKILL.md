---
name: search-first
description: Research existing code, libraries, and tools before writing new code - repository search first, then package registries and well-known C++ and Python libraries, then GitHub - and decide Adopt, Extend, Compose, or Build with an explicit evaluation. Use before writing a new utility, parser, data structure, integration, or dependency, when asked to "add X" where X is a common problem, or when choosing between libraries.
metadata:
  origin: Adapted from ECC skills/search-first (MIT, see ../THIRD_PARTY_NOTICES.md)
---

# search-first

The best code is the code you did not have to write.
Before building, spend a few minutes proving nothing suitable already exists, and say what you searched.

## 0. Preflight: which channels are actually available

| Channel | Check | If unavailable |
|---|---|---|
| This repository | `rg --files`, targeted `rg` for the concept and its synonyms | Say only visible files were inspected. |
| Other local repos | `rg` across `~/github/*` for prior implementations | Skip and say so. |
| Package registries | `pip index versions <pkg>` / `uv pip`, `vcpkg search`, `conan search`, `brew info` | Fall back to docs and web; do not claim registry coverage. |
| GitHub | `gh search repos` / `gh search code` (or `gh-axi`) | Use web search; say so. |
| Skills | `ls ~/.agents/skills ~/.claude/skills` and the repo's `.claude/skills` | Say no local catalog was checked. |

Never report "nothing found" for a channel that was not searched.

## 1. Define the need

One paragraph: the functionality, the language and standard (C++20, Python 3.12), hard constraints (header-only, no exceptions, allocation-free, license, latency budget, platforms), and what "good enough" means.

## 2. Search in this order

1. The repository itself, including tests and scripts: the helper you need often exists under another name.
2. The standard library: C++ `<algorithm>`, `<ranges>`, `<charconv>`, `<chrono>`, `std::expected`, `std::span`, `std::format`; Python `itertools`, `functools`, `bisect`, `heapq`, `dataclasses`, `zoneinfo`, `statistics`.
3. Well-known libraries for the domain (below), then registries, then GitHub.

## 3. Starting points by domain

**C++**
- Core utilities: Abseil (containers, hashing, strings, time), Boost (container, intrusive, lockfree, multiprecision, asio), `fmt`.
- Parsing and serialization: `simdjson`, `glaze`, FlatBuffers, Cap'n Proto, SBE (Simple Binary Encoding) for market-data style wire formats.
- Concurrency and low latency: `folly` (MPMC queue, small containers), `moodycamel::ConcurrentQueue` and `ReaderWriterQueue`, `rigtorp/SPSCQueue`, Boost.Lockfree.
- Containers: `absl::flat_hash_map`, `ankerl::unordered_dense`, `boost::container::small_vector` and `static_vector`.
- Numerics: Eigen, xsimd or Highway for SIMD, Boost.Multiprecision.
- Testing and benchmarking: GoogleTest, Catch2, RapidCheck, Google Benchmark, nanobench.
- Python bindings: nanobind, pybind11.
- Package managers: vcpkg or Conan; follow whatever the repo already uses.

**Python**
- DataFrames and arrays: polars, pandas, numpy, pyarrow, duckdb for SQL over files.
- Speed: numba, Cython, or a nanobind extension, after vectorization.
- Stats and ML: scipy, statsmodels, scikit-learn, lightgbm, PyTorch.
- Validation and config: pydantic, pandera for DataFrame schemas.
- Time and calendars: `zoneinfo`, `exchange_calendars` or `pandas_market_calendars` for trading sessions.
- HTTP and async: httpx, anyio.
- Testing: pytest, hypothesis, time-machine.

## 4. Evaluate candidates

For the top two or three, record:

| Criterion | What to check |
|---|---|
| Fit | Does it do the actual job, including edge cases and constraints (no exceptions, allocation behavior, thread safety)? |
| Health | Recent releases, open issue triage, bus factor, used by serious projects. |
| License | Compatible with the repo (MIT, BSD, Apache-2.0 are easy; GPL and AGPL need a decision). |
| Cost | Transitive dependencies, compile time and binary size (C++), install weight (Python), ABI and build-system friction. |
| Performance | Measured on your workload if performance matters (see `perf-loop`), not taken from the README. |

## 5. Decide

| Signal | Decision |
|---|---|
| Exact fit, healthy, compatible license | Adopt: use it directly. |
| Good foundation, partial fit | Extend: a thin adapter owned by the repo. |
| Several small pieces cover it | Compose: combine two or three focused libraries. |
| Nothing fits the constraints | Build: write it, informed by what you found, and say why each candidate was rejected. |

State the decision and its downside in the PR ("adopted X; costs a new dependency and 2 s of compile time").

## Anti-patterns

- Writing a utility before searching the repository.
- Silent skipping: claiming nothing exists when a channel was never searched.
- A massive dependency for one small function.
- Wrapping a library so heavily that its benefits and documentation no longer apply.
- Trusting benchmark claims for latency-critical code without measuring on your own workload.
