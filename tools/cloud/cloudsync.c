/* cloudsync: list or download an app's Steam Cloud files through the Steam API.
 *
 * Runs inside the game's Wine prefix (SteamAppId set, steam_api64.dll next to it), so it
 * talks to the running Steam client through lsteamclient.
 *
 *   cloudsync.exe list
 *   cloudsync.exe get <outdir>     (writes each file to <outdir>\<cloud name>)
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef BOOL (__cdecl *init_fn)(void);
typedef void *(__cdecl *iface_fn)(void);
typedef int (__cdecl *count_fn)(void *);
typedef const char *(__cdecl *name_fn)(void *, int, int *);
typedef int (__cdecl *read_fn)(void *, const char *, void *, int);

static void make_dirs(char *path)
{
    for (char *p = path + 3; *p; p++)
    {
        if (*p != '\\' && *p != '/') continue;
        char c = *p;
        *p = 0;
        CreateDirectoryA(path, NULL);
        *p = c;
    }
}

int main(int argc, char **argv)
{
    /* Under Proton the console output is not always visible: allow logging to a file. */
    const char *log = getenv("CLOUDSYNC_LOG");
    if (log) { freopen(log, "w", stdout); freopen(log, "a", stderr); setvbuf(stdout, NULL, _IONBF, 0); }
    HMODULE api = LoadLibraryA("steam_api64.dll");
    if (!api) { fprintf(stderr, "cannot load steam_api64.dll\n"); return 1; }
    init_fn init = (init_fn)GetProcAddress(api, "SteamAPI_Init");
    iface_fn storage_fn = (iface_fn)GetProcAddress(api, "SteamAPI_SteamRemoteStorage_v016");
    count_fn count = (count_fn)GetProcAddress(api, "SteamAPI_ISteamRemoteStorage_GetFileCount");
    name_fn name = (name_fn)GetProcAddress(api, "SteamAPI_ISteamRemoteStorage_GetFileNameAndSize");
    read_fn fread_ = (read_fn)GetProcAddress(api, "SteamAPI_ISteamRemoteStorage_FileRead");
    if (!init || !storage_fn || !count || !name || !fread_) { fprintf(stderr, "missing exports\n"); return 1; }
    if (!init()) { fprintf(stderr, "SteamAPI_Init failed (is Steam running?)\n"); return 1; }

    void *storage = storage_fn();
    int n = count(storage);
    printf("%d cloud files\n", n);
    for (int i = 0; i < n; i++)
    {
        int size = 0;
        const char *file = name(storage, i, &size);
        printf("%8d  %s\n", size, file);
        if (argc < 3 || strcmp(argv[1], "get")) continue;

        char *buf = malloc(size ? size : 1);
        int got = fread_(storage, file, buf, size);
        char out[MAX_PATH];
        snprintf(out, sizeof(out), "%s\\%s", argv[2], file);
        for (char *p = out; *p; p++) if (*p == '/') *p = '\\';
        make_dirs(out);
        FILE *f = fopen(out, "wb");
        if (f && got == size) { fwrite(buf, 1, got, f); printf("          -> %s\n", out); }
        else fprintf(stderr, "          failed (%d of %d bytes)\n", got, size);
        if (f) fclose(f);
        free(buf);
    }
    return 0;
}
