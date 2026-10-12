# Status

| Milestone | Description | Status |
|---|---|---|
| 0 | Environment and blocker research | ✅ Done. `doctor.sh` with no critical failures; (a), (b) and (c) answered with evidence ([findings](research/00-findings.md)) |
| 1 | Repository skeleton, forks and CI | ✅ Done. Forks `albvalort/Proton` and `albvalort/wine` (`macos` branch), clone with submodules verified, CI green |
| 2 | Valve's Wine building on macOS | ✅ Builds (cross-compiled arm64→x86_64) with the patches in [patches/wine.md](patches/wine.md). `wine cmd` works; `notepad` and `winecfg` open native windows |
| 3 | Graphics: D3DMetal with DXVK fallback | ✅ `PROTON_MAC_GFX` = dxvk (default, DXVK-macOS on MoltenVK), d3dmetal (the user's GPTK, integration ported from CrossOver) or wined3d. Downwell (DX11) and ANIMAL WELL (DX12, with vkd3d and with D3DMetal) at 60 fps ([bench](bench/graphics.md)). KosmicKrisp ruled out for now: arm64 only ([ADR 0004](adr/0004-graphics-backends.md)) |
| 4 | msync | 🟡 Implemented as fsync on top of XNU ulocks ([ADR 0003](adr/0003-msync.md)): ping-pong 3.9×, mutex 5.7×, cross-process 3.4× ([bench](bench/msync.md)). Enabled by default (`PROTON_NO_MSYNC=1` disables it). Pending: a 30-minute game session |
| 5 | lsteamclient → steamclient.dylib bridge | ✅ Done. `tests/steam-bridge/steamtest.exe` (Wine on macOS) connects to the running Steam, reads the user and AppID and unlocks Spacewar's `ACH_WIN_ONE_GAME`; the public profile shows "1 of 5". Patches in [patches/proton.md](patches/proton.md) |
| 6 | `proton` script for macOS | ✅ Done. `proton run`/`waitforexitandrun` behave as on Linux. Steam (steamcmd with Steam Play enabled) installs Minimalism (Windows depot) and launches it through `proton_macos`; the game (PE32, D3D9→wined3d→OpenGL) runs fullscreen. `steamtest.exe` goes through `proton run` and talks to Steam |
| 7 | Launcher and depot downloads | ✅ `pmac` (Rust): `login` (QR), `list` (library from Steam's caches, no login), `info`, `install` (DepotDownloader), `run` (Steam Play contract + `compat/<appid>.yaml`), `shortcut` (shortcuts.vdf + official artwork). Downwell launches with "Play" from the Steam library on Mac; Lingo was installed with `pmac login` + `pmac install` and is playable. [ADR 0005](adr/0005-launcher.md) |
| 8 | Performance | ⏳ |
| 9 | Integration into the Steam client | 🔬 Validated with steamcmd ([ADR 0002](adr/0002-steam-play-integration.md)). The Steam GUI is arm64 and loads the library exporting `V_strnicmp` with `dlopen`, so the dyld-interposing shim used with steamcmd does not apply there; not working yet |
| 10 | Publish | ⏳ |

## Test environment

- M2, macOS 27.0.1, Steam for Mac 6.1 (build 1788652215), steamcmd 1788292693.
- Windows-only test game: Minimalism (585690), 9 MB, PE32. DX11 candidate with achievements: ANIMAL WELL (813230).
  OpenGL (Godot 3) with first-person mouse look: Lingo (1814170).
