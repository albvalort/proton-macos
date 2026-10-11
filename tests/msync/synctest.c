/*
 * synctest — correctness and speed checks for NT synchronization under Wine (milestone 4).
 * Run once with WINEFSYNC=0 (server-side sync) and once with WINEFSYNC=1 (msync) and compare.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -o synctest.exe synctest.c
 * Usage: synctest.exe [iterations-scale [test-name-substring]]
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static LARGE_INTEGER freq;
static int failures;

static double now_ms(void)
{
    LARGE_INTEGER t;
    QueryPerformanceCounter(&t);
    return t.QuadPart * 1000.0 / freq.QuadPart;
}

static void check(const char *name, BOOL ok, const char *detail)
{
    printf("%s %-28s %s\n", ok ? "PASS" : "FAIL", name, detail);
    if (!ok) failures++;
}

/* 1. ping-pong between two threads with auto-reset events */
static HANDLE ping, pong;
static int pp_iters;
static DWORD WINAPI pong_thread(void *arg)
{
    for (int i = 0; i < pp_iters; i++)
    {
        if (WaitForSingleObject(ping, 10000) != WAIT_OBJECT_0) return 1;
        SetEvent(pong);
    }
    return 0;
}

static void test_pingpong(int iters)
{
    char buf[128];
    pp_iters = iters;
    ping = CreateEventW(NULL, FALSE, FALSE, NULL);
    pong = CreateEventW(NULL, FALSE, FALSE, NULL);
    HANDLE t = CreateThread(NULL, 0, pong_thread, NULL, 0, NULL);
    double start = now_ms();
    BOOL ok = TRUE;
    for (int i = 0; i < iters && ok; i++)
    {
        SetEvent(ping);
        ok = WaitForSingleObject(pong, 10000) == WAIT_OBJECT_0;
    }
    double ms = now_ms() - start;
    WaitForSingleObject(t, INFINITE);
    sprintf(buf, "%d round trips, %.1f ms, %.2f us/rt", iters, ms, ms * 1000 / iters);
    check("event ping-pong", ok, buf);
    CloseHandle(t); CloseHandle(ping); CloseHandle(pong);
}

/* 2. WaitForMultipleObjects (any) while another thread signals a random event */
static HANDLE multi[3];
static volatile LONG multi_done;
static LONG signal_count;
static DWORD WINAPI multi_signaler(void *arg)
{
    unsigned seed = 1;
    while (!multi_done)
    {
        signal_count++;
        seed = seed * 1103515245 + 12345;
        SetEvent(multi[(seed >> 16) % 3]);
        SwitchToThread();
    }
    return 0;
}

static void test_wait_any(int iters)
{
    char buf[128];
    int counts[3] = {0};
    for (int i = 0; i < 3; i++) multi[i] = CreateEventW(NULL, FALSE, FALSE, NULL);
    multi_done = 0;
    signal_count = 0;
    HANDLE t = CreateThread(NULL, 0, multi_signaler, NULL, 0, NULL);
    double start = now_ms();
    BOOL ok = TRUE;
    for (int i = 0; i < iters && ok; i++)
    {
        DWORD r = WaitForMultipleObjects(3, multi, FALSE, 10000);
        ok = r < WAIT_OBJECT_0 + 3;
        if (ok) counts[r]++;
    }
    double ms = now_ms() - start;
    multi_done = 1;
    WaitForSingleObject(t, INFINITE);
    sprintf(buf, "%d waits, %.1f ms (%d/%d/%d), %ld SetEvent", iters, ms, counts[0], counts[1], counts[2], signal_count);
    check("WaitForMultiple (any)", ok && counts[0] && counts[1] && counts[2], buf);
    CloseHandle(t);
    for (int i = 0; i < 3; i++) CloseHandle(multi[i]);
}

/* 3. WaitForMultipleObjects (all) on two semaphores released by two threads */
static HANDLE sems[2];
static int all_iters;
static double releaser_done[2];
static DWORD WINAPI sem_releaser(void *arg)
{
    for (int i = 0; i < all_iters; i++) { ReleaseSemaphore(sems[(INT_PTR)arg], 1, NULL); if (!(i & 63)) Sleep(0); }
    releaser_done[(INT_PTR)arg] = now_ms();
    return 0;
}

static void test_wait_all(int iters)
{
    char buf[128];
    all_iters = iters;
    sems[0] = CreateSemaphoreW(NULL, 0, iters, NULL);
    sems[1] = CreateSemaphoreW(NULL, 0, iters, NULL);
    HANDLE t0 = CreateThread(NULL, 0, sem_releaser, (void *)0, 0, NULL);
    HANDLE t1 = CreateThread(NULL, 0, sem_releaser, (void *)1, 0, NULL);
    double start = now_ms();
    BOOL ok = TRUE;
    for (int i = 0; i < iters && ok; i++) ok = WaitForMultipleObjects(2, sems, TRUE, 10000) == WAIT_OBJECT_0;
    double ms = now_ms() - start;
    WaitForSingleObject(t0, INFINITE); WaitForSingleObject(t1, INFINITE);
    LONG prev0 = -1, prev1 = -1;
    ReleaseSemaphore(sems[0], 1, &prev0); ReleaseSemaphore(sems[1], 1, &prev1);
    sprintf(buf, "%d waits, %.1f ms, leftover %ld/%ld, releasers done at %.1f/%.1f ms", iters, ms, prev0, prev1,
            releaser_done[0] - start, releaser_done[1] - start);
    check("WaitForMultiple (all)", ok && prev0 == 0 && prev1 == 0, buf);
    CloseHandle(t0); CloseHandle(t1); CloseHandle(sems[0]); CloseHandle(sems[1]);
}

/* 4. timeouts */
static void test_timeout(void)
{
    char buf[128];
    HANDLE e = CreateEventW(NULL, TRUE, FALSE, NULL);
    double start = now_ms();
    DWORD r = WaitForSingleObject(e, 50);
    double ms = now_ms() - start;
    HANDLE two[2] = { e, CreateEventW(NULL, TRUE, FALSE, NULL) };
    double start2 = now_ms();
    DWORD r2 = WaitForMultipleObjects(2, two, FALSE, 50);
    double ms2 = now_ms() - start2;
    sprintf(buf, "single %.1f ms, multi %.1f ms (want ~50)", ms, ms2);
    check("timeouts", r == WAIT_TIMEOUT && r2 == WAIT_TIMEOUT && ms >= 45 && ms < 150 && ms2 >= 45 && ms2 < 150, buf);
    CloseHandle(e); CloseHandle(two[1]);
}

/* 5. mutex contention */
static HANDLE mutex;
static volatile LONG counter;
static int mutex_iters;
static DWORD WINAPI mutex_worker(void *arg)
{
    for (int i = 0; i < mutex_iters; i++)
    {
        if (WaitForSingleObject(mutex, 10000) != WAIT_OBJECT_0) return 1;
        LONG v = counter; counter = v + 1; /* non-atomic on purpose: the mutex must protect it */
        ReleaseMutex(mutex);
    }
    return 0;
}

static void test_mutex(int iters)
{
    char buf[128];
    HANDLE t[4];
    mutex_iters = iters;
    counter = 0;
    mutex = CreateMutexW(NULL, FALSE, NULL);
    double start = now_ms();
    for (int i = 0; i < 4; i++) t[i] = CreateThread(NULL, 0, mutex_worker, NULL, 0, NULL);
    WaitForMultipleObjects(4, t, TRUE, INFINITE);
    double ms = now_ms() - start;
    sprintf(buf, "4x%d, counter %ld, %.1f ms", iters, counter, ms);
    check("mutex contention", counter == 4L * iters, buf);
    for (int i = 0; i < 4; i++) CloseHandle(t[i]);
    CloseHandle(mutex);
}

/* 6. alertable wait + APC */
static volatile LONG apc_ran;
static void CALLBACK apc_func(ULONG_PTR arg) { apc_ran = 1; }
static DWORD WINAPI apc_queuer(void *arg)
{
    Sleep(30);
    QueueUserAPC(apc_func, (HANDLE)arg, 0);
    return 0;
}

static void test_apc(void)
{
    char buf[128];
    HANDLE self;
    DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &self, 0, FALSE, DUPLICATE_SAME_ACCESS);
    HANDLE e = CreateEventW(NULL, TRUE, FALSE, NULL);
    HANDLE t = CreateThread(NULL, 0, apc_queuer, self, 0, NULL);
    double start = now_ms();
    DWORD r = WaitForSingleObjectEx(e, 5000, TRUE);
    double ms = now_ms() - start;
    sprintf(buf, "ret %#lx after %.1f ms, apc_ran %ld", r, ms, apc_ran);
    check("alertable wait + APC", r == WAIT_IO_COMPLETION && apc_ran && ms < 1000, buf);
    WaitForSingleObject(t, INFINITE);
    CloseHandle(t); CloseHandle(e); CloseHandle(self);
}

/* 7. cross-process ping-pong through named events */
static void test_cross_process(const char *self_path, int iters)
{
    char buf[128], cmd[MAX_PATH + 64];
    HANDLE a = CreateEventA(NULL, FALSE, FALSE, "synctest_a");
    HANDLE b = CreateEventA(NULL, FALSE, FALSE, "synctest_b");
    STARTUPINFOA si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    sprintf(cmd, "\"%s\" --child %d", self_path, iters);
    if (!CreateProcessA(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
    {
        check("cross-process ping-pong", FALSE, "CreateProcess failed");
        return;
    }
    double start = now_ms();
    BOOL ok = TRUE;
    for (int i = 0; i < iters && ok; i++)
    {
        SetEvent(a);
        ok = WaitForSingleObject(b, 10000) == WAIT_OBJECT_0;
    }
    double ms = now_ms() - start;
    WaitForSingleObject(pi.hProcess, 10000);
    sprintf(buf, "%d round trips, %.1f ms, %.2f us/rt", iters, ms, ms * 1000 / iters);
    check("cross-process ping-pong", ok, buf);
    CloseHandle(pi.hProcess); CloseHandle(pi.hThread); CloseHandle(a); CloseHandle(b);
}

static int child_main(int iters)
{
    HANDLE a = OpenEventA(EVENT_ALL_ACCESS, FALSE, "synctest_a");
    HANDLE b = OpenEventA(EVENT_ALL_ACCESS, FALSE, "synctest_b");
    if (!a || !b) return 1;
    for (int i = 0; i < iters; i++)
    {
        if (WaitForSingleObject(a, 10000) != WAIT_OBJECT_0) return 1;
        SetEvent(b);
    }
    return 0;
}

int main(int argc, char **argv)
{
    QueryPerformanceFrequency(&freq);
    if (argc > 2 && !strcmp(argv[1], "--child")) return child_main(atoi(argv[2]));

    int scale = argc > 1 ? atoi(argv[1]) : 1;
    if (scale < 1) scale = 1;
    char self_path[MAX_PATH];
    GetModuleFileNameA(NULL, self_path, MAX_PATH);

    const char *only = argc > 2 ? argv[2] : "";
#define RUN(name, call) do { if (strstr(name, only)) { call; } } while (0)
    double start = now_ms();
    RUN("pingpong", test_pingpong(20000 * scale));
    RUN("waitany", test_wait_any(20000 * scale));
    RUN("waitall", test_wait_all(20000 * scale));
    RUN("timeout", test_timeout());
    RUN("mutex", test_mutex(5000 * scale));
    RUN("apc", test_apc());
    RUN("crossprocess", test_cross_process(self_path, 5000 * scale));
    printf("%s total %.1f ms\n", failures ? "FAILED" : "ALL PASSED", now_ms() - start);
    return failures;
}
