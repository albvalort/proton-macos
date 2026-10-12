# (c) Platform decision (oslist) and launching in the Mac client

Documentation only. Nothing was modified. Static analysis of the x86_64 slice of `steamclient.dylib`
(build 1788652215). Addresses are relative to that build and **will change** with every update.

Reproduce:

```sh
lipo .../steamclient.dylib -thin x86_64 -output sc_x64.dylib
otool -tV sc_x64.dylib > sc_x64.asm     # ~3 s, 5.6 M lines; annotates "literal pool for: ..."
grep -n 'literal pool for: "config/oslist"' sc_x64.asm
```

## 1. Reading oslist

| Address | What it does | Evidence |
|---|---|---|
| `0x551340` | Parses `config/oslist` of a launch entry (`V_isnumeric`, `V_strnicmp`, `V_atoi`). | literal `"config/oslist"` |
| `0x5513de` | `GetAppStateInfo`: compares the platform with the string `"macos"` (`0x5516d0`). | literals `"GetAppStateInfo"` and `"macos"` |
| `0x553384…` | `IsAppDlcInstalled`: `oslist` and `config/oslist` with `V_stristr`. | literals |
| `0x545d60`, `0x54a22b`, `0x54b334`, `0x551937` | Reads of `osarch`. | literal `"osarch"` |

Platform values present: `windows`, `macos`, `linux`, `macos64`, `arm64`.

## 2. Steam Play (CCompatManager) is compiled into the Mac client ⚠️

This is the most important finding for milestone 9. The build paths show that `clientdll/compatmanager.cpp`
is part of the Mac build:
`/opt/buildbot/buildworker/steam_rel_client_osx/build/src/clientdll/compatmanager.cpp`.

The binary contains all of Linux's Steam Play machinery:

- Tool discovery: `/compatibilitytools.d`, `/usr/share/steam/compatibilitytools.d`,
  `/usr/local/share/steam/compatibilitytools.d` (refs at `0x6500bd`–`0x65041d`), `/toolmanifest.vdf`,
  `commandline`, `commandline_waitforexitandrun`, `commandline_getcompatpath`, `require_tool_appid`,
  `%verb%`, `waitforexitandrun`.
- App → tool mapping: `Software\Valve\Steam\CompatToolMapping`, `CSpecifyAppCompatToolJob`,
  `m_mapAppPlatformOverride`, `m_mapAppInvalidPlatform`, `m_mapCompatEnabled`, `src_os`/`dest_os` fields.
- The environment tools receive: `STEAM_COMPAT_CLIENT_INSTALL_PATH`, `STEAM_COMPAT_DATA_PATH`,
  `STEAM_COMPAT_APP_ID`, `STEAM_COMPAT_TOOL_PATHS`, `STEAM_COMPAT_LIBRARY_PATHS`, `STEAM_COMPAT_SHADER_PATH`,
  `STEAM_COMPAT_INSTALL_PATH`, `STEAM_COMPAT_MOUNTS`, `STEAM_COMPAT_PROTON`.
- Global switch: `CCompatManager` keeps a `bool enabled` at `this+0x7b0`. There is a getter at `0x64561c` and a
  function that prints `"Disabling compatibility layer."` and sets it to 0 at `0x645628`, called from
  `0x55448a`.

**Hypothesis (medium-low confidence):** the manager exists on macOS but is not enabled, or receives no valid
tools for `dest_os=macos`. On this machine, `logs/` has no compat lines and
`~/Library/Application Support/Steam/compatibilitytools.d` does not exist.

**Proposed experiment, cheap and reversible**, without patching anything (before milestone 9):

1. Create `~/Library/Application Support/Steam/compatibilitytools.d/proton-macos-test/` with
   `compatibilitytool.vdf` (`from_oslist "windows"`, `to_oslist "macos"`), `toolmanifest.vdf` and a script
   that only records the arguments and environment it receives.
2. Start Steam with `-compat_log` (the `compat_log` string is in the binary) and check `logs/compat_log.txt`.
3. See whether the tool shows up in Properties → Compatibility of a Windows game.

If it works, **milestone 9 needs no hooks**: Steam would launch our `proton` as on Linux, with
`STEAM_COMPAT_*` and `SteamAppId`. That fits "so that Valve could adopt it" perfectly.

### 2.1 Result of the experiment (2026-10-11)

**The switch.** In the `CCompatManager` constructor (x86_64 GUI `0x642fa5`; arm64 steamcmd `0x6913a4`):

```
m_bEnabled (this+0x7b0) = V_strnicmp(ClientOSList(), "linux", INT_MAX) == 0
```

`ClientOSList()` (`0x54b526`) reads `"oslist"` from the client's configuration KeyValues. That value can be
overridden with the **`@sSteamCmdForcePlatformType`** ConVar (`windows|macos|linux|android`), and the bitness
with `@sSteamCmdForcePlatformBitness`.

**The ConVar arrives too late.** `CCompatManager` is constructed when the Steam API loads. `+cmd` commands
(including `+set_var`) run afterwards. Checked with a `DYLD_INSERT_LIBRARIES` shim
(`tools/re/strnicmp_spy.c`) on steamcmd: the constructor receives `"macos"` even when
`+@sSteamCmdForcePlatformType linux` is passed. In the GUI, `+@sSteamCmdForcePlatformType` gives
`command not found`; `set_var` exists.

**Forcing it at runtime** (steamcmd only, without touching files; `SPY_FORCE_OFFSET=0x6913b8`):
`compat_log.txt` is created and the manager works:

```
Processing local tool list at ~/.local/opt/steamcmd/compatibilitytools.d/proton_macos_probe/compatibilitytool.vdf...
Registering tool proton_macos_probe, AppID 0
Ignoring tool proton_macos_probe as it's for a different target platform linux.
```

Conclusions:

| Conclusion | Confidence |
|---|---|
| Steam Play is compiled and works on macOS; a single `bool` requiring `oslist == "linux"` turns it off. | High |
| Tools are searched in `<client root>/compatibilitytools.d` and filtered by `to_oslist` against the **real** platform (`macos`). A `from_oslist windows` / `to_oslist macos` tool is exactly the case the code handles. | High |
| It does not enable itself without changing behaviour: the ConVar is applied after the constructor. | High |
| Minimal integration: flip that single check (hook or *interpose* on a **re-signed client or steamcmd**). Much smaller and more robust than hooking the oslist check and the launch separately (original milestone 9 plan). For Valve, adopting it would be a one-line change. | Medium-high |
| `STEAM_COMPAT_TOOL_MAPPINGS` (environment variable, comma separated, parsed with `strtoul`/`strtol`) allows app→tool mapping without touching `config.vdf`. Exact format pending. | Medium |

### 2.2 End-to-end test with steamcmd (2026-10-11) ✅

Setup: `compatibilitytools.d/proton_macos_probe` with `from_oslist windows` / `to_oslist macos`, which only
records the arguments and environment it receives. Mapping in `config.vdf` → `CompatToolMapping/585690`
(Minimalism, Windows only). Check flipped with the shim (`SPY_FORCE_OFFSET=0x6913b8`).

1. **Registration.** `compat_log.txt`: `Registering tool proton_macos_probe` → `Mapping AppID 585690 to tool
   "proton_macos_probe" with priority 250` → `Command prefix ... set to: "'.../proton_macos_probe/.'/probe run "`.
2. **Installation.** `app_status` no longer shows `Invalid Platform`. `app_update 585690` downloads the
   **Windows** depot (`Minimalism.exe: PE32 executable (GUI) Intel 80386`) and the shared redistributable depots
   (228986 and 228990 of app 228980), just like Steam Play on Linux.
3. **Launch.** `app_run 585690` runs
   `'.../proton_macos_probe/.'/probe waitforexitandrun '<install>/Minimalism.exe'` with the game directory as
   cwd and this environment:

```
STEAM_COMPAT_APP_ID=585690
STEAM_COMPAT_CLIENT_INSTALL_PATH=<directory containing steamclient.dylib>
STEAM_COMPAT_DATA_PATH=~/Library/Application Support/Steam/steamapps/compatdata/585690
STEAM_COMPAT_INSTALL_PATH=<install dir>
STEAM_COMPAT_SHADER_PATH=.../shadercache/585690
STEAM_COMPAT_MOUNTS=.../common/Steamworks Shared
STEAM_COMPAT_PROTON=1
STEAM_COMPAT_LIBRARY_PATHS= / STEAM_COMPAT_TOOL_PATHS=   (empty)
STEAM_DYLD_INSERT_LIBRARIES=<client>/steamloader.dylib
SteamAppId=SteamGameId=SteamOverlayGameId=585690, SteamClientLaunch=1, SteamEnv=1
PROTON_CRASH_REPORT_DIR=/tmp/proton_crashreports
```

**It is the same contract as Proton on Linux.** `STEAM_COMPAT_CLIENT_INSTALL_PATH` is exactly what the
`__APPLE__` branch of `lsteamclient/unixlib.cpp` reads to load `steamclient.dylib`.

### 2.3 The GUI client

- `steam_osx` (the real client) **has no hardened runtime** (`codesign` shows `flags=0x0`). Only the
  `/Applications/Steam.app` bootstrapper has it (`flags=0x10000(runtime)`).
- The check is at the same arm64 offset (`steamclient.dylib+0x6913b8`, `cmp w0,#0` → `strb w8,[x19,#0x7b0]`).
- Tried on 2026-10-12: `DYLD_INSERT_LIBRARIES` is honoured if Steam is not started through a SIP-protected binary
  (`/usr/bin/nohup` strips it), but the GUI resolves `V_strnicmp` from a library loaded later with `dlopen`, so
  dyld interposing fails (`symbol not found in flat namespace '_V_strnicmp'`) and Steam quits. Not working yet.

### 2.4 End to end with our Proton (2026-10-11) ✅

`scripts/steamcmd.sh` (isolated HOME) + shim + `CompatToolMapping/585690 → proton_macos`:
`app_update 585690` downloads the Windows depot and `app_run 585690` runs
`proton_macos/proton waitforexitandrun <...>/Minimalism.exe`. Minimalism (PE32, D3D9 → wined3d → OpenGL) starts
fullscreen.

Findings:

- **Steam launches the tool as an x86_64 process** (Rosetta) when the game is x86. The `/usr/bin/python3` shim of
  the macOS 27 CLT needs `libxcrun`, which is arm64 only, and fails. That is why `package.sh` installs Proton's
  script as `proton.py` and `proton` is an `arch -arm64 /usr/bin/python3 proton.py` launcher (Wine still starts as
  x86_64).
- **steamcmd does not provide the IPC server for games** (`[S_API FAIL] ... ipcserver GetSteamPath failed`; in
  Proton, `steamclient_init_registry: Failed to connect to Steam`). Games launched by steamcmd work, but without
  the Steam API (achievements, overlay, etc.). The API does work with the GUI client running (milestone 5).
- steamcmd and the GUI client cannot share a data directory: each overwrites the other's session token
  (`config.vdf` → `ConnectCache`). `scripts/steamcmd.sh` uses its own HOME.
- `installscript_posix.cpp: Standalone evaluator returned error code`: installscripts (redistributables) run
  through the tool with `proton run`. To be reviewed.

### Consequences for the plan

- **Milestone 6.** The `proton` script must implement the contract above (`waitforexitandrun`, `run`,
  `getcompatpath`) and ship `compatibilitytool.vdf` with `to_oslist macos`.
- **Milestone 7.** With the tool registered, Steam itself downloads Windows depots (isolated steamcmd).
  DepotDownloader becomes only a plan B. For games to have the Steam API they must be launched with the GUI client
  running: `pmac run` calls `proton` directly, with Steam's variables, while the GUI serves the IPC; or, in
  milestone 9, the GUI itself launches the tool.
- **Milestone 9.** No hooks for the oslist check or the launch are needed, and no re-signed copy: flipping **one**
  boolean is enough. It shows that native support from Valve would be a one-line change
  (`oslist == linux` → `oslist in {linux, macos}`).
- **Fragility.** The offset depends on the build. The production version must find the pattern (`"linux"` +
  `V_strnicmp` + store at `+0x7b0`) and do nothing if it is not found.

## 3. Launching the process

- Imports of the x86_64 slice: `posix_spawn` and `posix_spawn_file_actions_addchdir_np`,
  `posix_spawnattr_setbinpref_np` (Steam picks the x86_64/arm64 slice when launching), plus `fork`, `execvp`,
  `system` and `popen`.
- Resolution of the launch entry: around `0x54fff1` (`"Failed running app %u (entry for launch option %u not
  found)"`), called from `CAPIJobLaunchApp`.
- Launches are logged in `logs/gameprocess_log.txt`.

| Conclusion | Confidence |
|---|---|
| Platform filtering is based on appinfo's `oslist`/`config/oslist` and `osarch`; the functions are located above. | Medium (located through string references, not decompiled) |
| CCompatManager (Steam Play) is compiled into the Mac client with `compatibilitytools.d` discovery. | High |
| That manager can be enabled on macOS without file patches. | High with steamcmd (section 2.2); not yet in the GUI client (section 2.3) |
| Steam launches games with `posix_spawn`, choosing the architecture. | Medium-high |
