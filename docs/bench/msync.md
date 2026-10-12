# msync: results

Machine: MacBook M2, macOS 27.0.1, x86_64 Wine under Rosetta 2. Date: 2026-10-11.
Tests: `tests/msync/synctest.c` (correctness + timings), `tests/msync/opcost.c` (cost per call),
`tests/msync/ulock_bench.c` and `ulock_xproc.c` (primitives). Medians of 3 runs unless stated otherwise.

## Cost per uncontended operation (`opcost.exe`)

| Operation | Server (`WINEFSYNC=0`) | msync |
|---|---|---|
| `SetEvent` + `ResetEvent` | 19.36 µs | 3.82 µs |
| `WaitForSingleObject(e, 0)` + `SetEvent` | 20.71 µs | 4.12 µs |

## `synctest.exe` (x86_64)

| Test | Server | msync spin=0 | msync spin=1000 | **msync spin=4000** | msync spin=16000 |
|---|---|---|---|---|---|
| Event ping-pong (µs/round trip) | 26.97 | 18.86 | 11.82 | **6.99** | 3.78 |
| WaitForMultiple *any*, 20k (ms) | 265 | 473 | 446 | **442** | 901 |
| WaitForMultiple *all*, 20k (ms) | 288 | 606 | 355 | **73** | 130 |
| 50 ms timeouts (ms) | 51 | 52 | 52 | **52** | 52 |
| Contended mutex, 4×5000 (ms) | 209 | 65 | 63 | **37** | 35 |
| Alertable APC (ms) | 34.5 | 37 | 37 | **40** | 40 |
| Cross-process ping-pong (µs/round trip) | 31.6 | 25.2 | 16.6 | **9.4** | 7.6 |

Every test passes in every mode, including the 32-bit executable (WoW64).

**Default: spin=4000.** 16000 improves latency a little more, but doubles the cost of WaitAny.

## Known limitation: free-running producer + WaitAny

In *WaitForMultiple any*, the producer thread does `SetEvent` + `SwitchToThread` without pausing. With msync,
each producer iteration costs about 20 µs (instead of about 2), because every `SetEvent` really wakes a
sleeping thread, and on XNU under Rosetta that wakeup also costs the waker. In server mode wineserver pays that
cost and the producer is paced by the round trip to the server. It is a synthetic pattern; the real impact
will be measured with games in milestone 8.

## Stability

`tests/msync/stress.sh 30` (64 and 32 bits in a loop) was stopped at the user's request before 30 minutes,
with no failure or hang recorded until then. Minimalism, Downwell, ANIMAL WELL and Lingo also ran with msync
enabled. **Pending:** a full 30-minute game session (milestone 4 criterion).
