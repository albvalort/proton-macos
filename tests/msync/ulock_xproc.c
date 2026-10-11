/* ulock_xproc — checks that __ulock_wait2/__ulock_wake (UL_COMPARE_AND_WAIT_SHARED) work across
 * processes on a MAP_SHARED file mapping, which is what the msync backend relies on.
 * Build: clang -arch x86_64 -o ulock_xproc ulock_xproc.c   (run under Rosetta too) */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define UL_COMPARE_AND_WAIT_SHARED 3
#define ULF_WAKE_ALL 0x00000100
#define ULF_NO_ERRNO 0x01000000
extern int __ulock_wait2(uint32_t op, void *addr, uint64_t value, uint64_t timeout_ns, uint64_t value2);
extern int __ulock_wake(uint32_t op, void *addr, uint64_t wake_value);

static double now(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(void)
{
    char path[] = "/tmp/ulock-xproc-XXXXXX";
    int fd = mkstemp(path);
    ftruncate(fd, 4096);
    volatile uint32_t *word = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    unlink(path);
    *word = 0;

    pid_t pid = fork();
    if (!pid)
    {
        /* child: wait until the parent flips the word (5 s timeout) */
        double t = now();
        (void)*word; /* fault the shared page in: the SHARED lookup does not fault (EFAULT otherwise) */
        int ret = __ulock_wait2(UL_COMPARE_AND_WAIT_SHARED | ULF_NO_ERRNO, (void *)word, 0, 5000000000ull, 0);
        printf("child: ulock_wait2 ret=%d value=%u after %.1f ms\n", ret, *word, (now() - t) * 1000);
        fflush(stdout);
        _exit(*word == 1 && now() - t < 4 ? 0 : 1);
    }
    usleep(200000);
    *word = 1;
    int woken = __ulock_wake(UL_COMPARE_AND_WAIT_SHARED | ULF_WAKE_ALL | ULF_NO_ERRNO, (void *)word, 0);
    int status;
    waitpid(pid, &status, 0);

    /* timeout path */
    double t = now();
    int ret = __ulock_wait2(UL_COMPARE_AND_WAIT_SHARED | ULF_NO_ERRNO, (void *)word, 1, 50000000ull, 0);
    printf("parent: wake ret=%d; timeout wait ret=%d (%s) after %.1f ms\n", woken, ret,
           ret == -ETIMEDOUT ? "ETIMEDOUT" : "?", (now() - t) * 1000);

    int ok = WIFEXITED(status) && WEXITSTATUS(status) == 0 && ret == -ETIMEDOUT;
    printf("%s\n", ok ? "PASS" : "FAIL");
    return !ok;
}
