/*
 * steamtest — minimal Windows program exercising the Steam bridge (milestone 5).
 *
 * It talks to lsteamclient.dll the way steam_api64.dll does (CreateInterface + vtables), so it
 * needs no Steamworks SDK download. With SteamAppId=480 (Spacewar) it:
 *   1. connects to the running Steam client and reports the logged-on user,
 *   2. reads the app id and persona name,
 *   3. requests stats, unlocks ACH_WIN_ONE_GAME and stores it (unless --no-unlock).
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -o steamtest.exe steamtest.c
 * Run:   SteamAppId=480 STEAM_COMPAT_CLIENT_INSTALL_PATH=<dir with steamclient.dylib> wine steamtest.exe
 *
 * Set STEAMTEST_LOG=<file> to also append the results to a file (useful when launched through
 * Proton's steam.exe, which has no console).
 *
 * x86_64 only: on Win64 every C++ virtual call is fn(this, args...), so plain C is enough.
 * Vtable indices come from Steamworks SDK 1.51 (SteamClient020, SteamUser021, SteamUtils010,
 * SteamFriends017, STEAMUSERSTATS_INTERFACE_VERSION012).
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>

typedef int HSteamPipe;
typedef int HSteamUser;

typedef struct
{
    HSteamUser m_hSteamUser;
    int m_iCallback;
    unsigned char *m_pubParam;
    int m_cubParam;
} CallbackMsg_t;

static FILE *log_file;

/* printf to stdout and, if STEAMTEST_LOG is set, to that file */
static void report(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    if (log_file)
    {
        va_start(args, fmt);
        vfprintf(log_file, fmt, args);
        va_end(args);
        fflush(log_file);
    }
}

#define VCALL(obj, idx, type) ((type)((*(void ***)(obj))[idx]))

typedef void *(*CreateInterface_fn)(const char *, int *);
typedef BOOL (*BGetCallback_fn)(HSteamPipe, CallbackMsg_t *, int *);
typedef void (*FreeLastCallback_fn)(HSteamPipe);

static BGetCallback_fn pBGetCallback;
static FreeLastCallback_fn pFreeLastCallback;

/* Pump callbacks until `wanted` arrives or timeout; returns its first byte-param pointer copy. */
static BOOL wait_callback(HSteamPipe pipe, int wanted, DWORD timeout_ms, unsigned char *out, int out_size)
{
    DWORD start = GetTickCount();
    while (GetTickCount() - start < timeout_ms)
    {
        CallbackMsg_t msg;
        int call;
        while (pBGetCallback(pipe, &msg, &call))
        {
            int id = msg.m_iCallback;
            if (id == wanted && out)
                memcpy(out, msg.m_pubParam, min(out_size, msg.m_cubParam));
            pFreeLastCallback(pipe);
            if (id == wanted) return TRUE;
        }
        Sleep(50);
    }
    return FALSE;
}

int main(int argc, char **argv)
{
    BOOL unlock = !(argc > 1 && !strcmp(argv[1], "--no-unlock"));
    const char *log_path = getenv("STEAMTEST_LOG");
    if (log_path) log_file = fopen(log_path, "a");
    HMODULE mod = LoadLibraryA("lsteamclient.dll");
    if (!mod) { report("FAIL: LoadLibrary(lsteamclient.dll) error %lu\n", GetLastError()); return 1; }

    CreateInterface_fn pCreateInterface = (CreateInterface_fn)GetProcAddress(mod, "CreateInterface");
    pBGetCallback = (BGetCallback_fn)GetProcAddress(mod, "Steam_BGetCallback");
    pFreeLastCallback = (FreeLastCallback_fn)GetProcAddress(mod, "Steam_FreeLastCallback");
    if (!pCreateInterface || !pBGetCallback || !pFreeLastCallback) { report("FAIL: missing exports\n"); return 1; }

    void *client = pCreateInterface("SteamClient020", NULL);
    if (!client) { report("FAIL: CreateInterface(SteamClient020) returned NULL\n"); return 1; }
    report("OK   ISteamClient020 = %p\n", client);

    HSteamPipe pipe = VCALL(client, 0, HSteamPipe (*)(void *))(client);
    if (!pipe) { report("FAIL: CreateSteamPipe (is Steam running?)\n"); return 1; }
    HSteamUser user = VCALL(client, 2, HSteamUser (*)(void *, HSteamPipe))(client, pipe);
    if (!user) { report("FAIL: ConnectToGlobalUser (is a user logged in?)\n"); return 1; }
    report("OK   pipe %d, user %d\n", pipe, user);

    void *steam_user = VCALL(client, 5, void *(*)(void *, HSteamUser, HSteamPipe, const char *))(client, user, pipe, "SteamUser021");
    void *utils = VCALL(client, 9, void *(*)(void *, HSteamPipe, const char *))(client, pipe, "SteamUtils010");
    void *friends = VCALL(client, 8, void *(*)(void *, HSteamUser, HSteamPipe, const char *))(client, user, pipe, "SteamFriends017");
    void *stats = VCALL(client, 13, void *(*)(void *, HSteamUser, HSteamPipe, const char *))(client, user, pipe, "STEAMUSERSTATS_INTERFACE_VERSION012");
    if (!steam_user || !utils || !friends || !stats) { report("FAIL: interfaces %p %p %p %p\n", steam_user, utils, friends, stats); return 1; }

    BOOL logged_on = VCALL(steam_user, 1, BOOL (*)(void *))(steam_user) & 0xff;
    unsigned int appid = VCALL(utils, 9, unsigned int (*)(void *))(utils);
    const char *persona = VCALL(friends, 0, const char *(*)(void *))(friends);
    report("OK   BLoggedOn=%d AppID=%u persona=\"%s\"\n", logged_on, appid, persona ? persona : "(null)");

    if (!unlock) return 0;

    /* UserStatsReceived_t = k_iSteamUserStatsCallbacks (1100) + 1, UserStatsStored_t = + 2 */
    BOOL req = VCALL(stats, 0, BOOL (*)(void *))(stats) & 0xff;
    if (!req || !wait_callback(pipe, 1101, 15000, NULL, 0)) { report("FAIL: RequestCurrentStats / UserStatsReceived\n"); return 1; }
    report("OK   stats received\n");

    BOOL achieved = FALSE;
    VCALL(stats, 6, BOOL (*)(void *, const char *, BOOL *))(stats, "ACH_WIN_ONE_GAME", &achieved);
    report("OK   ACH_WIN_ONE_GAME before: %d\n", achieved & 0xff);

    BOOL set = VCALL(stats, 7, BOOL (*)(void *, const char *))(stats, "ACH_WIN_ONE_GAME") & 0xff;
    BOOL store = VCALL(stats, 10, BOOL (*)(void *))(stats) & 0xff;
    BOOL stored = wait_callback(pipe, 1102, 15000, NULL, 0);
    achieved = FALSE;
    VCALL(stats, 6, BOOL (*)(void *, const char *, BOOL *))(stats, "ACH_WIN_ONE_GAME", &achieved);
    report("%s SetAchievement=%d StoreStats=%d UserStatsStored=%d after=%d\n",
           (set && store && stored && (achieved & 0xff)) ? "OK  " : "FAIL", set, store, stored, achieved & 0xff);
    return (set && store && stored) ? 0 : 1;
}
