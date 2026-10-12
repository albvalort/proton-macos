# Proton-macOS

Port of Proton (Wine + lsteamclient + the `proton` script) to Apple Silicon macOS, to run Windows
games from Steam. Working name; it does not imply endorsement by Valve.

## Architecture

```
Game .exe (Windows x86_64)
  └─ Valve's Wine (fork, macos branch) — x86_64 under Rosetta 2, winemac.drv, new WoW64
       ├─ Graphics: D3DMetal (from the user's GPTK) | DXVK→MoltenVK | wined3d   (PROTON_MAC_GFX)
       ├─ Sync: msync (XNU ulocks)                                               (PROTON_NO_MSYNC=1)
       └─ lsteamclient (PE side + unix side) → steamclient.dylib of the running Steam client
  └─ `proton` script (Python, fork) — same contract as on Linux
pmac (launcher/, Rust): QR login, library, Windows depots, Steam shortcuts
steam-hook/ (experimental, opt-in): Steam Play inside the Steam client
```

## Repository layout

- `scripts/` — `doctor.sh`, `build-deps.sh`, `build-macos.sh`, `build-proton-modules.sh`, `package.sh`,
  `steamcmd.sh`, `bench.sh`
- `external/proton`, `external/wine` — submodules (forks, `macos` branch)
- `launcher/` — `pmac`, in Rust
- `steam-hook/` — experimental
- `compat/<appid>.yaml` — compatibility database
- `tools/` — debugging tools (see `tools/README.md`)
- `docs/research/` — reverse-engineering findings (with evidence and confidence level)
- `docs/patches/` — one file per component: every patch, why, and where it comes from
- `docs/adr/` — architecture decisions (`NNNN-title.md`)
- `docs/bench/` — performance results
- `docs/STATUS.md` — status per milestone

## Environment facts (verified)

- macOS 27 on arm64. Wine runs as x86_64 under Rosetta 2.
- **`/Applications/Steam.app` is only the bootstrapper.** The real client lives in
  `~/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/`
  (`steamclient.dylib`, `steam_osx`, etc.). Always use that path.
- `steamclient.dylib` is universal (`x86_64 arm64`): it can be loaded in-process from x86_64 Wine.
- User-space toolchains: `~/.local/opt/llvm-mingw` (PE), `~/.local/opt/ghidra_*` (analysis).
- Homebrew no longer supports x86_64: Wine's x86_64 unix dependencies are built with
  `scripts/build-deps.sh` into `~/.local/opt/proton-macos-deps/x86_64`. Never link Wine against the
  arm64 Homebrew in `/opt/homebrew`.
- **The macOS 27 Command Line Tools are arm64 only** (clang, make, ld and also `libxcrun`): no
  `arch -x86_64` for building. Everything is cross-compiled from arm64 (`clang -arch x86_64`,
  `--build=aarch64-apple-darwin --host=x86_64-apple-darwin`). Wine uses its native arm64 tools through
  `--with-wine-tools` (see `scripts/build-macos.sh`).
- `steam_osx` has no hardened runtime; `/Applications/Steam.app` does. Steam Play is compiled into the
  Mac client and a single check disables it (`docs/research/03-platform-and-launch.md`).
- SIP strips `DYLD_*` variables when executing protected system binaries (`/usr/bin/nohup`, `/bin/sh`,
  …): never launch something that needs `DYLD_INSERT_LIBRARIES` through them.
- steamcmd lives in `~/.local/opt/steamcmd`. **Always use it through `scripts/steamcmd.sh`**, which gives
  it its own HOME (`~/.local/share/proton-macos/steamcmd-home`). If it shares
  `~/Library/Application Support/Steam` with the Steam GUI, each client overwrites the other's session
  token (`config.vdf` → `ConnectCache`). Do not restart the Steam GUI for tests: use steamcmd.
- REA (MCP + `npx rea-agents` CLI) for binary reverse engineering.

## Rules

1. **Never redistribute anything from Apple** (GPTK, D3DMetal, MetalFX). Only detect the user's
   installation and reference it. Not in the repo, not in packages, not in CI. Note: the GPTK license
   limits its use to evaluating ports; document it and never make D3DMetal mandatory.
2. **Never modify the original Steam.app or the installed Steam.AppBundle.** Static, read-only
   analysis only. Any patch goes on a re-signed copy (milestone 9 only). Use a secondary Steam account
   for tests.
3. **Proton/Wine changes isolated and documented** in `docs/patches/` so rebasing on upstream stays
   trivial. Prefer new files and `if darwin` branches over rewrites.
4. **Third-party code**: only with a compatible license (LGPL for Wine, BSD-3 for ours). Record the
   origin in the patch and in `NOTICE`. Do not copy blindly from CrossOver/Gcenx: understand and cite.
5. **Research findings** always come with reproducible evidence (command + output) and a confidence
   level (high/medium/low).
6. **Same contract as Proton on Linux**: `proton run`, `proton waitforexitandrun`, `PROTON_*` variables,
   `toolmanifest.vdf`, `user_settings.py`.
7. Before moving to the next milestone, meet its definition of done and update `docs/STATUS.md`.
8. Never handle Steam passwords: QR login only.

## Language

Everything is in English: docs, commit messages, code comments and upstream-facing messages.

## Commands

- `scripts/doctor.sh [--ci]` — checks the environment (non-zero exit if something critical is missing)
- `scripts/build-deps.sh` — Wine's x86_64 unix dependencies (freetype…) into `~/.local/opt/proton-macos-deps/x86_64`
- `scripts/build-macos.sh [prepare|tools|wine|rebuild|all]` — Wine in `build/`, installed into `dist/wine`
- `scripts/build-proton-modules.sh` — lsteamclient and steam.exe
- `scripts/package.sh [--install]` — Steam compatibility tool in `dist/proton-macos` (and `pmac`)
