# Milestone 0: conclusions

Date: 2026-10-11. Machine: M2, macOS 27.0.1. Steam for Mac 6.1, build 1788652215.
Reference Proton: `proton-11.0-2`.

## Summary

| # | Question | Answer | Confidence | Detail |
|---|---|---|---|---|
| a | Does `steamclient.dylib` have an x86_64 slice? | **Yes.** It is universal (`x86_64 arm64`), like `libtier0_s`, `libvstdlib_s` and `libaudio`. The bridge can load it in-process; **no helper process with IPC is needed**. | High | [01](01-steamclient-arch.md) |
| b | Interfaces in the dylib versus lsteamclient? | Every interface games ask for is there (`SteamClient006–023`). **2 exports are missing** that Proton loads as mandatory: `Steam_IsKnownInterface` and `Steam_NotifyMissingInterface`. A small patch solves it. The ABI is the same as on Linux (`pack(4)` through `__APPLE__`, SysV). Proton **already has** the `#ifdef __APPLE__` path to load the dylib. | High | [02](02-interfaces.md) |
| c | Where is it decided whether a game is playable, and how is it launched? | Based on appinfo's `oslist`/`config/oslist`/`osarch` (functions located). Launched with `posix_spawn` and `setbinpref`. **The complete CCompatManager (Steam Play) is compiled into the Mac client**, including `compatibilitytools.d`. | Medium | [03](03-platform-and-launch.md) |

## Impact on the plan

1. **Milestone 5: the design holds (in-process) and gets simpler.** The dylib loader already exists in
   Proton. The real work is making 2 symbols optional and validating the ABI with `static_assert`.
2. **Milestone 9: radical change, confirmed (see [03 §2.2](03-platform-and-launch.md)).** With steamcmd, Steam
   on macOS registers our tool, installs the Windows depot and launches it with `waitforexitandrun` and the
   `STEAM_COMPAT_*` variables, by flipping a single boolean at runtime. Original wording of the hypothesis:
   if CCompatManager can be enabled on macOS with a tool in
   `~/Library/Application Support/Steam/compatibilitytools.d/`, Steam would launch our `proton` without hooks
   or a re-signed copy. Before investing in `steam-hook/`, run the experiment in
   [03 §2](03-platform-and-launch.md#2-steam-play-ccompatmanager-is-compiled-into-the-mac-client): it is cheap,
   reversible and does not touch binaries. It requires restarting Steam.
3. New, unverified risk: `steamclient.dylib` links AppKit/Carbon and could interfere with winemac.drv's
   `NSApplication` when loaded inside the Wine process.

## Later validation (milestone 5, 2026-10-11)

Conclusions (a)/(b) were confirmed end to end: a Windows `.exe` under our Wine loads `lsteamclient.so`, which
`dlopen`s the x86_64 `steamclient.dylib` of the running client. `CreateInterface`, pipe/user, `BLoggedOn`,
`GetAppID`, `GetPersonaName`, `RequestCurrentStats`, `SetAchievement` and `StoreStats` work with their
callbacks. No helper process with IPC was needed.

## Environment status (`scripts/doctor.sh`)

Critical checks green. Pending warnings that cannot be automated:

- **Wine's x86_64 dependencies**: Homebrew no longer supports x86_64 on macOS (the installer refuses to run
  under Rosetta: "Homebrew on macOS is only supported on Apple Silicon processors!"). Decision: build them
  from source with `scripts/build-deps.sh` into `~/.local/opt/proton-macos-deps/x86_64`, without `sudo` and
  reproducible in CI. Milestone 2.
- **GPTK/D3DMetal**: downloaded with an Apple ID from developer.apple.com. Needed in milestone 3.

Installed during milestone 0, in user space: llvm-mingw 20261006 (`~/.local/opt/llvm-mingw`), OpenJDK 21
(brew), Ghidra 12.1.4 (`~/.local/opt/ghidra_12.1.4_PUBLIC`) and REA 6.4.0 (MCP + skill).
