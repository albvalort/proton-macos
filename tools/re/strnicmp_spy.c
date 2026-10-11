/* strnicmp_spy: DYLD_INSERT_LIBRARIES shim that logs V_strnicmp(x, "<needle>") calls.
 * Used to observe platform checks in Valve's steamclient without a debugger.
 * Needle comes from SPY_NEEDLE (default "linux"); log goes to stderr.
 * SPY_FORCE_OFFSET=0x... makes the call returning to steamclient.dylib+offset report a match (0),
 * which lets us flip a single platform check at runtime without touching any file on disk. */
#include <dlfcn.h>
#include <execinfo.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

int V_strnicmp(const char *a, const char *b, int n);

static int spy_strnicmp(const char *a, const char *b, int n)
{
    int ret = V_strnicmp(a, b, n);
    const char *force = getenv("SPY_FORCE_OFFSET");
    if (force)
    {
        Dl_info info;
        void *ra = __builtin_return_address(0);
        if (dladdr(ra, &info) && info.dli_fname && strstr(info.dli_fname, "steamclient.dylib")
            && (unsigned long)((char *)ra - (char *)info.dli_fbase) == strtoul(force, NULL, 16))
        {
            fprintf(stderr, "SPY forcing match at +%s (was %d, a=\"%s\")\n", force, ret, a ? a : "");
            ret = 0;
        }
    }
    const char *needle = getenv("SPY_NEEDLE");
    if (!needle) needle = "linux";
    if (b && !strcmp(b, needle))
    {
        void *frames[4];
        int count = backtrace(frames, 4);
        fprintf(stderr, "SPY V_strnicmp(\"%s\", \"%s\") = %d", a ? a : "(null)", b, ret);
        for (int i = 1; i < count; i++)
        {
            Dl_info info;
            if (dladdr(frames[i], &info) && info.dli_fname)
                fprintf(stderr, " <- %s+0x%lx", strrchr(info.dli_fname, '/') + 1,
                        (unsigned long)((char *)frames[i] - (char *)info.dli_fbase));
        }
        fputc('\n', stderr);
    }
    return ret;
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement, *original; } interposers[] = {
    { (const void *)spy_strnicmp, (const void *)V_strnicmp },
};
