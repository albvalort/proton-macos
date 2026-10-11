/* opcost — per-call cost of basic sync operations (no contention). */
#include <windows.h>
#include <stdio.h>

static LARGE_INTEGER freq;
static double now_us(void) { LARGE_INTEGER t; QueryPerformanceCounter(&t); return t.QuadPart * 1e6 / freq.QuadPart; }

int main(void)
{
    int n = 100000;
    QueryPerformanceFrequency(&freq);
    HANDLE e = CreateEventW(NULL, FALSE, FALSE, NULL);
    double t = now_us();
    for (int i = 0; i < n; i++) { SetEvent(e); ResetEvent(e); }
    printf("SetEvent+ResetEvent: %.2f us\n", (now_us() - t) / n);
    t = now_us();
    for (int i = 0; i < n; i++) SwitchToThread();
    printf("SwitchToThread:      %.2f us\n", (now_us() - t) / n);
    t = now_us();
    for (int i = 0; i < n; i++) Sleep(0);
    printf("Sleep(0):            %.2f us\n", (now_us() - t) / n);
    SetEvent(e);
    t = now_us();
    for (int i = 0; i < n; i++) { WaitForSingleObject(e, 0); SetEvent(e); }
    printf("Wait(0)+SetEvent:    %.2f us\n", (now_us() - t) / n);
    return 0;
}
