/* ulock_bench — cost of the ulock primitives used by msync (run as x86_64 under Rosetta). */
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <time.h>

#define UL_COMPARE_AND_WAIT_SHARED 3
#define UL_COMPARE_AND_WAIT 1
#define ULF_WAKE_ALL 0x00000100
#define ULF_NO_ERRNO 0x01000000
extern int __ulock_wake(uint32_t op, void *addr, uint64_t wake_value);
extern int __ulock_wait2(uint32_t op, void *addr, uint64_t value, uint64_t timeout_ns, uint64_t value2);

static double now(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec * 1e9 + ts.tv_nsec; }

int main(void)
{
    int n = 200000;
    int *shared = mmap(NULL, 65536, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANON, -1, 0);
    shared[0] = 0;
    double t = now();
    for (int i = 0; i < n; i++) __ulock_wake(UL_COMPARE_AND_WAIT_SHARED | ULF_WAKE_ALL | ULF_NO_ERRNO, shared, 0);
    printf("ulock_wake SHARED, no waiters: %.0f ns\n", (now() - t) / n);
    t = now();
    for (int i = 0; i < n; i++) __ulock_wake(UL_COMPARE_AND_WAIT | ULF_WAKE_ALL | ULF_NO_ERRNO, shared, 0);
    printf("ulock_wake private, no waiters: %.0f ns\n", (now() - t) / n);
    t = now();
    for (int i = 0; i < n; i++) __ulock_wait2(UL_COMPARE_AND_WAIT_SHARED | ULF_NO_ERRNO, shared, 1, 0, 0);
    printf("ulock_wait2 SHARED, value differs: %.0f ns\n", (now() - t) / n);
    t = now();
    for (int i = 0; i < n; i++) __atomic_add_fetch(&shared[1], 1, __ATOMIC_SEQ_CST);
    printf("atomic add: %.1f ns\n", (now() - t) / n);
    return 0;
}
