# (b) Steamworks interfaces: steamclient.dylib versus lsteamclient

Proton reference: tag `proton-11.0-2` (`lsteamclient/`, newest SDK `steamworks_sdk_165`).

## Symbols lsteamclient loads

`lsteamclient/unixlib.cpp`, `steamclient_init()`. **It already has an `#ifdef __APPLE__` branch** that loads
`$STEAM_COMPAT_CLIENT_INSTALL_PATH/steamclient.dylib` (with `DYLD_*` as a fallback). It then resolves with
`LOAD_FUNC` (all mandatory: if any fails, initialisation returns -1):

| Symbol | x86_64 | arm64 |
|---|---|---|
| `CreateInterface` | ✅ | ✅ |
| `Steam_BGetCallback` | ✅ | ✅ |
| `Steam_GetAPICallResult` | ✅ | ✅ |
| `Steam_FreeLastCallback` | ✅ | ✅ |
| `Steam_ReleaseThreadLocalMemory` | ✅ | ✅ |
| `Steam_IsKnownInterface` | ❌ **not exported** | ❌ |
| `Steam_NotifyMissingInterface` | ❌ **not exported** | ❌ |

```
$ nm -arch x86_64 -gU steamclient.dylib | wc -l      # 38 exports in total
$ nm -arch x86_64 -gU steamclient.dylib | grep -E "IsKnownInterface|NotifyMissingInterface"
(empty)
$ strings -a -arch x86_64 steamclient.dylib | grep NotifyMissingInterface
NotifyMissingInterface   # only exists as an internal or IPC name, not as an export
```

**Consequence:** unchanged, lsteamclient on macOS fails in `steamclient_init` with
`unable to load Steam_IsKnownInterface`. Fix planned for milestone 5: make those two symbols optional. If
`IsKnownInterface` is missing, return `true` and let `CreateInterface` decide. If `NotifyMissingInterface` is
missing, do nothing. A small, isolated patch.

## Interface versions

The version strings were extracted from the dylib (`strings`) and compared with Proton's
`cppISteam*_<VERSION>.cpp` files (212 versions).

- **SteamClient:** the dylib contains `SteamClient006` to `SteamClient023`. Proton wraps 006–021 and 023 (022
  was never published in the SDK). It covers everything a game will ask for.
- **In Proton but not in the dylib:** only `SteamNetworkingFakeUDPPort001`. This interface is not requested by
  name from `CreateInterface`; `ISteamNetworkingSockets::CreateFakeUDPPort` returns it. Not a problem. Other
  versions that looked missing (`SteamBilling002`, `STEAMCONTROLLER_INTERFACE_VERSION`,
  `SteamNetworkingSocketsSerialized00x`…) are present: checked with an exact search.
- **In the dylib but not in Proton:** internal or old versions (`SteamClient022`, `SteamUtils001/003`,
  `STEAMVIDEO_INTERFACE_V003–006`, `STEAMTIMELINE_INTERFACE_V002/3`…). Irrelevant: lsteamclient only
  translates what games ask for.

## ABI: does macOS x86_64 behave like Linux x86_64?

- `steamworks_sdk_165/steamclientpublic.h`: `#if defined(__linux__) || defined(__APPLE__) || defined(__FreeBSD__)`
  defines `VALVE_CALLBACK_PACK_SMALL`, i.e. `#pragma pack(4)`. Windows uses `PACK_LARGE` (8).
  **macOS uses the same packing as Linux.**
- macOS x86_64 and Linux x86_64 use the same SysV AMD64 calling convention and the same LP64 model, so struct
  layout, `bool`, `wchar_t` (4 bytes) and argument passing match.
- `gen_wrapper.py` generates the `u64` ABI by parsing the headers with libclang on a Linux host
  (`-I/usr/include/x86_64-linux-gnu/`). The generated code can be reused as is. Regenerating it on macOS would
  only be needed if differences appeared, and none are expected.
- macOS has no 32-bit processes. 32-bit games go through WoW64 (`wow64_*` structs towards the 64-bit unix
  side), which Proton already implements.

| Conclusion | Confidence |
|---|---|
| The interfaces games need are available in the dylib. | High |
| The `Steam_IsKnownInterface` and `Steam_NotifyMissingInterface` exports are missing; lsteamclient needs a patch. | High (patched in milestone 5) |
| The macOS u64 ABI is identical to Linux's: the generated thunks work with no new cases. | High (confirmed end to end in milestone 5) |
| The calling convention of virtual methods (Itanium C++ ABI) is the same with clang/macOS and gcc/Linux. | High |
