---
name: cpp-testing
description: Writing, fixing, and gating C++ tests with GoogleTest/GoogleMock and CTest, including the RED gate for bug fixes, sanitizer builds (ASan, UBSan, TSan) with their macOS limits, coverage with llvm-cov, property tests with RapidCheck, fuzzing with libFuzzer, and microbenchmarks with Google Benchmark. Use when adding or repairing C++ tests, diagnosing a flaky or failing C++ test, wiring sanitizers or coverage into CMake, or proving a C++ bug fix.
metadata:
  origin: Adapted from ECC skills/cpp-testing and the RED gate in skills/tdd-workflow (MIT, see ../THIRD_PARTY_NOTICES.md)
---

# C++ testing

Tests prove behavior through public interfaces.
A test that only compiles, or only asserts that code ran, proves nothing.

## The RED gate (bug fixes and new behavior)

Before touching production code, get a valid RED:

- Runtime RED: the test target compiles, the new test actually executes (check the test name appears in the run), and it fails for the intended reason.
- Compile-time RED: the new test newly references the missing or buggy API and the compile error is that intended signal, not an unrelated typo or missing dependency.

A test that was written but never compiled and run is not RED.
Then make the smallest change that turns it GREEN, then refactor with the suite green.
When the bug was reported end to end (a wrong fill, a crash on a real capture), reproduce it at that level first, then pin it with the smallest unit test that would have caught it.

## Layout and CMake

```cmake
cmake_minimum_required(VERSION 3.24)
project(example LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)
FetchContent_Declare(googletest
  URL https://github.com/google/googletest/archive/refs/tags/v1.17.0.tar.gz  # pin per repo policy
  DOWNLOAD_EXTRACT_TIMESTAMP ON)
FetchContent_MakeAvailable(googletest)

enable_testing()
add_executable(core_tests tests/unit/book_test.cpp)
target_link_libraries(core_tests PRIVATE core GTest::gmock_main)
include(GoogleTest)
gtest_discover_tests(core_tests DISCOVERY_MODE PRE_TEST PROPERTIES LABELS unit)
```

- `tests/unit` (fast, hermetic, labelled `unit`), `tests/integration` (real files, sockets on loopback, labelled `integration`), `tests/data` for fixtures and golden files.
- Link the library under test, never recompile production sources into the test binary, so tests exercise what ships.
- `DISCOVERY_MODE PRE_TEST` avoids running test binaries at build time, which breaks under sanitizers and cross builds.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug && cmake --build build -j
ctest --test-dir build -L unit --output-on-failure          # fast signal first
ctest --test-dir build --output-on-failure -j "$(sysctl -n hw.ncpu)"
./build/core_tests --gtest_filter='BookTest.*' --gtest_repeat=200 --gtest_shuffle   # flake hunt
```

## Writing tests

- `ASSERT_*` for preconditions whose failure makes the rest meaningless, `EXPECT_*` for independent checks.
- One behavior per test; the name states it: `TEST(OrderBook, CancelOfUnknownIdIsRejectedWithoutMutation)`.
- Fakes for stateful collaborators (an in-memory venue, a fake clock), mocks only to assert interactions (a message was sent exactly once).
- Inject time: take a clock interface or a `now` parameter; never read the wall clock in logic under test.
- Floating point: `EXPECT_NEAR` with a tolerance derived from the computation, or `EXPECT_DOUBLE_EQ` (4 ULPs) only when the result should be exact up to rounding; prices and quantities in fixed point compare exactly.
- Parameterize with `TEST_P`/`INSTANTIATE_TEST_SUITE_P` for tables of edge cases (empty book, one level, crossed book, max size, overflow boundary).
- Golden files for complex outputs (a replayed session's fills): store under `tests/data`, compare byte for byte, regenerate only through an explicit flag, and review the golden diff like code.

## Sanitizers

Run the suite under each sanitizer in CI; one build per sanitizer, since ASan and TSan cannot be combined.

```cmake
set(SANITIZER "" CACHE STRING "address;undefined | thread")
if(SANITIZER)
  add_compile_options(-fsanitize=${SANITIZER} -fno-omit-frame-pointer -fno-sanitize-recover=all)
  add_link_options(-fsanitize=${SANITIZER})
endif()
```

```sh
cmake -S . -B build-asan -DSANITIZER="address,undefined" && cmake --build build-asan -j && ctest --test-dir build-asan
cmake -S . -B build-tsan -DSANITIZER=thread && cmake --build build-tsan -j && ctest --test-dir build-tsan
```

- `-fno-sanitize-recover=all` makes UBSan findings fail the test instead of printing and continuing.
- macOS with Apple clang (verified on arm64): ASan, UBSan, and TSan work; MemorySanitizer is unsupported, and ASan's leak detection is unsupported (`detect_leaks is not supported on this platform`).
  Use Homebrew LLVM's clang or a Linux CI job for MSan and LSan, or `leaks --atExit -- ./build/core_tests` for leak checks on macOS.
- Every lock-free structure and every cross-thread handoff gets a TSan-run stress test with enough iterations to interleave (thousands, not ten).

## Coverage

Coverage finds untested code; it does not prove tested code is correct, so there is no percentage target, but every changed branch in logic should be exercised.

```sh
cmake -S . -B build-cov -DCMAKE_CXX_FLAGS="-fprofile-instr-generate -fcoverage-mapping" && cmake --build build-cov -j
LLVM_PROFILE_FILE="build-cov/%p.profraw" ctest --test-dir build-cov
xcrun llvm-profdata merge -sparse build-cov/*.profraw -o build-cov/all.profdata
xcrun llvm-cov report build-cov/core_tests -instr-profile=build-cov/all.profdata -ignore-filename-regex='(_deps|tests)/'
```

On Linux use the matching `llvm-profdata`/`llvm-cov` from the same LLVM as the compiler; a version mismatch produces unreadable profiles.

## Property tests and fuzzing

Use them for invariants over large input spaces: parsers, codecs, order-book operations, risk checks.

```cpp
#include <rapidcheck/gtest.h>

RC_GTEST_PROP(OrderBook, TotalQuantityIsConservedAcrossAddAndCancel, (std::vector<Op> ops)) {
  OrderBook book;
  Model model;                       // simple reference implementation
  for (const auto& op : ops) { apply(book, op); apply(model, op); }
  RC_ASSERT(book.total_qty() == model.total_qty());
}
```

```cpp
extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t* data, std::size_t size) {
  (void)decode_message({data, size});   // must never crash, hang, or trip a sanitizer
  return 0;
}
// clang++ -g -O1 -fsanitize=fuzzer,address,undefined fuzz_decode.cpp -o fuzz_decode
```

Apple clang does not ship libFuzzer; build fuzzers with Homebrew LLVM (`$(brew --prefix llvm)/bin/clang++`) or on Linux.
Commit every crashing input as a regression test.

## Microbenchmarks (Google Benchmark)

Benchmarks are tests of a performance claim; the measurement discipline lives in the `perf-loop` skill.

```cpp
#include <benchmark/benchmark.h>

static void BM_BookAdd(benchmark::State& state) {
  OrderBook book = make_book(static_cast<int>(state.range(0)));
  const auto orders = make_orders(1 << 16);
  std::size_t i = 0;
  for (auto _ : state) {
    benchmark::DoNotOptimize(book.add(orders[i++ & 0xFFFF]));
  }
  state.SetItemsProcessed(state.iterations());
}
BENCHMARK(BM_BookAdd)->Arg(10)->Arg(1000);
BENCHMARK_MAIN();
```

```sh
./build-rel/bench --benchmark_repetitions=20 --benchmark_min_warmup_time=0.5 \
  --benchmark_report_aggregates_only=true --benchmark_out=bench.json
```

- Build benchmarks in Release with the production flags; a Debug benchmark measures the wrong program.
- `DoNotOptimize` and `ClobberMemory` prevent the compiler deleting the work; check the disassembly when a result looks too good.
- Compare runs with `compare.py` from the benchmark repo (it applies a Mann-Whitney U test), not by eyeballing means.

## Flakiness

A flaky test is a broken test.
Usual causes and fixes:

- Sleeps as synchronization: replace with `std::latch`, `std::barrier`, condition variables with predicates, or a bounded poll on the real condition.
- Shared temp paths: unique directory per test (`testing::TempDir()` plus the test name), removed in `TearDown`.
- Wall clock, real network, test-order dependence: inject the clock, use loopback fakes, run with `--gtest_shuffle` in CI.
- Unseeded randomness: fixed seed, printed on failure (RapidCheck prints its seed and shrunk case; rerun with `RC_PARAMS="reproduce=..."`).
