---
name: python-testing
description: Writing, fixing, and gating Python tests with pytest, focused on numerical and data code - the RED gate for bug fixes, fixtures and parametrization, hypothesis property tests, float tolerances with numpy.testing and pandas.testing, golden-file regression tests for pipelines and backtests, determinism (seeds, time, ordering), and flake triage. Use when adding or repairing Python tests, testing numpy/pandas/polars or ML code, or proving a Python bug fix.
metadata:
  origin: Adapted from ECC skills/python-testing and the RED gate in skills/tdd-workflow (MIT, see ../THIRD_PARTY_NOTICES.md)
---

# Python testing

Test observable behavior through public functions.
Assert on values, shapes, dtypes, and raised errors, never on how the code is written.

## The RED gate

Before editing production code for a bug or new behavior:

1. Write the test and run exactly it: `pytest tests/test_fills.py::test_partial_fill_keeps_remaining_qty -x`.
2. Confirm it fails for the intended reason (the assertion or the expected exception), not an `ImportError`, fixture error, or typo.
3. Only then change production code, and rerun until GREEN; then run the neighbouring tests.

A test that was written but never run is not RED.
When the bug came from a real run (a backtest, a job, a notebook), reproduce it at that level first, then pin it with the smallest test that would have caught it.

## Running

```sh
pytest -x -q                         # stop at first failure
pytest -k "fills and not slow" -q    # select by expression
pytest --lf                          # rerun last failures
pytest -n auto                       # parallel (pytest-xdist)
pytest -p no:randomly                # disable random ordering to bisect an order dependence
pytest --durations=15                # find the slow tests
```

Configure once in `pyproject.toml`:

```toml
[tool.pytest.ini_options]
addopts = "-ra --strict-markers --strict-config"
testpaths = ["tests"]
markers = ["slow: long-running", "integration: touches real files or services"]
filterwarnings = ["error"]            # warnings (pandas FutureWarning, numpy casts) fail tests
xfail_strict = true
```

`filterwarnings = ["error"]` matters for data code: chained-assignment, dtype-downcast, and deprecation warnings are usually real bugs in waiting.

## Fixtures and parametrization

- Fixtures build inputs; keep them small, explicit, and local to the module unless shared by several.
- Use `tmp_path` for files, `monkeypatch` for env vars and attributes, never real home or repo paths.
- `@pytest.mark.parametrize` for edge-case tables, with `ids=` so failures read clearly.

```python
@pytest.mark.parametrize(
    ("bids", "asks", "expected_mid"),
    [
        ([100.0], [101.0], 100.5),
        ([], [101.0], None),            # one-sided book
        ([101.0], [100.0], None),       # crossed book is rejected
    ],
    ids=["normal", "one-sided", "crossed"],
)
def test_mid_price(bids, asks, expected_mid):
    assert mid_price(bids, asks) == expected_mid
```

- Mock at the boundary you own (a client wrapper), with `autospec=True` so signature drift fails the test; do not mock the code under test or pandas itself.

## Numerical assertions

Exact equality on floats is almost always wrong; derive the tolerance from the computation.

```python
import numpy as np
import pandas as pd
from numpy.testing import assert_allclose, assert_array_equal

assert_allclose(result, expected, rtol=1e-12, atol=0)          # well-conditioned math
assert_allclose(pnl, expected_pnl, rtol=0, atol=1e-8)          # sums near zero need atol
assert_array_equal(signal.astype(int), expected_signal)         # discrete outputs compare exactly

pd.testing.assert_frame_equal(got, want, check_dtype=True, check_exact=False, rtol=1e-10)
pd.testing.assert_series_equal(got, want, check_names=True, check_index_type=True)
```

- Always check dtype and index as well as values; a silent `float64` to `object` or a shifted index is the classic data bug.
- Assert NaN placement explicitly (`assert got.isna().sum() == 0`, or compare masks) instead of letting tolerance helpers treat NaN as equal by accident.
- For polars: `polars.testing.assert_frame_equal(got, want, check_dtypes=True)`.
- Money in integer ticks or `Decimal` compares exactly; if it is a float, the test should expose why.

## Property tests (hypothesis)

Use properties for invariants over large input spaces: resamplers, joins, rolling windows, position accounting, serialization round-trips.

```python
from hypothesis import given, settings, strategies as st
from hypothesis.extra.numpy import arrays

@given(arrays(np.float64, st.integers(1, 500), elements=st.floats(-1e6, 1e6)))
def test_cumsum_diff_roundtrip(x):
    assert_allclose(np.diff(np.cumsum(x), prepend=0.0), x, atol=1e-6 * max(1.0, np.abs(x).max()))

@given(st.lists(st.tuples(st.sampled_from(["buy", "sell"]), st.integers(1, 1000))))
def test_position_equals_signed_fill_sum(fills):
    book = PositionBook()
    for side, qty in fills:
        book.apply(side, qty)
    assert book.position == sum(q if s == "buy" else -q for s, q in fills)
```

- Compare against a slow, obviously correct reference implementation where one exists.
- Keep the failing example hypothesis prints; add it as an explicit `@example(...)` regression.
- Use `@settings(deadline=None)` only for genuinely slow properties, and mark them `slow`.

## Golden-file regression tests

For pipelines, feature builders, and backtests whose output is too rich to assert by hand:

- Run on a small committed fixture (a day of bars, a few thousand ticks) and compare to a golden output under `tests/data/golden/`.
- Store goldens in a diff-friendly, stable format (sorted CSV or parquet with a fixed schema), and compare with the tolerance helpers above, not byte equality, when floats are involved.
- Regenerate only via an explicit switch (`pytest --update-golden`, implemented in `conftest.py`), and review the golden diff like code.
- A golden change without an explanation in the PR is a red flag.

## Determinism

- Seed everything the test touches: `rng = np.random.default_rng(1234)` passed in, not global `np.random.seed`; `random.seed`, `torch.manual_seed` where relevant.
- Freeze time with an injected clock or `time-machine`, never `datetime.now()` inside logic under test.
- Timezones: construct test timestamps tz-aware (`pd.Timestamp("2026-03-09 13:30", tz="America/New_York")`) and include a DST-boundary case for anything calendar-driven.
- Ordering: do not depend on dict, set, or `groupby` output order unless the code sorts; `pytest-randomly` flushes out order dependence between tests.

## Flakiness

A flaky test is a broken test; find the cause instead of adding retries.
Usual causes: unseeded randomness, wall-clock time, shared temp files, test-order dependence, real network, tolerance tighter than the computation's error, or a race in threaded or async code (use `pytest-asyncio` with explicit event loops and bounded waits, never `sleep`).
