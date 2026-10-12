# ADR 0003: msync as an fsync backend on top of XNU ulocks

- Status: accepted
- Date: 2026-10-11

## Context

The plan (milestone 4) asked to port msync from [marzent/wine-msync](https://github.com/marzent/wine-msync)
(LGPL-2.1): Mach semaphores and a Mach message server inside wineserver. That patch (2024) assumes Wine's
old server model, where every object implements `signaled` and exposes its sync index. Applied on top of
Valve's Wine 11, 45 hunks fail in 22 files.

Wine 11 reorganised synchronisation: objects delegate to sync objects (`get_sync`), and Valve implements
**fsync as a backend of the `inproc_sync` layer**, the same one ntsync uses. fsync keeps all state in
shared memory and only needs three futex operations:

- wake every waiter on a word;
- wait on a word;
- wait on several words at once (`futex_waitv`).

## Decision

Implement msync as **fsync with emulated futexes** on top of `__ulock_wait2`/`__ulock_wake` (XNU, macOS 11+,
the same API libc and libdispatch use), in `UL_COMPARE_AND_WAIT_SHARED` mode, which works across processes.

- Wait on one word → `__ulock_wait2`.
- Wake → `__ulock_wake(ULF_WAKE_ALL)`, plus a shared epoch counter.
- Wait on several words → register in a control block (index 0 of the shared memory, which fsync never
  allocates), read the epoch, check the words and wait on the epoch. With sequentially consistent atomics
  no wakeup is lost. Spurious wakeups do not matter, because fsync always re-checks the objects.
- Bounded spinning before sleeping (`WINE_MSYNC_SPIN`, 4000 iterations by default): waking a thread blocked
  in the kernel costs several µs on Apple Silicon under Rosetta.
- Deadline already expired → check and return without entering the kernel (a ulock with a minimal timeout
  still arms a coalesced timer of tens of µs).
- Shared memory with `shm_open` and a single `ftruncate` to 64 MiB, because shm objects cannot be resized
  on macOS. Pages are only materialised when used.
- The server's `inproc_sync` is built on macOS in "fsync only" mode, without ntsync.

Activation: `WINEFSYNC=1`, which the `proton` script sets by default on macOS. It is disabled with
`PROTON_NO_MSYNC=1`, following the `PROTON_NO_FSYNC` pattern.

## Consequences

- About 150 lines in five files (`include/wine/darwin_futex.h`, `server/fsync.c`, `server/inproc_sync.c`,
  `dlls/ntdll/unix/fsync.c`, `include/Makefile.in`), compared to about 5000 in the original patch. The whole
  fsync object model, already proven by Valve, is reused as is.
- Depends on a private but stable XNU API (`__ulock_*`), which the system itself uses.
- Multi-waits wake every thread waiting on several words on any wakeup. That is correct but scales worse
  with many threads in multi-waits. If a game suffers from it, the next step is to split the epoch into
  per-address buckets.
- Difference from marzent's msync: there is no Mach message server. Waits never go through wineserver.
- Results and methodology in [docs/bench/msync.md](../bench/msync.md).
