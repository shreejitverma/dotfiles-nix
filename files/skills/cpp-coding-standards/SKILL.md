---
name: cpp-coding-standards
description: Modern C++ (17/20/23) standards for writing, reviewing, or refactoring C++, built on the C++ Core Guidelines with explicit overrides for latency-critical hot paths (allocation-free loops, noexcept, cache layout, lock-free SPSC, CRTP over virtual). Use when writing or reviewing any C++ code, deciding ownership or error-handling strategy, or when a hot path, market-data handler, order path, or other low-latency component is involved.
metadata:
  origin: Adapted from ECC skills/cpp-coding-standards and agents/cpp-reviewer.md (MIT, see ../THIRD_PARTY_NOTICES.md)
---

# C++ coding standards

Two regimes, one codebase.
Cold code (setup, config, tooling, tests, control plane) follows the C++ Core Guidelines as written.
Hot code (the per-message, per-tick, per-order path whose latency is the product) follows the same guidelines plus the overrides in "Hot-path overrides", which win where they conflict.
Mark the boundary in the code, for example with a `// HOT PATH` comment on the entry point or a `hot/` directory, so reviewers know which regime applies.

## Core principles (cite rule IDs in reviews)

| Theme | Rules | What it means in practice |
|---|---|---|
| RAII everywhere | P.8, R.1, E.6, CP.20 | Every resource (memory, fd, socket, lock, mapping) is owned by an object whose destructor releases it. |
| Make illegal states unrepresentable | P.4, I.4, Enum.3 | Strong types for units and ids (`Price`, `Qty`, `OrderId`), `enum class`, `std::variant` for closed sets. |
| Immutable by default | P.10, Con.1-5, ES.25 | `const`/`constexpr` first; mutability is the documented exception. |
| Compile time over run time | P.5, Per.11, F.4 | `static_assert`, `constexpr` tables, concepts instead of runtime checks. |
| Value semantics | C.10, R.5, F.20 | Return by value, scoped objects, no heap unless lifetime demands it. |
| Measure before optimizing | Per.1, Per.2, Per.6 | Performance claims need a benchmark; see the `perf-loop` skill. |

## Interfaces and functions

- I.4 / I.11: strongly typed interfaces; never transfer ownership through a raw pointer or reference.
- F.16: pass cheap types (at most two or three words, trivially copyable) by value, others by `const&`; take sink parameters by value and move.
- F.20 / F.21: return values, not out-parameters; return a struct for multiple results.
- F.6: mark functions that cannot throw `noexcept`, and always move constructors, move assignment, `swap`, and destructors.
- F.43: never return a pointer or reference to a local.
- Use `[[nodiscard]]` on every function whose result carries an error or ownership (`std::expected`, status codes, handles, `try_*`).
- `std::span<const T>` for read-only contiguous input, `std::string_view` for read-only text; neither may outlive its source (see Lifetime).

```cpp
struct Price { std::int64_t ticks; };            // fixed-point, never double for money
struct Qty   { std::int64_t lots;  };

[[nodiscard]] std::expected<Order, RejectReason>
validate(const NewOrder& req, const RiskLimits& limits) noexcept;
```

## Classes and ownership

- C.20 / C.21: Rule of Zero by default; if you declare any of destructor, copy, or move, declare or `=delete` all five.
- C.35: base destructor public virtual or protected non-virtual.
- C.46: single-argument constructors `explicit`.
- C.128: exactly one of `virtual`, `override`, `final`.
- C.41: constructors establish the invariant or throw; no two-phase `init()` in cold code.
- R.20 / R.21: `std::unique_ptr` for owning pointers; `std::shared_ptr` only for genuinely shared, non-hot lifetimes, created with `std::make_shared`.
- R.3: a raw `T*` or `T&` is always non-owning.

## Error handling

Decide the strategy per component and write it down (E.1):

| Component | Strategy |
|---|---|
| Cold code, construction, config, I/O setup | Exceptions (E.2), custom types (E.14), throw by value, catch by `const&` (E.15). |
| Hot path | No exceptions thrown; `std::expected<T, E>` or error enums with `[[nodiscard]]`; `noexcept` entry points. |
| Process-fatal invariant breaks | Fail fast: log, flush, `std::abort()`; do not limp on with corrupt state. |

Never swallow an error: no empty `catch`, no ignored return codes, no `errno` read without checking the call failed first.
Destructors, deallocation, and `swap` never fail (E.16).

## Lifetime and undefined behavior

These are review blockers regardless of regime:

- Dangling views: `string_view`/`span` into a temporary, a lambda capturing a local by reference that outlives the scope (F.53), returning a view into a member of a temporary.
- Iterator and reference invalidation: holding `&vec[i]` or an iterator across `push_back`, `insert`, `erase`, or `rehash`.
- Signed overflow, shift past width, uninitialized reads (ES.20), strict-aliasing violations; use `std::bit_cast` or `std::memcpy` for type punning, never `reinterpret_cast` through an unrelated type.
- Narrowing and mixed signed/unsigned arithmetic (ES.46, ES.100); price times quantity must be computed in a type that cannot overflow, with the bound checked or proven.
- Data races are UB (CP.2): every shared mutable object is guarded by a mutex or is an atomic with a stated memory order.
- `std::move` then use of the moved-from object other than assignment or destruction.

## Concurrency

- CP.20 / CP.44: RAII locks only, always named; `std::scoped_lock` for several mutexes (CP.21).
- CP.22: never call unknown code (callbacks, virtuals, logging that can block) while holding a lock.
- CP.42: condition-variable waits always take a predicate.
- CP.8: `volatile` is not synchronization.
- CP.26: no detached threads; use `std::jthread` and a stop token.
- Atomics: default to `seq_cst`; relax to `acquire`/`release` only with a comment naming the happens-before edge it relies on; `relaxed` only for counters nobody synchronizes on.

## Hot-path overrides

These override the Core Guidelines inside the hot regime.
Each one is a measured-latency decision, so a reviewer may ask for the benchmark that justifies it.

| Guideline default | Hot-path rule | Why |
|---|---|---|
| R.11 / R.20 smart pointers anywhere | No heap allocation in steady state: preallocate at startup, use pools, arenas, `std::pmr` with a monotonic buffer, or fixed-capacity containers. | `malloc` has unbounded tail latency and takes locks. |
| E.2 exceptions for errors | No throw on the hot path; `noexcept` entry points; build hot translation units so an accidental throw is visible (review `-fno-exceptions` feasibility per target). | Unwind tables and throw cost are unpredictable. |
| Type erasure is fine | No `std::function`, no `std::shared_ptr`, no virtual dispatch per message; use templates, CRTP, or `std::variant` + `std::visit` over a closed set. | Indirect calls defeat inlining and branch prediction; `shared_ptr` copies are atomic RMWs. |
| CP.100 avoid lock-free | Bounded SPSC ring buffers (and well-known MPSC designs) are allowed and preferred over mutexes between pinned threads, with explicit memory orders and a test under TSan. | A contended mutex costs a syscall and a context switch. |
| SL.con.2 `std::vector` default | Still contiguous, but capacity is reserved up front and never grows in steady state; `std::array`, `boost::container::static_vector`, or C++26 `std::inplace_vector` when the bound is known. | Growth reallocates and copies. |
| Logging freely | No synchronous I/O, formatting, or `std::string` building on the hot path; log by pushing a POD record to a queue drained off-thread. | I/O and formatting dominate microsecond budgets. |
| Per.19 access memory predictably | Design the data layout first: struct-of-arrays for scans, separate data written by different threads onto their own cache lines, hot fields first, cold fields split out. | False sharing and cache misses are the usual real bottleneck. |

Cache-line padding is platform specific, so name it once per target instead of hard-coding 64:
Apple Silicon reports `hw.cachelinesize: 128` and Apple clang's libc++ sets `std::hardware_destructive_interference_size` to 256, while x86-64 lines are 64 bytes with adjacent-line prefetch making 128 the safe padding.
Define `inline constexpr std::size_t kFalseSharingPad = ...;` per target (checked with `sysctl hw.cachelinesize` or `getconf LEVEL1_DCACHE_LINESIZE`) and use `alignas(kFalseSharingPad)`; note that the standard constant can differ between compilers, so it must never appear in an ABI or wire format.
| Branch freely | Keep the common case straight-line; `[[likely]]`/`[[unlikely]]` only where a profile shows mispredicts. | Annotations without a profile are guesses. |

Also on the hot path: no `std::map`/`std::unordered_map` with node allocation in steady state (use flat or open-addressing maps sized at startup), no `std::endl`, no `dynamic_cast`, no RTTI-dependent code, and no floating point for prices or quantities.

## Templates and generic code

- T.10 / T.11: constrain every template with a concept, standard ones first.
- T.120: `constexpr` functions before template metaprogramming.
- T.144: overload instead of specializing function templates.
- T.43: `using`, never `typedef`.

## Source files and naming

- SF.7: no `using namespace` at global scope in a header.
- SF.8 / SF.11: include guards or `#pragma once`; every header compiles on its own.
- Naming follows the repository's existing convention and its `.clang-format`; when there is none, pick one consistent style and let `clang-format` own layout.
- NL.9: ALL_CAPS only for macros.

## Tooling

Run these before calling C++ work done; wire the ones a repo lacks into its build rather than running them ad hoc.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DCMAKE_CXX_FLAGS="-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion -Werror"
cmake --build build -j
run-clang-tidy -p build          # checks come from the repo's .clang-tidy, never '*'
cppcheck --project=build/compile_commands.json --enable=warning,performance,portability
```

A sensible `.clang-tidy` baseline when a repo has none: `bugprone-*`, `cert-*`, `concurrency-*`, `cppcoreguidelines-*`, `modernize-*`, `performance-*`, `readability-*`, minus `modernize-use-trailing-return-type`, `readability-magic-numbers`, and `cppcoreguidelines-avoid-magic-numbers`.
Sanitizer and test flags live in the `cpp-testing` skill.

## Review checklist

Severity is what a reviewer reports; block on CRITICAL and HIGH.

**CRITICAL**
- Any item under "Lifetime and undefined behavior".
- Owning raw pointer, manual `new`/`delete` outside an allocator or pool implementation, leaked resource.
- Unbounded write: C array without bounds, `strcpy`, `sprintf`, `memcpy` with an unchecked length.
- Command or format-string injection (`system`, `popen`, user text as a `printf` format).
- Ignored error: discarded `[[nodiscard]]` result, empty `catch`, unchecked syscall return.

**HIGH**
- Data race, inconsistent lock order, lock held across unknown code, `volatile` used as sync.
- Rule-of-five violation, missing virtual destructor on a polymorphic base.
- Hot-path override violated: allocation, throw, `std::function`, `shared_ptr` copy, virtual call, or blocking I/O per message.
- Missing `noexcept` on move operations (silently disables moves in containers).

**MEDIUM**
- Needless copies (large by-value parameters, missing `std::move` on sinks, missing `reserve`).
- Missing `const` on members, parameters, or locals that never change.
- Unconstrained template, `typedef`, plain `enum`, magic numbers, narrowing that is provably safe but unannotated.

**Approve** only with zero CRITICAL and zero HIGH findings, and state which regime (cold or hot) you reviewed against.
